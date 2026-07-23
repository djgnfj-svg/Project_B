extends VBoxContainer
# 창고 패널의 한쪽 열(가방/창고) 아이템 목록 = 드롭 대상.
# 반대쪽에서 온 아이템을 드롭하면 dropped 시그널로 패널에 알린다(패널이 deposit/withdraw 확정).
# 행(storage_drag_row)도 같은 accepts/receive를 부르므로 행 위/빈칸 어디에 놔도 동작한다.
# class_name 선언 안 함(§0) — 패널이 씬으로 문다.

signal dropped(target_zone: String, payload: Dictionary)

@export var zone: String = ""  # "bag" | "storage" — 이 목록이 속한 쪽


# 다른 쪽(zone이 다름)에서 온 유효 페이로드만 받는다.
func accepts(data: Variant) -> bool:
	return data is Dictionary and str((data as Dictionary).get("zone", "")) != zone


func receive_drop(data: Variant) -> void:
	if accepts(data):
		dropped.emit(zone, data as Dictionary)


func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	return accepts(data)


func _drop_data(_pos: Vector2, data: Variant) -> void:
	receive_drop(data)
