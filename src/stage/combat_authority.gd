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

@export var peer_sync_path: NodePath  # 형제 PeerSync — 공격자 조회(net_anchor·job)에 필요

var _peer_sync: PeerSyncNode = null
var _enemies: Dictionary = {}  # eid -> {root: Node2D, health: HealthComponent, def: EnemyDef}
var _last_hit_msec: Dictionary = {}  # peer_id -> 마지막 스윙 앵커 msec (호스트 전용 — 연사 스팸 게이트)
var _roll_grant_msec: Dictionary = {}  # peer_id -> 마지막 구르기 그랜트 msec (호스트 전용 — i-frame 창)
var _pending_php: Dictionary = {}  # peer_id -> hp (게스트 전용) — 스폰 전 도착한 php 보류. 씬 전환 직후 호스트의 이월 HP 확정이 원격 아바타 스폰(첫 G_POS)보다 먼저 오면 유실되던 표시 드리프트 방지 (peer_sync._peer_jobs 보류 패턴 미러)
var _stage_over: bool = false  # 클리어↔전멸 상호 배제 + 종료 후 판정 중지
var _boss_strike_frame: Dictionary = {}  # peer_id -> 보스 STRIKE 피격 물리 프레임 — 물뿌리기 원 겹침 시 같은 프레임 중복 확정 방지(per-cast dedup, 보스는 한 프레임에 한 패턴만 발화)
var _arrows: Array = []  # 호스트 권한 화살(궁수 활): [{aid, pos:Vector2, dir:Vector2, life:float, shooter:int}, …] — _physics_process가 전진·명중 판정
var _last_shot_msec: Dictionary = {}  # peer_id -> 마지막 발사 msec (호스트 전용 — 발사율 스팸 게이트, _last_hit_msec 미러)
var _rng := RandomNumberGenerator.new()  # 치명타 굴림 — 호스트만 (DropAuthority._rng 관용구). 게스트는 굴리지 않는다(§1)
var _leech_frac: Dictionary = {}  # peer_id -> 피흡 소수 잔량(호스트 전용). 데미지가 4~34 정수라 매 타격 절삭하면 6% 흡혈이 0이 된다 → 1 이상 쌓이면 회복(§3)


func _ready() -> void:
	_peer_sync = get_node(peer_sync_path) as PeerSyncNode
	if _peer_sync == null:
		push_error("[CombatAuthority] peer_sync_path 미배선 — 전투 확정 불능")
		return
	if Net.is_host():
		_rng.randomize()  # 치명 굴림은 호스트 전용 — 게스트는 rng를 쓰지 않는다
	EventBus.net_msg.connect(_on_net_msg)
	EventBus.player_spawned.connect(_on_player_spawned)
	EventBus.attack_hit.connect(_on_attack_hit)
	EventBus.enemy_hp_confirmed.connect(_on_enemy_hp_confirmed)
	EventBus.player_hp_confirmed.connect(_on_player_hp_confirmed)
	EventBus.mob_strike.connect(_on_mob_strike)
	EventBus.boss_strike.connect(_on_boss_strike)
	EventBus.player_shoot.connect(_on_player_shoot)
	for node: Node in get_tree().get_nodes_in_group("enemy"):
		_register_enemy(node)
	EventBus.peer_left.connect(func(peer_id: int) -> void:
		_last_hit_msec.erase(peer_id)
		_roll_grant_msec.erase(peer_id)
		_last_shot_msec.erase(peer_id)  # 발사율 게이트 기록 정리 (_last_hit_msec 대칭)
		_leech_frac.erase(peer_id)  # 피흡 잔량도 대칭 정리 (이탈 피어 잔류 방지)
		_pending_php.erase(peer_id)
		_boss_strike_frame.erase(peer_id)  # 보스 STRIKE dedup 기록도 대칭 정리 (유한하나 정리 일관성)
		GameState.drop_party_hp(peer_id))  # 챕터 내 잔류 이월 기록 정리 (재접속 id는 증가라 재사용 없음)


# 스폰 후속 처리. 호스트: 챕터 내 스테이지 간 HP 이월(GDD §4 한 호흡 진행 — 모닥불 회복의 전제)
# — 스폰 직후(잡 반영 뒤) 이월 HP를 권한 경로로 재확정 → php 브로드캐스트로 전원 수렴.
# 기록이 없으면(챕터 첫 판·마을) 풀피 유지. 마을 복귀 시 GameState.leave_chapter가 기록을 지운다.
# 게스트: 스폰 전에 도착해 보류된 php 반영 — 없으면 표시가 다음 확정까지 풀피로 드리프트한다.
func _on_player_spawned(peer_id: int, player: Node) -> void:
	var p := player as PlayerActor
	if p == null:
		return
	if not Net.is_host():
		if _pending_php.has(peer_id):
			p.confirm_hp_from_net(int(_pending_php[peer_id]))
			_pending_php.erase(peer_id)
		return
	var carried := GameState.carried_hp(p.peer_id)
	if carried < 0:
		return
	var health := p.get_node_or_null("Health") as HealthComponent
	if health != null and carried != health.hp:
		health.confirm_hp(carried)


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
	# 🔴 공속 반영 — 공격자 아바타의 level_stats에서 읽는다. **치명·피흡(_apply_confirmed)과 같은 소스**여야 한다:
	#   peer_level_stats()는 G_STATS **수신** 기록이라 로컬(호스트 자신) 항목이 영원히 없다(Net에 루프백 없음 —
	#   drop_spawn_local이 존재하는 그 이유). 그걸 게이트에 쓰면 호스트 자기 공속이 0으로 검증돼,
	#   로컬 간격 1/(1+h)가 게이트 0.9배보다 짧아지는 h>0.111부터 **자기 타격이 한 번 걸러 무피해**가 된다
	#   (에러 0·로그 0, 2026-07-25 리뷰 C1). 아바타 값은 로컬=내 레벨·원격=수신 clamp분이라 신뢰 경계는 그대로다
	#   (player.set_level_stats가 하드 상한으로 한 번 더 clamp).
	var haste_p := _peer_sync.player(attacker_id)
	var atk_haste := float(haste_p.level_stats.get("haste", 0.0)) if haste_p != null else 0.0
	if not CombatMath.is_hit_cooldown_ok(last, now, job, atk_haste):
		return
	if now - last > CombatMath.SAME_SWING_MS:
		_last_hit_msec[attacker_id] = now  # 새 스윙 앵커 — 매 확정마다 갱신하면 창이 미끄러진다
	_apply_confirmed(health, job, attacker_id, 0)  # 데미지 산출·치명·피흡은 공용 경로(아래) — 3경로 공통


# 🔴 호스트 전용 — 데미지 확정의 **단일 경로** (근접·투사체·폭발 공통, rules §3).
# 곱 순서·반올림·치명 판정은 전부 CombatMath.confirm_damage가 전담한다(경로마다 갈라지면 같은
# 상황에서 데미지가 달라진다 — charge_damage가 이미 round를 하므로 치명을 밖에서 곱하면 이중 반올림).
# 여기서 얹는 것은 ⑴ 공격자 보너스·레벨 스탯 조회 ⑵ 피흡 적립뿐이다.
# 치명 굴림 단위 = 데미지 인스턴스 1회 — 폭발이 3마리를 때리면 이 함수가 3번 불려 각각 굴린다(사용자 확정).
func _apply_confirmed(health: HealthComponent, job: JobDef, attacker_id: int, charge_level: int) -> void:
	var atk_p := _peer_sync.player(attacker_id)
	# 착용 장비 공격 보너스·레벨 5스탯 = 공격자 아바타(G_STATS로 반영). 미착용/미상 = 0·빈 dict (항등 폴백).
	var bonus := atk_p.equip_atk_bonus if atk_p != null else 0
	var lv_stats: Dictionary = atk_p.level_stats if atk_p != null else {}
	var res := CombatMath.confirm_damage(job, bonus, lv_stats, charge_level, _rng.randf())
	var dmg := int(res["damage"])
	if dmg <= 0:
		return
	var before := health.hp
	health.apply_damage(dmg, bool(res["crit"]))  # crit은 Health.last_crit으로 표시 경로에 전달(§3)
	_accrue_leech(attacker_id, before - health.hp, lv_stats)  # 🔴 실제로 깎인 HP 기준 = 오버킬 클립


# 호스트 전용 — 피흡 적립·회복. 소수를 누적해 1 이상이면 confirm_hp로 확정한다(새 메시지 0개 —
# php 브로드캐스트가 기존 경로로 전원에 전파). 잔량은 호스트만 갖는다: 게스트가 자기 잔량을 들면
# 회복 확정이 두 곳이 되어 §1 위반이다.
func _accrue_leech(attacker_id: int, applied_damage: int, lv_stats: Dictionary) -> void:
	var gain := CombatMath.leech_gain(applied_damage, float(lv_stats.get("leech", 0.0)))
	if gain <= 0.0:
		return
	var acc := float(_leech_frac.get(attacker_id, 0.0)) + gain
	var whole := int(floor(acc))
	_leech_frac[attacker_id] = acc - float(whole)
	if whole <= 0:
		return
	var p := _peer_sync.player(attacker_id)
	if p == null or not p.is_alive():
		return  # 사망자는 회복하지 않는다 (hit_req·G_SHOOT 사망 거부와 같은 규율)
	var h := p.get_node_or_null("Health") as HealthComponent
	if h == null or h.hp >= h.max_hp:
		return  # max_hp 상한 — 넘겨 회복하지 않는다
	h.confirm_hp(mini(h.max_hp, h.hp + whole))  # dropped=false라 거짓 피격 손맛이 안 뜬다


# --- 투사체(궁수 활·법사 차지 지팡이) 호스트 권한 (2026-07-24) — 결정론 직선. 표시는 ArrowField(전 클라), 판정은 여기(호스트만) ---
# 로컬 발사(호스트 자신) — 권한 투사체 등록. 자기 발사는 신뢰(로컬 쿨다운·차지가 발사율 제한). 게스트는 여기 안 옴(is_host 가드).
func _on_player_shoot(shooter_id: int, origin: Vector2, dir: Vector2, aid: String,
		arrow_range: float, weapon_id: String, charge: int) -> void:
	if not Net.is_host() or _stage_over:
		return
	_register_arrow(aid, origin, dir, shooter_id, arrow_range, weapon_id, charge)


# 속도·수명·폭발 반경은 GameState.projectile_params 단일 소스(§3) — 표시(ArrowField)와 같은 값이라
# "맞는 곳=보이는 곳"이 유지된다. 게스트 주장(w·r·c)은 그 안에서 allowlist 리졸브·clamp된다.
func _register_arrow(aid: String, origin: Vector2, dir: Vector2, shooter_id: int,
		arrow_range: float, weapon_id: String, charge: int) -> void:
	# 유한성 가드 — 게스트 발 dx/dy가 INF(JSON 1e999)면 normalized()가 NaN이 되어 == ZERO를 통과한다.
	# apply_remote_pos의 Inf/NaN 방어와 일관되게 차단 (NaN 화살은 무해하나 리스트를 오염시키지 않게).
	if aid.is_empty() or not (is_finite(dir.x) and is_finite(dir.y)):
		return
	var d := dir.normalized()
	if d == Vector2.ZERO:
		return
	var p := GameState.projectile_params(weapon_id, arrow_range, charge)
	_arrows.append({"aid": aid, "pos": origin, "dir": d, "life": float(p["life"]),
		"speed": float(p["speed"]), "blast": float(p["blast"]), "level": int(p["level"]),
		"shooter": shooter_id})


# 호스트 전용 — 권한 투사체 전진 + 명중 판정. 매 프레임 거리 질의(is_arrow_hit)라 물리 레이어 함정(§5) 회피 + 단위 테스트 가능.
# 첫 적중에서 멈춤(관통 없음). 폭발탄(차지)은 그 지점에서 반경 판정(여러 적) + 빗나가도 만료 지점에서 폭발.
# 발사율은 발사 시 is_fire_rate_ok로 이미 강제 — 명중엔 쿨다운 게이트 재적용 안 함(투사체 하나=한 발).
func _physics_process(delta: float) -> void:
	if not Net.is_host() or _stage_over or _arrows.is_empty():
		return
	var survivors: Array = []
	for a: Dictionary in _arrows:
		var pos := (a["pos"] as Vector2) + (a["dir"] as Vector2) * (float(a["speed"]) * delta)
		a["pos"] = pos
		a["life"] = float(a["life"]) - delta
		var blast_r := float(a["blast"])
		var hit_eid := _arrow_probe(pos)
		if not hit_eid.is_empty():
			if blast_r > 0.0:
				_confirm_blast(a, pos)  # 폭발탄 — 반경 안 전원(첫 적중 대상 포함)
			else:
				_confirm_arrow_hit(hit_eid, a)
			_terminate_arrow(str(a["aid"]), pos)
			continue  # 투사체 소멸 — survivors에 안 넣음
		if float(a["life"]) <= 0.0:
			# 빗나감 — 표시 탄은 각 클라 로컬 수명으로 동시 소멸(브로드캐스트 불필요).
			# 폭발탄은 그 자리에서 터진다: 판정은 여기(호스트), FX는 각 클라 arrow.expired 로컬(같은 지점).
			if blast_r > 0.0:
				_confirm_blast(a, pos)
			continue
		survivors.append(a)
	_arrows = survivors


# 화살 현재 위치에 맞는 살아있는 적 eid (첫 적중, 없으면 ""). 판정 반경 = 화살굵기 + 적 body_radius (§3 거대 적 대응).
func _arrow_probe(pos: Vector2) -> String:
	for eid: String in _enemies:
		var entry := _enemies[eid] as Dictionary
		var health := entry["health"] as HealthComponent
		if health == null or health.is_dead():
			continue
		var root := entry["root"] as Node2D
		if root == null:
			continue
		var def := entry["def"] as EnemyDef
		var body_r := def.body_radius if def != null else 0.0
		if CombatMath.is_arrow_hit(pos, root.global_position, body_r):
			return eid
	return ""


# 호스트 전용 — 단일 명중(화살) 데미지 확정. 쿨다운 게이트 없음(발사 시 강제).
func _confirm_arrow_hit(eid: String, a: Dictionary) -> void:
	var entry_v: Variant = _enemies.get(eid)
	if entry_v == null:
		return
	var shooter := _peer_sync.player(int(a["shooter"]))
	if shooter == null or shooter.job == null:
		return  # 발사자 이탈/무직업 = 무피해 (기존 동작 보존)
	_apply_confirmed((entry_v as Dictionary)["health"] as HealthComponent,
		shooter.job, int(a["shooter"]), int(a["level"]))


# 호스트 전용 — 폭발 확정(차지 무기): 반경 안 살아있는 적 전원에게 같은 데미지 1회.
# 판정 반경 = 표시 폭발 FX 반경(둘 다 GameState.projectile_params → charge_blast_radius) — "맞는 곳=보이는 곳"(§3).
# ⚠ 현재는 적만 친다 — 아군 오사(플레이어 피격)는 협동 설계상 없음(GDD §5 2인 협동). 넣으려면 여기에 플레이어 루프 추가.
func _confirm_blast(a: Dictionary, center: Vector2) -> void:
	var shooter := _peer_sync.player(int(a["shooter"]))
	if shooter == null or shooter.job == null:
		return  # 발사자 이탈/무직업 = 무피해
	var radius := float(a["blast"])
	for eid: String in _enemies:
		var entry := _enemies[eid] as Dictionary
		var health := entry["health"] as HealthComponent
		if health == null or health.is_dead():
			continue
		var root := entry["root"] as Node2D
		if root == null:
			continue
		var def := entry["def"] as EnemyDef
		var body_r := def.body_radius if def != null else 0.0
		if CombatMath.is_blast_hit(root.global_position, center, radius, body_r):
			# 대상별로 따로 확정 = 치명 굴림도 대상별 1회 (사용자 확정 2026-07-25)
			_apply_confirmed(health, shooter.job, int(a["shooter"]), int(a["level"]))


# 호스트 전용 — 화살 종료 통지: 게스트는 G_ARROW_HIT로, 호스트 자신은 arrow_gone_local로(릴레이 미에코). ArrowField가 despawn.
func _terminate_arrow(aid: String, pos: Vector2) -> void:
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_ARROW_HIT, "aid": aid, "x": pos.x, "y": pos.y})
	EventBus.arrow_gone_local.emit(aid, pos)


# 호스트 전용 수신 경로 — Health 권한 경로(apply_damage/부활)가 확정한 HP를 전원에 브로드캐스트
func _on_enemy_hp_confirmed(eid: String, hp: int) -> void:
	# 치명 여부는 Health가 확정 직전에 세팅한 last_crit에서 읽는다(표시 강조 전용 — 굴림은 이미 끝났다).
	var crit := false
	var ehp_entry: Variant = _enemies.get(eid)
	if ehp_entry != null:
		var eh := (ehp_entry as Dictionary)["health"] as HealthComponent
		crit = eh != null and eh.last_crit
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_ENEMY_HP, "eid": eid, "hp": hp,
		"cr": 1 if crit else 0})
	if hp <= 0:
		# 드랍 롤 트리거 (호스트 전용 경로) — 죽는 순간 좌표에서 떨어지도록 clear 판정 전에 쏜다.
		# 실제 롤·산개·브로드캐스트는 DropAuthority가 받는다 (rules §2 책임 분리, §1 호스트 권한).
		var entry_v: Variant = _enemies.get(eid)
		if entry_v != null:
			var entry := entry_v as Dictionary
			var root := entry["root"] as Node2D
			if root != null:
				EventBus.enemy_killed.emit(eid, entry["def"] as EnemyDef, root.global_position)
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
		# 지연 보상(§3): 낡은 수신 좌표와 속도로 외삽한 추정 좌표가 **둘 다** 판정 안일 때만 확정.
		# 호스트 자신은 one_way=0·is_local이라 두 좌표가 같아져 기존 동작과 동일하다(항등 폴백).
		if not CombatMath.is_strike_hit_lagged(
				p.net_anchor(), p.net_anchor_lead(Net.one_way_ms(p.peer_id)),
				center, def.strike_radius):
			continue
		if _is_iframe_active(p):
			continue  # 구르기 무적 (GDD §11 확정 2026-07-22)
		(p.get_node("Health") as HealthComponent).apply_damage(def.attack_damage)


# 호스트 전용(보스 AI가 호스트에서만 emit) — 패턴 타격 판정·확정. 판정 좌표 = net_anchor (rules §3),
# 판정 기하 = pattern.shape별(원/부채꼴, CombatMath 단일 소스 §3). "맞는 곳=보이는 곳" — 텔레그래프와 같은 range/half_angle.
func _on_boss_strike(center: Vector2, angle: float, pattern: BossPatternDef) -> void:
	if not Net.is_host() or _stage_over or pattern == null:
		return
	var frame := Engine.get_physics_frames()  # 물뿌리기 N개 원이 같은 프레임에 emit → 플레이어당 1회로 dedup
	for node: Node in get_tree().get_nodes_in_group("player"):
		var p := node as PlayerActor
		if p == null or not p.is_alive():
			continue
		if int(_boss_strike_frame.get(p.peer_id, -1)) == frame:
			continue  # 이번 STRIKE(프레임)에서 이미 이 플레이어 피격 — 착탄 원 겹침 중복 데미지 차단
		# 지연 보상(§3) — 잔몹 STRIKE와 같은 규약: 낡은 좌표·추정 좌표가 둘 다 맞아야 확정.
		var anchor := p.net_anchor()
		var lead := p.net_anchor_lead(Net.one_way_ms(p.peer_id))
		var hit := false
		if pattern.shape == "cone":
			hit = CombatMath.is_hit_in_cone_lagged(
				anchor, lead, center, angle, pattern.half_angle, pattern.range)
		else:
			hit = CombatMath.is_strike_hit_lagged(anchor, lead, center, pattern.range)
		if not hit:
			continue
		if _is_iframe_active(p):
			continue  # 구르기 무적 (GDD §11 — 잔몹/보스 공용 예고 회피)
		(p.get_node("Health") as HealthComponent).apply_damage(pattern.damage)
		_boss_strike_frame[p.peer_id] = frame


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
	EventBus.stage_cleared.emit()  # 다음 칸/마을 전환은 ChapterFlow(호스트)가 결정


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
	EventBus.stage_wiped.emit()  # 마을 귀환 전환은 ChapterFlow(호스트)가 결정


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
			# 적 몸 반경 반영 — 거대 보스(radius ~48)는 중심이 멀어 표면까지로 판정 (§3, 기존 잔몹 영향 미미).
			var reach_def := entry["def"] as EnemyDef
			var reach_radius := reach_def.body_radius if reach_def != null else 0.0
			# 🔴 메인 특성(검기 파형)의 사거리 보너스도 **공격자 아바타에서** 읽는다 — 공속·치명·피흡과
			#   같은 소스다(위 _confirm_damage 주석: peer_level_stats류는 호스트 자신 항목이 없어
			#   검성 호스트가 자기 파형 사거리를 못 받고 "내 파형은 헛치는데 게스트는 맞는다"가 된다).
			#   아바타 값은 로컬=GameState 리졸브·원격=공지 id 리졸브라 신뢰 경계는 그대로다(수치 무전송).
			if CombatMath.is_hit_in_reach(
					attacker.net_anchor(), (entry["root"] as Node2D).global_position, attacker.job,
					reach_radius, attacker.reach_bonus):
				_confirm_damage(entry["health"] as HealthComponent, attacker.job, from_id)
		NetSchema.G_SHOOT:
			if not Net.is_host() or _stage_over:
				return  # 화살 등록 권한은 호스트만 (게스트도 릴레이 도달하나 무시)
			var shooter := _peer_sync.player(from_id)
			if shooter == null or not shooter.is_alive() or shooter.job == null:
				return  # 사망(관전 고스트)·무스폰 피어의 발사 거부 — G_HIT_REQ 미러 (rules §3)
			# aid 네임스페이스 검증 — 발신자가 "피어id:seq" 규약을 지키는지. 안 그러면 남의 화살 aid("1:5")를
			# 위조해 그 화살 종료 시 상대 표시 화살을 조기 despawn시키는 코스메틱 그리핑이 가능(reviewer 2026-07-24).
			var aid_s := str(data.get("aid", ""))
			if not aid_s.begins_with(str(from_id) + ":"):
				return
			# 신뢰 경계(rules §3): 발사율(job 쿨다운) + 원점 근접 검증. 스팸·순간이동 원점 거부.
			# 좌표는 net_anchor() — 표시 보간 지연 제외(사거리 검증과 같은 철학).
			var now_shot := Time.get_ticks_msec()
			var last_shot := int(_last_shot_msec.get(from_id, -1000000000))
			# 발사율·차지 시간도 공속 반영 — 근접과 **같은 소스**(공격자 아바타). peer_level_stats를 쓰면
			# 호스트 자신에게 값이 없다(위 _confirm_damage 주석 참조).
			var shoot_haste := float(shooter.level_stats.get("haste", 0.0))
			if not CombatMath.is_fire_rate_ok(last_shot, now_shot, shooter.job, shoot_haste):
				return
			var origin := Vector2(float(data.get("ox", 0.0)), float(data.get("oy", 0.0)))
			if not CombatMath.is_shot_origin_ok(shooter.net_anchor(), origin):
				return
			# 차지 레벨 검증(법사 지팡이, rules §3) — 주장한 단계만큼 실제로 모을 시간이 있었는가.
			# ⚠ 무기는 **메시지 "w"가 아니라 그 피어가 G_STATS로 공지한 착용 무기**로 리졸브한다 —
			#   안 그러면 전사/궁수가 w="worn_staff"를 실어 차지 배율(×3.4)과 광역 폭발을 얻는다(2026-07-24 리뷰).
			#   표시(ArrowField)는 메시지 w를 쓰므로 사칭 시 그 클라 화면에만 폭발이 그려지고 판정은 안 난다(안전한 방향).
			#   G_STATS 미도착 창에서는 ""(기본 화살) → 폭발/차지 없음. 관대한 쪽으로 실패하지 않는다.
			# ⚠ 네트워크 지연은 도착을 늦출 뿐이라 정당한 발사를 떨구지 않는다(경과 시간이 길어지는 쪽).
			var weapon_id := _peer_sync.peer_weapon_id(from_id)
			var charge := CombatMath.clamp_charge_level(int(data.get("c", 0)))
			var step_time := float(GameState.projectile_params(weapon_id, 0.0, charge)["step_time"])
			if not CombatMath.is_charge_time_ok(last_shot, now_shot, charge, step_time, shoot_haste):
				return
			_last_shot_msec[from_id] = now_shot
			_register_arrow(aid_s, origin,
				Vector2(float(data.get("dx", 1.0)), float(data.get("dy", 0.0))), from_id,
				float(data.get("r", CombatMath.DEFAULT_ARROW_RANGE)), weapon_id, charge)
		NetSchema.G_ENEMY_HP:
			if Net.is_host():
				return  # 호스트 상태가 원본
			if from_id != NetSchema.HOST_ID:
				return  # 권한 스푸핑 차단 — HP 확정은 호스트 발신만 신뢰 (from은 릴레이가 찍음)
			var entry_hp: Variant = _enemies.get(str(data.get("eid", "")))
			if entry_hp != null:
				((entry_hp as Dictionary)["health"] as HealthComponent).set_hp_display(
					int(data.get("hp", 0)), int(data.get("cr", 0)) == 1)
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
			var pid := int(data.get("pid", 0))
			var target := _peer_sync.player(pid)
			if target != null:
				target.confirm_hp_from_net(int(data.get("hp", 0)))
			else:
				_pending_php[pid] = int(data.get("hp", 0))  # 스폰 전 도착 — player_spawned에서 반영
		NetSchema.G_STAGE_CLEAR:
			if not Net.is_host() and from_id == NetSchema.HOST_ID and not _stage_over:
				_stage_over = true
				EventBus.stage_cleared.emit()  # 부활 자체는 php가 옮긴다 — clear는 흐름/배너만
		NetSchema.G_WIPE:
			if not Net.is_host() and from_id == NetSchema.HOST_ID and not _stage_over:
				_stage_over = true
				EventBus.stage_wiped.emit()
