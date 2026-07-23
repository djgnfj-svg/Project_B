extends Node2D
# 조합 루트 — 로비 → 마을 ⇄ 스테이지 전환 (rules §2 src/main).
# 씬 전환 판단은 여기서만 한다. 각 씬은 자기 일만 하고 EventBus.scene_change로 알린다.
# 멀티에선 전환을 호스트가 지시(G_SCENE)하고, 수신·검증은 각 씬이 한 뒤 여기로 emit한다.

const NetSchema := preload("res://src/core/net_schema.gd")
const LobbyScene := preload("res://src/ui/lobby.tscn")
const VillageScene := preload("res://src/village/village.tscn")

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
	GameState.leave_chapter()  # 끊김/방 종료 — 이전 판의 챕터 좌표·이월 HP가 남지 않게
	_swap(LobbyScene.instantiate())


func _to_village() -> void:
	GameState.leave_chapter()
	GameState.grant_starting_loadout(GameState.selected_job())  # 새 판이면 시작 무기 지급·착용(멱등)
	_swap(VillageScene.instantiate())


# 씬 id → 씬 매핑 — id는 net_schema SCENE_*가 단일 소스. 모르는 id는 무시(allowlist).
# 스테이지 씬 경로는 GameState(챕터 좌표 — scene_flow 검증을 통과한 값)에서 리졸브한다.
func _on_scene_change(scene_id: String) -> void:
	match scene_id:
		NetSchema.SCENE_VILLAGE:
			GameState.leave_chapter()  # 귀환 = 챕터 종료 (완주·전멸 공통) — 이월 HP 리셋
			GameState.grant_starting_loadout(GameState.selected_job())  # 전멸 롤백으로 잃었으면 재지급(멱등)
			_swap(VillageScene.instantiate())
		NetSchema.SCENE_STAGE:
			var path := GameState.stage_scene_path()
			var ps := load(path) as PackedScene
			if ps == null:
				push_error("[main] 스테이지 씬 로드 실패 '%s' — 마을 폴백" % path)
				GameState.leave_chapter()
				_swap(VillageScene.instantiate())
				return
			_swap(ps.instantiate())
		_:
			push_warning("[main] 모르는 씬 id '%s' — 전환 무시" % scene_id)


func _swap(next: Node) -> void:
	if _current != null:
		_current.queue_free()
	_current = next
	add_child(next)
