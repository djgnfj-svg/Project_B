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
var _peer_jobs: Dictionary = {}  # peer_id -> 잠긴 직업 id — "시작 시 선택·이후 고정"(GDD §5) 강제
var _pos_seen: Dictionary = {}  # peer_id -> true — 첫 G_POS 수신 시 재공지 트리거 (공지 유실 경합 복구)
var _invite_fx_seq: int = 0  # 복사 연타 시 이전 타이머가 새 피드백을 지우지 않게


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
	($HUD/InviteBtn as Button).pressed.connect(_on_invite_pressed)
	_spawn(Net.my_id, true)
	for pid: int in Net.peer_ids:
		_spawn(pid, false)
	_announce_job()


func _spawn(peer_id: int, is_local: bool) -> void:
	if peer_id == 0 or _players.has(peer_id):
		return
	var p := PlayerScene.instantiate() as PlayerActor
	add_child(p)
	p.setup(peer_id, is_local, SPAWN_BASE + Vector2(SPAWN_GAP * float(peer_id - 1), 0.0))
	if is_local:
		p.set_job(GameState.selected_job())  # 원격은 기본(전사)으로 두고 G_JOB 공지로 확정
	_players[peer_id] = p


# 직업 공지 — 내 직업 id를 방 전원에 브로드캐스트.
# 스테이지 입장 시 1회 + 새 피어 합류 시 재공지(늦게 온 피어도 기존 피어 직업을 알게).
func _announce_job() -> void:
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_JOB, "job": GameState.selected_job_id})


# 초대 링크(없으면 방 코드) 클립보드 복사 — URL 구성은 Net.invite_url()이 단일 소스
func _on_invite_pressed() -> void:
	var btn := $HUD/InviteBtn as Button
	var url := Net.invite_url()
	var copied := url if not url.is_empty() else Net.room_code
	DisplayServer.clipboard_set(copied)
	print("[PB] invite copied: %s" % copied)
	btn.text = "복사됨!" if not url.is_empty() else "코드 복사됨 (%s)" % Net.room_code
	_invite_fx_seq += 1
	var seq := _invite_fx_seq
	get_tree().create_timer(1.5).timeout.connect(
		func() -> void:
			if is_instance_valid(btn) and seq == _invite_fx_seq:
				btn.text = "초대 링크 복사")


func _on_peer_joined(peer_id: int) -> void:
	_spawn(peer_id, false)
	_announce_job()


func _on_peer_left(peer_id: int) -> void:
	if _players.has(peer_id):
		_players[peer_id].queue_free()
		_players.erase(peer_id)
	_peer_jobs.erase(peer_id)  # 같은 id로 새 피어가 들어와도 이전 잠금·앵커가 남지 않게
	_pos_seen.erase(peer_id)
	_last_hit_msec.erase(peer_id)


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
			if not _pos_seen.has(from_id):
				# 첫 G_POS = 상대 스테이지가 듣고 있다는 증명 — 스테이지 입장 전 드랍된 공지를 재전송.
				# (peer_joined 시점 공지는 상대 씬 전환 중이면 수신자 없이 유실될 수 있다)
				_pos_seen[from_id] = true
				_announce_job()
		NetSchema.G_JOB:
			if not _players.has(from_id):
				_spawn(from_id, false)  # 공지가 스폰보다 먼저 온 경합 대비 (G_POS와 동일 패턴)
				if not _players.has(from_id):
					return
			if _peer_jobs.has(from_id):
				return  # 첫 공지에서 잠금 — 판 도중 직업 변경(스탯 취사선택 이득)은 무시 (GDD §5)
			# 신뢰 경계(rules §3): id 문자열만 받고 수치는 내 data/jobs에서 리졸브.
			# 모르는 id는 GameState가 기본 직업으로 떨어뜨린다. 이후 사거리·쿨다운 검증이 이 job 기준.
			_peer_jobs[from_id] = str(data.get("job", ""))
			_players[from_id].set_job(GameState.job_def(str(data.get("job", ""))))
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
			# 신뢰 경계(rules §3): 공격자의 job 기준 사거리 검증 + _confirm_damage의 쿨다운 게이트.
			# 좌표는 net_anchor() — 스푸핑 클램프는 유지하되 표시 보간 지연은 검증에서 제외.
			if CombatMath.is_hit_in_reach(
					attacker.net_anchor(), e.global_position, attacker.job):
				_confirm_damage(e, attacker.job, from_id)
		NetSchema.G_ENEMY_HP:
			if Net.is_host():
				return  # 호스트 상태가 원본
			if from_id != NetSchema.HOST_ID:
				return  # 권한 스푸핑 차단 — HP 확정은 호스트 발신만 신뢰 (from은 릴레이가 찍음)
			var e_hp: Variant = _enemies.get(str(data.get("eid", "")))
			if e_hp != null:
				(e_hp as EnemyActor).set_hp_display(int(data.get("hp", 0)))
