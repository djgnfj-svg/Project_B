extends Area2D
# 흔들리는 지형 오브젝트 (풀·덤불·작은 나무) — 사용자 요청 2026-07-26: "나무나 지형 오브젝트가 움직여야 함".
#
# 두 가지가 겹쳐 움직인다:
#   ⑴ **상시 바람** — 아주 약한 사인파. 정지 화면이 죽어 보이지 않게 하는 것이 목적이라 진폭이 작다.
#   ⑵ **통과 반응** — 플레이어/적이 지나가면 그 방향으로 휘었다가 감쇠 진동으로 돌아온다.
#
# 🔴 **표시 전용이다 — 네트워크 메시지 0개.** 각 클라가 자기 화면의 몸(로컬·원격 아바타 전부)이
#   겹치는 것만 보고 흔든다. 호스트 확정이 필요 없다(맞히지도, 막지도 않는다).
# 🔴 **충돌 레이어를 쓰지 않는다**(collision_layer = 0) — mask로 남의 몸을 감지하기만 한다.
#   레이어를 잡으면 rules §5 배정표를 늘려야 하고, interact(7)를 재사용하면 F키 상호작용과 섞인다.
# ⚠ 밑동이 회전 피벗이다 — 스프라이트 offset을 텍스처 높이에서 런타임에 계산하므로 아트가 8px든
#   32px든 자동으로 맞는다(에셋 크기 미러 상수를 만들지 않는다).
#
# 연출값 (rules §0 예외 — 사용자가 보며 조인다).

const STIFFNESS := 62.0        # 원위치로 돌아오려는 힘(클수록 빳빳)
const DAMPING := 6.5           # 감쇠(클수록 빨리 멎는다)
const PUSH_IMPULSE := 5.2      # 통과 순간 받는 각속도
const MAX_ANGLE := 0.42        # 휘는 각 상한(rad) — 넘으면 뽑힌 것처럼 보인다
const WIND_AMP := 0.035        # 상시 바람 진폭(rad)
const WIND_SPEED := 1.15       # 상시 바람 속도
const BODY_MASK := (1 << 1) | (1 << 2)  # player_body(2) + enemy_body(3) — rules §5 배정표가 단일 소스

@export var sprite_texture: Texture2D  # 이 오브젝트의 겉모습(풀/덤불/나무). 씬 인스턴스마다 교체 가능
@export var wind_phase: float = 0.0    # 바람 위상 오프셋 — 같은 값이면 숲 전체가 한 몸처럼 흔들린다

var _angle: float = 0.0
var _vel: float = 0.0
var _wind_t: float = 0.0
var _inside: Array[Node2D] = []  # 겹쳐 있는 몸들 — 나갈 때 한 번 더 밀어 주려고 들고 있는다

@onready var _sprite: Sprite2D = $Sprite


func _ready() -> void:
	collision_layer = 0        # 아무에게도 안 잡힌다 — 감지만 한다
	collision_mask = BODY_MASK
	monitorable = false        # 남이 나를 질의할 일이 없다(불필요한 브로드페이즈 비용 제거)
	_wind_t = wind_phase
	if sprite_texture != null:
		_sprite.texture = sprite_texture
	# 회전 피벗을 밑동으로 — Sprite2D는 기본 centered라 offset을 위로 올려 원점이 바닥에 오게 한다.
	if _sprite.texture != null:
		_sprite.offset = Vector2(0.0, -float(_sprite.texture.get_height()) * 0.5)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


# 지나간 몸이 남긴 충격 — 몸이 오브젝트의 어느 쪽에 있느냐로 휘는 방향이 갈린다.
func _push_from(body: Node2D) -> void:
	if body == null or not is_instance_valid(body):
		return
	var side := signf(body.global_position.x - global_position.x)
	if side == 0.0:
		side = 1.0
	# 밀고 들어온 쪽 **반대로** 휜다(몸이 왼쪽에 있으면 오른쪽으로 눕는다)
	_vel += -side * PUSH_IMPULSE


func _on_body_entered(body: Node2D) -> void:
	_inside.append(body)
	_push_from(body)


func _on_body_exited(body: Node2D) -> void:
	_inside.erase(body)
	_push_from(body)  # 빠져나갈 때 한 번 더 — 스치고 지나가는 느낌이 살아난다


func _process(delta: float) -> void:
	_wind_t += delta * WIND_SPEED
	# 감쇠 스프링 — 통과 충격이 0으로 잦아든다
	_vel += (-STIFFNESS * _angle - DAMPING * _vel) * delta
	_angle = clampf(_angle + _vel * delta, -MAX_ANGLE, MAX_ANGLE)
	# 겹쳐 서 있는 동안은 계속 눌려 있게 — 안 그러면 위에 서 있는데 풀이 똑바로 선다
	if not _inside.is_empty():
		var body := _inside[0]
		if is_instance_valid(body):
			var side := signf(body.global_position.x - global_position.x)
			_vel += -side * PUSH_IMPULSE * 0.9 * delta
		else:
			_inside.remove_at(0)
	_sprite.rotation = _angle + sin(_wind_t) * WIND_AMP
