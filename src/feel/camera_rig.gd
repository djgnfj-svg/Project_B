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


func _on_impact(kind: String, _world_pos: Vector2, _amount: int) -> void:
	add_shake(float(IMPACT_SHAKE.get(kind, 1.0)))


func add_shake(strength: float) -> void:
	_shake = minf(SHAKE_MAX, _shake + strength)


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
	if _shake > 0.05:
		offset = Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))
	elif offset != Vector2.ZERO:
		offset = Vector2.ZERO
