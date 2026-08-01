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
# ⚠ 밑동이 흔들림의 기준점이다 — 스프라이트 offset을 텍스처 높이에서 런타임에 계산하므로 아트가
#   8px든 32px든 자동으로 맞는다(에셋 크기 미러 상수를 만들지 않는다).
#
# 🔴 **물리는 각(rad)으로 풀고 그리기는 픽셀 시어로 한다 — 둘을 헷갈리지 마라** (2026-08-01).
#   스프링·통과 충격·상한은 전부 `_angle`(라디안)에서 돌고, 마지막 한 줄에서만
#   우듬지 변위 = 높이 × sin(각) 으로 바꿔 셰이더에 넘긴다. `Sprite2D.rotation`은 **더 이상 쓰지 않는다**
#   — 각도 회전은 리샘플이 매 프레임 달라져 픽셀아트 윤곽이 끓었다(근거는 `foliage_sway.gdshader`).
#
# 연출값 (rules §0 예외 — 사용자가 보며 조인다).

const STIFFNESS := 62.0        # 원위치로 돌아오려는 힘(클수록 빳빳)
const DAMPING := 6.5           # 감쇠(클수록 빨리 멎는다)
const PUSH_IMPULSE := 5.2      # 통과 순간 받는 각속도
const MAX_ANGLE := 0.42        # 휘는 각 상한(rad) — 넘으면 뽑힌 것처럼 보인다
const BODY_MASK := (1 << 1) | (1 << 2)  # player_body(2) + enemy_body(3) — rules §5 배정표가 단일 소스

# ── 상시 바람 (사용자 요청 2026-08-01: "나무 움직이는 애니메이션좀 넣어줘")
# 배선은 2026-07-26부터 있었지만 진폭이 0.035rad(2.0°)라 **실기에서 사실상 안 보였다** —
# 나무 높이 60px에서 우듬지가 ±2.1px, 그마저 픽셀 격자에 스냅되어 한 칸 깜빡이는 수준이었다.
# 세 가지를 겹쳐 "안 움직인다"를 뗀다:
#   ⑴ 진폭 상향 — 2.0° → 5.2°(우듬지 ±5.4px). 기준점이 밑동이라 **큰 개체일수록 끝이 더 움직인다**.
#   ⑵ 2차 파 — 주기가 어긋난 사인을 겹친다. 사인 하나면 왕복이 규칙적이라 메트로놈처럼 보인다.
#   ⑶ 돌풍 — 아주 느린 파가 진폭 전체를 변조하고, **위상을 x 좌표에서 유도**해 바람이 숲을
#      왼쪽에서 오른쪽으로 훑고 지나간다. 개체마다 무작위 위상이면 제각각 떨려 비가 오는 것처럼 보인다.
const WIND_AMP := 0.09         # 상시 바람 기본 진폭(rad)
const WIND_SPEED := 1.15       # 상시 바람 기본 속도
const WIND_AMP2 := 0.42        # 2차 파 진폭(1차 대비)
const WIND_SPEED2 := 2.37      # 2차 파 속도 배수 — 1차와 정수비를 피해야 합성 주기가 길어진다
const GUST_PERIOD := 7.3       # 돌풍 한 번의 주기(초)
const GUST_DEPTH := 0.45       # 돌풍 깊이 — 진폭이 (1−이 값)~(1+이 값) 배로 오간다
const GUST_WAVE_LEN := 420.0   # 돌풍이 한 파장을 도는 가로 거리(px) — 작을수록 훑는 게 빨라 보인다

# 개체 크기별 속도 — 큰 나무는 느리고 묵직하게, 작은 풀은 잘게 떤다.
# ⚠ 기준 높이는 **가장 작은 장식(32px)** 이고 실제 높이는 텍스처에서 읽는다 —
#   `_ready`의 피벗 계산과 같은 이유로 에셋 크기 미러 상수를 만들지 않는다.
const SIZE_REF_H := 32.0
const SIZE_SPEED_MIN := 0.5    # 아무리 커도 이보다 느려지진 않는다(멈춘 것처럼 보인다)
const SIZE_SPEED_MAX := 1.25

# 접지 그림자 (사용자 지적 2026-08-01: "나무 등 오브젝트가 그림자가 없네?").
# 🔴 **그림자는 픽셀로 찍지 않는다** — 공용 `shadow.png` 한 장을 코드가 크기만 맞춘다.
#   `mob_melee._fit_shadow()`와 같은 관용구이고 이유도 같다: 아트를 다시 그려도 자동으로 맞아서
#   **텍스처 크기 미러 상수가 안 생긴다**. 잔몹은 `body_radius`(판정)에서 폭을 유도하지만 폴리지엔
#   판정이 없으므로 **스프라이트 폭**에서 유도한다 → 나무(64)는 크고 풀(32)은 작은 그림자가 자동.
# ⚠ **z는 폴리지보다 아래여야 한다.** 씬에서 Shadow의 z_index = −1(상대) → 절대 **−4**.
#   잔몹·플레이어 그림자(−2)를 그대로 베끼면 폴리지(−3)보다 **위**라 그림자가 나무 몸통에 뜬다.
# ⚠ 그림자는 흔들리지 않는다 — 시어 셰이더가 `Sprite`에만 붙으므로 별도 노드인 그림자는 제자리다(의도).
const SHADOW_WIDTH_MULT := 0.8  # 그림자 폭 = 스프라이트 폭 × 이 배수
# 🔴 **텍스처가 `shadow_prop.png`(장식 전용)다 — 공용 `shadow.png`가 아니다.**
#   공용 쪽은 alpha 최대 **94/255**라 modulate를 1.0(최대)로 올려도 그 이상 진해질 수 없다.
#   처음에 공용 텍스처 + 0.26으로 뒀다가 실효 alpha 24 = 캐릭터 그림자의 1/4이 되어
#   **"그림자가 너무 안 보임"** 신고를 받았다(사용자, 2026-08-01). 배수만 올려선 한계에 부딪혀
#   알파를 2.2배 증폭한 전용 텍스처를 따로 만들었다.
# ⚠ **공용 `shadow.png`를 진하게 고치지 마라** — 플레이어·잔몹·보스 그림자가 전부 같이 바뀐다.
const SHADOW_ALPHA := 0.9

const SWAY_SHADER := preload("res://assets/shaders/foliage_sway.gdshader")
const SWAY_PARAM := &"sway_px"

@export var sprite_texture: Texture2D  # 이 오브젝트의 겉모습(풀/덤불/나무). 씬 인스턴스마다 교체 가능
@export var wind_phase: float = 0.0    # 바람 위상 오프셋 — 같은 값이면 숲 전체가 한 몸처럼 흔들린다

var _angle: float = 0.0
var _vel: float = 0.0
var _wind_t: float = 0.0
var _wind_speed: float = WIND_SPEED  # 개체 높이에서 유도(_ready)
var _gust_t: float = 0.0
var _gust_phase: float = 0.0         # 이 개체가 돌풍 파에서 차지하는 자리 — x 좌표에서 유도
var _sway_h: float = 32.0            # 각 → 우듬지 변위(px) 환산에 쓰는 높이
var _mat: ShaderMaterial
var _inside: Array[Node2D] = []  # 겹쳐 있는 몸들 — 나갈 때 한 번 더 밀어 주려고 들고 있는다

@onready var _sprite: Sprite2D = $Sprite
@onready var _shadow: Sprite2D = $Shadow


func _ready() -> void:
	collision_layer = 0        # 아무에게도 안 잡힌다 — 감지만 한다
	collision_mask = BODY_MASK
	monitorable = false        # 남이 나를 질의할 일이 없다(불필요한 브로드페이즈 비용 제거)
	_wind_t = wind_phase
	if sprite_texture != null:
		_sprite.texture = sprite_texture
	# 밑동을 원점으로 — Sprite2D는 기본 centered라 offset을 위로 올려 노드 원점이 바닥에 오게 한다.
	if _sprite.texture != null:
		var h := float(_sprite.texture.get_height())
		_sprite.offset = Vector2(0.0, -h * 0.5)
		_sway_h = h
		# 큰 개체일수록 느리게 — 관성이 큰 것처럼 보인다. 제곱근이라 크기 차가 4배여도 속도는 2배 차.
		if h > 0.0:
			_wind_speed = WIND_SPEED * clampf(sqrt(SIZE_REF_H / h), SIZE_SPEED_MIN, SIZE_SPEED_MAX)
	# 개체마다 흔들리는 양이 달라야 하므로 머티리얼도 개체마다 하나다(공유하면 전부 같이 눕는다).
	_mat = ShaderMaterial.new()
	_mat.shader = SWAY_SHADER
	_sprite.material = _mat
	# 돌풍은 가로로 흐른다 — 같은 x에 선 것끼리 같이 눕는다(바람이 지나가는 느낌의 정체).
	_gust_phase = global_position.x / GUST_WAVE_LEN * TAU
	_fit_shadow()


# 접지 그림자를 이 개체 크기에 맞춘다 — 노드 원점이 곧 밑동이라 위치는 (0,0) 그대로면 된다.
func _fit_shadow() -> void:
	if _shadow == null:
		return
	var tex := _sprite.texture
	var stex := _shadow.texture
	if tex == null or stex == null or stex.get_width() <= 0:
		_shadow.visible = false  # 텍스처가 없으면 그림자만 떠 있는 것이 더 이상하다
		return
	_shadow.scale = Vector2.ONE * (float(tex.get_width()) * SHADOW_WIDTH_MULT / float(stex.get_width()))
	_shadow.modulate = Color(1.0, 1.0, 1.0, SHADOW_ALPHA)
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


# 이 순간의 상시 바람 각(rad). 2차 파로 왕복을 흩고, 돌풍이 진폭 전체를 부풀렸다 줄인다.
func _wind_angle() -> float:
	var gust := 1.0 + sin(_gust_t * TAU / GUST_PERIOD - _gust_phase) * GUST_DEPTH
	var wave := sin(_wind_t) + sin(_wind_t * WIND_SPEED2 + 1.7) * WIND_AMP2
	return wave * WIND_AMP * gust


func _process(delta: float) -> void:
	_wind_t += delta * _wind_speed
	_gust_t += delta
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
	# 각 → 픽셀. 밑동에서 높이 h만큼 위인 우듬지가 가로로 h·sin θ 만큼 간다(셰이더가 나머지 행을 보간).
	_mat.set_shader_parameter(SWAY_PARAM, sin(_angle + _wind_angle()) * _sway_h)
