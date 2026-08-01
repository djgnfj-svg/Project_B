extends AnimatedSprite2D
# 검성 검격 — 표시 전용(판정 없음, rules §0 스프라이트)·각 클라 로컬(네트워크 0).
#   travel=true  : 평타 1~3타 슬래시가 조준 방향으로 **앞으로 날아간다**(씬 루트에 붙임).
#   travel=false : 구르기 평타(4번 소용돌이)가 **플레이어 주변을 휘두른다**(플레이어 자식으로 붙어 따라옴, 제자리).
# preload로만 쓴다(const SlashFx := preload(...)).

const SPEED := 330.0        # 앞으로 날아가는 속도(px/s, travel일 때만) — 연출값(rules §0 예외)
const LIFE := 0.7           # 수명(s)
const FADE_AT := 0.72       # 이 수명 비율부터 알파 페이드 시작

var _dir: Vector2 = Vector2.RIGHT
var _life: float = 0.0
var _base_a: float = 1.0
var _travel: bool = true


# frames = 슬래시 시트 · angle = 조준각(회전) · tint = 색 · travel = 앞으로 날아갈지(false = 제자리 회전).
# 위치는 호출부가 설정한다(날아감 = 씬 루트 + global_position, 회전 = 플레이어 자식 + local position).
func setup(frames: SpriteFrames, angle: float, tint: Color = Color(1, 1, 1, 1), travel: bool = true) -> void:
	sprite_frames = frames
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rotation = angle                       # 슬래시는 +x(오른쪽) 기준 → 조준각으로 회전
	# 🔴 사용자 결정(2026-08-02): 시트는 오목(concave)이 +x를 향하게 구워졌지만, 실제로 맞는 방향은
	#   **그 반대** — 볼록(convex) 날이 진행 방향을 이끈다. 진행축(로컬 x) 기준 좌우 미러 = flip_h.
	#   travel일 때만(날아가는 슬래시). 소용돌이(travel=false)는 방사형이라 미러 불필요.
	flip_h = travel
	_dir = Vector2.RIGHT.rotated(angle)
	_travel = travel
	_base_a = tint.a
	modulate = tint
	z_index = 3                            # 몸(1)·무기(0~2) 위
	var names := frames.get_animation_names()
	if names.size() > 0:
		play(names[0])


func _process(delta: float) -> void:
	if _travel:
		global_position += _dir * SPEED * delta
	_life += delta
	if _life >= LIFE * FADE_AT:
		var t := (_life - LIFE * FADE_AT) / maxf(LIFE * (1.0 - FADE_AT), 0.0001)
		modulate.a = _base_a * maxf(0.0, 1.0 - t)
	if _life >= LIFE:
		queue_free()
