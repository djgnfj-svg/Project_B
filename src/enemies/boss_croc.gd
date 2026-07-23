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
		_health.setup(def.max_hp, def.respawns, def.respawn_delay)
		_prev_hp = def.max_hp
	_health.hp_changed.connect(_on_hp_changed)
	# 권한 경로(호스트 apply_damage)에서만 발화 — CombatAuthority가 ehp 브로드캐스트 + 클리어 판정.
	_health.hp_confirmed.connect(func(hp: int) -> void: EventBus.enemy_hp_confirmed.emit(eid, hp))
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
	# 페이즈 전이 — 호스트만 확정(로컬 페이즈). G_BOSS_PHASE 브로드캐스트는 슬라이스 4.
	if Net.is_host() and _phase < 2 and not dead and def != null \
			and hp <= int(def.max_hp * def.phase2_hp_ratio):
		_phase = 2
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
	if pat.shape == "cone":
		_strike_center = global_position  # apex = 보스 위치
	else:
		# 원: 대상 net_anchor 고정 — 예고를 보고 빠져나갈 수 있게 (GDD §5 기믹 원칙)
		_strike_center = anchor
	_sprite.flip_h = cos(_strike_angle) < 0.0
	_show_telegraph_visual(pat, _strike_center, _strike_angle)
	_play(StringName(pat.id))  # 공격 애니(swing/slam/spray)
	if Net.is_host():
		# MobSync가 G_BOSS_ATK로 브로드캐스트 → 게스트 표시. 판정은 절대 여기서 안 한다.
		EventBus.boss_telegraph.emit(eid, pat.id, _strike_center, _strike_angle)


# STRIKE 순간 — 호스트만 판정 요청/늪 생성. 판정은 CombatAuthority(boss_strike 구독).
func _fire_strike() -> void:
	if not Net.is_host() or _cur_pattern == null:
		return
	_pattern_last_msec[_cur_pattern.id] = Time.get_ticks_msec()  # 쿨다운 게이트(호스트 전용)
	EventBus.boss_strike.emit(_strike_center, _strike_angle, _cur_pattern)
	if _cur_pattern.creates_swamp:
		_swamp_seq += 1
		var sid := "%s:swamp:%d" % [eid, _swamp_seq]
		# 호스트는 자기 G_SWAMP를 릴레이로 못 받으므로 로컬 스폰 (drop_spawn_local 미러).
		# 구독자 = SwampField(슬라이스 2 — 지금 없어도 무해).
		EventBus.swamp_spawn_local.emit(
			[[sid, _strike_center.x, _strike_center.y, def.swamp_radius, def.swamp_ttl]])


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
