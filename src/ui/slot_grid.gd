extends GridContainer
# 슬롯 그리드 = 드롭 대상 컨테이너 (창고 패널의 가방/창고 한 쪽). 반대쪽에서 온 아이템 드롭을 받는다.
# slot_cell도 같은 accepts/receive_drop를 위임하므로 셀 위/빈칸 어디에 놔도 이동이 성립한다.
# class_name 선언 안 함(§0) — 패널이 씬으로 문다.

signal dropped(target_zone: String, payload: Dictionary)

@export var zone: String = ""  # "bag" | "storage"


func accepts(data: Variant) -> bool:
	return data is Dictionary and str((data as Dictionary).get("zone", "")) != zone


func receive_drop(data: Variant) -> void:
	if accepts(data):
		dropped.emit(zone, data as Dictionary)


func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	return accepts(data)


func _drop_data(_pos: Vector2, data: Variant) -> void:
	receive_drop(data)
