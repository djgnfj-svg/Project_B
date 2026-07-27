extends Camera2D
# 로컬 플레이어 추적 카메라 + 스크린셰이크 (src/feel, 사용자 확정 2026-07-23: 로컬 추적).
# player.tscn의 자식 — 로컬 플레이어 인스턴스만 enabled=true(=현재 카메라). 원격 피어의
# 카메라는 비활성이라 뷰포트를 잡지 않는다(player.gd setup에서 enabled=is_local).
# 흔들림 = offset에 감쇠하는 랜덤 변위. Engine.time_scale 안 건드림 (rules §5 멀티 안전).
# EventBus 구독은 씬 스크립트라 전역 식별자 허용 (rules §5 — 헤드리스 -s 대상 아님).
# 연출값 (rules §0 예외).

# 🔴 확대 배율 (사용자 요청 2026-07-26: 16px 전환 후 "좀더 확대해줘").
# 🔴 **줌은 1.0이다 — 32px 아트가 기준이기 때문이다** (2026-07-27 복귀).
# 이 상수는 원래 없었다. 2026-07-26에 아트를 16px로 내리면서 캐릭터가 화면 세로의 1/22이 되자
# **그 보정으로** 2.0이 들어온 것이고(`a29991a`), 같은 날 32px로 되돌아오면서 함께 1.0으로 돌렸다.
# 안 돌리면 32px × 2.0 = 화면상 64px로 **16px 시절의 2배**가 되고 시야는 절반이 된다.
# ⚠ 값을 올릴 땐 **정수 배율만** 써라(1.5·2.5는 픽셀이 뭉갠다). HUD는 CanvasLayer라 영향을 안 받는다.
# ⚠ 올리면 보이는 범위가 그만큼 줄어 맵이 넓게 느껴지고 같은 move_speed가 더 빠르게 보인다 —
#   아래 두 상한도 배율만큼 나눠야 한다(그 미러가 이 파일 안에 있다).
const ZOOM := 1.0

const SHAKE_DECAY := 14.0   # 초당 감쇠량(클수록 빨리 잦아든다)
# ⚠ 아래 두 상한은 **줌 좌표계**다 — offset에 zoom이 곱해져 화면에 나가므로, 확대 배율만큼
#   나눠야 체감이 유지된다. 안 그러면 확대한 만큼 화면이 더 크게 흔들려 멀미가 난다.
const SHAKE_MAX := 7.0      # 오프셋 상한(px) — 640×360 / ZOOM 1.0 기준
const SMOOTH_SPEED := 9.0   # 위치 추적 부드러움
# combat_impact 종류별 기본 셰이크 강도 (내가 맞으면 더 크게)
const IMPACT_SHAKE := {"enemy": 1.5, "player": 3.0}
const CRIT_SHAKE_MULT := 1.6  # 치명타 셰이크 가중 (성장축 2026-07-25 — 연출값, rules §0 예외)
# 방향성 반동 (사용자 요청 2026-07-26: "카메라가 좀더 쫀득해야함 — 반동이 필요").
# 셰이크와 **다른 축**이라 따로 쌓고 offset에서 합친다: 셰이크는 무작위 진동, 반동은 방향이 읽히는 밀림.
const KICK_MAX := 9.0        # 반동 변위 상한(px) — 셰이크와 합쳐도 화면이 안 무너지는 선(줌 좌표계)
const KICK_DECAY := 34.0     # 밀린 뒤 되돌아오는 속도(px/s). 셰이크보다 훨씬 빨라야 "톡" 치는 느낌
const KICK_SMOOTH := 26.0    # 밀리는 순간의 부드러움 — 즉시 점프하면 프레임 튀듯 보인다

var _shake: float = 0.0
var _kick: Vector2 = Vector2.ZERO        # 현재 적용 중인 반동 변위
var _kick_target: Vector2 = Vector2.ZERO # 목표 변위 — 여기로 빠르게 따라간 뒤 함께 0으로 감쇠


func _ready() -> void:
	zoom = Vector2(ZOOM, ZOOM)
	position_smoothing_enabled = true
	position_smoothing_speed = SMOOTH_SPEED
	EventBus.combat_impact.connect(_on_impact)
	EventBus.screen_shake.connect(add_shake)
	EventBus.camera_kick.connect(add_kick)
	# 내 무기 적중(공격자 로컬 예측) — 무기 무게감 셰이크. enabled(로컬 카메라)일 때만 흔들린다.
	EventBus.weapon_impact.connect(func(_pos: Vector2, _sfx: String, shake: float) -> void: add_shake(shake))
	# 씬 루트가 map_rect 메타를 선언하면 맵 경계로 클램프 — 맵 밖(공허)이 안 보이게.
	# 각 씬은 _ready에서 set_meta("map_rect", Rect2(...)) 한 줄만 선언한다 (복붙 배선 방지).
	# ⚠ current_scene은 못 쓴다 — main의 씬 스왑이 수동 add_child라 항상 부팅 씬(Main)이다.
	#   대신 조상 체인을 올라가며 메타를 찾는다 (플레이어 → 씬 루트 → Main 순).
	var n: Node = get_parent()
	while n != null:
		if n.has_meta("map_rect"):
			set_limits(n.get_meta("map_rect") as Rect2)
			break
		n = n.get_parent()


func _on_impact(kind: String, _world_pos: Vector2, _amount: int, crit: bool) -> void:
	var shake := float(IMPACT_SHAKE.get(kind, 1.0))
	add_shake(shake * CRIT_SHAKE_MULT if crit else shake)  # 치명타는 조금 더 묵직하게(표시 전용)


func add_shake(strength: float) -> void:
	_shake = minf(SHAKE_MAX, _shake + strength)


# 방향성 반동 — dir 방향으로 strength만큼 밀렸다 돌아온다. 셰이크와 독립적으로 쌓인다.
# dir이 0이면 무시(정규화 불가) — 방향 없는 충격은 add_shake 쪽이다.
func add_kick(dir: Vector2, strength: float) -> void:
	if dir.length_squared() < 0.000001 or not (is_finite(dir.x) and is_finite(dir.y)):
		return
	_kick_target = (_kick_target + dir.normalized() * strength).limit_length(KICK_MAX)


# 맵 경계 클램프 — 씬(마을 등)이 스폰 후 호출해 카메라가 맵 밖(공허)을 못 보게 한다.
# 맵이 뷰포트(640×360)보다 큰 씬에서만 의미 있다 — 미호출 시 기본(무제한) 유지.
func set_limits(rect: Rect2) -> void:
	limit_left = int(rect.position.x)
	limit_top = int(rect.position.y)
	limit_right = int(rect.end.x)
	limit_bottom = int(rect.end.y)


func _process(delta: float) -> void:
	if not enabled:
		return  # 원격 피어 카메라는 흔들 필요 없음(현재 카메라 아님)
	_shake = maxf(0.0, _shake - SHAKE_DECAY * delta)
	# 반동: 목표를 0으로 끌어당기면서, 현재 변위는 그 목표를 빠르게 따라간다.
	# (목표를 즉시 offset에 대입하면 한 프레임 점프로 보이고, 감쇠만 쓰면 밀리는 순간이 뭉개진다)
	_kick_target = _kick_target.move_toward(Vector2.ZERO, KICK_DECAY * delta)
	_kick = _kick.lerp(_kick_target, minf(1.0, KICK_SMOOTH * delta))
	var shake_off := Vector2.ZERO
	if _shake > 0.05:
		shake_off = Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))
	var next := shake_off + _kick
	if next.length_squared() < 0.0025:
		next = Vector2.ZERO  # 미세 잔여로 카메라가 영원히 떨리지 않게 스냅
	if offset != next:
		offset = next
