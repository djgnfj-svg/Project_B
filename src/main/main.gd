extends Node2D
# 조합 루트 — 로비 ↔ 테스트 스테이지 전환 (rules §2 src/main).
# 씬 전환 판단은 여기서만 한다. 스테이지/로비는 자기 일만 하고 EventBus로 알린다.

const LobbyScene := preload("res://src/ui/lobby.tscn")
const StageScene := preload("res://src/stage/test_stage.tscn")

var _current: Node = null


func _ready() -> void:
	print("Project_B boot OK")
	EventBus.room_created.connect(func(_code: String) -> void: _to_stage())
	EventBus.room_joined.connect(func(_code: String, _peers: Array[int]) -> void: _to_stage())
	EventBus.room_closed.connect(_to_lobby)
	EventBus.net_disconnected.connect(_to_lobby)
	_to_lobby()


func _to_lobby() -> void:
	_swap(LobbyScene.instantiate())


func _to_stage() -> void:
	_swap(StageScene.instantiate())


func _swap(next: Node) -> void:
	if _current != null:
		_current.queue_free()
	_current = next
	add_child(next)
