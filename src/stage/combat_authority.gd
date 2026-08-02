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

# 🔴 지형 레이어(1 = world) 마스크 — rules §5 배정표가 단일 소스. 투사체의 지형 차단 질의 전용
#   (설계 ⑹ 층②). 몸 레이어를 넣지 마라 — 명중 판정은 여전히 거리 질의다(물리 레이어 함정 §5).
const WORLD_MASK := 1 << 0

@export var peer_sync_path: NodePath  # 형제 PeerSync — 공격자 조회(net_anchor·job)에 필요

var _peer_sync: PeerSyncNode = null
var _enemies: Dictionary = {}  # eid -> {root: Node2D, health: HealthComponent, def: EnemyDef}
var _last_hit_msec: Dictionary = {}  # peer_id -> 마지막 스윙 앵커 msec (호스트 전용 — 연사 스팸 게이트)
var _roll_grant_msec: Dictionary = {}  # peer_id -> 마지막 구르기 그랜트 msec (호스트 전용 — i-frame 창)
var _pending_php: Dictionary = {}  # peer_id -> hp (게스트 전용) — 스폰 전 도착한 php 보류. 씬 전환 직후 호스트의 이월 HP 확정이 원격 아바타 스폰(첫 G_POS)보다 먼저 오면 유실되던 표시 드리프트 방지 (peer_sync._peer_jobs 보류 패턴 미러)
var _stage_over: bool = false  # 클리어↔전멸 상호 배제 + 종료 후 판정 중지
var _boss_strike_frame: Dictionary = {}  # peer_id -> 보스 STRIKE 피격 물리 프레임 — 물뿌리기 원 겹침 시 같은 프레임 중복 확정 방지(per-cast dedup, 보스는 한 프레임에 한 패턴만 발화)
var _boss_sweep_seq: Dictionary = {}  # peer_id -> 마지막 피격 dash_seq — 🔴 돌진(P3) 스윕은 매 프레임 발화라 여기서 **돌진 1회당 플레이어 1회**로 dedup(프레임 dedup으론 매 프레임 데미지). i-frame으로 안 맞으면 미기록 → 다음 프레임 재판정(구르며 반경 밖으로 빠지면 회피)
var _arrows: Array = []  # 호스트 권한 화살(궁수 활): [{aid, pos:Vector2, dir:Vector2, life:float, shooter:int}, …] — _physics_process가 전진·명중 판정
# 호스트 권한 **적** 화살(원거리 잔몹, 2026-08-01): [{aid, pos, dir, speed, life, radius, damage}, …]
# 🔴 `_arrows`에 얹을 수 없다 — 저쪽 엔트리의 `shooter`는 peer id이고 명중 시 그 아바타에서
#   job·장비 보너스·레벨 스탯을 꺼내 `confirm_damage`(치명·피흡·콤보)를 지난다. 적 화살은
#   **공격자·대상·데미지 산식이 셋 다 뒤집힌다**(대상 = 플레이어, 데미지 = def.attack_damage 평문).
#   ⚠ 평문인 것이 규율 위반이 아니다 — 적→플레이어는 `_on_mob_strike`가 이미 평문이고,
#     §3의 "`confirm_damage`가 3경로 전부"는 **플레이어→적** 계약이다. 새 데미지 축은 0개.
# ⚠ 전진·지형 차단·종료 통지는 `_arrows`와 **같은 헬퍼**를 지난다(갈라질 자리를 안 만든다).
var _mob_arrows: Array = []
var _last_shot_msec: Dictionary = {}  # peer_id -> 마지막 발사 msec (호스트 전용 — 발사율 스팸 게이트, _last_hit_msec 미러)
# peer_id -> 호스트가 그 피어에게 **마지막으로 인정한** 평타 콤보 타수 (호스트 전용, 궁수 "평·평·쭉").
# 🔴 클라 주장(G_SHOOT "cb")을 그대로 믿으면 매 발사가 마무리 타(사거리 2배·데미지 2.5배)가 된다 —
#   근접 콤보(G_ATK "cb")가 궤적만 정해 "조작돼도 화면만 달라진다"였던 것과 성격이 다르다.
#   그래서 호스트가 **자기 수신 간격으로 직접 세고**(CombatMath.authoritative_combo) 주장은 상한으로만 쓴다.
var _shot_combo: Dictionary = {}
# peer_id -> 호스트가 그 피어에게 **마지막으로 인정한** 근접 콤보 타수 (호스트 전용, v2.2 2026-07-29).
# 🔴 `_shot_combo`의 **미러**다 — 규칙 함수(`CombatMath.authoritative_combo`)·정리(`peer_left`)·
#   "주장은 상한으로만"이 전부 같다. 갈리는 것은 무엇을 고르는가뿐이다(이쪽 = 데미지 배율 + 마무리 각).
# 🔴 **세는 소스는 `G_ATK`뿐이다 — `G_HIT_REQ`로 세지 마라.** 그쪽은 **맞았을 때만** 오므로 헛친 스윙이
#   누락돼 `min`이 정직한 마무리 타를 깎는다. 근접은 헛치는 것이 흔하고 GDD §6이 "헛쳐도 콤보는
#   전진한다"로 못박았다. G_ATK는 매 스윙 1회 + safe 채널(유실 없음)이라 유일하게 옳은 소스다.
# 🔴 **호스트 자신의 항목은 영원히 없다**(Net 루프백 없음) — 자기 콤보는 로컬 아바타에서 읽는다
#   (`_on_attack_hit` → `player.melee_combo_mult()`). `_shot_combo`가 같은 자리에서 같은 판단을 한다.
var _melee_combo: Dictionary = {}
var _last_atk_msec: Dictionary = {}  # peer_id -> 마지막 G_ATK 수신 msec (콤보 간격 측정 전용 — `_last_shot_msec` 미러)
# peer_id -> 그 피어가 **주장한** 마지막 타수. 🔴 **각 축 전용이고 데미지에는 절대 쓰지 마라.**
# 🔴 **두 축을 왜 가르는가** (netreview C-1, 2026-07-29): 각을 `_melee_combo`(min된 타수)로 세우면
#   데이터가 `combo_finish_arc ≥ swing_arc`를 강제하므로 주장과 계수가 어긋난 순간 **호스트 콘이 로컬
#   콘의 진부분집합**이 되어 §3 「로컬 ≤ 호스트」가 깨진다 — 로컬은 그 띠의 적에게 `G_HIT_REQ`를
#   보내는데 호스트가 거부하고, 증상은 **스윙·궤적·타격음·킥이 다 나오고 적 HP만 안 깎이는 것**이다
#   (거부 띠 실측: 창 17.2° = 마무리 콘의 절반 · 대검 2종 28.6° · 도끼 5.7°). 도달성도 낮지 않다 —
#   클라와 호스트가 `combo_window_s` **같은 함수**를 쓰므로 창 경계 근처에서 이어 치면 양수 지터
#   아무거나 호스트를 리셋시킨다(상한 여유 0).
# 🔴 **「판정 ≤ 표시」는 이래도 유지된다 — 표시도 주장 타수로 그려지기 때문이다.** 각·표시·로컬 질의
#   셋이 전부 주장 기준으로 정렬되고, `min`은 **데미지에만** 남는다(데미지는 그려지는 것이 없으므로
#   낮은 쪽으로 눌러도 화면과 어긋날 수 없다).
# 🔴 **신뢰 대가 ≈ 0** — 주장으로 넓힐 수 있는 각의 상한은 `melee_half_angle`이 쥔 `PI − EPS − MARGIN`
#   (2.98)인데, 변조 클라는 `dx`/`dy`를 **빼기만 하면** 이미 전방위(π)를 공짜로 얻는다(`net_schema`가
#   *"부채꼴은 안티치트가 아니라 게임 정합 장치"* 라고 명시). 즉 새로 열리는 표면이 없다.
# ⚠ 순서 의존: G_ATK(클릭 시점)와 G_HIT_REQ(판정 시점)가 **같은 ordered 채널**(`RTC_CH_SAFE`/릴레이 TCP)
#   이라 같은 스윙의 G_ATK가 항상 먼저 도착한다. G_ATK를 fast로 내리면 이 기록이 조용히 낡는다(§3 불변식).
var _melee_claim: Dictionary = {}
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
	EventBus.boss_sweep.connect(_on_boss_sweep)
	EventBus.player_shoot.connect(_on_player_shoot)
	EventBus.mob_shoot.connect(_on_mob_shoot)
	# 🔴 **자기 씬 하위만 등록한다** — 그룹 스캔은 씬 스왑 프레임에 **이전 씬의 적까지** 돌려준다
	#   (rules §5). 근본 처방은 `main._swap`의 `remove_child`지만, 이 스캔은 `_ready` **일회**라
	#   유령이 들어오면 딕셔너리에 영구히 박히고 그 대가가 크다: 다음 프레임에 그 노드가 해제되면
	#   `_check_clear`의 `entry["health"] as HealthComponent`가 **캐스트에서** 터져
	#   (`Trying to cast a freed object`) 함수가 중단되고, Dictionary는 삽입 순서라 유령이 늘 첫
	#   항목이라 **스테이지가 영영 클리어되지 않는다**(2026-08-01 "스테이지2에서 멈춘다" 신고의 원인).
	#   ⚠ 소비처 12곳에 `is_instance_valid`를 뿌리는 대신 **입구 하나**를 막는다 — 그래야 다음에
	#     `_enemies`를 읽는 코드가 늘어도 같은 결함이 재발하지 않는다.
	#   ⚠ 스캔 시점의 유령은 **아직 살아 있어** 캐스트가 안 터진다 — 그래서 이 필터가 성립한다.
	# 🔴 **기준은 `owner`(그 .tscn의 루트)다 — `get_parent()`가 아니다** (netreview 2026-08-01).
	#   둘은 지금 같은 노드를 가리키지만(전 씬에서 컴포넌트가 루트의 직계 자식), 누군가 컴포넌트를
	#   `Systems` 같은 노드로 한 겹만 감싸면 `get_parent()`는 그 껍데기를 반환해 **자기 씬 적이
	#   하나도 안 통과한다.** 그 실패는 조용하고 증상이 방금 고친 것과 **똑같은데**(클리어 영영 안 됨 ·
	#   게스트 hit_req 전량 무시 · 드랍·EXP 0) 이번엔 **SCRIPT ERROR조차 안 난다.**
	#   `owner`는 중첩 깊이와 무관하게 그 씬의 루트다(실측: 4개 씬 전부 `owner=Stage`/`Campfire`).
	var scene_root: Node = owner if owner != null else get_parent()
	var passed := 0
	for node: Node in get_tree().get_nodes_in_group("enemy"):
		if scene_root == null or not scene_root.is_ancestor_of(node):
			continue
		passed += 1
		_register_enemy(node)
	# 🔴 **실패 방향이 「전면 무등록」이라 진단을 코드로 박아 둔다.** 위 필터가 어떤 이유로든
	#   자기 씬 적을 떨어뜨리면 화면에는 "적이 안 죽는다/클리어가 안 된다"로만 나타난다 —
	#   에러가 없으면 다음 사람이 다시 며칠을 쓴다. 씬 하위 실제 개수와 통과 개수를 대조한다.
	#   ⚠ `_register_enemy` 자체의 거부(eid 없음·Health 없음)는 그쪽이 이미 push_error를 낸다.
	if scene_root != null:
		var under := _count_in_group_under(scene_root, &"enemy")
		if passed < under:
			push_error("[CombatAuthority] 씬 하위 적 %d마리 중 %d마리만 등록됐다 — 씬 스캔 필터가 자기 씬을 떨어뜨린다(scene_root=%s)"
				% [under, passed, scene_root.name])
	EventBus.peer_left.connect(func(peer_id: int) -> void:
		_last_hit_msec.erase(peer_id)
		_roll_grant_msec.erase(peer_id)
		_last_shot_msec.erase(peer_id)  # 발사율 게이트 기록 정리 (_last_hit_msec 대칭)
		_shot_combo.erase(peer_id)  # 콤보 타수 기록도 대칭 정리 — 남겨 두면 재접속 id가 남의 마무리 타를 물려받는다
		_melee_combo.erase(peer_id)  # 근접 콤보도 같은 이유로 (v2.2 — 이쪽은 데미지 배율·마무리 각을 고른다)
		_last_atk_msec.erase(peer_id)  # 근접 콤보 간격 기준점 (_last_shot_msec 대칭)
		_melee_claim.erase(peer_id)  # 주장 타수(각 축)도 대칭 정리 — 안 지우면 재접속 id가 남의 넓은 마무리 각을 물려받는다
		_leech_frac.erase(peer_id)  # 피흡 잔량도 대칭 정리 (이탈 피어 잔류 방지)
		_pending_php.erase(peer_id)
		_boss_strike_frame.erase(peer_id)  # 보스 STRIKE dedup 기록도 대칭 정리 (유한하나 정리 일관성)
		_boss_sweep_seq.erase(peer_id)  # 돌진 스윕 dedup 기록도 대칭 정리 (재접속 id가 남의 돌진 피격 이월 방지)
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


# 씬 하위의 그룹 소속 노드 수 — 위 「전면 무등록」 진단 전용. `_ready` 1회라 재귀 비용은 무시할 수준.
func _count_in_group_under(n: Node, group: StringName) -> int:
	var c := 1 if n.is_in_group(group) else 0
	for ch: Node in n.get_children():
		c += _count_in_group_under(ch, group)
	return c


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


# 로컬 플레이어의 공격이 적에 닿음 (player가 자기 job + 조준 방향을 실어 emit) — 확정은 권한 경로로
# ⚠ dir은 **게스트 경로에서만** 쓴다 — 호스트 자신의 타격은 로컬 부채꼴 질의가 이미 통과시킨 것이라
#   여기서 각을 다시 보지 않는다(도입 전에도 사거리를 재검증하지 않았다. 자기 질의 = 자기 권한).
func _on_attack_hit(enemy: Node, job: JobDef, dir: Vector2) -> void:
	var eid_v: Variant = enemy.get("eid")
	if not (eid_v is String):
		return
	var entry_v: Variant = _enemies.get(str(eid_v))
	if entry_v == null:
		return
	if Net.is_host():
		# 🔴 **호스트 자신의 콤보는 로컬 아바타가 유일한 소스다** (v2.2) — Net에 루프백이 없어 자기
		#   G_ATK를 받지 않으므로 `_melee_combo`엔 자기 항목이 **영원히** 없다. 그걸 읽으면 항상 0타 =
		#   "내 마무리 타만 안 아프다"가 되고, 그건 2026-07-25 공속 Critical과 **같은 함정**이다
		#   (`_on_player_shoot`이 이미 같은 관용구로 자기 발사의 타수를 아바타에서 받는다).
		# ⚠ 재계수하지 않는다 — 호스트 자신에게는 지연도 사칭 동기도 없고, 재계수하면 자기 화면 표시
		#   (같은 값을 쓰는 궤적·킥)와 자기 판정이 갈라질 수 있다.
		var me := _peer_sync.player(Net.my_id)
		# 🔴 넉백 입력도 **로컬 아바타**에서 온다 — 위와 같은 이유다(`_melee_combo`엔 자기 항목이 없다).
		#   방향은 이미 인자로 온 `dir`(그 스윙의 조준각)이라 새 필드가 필요 없다.
		var entry_self := entry_v as Dictionary
		_confirm_damage(entry_self["health"] as HealthComponent, job, Net.my_id,
			me.melee_combo_mult() if me != null else 1.0,
			{} if me == null else {"root": entry_self["root"], "def": entry_self["def"],
				"dir": dir, "equip": me.melee_weapon_def(), "finish": me.melee_is_finish()})
	else:
		Net.send_game({NetSchema.KEY_KIND: NetSchema.G_HIT_REQ, "eid": str(eid_v),
			"dx": dir.x, "dy": dir.y})


# 호스트 전용 — 데미지 확정 (rules §3 하드 계약: 계산·검증은 CombatMath만 쓴다)
# 쿨다운 게이트: 같은 스윙(SAME_SWING_MS)의 다중 타격은 허용, 스윙 간격은 공격자 job 쿨다운 강제.
# combo_mult = 근접 콤보 타별 데미지 배율(v2.2). 🔴 **호출부가 이미 확정한 값**을 받는다 — 여기서
#   리졸브하면 근거가 둘이 된다(호스트 자기 타격 = 로컬 아바타 / 게스트 = `_melee_combo` 계수분).
#   1.0 = 콤보 없는 무기 = **도입 전과 완전 항등**. 곱셈은 `confirm_damage` 안 = 반올림 여전히 1회.
func _confirm_damage(health: HealthComponent, job: JobDef, attacker_id: int,
		combo_mult: float = 1.0, knock: Dictionary = {}) -> void:
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
	_apply_confirmed(health, job, attacker_id, 0, combo_mult, knock)  # 데미지 산출·치명·피흡은 공용 경로(아래) — 3경로 공통


# 🔴 호스트 전용 — 데미지 확정의 **단일 경로** (근접·투사체·폭발 공통, rules §3).
# 곱 순서·반올림·치명 판정은 전부 CombatMath.confirm_damage가 전담한다(경로마다 갈라지면 같은
# 상황에서 데미지가 달라진다 — charge_damage가 이미 round를 하므로 치명을 밖에서 곱하면 이중 반올림).
# 여기서 얹는 것은 ⑴ 공격자 보너스·레벨 스탯 조회 ⑵ 피흡 적립뿐이다.
# 치명 굴림 단위 = 데미지 인스턴스 1회 — 폭발이 3마리를 때리면 이 함수가 3번 불려 각각 굴린다(사용자 확정).
# combo_mult = 평타 콤보 타별 데미지 배율. 🔴 **v2.2(2026-07-29)부터 근접도 실어 준다** — 전사 콤보가
# "연출 전용"이라던 옛 서술은 거짓이 됐다(GDD §6 「공격 리듬」). 곱셈은 confirm_damage 안에서 =
# 반올림 여전히 1회. 콤보 배열이 없는 무기는 1.0 = 도입 전과 완전 항등.
# knock = 넉백 입력 {root, def, dir, equip, finish}. **비면 넉백 없음 = 도입 전과 완전 항등**이고,
# 그것이 방향을 모르는 경로(dx/dy 없는 구버전·조작 클라)의 안전한 폴백이다.
func _apply_confirmed(health: HealthComponent, job: JobDef, attacker_id: int, charge_level: int,
		combo_mult: float = 1.0, knock: Dictionary = {}) -> void:
	var atk_p := _peer_sync.player(attacker_id)
	# 착용 장비 공격 보너스·레벨 5스탯 = 공격자 아바타(G_STATS로 반영). 미착용/미상 = 0·빈 dict (항등 폴백).
	var bonus := atk_p.equip_atk_bonus if atk_p != null else 0
	var lv_stats: Dictionary = atk_p.level_stats if atk_p != null else {}
	var res := CombatMath.confirm_damage(job, bonus, lv_stats, charge_level, _rng.randf(), combo_mult)
	var dmg := int(res["damage"])
	if dmg <= 0:
		return
	# 🔴 **넉백은 `apply_damage` 「앞」이다 — 순서가 계약이다.** 바로 뒤 `hp_changed` → 배우의
	#   `_on_hp_changed`가 층①(흠칫)의 세기·방향을 여기서 심은 값에서 읽는다. 뒤로 옮기면 흠칫이
	#   **한 타 늦은 무기**의 세기로 재생되고(그리고 첫 타는 옛 고정값), 화면에 이유가 안 드러난다.
	# ⚠ 데미지가 실제로 확정되는 자리에 둔 이유 = 쿨다운 게이트·0데미지에서 거부된 타격이
	#   **밀기만 하는 것**을 막는다(스팸으로 몹을 밀어내는 경로가 안 생긴다).
	_push_knockback(knock, charge_level)
	var before := health.hp
	health.apply_damage(dmg, bool(res["crit"]))  # crit은 Health.last_crit으로 표시 경로에 전달(§3)
	_accrue_leech(attacker_id, before - health.hp, lv_stats)  # 🔴 실제로 깎인 HP 기준 = 오버킬 클립


# 🔴 호스트 전용 — 넉백(층② 밀림 + 층① 흠칫 세기) 적용의 **단일 지점** (2026-08-02).
#
# 🔴 **네트워크 메시지·필드가 0개다.** 호스트가 몸을 밀면 그 결과가 이미 있는 `G_MOB_POS`
#   (10Hz, 호스트→전원)로 그대로 흐르고, 게스트는 "목표점이 뒤로 갔다"로만 받는다 —
#   게스트 코드 변경 0. 방향도 전송하지 않는다: 세 경로 모두 **이미 방향을 갖고 있다**
#   (근접 = `dir`/`dx,dy` · 화살 = 비행 방향 · 폭발 = 중심→대상 방사).
# 🔴 **세기는 `CombatMath` 하나에서 온다** — 여기서 무게·저항·상한을 다시 계산하지 마라(§3).
#   저항은 `EnemyDef.body_radius`에서 유도되므로 **새 적 = 여전히 .tres 한 장**이다.
# 🔴 **배우가 자기 상태를 안다** — 이 함수가 보는 것은 `can_knock()` 술어 하나뿐이고 보스의
#   돌진·결박·그로기를 여기서 열거하지 않는다(열거하면 보스 상태기계가 바뀔 때마다 여기가 갈라진다).
# ⚠ 잔몹·보스만 이 API를 갖는다 — 허수아비(`enemy.gd`, StaticBody2D)는 `has_method`에서 걸러져
#   **도입 전과 완전 항등**이다(밀 몸이 애초에 없다).
func _push_knockback(knock: Dictionary, charge_level: int) -> void:
	if knock.is_empty():
		return
	var root := knock.get("root") as Node2D
	if root == null or not root.has_method("apply_knockback") or not root.has_method("can_knock"):
		return
	if not bool(root.call("can_knock")):
		return
	var dir := knock.get("dir", Vector2.ZERO) as Vector2
	if not dir.is_finite() or dir.length_squared() <= 0.000001:
		return
	var equip := knock.get("equip") as EquipDef
	var is_finish := bool(knock.get("finish", false))
	var edef := knock.get("def") as EnemyDef
	root.call("apply_knockback", dir.normalized(),
		CombatMath.knockback_px(equip, is_finish, edef, charge_level),
		CombatMath.knock_show_px(equip, is_finish, charge_level))


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
# ⚠ 자기 발사의 콤보 타수는 **로컬 아바타가 이미 센 값**(player._advance_shot_combo)을 그대로 쓴다 —
#   호스트 자신에게는 네트워크 지연도 사칭 동기도 없어 재계수가 의미가 없고, 재계수를 넣으면 자기 화면
#   표시(같은 값을 쓰는 ArrowField)와 자기 판정이 갈라질 수 있다.
# ⚠ **`_shot_combo[내 id]`는 읽는 곳이 없다 — 기록 대칭을 위한 것일 뿐이다** (2026-07-27 netreview m1 정정).
#   `authoritative_combo`는 G_SHOOT 경로에서 `from_id`(원격)로만 불리고 `player_shoot`은 항상 `Net.my_id`를
#   싣는데 Net엔 루프백이 없다 — 즉 **두 키는 구조적으로 겹칠 수 없다.** 여기 대입은 무해하지만,
#   "로컬/원격이 같은 키를 공유한다"고 읽고 그 위에 무언가 얹지 마라(4인/재합류에서 그 전제가 필요해지면
#   그때 `_peer_sync.player()`처럼 로컬을 포함하는 소스로 옮기는 것이 옳다).
func _on_player_shoot(shooter_id: int, origin: Vector2, dir: Vector2, aid: String,
		arrow_range: float, weapon_id: String, charge: int, combo: int) -> void:
	if not Net.is_host() or _stage_over:
		return
	_shot_combo[shooter_id] = combo
	_register_arrow(aid, origin, dir, shooter_id, arrow_range, weapon_id, charge, combo)


# 🔴 원거리 잔몹의 발사 — 권한 화살 등록 (호스트 전용, 2026-08-01).
# 신뢰 경계는 **플레이어 경로보다 좁다**: 이 시그널의 호스트 발화는 자기 AI(`mob_melee._fire_arrow`)뿐이고,
# 게스트에서도 로컬 emit되지만 아래 `is_host` 가드가 막는다. 즉 **게스트가 적 발사를 주장할 경로가 없다** —
# `G_MOB_SHOOT`은 호스트만 보내고 수신부(MobSync)가 `from_id != HOST_ID`를 거부한다.
# 🔴 수치는 전부 **호스트 자기 def**에서 온다(네트워크로 온 것은 eid뿐) — 표시(ArrowField)도 같은 def를
#   읽으므로 속도·수명이 정확히 일치한다("맞는 곳=보이는 곳", §3).
# ⚠ `_stage_over` 가드 — 클리어 후 날아가던 화살이 부활한 플레이어를 때리지 않게(`_on_mob_strike` 미러).
func _on_mob_shoot(_eid: String, origin: Vector2, dir: Vector2, aid: String, def: EnemyDef) -> void:
	if not Net.is_host() or _stage_over or def == null or aid.is_empty():
		return
	# 유한성 가드 — 방향이 NaN/INF면 normalized()가 NaN이 되어 == ZERO를 통과한다(_register_arrow 미러).
	if not (is_finite(dir.x) and is_finite(dir.y)):
		return
	var d := dir.normalized()
	if d == Vector2.ZERO:
		return
	# 🔴 **aid 중복 등록 차단** (netreview ③) — 같은 aid가 두 번 들어오면 권한 화살이 2개가 되어
	#   **한 발이 두 번 데미지를 확정한다**(그리고 첫 종료 통지가 둘 다의 표시 탄을 지운다).
	#   지금 도달 경로는 없다(호스트 로컬 emit 1회 + 릴레이/직결 모두 중복 없는 reliable 채널)지만,
	#   막는 비용이 선형 스캔 한 번(배열 크기 = 비행 중 화살 수)이라 구조로 못 박는다.
	#   ⚠ 발신 측 유일성 근거는 `mob_melee._fire_arrow` 주석이 정본이다(eid × 단조 seq).
	for existing: Dictionary in _mob_arrows:
		if str(existing["aid"]) == aid:
			return
	var speed := CombatMath.clamp_projectile_speed(def.proj_speed)
	_mob_arrows.append({"aid": aid, "pos": origin, "dir": d, "speed": speed,
		"life": CombatMath.projectile_lifetime_s(def.proj_range, speed),
		"radius": def.strike_radius, "damage": def.attack_damage})


# 속도·수명·폭발 반경은 GameState.projectile_params 단일 소스(§3) — 표시(ArrowField)와 같은 값이라
# "맞는 곳=보이는 곳"이 유지된다. 게스트 주장(w·r·c)은 그 안에서 allowlist 리졸브·clamp된다.
func _register_arrow(aid: String, origin: Vector2, dir: Vector2, shooter_id: int,
		arrow_range: float, weapon_id: String, charge: int, combo: int) -> void:
	# 유한성 가드 — 게스트 발 dx/dy가 INF(JSON 1e999)면 normalized()가 NaN이 되어 == ZERO를 통과한다.
	# apply_remote_pos의 Inf/NaN 방어와 일관되게 차단 (NaN 화살은 무해하나 리스트를 오염시키지 않게).
	if aid.is_empty() or not (is_finite(dir.x) and is_finite(dir.y)):
		return
	var d := dir.normalized()
	if d == Vector2.ZERO:
		return
	# 🔴 「투사체 사거리」(proj_range)도 **발사자 아바타에서** 읽는다 — reach·roll_cd·campfire_heal과
	#   같은 소스다(rules §3). peer_stats류를 읽으면 호스트 자신 항목이 영원히 없어(Net 루프백 없음)
	#   "내 화살만 안 늘어난다"가 된다(2026-07-25 공속 Critical과 같은 함정).
	#   표시(ArrowField)도 같은 아바타를 읽으므로 수명 = 날아가는 거리가 일치한다("맞는 곳=보이는 곳").
	#   미스폰이면 0(항등) — G_SHOOT 경로는 이미 shooter null을 거부하므로 로컬 발사에만 남는 폴백이다.
	# 🔴 콤보 타수(combo)는 **호출부가 이미 확정한 값**이다 — G_SHOOT 경로는 authoritative_combo로 센
	#   값, 로컬 발사는 자기 아바타가 센 값. 여기서 다시 세지 않는다(근거가 둘이 되면 갈라진다).
	#   사거리 배율은 projectile_params가, 데미지 배율은 그 결과("combo_dmg")가 실어 준다 — **같은
	#   리졸브 한 번**을 지나므로 "더 멀리 가는 타 = 더 아픈 타"가 데이터 한 장에서 함께 온다.
	var shooter := _peer_sync.player(shooter_id)
	var p := GameState.projectile_params(weapon_id, arrow_range, charge,
		shooter.trait_value("proj_range") if shooter != null else 0.0, combo)
	# 🔴 넉백 무게의 출처인 **무기 정의를 발사 시점에 굳힌다** — `combo_dmg`와 같은 규약이다:
	#   명중 시점에 다시 리졸브하면 날아가는 동안 무기를 바꾼 발사자가 남의 무게를 얻는다.
	#   ⚠ 새 네트워크 필드가 아니다(로컬 dict 한 칸) — `weapon_id`는 이미 호스트가 자기 데이터로
	#     리졸브한 값이고, 모르는 id는 `equip_def`가 null로 떨어져 기본 무게(1.0)가 된다.
	_arrows.append({"aid": aid, "pos": origin, "dir": d, "life": float(p["life"]),
		"speed": float(p["speed"]), "blast": float(p["blast"]), "level": int(p["level"]),
		"shooter": shooter_id, "combo_dmg": float(p["combo_dmg"]),
		"equip": GameState.equip_def(weapon_id)})


# 호스트 전용 — 권한 투사체 전진 + 명중 판정. 매 프레임 거리 질의(is_arrow_hit)라 물리 레이어 함정(§5) 회피 + 단위 테스트 가능.
# 첫 적중에서 멈춤(관통 없음). 폭발탄(차지)은 그 지점에서 반경 판정(여러 적) + 빗나가도 만료 지점에서 폭발.
# 발사율은 발사 시 is_fire_rate_ok로 이미 강제 — 명중엔 쿨다운 게이트 재적용 안 함(투사체 하나=한 발).
func _physics_process(delta: float) -> void:
	if not Net.is_host() or _stage_over:
		return
	if not _arrows.is_empty():
		_step_player_arrows(delta)
	if not _mob_arrows.is_empty():
		_step_mob_arrows(delta)


func _step_player_arrows(delta: float) -> void:
	var survivors: Array = []
	for a: Dictionary in _arrows:
		var from_pos := a["pos"] as Vector2
		var pos := from_pos + (a["dir"] as Vector2) * (float(a["speed"]) * delta)
		a["pos"] = pos
		a["life"] = float(a["life"]) - delta
		var blast_r := float(a["blast"])
		# 🔴 지형 차단 (설계 ⑹ 층②, 2026-08-01) — 적 명중보다 **먼저** 본다: 벽 너머의 적을
		#   관통해 맞히면 안 된다. 표시 탄(arrow.gd)도 같은 질의를 하므로 결정론이 유지된다.
		var wall_v: Variant = _terrain_block_point(from_pos, pos)
		if wall_v != null:
			if blast_r > 0.0:
				_confirm_blast(a, wall_v as Vector2)  # 벽에 맞아도 그 자리에서 터진다(폭발탄)
			_terminate_arrow(str(a["aid"]), wall_v as Vector2)
			continue
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


# 호스트 전용 — 적 화살 전진 + **플레이어** 명중 판정. 관통 없음(첫 적중에서 소멸, 플레이어 화살 미러).
# ⚠ `_stage_over` 가드는 호출부(_physics_process)가 이미 진다 — `_on_mob_strike`와 같은 규율이다
#   (rules §2가 지적한 "G_HIT_REQ엔 그 가드가 없다"는 비대칭을 여기서 새로 만들지 않는다).
func _step_mob_arrows(delta: float) -> void:
	var survivors: Array = []
	for a: Dictionary in _mob_arrows:
		var from_pos := a["pos"] as Vector2
		var pos := from_pos + (a["dir"] as Vector2) * (float(a["speed"]) * delta)
		a["pos"] = pos
		a["life"] = float(a["life"]) - delta
		var wall_v: Variant = _terrain_block_point(from_pos, pos)
		if wall_v != null:
			_terminate_arrow(str(a["aid"]), wall_v as Vector2)
			continue
		if _mob_arrow_probe(a, pos):
			_terminate_arrow(str(a["aid"]), pos)
			continue
		if float(a["life"]) <= 0.0:
			continue  # 빗나감 — 표시 탄은 각 클라 로컬 수명으로 소멸(브로드캐스트 불필요, 플레이어 화살과 동일)
		survivors.append(a)
	_mob_arrows = survivors


# 적 화살이 이 지점에서 플레이어를 맞혔는가 — 맞았으면 데미지 확정 후 true(그 화살은 소멸).
# 🔴 **지연 보상은 잔몹 STRIKE와 완전히 같은 규약**(§3 방어자 우대): 낡은 수신 좌표와 속도로 외삽한
#   추정 좌표가 **둘 다** 판정 안일 때만 확정한다. 호스트 자신은 두 좌표가 같아 항등이다.
# 🔴 판정 반경 = `def.strike_radius` — 근접에서 "판정 반경 = 예고 표시 반경"이던 그 필드가 여기선
#   "판정 반경 = 그려진 화살 크기"다. 개념이 같아 새 필드를 만들지 않았다("맞는 곳=보이는 곳").
# 🔴 i-frame(구르기)을 반드시 본다 — 전사만 남은 지금 플레이어의 **유일한** 회피 수단이다(GDD §11).
func _mob_arrow_probe(a: Dictionary, pos: Vector2) -> bool:
	var radius := float(a["radius"])
	var dmg := int(a["damage"])
	for node: Node in get_tree().get_nodes_in_group("player"):
		var p := node as PlayerActor
		if p == null or not p.is_alive():
			continue
		if not CombatMath.is_strike_hit_lagged(
				p.net_anchor(), p.net_anchor_lead(Net.one_way_ms(p.peer_id)), pos, radius):
			continue
		if _is_iframe_active(p):
			continue  # 구르기 무적 — 잔몹/보스 예고와 같은 회피 규약
		(p.get_node("Health") as HealthComponent).apply_damage(dmg)
		return true
	return false


# 화살 한 스텝이 지형(layer 1 world)에 막혔는가 — 막혔으면 그 충돌 지점, 아니면 null.
# 🔴 **지형 차단은 호스트만 한다 — 표시 탄(`arrow.gd`)은 로컬로 질의하지 않는다**(리드 결정 2026-08-01).
#   결정론이라 게스트도 같은 지점을 계산할 수 있지만, 게스트가 **스스로 화살을 지우면** 호스트가 안
#   막은 경우에 「안 맞았는데 맞았다」가 된다 — 「보이는 것 ⊇ 판정」이 깨지는 방향이다. 그래서 소멸은
#   항상 호스트의 `G_ARROW_HIT` 통지를 따른다(플레이어 화살의 despawn 규약과 같은 쌍).
#   ⚠ 그 대가로 게스트 화면에서 화살이 벽을 편도 지연만큼 지나쳐 보일 수 있다 — **안전한 쪽의
#     어긋남**이다(보이는 것이 판정보다 넓다). 반대로 기울이지 마라.
# ⚠ 몸 레이어(2 player_body · 3 enemy_body)는 마스크에 없다 — 명중 판정은 여전히 거리 질의다
#   (물리 레이어 함정 §5 회피 + 단위 테스트 가능성 유지). 여기서 보는 것은 **지형뿐**이다.
func _terrain_block_point(from_pos: Vector2, to_pos: Vector2) -> Variant:
	if from_pos.is_equal_approx(to_pos):
		return null
	var space := get_viewport().world_2d.direct_space_state
	var q := PhysicsRayQueryParameters2D.create(from_pos, to_pos, WORLD_MASK)
	q.collide_with_areas = false
	q.collide_with_bodies = true
	var hit := space.intersect_ray(q)
	return hit["position"] as Vector2 if hit.has("position") else null


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
	# 콤보 데미지 배율은 **발사 시점에 굳어 있다**(a["combo_dmg"]) — 명중 시점에 다시 리졸브하면
	# 날아가는 동안 무기를 바꾼 발사자가 남의 배율을 얻는다(사거리는 이미 수명으로 굳어 있는 것과 대칭).
	# 넉백 방향 = **화살이 날아가던 방향**(관통 없음 = 이 화살의 마지막 방향). 세기는 발사 시 굳힌
	# 무기 무게 × 차지 레벨에서 오고, 적 저항은 여기서 곱해진다(전부 `CombatMath` 단일 소스).
	var entry_arrow := entry_v as Dictionary
	_apply_confirmed(entry_arrow["health"] as HealthComponent,
		shooter.job, int(a["shooter"]), int(a["level"]), float(a.get("combo_dmg", 1.0)),
		{"root": entry_arrow["root"], "def": entry_arrow["def"], "dir": a["dir"],
			"equip": a.get("equip"), "finish": false})


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
			# 넉백 방향 = **폭심 → 대상**(방사). 중심에 정확히 겹친 대상은 방향이 0이라 화살 진행
			# 방향으로 떨어진다 — `_push_knockback`이 0 벡터를 거부하므로 그 폴백이 필요하다.
			var blast_dir := root.global_position - center
			if blast_dir.length_squared() <= 0.000001:
				blast_dir = a["dir"] as Vector2
			# 대상별로 따로 확정 = 치명 굴림도 대상별 1회 (사용자 확정 2026-07-25)
			_apply_confirmed(health, shooter.job, int(a["shooter"]), int(a["level"]),
				float(a.get("combo_dmg", 1.0)),
				{"root": root, "def": def, "dir": blast_dir,
					"equip": a.get("equip"), "finish": false})


# 호스트 전용 — 화살 종료 통지: 게스트는 G_ARROW_HIT로, 호스트 자신은 arrow_gone_local로(릴레이 미에코). ArrowField가 despawn.
func _terminate_arrow(aid: String, pos: Vector2) -> void:
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_ARROW_HIT, "aid": aid, "x": pos.x, "y": pos.y})
	EventBus.arrow_gone_local.emit(aid, pos)


# 호스트 전용 수신 경로 — Health 권한 경로(apply_damage/부활)가 확정한 HP를 전원에 브로드캐스트
func _on_enemy_hp_confirmed(eid: String, hp: int) -> void:
	# 치명 여부는 Health가 확정 직전에 세팅한 last_crit에서 읽는다(표시 강조 전용 — 굴림은 이미 끝났다).
	var crit := false
	# 🔴 실데미지도 **같은 자리에서** 읽는다(2026-08-01) — `hp`만 보내면 게스트가 감소량으로 역산하는데
	#   그 값은 **오버킬이 잘려** 막타가 실제보다 작게 뜬다. 표시 전용이고 `cr`과 같은 근거·같은 소스다.
	var dmg := 0
	var ehp_entry: Variant = _enemies.get(eid)
	if ehp_entry != null:
		var eh := (ehp_entry as Dictionary)["health"] as HealthComponent
		crit = eh != null and eh.last_crit
		dmg = eh.last_damage if eh != null else 0
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_ENEMY_HP, "eid": eid, "hp": hp,
		"cr": 1 if crit else 0, "d": dmg})
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
	# 실데미지도 함께 — ehp "d"와 같은 근거(hp만 보내면 수신 측 역산이 오버킬에서 잘린다).
	# 🔴 **그 피어의 아바타에서 읽는다** — 확정을 만든 Health가 곧 그 노드다.
	var php_p := _peer_sync.player(peer_id)
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_PLAYER_HP, "pid": peer_id, "hp": hp,
		"d": php_p.last_damage_taken() if php_p != null else 0})
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


# 🔴 돌진(P3) 스윕 판정 — 호스트만. boss.gd가 돌진 매 프레임 emit하므로 **dash_seq로 돌진당 플레이어
# 1회** 확정한다(boss_strike의 프레임 dedup과 다른 이유 = 이동 히트박스라 매 프레임 발화·같은 돌진이
# 여러 프레임 지속). 판정 = charge_sweep_radius 원(is_strike_hit_lagged, 지연 보상은 boss_strike와 동일
# 규약). i-frame(구르기)이면 미기록 → 다음 프레임 재판정 → 구르며 반경 밖으로 빠지면 회피(§3 공정성).
func _on_boss_sweep(center: Vector2, _angle: float, pattern: BossPatternDef, dash_seq: int) -> void:
	if not Net.is_host() or _stage_over or pattern == null:
		return
	for node: Node in get_tree().get_nodes_in_group("player"):
		var p := node as PlayerActor
		if p == null or not p.is_alive():
			continue
		if int(_boss_sweep_seq.get(p.peer_id, -1)) == dash_seq:
			continue  # 이번 돌진에서 이미 이 플레이어 피격 — 매 프레임 중복 데미지 차단
		var anchor := p.net_anchor()
		var lead := p.net_anchor_lead(Net.one_way_ms(p.peer_id))
		if not CombatMath.is_strike_hit_lagged(anchor, lead, center, pattern.charge_sweep_radius):
			continue
		if _is_iframe_active(p):
			continue  # 구르기 무적 — 미기록이라 다음 프레임 재판정(반경 밖으로 빠지면 영구 회피)
		(p.get_node("Health") as HealthComponent).apply_damage(pattern.damage)
		_boss_sweep_seq[p.peer_id] = dash_seq


# 🔴 스테이지 종료 시 비행 중이던 **적** 화살을 폐기한다 (netreview ④·⑤ 2026-08-01).
# ⑴ 클리어는 사망자를 HP1로 부활시키는데(_check_clear), 그 직후 착탄한 화살이 1HP를 깎으면
#    부활하자마자 다시 죽는다 — `_stage_over` 가드가 `_physics_process`에 있어 판정은 이미 멎지만,
#    엔트리를 남겨 두면 "왜 안 맞지"를 다음 사람이 여기서 다시 유도해야 한다. 의도를 코드로 적는다.
# ⑵ 표시 탄은 각 클라 `arrow.gd`가 자기 수명으로 스스로 `queue_free`하므로(`:39-41`) 종료 통지를
#    보낼 필요가 없다 — 그래서 **좀비 화살이 화면에 남지 않는다.** 여기서 G_ARROW_HIT를 쏘면
#    오히려 종료 지점에 임팩트 연출이 뜬다(맞지도 않았는데).
# ⚠ 플레이어 화살(`_arrows`)은 건드리지 않는다 — 클리어 후에도 적을 못 때리는 것은 같지만,
#   그쪽은 폭발탄 FX가 `_confirm_blast`와 엮여 있어 별도 판단이 필요하다(현행 유지 = 기존 동작).
func _drop_mob_arrows() -> void:
	_mob_arrows.clear()


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
	_drop_mob_arrows()  # 비행 중이던 적 화살 폐기 — 아래 함수 주석이 근거
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
	_drop_mob_arrows()
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_WIPE})
	EventBus.stage_wiped.emit()  # 마을 귀환 전환은 ChapterFlow(호스트)가 결정


# 그 타수가 마무리 타인가 — ✅ **사본을 없앴다: 판단은 `CombatMath.is_combo_finish` 하나다**
#   (2026-07-29 리드 반영). 표시(`player`)와 판정(여기)이 **같은 함수**를 지나므로 "판정만 마무리"
#   (= 안 보이는데 맞는다, §3 금지 방향)가 원리적으로 불가능하다. `n > 1` 가드의 근거는 그 함수 주석이 정본.
func _is_melee_finish(equip: EquipDef, index: int) -> bool:
	return CombatMath.is_combo_finish(equip, index)


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
			# 🔴 **발사형 무기로는 근접 확정을 못 받는다 — G_SHOOT 가드의 대칭** (2026-07-27 netreview m1).
			#   G_SHOOT엔 `is_projectile_weapon` 가드가 있는데 이쪽엔 없어서, 조작 클라가 지팡이를
			#   공지한 채 G_HIT_REQ를 보내면 `attack_range` 56짜리 근접타가 그대로 확정됐다.
			#   ⚠ 선재 결함이지만 **법사 쿨다운 0.8→0.5로 스팸 허용치가 720ms → 450ms(1.6배)** 로
			#     넓어졌고, 한쪽에만 가드가 있어 **두 경로가 비대칭**이던 상태이기도 하다.
			#   🔴 `weapon_id = ""`로 떨구면 **안 된다** — 폴백이 살아나 아무것도 안 고쳐진다(G_SHOOT와
			#     같은 함정). 리졸브에 **성공한** 무기가 발사형이면 `return`이 유일한 답이다.
			#   ⚠ `weapon_def == null`(G_STATS 미도착)은 **거부하지 않는다** — 정상 창이고, 여기서
			#     막으면 접속 직후의 정당한 근접타가 조용히 사라진다. 판정 기준은 `is_projectile_weapon`
			#     단일 소스(클라의 모션 분기와 같은 기준 — 사본 조건문을 두지 마라).
			#   🔴🔴 **이 가드도 헤드리스가 겨눌 수 없다**(G_SHOOT 가드와 같은 이유 — `combat_authority.gd`는
			#     씬 글루라 `-s`가 preload 못 한다). 지워도 스위트 8종이 초록이다. 자동 방어는
			#     `test_combat_math_auto`의 `is_projectile_weapon` 전수 단정이 절반을 지키고, 나머지
			#     절반(호출부가 살아 있는가)은 **실기 확인이 유일하다**(docs/TUNING.md §10 실기 목록).
			var melee_weapon := GameState.equip_def(_peer_sync.peer_weapon_id(from_id))
			# 🔴🔴 **이 두 블록의 순서가 계약이다 — 거부 게이트가 먼저, 관대한 폴백이 나중.**
			#   (2026-07-28 netreview M-1: I-1을 넣으면서 순서를 반대로 했다가 2026-07-27 M4가 닫은
			#    구멍을 다시 열었다.) 일반형: `x = null` **뒤에** `if x != null and <거부조건>`이 오면
			#   그 거부는 **항상 꺼진다**. 폐기가 관대한 쪽이라 에러도 로그도 없다.
			#   구체적으로: 궁수가 `worn_staff`(남의 **발사형**)를 공지하면 `can_job_equip`이 false →
			#   null → 아래 발사형 거부가 통째로 건너뛰어져 **전방위 96px·초당 7.4회 근접타**가 확정됐다.
			#   ⚠ G_SHOOT `:542`는 폴백을 먼저 하고도 안 깨진다(거기 거부 게이트는 `weapon_def`가 아닌
			#     별도 조건을 본다) — **그 자리를 그대로 미러하면 여기서는 깨진다.**
			if melee_weapon != null and CombatMath.is_projectile_weapon(melee_weapon):
				return
			# 🔴 **공지 무기가 그 피어의 공지 직업이 들 수 있는 것인지 본다 — G_SHOOT `:542`와 대칭**
			#   (2026-07-28 netreview I-1). 저쪽에만 있고 이쪽엔 없던 비대칭이 이번 변경으로 **대가가
			#   커졌다**: 전에는 이 id가 "발사형 거부 여부 + 겉모습"만 정했는데, 이제 **판정 사거리
			#   (`melee_range`)와 판정 반각(`swing_arc`)까지** 정한다. `peer_sync`는 `wid`를 무필터로
			#   기록하므로, 대조가 없으면 궁수가 대검을 공지해 **궁수 쿨다운(0.15s = 초당 6.7회)으로
			#   대검 기하의 근접타**를 확정받는다.
			# ⚠ 이건 **거부가 아니라 기하 폴백이다** — null = 직업 기본 사거리 + 전방위 = 부채꼴 도입 전과
			#   항등. 그래서 위 거부 게이트 **뒤**에 있어야 맞다(거부는 이미 끝났다).
			#   ⚠ 판정 규칙은 클라의 착용 규칙과 **같은 함수**(can_job_equip)를 지난다 — 사본 금지.
			# 🔴 **거부로 null이 된 것과 「아직 모른다」는 다른 사건이다** (netreview N-2ⓐ).
			#   아래 폴백 넓힘은 **모르는 경우에만** 준다 — 안 가르면 궁수가 대검을 공지했을 때
			#   **거부의 보상으로** 수용이 84 → 160px가 된다(정직한 클라 비용 0인 구분이다).
			var weapon_known := melee_weapon != null
			if not GameState.can_job_equip(_peer_sync.peer_job_id(from_id), melee_weapon):
				melee_weapon = null
				weapon_known = true   # 알긴 아는데 못 드는 것 = 넓히지 않는다
			# 🔴 **근접 콤보 타수 — 아래 G_ATK 분기가 이미 센 값이다. 여기서 다시 세지 마라.**
			#   근거가 둘이 되면 갈라지고, 이 타수는 데미지 배율과 판정 각을 **동시에** 고르므로
			#   갈라짐이 곧 "맞는 곳 ≠ 보이는 곳"이 된다(§3).
			# ⚠ 무기가 바뀌었으면 기록된 인덱스가 새 무기의 길이를 넘을 수 있다 → 그 무기 기준으로
			#   다시 clamp한다(`authoritative_combo` 안과 **같은 함수** — 사본이 아니다).
			# ⚠ G_STATS 미도착 창이면 `melee_weapon == null`이라 `combo_len` 1 → 타수 0 = 평타 =
			#   배율 1.0 · 각 = 직업 기본. **관대한 쪽이 아니라 안전한 쪽**으로 떨어진다.
			var req_combo := CombatMath.clamp_combo_index(
				int(_melee_combo.get(from_id, 0)), melee_weapon)
			var req_finish := _is_melee_finish(melee_weapon, req_combo)
			# 🔴 **거리 판정 전용 폴백** (netreview 2026-08-02 I-3). G_STATS 미도착 창에는 무기뿐
			#   아니라 **reach 특성도 모른다**(같은 메시지다) — 그래서 호스트 수용이 `기본 × 1 × SLACK`
			#   = 84로 고정되는데 로컬은 `무기 도달 × (1+reach)`까지 뻗어 **정당한 팁 타격이 무음
			#   거부**됐다(창 + 검성 = 실측 20px 띠, **스테이지 전환마다** 재발. 창은 콤보가 필요
			#   없어 전환 직후 첫 스윙에 바로 닿는다). 이 창에서만 「그 직업이 낼 수 있는 가장 긴
			#   근접 무기」를 거리 기준으로 쓴다 — 전사 기준 84 → 160px.
			# 🔴🔴 **거리에만 쓴다 — `melee_weapon`을 통째로 바꾸지 마라.** 각(`hit_half`)·데미지
			#   배율·타수는 여전히 `melee_weapon = null` 기준(= 부채꼴 도입 전과 항등)이다. 통째로
			#   바꾸면 그 창에서 남의 무기 각·배율까지 확정받는다.
			# ⚠ **reach는 여기 안 넣는다**(그래서 인자가 그대로 `attacker.trait_value`다) — `SLACK`
			#   2.0이 이미 특성 상한(+50%)을 덮는다: 로컬 최악 `80 × 1.5 = 120` ≤ 호스트 `80 × 2 = 160`.
			#   넣으면 240px가 되어 표면만 넓어진다.
			# 🔴🔴 **남는 표면 — 리뷰가 리드의 초기 판단 둘을 정정했다** (netreview N-2, 수용 결정):
			#   ⑴ 기각된 오판: *"160px는 창 공지 208~240px보다 작으니 표면이 안 넓어진다."* **면적으로
			#      보면 반대다** — 폴백은 **전방위**(`melee_half_angle(null)` = `MELEE_FULL_ARC`)라
			#      `π·160²` ≈ **80,400px²**이고 창 공지는 반각 17°라 `½·208²·0.593` ≈ **12,800px²**,
			#      즉 **약 6배**다. 두 집합은 포함관계가 아니라 반지름 비교가 성립하지 않는다.
			#   ⑵ 기각된 오판: *"창이 200~400ms만 열린다."* **G_STATS를 아예 안 보내면 영구히 열린다**
			#      (`peer_weapon_id` = "" → `equip_def("")` = null). 창은 네트워크가 아니라 클라가 연다.
			#   🔵 **그래도 수용한다** — 그 클라는 장비 공격력·5스탯(치명/공속/피흡)·콤보 배율을 전부
			#      포기한다(`combo_len` 1 = 항상 ×1.0). 협동 2인·PvP 없음. §2 G_STATS 게이트에 등재.
			#   ⚠ 남은 값싼 레버 = 넓힘을 스폰 후 N초로 한정하는 것(정직한 클라는 1 RTT 안에 보낸다)
			#      — §2 게이트에 후보로 적어 뒀다.
			# 🔴 폴백은 `is_finish = true`로 읽는다 — `widest_melee_for_job`이 **마무리 도달로 골랐으므로**
			#   소비도 같은 기준이어야 지표와 값이 일치한다(N-1 ③). 무기를 아는 경우는 실제 타수 그대로.
			var reach_def := entry["def"] as EnemyDef
			var reach_radius := reach_def.body_radius if reach_def != null else 0.0
			# 🔴 특성(검기 파형)의 사거리 보너스도 **공격자 아바타에서** 읽는다 — 공속·치명·피흡과
			#   같은 소스다(위 _confirm_damage 주석: peer_level_stats류는 호스트 자신 항목이 없어
			#   검성 호스트가 자기 파형 사거리를 못 받고 "내 파형은 헛치는데 게스트는 맞는다"가 된다).
			#   아바타 값은 로컬=GameState 리졸브·원격=공지 id 리졸브라 신뢰 경계는 그대로다(수치 무전송).
			# 🔴 **무기 부채꼴 검증** (무기 모션 축 2026-07-28) — 사거리도 각도 이제 무기가 정한다.
			#   무기는 위에서 이미 **호스트가 자기 데이터로 리졸브한** `melee_weapon`이다(공지 id →
			#   `GameState.equip_def`). 즉 창의 긴 사거리·좁은 각은 클라 주장이 아니라 호스트 판단이고,
			#   `peer_weapon_id`가 이미 공지 직업과 대조된다(§3 직업 귀속). 신뢰 경계는 안 넓어졌다.
			# 🔴 **방향만은 클라 주장이다** — 그래도 판정이 넓어지지 않는다: 부채꼴은 같은 반경 원의
			#   부분집합이라 어떤 방향을 주장해도 **도입 전보다 좁고**, 얻는 것은 "자기 화면과 다른
			#   쪽을 때리기"뿐인데 그건 자기 화면에 헛스윙으로 보인다(협동 2인이라 남에게 피해 없음).
			#   ⚠ 방향이 없거나(구버전) 유한하지 않으면 **각 검사를 생략**한다 = 도입 전과 항등.
			#   막는 방향으로 폴백하면 접속 창·구버전에서 정당한 근접타가 조용히 사라진다(위
			#   `weapon_def == null`을 거부하지 않는 것과 같은 판단).
			var hit_dir := Vector2(float(data.get("dx", 0.0)), float(data.get("dy", 0.0)))
			var has_dir := hit_dir.is_finite() and hit_dir.length_squared() > 0.000001
			# 🔴 **마무리 타면 각이 넓어진다**(v2.2) — `EquipDef.combo_finish_arc`(절대값)를 지난다.
			#   배율이 아니라 절대값이고 상한을 `melee_half_angle`이 쥐므로 넓은 무기가 조용히 전방위가
			#   되지 않는다.
			# 🔴🔴 **각은 「주장 타수」로, 데미지는 「센 타수」로 — 두 축을 갈라야 한다** (netreview C-1
			#   2026-07-29). `req_finish`(min된 것)만 쓰면 주장과 계수가 어긋난 창에서 **호스트 콘이 로컬
			#   콘의 진부분집합**이 되어 §3 「로컬 ≤ 호스트」가 깨진다 — 로컬이 보낸 정당한 타격을 호스트가
			#   거부하고, 화면에는 **적 HP만 안 깎이는 것**으로만 나타난다. `or`로 넓은 쪽을 택하는 이유·
			#   신뢰 대가·순서 의존은 `_melee_claim` 선언부 주석이 정본이다.
			# ⚠ **데미지는 아래에서 여전히 `req_combo`(min)를 쓴다 — 그 줄을 주장으로 바꾸지 마라.**
			#   각은 표시가 있어 주장 기준으로 정렬해야 하지만, 데미지는 그려지는 것이 없어 min이 안전하다.
			# 🔴🔴 **`req_finish` 항은 수학적으로 중복이다 — 그래도 지우지 마라. 위험은 반대쪽이다.**
			#   증명(리뷰 B-1): `_melee_combo = min(clamp(claim, atk_w), counted) ≤ clamp(claim, atk_w)
			#   = _melee_claim`이고 읽기 쪽 `clamp_combo_index`도 단조, `is_combo_finish`도 index에
			#   단조이므로 **`req_finish ⟹ claim_finish`**. 즉 `or`의 값은 항상 `claim_finish`와 같다.
			#   ⚠ **"중복이니 정리한다"며 `claim_finish`를 지우고 `req_finish`만 남기면 C-1이 그대로
			#   재발한다**(정당한 마무리 타가 무음 거부된다). 지울 쪽은 `req_finish`이고, 그것도
			#   방어적 중복으로 남겨 두는 것이 옳다 — 부등식이 깨지는 변경이 오면 `or`가 받아 준다.
			var claim_finish := CombatMath.is_combo_finish(melee_weapon,
				CombatMath.clamp_combo_index(int(_melee_claim.get(from_id, 0)), melee_weapon))
			var hit_half := CombatMath.melee_half_angle(melee_weapon, req_finish or claim_finish) \
				if has_dir else CombatMath.MELEE_FULL_ARC
			var reach_equip := melee_weapon
			var reach_finish := req_finish or claim_finish
			if reach_equip == null and not weapon_known:
				reach_equip = GameState.widest_melee_for_job(_peer_sync.peer_job_id(from_id))
				reach_finish = true
			# 🔴🔴 **사거리도 각과 같이 `req or claim`이다** (netreview 2026-08-02 I-1·I-2).
			#   ⚠ **처음엔 `req_finish`만 썼다가 리뷰에서 뒤집혔다 — 그 논거를 여기 남긴다.**
			#   기각된 논거: *"각은 dx/dy를 빼면 이미 전방위라 `or`의 대가가 ≈0인데, 사거리엔 그런
			#   우회로가 없으니 주장 리졸브는 수용 반경을 84 → 168px로 새로 연다."*
			#   🔴 **거짓이다 — 우회로는 `dx`/`dy`가 아니라 「무기 id 공지」다**(§2가 이미 등재):
			#   변조 게스트가 `long_spear`를 공지하면 오늘도 수용 **208~240px**를 얻는다. `or`로 얻는
			#   최대치는 철대검 **189px**(r=0.5)라 **이미 도달 가능한 것보다 작다** = 한계 표면 불변.
			#   🔴 반대로 `req`만 쓰는 대가는 실재했다: 안전 여유가 `2·E_base − E_fin`로 **반토막**난다
			#   (철대검 42 → 21px). 마무리 타는 스스로 `combo_dash` 20px를 만들므로 릴레이에서 남는
			#   여유가 1~7px이고, 불일치 창(`advance_combo` 리셋 → claim=2 / req=0)은 지터 한 번이면
			#   생긴다. 증상은 **"궤적·타격음은 나는데 적 HP만 안 깎인다"** 로 각 축 결함과 구분되지 않는다.
			#   ✅ `or`면 여유가 `E_fin`(63 / r=0.3에서 81.9)로 **도입 전보다 넓어진다.**
			# ⚠ **데미지는 아래에서 여전히 `req_combo`(min)다 — 그 줄은 주장으로 바꾸지 마라.**
			# 🔴 **각 축의 지연 보상**(netreview C-1) — apex가 `net_anchor()`(낡은 좌표)라 이동 중인
			#   게스트는 각이 통째로 틀어진다. 거리는 anchor 하나로 묶어 두고(신뢰 경계 불변) **각만**
			#   외삽 좌표와 둘 중 하나가 맞으면 통과시킨다. §3 방어자 우대와 반대 부호인 이유는
			#   `is_hit_in_reach_lagged` 주석에 있다 — 여기선 게스트가 **공격자**다.
			# 🔴 **대상(적) 좌표의 지연분도 각 슬랙에 넣는다** (2026-07-28 netreview 2차 C-1).
			#   위 `or`는 공격자 apex만 훑는다 — 적 좌표는 두 apex가 똑같이 쓰므로 **원리적으로 못
			#   덮는다**. 호스트는 몹 실시간 좌표를 아는데 게스트 화면은 10Hz·외삽 없는 `G_MOB_POS`라
			#   낡아서, 게스트가 정당하게 맞힌 것이 거부됐다(창에서만 상시 — 각 예산이 좁다).
			var mob_lag := CombatMath.mob_lag_slack_px(Net.one_way_ms(from_id))
			if CombatMath.is_hit_in_reach_lagged(
					attacker.net_anchor(), attacker.net_anchor_lead(Net.one_way_ms(from_id)),
					(entry["root"] as Node2D).global_position, attacker.job,
					reach_radius, attacker.trait_value("reach"), reach_equip,
					hit_dir.angle(), hit_half, mob_lag, reach_finish):
					# 🔴 데미지 배율도 **확정 타수**에서 온다 — 각과 같은 인덱스라 "세게 때리는 타 = 넓게
					#   치는 타"가 데이터 한 장에서 함께 온다(`_register_arrow`의 같은 규약).
					# ⚠ **이 블록의 들여쓰기를 눈으로 맞춰라**(netreview m-1). GDScript는 주석 깊이를
					#   무시하고 **첫 statement**로 블록을 잡으므로, 위 주석이 `if`와 같은 깊이로 남아
					#   있으면 다음 사람이 그 깊이로 코드를 더했을 때 그 줄이 조용히 `if` **밖**으로
					#   빠진다 = **사거리 검증을 우회한 확정**(에러 0). 그래서 주석도 블록 깊이로 맞췄다.
					# 🔴 넉백도 **데미지와 같은 타수**(`req_combo` = min된 것)를 쓴다 — 세기는 화력
					#   축이라 각(주장 타수)이 아니라 데미지 편에 선다. 방향은 이미 온 `dx`/`dy`이고
					#   없으면(`has_dir` false = 구버전·조작 클라) 넉백만 조용히 빠진다 = 항등 폴백.
					_confirm_damage(entry["health"] as HealthComponent, attacker.job, from_id,
						CombatMath.combo_damage_mult_at(melee_weapon, req_combo),
						{} if not has_dir else {"root": entry["root"], "def": reach_def,
							"dir": hit_dir, "equip": melee_weapon, "finish": req_finish})
		NetSchema.G_ATK:
			# 🔴 **근접 콤보 타수 계수 — 호스트 전용** (v2.2 2026-07-29). 표시 중계는 `PeerSync`가 따로
			#   한다(그쪽은 연출, 여기는 **판정 입력**). 세는 소스가 G_ATK인 근거는 `_melee_combo` 주석.
			# 🔴 **새 네트워크 메시지 0개다** — 이미 매 스윙 오던 메시지의 쓰임이 바뀐 것뿐이다.
			if not Net.is_host() or _stage_over:
				return
			var atk_p := _peer_sync.player(from_id)
			if atk_p == null or not atk_p.is_alive() or atk_p.job == null:
				return  # 사망(관전 고스트)·무스폰 피어 — G_HIT_REQ·G_SHOOT 거부와 같은 규율 (rules §3)
			# 🔴🔴 **거부 게이트가 먼저, 관대한 폴백이 나중** (rules §3 · 2026-07-28 M-1이 실제로 밟은
			#   자리). 순서를 뒤집으면 `can_job_equip` 널링이 아래 발사형 거부를 **항상 꺼 버린다**.
			var atk_w := GameState.equip_def(_peer_sync.peer_weapon_id(from_id))
			if atk_w != null and CombatMath.is_projectile_weapon(atk_w):
				# 발사형을 공지한 피어의 G_ATK로는 근접 콤보를 세지 않는다 — G_HIT_REQ 근접 거부의 대칭.
				# ⚠ 안 막으면 활(3타)로 타수를 쌓아 두고 대검을 공지해 그 인덱스를 물려받는 경로가 열린다.
				return
			if not GameState.can_job_equip(_peer_sync.peer_job_id(from_id), atk_w):
				atk_w = null  # 기하·리듬 폴백(= 콤보 길이 1 = 항상 평타) — 거부가 아니다
			var now_atk := Time.get_ticks_msec()
			var last_atk := int(_last_atk_msec.get(from_id, -1000000000))
			# 🔴 규칙은 클라 로컬(`player._swing_attack`이 심는 창·간격)과 **같은 함수**를 지난다(§3) —
			#   사본 조건문을 두면 다음 리듬 튜닝에서 "내 화면은 마무리인데 판정은 평타"가 된다.
			# ⚠ 너무 빠른 스윙은 **거부가 아니라 콤보 리셋**이다(`advance_combo` 주석) — 거부로 만들면
			#   창 경계 지터에서 정당한 타격이 통째로 사라진다. 리셋이면 최악이 "이번 타는 평타"다.
			# ⚠ 공속은 **공격자 아바타**에서 읽는다(`_confirm_damage`·`_register_arrow`와 같은 소스) —
			#   `peer_level_stats`류는 호스트 자신 항목이 없다.
			_melee_combo[from_id] = CombatMath.authoritative_combo(int(data.get("cb", 0)),
				int(_melee_combo.get(from_id, 0)), float(now_atk - last_atk) / 1000.0,
				atk_p.job, atk_w, float(atk_p.level_stats.get("haste", 0.0)))
			_last_atk_msec[from_id] = now_atk
			# 🔴 **주장 타수는 따로 보관한다 — 각 축 전용**(netreview C-1). 선언부 주석이 근거 정본이다.
			#   여기서 `clamp_combo_index`를 지나므로 배열 밖·거대값·음수는 그 무기의 범위로 접힌다.
			_melee_claim[from_id] = CombatMath.clamp_combo_index(int(data.get("cb", 0)), atk_w)
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
			# 🔴 공지 무기가 **그 피어의 공지 직업이 들 수 있는 것**인지도 본다 (2026-07-26 리뷰 I-4).
			#   지금까지의 공지 스푸핑은 전부 변조 클라가 필요했는데, "전사 + 지팡이"는 **정직한 클라가
			#   상태 버그만으로** 도달했다(직업을 바꿔도 착용이 안 풀리던 것) — 재발 가능한 버그 클래스다.
			#   폐기 방향은 안전하다: ""(기본 화살) = 차지 배율도 폭발도 없음.
			#   판정 규칙은 클라의 착용 규칙과 **같은 함수**(can_job_equip)를 지난다 — 사본을 만들지 마라.
			var weapon_id := _peer_sync.peer_weapon_id(from_id)
			var weapon_def := GameState.equip_def(weapon_id)
			if not GameState.can_job_equip(_peer_sync.peer_job_id(from_id), weapon_def):
				weapon_id = ""
				weapon_def = null
			# 🔴 **발사형 무기가 아니면 발사 자체를 거부한다** (2026-07-27 netreview M4).
			#   위 대조는 "그 직업이 들 수 있는가"만 본다 — **그 무기가 쏠 수 있는 물건인가**는 안 봤다.
			#   변조 클라가 대검을 공지한 채 G_SHOOT을 쏘면 호스트가 권한 화살을 등록하고 전사 공격력으로
			#   확정한다(로컬 클라는 motion_type 분기 때문에 애초에 이 경로에 못 온다 — 호스트만 못 봤다).
			#   🔴 `weapon_id = ""`로 떨구면 **안 된다** — 그러면 리졸브 실패 폴백으로 전송 사거리(r)가 그대로
			#     살아나 아무것도 안 고쳐진다. 리졸브에 **성공한** 무기가 발사형이 아니면 return이 유일한 답이다.
			#   ⚠ `weapon_def == null`(G_STATS 미도착)은 **거부하지 않는다** — 정상 창이고 폴백이 의도된 동작이다.
			#     판정 기준은 `CombatMath.is_projectile_weapon` 단일 소스(로컬 모션 분기와 같은 기준).
			#
			# 🔴🔴 **이 가드는 헤드리스가 겨눌 수 없다 — "스위트가 그린이니 안전하다"고 읽지 마라**(verify §0).
			#   `combat_authority.gd`는 씬 전용 글루라 `-s` 테스트가 preload할 수 없다(오토로드 전역 식별자,
			#   rules §5). `boss.gd`를 못 겨눠 `test_boss_data_auto`가 **데이터만** 단정하는 것과 같은 한계다.
			#   실제로 이 `if` 두 줄을 통째로 지워도 스위트 8종이 전부 초록이다(2026-07-27 뮤테이션으로 확인).
			#   그래서 회귀 방어를 **독립된 두 층**이 나눠 진다:
			#     ⑴ `EquipDef.arrow_range` **기본값 0** — 뚫려도 clamp가 40px로 떨어뜨려 위협이 아니다.
			#     ⑵ `test_combat_math_auto` 전수 단정 — 발사형 무기가 사거리를 명시했는지 + 예측자 정확성.
			#   ⑴은 이 가드와 무관하게 성립한다. 셋 중 하나를 지울 땐 나머지가 남는지 반드시 확인해라.
			if weapon_def != null and not CombatMath.is_projectile_weapon(weapon_def):
				return
			var charge := CombatMath.clamp_charge_level(int(data.get("c", 0)))
			# ⚠ 여기서 꺼내는 것은 `step_time`(차지 단계 시간)뿐이라 사거리와 무관하다 — proj_range·combo
			#   인자는 기본값으로 둔다(넘겨도 결과가 같다). 사거리·데미지 배율은 아래 _register_arrow가
			#   한 번에 리졸브한다(단일 소스 §3 — 여기서 또 읽으면 근거가 둘이 된다).
			var step_time := float(GameState.projectile_params(weapon_id, 0.0, charge)["step_time"])
			if not CombatMath.is_charge_time_ok(last_shot, now_shot, charge, step_time, shoot_haste):
				return
			# 🔴 평타 콤보 타수 — **호스트가 직접 센다** (궁수 "평·평·쭉", 2026-07-27).
			#   G_ATK의 "cb"는 궤적만 정해 조작돼도 화면이 달라질 뿐이었지만, 이 타수는 **사거리·데미지
			#   배율을 고른다** — 매 발사에 "나 마무리 타야"를 주장하면 항상 강화살이 된다.
			#   그래서 자기 수신 간격(now-last)으로 세고, 주장(cb)은 **상한으로만** 쓴다(min).
			#   그 결과 갈라짐은 항상 "그려졌는데 안 맞는다" 쪽으로만 떨어진다(표시는 주장값을 쓴다).
			# 🔴 규칙은 클라 로컬(player._advance_shot_combo)과 **같은 함수**를 지난다 — 사본 조건문을
			#   두면 다음 리듬 튜닝에서 "내 화면은 3타인데 판정은 평타"가 된다(§3).
			# ⚠ 너무 빠른 발사는 **거부가 아니라 콤보 리셋**이다(advance_combo 주석) — 발사 자체를
			#   떨구면 창 경계 지터로 정당한 화살이 조용히 사라진다. 리셋이면 최악이 "이번 타는 평타"다.
			# ⚠ 배율·뜸 수치는 여기 안 온다 — weapon_id로 리졸브한 로컬 .tres에서만 나온다.
			var combo := CombatMath.authoritative_combo(int(data.get("cb", 0)),
				int(_shot_combo.get(from_id, 0)), float(now_shot - last_shot) / 1000.0,
				shooter.job, GameState.equip_def(weapon_id), shoot_haste)
			_shot_combo[from_id] = combo
			_last_shot_msec[from_id] = now_shot
			_register_arrow(aid_s, origin,
				Vector2(float(data.get("dx", 1.0)), float(data.get("dy", 0.0))), from_id,
				float(data.get("r", CombatMath.DEFAULT_ARROW_RANGE)), weapon_id, charge, combo)
		NetSchema.G_ENEMY_HP:
			if Net.is_host():
				return  # 호스트 상태가 원본
			if from_id != NetSchema.HOST_ID:
				return  # 권한 스푸핑 차단 — HP 확정은 호스트 발신만 신뢰 (from은 릴레이가 찍음)
			var entry_hp: Variant = _enemies.get(str(data.get("eid", "")))
			if entry_hp != null:
				# "d" = 호스트가 확정한 실데미지(표시 전용). 없으면 0 = 미상 → 글루가 hp 감소량으로
				# 폴백한다 = 구버전 호스트와 **완전 항등**(cr과 같은 규약).
				((entry_hp as Dictionary)["health"] as HealthComponent).set_hp_display(
					int(data.get("hp", 0)), int(data.get("cr", 0)) == 1, int(data.get("d", 0)))
		NetSchema.G_ROLL:
			if not Net.is_host():
				return  # 그랜트 권한은 호스트만
			var roller := _peer_sync.player(from_id)
			if roller == null or not roller.is_alive():
				return  # 사망자의 구르기 선언 무시 (rules §3)
			# 신뢰 경계(rules §3): 쿨다운 검증 통과 시에만 i-frame 창 부여 — 스팸 = 무시.
			# 수용된 한계: 조작 클라가 그랜트 창 중 공격하는 것은 막지 않는다 — naive하게 막으면
			# 정직한 "구르기 직후 공격"이 GRACE+지연 시프트로 오탐 거부된다 (2인 협동이라 실익 낮음).
			# 🔴 구르기 쿨 특성(roll_cd)도 **구른 아바타에서** 읽는다 — 사거리·공속과 같은 소스다.
			#   여기가 좁으면 곡예사/검사가 자기 화면에선 굴러지는데 무적이 안 걸린다("맞을 리 없는데
			#   맞았다") — 로컬 쿨(player)과 이 게이트가 같은 effective_roll_cooldown을 지나야 한다(§3).
			var now_roll := Time.get_ticks_msec()
			if CombatMath.is_roll_grant_ok(int(_roll_grant_msec.get(from_id, -1000000000)), now_roll,
					roller.trait_value("roll_cd")):
				_roll_grant_msec[from_id] = now_roll
		NetSchema.G_PLAYER_HP:
			if Net.is_host() or from_id != NetSchema.HOST_ID:
				return  # 플레이어 HP 확정은 호스트 발신만 신뢰 — 자기 HP도 이것만 믿는다 (rules §3)
			var pid := int(data.get("pid", 0))
			var target := _peer_sync.player(pid)
			if target != null:
				target.confirm_hp_from_net(int(data.get("hp", 0)), int(data.get("d", 0)))
			else:
				# 스폰 전 도착 — player_spawned에서 반영. ⚠ "d"는 안 들고 간다: 아직 화면에 없는
				# 아바타의 피격 숫자는 띄울 자리가 없고, 반영 시점엔 0 = 폴백이 옳다.
				_pending_php[pid] = int(data.get("hp", 0))
		NetSchema.G_STAGE_CLEAR:
			if not Net.is_host() and from_id == NetSchema.HOST_ID and not _stage_over:
				_stage_over = true
				EventBus.stage_cleared.emit()  # 부활 자체는 php가 옮긴다 — clear는 흐름/배너만
		NetSchema.G_WIPE:
			if not Net.is_host() and from_id == NetSchema.HOST_ID and not _stage_over:
				_stage_over = true
				EventBus.stage_wiped.emit()
