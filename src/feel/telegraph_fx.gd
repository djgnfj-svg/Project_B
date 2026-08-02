extends Node
# 바닥 예고·충격 표시의 **쿼드 기하 단일 소스** (rules §3 「보스 텔레그래프 표시 기하」의 규약을
# 함수로 굳힌 것). preload로만 쓴다 — `class_name` 금지(rules §0).
#
# 🔴 여기에 **각·반지름은 없다.** 반지름은 언제나 호출부가 판정 데이터에서 받아 넘긴다
#   (잔몹 = `EnemyDef.strike_radius` = `CombatMath.is_strike_hit`의 반경 · 보스 = `BossPatternDef.range`).
#   이 파일에 크기 상수를 만드는 순간 "보이는 곳 ≠ 맞는 곳"이 열린다.
#
# 규약 (boss.gd `_apply_telegraph_geometry`와 **같은 유도** — 사본이 아니라 같은 규칙이어야 한다):
#   · 노드 원점 = 원 중심 · `centered = true` · **균일** scale
#     🔴 비균일 스케일 금지 — 정원이 **타원**이 되어 축 방향 말고는 전부 어긋난다
#       (텍스처 시절 이 우회로를 두 번 시도해 두 번 기각했다).
#   · 쿼드 한 변 = `2 * (radius + aa + margin)` — 🔴 **딱 지름이면 안 된다**: 원호의 상하좌우
#     끝에서 화면 픽셀 중심이 쿼드 밖으로 나가 그 프래그먼트가 **아예 안 돌아** 판정 안인데
#     안 그려지는 픽셀이 생긴다. 여유는 표시용일 뿐 판정 기하가 아니다(셰이더는 `radius_px`로만
#     안팎을 가른다).
#   · 텍스처 = **2×2 흰 쿼드**. 1×1은 centered 오프셋 -0.5px가 거대 scale에 곱해져 half-quad만큼
#     통째로 어긋난다(boss.gd 실측 2026-07-31 — 콘 apex가 -123px 튀었다).
#     🔴 **형태를 그린 텍스처를 물리지 마라** — 알파가 셰이더 형태를 다시 잘라 정합이 깨진다.
#     무늬를 얹으려면 **정사각 풀블리드(알파 1)** 패턴이어야 한다.
#
# ⚠ boss.gd(`_apply_telegraph_geometry`)는 아직 자기 사본을 들고 있다 — 같은 유도가 두 곳에 있으니
#   리드가 §3에 등재하고 보스 쪽을 이 함수로 넘기는 것이 다음 단계다(2026-08-02 dev 보고).
#   그때까지는 **두 곳을 같이 고쳐라.**

const SHADER := preload("res://assets/shaders/boss_telegraph.gdshader")

# 예고 쿼드 소스 — 모든 예고(보스 단일/N개 원 · 잔몹 장판 · 타격 충격파)가 공유한다.
# 기하를 셰이더가 그리므로 텍스처는 "크기"만 준다. 흰색이라 셰이더의 `texture(TEXTURE, UV)` 곱이
# 정확한 항등이다.
static var _quad_tex: ImageTexture = null


static func quad_tex() -> ImageTexture:
	if _quad_tex == null:
		var img := Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_quad_tex = ImageTexture.create_from_image(img)
	return _quad_tex


# 쿼드 월드 한 변(px). 🔴 `radius_px`는 **판정 반경 그대로**여야 한다 — 여유(aa·margin)는 쿼드를
# 넓힐 뿐 셰이더의 `radius_px`에는 안 들어간다(호출부가 둘을 따로 넘기는 이유).
static func quad_span(radius_px: float, aa_px: float, margin_px: float) -> float:
	return 2.0 * (maxf(radius_px, 0.0) + maxf(aa_px, 0.0) + maxf(margin_px, 0.0))


# 스프라이트를 쿼드 규약에 맞춘다(텍스처·정렬·균일 스케일). 셰이더는 호출부가 붙인다.
static func fit_quad(spr: Sprite2D, quad_px: float) -> void:
	spr.texture = quad_tex()
	spr.centered = true
	spr.offset = Vector2.ZERO
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.rotation = 0.0
	# 텍스처가 2×2라 월드 한 변 = 2*scale → scale = quad/2. **균일**이어야 한다(위 규약).
	spr.scale = Vector2.ONE * (quad_px * 0.5)


# 원형 예고 한 장을 세운다 — 판정식 `length(p) <= radius_px` ≡ `CombatMath.is_strike_hit` 그대로.
# 색·테두리·맥동 같은 **연출값은 호출부가** 반환된 머티리얼에 심는다(보스/잔몹이 톤을 달리 쓴다).
# ⚠ `half_angle`에 PI를 넘기면 셰이더가 각 검사를 통째로 건너뛴다(= 원과 항등).
# ⚠ `half_len_px = 0`은 캡슐 분기를 끄고 원·콘과 **비트 단위 항등**이다(셰이더 헤더의 증명).
#   🔴 노드가 재사용될 수 있으므로 **무조건 심는다** — 조건부로 심으면 다음 원 예고가 캡슐로 그려진다.
static func apply_circle(spr: Sprite2D, radius_px: float, aa_px: float,
		margin_px: float) -> ShaderMaterial:
	var radius := maxf(radius_px, 0.0)
	var quad := quad_span(radius, aa_px, margin_px)
	fit_quad(spr, quad)
	var mat := spr.material as ShaderMaterial
	if mat == null or mat.shader != SHADER:
		mat = ShaderMaterial.new()
		mat.shader = SHADER
		spr.material = mat
	mat.set_shader_parameter(&"quad_px", quad)
	mat.set_shader_parameter(&"radius_px", radius)
	mat.set_shader_parameter(&"half_angle", PI)
	mat.set_shader_parameter(&"half_len_px", 0.0)
	mat.set_shader_parameter(&"aa_px", maxf(aa_px, 0.0001))
	mat.set_shader_parameter(&"progress", 0.0)
	return mat


# 차오름(임박도). 🔴 **`TIME`에서 유도하지 마라** — 예고 창 길이가 클라마다 다르다(호스트는
#   `strike_delay_s`만큼 길다). 호출부가 **자기 예고 창**으로 나눈 값을 넘긴다(§3 지연 보상).
static func set_progress(mat: ShaderMaterial, p: float) -> void:
	if mat == null:
		return
	mat.set_shader_parameter(&"progress", clampf(p, 0.0, 1.0))
