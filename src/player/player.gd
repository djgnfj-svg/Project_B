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
const ATTACK_FX_TIME := 0.12
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
var _attack_queued: bool = false
var _last_remote_msec: int = -1
var _alive: bool = true
var _saved_layer: int = 0
var _saved_mask: int = 0

@onready var _sprite: Sprite2D = $Sprite
@onready var _attack_fx: Sprite2D = $AttackFx
@onready var _health: HealthComponent = $Health


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


# 직업 적용 — 스프라이트까지 교체. 원격은 G_JOB 공지 수신 시 stage가 다시 부른다.
func set_job(j: JobDef) -> void:
	if j == null:
		return
	job = j
	if j.sprite != null:
		_sprite.texture = j.sprite
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
		_roll_time_left = 0.0
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
		global_position = global_position.lerp(_remote_target, minf(1.0, REMOTE_LERP_SPEED * delta))
		_sprite.flip_h = _remote_flip


func _tick_timers(delta: float) -> void:
	_attack_cd_left = maxf(0.0, _attack_cd_left - delta)
	_roll_cd_left = maxf(0.0, _roll_cd_left - delta)
	if _fx_left > 0.0:
		_fx_left -= delta
		if _fx_left <= 0.0:
			_attack_fx.visible = false


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


func _show_attack_fx(dir: Vector2) -> void:
	_attack_fx.rotation = dir.angle()
	_attack_fx.position = CombatMath.attack_center_offset(dir, job)
	_attack_fx.visible = true
	_fx_left = ATTACK_FX_TIME


# 네트워크 검증용 좌표 — 원격은 lerp된 표시 좌표가 아니라 (클램프된) 최신 수신 좌표를 쓴다.
# 표시 보간 지연 때문에 호스트의 사거리 검증이 정당한 적중을 거부하는 문제 방지 (실기 진단에서 확인).
func net_anchor() -> Vector2:
	return global_position if is_local else _remote_target


# 원격 플레이어의 공격 연출 (stage가 G_ATK 수신 시 호출)
func play_attack_fx(dir: Vector2) -> void:
	_show_attack_fx(dir)
	_sprite.flip_h = dir.x < 0.0


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
		})


# 원격 위치 반영 — 메시지 간 변위를 최대 이동 속도로 클램프한다.
# 호스트의 사거리 검증(§3)이 이 표시 좌표를 기준으로 하므로, 클램프 없이는 순간이동 스푸핑으로 검증이 무력화된다.
func apply_remote_pos(pos: Vector2, flip: bool) -> void:
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
