extends Node2D
# 드랍 등장/픽업 파티클 팝 (src/feel) — item_dropped/item_picked 구독, 월드 좌표에 일회성 버스트.
# 오토로드 Node2D: /root 아래라 현재 Camera2D의 캔버스 변환을 그대로 받아 월드 좌표에 그려진다
# (DamageNumbers 미러 — 스테이지 3종을 안 건드리고 전 씬 커버). 표시 전용·각 클라 로컬·네트워크 0.
# ⚠ 오토로드 본체라 EventBus 전역 식별자 런타임 접근 OK (헤드리스 -s 대상 아님, rules §5).
# 파티클은 도형 금지(rules §0 = 게임 오브젝트) 대상이 아닌 연출 이펙트 — 텍스처 없는 점 버스트.
# 연출값 (rules §0 예외). 등장은 drop_item 자체 스케일 팝과 함께, 픽업은 노드 소멸 후 pos 기반이라 여기서만.

const DROP_AMOUNT := 6       # 등장 버스트 파티클 수
const PICK_AMOUNT := 10      # 픽업 버스트 파티클 수(획득이 더 화려)
const LIFE := 0.4            # 파티클 수명(s)
# 등급별 색 (MaterialDef.rarity 미러) — 0 일반 흰·1 희귀 청·2 핵심 금. gold kind는 rarity 0이라 별도 금색.
const RARITY_COLOR := {0: Color(1.0, 1.0, 1.0), 1: Color(0.6, 0.8, 1.0), 2: Color(1.0, 0.87, 0.4)}
const GOLD_COLOR := Color(1.0, 0.85, 0.3)


func _ready() -> void:
	EventBus.item_dropped.connect(_on_dropped)
	EventBus.item_picked.connect(_on_picked)


func _on_dropped(kind: String, rarity: int, world_pos: Vector2) -> void:
	_burst(world_pos, _color_for(kind, rarity), DROP_AMOUNT, 46.0, 90.0)  # 아래로 흩어지는 착지 먼지


func _on_picked(kind: String, rarity: int, world_pos: Vector2) -> void:
	_burst(world_pos, _color_for(kind, rarity), PICK_AMOUNT, 70.0, -50.0)  # 위로 튀어오르는 획득 반짝


func _color_for(kind: String, rarity: int) -> Color:
	if kind == "gold":
		return GOLD_COLOR
	return RARITY_COLOR.get(rarity, Color.WHITE)


# 일회성 CPUParticles2D 버스트 — 방출 후 수명+여유 뒤 정리. 웹 Compatibility 안전(GPU 파티클 회피).
func _burst(pos: Vector2, color: Color, amount: int, speed: float, gravity_y: float) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.z_index = 90  # 바닥(-10)·드랍 위, 데미지 숫자(100) 아래
	p.one_shot = true
	p.explosiveness = 1.0  # 전량 동시 방출
	p.amount = amount
	p.lifetime = LIFE
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector2(0.0, gravity_y)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.2
	p.color = color
	add_child(p)
	p.emitting = true  # 모든 파라미터·tree 진입 후 방출 (amount 재할당 뒤라 엔진 버전 변화에도 견고)
	get_tree().create_timer(LIFE + 0.3).timeout.connect(p.queue_free)
