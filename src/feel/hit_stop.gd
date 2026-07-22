extends Node
# 히트스톱 — "맞은 대상만" (사용자 확정 2026-07-23). 표시 전용, 멀티 안전.
# 🔴 Engine.time_scale 전역 정지 금지 (rules §5): 호스트가 멈추면 방 전체가 정지한다.
#   대신 맞은 스프라이트 하나의 애니만 잠깐 멈추고(speed_scale=0) 스케일을 튕긴다.
# preload로만 쓴다(const HitStop := preload(...)); 정적 함수라 인스턴스 불필요.
# 연출값 (rules §0 예외 — 사용자가 플레이하며 조인다).

const FREEZE_S := 0.055     # 애니 정지 시간(맞은 대상만)
const PUNCH_SCALE := 1.16   # 임팩트 순간 스케일 배수
const PUNCH_BACK_S := 0.12  # 원래 스케일로 되돌아오는 시간


# sprite = 맞은 대상의 표시 노드(Sprite2D/AnimatedSprite2D). 여러 번 맞아도 겹치지 않게
# 이전 튕김 트윈을 죽이고 기준 스케일을 meta로 한 번만 고정한다(누적 드리프트 방지).
static func punch(sprite: Node2D) -> void:
	if sprite == null or not sprite.is_inside_tree():
		return
	var base: Vector2 = sprite.get_meta(&"hs_base_scale", sprite.scale)
	sprite.set_meta(&"hs_base_scale", base)
	var prev: Variant = sprite.get_meta(&"hs_tween", null)
	if prev is Tween and (prev as Tween).is_valid():
		(prev as Tween).kill()
	sprite.scale = base * PUNCH_SCALE
	var anim := sprite as AnimatedSprite2D
	if anim != null:
		anim.speed_scale = 0.0
	var tw := sprite.create_tween()
	sprite.set_meta(&"hs_tween", tw)
	tw.tween_interval(FREEZE_S)
	tw.tween_callback(func() -> void:
		if is_instance_valid(anim):
			anim.speed_scale = 1.0)
	tw.tween_property(sprite, "scale", base, PUNCH_BACK_S) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
