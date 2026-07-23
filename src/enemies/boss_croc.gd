extends CharacterBody2D
# 보스(악어) — 잔몹 FSM(mob_melee)을 다패턴으로 확장. AI·판정 결정은 호스트만(rules §1·§3),
# 게스트는 mpos 수신 표시 + G_BOSS_ATK 텔레그래프 표시만. 판정·데미지 확정은 여기 없다 —
# WINDUP 만료(STRIKE) 시점을 EventBus.boss_strike로 알리면 CombatAuthority(호스트)가 확정한다.
# 수치는 전부 def(BossDef, .tres)가 쥔다 (rules §4 — "새 보스 = 파일 한 장"). 연출값만 const 예외.
# ⚠ 씬 전용 글루(오토로드 전역 식별자 사용) — -s 헤드리스 테스트에서 preload 금지 (rules §5).

const HealthComponent := preload("res://src/combat/health_component.gd")
const PlayerActor := preload("res://src/player/player.gd")
const HitStop := preload("res://src/feel/hit_stop.gd")
const HitFlash := preload("res://src/feel/hit_flash.gd")
const Flinch := preload("res://src/feel/flinch.gd")

# 연출값 (rules §0 예외)
const REMOTE_LERP_SPEED := 12.0
const REMOTE_MOVE_EPS := 1.0      # 게스트 표시: 목표점과 이만큼 이상 벌어져 있으면 walk

# 추격 이탈 = aggro_range × 이 배수. 씬 스왑 프레임 유령 어그로 방지 (mob_melee와 동일 규약, rules §5).
const LEASH_MULT := 1.5

# 공격 애니 이름(=BossPatternDef.id 관례). 이 애니가 도는 동안엔 walk/idle로 덮지 않는다.
const ATTACK_ANIMS: Array[StringName] = [&"swing", &"slam", &"spray"]

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

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _collision: CollisionShape2D = $Collision
@onready var _telegraph: Sprite2D = $Telegraph
@onready var _health: HealthComponent = $Health


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("mob")  # MobSync mpos 배치·G_BOSS_ATK 라우팅이 이 그룹으로 문다
	_remote_target = global_position
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
		EventBus.combat_impact.emit("enemy", global_position, maxi(amount, 0))  # 손맛 공용 훅
		if dead:
			EventBus.entity_died.emit("enemy", global_position)  # 사망 SFX
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
	if _health.is_dead() or def == null:
		return
	if Net.is_host():
		_host_ai(delta)
		_update_move_anim(_state == State.CHASE and velocity.length_squared() > 0.0)
	else:
		var moving := global_position.distance_to(_remote_target) > REMOTE_MOVE_EPS
		global_position = global_position.lerp(_remote_target, minf(1.0, REMOTE_LERP_SPEED * delta))
		_sprite.flip_h = _remote_flip
		_update_move_anim(moving)


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
			# 쓸 패턴 없음 → 계속 추격 (net_anchor 기준, rules §3)
			velocity = (anchor - global_position).normalized() * def.move_speed
			move_and_slide()
			_sprite.flip_h = velocity.x < 0.0
		State.WINDUP:
			if _state_left <= 0.0:
				_fire_strike()
				_state = State.RECOVER
				_state_left = _cur_pattern.cooldown_s if _cur_pattern != null else 1.0
		State.RECOVER:
			if _state_left <= 0.0:
				_state = State.CHASE


# 패턴 선택기 — (a) min_phase ≤ 현재 페이즈 (b) 대상 거리 ∈ [use_min_dist, use_max_dist]
# (c) 쿨다운 경과, 를 만족하는 후보 중 근접형 우선(range 작은 것). 결정적 선택 — 랜덤 없음.
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
		if best == null or p.range < best.range:
			best = p  # 근접형(작은 range) 우선 — 붙으면 부채꼴 평타부터
	return best


# WINDUP 진입 — 판정 중심/각 확정 + 텔레그래프 표시 + 호스트 예고 브로드캐스트.
func _begin_windup(pat: BossPatternDef, anchor: Vector2) -> void:
	_cur_pattern = pat
	_state = State.WINDUP
	_state_left = pat.telegraph_s
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
	_play(StringName(pat.id))  # 공격 애니(swing/slam)
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
	_play(StringName(pat.id))  # 공격 애니 재생


# 물뿌리기 N개 원 텔레그래프 + 애니 (표시 전용, 판정 절대 없음 — 그건 CombatAuthority). 호스트/게스트 공용:
# 호스트=_begin_windup의 boss_spray emit, 게스트=MobSync가 G_BOSS_SPRAY 수신 후 emit. 각자 로컬 렌더.
func _on_boss_spray(spray_eid: String, pattern_id: String, centers: Array, _angle: float) -> void:
	if spray_eid != eid:
		return  # 다른 보스(다중 보스 확장 대비) — 무시
	var pat := _resolve_pattern(pattern_id)
	if pat == null:
		return  # 모르는 패턴 id
	_play(StringName(pattern_id))  # 물뿌리기 애니
	if pat.telegraph_tex == null:
		return  # 아트 대기 — 애니만, 원 표시 생략 (판정 타이밍은 정상 진행)
	for c: Variant in centers:
		_spawn_spray_circle(pat, c as Vector2)


# 착탄점 하나에 원형 텔레그래프 스프라이트 스폰 후 telegraph_s 뒤 자동 free. 단일 Telegraph 노드로는
# N개를 못 그리므로 착탄점마다 별도 스프라이트 (판정 반경 = range → 스케일, "맞는 곳=보이는 곳" §3).
func _spawn_spray_circle(pat: BossPatternDef, center: Vector2) -> void:
	var spr := Sprite2D.new()
	spr.texture = pat.telegraph_tex
	spr.centered = true
	spr.z_index = -1  # 바닥(-10) 위, 몸/무기(0+) 아래 — 가려지지 않게 (rules §5)
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var tex_w := maxf(float(pat.telegraph_tex.get_width()), 1.0)
	spr.scale = Vector2.ONE * (pat.range * 2.0 / tex_w)  # 원: 지름 = range*2 (텔레그래프 반경=판정 반경)
	get_parent().add_child(spr)  # 스테이지 Node2D 자식 (런타임 add_child — _ready 함정 무관, rules §5)
	spr.global_position = center
	get_tree().create_timer(pat.telegraph_s).timeout.connect(
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


# 텔레그래프 표시 — 형태별 텍스처를 판정 기하(range·angle)에 맞춰 스케일/회전. "맞는 곳=보이는 곳" (§3).
# telegraph_tex가 null(아트 대기)이면 표시만 건너뛴다 — 판정 타이밍은 정상 진행(placeholder).
func _show_telegraph_visual(pat: BossPatternDef, center: Vector2, angle: float) -> void:
	if pat.telegraph_tex == null:
		_telegraph.visible = false
		_telegraph_left = 0.0
		return
	_telegraph.texture = pat.telegraph_tex
	_telegraph.global_position = center
	var tex_w := maxf(float(pat.telegraph_tex.get_width()), 1.0)
	var tex_h := float(pat.telegraph_tex.get_height())
	if pat.shape == "cone":
		# 부채꼴 텍스처 = 우향(+x) 수평·apex가 좌측 중앙. 원점을 apex에 맞추고 회전.
		_telegraph.centered = false
		_telegraph.offset = Vector2(0.0, -tex_h * 0.5)
		_telegraph.rotation = angle
		_telegraph.scale = Vector2.ONE * (pat.range / tex_w)  # 텍스처 길이 → 사거리
	else:
		# 원 텍스처 = 지름 tex_w. 중심 정렬, 지름 = range*2.
		_telegraph.centered = true
		_telegraph.offset = Vector2.ZERO
		_telegraph.rotation = 0.0
		_telegraph.scale = Vector2.ONE * (pat.range * 2.0 / tex_w)
	_telegraph.visible = true
	_telegraph_left = pat.telegraph_s


# --- 애니 표시 경로 (호스트/게스트 공용 — 판정과 무관) ---

func _play(anim: StringName) -> void:
	if _has_anim(anim) and _sprite.animation != anim:
		_sprite.play(anim)


func _has_anim(anim: StringName) -> bool:
	return _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation(anim)


func _is_attack_anim_playing() -> bool:
	return _sprite.animation in ATTACK_ANIMS and _sprite.is_playing()


func _update_move_anim(moving: bool) -> void:
	# 공격 애니(one-shot)가 도는 동안은 덮지 않는다 — 끝나면 walk/idle로 복귀
	if _is_attack_anim_playing():
		return
	_play(&"walk" if moving else &"idle")
