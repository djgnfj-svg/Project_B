extends HBoxContainer
# 창고 패널의 아이템 한 줄 = 드래그 소스 + (부모 목록으로 위임하는) 드롭 대상.
# 드래그로 아이템을 반대쪽 열에 옮긴다(전부 이동). 버튼(1개/장비)은 자식으로 따로 배선한다.
# 드롭은 부모 목록(storage_drop_list)의 accepts/receive로 위임 — 행 위에 놔도 이동이 성립한다.
# class_name 선언 안 함(§0). ItemUi 헬퍼로 드래그 프리뷰를 만든다.

const ItemUi := preload("res://src/ui/item_ui.gd")

var payload: Dictionary = {}  # {kind, id, zone, tex} — 이 행이 표현하는 아이템 (드래그 시 넘김)


func _get_drag_data(_pos: Vector2) -> Variant:
	if payload.is_empty():
		return null
	var tex := payload.get("tex") as Texture2D
	set_drag_preview(ItemUi.make_drag_preview(tex))
	return payload


func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	var parent := get_parent()
	return parent != null and parent.has_method("accepts") and parent.accepts(data)


func _drop_data(_pos: Vector2, data: Variant) -> void:
	var parent := get_parent()
	if parent != null and parent.has_method("receive_drop"):
		parent.receive_drop(data)
