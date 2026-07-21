extends Node2D
# 조합 루트 — 로비 → 마을 ⇄ 스테이지 전환 (rules §2 src/main).
# 씬 전환 판단은 여기서만 한다. 각 씬은 자기 일만 하고 EventBus.scene_change로 알린다.
# 멀티에선 전환을 호스트가 지시(G_SCENE)하고, 수신·검증은 각 씬이 한 뒤 여기로 emit한다.

const NetSchema := preload("res://src/core/net_schema.gd")
const LobbyScene := preload("res://src/ui/lobby.tscn")
const VillageScene := preload("res://src/village/village.tscn")
const StageScene := preload("res://src/stage/test_stage.tscn")

var _current: Node = null


func _ready() -> void:
	print("Project_B boot OK")
	EventBus.room_created.connect(func(_code: String) -> void: _to_village())
	EventBus.room_joined.connect(func(_code: String, _peers: Array[int]) -> void: _to_village())
	EventBus.room_closed.connect(_to_lobby)
	EventBus.net_disconnected.connect(_to_lobby)
	EventBus.scene_change.connect(_on_scene_change)
	_to_lobby()


func _to_lobby() -> void:
	_swap(LobbyScene.instantiate())


func _to_village() -> void:
	_swap(VillageScene.instantiate())


# 씬 id → PackedScene 매핑 — id는 net_schema SCENE_*가 단일 소스. 모르는 id는 무시(allowlist).
func _on_scene_change(scene_id: String) -> void:
	match scene_id:
		NetSchema.SCENE_VILLAGE:
			_swap(VillageScene.instantiate())
		NetSchema.SCENE_STAGE:
			_swap(StageScene.instantiate())
		_:
			push_warning("[main] 모르는 씬 id '%s' — 전환 무시" % scene_id)


func _swap(next: Node) -> void:
	if _current != null:
		_current.queue_free()
	_current = next
	add_child(next)
