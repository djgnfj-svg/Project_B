extends CanvasLayer
# 창고 패널 (개인·로컬 보관함) — 마을 창고 상호작용이 F로 여는 오버레이.
# craft_panel/inventory_panel 모달 패턴을 복제(rules §5·verify §2-1):
#  - 루트 = CanvasLayer, 기본 visible=false. 닫히면 완전히 숨겨 뒤 게임 클릭을 안 막는다.
#  - Backdrop(ColorRect, mouse_filter=STOP)이 열려 있는 동안만 뒤 게임 클릭을 막는다(마우스만 모달).
#  - Center(CenterContainer)는 mouse_filter=IGNORE — 화면을 덮지만 클릭을 안 먹는다(rules §5 1번 함정).
#
# ⚠ 게임을 멈추지 않는다(멀티) — pause·Engine.time_scale 금지. F/Esc만 이 패널이 소비해 닫는다.
# 창고는 각 클라 로컬(비네트워크, 사용자 확정) — GameState deposit/withdraw API로만 조작.
# 이동 방식: 재료 버튼=1개씩 / 드래그=전부, 골드·장비=버튼(전부/그 장비). 드래그&드롭은 storage_drag_row·drop_list.
# ⚠ UI 씬 스크립트라 전역 오토로드(GameState·EventBus·CombatMath) 직접 접근 OK(§5). class_name 안 함(§0).

const DragRow := preload("res://src/ui/storage_drag_row.gd")
const ItemUi := preload("res://src/ui/item_ui.gd")
const UiTheme := preload("res://src/ui/ui_theme.gd")

signal closed

# 열린 프레임에 온 interact(F)가 곧바로 close로 튀는 걸 막는 1프레임 가드 (craft_panel과 동일).
var _ignore_toggle: bool = false

@onready var _close_btn: Button = %CloseBtn
@onready var _bag_list: VBoxContainer = %BagList
@onready var _store_list: VBoxContainer = %StoreList
@onready var _bag_gold: Label = %BagGold
@onready var _store_gold: Label = %StoreGold
@onready var _bag_gold_btn: Button = %BagGoldBtn
@onready var _store_gold_btn: Button = %StoreGoldWithdraw


func _ready() -> void:
	visible = false
	$Center.theme = UiTheme.get_theme()  # 공용 픽셀 테마 (인벤/제작과 통일)
	_close_btn.pressed.connect(close)
	_bag_gold_btn.pressed.connect(_on_bag_gold)
	_store_gold_btn.pressed.connect(_on_store_gold)
	_bag_list.dropped.connect(_on_dropped)
	_store_list.dropped.connect(_on_dropped)
	# 넣기/빼기·픽업으로 인벤이 바뀌면(inventory_changed) 열려 있는 동안 즉시 반영.
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


# F(interact)/Esc(ui_cancel)로 닫기. ⚠ 닫힌 invisible CanvasLayer도 _unhandled_input을 받으므로
# 반드시 visible 가드 (rules §5) — 안 그러면 닫힌 패널이 창고의 F를 삼킨다.
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
	# 골드
	_bag_gold.text = "골드 %d" % GameState.gold
	_store_gold.text = "골드 %d" % GameState.storage_gold
	_bag_gold_btn.disabled = GameState.gold <= 0
	_store_gold_btn.disabled = GameState.storage_gold <= 0
	# 목록 (가방 / 창고)
	_fill_list(_bag_list, "bag")
	_fill_list(_store_list, "storage")


# 한쪽 열 목록 재구성 — 재료(qty>0) + 장비. 각 행은 드래그 소스(DragRow) + 이동 버튼.
func _fill_list(list: VBoxContainer, zone: String) -> void:
	for c: Node in list.get_children():
		c.queue_free()
	var mats: Dictionary = GameState.materials if zone == "bag" else GameState.storage_materials
	var equips: Dictionary = GameState.owned_equipment if zone == "bag" else GameState.storage_equipment
	var shown := 0
	for mid: String in mats:
		var qty := int(mats[mid])
		if qty <= 0:
			continue
		list.add_child(_make_mat_row(mid, qty, zone))
		shown += 1
	for eid: String in equips:
		list.add_child(_make_equip_row(eid, int(equips[eid]), zone))
		shown += 1
	if shown == 0:
		var empty := Label.new()
		empty.text = "비어 있음"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_color_override(&"font_color", Color(0.6, 0.6, 0.6))
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 빈 열에 첫 드롭이 라벨에 막히지 않게 (리스트가 수신)
		list.add_child(empty)


func _make_mat_row(mid: String, qty: int, zone: String) -> HBoxContainer:
	var mdef := GameState.material_def(mid)
	var tex: Texture2D = mdef.icon if mdef != null else null
	var row: HBoxContainer = DragRow.new()
	row.add_theme_constant_override(&"separation", 6)
	row.payload = {"kind": "material", "id": mid, "zone": zone, "tex": tex}
	row.tooltip_text = ItemUi.material_tooltip(mdef, qty) if mdef != null else mid
	# 창고 열(오른쪽)은 버튼을 왼쪽에, 가방 열(왼쪽)은 버튼을 오른쪽에 — 두 열 사이를 향하게.
	if zone == "storage":
		row.add_child(_move_btn("◀", _on_mat_move.bind(mid, zone)))
	row.add_child(ItemUi.make_icon(tex))
	var name_lbl := Label.new()
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 라벨은 행(드래그)에 이벤트를 넘긴다
	name_lbl.text = "%s x%d" % [mdef.display_name if mdef != null else mid, qty]
	row.add_child(name_lbl)
	if zone == "bag":
		row.add_child(_move_btn("▶", _on_mat_move.bind(mid, zone)))
	return row


func _make_equip_row(eid: String, level: int, zone: String) -> HBoxContainer:
	var equip := GameState.equip_def(eid)
	var tex: Texture2D = equip.icon if equip != null else null
	var row: HBoxContainer = DragRow.new()
	row.add_theme_constant_override(&"separation", 6)
	row.payload = {"kind": "equipment", "id": eid, "zone": zone, "tex": tex}
	if equip != null:
		var s := CombatMath.equip_stat_at_level(equip, level)
		row.tooltip_text = ItemUi.equip_tooltip(equip, level, int(s["attack"]), int(s["hp"]))
	if zone == "storage":
		row.add_child(_move_btn("◀", _on_equip_move.bind(eid, zone)))
	row.add_child(ItemUi.make_icon(tex))
	var name_lbl := Label.new()
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.text = "%s Lv.%d" % [equip.display_name if equip != null else eid, level]
	row.add_child(name_lbl)
	if zone == "bag":
		row.add_child(_move_btn("▶", _on_equip_move.bind(eid, zone)))
	return row


func _move_btn(label: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(28, 0)
	b.pressed.connect(cb)
	return b


# --- 이동 조작 (전부 로컬 GameState — 네트워크 0개) ---

# 재료 버튼: 한 번에 1개씩 (세밀 조절)
func _on_mat_move(mid: String, from_zone: String) -> void:
	if from_zone == "bag":
		GameState.deposit_material(mid, 1)
	else:
		GameState.withdraw_material(mid, 1)
	_commit_save()


# 장비 버튼: 그 장비를 통째로 이동
func _on_equip_move(eid: String, from_zone: String) -> void:
	if from_zone == "bag":
		GameState.deposit_equipment(eid)
	else:
		GameState.withdraw_equipment(eid)
	_commit_save()


func _on_bag_gold() -> void:
	GameState.deposit_gold(GameState.gold)  # 골드 전부 보관
	_commit_save()


func _on_store_gold() -> void:
	GameState.withdraw_gold(GameState.storage_gold)  # 골드 전부 꺼내기
	_commit_save()


# 드래그&드롭: 반대쪽 열에 놓으면 그 아이템을 전부 이동. target_zone = 놓인 쪽.
func _on_dropped(target_zone: String, payload: Dictionary) -> void:
	var kind := str(payload.get("kind", ""))
	var id := str(payload.get("id", ""))
	if target_zone == "storage":  # 가방 → 창고 (예치)
		match kind:
			"material":
				GameState.deposit_material(id, GameState.material_count(id))
			"equipment":
				GameState.deposit_equipment(id)
	else:  # 창고 → 가방 (회수)
		match kind:
			"material":
				GameState.withdraw_material(id, GameState.storage_material_count(id))
			"equipment":
				GameState.withdraw_equipment(id)
	_commit_save()


func _commit_save() -> void:
	# SaveManager는 오토로드지만 -s 테스트/특수 컨텍스트 대비 null-safe로 접근 (다른 패널과 동일).
	var sm := get_node_or_null("/root/SaveManager")
	if sm != null:
		sm.commit()
