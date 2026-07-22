extends Node
# 전투 확정 공용 컴포넌트 — 전투가 있는 씬(스테이지)이 PeerSync와 함께 자식 노드로 문다.
# 데미지 확정은 호스트만 (rules §1·§3): 로컬 적중(호스트) → 즉시 확정,
# 게스트 적중 → hit_req → 호스트 사거리+쿨다운 검증 후 확정 → ehp 브로드캐스트.
# 플레이어 피격도 동일 — 잔몹 타격(mob_strike)을 호스트가 판정·확정 → php 브로드캐스트.
# i-frame: 구르기 선언(G_ROLL)을 쿨다운 검증 후 그랜트 — 스팸해도 정직한 구르기 이상을 못 얻는다.
# 데스 룰(GDD §5): 클리어 = 비부활 적 전멸(1기 이상) → 사망자 HP1 부활, 전멸 = 생존 0 → 마을 귀환.
# 적은 바디 타입 무관 — 그룹 "enemy" + eid 프로퍼티 + Health 자식(health_component)만 요구한다.
# ⚠ 씬 전용 글루(오토로드 전역 식별자 사용) — -s 헤드리스 테스트에서 preload 금지 (rules §5).

const NetSchema := preload("res://src/core/net_schema.gd")
const PlayerActor := preload("res://src/player/player.gd")
const HealthComponent := preload("res://src/combat/health_component.gd")
const PeerSyncNode := preload("res://src/net/peer_sync.gd")
const SceneFlowNode := preload("res://src/net/scene_flow.gd")

const RETURN_DELAY_S := 3.0  # 클리어/전멸 배너 후 마을 귀환 지연 (연출값)

@export var peer_sync_path: NodePath  # 형제 PeerSync — 공격자 조회(net_anchor·job)에 필요
@export var scene_flow_path: NodePath  # 형제 SceneFlow — 클리어/전멸 귀환 지시 (호스트 전용 사용)

var _peer_sync: PeerSyncNode = null
var _scene_flow: SceneFlowNode = null
var _enemies: Dictionary = {}  # eid -> {root: Node2D, health: HealthComponent, def: EnemyDef}
var _last_hit_msec: Dictionary = {}  # peer_id -> 마지막 스윙 앵커 msec (호스트 전용 — 연사 스팸 게이트)
var _roll_grant_msec: Dictionary = {}  # peer_id -> 마지막 구르기 그랜트 msec (호스트 전용 — i-frame 창)
var _stage_over: bool = false  # 클리어↔전멸 상호 배제 + 종료 후 판정 중지


func _ready() -> void:
	_peer_sync = get_node(peer_sync_path) as PeerSyncNode
	if _peer_sync == null:
		push_error("[CombatAuthority] peer_sync_path 미배선 — 전투 확정 불능")
		return
	_scene_flow = get_node_or_null(scene_flow_path) as SceneFlowNode  # 없으면 귀환만 생략
	EventBus.net_msg.connect(_on_net_msg)
	EventBus.attack_hit.connect(_on_attack_hit)
	EventBus.enemy_hp_confirmed.connect(_on_enemy_hp_confirmed)
	EventBus.player_hp_confirmed.connect(_on_player_hp_confirmed)
	EventBus.mob_strike.connect(_on_mob_strike)
	for node: Node in get_tree().get_nodes_in_group("enemy"):
		_register_enemy(node)
	EventBus.peer_left.connect(func(peer_id: int) -> void:
		_last_hit_msec.erase(peer_id)
		_roll_grant_msec.erase(peer_id))


func _register_enemy(node: Node) -> void:
	var root := node as Node2D
	if root == null:
		return
	var eid_v: Variant = root.get("eid")
	if not (eid_v is String) or str(eid_v).is_empty():
		return
	var health := root.get_node_or_null("Health") as HealthComponent
	if health == null:
		push_error("[CombatAuthority] Health 자식 없는 적 — %s" % root.get_path())
		return
	_enemies[str(eid_v)] = {"root": root, "health": health, "def": root.get("def") as EnemyDef}


# 로컬 플레이어의 공격이 적에 닿음 (player가 자기 job을 실어 emit) — 확정은 권한 경로로
func _on_attack_hit(enemy: Node, job: JobDef) -> void:
	var eid_v: Variant = enemy.get("eid")
	if not (eid_v is String):
		return
	var entry_v: Variant = _enemies.get(str(eid_v))
	if entry_v == null:
		return
	if Net.is_host():
		_confirm_damage((entry_v as Dictionary)["health"] as HealthComponent, job, Net.my_id)
	else:
		Net.send_game({NetSchema.KEY_KIND: NetSchema.G_HIT_REQ, "eid": str(eid_v)})


# 호스트 전용 — 데미지 확정 (rules §3 하드 계약: 계산·검증은 CombatMath만 쓴다)
# 쿨다운 게이트: 같은 스윙(SAME_SWING_MS)의 다중 타격은 허용, 스윙 간격은 공격자 job 쿨다운 강제.
func _confirm_damage(health: HealthComponent, job: JobDef, attacker_id: int) -> void:
	var now := Time.get_ticks_msec()
	var last := int(_last_hit_msec.get(attacker_id, -1000000000))
	if not CombatMath.is_hit_cooldown_ok(last, now, job):
		return
	if now - last > CombatMath.SAME_SWING_MS:
		_last_hit_msec[attacker_id] = now  # 새 스윙 앵커 — 매 확정마다 갱신하면 창이 미끄러진다
	health.apply_damage(CombatMath.calc_damage(job))


# 호스트 전용 수신 경로 — Health 권한 경로(apply_damage/부활)가 확정한 HP를 전원에 브로드캐스트
func _on_enemy_hp_confirmed(eid: String, hp: int) -> void:
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_ENEMY_HP, "eid": eid, "hp": hp})
	if hp <= 0:
		_check_clear()


# 호스트 전용 수신 경로 — 플레이어 Health 권한 경로가 확정한 HP를 전원에 브로드캐스트 (+전멸 판정)
# 게스트도 php 반영 시 같은 시그널을 emit하지만 is_host 가드가 재브로드캐스트 루프를 차단한다.
func _on_player_hp_confirmed(peer_id: int, hp: int) -> void:
	if not Net.is_host():
		return
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_PLAYER_HP, "pid": peer_id, "hp": hp})
	if hp <= 0:
		_check_wipe()


# 호스트 전용(잔몹 AI가 호스트에서만 emit) — 타격 판정·확정. 판정 좌표 = net_anchor (rules §3),
# 판정 반경 = def.strike_radius (텔레그래프 표시와 같은 값 — CombatMath.is_strike_hit 단일 소스).
func _on_mob_strike(eid: String, center: Vector2) -> void:
	if not Net.is_host() or _stage_over:
		return
	var entry_v: Variant = _enemies.get(eid)
	if entry_v == null:
		return
	var def := (entry_v as Dictionary)["def"] as EnemyDef
	if def == null:
		return
	for node: Node in get_tree().get_nodes_in_group("player"):
		var p := node as PlayerActor
		if p == null or not p.is_alive():
			continue
		if not CombatMath.is_strike_hit(p.net_anchor(), center, def.strike_radius):
			continue
		if _is_iframe_active(p):
			continue  # 구르기 무적 (GDD §11 확정 2026-07-22)
		(p.get_node("Health") as HealthComponent).apply_damage(def.attack_damage)


# i-frame 조회 — 호스트 자신은 로컬 구르기 상태 직접, 원격은 G_ROLL 그랜트 창 (CombatMath 단일 소스)
func _is_iframe_active(p: PlayerActor) -> bool:
	if p.is_local:
		return p.is_rolling()
	return CombatMath.is_iframe_active(
		int(_roll_grant_msec.get(p.peer_id, -1000000000)), Time.get_ticks_msec())


# 호스트 전용 — 클리어 판정: 비부활 적(1기 이상)이 전멸했는가. 허수아비(respawns)는 조건 제외.
func _check_clear() -> void:
	if _stage_over or not Net.is_host():
		return
	var required := 0
	for eid: String in _enemies:
		var entry := _enemies[eid] as Dictionary
		var def := entry["def"] as EnemyDef
		if def != null and def.respawns:
			continue
		required += 1
		if not (entry["health"] as HealthComponent).is_dead():
			return
	if required == 0:
		return  # 비부활 적 없는 씬 — 입장 즉시 클리어 방지 가드
	_stage_over = true
	# 사망자 HP1 부활 확정 (GDD §5) — php는 player_hp_confirmed 경유로 자동 브로드캐스트
	for node: Node in get_tree().get_nodes_in_group("player"):
		var p := node as PlayerActor
		if p != null and not p.is_alive():
			(p.get_node("Health") as HealthComponent).confirm_hp(1)
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_STAGE_CLEAR})
	EventBus.stage_cleared.emit()
	_return_to_village_later()


# 호스트 전용 — 전멸 판정: 생존 플레이어 0 (솔로 사망 = 전멸 동일, GDD §5)
func _check_wipe() -> void:
	if _stage_over or not Net.is_host():
		return
	for node: Node in get_tree().get_nodes_in_group("player"):
		var p := node as PlayerActor
		if p != null and p.is_alive():
			return
	_stage_over = true
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_WIPE})
	EventBus.stage_wiped.emit()
	_return_to_village_later()


# 마을 귀환은 플레이스홀더 — 챕터 흐름(모닥불→다음 스테이지)이 생기면 이 지점이 갈아끼워진다.
# ⚠ SceneTree 타이머는 씬 해제 후에도 발화한다 — self 멤버를 람다에서 더듬으면 freed 접근이므로
# 로컬 변수로 캡처해 is_instance_valid로 거른다 (끊김→로비 전환 등으로 3초 안에 해제되는 케이스).
func _return_to_village_later() -> void:
	var sf := _scene_flow
	get_tree().create_timer(RETURN_DELAY_S).timeout.connect(func() -> void:
		if is_instance_valid(sf):
			sf.request(NetSchema.SCENE_VILLAGE))


func _on_net_msg(from_id: int, data: Dictionary) -> void:
	match str(data.get(NetSchema.KEY_KIND, "")):
		NetSchema.G_HIT_REQ:
			if not Net.is_host():
				return  # 확정 권한은 호스트만 (게스트에게도 릴레이가 도달하지만 무시)
			var attacker := _peer_sync.player(from_id)
			if attacker == null or not attacker.is_alive():
				return  # 사망(관전 고스트)의 적중 요청 거부 — 사후 적중·고스트 클리어 조작 차단 (rules §3)
			var entry_req: Variant = _enemies.get(str(data.get("eid", "")))
			if entry_req == null:
				return
			var entry := entry_req as Dictionary
			# 신뢰 경계(rules §3): 공격자의 job 기준 사거리 검증 + _confirm_damage의 쿨다운 게이트.
			# 좌표는 net_anchor() — 스푸핑 클램프는 유지하되 표시 보간 지연은 검증에서 제외.
			if CombatMath.is_hit_in_reach(
					attacker.net_anchor(), (entry["root"] as Node2D).global_position, attacker.job):
				_confirm_damage(entry["health"] as HealthComponent, attacker.job, from_id)
		NetSchema.G_ENEMY_HP:
			if Net.is_host():
				return  # 호스트 상태가 원본
			if from_id != NetSchema.HOST_ID:
				return  # 권한 스푸핑 차단 — HP 확정은 호스트 발신만 신뢰 (from은 릴레이가 찍음)
			var entry_hp: Variant = _enemies.get(str(data.get("eid", "")))
			if entry_hp != null:
				((entry_hp as Dictionary)["health"] as HealthComponent).set_hp_display(int(data.get("hp", 0)))
		NetSchema.G_ROLL:
			if not Net.is_host():
				return  # 그랜트 권한은 호스트만
			var roller := _peer_sync.player(from_id)
			if roller == null or not roller.is_alive():
				return  # 사망자의 구르기 선언 무시 (rules §3)
			# 신뢰 경계(rules §3): 쿨다운 검증 통과 시에만 i-frame 창 부여 — 스팸 = 무시.
			# 수용된 한계: 조작 클라가 그랜트 창 중 공격하는 것은 막지 않는다 — naive하게 막으면
			# 정직한 "구르기 직후 공격"이 GRACE+지연 시프트로 오탐 거부된다 (2인 협동이라 실익 낮음).
			var now_roll := Time.get_ticks_msec()
			if CombatMath.is_roll_grant_ok(int(_roll_grant_msec.get(from_id, -1000000000)), now_roll):
				_roll_grant_msec[from_id] = now_roll
		NetSchema.G_PLAYER_HP:
			if Net.is_host() or from_id != NetSchema.HOST_ID:
				return  # 플레이어 HP 확정은 호스트 발신만 신뢰 — 자기 HP도 이것만 믿는다 (rules §3)
			var target := _peer_sync.player(int(data.get("pid", 0)))
			if target != null:
				target.confirm_hp_from_net(int(data.get("hp", 0)))
		NetSchema.G_STAGE_CLEAR:
			if not Net.is_host() and from_id == NetSchema.HOST_ID and not _stage_over:
				_stage_over = true
				EventBus.stage_cleared.emit()  # 부활 자체는 php가 옮긴다 — clear는 흐름/배너만
		NetSchema.G_WIPE:
			if not Net.is_host() and from_id == NetSchema.HOST_ID and not _stage_over:
				_stage_over = true
				EventBus.stage_wiped.emit()
