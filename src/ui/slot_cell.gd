extends PanelContainer
# 재사용 슬롯 셀 — 아이콘 + 수량/레벨 뱃지 + 등급 테두리 + 클릭/드래그/툴팁. 인벤·창고·장비 doll 공용.
# 언던류 슬롯 그리드의 한 칸. 빈 셀(장비 doll 빈 슬롯 = "무기/방어구" 라벨, 그리드 패딩 = 아무것도 없음)도 표현.
# 드롭은 부모 컨테이너(slot_grid / equip doll)에 위임한다(accepts/receive_drop) — 셀 위/빈칸 어디에 놔도 성립.
# class_name 선언 안 함(§0) — 패널이 const preload로 문다. 오토로드 미참조(순수 표시).

const UiTheme := preload("res://src/ui/ui_theme.gd")
const ItemUi := preload("res://src/ui/item_ui.gd")

signal activated(payload: Dictionary)  # 좌클릭 (장착/해제/이동은 부모 패널이 해석)

const CELL := 34.0

var payload: Dictionary = {}     # {kind, id, zone, tex, ...} — 빈 셀은 {}
var _draggable: bool = false
var _border: Color = UiTheme.SLOT_BORDER
var _filled: bool = false
var _equipped: bool = false
var _hover: bool = false

# ⚠ @onready 대신 _init에서 직접 참조를 잡는다 — 패널이 .new() 직후(트리 추가 전) fill()을 부르므로
#   _ready를 기다리는 @onready면 null 크래시가 난다.
var _icon: TextureRect
var _qty_lbl: Label
var _badge_lbl: Label
var _slot_lbl: Label


func _init() -> void:
	# 씬 없이 코드로 자식 구성 (패널이 .new()로 대량 생성).
	custom_minimum_size = Vector2(CELL, CELL)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var overlay := Control.new()
	overlay.name = "Overlay"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 3; icon.offset_top = 3; icon.offset_right = -3; icon.offset_bottom = -3
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(icon)

	var qty := Label.new()
	qty.name = "Qty"
	qty.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	qty.offset_left = -CELL; qty.offset_top = -14; qty.offset_right = -2; qty.offset_bottom = -1
	qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	qty.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	qty.add_theme_font_size_override("font_size", 9)
	qty.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	qty.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	qty.add_theme_constant_override("outline_size", 3)
	qty.visible = false
	overlay.add_child(qty)

	var badge := Label.new()
	badge.name = "Badge"
	badge.set_anchors_preset(Control.PRESET_TOP_LEFT)
	badge.offset_left = 2; badge.offset_top = 1; badge.offset_right = CELL; badge.offset_bottom = 13
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_font_size_override("font_size", 9)
	badge.add_theme_color_override("font_color", UiTheme.GOLD)
	badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	badge.add_theme_constant_override("outline_size", 3)
	badge.visible = false
	overlay.add_child(badge)

	var slot_name := Label.new()
	slot_name.name = "SlotName"
	slot_name.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_name.add_theme_font_size_override("font_size", 9)
	slot_name.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	slot_name.visible = false
	overlay.add_child(slot_name)

	_icon = icon
	_qty_lbl = qty
	_badge_lbl = badge
	_slot_lbl = slot_name


func _ready() -> void:
	mouse_entered.connect(func() -> void: _hover = true; _restyle())
	mouse_exited.connect(func() -> void: _hover = false; _restyle())
	_restyle()


# 아이템으로 채운다. badge = 레벨/부위 문구(비면 숨김), qty>1이면 수량 뱃지.
func fill(p: Dictionary, tex: Texture2D, qty: int, badge: String, border: Color, draggable: bool, equipped: bool, tip: String) -> void:
	payload = p
	_draggable = draggable
	_border = border
	_filled = true
	_equipped = equipped
	_icon.texture = tex
	_icon.modulate = Color(1, 1, 1, 1)  # 채운 셀은 아이콘 원색 (빈 슬롯 고스트에서 복귀)
	_qty_lbl.text = "x%d" % qty
	_qty_lbl.visible = qty > 1
	_badge_lbl.text = badge
	_badge_lbl.visible = not badge.is_empty()
	_slot_lbl.visible = false
	tooltip_text = tip
	_restyle()


# 빈 셀. placeholder 아이콘이 있으면 흐린 고스트로 표시(빈 장비 슬롯 = 검 실루엣 등),
# 없고 slot_name만 있으면 글자, 둘 다 없으면 그냥 빈 칸(그리드 패딩).
func set_empty(slot_name: String = "", placeholder: Texture2D = null) -> void:
	payload = {}
	_draggable = false
	_filled = false
	_equipped = false
	_qty_lbl.visible = false
	_badge_lbl.visible = false
	if placeholder != null:
		_icon.texture = placeholder
		_icon.modulate = Color(1, 1, 1, 0.55)  # 반투명 픽토그램 — "여기 무기를 장착" 힌트
		_slot_lbl.visible = false
	else:
		_icon.texture = null
		_icon.modulate = Color(1, 1, 1, 1)
		_slot_lbl.text = slot_name
		_slot_lbl.visible = not slot_name.is_empty()
	tooltip_text = ""
	_restyle()


func _restyle() -> void:
	if _equipped:
		add_theme_stylebox_override("panel", UiTheme.equipped_slot_box())
	else:
		add_theme_stylebox_override("panel", UiTheme.slot_box(_border, _filled, _hover))


# 🔴 클릭은 **뗄 때** 발화한다 — 누를 때 emit하면 드래그를 시작해도 클릭 액션이 먼저 터진다.
#   패널들의 클릭 핸들러는 예외 없이 GameState를 바꾸고 _refresh()로 그리드를 통째로 재생성하는데
#   (창고·훈련소 공통), Godot은 마우스가 임계값만큼 **움직인 뒤에야** _get_drag_data를 부르므로
#   그 시점엔 소스 셀이 이미 queue_free돼 **드래그가 통째로 성립하지 않는다**. 증상은 조작마다 다르다:
#   창고 = "끌었는데 재료가 1개만 옮겨짐"(클릭 동작이 대신 실행), 훈련소 = "메인 칸에 놨는데 서브 칸에 들어감".
#   에러는 어디에도 안 난다. 그래서 누름은 기억만 하고, 드래그로 전환되면 그 기억을 지운다.
var _press_armed: bool = false


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT or payload.is_empty():
			return
		if mb.pressed:
			_press_armed = true
		elif _press_armed:
			_press_armed = false
			activated.emit(payload)


func _get_drag_data(_pos: Vector2) -> Variant:
	if not _draggable or payload.is_empty():
		return null
	_press_armed = false  # 드래그로 전환 — 뗄 때 클릭이 겹쳐 터지지 않게 (위 주석)
	set_drag_preview(ItemUi.make_drag_preview(payload.get("tex") as Texture2D, 26.0))
	return payload


func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	var parent := get_parent()
	return parent != null and parent.has_method("accepts") and parent.accepts(data)


func _drop_data(_pos: Vector2, data: Variant) -> void:
	var parent := get_parent()
	if parent != null and parent.has_method("receive_drop"):
		parent.receive_drop(data)
