extends Camera2D
# 로컬 플레이어 추적 카메라 + 스크린셰이크 (src/feel, 사용자 확정 2026-07-23: 로컬 추적).
# player.tscn의 자식 — 로컬 플레이어 인스턴스만 enabled=true(=현재 카메라). 원격 피어의
# 카메라는 비활성이라 뷰포트를 잡지 않는다(player.gd setup에서 enabled=is_local).
# 흔들림 = offset에 감쇠하는 랜덤 변위. Engine.time_scale 안 건드림 (rules §5 멀티 안전).
# EventBus 구독은 씬 스크립트라 전역 식별자 허용 (rules §5 — 헤드리스 -s 대상 아님).
# 연출값 (rules §0 예외).

const SHAKE_DECAY := 14.0   # 초당 감쇠량(클수록 빨리 잦아든다)
const SHAKE_MAX := 7.0      # 오프셋 상한(px) — 640×360이라 과하면 멀미
const SMOOTH_SPEED := 9.0   # 위치 추적 부드러움
# combat_impact 종류별 기본 셰이크 강도 (내가 맞으면 더 크게)
const IMPACT_SHAKE := {"enemy": 1.5, "player": 3.0}

var _shake: float = 0.0


func _ready() -> void:
	position_smoothing_enabled = true
	position_smoothing_speed = SMOOTH_SPEED
	EventBus.combat_impact.connect(_on_impact)
	EventBus.screen_shake.connect(add_shake)


func _on_impact(kind: String, _world_pos: Vector2, _amount: int) -> void:
	add_shake(float(IMPACT_SHAKE.get(kind, 1.0)))


func add_shake(strength: float) -> void:
	_shake = minf(SHAKE_MAX, _shake + strength)


func _process(delta: float) -> void:
	if not enabled:
		return  # 원격 피어 카메라는 흔들 필요 없음(현재 카메라 아님)
	_shake = maxf(0.0, _shake - SHAKE_DECAY * delta)
	if _shake > 0.05:
		offset = Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))
	elif offset != Vector2.ZERO:
		offset = Vector2.ZERO
