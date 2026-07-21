extends CharacterBody2D
# 플레이어 배우 — 로컬(입력 구동) / 원격(수신 보간) 겸용.
# 자기 위치는 자기가 권한을 갖고 보낸다 (rules §1 — 위치는 각자 소유, 게임 상태 확정은 호스트).

const NetSchema := preload("res://src/core/net_schema.gd")

const REMOTE_LERP_SPEED := 12.0  # 연출값(원격 보간 손맛) — 스크립트 const 허용 (rules §0)
const POS_SEND_RATE := 15.0      # 초당 위치 전송 횟수 (네트워크 부하 조절값)
const REMOTE_TINT := Color(1.0, 0.75, 0.75)  # 원격 플레이어 구분 틴트 (연출값)

@export var job: JobDef

var peer_id: int = 0
var is_local: bool = false

var _remote_target: Vector2 = Vector2.ZERO
var _send_accum: float = 0.0

@onready var _sprite: Sprite2D = $Sprite


func setup(p_peer_id: int, p_is_local: bool, spawn_pos: Vector2) -> void:
	peer_id = p_peer_id
	is_local = p_is_local
	global_position = spawn_pos
	_remote_target = spawn_pos
	if not is_local:
		_sprite.modulate = REMOTE_TINT


func _physics_process(delta: float) -> void:
	if is_local:
		var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		velocity = dir * job.move_speed
		move_and_slide()
		_send_accum += delta
		if _send_accum >= 1.0 / POS_SEND_RATE:
			_send_accum = 0.0
			Net.send_game({
				NetSchema.KEY_KIND: NetSchema.G_POS,
				"x": global_position.x,
				"y": global_position.y,
			})
	else:
		global_position = global_position.lerp(_remote_target, minf(1.0, REMOTE_LERP_SPEED * delta))


func apply_remote_pos(pos: Vector2) -> void:
	_remote_target = pos
