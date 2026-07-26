extends Node
# 대쉬 잔상 — 스프라이트의 현재 프레임을 그 자리에 "떼어 놓고" 페이드시킨다 (사용자 요청 2026-07-26:
# "구르기 보다는 잔상이 남는 대쉬"). 표시 전용·각 클라 로컬이라 **네트워크 메시지 0개**다.
# preload로만 쓴다(const AfterImage := preload(...)); 정적 함수라 인스턴스 불필요 (HitStop 미러).
#
# 🔴 잔상은 **씬 루트에 붙인다** — 플레이어의 자식으로 두면 플레이어를 따라다녀서 "지나온 자리에
#   남는다"가 성립하지 않는다(잔상이 몸에 겹쳐 그냥 흐릿한 몸으로 보인다).
# ⚠ z_index는 몸(Sprite z=1)보다 낮게 둔다. 음수로 내리면 배경 타일(z=-10)과의 사이라 안전하지만,
#   0이면 바닥 위·몸 아래에 정확히 깔린다 (rules §5 z 배치: 바닥 -10 < 텔레그래프 -1 < 몸/무기 0+).
#
# 연출값 (rules §0 예외 — 사용자가 플레이하며 조인다).

const FADE_S := 0.26            # 잔상 하나가 사라지기까지(s)
const START_ALPHA := 0.55       # 태어날 때 불투명도
const TINT := Color(0.72, 0.86, 1.0)  # 청백 — 몸과 구분되게(잔상이 몸으로 안 읽히게)
const SPAWN_INTERVAL := 0.045   # 잔상 사이 최소 간격(s) — 호출부가 이 값으로 타이머를 돈다
const Z_INDEX := 0              # 몸(1) 아래 · 바닥(-10) 위


# sprite = 복제할 표시 노드(AnimatedSprite2D), host = 잔상을 남기는 주체(플레이어 등).
# host의 부모(씬 루트)에 붙인다 — 부모가 없으면(테스트·해제 중) 조용히 아무것도 안 한다.
static func spawn(sprite: AnimatedSprite2D, host: Node2D) -> void:
	if sprite == null or host == null or not sprite.is_inside_tree():
		return
	var parent := host.get_parent()
	if parent == null:
		return
	var frames := sprite.sprite_frames
	if frames == null or not frames.has_animation(sprite.animation):
		return
	var count := frames.get_frame_count(sprite.animation)
	if count <= 0:
		return
	var tex := frames.get_frame_texture(sprite.animation, clampi(sprite.frame, 0, count - 1))
	if tex == null:
		return
	var ghost := Sprite2D.new()
	ghost.texture = tex
	ghost.global_position = sprite.global_position
	ghost.rotation = sprite.global_rotation
	ghost.scale = sprite.global_scale
	ghost.flip_h = sprite.flip_h
	ghost.flip_v = sprite.flip_v
	ghost.offset = sprite.offset
	ghost.centered = sprite.centered
	ghost.z_index = Z_INDEX
	ghost.modulate = Color(TINT.r, TINT.g, TINT.b, START_ALPHA)
	parent.add_child(ghost)
	# 페이드 후 자기 정리 — 타이머가 아니라 트윈에 매달아야 씬이 먼저 사라져도 같이 죽는다.
	var tw := ghost.create_tween()
	tw.tween_property(ghost, "modulate:a", 0.0, FADE_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(ghost.queue_free)
