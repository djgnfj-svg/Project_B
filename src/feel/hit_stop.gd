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
#
# 🔴 **`speed_scale`은 `scale`과 달리 복원이 아니라 "1.0으로 리셋"이다 — 의도적이지만 함정이다.**
# `scale`은 hs_base_scale meta로 원래 값을 되돌리는데, `speed_scale`은 아래에서 무조건 1.0을 심는다.
# 이걸 meta 저장 방식으로 "고치면" 더 나빠진다: ⑴ 소유자가 회차마다 배율을 바꾸는 경우(보스가
# 예고 길이에 애니를 맞춘다) 첫 회차 배율이 영구 base로 굳고 ⑵ 연속 피격이면 이미 0.0인 값을
# base로 저장해 애니가 영구 정지한다. 즉 **히트스톱은 "원래 값"을 알 수 있는 위치에 없다.**
#
# ⚠ **그래서 규약은 이쪽이다: `speed_scale`을 쓰는 노드는 소유자가 자기 의도를 재주장해야 한다.**
# 준거 = `src/enemies/boss.gd`의 `_apply_anim_scale()` — 매 물리 프레임 원하는 배율을 다시 심고,
# 정지(0.0) 중에는 건드리지 않는다(덮으면 히트스톱 자체가 사라진다). 그 방어가 없으면 예고 중
# 한 대 맞는 순간 늘려둔 배율이 1.0으로 날아가 **공격 애니가 예고보다 일찍 끝난다**(에러 없음,
# 화면만 어긋난다 — 실제로 이 파일 탓에 보스 애니 수정이 거의 무효화될 뻔했다, 2026-07-26).
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
