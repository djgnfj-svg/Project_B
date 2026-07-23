extends CanvasLayer
# 인벤토리 조회 + 장착 모달 — 스테이지·마을 어디서나 I키로 여는 창.
# craft_panel 모달 패턴을 복제·확장했다(rules §5·verify §2-1):
#  - 루트 = CanvasLayer, 기본 visible=false. 닫히면 완전히 숨겨 뒤 게임 클릭을 안 막는다.
#  - Backdrop(ColorRect, mouse_filter=STOP)이 열려 있는 동안만 뒤 게임 클릭을 막는다(마우스만 모달).
#  - Center(CenterContainer)는 mouse_filter=IGNORE — 화면을 덮지만 클릭을 안 먹는다(rules §5 1번 함정).
#
# ⚠ 게임을 멈추지 않는다(멀티) — pause·Engine.time_scale 금지. 다른 플레이어는 계속 움직인다.
#   마우스만 모달(Backdrop STOP)이고, Esc(ui_cancel)만 이 패널이 소비해 닫는다.
#   여는 I키("inventory" 액션)는 HUD가 담당한다 — 여기서 처리하면 이중 소비된다.
#
# 제작/강화는 여기서 하지 않는다(마을 제작대 craft_panel 담당) — 조회 + 장착만.
# 인벤은 각 클라 로컬(비네트워크) — GameState API + CombatMath 단일 소스(rules §3)로만.
# ⚠ UI 씬 스크립트라 전역 오토로드(GameState·EventBus·CombatMath) 직접 접근 OK
#   (헤드리스 -s 대상 아님, rules §5). class_name 선언은 하지 않는다(서브에이전트 규칙 §0).

const UiTheme := preload("res://src/ui/ui_theme.gd")
const ItemUi := preload("res://src/ui/item_ui.gd")

@onready var _close_btn: Button = %CloseBtn
@onready var _mat_list: VBoxContainer = %MatList
@onready var _equip_list: VBoxContainer = %EquipList

signal closed


func _ready() -> void:
	visible = false
	$Center.theme = UiTheme.get_theme()  # 공용 픽셀 테마 (제작/창고와 통일)
	_close_btn.pressed.connect(close)
	# 픽업/장착으로 인벤이 바뀌면(inventory_changed) 열려 있는 동안 즉시 반영.
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


# Esc(ui_cancel)로 닫기. ⚠ 닫힌 invisible CanvasLayer도 _unhandled_input을 받으므로
# (rules §5) 반드시 visible 가드 — 안 그러면 닫힌 패널이 다른 Esc 소비를 삼킨다.
# "inventory"(여는 I키)는 여기서 처리하지 않는다 — HUD가 열고, 이 패널은 Esc만 닫는다.
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
	_refresh_materials()
	_refresh_equipment()


# --- 재료: 보유 재료(qty>0) 나열 ---

func _refresh_materials() -> void:
	_clear(_mat_list)
	var shown := 0
	for mid: String in GameState.materials:
		var qty := int(GameState.materials[mid])
		if qty <= 0:
			continue
		var mdef := GameState.material_def(mid)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.tooltip_text = ItemUi.material_tooltip(mdef, qty) if mdef != null else mid  # 아이템 상세 hover
		row.add_child(_make_icon(mdef.icon if mdef != null else null))
		var lbl := Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 툴팁은 행이 받게 라벨은 이벤트 통과
		var name_txt := mdef.display_name if mdef != null else mid
		lbl.text = name_txt
		row.add_child(lbl)
		var qty_lbl := Label.new()
		qty_lbl.text = "x%d" % qty
		row.add_child(qty_lbl)
		_mat_list.add_child(row)
		shown += 1
	if shown == 0:
		_mat_list.add_child(_make_empty_label("보유한 재료가 없습니다"))


# --- 장비: 보유 장비 나열 (조회 + 장착) ---

func _refresh_equipment() -> void:
	_clear(_equip_list)
	if GameState.owned_equipment.is_empty():
		_equip_list.add_child(_make_empty_label("보유한 장비가 없습니다"))
		return
	for eid: String in GameState.owned_equipment:
		var equip := GameState.equip_def(eid)
		if equip == null:
			continue
		_equip_list.add_child(_make_equip_row(eid, equip))


func _make_equip_row(eid: String, equip: EquipDef) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_make_icon(equip.icon))

	var level := GameState.equip_level(eid)
	var cur := CombatMath.equip_stat_at_level(equip, level)
	row.tooltip_text = ItemUi.equip_tooltip(equip, level, int(cur["attack"]), int(cur["hp"]))  # 아이템 상세 hover

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 행 툴팁이 이 영역 hover에서도 뜨게 이벤트 통과
	var name_lbl := Label.new()
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.text = "%s  Lv.%d/%d" % [equip.display_name, level, equip.max_level]
	info.add_child(name_lbl)
	var stat_lbl := Label.new()
	stat_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stat_lbl.text = "공격 %d · HP %d" % [int(cur["attack"]), int(cur["hp"])]
	stat_lbl.add_theme_font_size_override("font_size", 10)
	info.add_child(stat_lbl)
	row.add_child(info)

	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(64, 0)
	var equipped := GameState.equipped_id(equip.slot()) == eid
	if equipped:
		btn.text = "장착됨"
		btn.disabled = true
	else:
		btn.text = "장착"
		btn.pressed.connect(_on_equip_pressed.bind(eid))
	row.add_child(btn)
	return row


func _on_equip_pressed(eid: String) -> void:
	GameState.equip(eid)  # equip은 항상 성공(보유 장비) — inventory_changed로 _refresh
	_commit_save()


# --- 헬퍼 (craft_panel과 동일) ---

func _commit_save() -> void:
	# SaveManager는 오토로드지만 -s 테스트/특수 컨텍스트 대비 null-safe로 접근.
	var sm := get_node_or_null("/root/SaveManager")
	if sm != null:
		sm.commit()


func _clear(container: Node) -> void:
	for c: Node in container.get_children():
		c.queue_free()


# 아이콘 TextureRect — 도형 금지(§0)라 스프라이트만. icon이 null일 수 있어 안전 처리(빈 칸 유지).
func _make_icon(tex: Texture2D) -> TextureRect:
	var t := TextureRect.new()
	t.custom_minimum_size = Vector2(16, 16)
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # 픽셀아트 크리스프
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 장식 — 클릭 안 먹음
	if tex != null:
		t.texture = tex
	return t


func _make_empty_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	return l
