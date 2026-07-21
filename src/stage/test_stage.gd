extends Node2D
# 멀티 스파이크용 테스트 스테이지 — 피어당 플레이어 스폰 + 적 HP 호스트 권한 처리 (rules §1·§3).
# 데미지 확정은 호스트만: 로컬 적중(호스트) → 즉시 확정, 게스트 적중 → hit_req → 호스트 사거리 검증 후 확정.

const NetSchema := preload("res://src/core/net_schema.gd")
const PlayerScene := preload("res://src/player/player.tscn")
const PlayerActor := preload("res://src/player/player.gd")
const EnemyActor := preload("res://src/enemies/enemy.gd")

const SPAWN_BASE := Vector2(280.0, 180.0)
const SPAWN_GAP := 80.0  # 피어별 가로 간격 (연출값)

var _players: Dictionary = {}  # peer_id -> PlayerActor
var _enemies: Dictionary = {}  # eid -> EnemyActor
var _last_hit_msec: Dictionary = {}  # peer_id -> 마지막 스윙 앵커 msec (호스트 전용 — 연사 스팸 게이트)


func _ready() -> void:
	EventBus.peer_joined.connect(_on_peer_joined)
	EventBus.peer_left.connect(_on_peer_left)
	EventBus.net_msg.connect(_on_net_msg)
	EventBus.attack_hit.connect(_on_attack_hit)
	EventBus.enemy_hp_confirmed.connect(_on_enemy_hp_confirmed)
	for node: Node in get_tree().get_nodes_in_group("enemy"):
		var e := node as EnemyActor
		if e != null and not e.eid.is_empty():
			_enemies[e.eid] = e
	($HUD/RoomCode as Label).text = "방 %s · %s" % [
		Net.room_code, "호스트" if Net.is_host() else "게스트"]
	_spawn(Net.my_id, true)
	for pid: int in Net.peer_ids:
		_spawn(pid, false)


func _spawn(peer_id: int, is_local: bool) -> void:
	if peer_id == 0 or _players.has(peer_id):
		return
	var p := PlayerScene.instantiate() as PlayerActor
	add_child(p)
	p.setup(peer_id, is_local, SPAWN_BASE + Vector2(SPAWN_GAP * float(peer_id - 1), 0.0))
	_players[peer_id] = p


func _on_peer_joined(peer_id: int) -> void:
	_spawn(peer_id, false)


func _on_peer_left(peer_id: int) -> void:
	if _players.has(peer_id):
		_players[peer_id].queue_free()
		_players.erase(peer_id)


# 로컬 플레이어의 공격이 적에 닿음 (player가 자기 job을 실어 emit) — 확정은 권한 경로로
func _on_attack_hit(enemy: Node, job: JobDef) -> void:
	var e := enemy as EnemyActor
	if e == null:
		return
	if Net.is_host():
		_confirm_damage(e, job, Net.my_id)
	else:
		Net.send_game({NetSchema.KEY_KIND: NetSchema.G_HIT_REQ, "eid": e.eid})


# 호스트 전용 — 데미지 확정 (rules §3 하드 계약: 계산·검증은 CombatMath만 쓴다)
# 쿨다운 게이트: 같은 스윙(SAME_SWING_MS)의 다중 타격은 허용, 스윙 간격은 공격자 job 쿨다운 강제.
func _confirm_damage(e: EnemyActor, job: JobDef, attacker_id: int) -> void:
	var now := Time.get_ticks_msec()
	var last := int(_last_hit_msec.get(attacker_id, -1000000000))
	if not CombatMath.is_hit_cooldown_ok(last, now, job):
		return
	if now - last > CombatMath.SAME_SWING_MS:
		_last_hit_msec[attacker_id] = now  # 새 스윙 앵커 — 매 확정마다 갱신하면 창이 미끄러진다
	e.take_hit(CombatMath.calc_damage(job))


# 호스트 전용 수신 경로 — enemy(take_hit/부활)가 확정한 HP를 전원에 브로드캐스트
func _on_enemy_hp_confirmed(eid: String, hp: int) -> void:
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_ENEMY_HP, "eid": eid, "hp": hp})


func _on_net_msg(from_id: int, data: Dictionary) -> void:
	match str(data.get(NetSchema.KEY_KIND, "")):
		NetSchema.G_POS:
			if not _players.has(from_id):
				_spawn(from_id, false)  # 스폰 경합 대비 (peer_joined보다 pos가 먼저 온 경우)
				if not _players.has(from_id):
					return  # 스폰 거부(peer_id 0 등) — 인덱싱 에러 방지
			_players[from_id].apply_remote_pos(
				Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0))),
				bool(data.get("f", false)))
		NetSchema.G_ATK:
			if _players.has(from_id):
				var dir := Vector2(float(data.get("dx", 1.0)), float(data.get("dy", 0.0)))
				_players[from_id].play_attack_fx(dir.normalized() if dir.length() > 0.001 else Vector2.RIGHT)
		NetSchema.G_HIT_REQ:
			if not Net.is_host():
				return  # 확정 권한은 호스트만 (게스트에게도 릴레이가 도달하지만 무시)
			if not _players.has(from_id):
				return
			var e_req: Variant = _enemies.get(str(data.get("eid", "")))
			if e_req == null:
				return
			var e := e_req as EnemyActor
			var attacker := _players[from_id] as PlayerActor
			# 신뢰 경계(rules §3): 공격자의 job 기준 사거리 검증(표시 좌표는 클램프됨 — player.apply_remote_pos)
			# + _confirm_damage의 쿨다운 게이트. 통과한 것만 확정.
			if CombatMath.is_hit_in_reach(
					attacker.global_position, e.global_position, attacker.job):
				_confirm_damage(e, attacker.job, from_id)
		NetSchema.G_ENEMY_HP:
			if Net.is_host():
				return  # 호스트 상태가 원본
			if from_id != NetSchema.HOST_ID:
				return  # 권한 스푸핑 차단 — HP 확정은 호스트 발신만 신뢰 (from은 릴레이가 찍음)
			var e_hp: Variant = _enemies.get(str(data.get("eid", "")))
			if e_hp != null:
				(e_hp as EnemyActor).set_hp_display(int(data.get("hp", 0)))
