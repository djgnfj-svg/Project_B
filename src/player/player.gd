extends CharacterBody2D
# 플레이어 배우 — 로컬(입력 구동) / 원격(수신 보간) 겸용.
# 자기 위치·공격 입력은 자기가 소유하고, 데미지 확정은 호스트가 한다 (rules §1·§3).
# 조작(GDD §5 v1.5): WASD 이동, 마우스 조준(2방향 플립), 좌클릭 공격, Shift 구르기.

const NetSchema := preload("res://src/core/net_schema.gd")

# 연출값 (rules §0 예외 — 사용자가 플레이하며 조인다)
const REMOTE_LERP_SPEED := 12.0
const POS_SEND_RATE := 15.0
const REMOTE_TINT := Color(1.0, 0.75, 0.75)
const ROLL_SPEED_MULT := 2.6
const ROLL_TIME := 0.25
const ROLL_COOLDOWN := 0.8
const ATTACK_FX_TIME := 0.12
const REMOTE_MAX_SPEED_MULT := 1.5  # 원격 변위 클램프 여유 — 순간이동 스푸핑 완화 (rules §3)

@export var job: JobDef

var peer_id: int = 0
var is_local: bool = false

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

@onready var _sprite: Sprite2D = $Sprite
@onready var _attack_fx: Sprite2D = $AttackFx


func _ready() -> void:
	add_to_group("player")


func setup(p_peer_id: int, p_is_local: bool, spawn_pos: Vector2) -> void:
	peer_id = p_peer_id
	is_local = p_is_local
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
		if Input.is_action_just_pressed("roll") and _roll_cd_left <= 0.0:
			_roll_dir = dir if dir != Vector2.ZERO else _aim_dir()
			_roll_time_left = ROLL_TIME
			_roll_cd_left = ROLL_COOLDOWN
	move_and_slide()
	_sprite.flip_h = get_global_mouse_position().x < global_position.x


# 공격은 폴링이 아니라 _unhandled_input — UI(Control)가 소비한 클릭은 여기 안 온다 (mouse_filter 존중)
func _unhandled_input(event: InputEvent) -> void:
	if is_local and event.is_action_pressed("attack"):
		_attack_queued = true


func _local_combat() -> void:
	var want := _attack_queued
	_attack_queued = false
	if want and _attack_cd_left <= 0.0 and _roll_time_left <= 0.0:
		_attack_cd_left = job.attack_cooldown
		var dir := _aim_dir()
		_show_attack_fx(dir)
		Net.send_game({NetSchema.KEY_KIND: NetSchema.G_ATK, "dx": dir.x, "dy": dir.y})
		# 판정: 조준 방향 원형 질의 (Area 노드 대신 즉시 질의 — 프레임 지연 없음)
		var center := global_position + dir * (job.attack_range * 0.6)
		var shape := CircleShape2D.new()
		shape.radius = job.attack_range * 0.5
		var params := PhysicsShapeQueryParameters2D.new()
		params.shape = shape
		params.transform = Transform2D(0.0, center)
		params.collision_mask = 4  # enemy_body (레이어 3) — rules §5 배정표
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
	_attack_fx.position = dir * (job.attack_range * 0.6)
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
