extends CanvasLayer
# 창고 패널 (개인·로컬 보관함) — 마을 창고 상호작용이 F로 여는 오버레이.
# 언던류 2열 슬롯 그리드(내 가방 | 창고). 이동: 드래그=전부 / 클릭=재료 1개·장비 통째.
# craft/inventory와 공용: ui_theme·slot_cell·slot_grid·item_ui.
#  - 루트 = CanvasLayer, 기본 visible=false. Backdrop(STOP)이 열린 동안만 뒤 클릭 차단, Center(IGNORE).
# ⚠ 게임을 멈추지 않는다(멀티). F/Esc만 소비해 닫는다. 창고는 각 클라 로컬(비네트워크, 사용자 확정).
# ⚠ UI 씬 스크립트라 전역 오토로드 직접 접근 OK(§5). class_name 선언 안 함(§0).

const UiTheme := preload("res://src/ui/ui_theme.gd")
const ItemUi := preload("res://src/ui/item_ui.gd")
const SlotCell := preload("res://src/ui/slot_cell.gd")

const GRID_MIN_CELLS := 24  # 한 쪽 최소 칸(빈 슬롯 패딩) — 그리드 형태 유지

signal closed

# 열린 프레임에 온 interact(F)가 곧바로 close로 튀는 걸 막는 1프레임 가드 (craft_panel과 동일).
var _ignore_toggle: bool = false

@onready var _close_btn: Button = %CloseBtn
@onready var _bag_grid: GridContainer = %BagGrid
@onready var _store_grid: GridContainer = %StoreGrid
@onready var _bag_gold: Label = %BagGold
@onready var _store_gold: Label = %StoreGold
@onready var _bag_gold_btn: Button = %BagGoldBtn
@onready var _store_gold_btn: Button = %StoreGoldBtn


func _ready() -> void:
	visible = false
	$Center.theme = UiTheme.get_theme()
	_close_btn.pressed.connect(close)
	_bag_gold_btn.pressed.connect(_on_bag_gold)
	_store_gold_btn.pressed.connect(_on_store_gold)
	_bag_grid.dropped.connect(_on_dropped)
	_store_grid.dropped.connect(_on_dropped)
	EventBus.inventory_changed.connect(_on_inventory_changed)


# --- 공개 API (창고 상호작용이 부른다) ---

func open() -> void:
	_ignore_toggle = true
	call_deferred("_clear_ignore_toggle")
	_refresh()
	visible = true


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _clear_ignore_toggle() -> void:
	_ignore_toggle = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and not _ignore_toggle:
		close()
		get_viewport().set_input_as_handled()


func _on_inventory_changed() -> void:
	if visible:
		_refresh()


func _refresh() -> void:
	_bag_gold.text = str(GameState.gold)
	_store_gold.text = str(GameState.storage_gold)
	_bag_gold_btn.disabled = GameState.gold <= 0
	_store_gold_btn.disabled = GameState.storage_gold <= 0
	_fill_grid(_bag_grid, "bag")
	_fill_grid(_store_grid, "storage")


# 한쪽 그리드 재구성 — 재료(qty>0) + 장비. 각 셀 = 드래그 소스, 빈 칸 패딩으로 그리드 형태 유지.
func _fill_grid(grid: GridContainer, zone: String) -> void:
	for c: Node in grid.get_children():
		c.queue_free()
	var mats: Dictionary = GameState.materials if zone == "bag" else GameState.storage_materials
	var equips: Dictionary = GameState.owned_equipment if zone == "bag" else GameState.storage_equipment
	var count := 0
	for eid: String in equips:
		grid.add_child(_make_equip_cell(eid, int(equips[eid]), zone))
		count += 1
	for mid: String in mats:
		var qty := int(mats[mid])
		if qty <= 0:
			continue
		grid.add_child(_make_material_cell(mid, qty, zone))
		count += 1
	var target := maxi(GRID_MIN_CELLS, int(ceil(float(count) / grid.columns)) * grid.columns)
	for _i in range(target - count):
		var empty: PanelContainer = SlotCell.new()
		empty.set_empty("")
		grid.add_child(empty)


func _make_equip_cell(eid: String, level: int, zone: String) -> Control:
	var equip := GameState.equip_def(eid)
	var cell: PanelContainer = SlotCell.new()
	cell.activated.connect(_on_slot_activated)
	if equip == null:
		cell.set_empty("")
		return cell
	var s := CombatMath.equip_stat_at_level(equip, level)
	var badge := "+%d" % level if level > 0 else ""
	cell.fill(
		{"kind": "equipment", "id": eid, "zone": zone, "tex": equip.icon},
		equip.icon, 1, badge, UiTheme.EQUIP_BORDER, true, false,
		ItemUi.equip_tooltip(equip, level, int(s["attack"]), int(s["hp"])))
	return cell


func _make_material_cell(mid: String, qty: int, zone: String) -> Control:
	var mdef := GameState.material_def(mid)
	var cell: PanelContainer = SlotCell.new()
	cell.activated.connect(_on_slot_activated)
	var tex: Texture2D = mdef.icon if mdef != null else null
	var border := UiTheme.rarity_color(mdef.rarity) if mdef != null else UiTheme.SLOT_BORDER
	cell.fill(
		{"kind": "material", "id": mid, "zone": zone, "tex": tex},
		tex, qty, "", border, true, false,
		ItemUi.material_tooltip(mdef, qty) if mdef != null else mid)
	return cell


# --- 이동 (전부 로컬 GameState — 네트워크 0개) ---

# 클릭: 재료는 1개, 장비는 통째. zone이 곧 방향(bag→예치 / storage→회수).
func _on_slot_activated(payload: Dictionary) -> void:
	var kind := str(payload.get("kind", ""))
	var id := str(payload.get("id", ""))
	var zone := str(payload.get("zone", ""))
	if zone == "bag":
		if kind == "material":
			GameState.deposit_material(id, 1)
		elif kind == "equipment":
			GameState.deposit_equipment(id)
	else:
		if kind == "material":
			GameState.withdraw_material(id, 1)
		elif kind == "equipment":
			GameState.withdraw_equipment(id)
	_commit_save()


# 드래그&드롭: 반대쪽에 놓으면 전부 이동. target_zone = 놓인 쪽.
func _on_dropped(target_zone: String, payload: Dictionary) -> void:
	var kind := str(payload.get("kind", ""))
	var id := str(payload.get("id", ""))
	if target_zone == "storage":  # 가방 → 창고 (예치)
		if kind == "material":
			GameState.deposit_material(id, GameState.material_count(id))
		elif kind == "equipment":
			GameState.deposit_equipment(id)
	else:  # 창고 → 가방 (회수)
		if kind == "material":
			GameState.withdraw_material(id, GameState.storage_material_count(id))
		elif kind == "equipment":
			GameState.withdraw_equipment(id)
	_commit_save()


func _on_bag_gold() -> void:
	GameState.deposit_gold(GameState.gold)  # 골드 전부 보관
	_commit_save()


func _on_store_gold() -> void:
	GameState.withdraw_gold(GameState.storage_gold)  # 골드 전부 꺼내기
	_commit_save()


func _commit_save() -> void:
	var sm := get_node_or_null("/root/SaveManager")
	if sm != null:
		sm.commit()
