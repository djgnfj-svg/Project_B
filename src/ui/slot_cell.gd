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
	_qty_lbl.text = "x%d" % qty
	_qty_lbl.visible = qty > 1
	_badge_lbl.text = badge
	_badge_lbl.visible = not badge.is_empty()
	_slot_lbl.visible = false
	tooltip_text = tip
	_restyle()


# 빈 셀. slot_name이 있으면 장비 doll 빈 슬롯(무기/방어구), 없으면 그냥 빈 칸(그리드 패딩).
func set_empty(slot_name: String = "") -> void:
	payload = {}
	_draggable = false
	_filled = false
	_equipped = false
	_icon.texture = null
	_qty_lbl.visible = false
	_badge_lbl.visible = false
	_slot_lbl.text = slot_name
	_slot_lbl.visible = not slot_name.is_empty()
	tooltip_text = ""
	_restyle()


func _restyle() -> void:
	if _equipped:
		add_theme_stylebox_override("panel", UiTheme.equipped_slot_box())
	else:
		add_theme_stylebox_override("panel", UiTheme.slot_box(_border, _filled, _hover))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and not payload.is_empty():
			activated.emit(payload)


func _get_drag_data(_pos: Vector2) -> Variant:
	if not _draggable or payload.is_empty():
		return null
	set_drag_preview(ItemUi.make_drag_preview(payload.get("tex") as Texture2D, 26.0))
	return payload


func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	var parent := get_parent()
	return parent != null and parent.has_method("accepts") and parent.accepts(data)


func _drop_data(_pos: Vector2, data: Variant) -> void:
	var parent := get_parent()
	if parent != null and parent.has_method("receive_drop"):
		parent.receive_drop(data)
