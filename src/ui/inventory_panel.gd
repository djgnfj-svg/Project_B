extends CanvasLayer
# 인벤토리 창 (I키, 어디서나) — 장비 착용 슬롯(무기/방어구) + 총 스탯 + 가방 슬롯 그리드.
# 언던류 슬롯 UI로 재구성(리스트 → 그리드). 장착/해제 = 셀 좌클릭, 상세 = hover 툴팁.
# craft/storage와 공용: ui_theme(테마)·slot_cell(셀)·item_ui(툴팁 텍스트).
#  - 루트 = CanvasLayer, 기본 visible=false. 닫히면 완전히 숨겨 뒤 게임 클릭을 안 막는다.
#  - Backdrop(STOP)이 열린 동안만 뒤 클릭 차단, Center(IGNORE)는 화면 덮되 클릭 안 먹음(rules §5).
# ⚠ 게임을 멈추지 않는다(멀티) — pause 금지. Esc만 소비해 닫고, 여는 I키는 HUD가 소비.
# 인벤은 각 클라 로컬(비네트워크) — GameState API + CombatMath 단일 소스(rules §3)로만.
# ⚠ UI 씬 스크립트라 전역 오토로드 직접 접근 OK(§5). class_name 선언 안 함(§0).

const UiTheme := preload("res://src/ui/ui_theme.gd")
const ItemUi := preload("res://src/ui/item_ui.gd")
const SlotCell := preload("res://src/ui/slot_cell.gd")

const BAG_MIN_CELLS := 24  # 가방 최소 칸(빈 슬롯 패딩) — 4행×6열 그리드 형태 유지

signal closed

@onready var _close_btn: Button = %CloseBtn
@onready var _gold: Label = %Gold
@onready var _equip_row: HBoxContainer = %EquipRow
@onready var _stats: Label = %Stats
@onready var _bag_header: Label = %BagHeader
@onready var _bag_grid: GridContainer = %BagGrid


func _ready() -> void:
	visible = false
	$Center.theme = UiTheme.get_theme()
	_close_btn.pressed.connect(close)
	EventBus.inventory_changed.connect(_on_inventory_changed)


# --- 공개 API (HUD가 I키로 부른다) ---

func open() -> void:
	_refresh()
	visible = true


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _on_inventory_changed() -> void:
	if visible:
		_refresh()


func _refresh() -> void:
	_gold.text = str(GameState.gold)
	_refresh_equip()
	_refresh_stats()
	_refresh_bag()


# --- 장비 착용 슬롯 (무기/방어구 doll) ---

func _refresh_equip() -> void:
	for c: Node in _equip_row.get_children():
		c.queue_free()
	_equip_row.add_child(_make_equip_slot(EquipDef.SLOT_WEAPON, "무기"))
	# 방어구 슬롯은 뺐다(현재 방어구 미도입) — 나중에 방어구가 생기면 여기 SLOT_ARMOR 슬롯을 다시 추가.


func _make_equip_slot(slot: int, slot_name: String) -> Control:
	var cell: PanelContainer = SlotCell.new()
	cell.activated.connect(_on_slot_activated)
	var eid := GameState.equipped_id(slot)
	if eid.is_empty():
		cell.set_empty(slot_name)
		return cell
	var equip := GameState.equip_def(eid)
	if equip == null:
		cell.set_empty(slot_name)
		return cell
	var level := GameState.equip_level(eid)
	var s := CombatMath.equip_stat_at_level(equip, level)
	var badge := "+%d" % level if level > 0 else ""
	cell.fill(
		{"kind": "equipped", "slot": slot, "tex": equip.icon},
		equip.icon, 1, badge, UiTheme.EQUIP_BORDER, false, true,
		ItemUi.equip_tooltip(equip, level, int(s["attack"]), int(s["hp"])) + "\n(클릭: 해제)")
	return cell


func _refresh_stats() -> void:
	var s := GameState.current_stats()
	_stats.text = "총 스탯\n공격  %d\n체력  %d" % [int(s["attack"]), int(s["hp"])]


# --- 가방 슬롯 그리드 (미착용 장비 + 재료) ---

func _refresh_bag() -> void:
	for c: Node in _bag_grid.get_children():
		c.queue_free()
	var count := 0
	# 미착용 보유 장비
	for eid: String in GameState.owned_equipment:
		if _is_equipped(eid):
			continue
		_bag_grid.add_child(_make_equip_cell(eid))
		count += 1
	# 재료
	for mid: String in GameState.materials:
		var qty := int(GameState.materials[mid])
		if qty <= 0:
			continue
		_bag_grid.add_child(_make_material_cell(mid, qty))
		count += 1
	# 빈 칸 패딩 — 그리드 형태 유지 (언던류: 빈 슬롯도 보이게)
	var target := maxi(BAG_MIN_CELLS, int(ceil(float(count) / _bag_grid.columns)) * _bag_grid.columns)
	_bag_header.text = "가방 (%d)" % count
	for _i in range(target - count):
		var empty: PanelContainer = SlotCell.new()
		empty.set_empty("")
		_bag_grid.add_child(empty)


func _make_equip_cell(eid: String) -> Control:
	var equip := GameState.equip_def(eid)
	var cell: PanelContainer = SlotCell.new()
	cell.activated.connect(_on_slot_activated)
	if equip == null:
		cell.set_empty("")
		return cell
	var level := GameState.equip_level(eid)
	var s := CombatMath.equip_stat_at_level(equip, level)
	var badge := "+%d" % level if level > 0 else ""
	cell.fill(
		{"kind": "equipment", "id": eid, "tex": equip.icon},
		equip.icon, 1, badge, UiTheme.EQUIP_BORDER, false, false,
		ItemUi.equip_tooltip(equip, level, int(s["attack"]), int(s["hp"])) + "\n(클릭: 장착)")
	return cell


func _make_material_cell(mid: String, qty: int) -> Control:
	var mdef := GameState.material_def(mid)
	var cell: PanelContainer = SlotCell.new()
	var tex: Texture2D = mdef.icon if mdef != null else null
	var border := UiTheme.rarity_color(mdef.rarity) if mdef != null else UiTheme.SLOT_BORDER
	cell.fill(
		{"kind": "material", "id": mid, "tex": tex},
		tex, qty, "", border, false, false,
		ItemUi.material_tooltip(mdef, qty) if mdef != null else mid)
	return cell


# --- 클릭 처리 (장착/해제) ---

func _on_slot_activated(payload: Dictionary) -> void:
	match str(payload.get("kind", "")):
		"equipment":
			GameState.equip(str(payload["id"]))
			_commit_save()
		"equipped":
			GameState.unequip(int(payload["slot"]))
			_commit_save()
		# material 클릭은 조회만 (액션 없음)


func _is_equipped(eid: String) -> bool:
	# 방어구 슬롯은 현재 미도입 — 무기 슬롯만 확인 (SLOT_ARMOR는 스키마에 dormant 유지)
	return GameState.equipped_id(EquipDef.SLOT_WEAPON) == eid


func _commit_save() -> void:
	var sm := get_node_or_null("/root/SaveManager")
	if sm != null:
		sm.commit()
