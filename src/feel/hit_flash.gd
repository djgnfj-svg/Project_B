extends Node
# 히트 플래시 — "맞은 스프라이트만" 하얗게 번쩍 (canvas_item 셰이더). 표시 전용, 멀티 안전.
# preload로만 쓴다(const HitFlash := preload(...)); 정적 함수라 인스턴스 불필요.
# 🔴 평상시엔 머티리얼을 떼어 셰이더가 아예 안 걸리게 한다 — 번쩍이 끝나면 sprite.material=null.
#   이유: 웹(Compatibility) 렌더러에서 amount=0이 완전한 항등이 아닐 위험이 있어, 머티리얼이 계속
#   붙어 있으면 "한 대 맞으면 색이 틀어진 채 안 돌아온다"가 된다(실기에서 발견 2026-07-23).
#   → 번쩍 동안만 셰이더를 걸고, 끝나면 제거해 근본 차단.
# 각 스프라이트에 고유 ShaderMaterial을 붙인다(같은 tscn 개체끼리 공유 시 동시 번쩍 방지).
# 연출값 (rules §0 예외).

const FLASH_SHADER := preload("res://assets/shaders/hit_flash.gdshader")
const FLASH_TIME := 0.13


static func flash(sprite: CanvasItem) -> void:
	if sprite == null or not sprite.is_inside_tree():
		return
	var mat := sprite.material as ShaderMaterial
	if mat == null or mat.shader != FLASH_SHADER:
		mat = ShaderMaterial.new()
		mat.shader = FLASH_SHADER
		sprite.material = mat
	mat.set_shader_parameter(&"flash_color", Color.WHITE)  # 기본값 의존 금지 (웹 검정 렌더 방지)
	mat.set_shader_parameter(&"flash_amount", 1.0)
	var prev: Variant = sprite.get_meta(&"hf_tween", null)
	if prev is Tween and (prev as Tween).is_valid():
		(prev as Tween).kill()
	var tw := sprite.create_tween()
	sprite.set_meta(&"hf_tween", tw)
	tw.tween_property(mat, "shader_parameter/flash_amount", 0.0, FLASH_TIME)
	# 끝나면 머티리얼 제거 → 평상시엔 기본 렌더. 더 새 플래시가 덮었으면(메타 불일치) 건드리지 않는다.
	tw.finished.connect(func() -> void:
		if is_instance_valid(sprite) and sprite.get_meta(&"hf_tween", null) == tw:
			sprite.material = null
			sprite.remove_meta(&"hf_tween"))
