extends Node2D
# 멀티 스파이크용 테스트 스테이지 — 방의 피어당 플레이어 1기 스폰.
# 씬 전환·방 종료 처리는 조합 루트(src/main)가 한다. 여기는 스폰/해제와 위치 수신만.

const NetSchema := preload("res://src/core/net_schema.gd")
const PlayerScene := preload("res://src/player/player.tscn")

const SPAWN_BASE := Vector2(280.0, 180.0)
const SPAWN_GAP := 80.0  # 피어별 가로 간격 (연출값)

var _players: Dictionary = {}  # peer_id -> Node


func _ready() -> void:
	EventBus.peer_joined.connect(_on_peer_joined)
	EventBus.peer_left.connect(_on_peer_left)
	EventBus.net_msg.connect(_on_net_msg)
	_spawn(Net.my_id, true)
	for pid: int in Net.peer_ids:
		_spawn(pid, false)


func _spawn(peer_id: int, is_local: bool) -> void:
	if peer_id == 0 or _players.has(peer_id):
		return
	var p := PlayerScene.instantiate()
	add_child(p)
	p.setup(peer_id, is_local, SPAWN_BASE + Vector2(SPAWN_GAP * float(peer_id - 1), 0.0))
	_players[peer_id] = p


func _on_peer_joined(peer_id: int) -> void:
	_spawn(peer_id, false)


func _on_peer_left(peer_id: int) -> void:
	if _players.has(peer_id):
		_players[peer_id].queue_free()
		_players.erase(peer_id)


func _on_net_msg(from_id: int, data: Dictionary) -> void:
	match str(data.get(NetSchema.KEY_KIND, "")):
		NetSchema.G_POS:
			if not _players.has(from_id):
				_spawn(from_id, false)  # 스폰 경합 대비 (peer_joined보다 pos가 먼저 온 경우)
				if not _players.has(from_id):
					return  # 스폰 거부(peer_id 0 등) — 인덱싱 에러 방지
			_players[from_id].apply_remote_pos(Vector2(
				float(data.get("x", 0.0)), float(data.get("y", 0.0))))
