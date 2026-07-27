extends CharacterBody2D
# 보스 공용 — 잔몹 FSM(mob_melee)을 다패턴으로 확장. 어느 보스든 `BossDef`(patterns/frames)로 돌리는
# 데이터 주도 배우다(특정 몬스터 전용이 아니다 — 그래서 이름에 종을 박지 않는다).
# AI·판정 결정은 호스트만(rules §1·§3),
# 게스트는 mpos 수신 표시 + G_BOSS_ATK 텔레그래프 표시만. 판정·데미지 확정은 여기 없다 —
# WINDUP 만료(STRIKE) 시점을 EventBus.boss_strike로 알리면 CombatAuthority(호스트)가 확정한다.
# 수치는 전부 def(BossDef, .tres)가 쥔다 (rules §4 — "새 보스 = 파일 한 장"). 연출값만 const 예외.
# ⚠ 씬 전용 글루(오토로드 전역 식별자 사용) — -s 헤드리스 테스트에서 preload 금지 (rules §5).

const HealthComponent := preload("res://src/combat/health_component.gd")
const PlayerActor := preload("res://src/player/player.gd")
const HitStop := preload("res://src/feel/hit_stop.gd")
const HitFlash := preload("res://src/feel/hit_flash.gd")
const Flinch := preload("res://src/feel/flinch.gd")
const TELEGRAPH_SHADER := preload("res://assets/shaders/boss_telegraph.gdshader")

# 연출값 (rules §0 예외)
const REMOTE_LERP_SPEED := 12.0
const REMOTE_MOVE_EPS := 1.0      # 게스트 표시: 목표점과 이만큼 이상 벌어져 있으면 walk

# 텔레그래프 연출값 (rules §0 예외 — 사용자가 조인다, docs/TUNING.md 대상).
# 🔴 기하값(각·반지름)은 여기 없다 — 전부 BossPatternDef에서 파생한다. 여기 숫자를 늘려
# 예고를 "조금 더 크게" 만들지 마라: 그 순간 보이는 곳과 맞는 곳이 갈라진다(§3).
const TELEGRAPH_PIXEL_PX := 2.0        # 픽셀 양자화 격자(월드 px) — 16px 도트와 어울리는 계단
const TELEGRAPH_BORDER_PX := 3.0       # 테두리 두께(경계 안쪽)
# 🔴 격자 스냅 여유 = **셀 반대각선**. 표본점이 셀 중심으로 옮겨지는 최대 거리가 이 값이므로,
# 이만큼 바깥으로 관대하게 칠하면 "판정 안인데 안 칠해지는 픽셀"이 격자 모델 안에서 0이 된다.
# 격자에서 유도한다 — 독립 상수로 두면 pixel_px를 조일 때 이 보장이 조용히 깨진다.
# ⚠ **완전한 0은 아니다**: 화면 픽셀 양자화까지 넣으면 최악 위상에서 0.34px(≈0.7 화면픽셀)가
# 남는다(리뷰 실측 430만 표본). 고친 결함이 19px이라 실질 무의미하지만, "0"으로 읽고 그 위에
# 다른 보장을 쌓지 마라. 확실한 것은 **틀리는 방향이 항상 과예고**라는 쪽이다.
const TELEGRAPH_EDGE_BIAS_PX := TELEGRAPH_PIXEL_PX * 0.7071068
const TELEGRAPH_FILL := Color(0.910, 0.275, 0.110, 0.306)    # 옛 telegraph_cone.png 채움색 실측 미러
const TELEGRAPH_BORDER := Color(1.000, 0.604, 0.235, 0.729)  # 옛 telegraph_cone.png 테두리색 실측 미러
const TELEGRAPH_FILL_FADE := 0.25      # 바깥으로 갈수록 옅어지는 정도
const TELEGRAPH_PULSE_AMP := 0.10
const TELEGRAPH_PULSE_HZ := 2.2

# 추격 이탈 = aggro_range × 이 배수. 씬 스왑 프레임 유령 어그로 방지 (mob_melee와 동일 규약, rules §5).
const LEASH_MULT := 1.5

# 공격 애니 이름(=BossPatternDef.id 관례). 이 애니가 도는 동안엔 walk/idle로 덮지 않는다.
const ATTACK_ANIMS: Array[StringName] = [&"swing", &"slam", &"spray"]

# 공격 애니 speed_scale 하한 — 0/음수는 애니를 세우거나 거꾸로 돌린다. 히트스톱 정지(0.0) 판별과도 겹치지 않게.
const MIN_ANIM_SPEED_SCALE := 0.01

enum State { IDLE, CHASE, WINDUP, RECOVER }

@export var eid: String = ""
@export var def: BossDef

var _state: State = State.IDLE
var _state_left: float = 0.0
var _phase: int = 1                    # 페이즈(1→2). hp ≤ max_hp*phase2_hp_ratio 최초 도달 시 호스트가 2로.
var _prev_hp: int = 0                  # combat_impact 감소량 계산용
var _cur_pattern: BossPatternDef = null  # WINDUP 중 선택된 패턴
var _strike_center: Vector2 = Vector2.ZERO
var _strike_angle: float = 0.0
var _pattern_last_msec: Dictionary = {}  # pattern.id -> 마지막 발동 msec (호스트 전용 쿨다운 게이트)
var _swamp_seq: int = 0                # 늪 생성 로컬 id 시퀀스
var _strike_centers: Array = []        # 물뿌리기 착탄점(Vector2) — 비었으면 단일 패턴(_strike_center)
var _max_hp: int = 0                   # party_scale 적용된 max_hp (페이즈2 임계·초기 hp 단일 소스)
var _p2_swamp_accum: float = 0.0       # 페이즈2 자동 늪 생성 카운트다운(호스트 전용)
var _remote_target: Vector2 = Vector2.ZERO
var _remote_flip: bool = false
var _telegraph_left: float = 0.0       # 표시용 자동 숨김 타이머(각 클라 로컬 리졸브)
# 🔴 이번 예고의 월드 중심 — **매 물리 프레임 재주장한다**(`_reassert_telegraph_pos`). `$Telegraph`가
# Boss의 자식이라 `global_position`을 한 번만 심으면 **부모가 움직인 만큼 예고가 따라 끌려간다.**
# 호스트는 WINDUP에서 정지(velocity = ZERO)라 안 드러나지만, **게스트는 매 프레임 원격 위치로 lerp**해
# 예고가 t=0에 정확한 자리에 찍혔다가 남은 1초 내내 9~14px 어긋난 채 있다(netreview 실측: 배포 13.8px ·
# P2P 9.1px · dev_local 8.7px). 셰이더가 세운 "틀리면 과예고 방향으로만"(예산 2.83px) 보장이 **노드
# 좌표계 바깥에서** 깨지는 자리다 — 밀리는 방향이 보스 진행 방향이라 **무예고 쪽으로도** 떨어진다.
var _telegraph_center: Vector2 = Vector2.ZERO
# 이번 예고를 띄워둘 시간(초) — 호스트는 지연 보상분이 더해진 값, 게스트는 pat.telegraph_s 그대로.
# WINDUP 진입/예고 수신 때 한 번 확정해 표시·타격이 같은 값을 쓰게 한다(중간에 RTT가 흔들려도 안 갈라지게).
var _telegraph_hold_s: float = 0.0
var _anim_scale: float = 1.0           # 지금 애니에 걸려 있어야 할 speed_scale (공격 애니만 1.0이 아니다)

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _collision: CollisionShape2D = $Collision
@onready var _telegraph: Sprite2D = $Telegraph
@onready var _health: HealthComponent = $Health


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("mob")  # MobSync mpos 배치·G_BOSS_ATK 라우팅이 이 그룹으로 문다
	_remote_target = global_position
	# 🔴 예고가 끝나도 머티리얼을 떼지 않는다 — hit_flash의 "끝나면 material=null" 규율(§5)과 다른 판단이다.
	# 그 규율의 근거는 "평상시에도 그려지는 스프라이트에 셰이더가 남으면 웹 Compatibility에서 항등이
	# 아닐 수 있다"인데, 이 노드는 예고 밖에서 visible=false라 **아예 그려지지 않는다**(항등을 물을 상태가
	# 없다). 반대로 떼면 남는 것이 1×1 흰 쿼드라 혹시 visible이 살아 있는 순간엔 거대한 흰 사각이 뜬다 —
	# 붙여 두는 쪽이 안전한 방향이다. 대신 표시할 때마다 셰이더·uniform을 전부 다시 심어
	# (_apply_telegraph_geometry) 낡은 값이 남을 경로를 없앤다. N개 원은 노드째 free되므로 무관.
	_telegraph.visible = false
	if def != null:
		if def.frames != null:
			_sprite.sprite_frames = def.frames
		elif def.sprite != null:
			# 애니 없는 개체 폴백 — sprite 1장을 idle로 감싼다 (placeholder 호환)
			var sf := SpriteFrames.new()
			sf.rename_animation(&"default", &"idle")
			sf.add_frame(&"idle", def.sprite)
			_sprite.sprite_frames = sf
		# 몸 판정 반경 = def.body_radius — shape 리소스는 씬 인스턴스 간 공유라 복제 후 적용 (rules §5)
		var shape := _collision.shape.duplicate() as CircleShape2D
		if shape != null:
			shape.radius = def.body_radius
			_collision.shape = shape
		# 솔로 약화 — 인원 스케일(§3 party_scale). 호스트/게스트 같은 피어 수 → 동일 계산(표시 일치),
		# 정본 hp는 ehp라 무해. 페이즈2 임계도 이 스케일 max를 기준으로 삼는다.
		_max_hp = int(CombatMath.party_scale(float(def.max_hp), _party_size()))
		_health.setup(_max_hp, def.respawns, def.respawn_delay)
		_prev_hp = _max_hp
	_health.hp_changed.connect(_on_hp_changed)
	# 권한 경로(호스트 apply_damage)에서만 발화 — CombatAuthority가 ehp 브로드캐스트 + 클리어 판정.
	_health.hp_confirmed.connect(func(hp: int) -> void: EventBus.enemy_hp_confirmed.emit(eid, hp))
	# 물뿌리기 N개 원 텔레그래프 + 애니 = 이 구독이 그린다 (호스트/게스트 공용 단일 경로).
	EventBus.boss_spray.connect(_on_boss_spray)
	_play(&"idle")


func _on_hp_changed(hp: int, dropped: bool) -> void:
	var dead := hp <= 0
	_collision.set_deferred("disabled", dead)
	if dropped:
		var amount := _prev_hp - hp
		_prev_hp = hp
		EventBus.combat_impact.emit("enemy", global_position, maxi(amount, 0), _health.last_crit)  # 손맛 공용 훅 (crit = 표시 강조)
		if dead:
			EventBus.entity_died.emit("enemy", global_position, def.respawns)  # 사망 SFX (+ 광란 제외 판단)
		else:
			HitStop.punch(_sprite)   # 맞은 대상만 정지+스케일 튕김
			HitFlash.flash(_sprite)  # 흰색 번쩍
			var opp := Flinch.nearest_pos(global_position, get_tree().get_nodes_in_group("player"))
			Flinch.play(_sprite, global_position - opp)  # 플레이어 반대로 흠칫
	else:
		_prev_hp = hp
	# 페이즈 전이 — 호스트만 확정(로컬 페이즈). 임계는 party_scale 적용된 _max_hp 기준(솔로 정합).
	if Net.is_host() and _phase < 2 and not dead and def != null \
			and hp <= int(_max_hp * def.phase2_hp_ratio):
		_phase = 2
		_p2_swamp_accum = _auto_swamp_interval()  # 즉시 늪 방지 — 첫 자동 늪은 한 간격 뒤
		EventBus.boss_phase_changed.emit(2)  # MobSync가 G_BOSS_PHASE 중계·HUD가 배너 (표시 큐)
	if dead:
		_telegraph.visible = false
		_telegraph_left = 0.0
		velocity = Vector2.ZERO
		_state = State.IDLE
		if _has_anim(&"death"):
			visible = true
			_play(&"death")  # 시체 남김(loop=false 전제) — 없으면 숨김
		else:
			visible = false
	else:
		visible = true
		# 공격 애니가 도는 중이 아니면 idle 복귀 (피격 흠칫과 겹치지 않게)
		if not _is_attack_anim_playing():
			_play(&"idle")


func _physics_process(delta: float) -> void:
	if _telegraph_left > 0.0:
		_telegraph_left -= delta
		if _telegraph_left <= 0.0:
			_telegraph.visible = false
	_apply_anim_scale()
	if _health.is_dead() or def == null:
		_reassert_telegraph_pos()
		return
	if Net.is_host():
		_host_ai(delta)
		_update_move_anim(_state == State.CHASE and velocity.length_squared() > 0.0)
	else:
		var moving := global_position.distance_to(_remote_target) > REMOTE_MOVE_EPS
		global_position = global_position.lerp(_remote_target, minf(1.0, REMOTE_LERP_SPEED * delta))
		_sprite.flip_h = _remote_flip
		_update_move_anim(moving)
	# 🔴 **몸이 움직인 뒤에** 예고를 제자리에 다시 못 박는다 — 순서가 계약이다. 위쪽(타이머 감산 자리)에서
	# 부르면 그 프레임의 이동(_host_ai의 move_and_slide · 게스트 lerp)이 뒤따라와 한 프레임씩 밀린다.
	# `_apply_anim_scale()`이 speed_scale을 매 프레임 재주장하는 것과 같은 관용구다(rules §2 손맛 계층 —
	# "소유자가 자기 의도를 재주장한다"). 대안이던 `top_level = true`는 드로우 순서까지 바꿔 z 층
	# (바닥 -10 < 예고 -1 < 몸 0)을 눈으로 재확인해야 하므로 고르지 않았다.
	_reassert_telegraph_pos()


func _host_ai(delta: float) -> void:
	_state_left -= delta
	# 페이즈2 = 안 때려도 바닥 잠식. 상태 무관하게 주기적으로 늪 생성(솔로면 간격↑, _auto_swamp_interval).
	if _phase == 2:
		_p2_swamp_accum -= delta
		if _p2_swamp_accum <= 0.0:
			_p2_swamp_accum = _auto_swamp_interval()
			_spawn_auto_swamp()
	match _state:
		State.IDLE:
			var t := _nearest_alive_player()
			if t != null and global_position.distance_to(t.net_anchor()) <= def.aggro_range:
				_state = State.CHASE
		State.CHASE:
			var t := _nearest_alive_player()
			if t == null:
				velocity = Vector2.ZERO
				_state = State.IDLE
				return
			var anchor := t.net_anchor()
			var dist := global_position.distance_to(anchor)
			if dist > def.aggro_range * LEASH_MULT:
				velocity = Vector2.ZERO
				_state = State.IDLE  # 리시 초과 — 유령 어그로·무한 카이팅 해제
				return
			var pat := _select_pattern(dist)
			if pat != null:
				_begin_windup(pat, anchor)
				return
			# 쓸 패턴 없음 → 이동 (net_anchor 기준, rules §3).
			# keep_distance>0 = 카이팅: 너무 가까우면 물러나고, 유지 거리면 멈추고, 멀면 접근.
			var dir := Vector2.ZERO
			if def.keep_distance > 0.0:
				if dist < def.keep_distance - 12.0:
					dir = (global_position - anchor).normalized()   # 물러남
				elif dist > def.keep_distance + 40.0:
					dir = (anchor - global_position).normalized()   # 접근
			else:
				dir = (anchor - global_position).normalized()       # 추격(기본)
			velocity = dir * def.move_speed
			if dir != Vector2.ZERO:
				move_and_slide()
				_sprite.flip_h = velocity.x < 0.0
		State.WINDUP:
			if _state_left <= 0.0:
				_fire_strike()
				_state = State.RECOVER
				# 회복은 짧게(recover_s) — 재사용 쿨다운(cooldown_s)은 _pattern_last_msec가 따로 막는다.
				# 둘을 분리하지 않으면 슬램 후 쿨다운(4s)만큼 멈춰 서 "빈틈"이 생긴다.
				_state_left = _cur_pattern.recover_s if _cur_pattern != null else 0.5
		State.RECOVER:
			if _state_left <= 0.0:
				_state = State.CHASE


# 패턴 선택기 — (a) min_phase ≤ 현재 페이즈 (b) 대상 거리 ∈ [use_min_dist, use_max_dist]
# (c) 쿨다운 경과, 를 만족하는 후보 중 **priority 높은 것** 우선(거리별 역할 분리 — 가까이=평타·중간=슬램·
# 멀리=물뿌리기). 동률이면 range 작은 것. 결정적 선택 — 랜덤 없음.
func _select_pattern(dist: float) -> BossPatternDef:
	var now := Time.get_ticks_msec()
	var best: BossPatternDef = null
	for p: BossPatternDef in def.patterns:
		if p == null or p.min_phase > _phase:
			continue
		if dist < p.use_min_dist or dist > p.use_max_dist:
			continue
		var last := int(_pattern_last_msec.get(p.id, -1000000000))
		if now - last < int(p.cooldown_s * 1000.0):
			continue
		if best == null or p.priority > best.priority \
				or (p.priority == best.priority and p.range < best.range):
			best = p
	return best


# WINDUP 진입 — 판정 중심/각 확정 + 텔레그래프 표시 + 호스트 예고 브로드캐스트.
func _begin_windup(pat: BossPatternDef, anchor: Vector2) -> void:
	_cur_pattern = pat
	_state = State.WINDUP
	# 지연 보상(§3, 잔몹 mob_melee와 같은 규약): 예고가 게스트 화면에 뜨기까지 편도 지연만큼 늦으므로
	# 타격도 그만큼 늦춘다 → 게스트도 온전한 telegraph_s를 갖는다. 이 경로는 호스트 전용(보스 AI).
	_telegraph_hold_s = pat.telegraph_s + CombatMath.strike_delay_s(Net.max_remote_one_way_ms())
	_state_left = _telegraph_hold_s
	velocity = Vector2.ZERO
	_strike_angle = (anchor - global_position).angle()  # 대상 방향
	_strike_centers = []
	_sprite.flip_h = cos(_strike_angle) < 0.0
	if pat.burst_count > 1:
		# 물뿌리기 — N개 원 착탄. 호스트가 착탄점 확정 → boss_spray로 게스트 표시 중계(G_BOSS_SPRAY).
		# 개수는 솔로면 party_scale로 감소. 애니·N개 원 텔레그래프는 _on_boss_spray가 그린다(호스트/게스트 공용).
		var count := maxi(1, int(CombatMath.party_scale(float(pat.burst_count), _party_size())))
		_strike_centers = _scatter_centers(anchor, pat.burst_spread, count)
		_telegraph.visible = false  # 단일 텔레그래프 숨김 — 렌더러가 N개 원을 대신 그린다
		_telegraph_left = 0.0
		if Net.is_host():
			EventBus.boss_spray.emit(eid, pat.id, _strike_centers, _strike_angle)
		return
	if pat.shape == "cone":
		_strike_center = global_position  # apex = 보스 위치
	else:
		# 원: 대상 net_anchor 고정 — 예고를 보고 빠져나갈 수 있게 (GDD §5 기믹 원칙)
		_strike_center = anchor
	_show_telegraph_visual(pat, _strike_center, _strike_angle)
	_play_attack_anim(pat)  # 공격 애니(swing/slam) — 예고 길이에 맞춰 재생 속도를 늘린다
	if Net.is_host():
		# MobSync가 G_BOSS_ATK로 브로드캐스트 → 게스트 표시. 판정은 절대 여기서 안 한다.
		EventBus.boss_telegraph.emit(eid, pat.id, _strike_center, _strike_angle)


# STRIKE 순간 — 호스트만 판정 요청/늪 생성. 판정은 CombatAuthority(boss_strike 구독).
func _fire_strike() -> void:
	if not Net.is_host() or _cur_pattern == null:
		return
	_pattern_last_msec[_cur_pattern.id] = Time.get_ticks_msec()  # 쿨다운 게이트(호스트 전용)
	if not _strike_centers.is_empty():
		# 물뿌리기 — 착탄점마다 원 판정(기존 boss_strike 재사용, is_strike_hit N회). 겹침 중복 데미지는
		# CombatAuthority가 같은 STRIKE(물리 프레임)에서 플레이어당 1회로 dedup (rules §3 판정은 호스트).
		for c: Variant in _strike_centers:
			EventBus.boss_strike.emit(c as Vector2, 0.0, _cur_pattern)
	else:
		EventBus.boss_strike.emit(_strike_center, _strike_angle, _cur_pattern)
	if _cur_pattern.creates_swamp:
		_swamp_seq += 1
		var sid := "%s:swamp:%d" % [eid, _swamp_seq]
		# 호스트는 자기 G_SWAMP를 릴레이로 못 받으므로 로컬 스폰 (drop_spawn_local 미러).
		# 구독자 = SwampField. 튜플 = [sid, x, y, r, ttl, slow] (net_schema G_SWAMP "sw" 미러).
		EventBus.swamp_spawn_local.emit(
			[[sid, _strike_center.x, _strike_center.y,
			def.swamp_radius, def.swamp_ttl, def.swamp_slow_factor]])


# 나 포함 파티 인원 — 호스트/게스트 동일 계산(peer_ids는 자기 제외라 +1). party_scale 표시 일치의 근거.
func _party_size() -> int:
	return Net.peer_ids.size() + 1


# 페이즈2 자동 늪 간격 — 솔로면 덜 자주(간격↑). party_scale(1,solo)=solo_factor<1 → 나눠서 간격을 늘린다.
func _auto_swamp_interval() -> float:
	return def.swamp_auto_interval_p2 / CombatMath.party_scale(1.0, _party_size())


# 페이즈2 자동 늪(호스트 전용) — 안 때려도 바닥 잠식. 위치 = 랜덤 생존 플레이어 근처(없으면 보스 주변).
# swamp_spawn_local = 슬램과 동일 경로(SwampField 로컬 스폰 + G_SWAMP 브로드캐스트, sid 시퀀스 재사용).
func _spawn_auto_swamp() -> void:
	var target := _nearest_alive_player()
	var center := target.net_anchor() if target != null else global_position
	center += Vector2(randf_range(-24.0, 24.0), randf_range(-24.0, 24.0))
	_swamp_seq += 1
	var sid := "%s:swamp:%d" % [eid, _swamp_seq]
	EventBus.swamp_spawn_local.emit(
		[[sid, center.x, center.y, def.swamp_radius, def.swamp_ttl, def.swamp_slow_factor]])


# 물뿌리기 착탄점 산개(호스트 확정) — 대상 주변 spread 반경 원판 안 N개. 첫 발은 대상 위(확실한 압박),
# 나머지는 균일 랜덤 분포. 씬 전용 글루라 randf 무관(-s 아님) — 호스트가 계산해 boss_spray로 그대로 중계.
func _scatter_centers(anchor: Vector2, spread: float, count: int) -> Array:
	var centers: Array = []
	for i in count:
		if i == 0:
			centers.append(anchor)
			continue
		var ang := randf() * TAU
		var dist := sqrt(randf()) * spread  # sqrt = 균일 원판 분포 (중심 몰림 방지)
		centers.append(anchor + Vector2(cos(ang), sin(ang)) * dist)
	return centers


# 추격/조준 좌표는 표시 좌표가 아니라 net_anchor — 호스트 판정 기준과 일치 (rules §3)
func _nearest_alive_player() -> PlayerActor:
	var best: PlayerActor = null
	var best_dist := INF
	for node: Node in get_tree().get_nodes_in_group("player"):
		var p := node as PlayerActor
		if p == null or not p.is_alive():
			continue
		var d := global_position.distance_to(p.net_anchor())
		if d < best_dist:
			best_dist = d
			best = p
	return best


# --- MobSync용 API (호스트 송신 배치 / 게스트 수신 반영) — mob_melee와 동일 규약 ---

func get_sync_state() -> Array:
	return [eid, global_position.x, global_position.y, _sprite.flip_h]


func apply_remote_pos(pos: Vector2, flip: bool) -> void:
	_remote_target = pos
	_remote_flip = flip


# --- 게스트 표시 API (G_BOSS_ATK 수신 → MobSync가 호출). 판정은 절대 없다(mob_melee matk 표시 미러). ---

func show_boss_telegraph(pattern_id: String, center: Vector2, angle: float) -> void:
	var pat := _resolve_pattern(pattern_id)
	if pat == null:
		return  # 모르는 패턴 id = 무시
	_show_telegraph_visual(pat, center, angle)
	_play_attack_anim(pat)  # 공격 애니 재생 (게스트는 자기 pat.telegraph_s 길이에 맞춘다)


# 물뿌리기 N개 원 텔레그래프 + 애니 (표시 전용, 판정 절대 없음 — 그건 CombatAuthority). 호스트/게스트 공용:
# 호스트=_begin_windup의 boss_spray emit, 게스트=MobSync가 G_BOSS_SPRAY 수신 후 emit. 각자 로컬 렌더.
func _on_boss_spray(spray_eid: String, pattern_id: String, centers: Array, _angle: float) -> void:
	if spray_eid != eid:
		return  # 다른 보스(다중 보스 확장 대비) — 무시
	var pat := _resolve_pattern(pattern_id)
	if pat == null:
		return  # 모르는 패턴 id
	_play_attack_anim(pat)  # 물뿌리기 애니
	for c: Variant in centers:
		_spawn_spray_circle(pat, c as Vector2)


# 착탄점 하나에 원형 텔레그래프 스프라이트 스폰 후 telegraph_s 뒤 자동 free. 단일 Telegraph 노드로는
# N개를 못 그리므로 착탄점마다 별도 스프라이트 (기하는 _apply_telegraph_geometry 공용 — 단일 원과 같은 식).
func _spawn_spray_circle(pat: BossPatternDef, center: Vector2) -> void:
	var spr := Sprite2D.new()
	spr.z_index = -1  # 바닥(-10) 위, 몸/무기(0+) 아래 — 가려지지 않게 (rules §5)
	_apply_telegraph_geometry(spr, pat, 0.0)
	get_parent().add_child(spr)  # 스테이지 Node2D 자식 (런타임 add_child — _ready 함정 무관, rules §5)
	spr.global_position = center
	# 표시 지속 = 호스트는 지연 보상분 포함(_begin_windup 확정), 게스트는 자기 telegraph_s (단일 원과 같은 규약)
	get_tree().create_timer(_telegraph_duration(pat)).timeout.connect(
		func() -> void:
			if is_instance_valid(spr):
				spr.queue_free())


func _resolve_pattern(pattern_id: String) -> BossPatternDef:
	if def == null:
		return null
	for p: BossPatternDef in def.patterns:
		if p != null and p.id == pattern_id:
			return p
	return null


# 이번 회차의 예고 지속(초) — 단일 소스. 호스트는 _begin_windup이 지연 보상분을 더해 확정하고
# (_telegraph_hold_s), 게스트는 그 값이 0이라 자기 pat.telegraph_s를 쓴다(§3 지연 보상).
# 🔴 예고 표시 지속(단일/N개 원)과 공격 애니 길이가 **전부 이 함수에서 파생돼야** 예고와 동작이
# 같은 순간에 끝난다 — 식을 복제하면 다음 튜닝에서 표시와 모션이 갈라진다.
func _telegraph_duration(pat: BossPatternDef) -> float:
	return _telegraph_hold_s if _telegraph_hold_s > 0.0 else pat.telegraph_s


# 예고를 월드에 못 박는다 — "예고는 뜬 자리에 그대로 있다"가 회피의 전제다(§3 "맞는 곳=보이는 곳"이
# 시간축으로 확장된 것). 🔴 **`_physics_process`의 맨 끝에서만 불러라** (호출부 주석 참조).
# ⚠ 물뿌리기 N개 원은 이 함수와 무관하다 — 스테이지 자식으로 스폰돼 애초에 보스를 안 따라간다.
func _reassert_telegraph_pos() -> void:
	if _telegraph_left > 0.0:
		_telegraph.global_position = _telegraph_center


# 예고 스프라이트의 쿼드 소스 — 1×1 흰 텍스처 한 장을 모든 예고가 공유한다(단일 콘/원 + N개 원).
# 🔴 기하를 셰이더가 그리므로 텍스처는 "크기"만 준다. 1×1이면 **scale이 곧 월드 한 변**이라
# 텍스처 해상도·종횡비가 판정 정합에 끼어들 여지가 아예 없다 — 옛 결함(텍스처에 각이 박혀 데이터와
# 갈라짐)의 근본 원인 제거다. 셰이더가 이 텍스처를 곱하므로 흰색 = 정확한 항등이다.
# ⚠ **무늬를 얹으려면 코드 변경이 선행된다** — 갈아끼울 데이터 자리는 없다(`telegraph_tex` 필드는
# 2026-07-27에 제거됐다). 아트가 **정사각 풀블리드(알파 1)** 패턴을 주면 이 함수를 그 텍스처
# preload로 바꾸거나 새 필드를 판다. 🔴 **형태를 그린 텍스처는 안 된다** — 알파가 셰이더 형태를
# 다시 잘라 정합이 깨진다(그게 방금 없앤 결함이다). 형태는 언제나 코드가 정한다.
static var _quad_tex: ImageTexture = null


static func _telegraph_quad_tex() -> ImageTexture:
	if _quad_tex == null:
		var img := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_quad_tex = ImageTexture.create_from_image(img)
	return _quad_tex


# 🔴 판정 기하를 화면으로 넘기는 **유일한 지점** — "맞는 곳 = 보이는 곳" (§3).
#   원(circle)   = 중심 기준 반지름 pat.range           ≡ CombatMath.is_strike_hit
#   부채꼴(cone) = apex 기준 반지름 pat.range ∩ 전체각 2*pat.half_angle ≡ CombatMath.is_hit_in_cone
# 규약: 노드 원점 = 원 중심 / apex, 노드 회전 = facing, **균일** scale = 2*range(1×1 쿼드 → 월드 한 변).
#   셰이더는 로컬 프레임(facing = +x = 각 0)에서 판정식을 그대로 계산한다. 회전+균일스케일은
#   닮음변환이라 각·거리비가 보존된다 — 세로만 늘리는 비균일 스케일은 정원을 타원으로 만들어
#   다시 어긋나므로 절대 넣지 마라(rules §3 콘 계약이 두 번 기각한 우회로).
# ⚠ 모든 uniform을 매번 심는다(기본값 의존 금지) — Telegraph 노드는 재사용돼 콘/원을 오가므로
#   한 번이라도 안 심으면 이전 패턴의 각·반지름이 남는다.
func _apply_telegraph_geometry(spr: Sprite2D, pat: BossPatternDef, angle: float) -> void:
	var is_cone := pat.shape == "cone"
	var radius := maxf(pat.range, 0.0)
	spr.texture = _telegraph_quad_tex()
	spr.centered = true
	spr.offset = Vector2.ZERO
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.rotation = angle if is_cone else 0.0  # 원은 회전 불변 — 격자를 월드 축에 맞춰 둔다
	# 쿼드 한 변 = 지름 + 여유(격자 1칸 + 스냅 여유)의 2배. 🔴 딱 지름으로 두면 원호의 상하좌우 끝에서
	# 셀 중심이 쿼드 밖으로 나가 그 픽셀이 아예 안 그려진다(= 판정 안인데 무예고). 여유는 표시용일 뿐
	# 판정 기하가 아니다 — 셰이더는 radius_px로만 안팎을 가른다.
	var quad := 2.0 * (radius + TELEGRAPH_PIXEL_PX + TELEGRAPH_EDGE_BIAS_PX)
	spr.scale = Vector2.ONE * quad
	var mat := spr.material as ShaderMaterial
	if mat == null or mat.shader != TELEGRAPH_SHADER:
		mat = ShaderMaterial.new()
		mat.shader = TELEGRAPH_SHADER
		spr.material = mat
	mat.set_shader_parameter(&"quad_px", quad)
	mat.set_shader_parameter(&"radius_px", radius)
	# 원 = 각 제한 없음. PI를 넘기면 셰이더가 각 검사를 통째로 건너뛴다(is_strike_hit와 항등).
	mat.set_shader_parameter(&"half_angle", pat.half_angle if is_cone else PI)
	mat.set_shader_parameter(&"pixel_px", TELEGRAPH_PIXEL_PX)
	mat.set_shader_parameter(&"edge_bias_px", TELEGRAPH_EDGE_BIAS_PX)
	mat.set_shader_parameter(&"border_px", TELEGRAPH_BORDER_PX)
	mat.set_shader_parameter(&"fill_color", TELEGRAPH_FILL)
	mat.set_shader_parameter(&"border_color", TELEGRAPH_BORDER)
	mat.set_shader_parameter(&"fill_fade", TELEGRAPH_FILL_FADE)
	mat.set_shader_parameter(&"pulse_amp", TELEGRAPH_PULSE_AMP)
	mat.set_shader_parameter(&"pulse_hz", TELEGRAPH_PULSE_HZ)


# 텔레그래프 표시 — 판정 기하(range·half_angle·angle)를 셰이더에 그대로 넘긴다. "맞는 곳=보이는 곳" (§3).
# 🔴 **표시를 건너뛰는 분기는 없다.** 옛 `telegraph_tex == null` 게이트("아트 대기 = 표시 생략, 판정은
# 정상 진행")는 2026-07-27에 필드째 제거했다 — 셰이더가 텍스처 없이 그리게 된 뒤로 그 게이트는
# "데이터 한 칸을 비우면 예고가 통째로 안 보이는데 판정은 난다"(= 무예고 피격 100%)로만 남았다.
# 이 전환이 없애려던 결함 클래스 그 자체라 게이트를 두는 것이 곧 위험이었다.
func _show_telegraph_visual(pat: BossPatternDef, center: Vector2, angle: float) -> void:
	_apply_telegraph_geometry(_telegraph, pat, angle)
	_telegraph_center = center     # 매 프레임 재주장할 목표 (부모에 끌려가지 않게 — 선언부 주석)
	_telegraph.global_position = center
	_telegraph.visible = true
	# 호스트는 지연 보상분이 더해진 시간(_begin_windup에서 확정), 게스트는 자기 telegraph_s.
	# 게스트가 편도 지연만큼 늦게 시작하고 호스트가 그만큼 늦게 때리므로 양쪽 예고가 같은 순간에 끝난다.
	_telegraph_left = _telegraph_duration(pat)


# --- 애니 표시 경로 (호스트/게스트 공용 — 판정과 무관) ---

# 애니 재생. 🔴 speed_scale은 **노드 전역**이라 공격 애니에서 늘려둔 배율이 idle/walk/death에 남으면
# 다음 애니가 느려진 채 굳는다(에러 없음). 진입 경로가 여럿(_ready·_on_hp_changed 2곳·_begin_windup·
# show_boss_telegraph·_on_boss_spray·_update_move_anim)이라 호출부마다 손으로 맞추면 다음 사람이
# 빠뜨리므로, **복귀를 이 한 곳으로 모은다** — 기본 인자 1.0이 곧 복귀다(공격 애니만 값을 넘긴다).
#
# 🔴 force_restart = "같은 애니여도 처음부터". 평소 가드(`animation != anim`)는 매 프레임 오는
# _play(&"idle")이 애니를 리스타트하지 않게 막는 것인데, **공격 애니에는 그 가드가 독이다**:
# animation이 이미 그 패턴 이름으로 남아 있으면 재생이 시작되지 않아 예고 내내 이전 스윙의 마지막
# 프레임으로 얼어 있는다(에러 없음). 시트에 walk가 없는 보스에서 실제로 도달 가능하다 —
# 공격 애니가 예고를 꽉 채우게 된 뒤로는 중간에 idle/walk가 끼어들어 이름을 갈아주는 것에
# 기댈 수 없다(RECOVER의 idle·CHASE의 walk 둘뿐이고, walk가 없는 시트는 early return한다).
func _play(anim: StringName, speed_scale: float = 1.0, force_restart: bool = false) -> void:
	if not _has_anim(anim):
		return  # 없는 애니는 갈아타지 않으므로 배율도 그대로 둔다(현재 애니의 배율이 계속 맞다)
	_anim_scale = maxf(speed_scale, MIN_ANIM_SPEED_SCALE)
	if force_restart or _sprite.animation != anim:
		_sprite.play(anim)
	if force_restart:
		# 🔴 play()에만 기대지 않는다: 4.7 실측으로 play()는 **끝나 멈춘** 같은 애니를 프레임 0으로
		# 되돌리지만, **재생 중인** 같은 애니는 이어서 돈다(그러면 그 회차만 애니가 일찍 끝난다).
		# 지금은 패턴 cooldown_s가 그 경우를 막고 있을 뿐이라 데이터에 기댄 안전이다 — 명시로 못 박는다.
		_sprite.set_frame_and_progress(0, 0.0)
	_apply_anim_scale()


# 원하는 배율을 스프라이트에 심는다 — 유일한 speed_scale 대입 지점.
# ⚠ 히트스톱(src/feel/hit_stop.gd)이 맞은 스프라이트의 speed_scale을 55ms간 0으로 세우고 **무조건
# 1.0으로** 되돌린다. 그래서 ⑴ 정지(0.0) 중에는 건드리지 않고(덮으면 히트스톱이 사라진다) ⑵ 매
# 물리 프레임 다시 심는다 — 예고 중 보스를 때리면(= 거의 항상) 늘려둔 배율이 1.0으로 날아가
# 공격 애니가 다시 일찍 끝나기 때문이다(에러 없음, 화면만 어긋난다).
# ⚠ **그래서 "애니 종료 = 타격 순간"은 근사만 성립한다** — 전투 중엔 히트스톱 정지분이 누적된다
# (피격 1회당 약 −44ms. 2인이 1.2s 예고 동안 6타면 약 0.26s 늦게 끝난다). 정지 자체가 "때린 맛"이라
# 의도된 것이고, 없애려면 매 프레임 `남은 애니분 / 남은 예고시간`으로 배율을 재유도해야 하는데
# 그러면 피격마다 배속이 눈에 띄게 튄다 — **수락한 부채다**(고치려 하지 마라, 리뷰 판단 2026-07-26).
func _apply_anim_scale() -> void:
	if _sprite.speed_scale <= 0.0:
		return
	if not is_equal_approx(_sprite.speed_scale, _anim_scale):
		_sprite.speed_scale = _anim_scale


# 공격 애니 재생 — 총 재생 길이를 그 회차 예고 길이(_telegraph_duration)에 맞춘다.
# 🔴 데이터(.tres speed)로는 원리적으로 못 맞춘다: 호스트의 예고 길이는 지연 보상분
# (CombatMath.strike_delay_s)이 더해져 **RTT에 따라 가변**이라, 애니를 telegraph_s에 정확히 맞춰
# 놔도 호스트에선 그 차이만큼 계속 어긋난다. 그래서 매 회차 speed_scale로 늘린다.
# (§3 "애니 길이 ≈ telegraph_s" 미러 — 안 맞으면 보스가 휘두름을 마치고 idle 자세로 서 있다가 때린다.)
func _play_attack_anim(pat: BossPatternDef) -> void:
	var anim := StringName(pat.id)
	# force_restart = true — 같은 패턴이 연속으로 와도 반드시 처음부터 (위 _play 주석의 "얼음" 방지)
	_play(anim, _attack_speed_scale(anim, _telegraph_duration(pat)), true)


# 목표 길이에 맞춘 speed_scale = 기본 길이 / 목표 길이. 못 구하는 경우(애니 없음·프레임 0·speed 0·
# 목표 ≤ 0)는 1.0 = 항등 폴백(옛 동작).
func _attack_speed_scale(anim: StringName, target_s: float) -> float:
	var base := _anim_base_length(anim)
	if base <= 0.0 or target_s <= 0.0:
		return 1.0
	return base / target_s


# 애니 기본 재생 길이(초) = Σ프레임 duration / 애니 speed.
# ⚠ 프레임 수·speed를 코드에 박지 않는다 — sprite_frames에서 읽으므로 아트가 프레임을 늘리거나
# speed를 바꿔도 이 계산이 자동으로 따라간다. duration도 프레임별로 다를 수 있어 개수로 가정하지 않고 합산.
func _anim_base_length(anim: StringName) -> float:
	var sf := _sprite.sprite_frames
	if sf == null or not sf.has_animation(anim):
		return 0.0
	var speed := sf.get_animation_speed(anim)
	var count := sf.get_frame_count(anim)
	if speed <= 0.0 or count <= 0:
		return 0.0
	var total := 0.0
	for i in count:
		total += sf.get_frame_duration(anim, i)
	return total / speed


func _has_anim(anim: StringName) -> bool:
	return _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation(anim)


func _is_attack_anim_playing() -> bool:
	return _sprite.animation in ATTACK_ANIMS and _sprite.is_playing()


func _update_move_anim(moving: bool) -> void:
	# 공격 애니(one-shot)가 도는 동안은 덮지 않는다 — 끝나면 walk/idle로 복귀
	if _is_attack_anim_playing():
		return
	_play(&"walk" if moving else &"idle")
