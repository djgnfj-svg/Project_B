extends CharacterBody2D
# 플레이어 배우 — 로컬(입력 구동) / 원격(수신 보간) 겸용.
# 자기 위치·공격 입력은 자기가 소유하고, 데미지 확정은 호스트가 한다 (rules §1·§3).
# 조작(GDD §5 v1.5): WASD 이동, 마우스 조준(2방향 플립), 좌클릭 공격, Shift 구르기.

const NetSchema := preload("res://src/core/net_schema.gd")
const HealthComponent := preload("res://src/combat/health_component.gd")

# 연출값 (rules §0 예외 — 사용자가 플레이하며 조인다)
# ⚠ 구르기 시간·쿨다운은 여기 없다 — CombatMath.ROLL_TIME_S/ROLL_COOLDOWN_S(§3 단일 소스,
#   호스트 i-frame 검증과 같은 값). 사본을 만들면 무적 창과 이동이 갈라진다.
const REMOTE_LERP_SPEED := 12.0
const POS_SEND_RATE := 15.0
const REMOTE_TINT := Color(1.0, 0.75, 0.75)
const ROLL_SPEED_MULT := 2.6
const GHOST_ALPHA := 0.4
const ATTACK_FX_DELAY := 0.07        # 예비동작이 끝나고 스윕이 시작될 때 궤적을 표시
const ATTACK_FX_TIME := 0.18         # 궤적 잔상 페이드 시간
const SWOOSH_TEX_RADIUS := 46.0      # swoosh_arc.png의 호 바깥 반지름(px) — FX 스케일 기준 (텍스처와 미러)
# ⚠ 미러(rules §3): 모든 JobDef.attack_cooldown보다 짧아야 한다 (전사 0.4s > 0.25s) —
#   원격 창-잠금 가드(play_attack_fx)가 정당한 연속 공격의 스윙을 무시하지 않으려면.
const ATTACK_ANIM_TIME := 0.25       # 무기 스윙 창 (공격 연출 길이)
const SWING_HALF_ARC := 1.9          # 스윙 호 반각(라디안) — 조준각 기준 ±이만큼 쓸고 지나간다
const WEAPON_AIM_LERP := 18.0        # 원격 조준각 보간 속도
const HOLD_DIST := 8.0               # 몸 중심 → 그립 거리 (몸에 붙지 않게 떨어뜨려 든다)
const LUNGE_DIST := 5.0              # 스윕 중 앞으로 내지르는 거리
const REMOTE_MAX_SPEED_MULT := 1.5  # 원격 변위 클램프 여유 — 순간이동 스푸핑 완화 (rules §3)
const ENEMY_BODY_MASK := 1 << 2  # 물리 레이어 3 enemy_body — rules §5 배정표가 단일 소스

@export var job: JobDef

var peer_id: int = 0
var is_local: bool = false
var scene_id: String = ""  # 소속 씬 (net_schema SCENE_*) — G_POS에 실어 다른 씬 피어의 유령 스폰 방지

var _remote_target: Vector2 = Vector2.ZERO
var _remote_flip: bool = false
var _send_accum: float = 0.0
var _attack_cd_left: float = 0.0
var _roll_time_left: float = 0.0
var _roll_cd_left: float = 0.0
var _roll_dir: Vector2 = Vector2.RIGHT
var _fx_left: float = 0.0
var _fx_delay_left: float = 0.0
var _fx_dir: Vector2 = Vector2.RIGHT
var _attack_queued: bool = false
var _last_remote_msec: int = -1
var _alive: bool = true
var _saved_layer: int = 0
var _saved_mask: int = 0
var _remote_roll_left: float = 0.0  # 원격 구르기 연출 창 (G_ROLL 수신 — 표시 전용, 판정 아님)
var _attack_anim_left: float = 0.0  # 공격 스윙 창 — 로컬은 공격 발동, 원격은 G_ATK 수신 시 (표시 전용)
var _aim_angle: float = 0.0  # 무기 조준각 — 로컬은 마우스, 원격은 _remote_aim으로 보간
var _remote_aim: float = 0.0  # G_POS "a" 수신 목표각 (표시 전용, 판정 아님)
var _remote_moving: bool = false

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _attack_fx: Sprite2D = $AttackFx
@onready var _health: HealthComponent = $Health
@onready var _weapon_pivot: Node2D = $WeaponPivot
@onready var _weapon: Sprite2D = $WeaponPivot/Weapon


func _ready() -> void:
	add_to_group("player")
	_saved_layer = collision_layer
	_saved_mask = collision_mask
	# 권한 경로(호스트의 apply_damage/confirm_hp)에서만 발화 — 게스트 표시 경로는 confirm_hp_from_net이 별도 emit
	_health.hp_confirmed.connect(_on_hp_confirmed)
	if job != null:
		_health.setup(job.max_hp)


func setup(p_peer_id: int, p_is_local: bool, spawn_pos: Vector2, p_scene_id: String) -> void:
	peer_id = p_peer_id
	is_local = p_is_local
	scene_id = p_scene_id
	global_position = spawn_pos
	_remote_target = spawn_pos
	if not is_local:
		_sprite.modulate = REMOTE_TINT
	set_job(job)


# 직업 적용 — 애니 프레임까지 교체. 원격은 G_JOB 공지 수신 시 stage가 다시 부른다.
func set_job(j: JobDef) -> void:
	if j == null:
		return
	job = j
	if j.frames != null:
		_sprite.sprite_frames = j.frames
		_sprite.play("idle")
	# 무기 = 몸과 분리된 독립 스프라이트 (장비 교체 = 텍스처 교체). 그립을 회전축에 정렬.
	_weapon.texture = j.weapon_texture
	_weapon.position = -j.weapon_grip + Vector2(HOLD_DIST, 0.0)
	_weapon_pivot.visible = j.weapon_texture != null
	if is_node_ready():
		_health.setup(j.max_hp)


func is_alive() -> bool:
	return _alive


# 호스트가 자기 로컬 플레이어의 i-frame을 직접 조회 (원격 피어는 G_ROLL 그랜트 창으로 판정)
func is_rolling() -> bool:
	return _roll_time_left > 0.0


# 게스트 수신 경로 — php 브로드캐스트 반영. 타이머 없는 표시 전용 (§3: 자기 HP도 이것만 믿는다)
func confirm_hp_from_net(p_hp: int) -> void:
	_health.set_hp_display(p_hp)
	EventBus.player_hp_confirmed.emit(peer_id, p_hp)
	_update_life_state(p_hp)


func _on_hp_confirmed(p_hp: int) -> void:
	EventBus.player_hp_confirmed.emit(peer_id, p_hp)
	_update_life_state(p_hp)


# 사망 = 관전 고스트 (GDD §5): 공격·구르기 차단, 이동은 자유(충돌 off), G_POS는 계속 송신
# (송신을 멈추면 부활 순간 원격 변위 클램프가 순간이동을 기어가는 걸로 만든다 — 앵커 연속성 유지)
func _update_life_state(p_hp: int) -> void:
	var now_alive := p_hp > 0
	if now_alive == _alive:
		return
	_alive = now_alive
	if _alive:
		collision_layer = _saved_layer
		collision_mask = _saved_mask
		_sprite.visible = true
		_sprite.modulate.a = 1.0
	else:
		collision_layer = 0
		collision_mask = 0
		_attack_fx.visible = false
		_fx_delay_left = 0.0  # 예약된 궤적도 취소 — 시체에서 스워시가 뜨지 않게
		_roll_time_left = 0.0
		_remote_roll_left = 0.0
		_attack_anim_left = 0.0  # 사망 직전 발동한 공격 스윙이 고스트에 남지 않게
		if is_local:
			_sprite.modulate.a = GHOST_ALPHA
		else:
			_sprite.visible = false


func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	if is_local:
		_local_move(delta)
		_local_combat()
		_send_pos(delta)
	else:
		_remote_moving = global_position.distance_to(_remote_target) > 1.0
		global_position = global_position.lerp(_remote_target, minf(1.0, REMOTE_LERP_SPEED * delta))
		_sprite.flip_h = _remote_flip
	_update_anim()
	_update_weapon(delta)


func _tick_timers(delta: float) -> void:
	_attack_cd_left = maxf(0.0, _attack_cd_left - delta)
	_roll_cd_left = maxf(0.0, _roll_cd_left - delta)
	_remote_roll_left = maxf(0.0, _remote_roll_left - delta)
	_attack_anim_left = maxf(0.0, _attack_anim_left - delta)
	if _fx_delay_left > 0.0:
		_fx_delay_left -= delta
		if _fx_delay_left <= 0.0:
			# 궤적 표시 — 플레이어 중심 회전, 크기는 판정 기하(§3 단일 소스)에서 파생해 "맞는 곳=보이는 곳" 유지
			var reach := CombatMath.attack_center_offset(_fx_dir, job).length() + CombatMath.attack_radius(job)
			_attack_fx.rotation = _fx_dir.angle()
			_attack_fx.position = Vector2.ZERO
			_attack_fx.scale = Vector2.ONE * (reach / SWOOSH_TEX_RADIUS)
			_attack_fx.modulate.a = 1.0
			_attack_fx.visible = true
			_fx_left = ATTACK_FX_TIME
	if _fx_left > 0.0:
		_fx_left -= delta
		_attack_fx.modulate.a = clampf(_fx_left / ATTACK_FX_TIME, 0.0, 1.0)
		if _fx_left <= 0.0:
			_attack_fx.visible = false


# 애니 상태: roll > attack > run > idle. 로컬은 자기 상태, 원격은 수신 신호(G_POS 변위·G_ROLL/G_ATK 창)로 판단.
func _update_anim() -> void:
	var next: StringName = &"idle"
	if _roll_time_left > 0.0 or _remote_roll_left > 0.0:
		next = &"roll"
	elif _attack_anim_left > 0.0 and _has_attack_anim():
		next = &"attack"
	elif (is_local and velocity.length_squared() > 1.0) or (not is_local and _remote_moving):
		next = &"run"
	if _sprite.animation != next:
		_sprite.play(next)


# 현재 미사용(어느 직업도 frames에 attack 없음) — 공격 연출은 무기 스윙(_update_weapon)이 담당.
# 몸통 attack 애니를 되살리면 애니 길이 ↔ ATTACK_ANIM_TIME 미러(rules §3)도 같이 되살릴 것.
func _has_attack_anim() -> bool:
	return _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation(&"attack")


# 무기 표시 — 조준 방향으로 내밀고, 공격 창 동안 호를 그리며 스윙 (전부 표시 전용, 판정은 별개).
func _update_weapon(delta: float) -> void:
	# 조준각은 무기 유무와 무관하게 갱신 — 무기 없는 직업도 "a"를 실제 값으로 송신해야
	# 나중에 활/지팡이 텍스처가 붙는 순간 원격 표시가 바로 맞는다 (리뷰 Minor)
	if is_local:
		_aim_angle = _aim_dir().angle()
	else:
		_aim_angle = lerp_angle(_aim_angle, _remote_aim, minf(1.0, WEAPON_AIM_LERP * delta))
	if _weapon.texture == null:
		return
	# 스윙 3박자: 예비(뒤로 젖힘) → 가속 스윕(+내지르기) → 복귀
	var swing_off := 0.0
	var lunge := 0.0
	if _attack_anim_left > 0.0:
		var t := 1.0 - _attack_anim_left / ATTACK_ANIM_TIME
		if t < 0.28:
			swing_off = -SWING_HALF_ARC * (t / 0.28)
		elif t < 0.75:
			var u := (t - 0.28) / 0.47
			u = u * u * (3.0 - 2.0 * u)  # smoothstep — 스윕에 가속감
			swing_off = lerpf(-SWING_HALF_ARC, SWING_HALF_ARC, u)
			lunge = LUNGE_DIST * sin(u * PI)
		else:
			swing_off = SWING_HALF_ARC * (1.0 - (t - 0.75) / 0.25)
	var ang := _aim_angle + swing_off
	_weapon_pivot.rotation = ang
	_weapon.position = -job.weapon_grip + Vector2(HOLD_DIST + lunge, 0.0)
	# 좌향 조준 시 뒤집기 — 안 하면 검이 거꾸로(날이 아래) 보인다. 기준은 조준각(스윙 중 깜빡임 방지)
	_weapon.flip_v = absf(wrapf(_aim_angle, -PI, PI)) > PI / 2.0
	# 위쪽 조준 = 몸 뒤(0), 아래 = 몸 앞(2) — 몸(Sprite z=1) 기준 상대 배치.
	# ⚠ 음수 z_index는 배경 타일 밑으로 꺼져 무기가 통째로 사라진다 (실기에서 확인) — 전부 0 이상 유지
	_weapon_pivot.z_index = 0 if sin(ang) < 0.0 else 2
	_weapon_pivot.visible = _alive and _roll_time_left <= 0.0 and _remote_roll_left <= 0.0


func _local_move(delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if _roll_time_left > 0.0:
		_roll_time_left -= delta
		velocity = _roll_dir * job.move_speed * ROLL_SPEED_MULT
	else:
		velocity = dir * job.move_speed
		if _alive and Input.is_action_just_pressed("roll") and _roll_cd_left <= 0.0:
			_roll_dir = dir if dir != Vector2.ZERO else _aim_dir()
			_roll_time_left = CombatMath.ROLL_TIME_S
			_roll_cd_left = CombatMath.ROLL_COOLDOWN_S
			# 구르기 선언 — 호스트가 쿨다운 검증 후 i-frame 창 부여 (방향은 연출용)
			Net.send_game({NetSchema.KEY_KIND: NetSchema.G_ROLL, "dx": _roll_dir.x, "dy": _roll_dir.y})
	move_and_slide()
	_sprite.flip_h = get_global_mouse_position().x < global_position.x


# 공격은 폴링이 아니라 _unhandled_input — UI(Control)가 소비한 클릭은 여기 안 온다 (mouse_filter 존중)
func _unhandled_input(event: InputEvent) -> void:
	if is_local and event.is_action_pressed("attack"):
		_attack_queued = true


func _local_combat() -> void:
	var want := _attack_queued
	_attack_queued = false
	if not _alive:
		return
	if want and _attack_cd_left <= 0.0 and _roll_time_left <= 0.0:
		_attack_cd_left = job.attack_cooldown
		_attack_anim_left = ATTACK_ANIM_TIME
		var dir := _aim_dir()
		_show_attack_fx(dir)
		Net.send_game({NetSchema.KEY_KIND: NetSchema.G_ATK, "dx": dir.x, "dy": dir.y})
		# 판정: 조준 방향 원형 질의 (Area 노드 대신 즉시 질의 — 프레임 지연 없음)
		# 기하는 CombatMath 단일 소스 — FX 위치(_show_attack_fx)와 같은 함수라 어긋나지 않는다
		var center := global_position + CombatMath.attack_center_offset(dir, job)
		var shape := CircleShape2D.new()
		shape.radius = CombatMath.attack_radius(job)
		var params := PhysicsShapeQueryParameters2D.new()
		params.shape = shape
		params.transform = Transform2D(0.0, center)
		params.collision_mask = ENEMY_BODY_MASK
		params.collide_with_bodies = true
		var hits := get_world_2d().direct_space_state.intersect_shape(params, 8)
		for hit: Dictionary in hits:
			var body := hit.get("collider") as Node
			if body != null and body.is_in_group("enemy"):
				EventBus.attack_hit.emit(body, job)


func _aim_dir() -> Vector2:
	var d := get_global_mouse_position() - global_position
	return d.normalized() if d.length() > 0.001 else Vector2.RIGHT


# 궤적 예약 — 스윕 타이밍(_tick_timers의 딜레이 만료)에 맞춰 표시된다
func _show_attack_fx(dir: Vector2) -> void:
	_fx_dir = dir
	_fx_delay_left = ATTACK_FX_DELAY


# 네트워크 검증용 좌표 — 원격은 lerp된 표시 좌표가 아니라 (클램프된) 최신 수신 좌표를 쓴다.
# 표시 보간 지연 때문에 호스트의 사거리 검증이 정당한 적중을 거부하는 문제 방지 (실기 진단에서 확인).
func net_anchor() -> Vector2:
	return global_position if is_local else _remote_target


# 원격 플레이어의 공격 연출 (stage가 G_ATK 수신 시 호출) — 표시 전용, 판정 아님
func play_attack_fx(dir: Vector2) -> void:
	if not _alive:
		return  # 사망자(조작 클라)의 G_ATK로 시체 위치에 FX가 뜨는 그리핑 차단
	_show_attack_fx(dir)
	_sprite.flip_h = dir.x < 0.0
	if _attack_anim_left <= 0.0:
		# 애니 창만 재수신 무시(FX·플립은 매번 적용) — G_ATK 스팸으로 애니를 영구 attack으로
		# 잠그는 그리핑 차단 (정직한 공격은 쿨다운 0.4s > 창 0.25s라 안 걸린다)
		_attack_anim_left = ATTACK_ANIM_TIME


# 원격 플레이어의 구르기 연출 (peer_sync가 G_ROLL 수신 시 호출) — 표시 전용.
# i-frame 판정은 호스트 그랜트 창(CombatAuthority)이 별도로 한다 (§3) — 이 창은 애니만 돌린다.
func play_roll_fx(dir: Vector2) -> void:
	if _remote_roll_left > 0.0:
		return  # 창 중 재수신 무시 — G_ROLL 스팸으로 애니를 영구 roll로 잠그는 그리핑 차단 (정직한 구르기는 쿨다운 0.8s > 창 0.25s라 안 걸린다)
	_remote_roll_left = CombatMath.ROLL_TIME_S
	if absf(dir.x) > 0.001:
		_remote_flip = dir.x < 0.0


func _send_pos(delta: float) -> void:
	_send_accum += delta
	if _send_accum >= 1.0 / POS_SEND_RATE:
		_send_accum = 0.0
		Net.send_game({
			NetSchema.KEY_KIND: NetSchema.G_POS,
			"s": scene_id,
			"x": global_position.x,
			"y": global_position.y,
			"f": _sprite.flip_h,
			"a": snappedf(_aim_angle, 0.01),  # 조준각 — 원격 무기 표시 전용 (판정 아님)
		})


# 원격 위치 반영 — 메시지 간 변위를 최대 이동 속도로 클램프한다.
# 호스트의 사거리 검증(§3)이 이 표시 좌표를 기준으로 하므로, 클램프 없이는 순간이동 스푸핑으로 검증이 무력화된다.
func apply_remote_pos(pos: Vector2, flip: bool, aim: float) -> void:
	# Inf/NaN 주입 가드 — JSON은 1e999 같은 오버플로를 Inf로 파싱한다. lerp_angle(유한, INF)=NaN이
	# 한 발로 _aim_angle을 영구 오염시키고, pos 쪽은 net_anchor()를 타 호스트 판정까지 닿는다 (리뷰 Important).
	if is_finite(aim):
		_remote_aim = wrapf(aim, -PI, PI)
	if not (is_finite(pos.x) and is_finite(pos.y)):
		return  # 무효 좌표는 통째로 무시 — 이전 앵커 유지
	var now := Time.get_ticks_msec()
	if _last_remote_msec >= 0:
		var dt := maxf(float(now - _last_remote_msec) / 1000.0, 1.0 / POS_SEND_RATE)
		var max_disp := job.move_speed * ROLL_SPEED_MULT * REMOTE_MAX_SPEED_MULT * dt
		var delta := pos - _remote_target
		if delta.length() > max_disp:
			pos = _remote_target + delta.normalized() * max_disp
	_last_remote_msec = now
	_remote_target = pos
	_remote_flip = flip
