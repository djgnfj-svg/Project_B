extends Sprite2D
# 하위 직업 스킬 FX(회전 베기 spin · 비검 beam) — 표시 전용(판정 없음)·각 클라 로컬(네트워크 메시지·필드 0).
# 형태는 `assets/shaders/skill_fx.gdshader`가 그리고, 이 스크립트는 **기하를 셰이더에 심고 수명을
# 굴리는 일**만 한다 (`slash_fx.gd`와 같은 구조 — 그쪽이 준거다).
#
# 🔴 **크기의 출처는 판정이다 — 여기서 만들지 않는다.** 반경·길이는 `SkillDef.radius`/`length`가
#   그대로 오고, 호스트 확정(`combat_authority`)과 로컬 표시가 **같은 `CombatMath.is_skill_hit`**을
#   지난다. 아래 const에 도달 거리를 만들어 내는 값은 **하나도 없다**(전부 비율·연출·소프트 폭).
#   ⚠ 스킬 범위를 키우려면 `data/skills/*.tres`를 고쳐라 = 밸런스 변경(rules §3 "맞는 곳 = 보이는 곳").
#
# 🔴 **크기가 자라지 않는다.** 판정은 한순간인데 FX가 작게 태어나 커지면 그 사이가 「표시 < 판정」이
#   되어 §3이 금지하는 방향이다 — 태어난 첫 프레임부터 판정 전체 크기이고, 연출은 **회전 위상과
#   알파 페이드**만 굴린다.
#
# 🔴 **캐스터를 따라다니지 않는다.** 판정은 발동 순간의 좌표에서 한 번 나므로 FX도 그 자리에 못 박힌다
#   (따라다니면 "보이는 곳"이 판정 이후에 움직여 §3이 시간 축에서 깨진다).
#   ⚠ **이동형(`travel_speed > 0`)은 예외이고, 그것이 예외인 이유가 규칙 자체다** — 그쪽은
#     **판정도 같이 움직인다**(호스트가 매 물리 프레임 판정 원을 앞으로 민다). 즉 "못 박는다"가
#     지키려던 것은 *정지*가 아니라 **「보이는 곳 = 그 순간 맞는 곳」**이고, 이동형에서는 둘이 같은
#     속도·같은 수명(`CombatMath.skill_travel_lifetime_s`)으로 나아가야 그것이 지켜진다.
#     🔴 **속도·수명을 여기서 만들지 마라** — 둘 다 호출부가 `SkillDef`/`CombatMath`에서 받아 넘긴다.
#
# preload로만 쓴다(const SkillFx := preload(...)) — rules §0 `class_name` 금지.

const SHADER := preload("res://assets/shaders/skill_fx.gdshader")

# --- 연출값 (rules §0 예외 = 손맛 상수. 밸런스가 아니다 — 판정에 한 픽셀도 안 닿는다) ---
const LIFE := 0.34          # 수명(s) — 한 방짜리 광역이라 짧고 굵게
# 🔴 **다단(`hit_count > 1`)에서는 수명을 타 간격에 묶는다** (2026-08-02 「환영검무」).
#   5타 × 0.08s인데 각 FX가 0.34s를 살면 **다섯 장이 통째로 겹쳐** 한 번 크게 번쩍인 것과
#   구분이 안 된다 — 그러면 "다단"이 화면에서 안 읽히고, 그것이 이 기능의 요구사항 전부다.
#   ⚠ **기하는 한 픽셀도 안 건드린다** — 줄이는 것은 「보이는 시간」뿐이고, 각 타의 FX는 여전히
#     그 타가 확정되는 순간에 **판정 전체 크기**로 태어난다(§3 「표시 ≥ 판정」은 공간 축 계약이다).
#   ⚠ 간격이 넉넉하면(`× 이 비율 ≥ LIFE`) 자동으로 `LIFE`로 돌아온다 = 느린 다단은 항등.
const MULTI_LIFE_RATIO := 1.5
const FADE_AT := 0.35       # 이 수명 비율부터 알파 페이드 시작
const AA_PX := 1.2          # 경계 소프트 폭(월드 px)
# 🔴 쿼드 여유 — 딱 `2*(half_len + radius)`면 경계에서 프래그먼트가 아예 안 돌아 **그려져야 하는데
#   안 그려지는** 픽셀이 생긴다. 항 둘 = ⑴ 알파 램프가 바깥으로 퍼지는 폭(AA_PX) ⑵ 프래그먼트가
#   픽셀 **중심**에서만 생기는 데서 오는 화면 반픽셀(줌 1.5에서 0.33 월드px)을 넉넉히 잡은 값.
const QUAD_MARGIN_PX := 1.5
const RIM_PX := 9.0         # 테두리 밝은 띠 두께(경계 안쪽) — "여기까지 닿는다"를 읽게 하는 겹
# 🔴 아래 넷은 **2026-08-02에 강렬화로 올렸다**(사용자: *"검기 임팩트? 리본들을 좀더 강렬하게"*).
#   올린 것은 **밝기·대비뿐이고 기하는 한 픽셀도 안 건드렸다** — 반경·길이는 여전히 `SkillDef`
#   그대로다(§3 "맞는 곳 = 보이는 곳"). 세기가 과하면 여기를 내려라, `.tres`가 아니다.
const EDGE_GLOW := 2.1      # 강조부 rgb 증폭(틴트를 흰 쪽으로 태운다 — 셰이더 헤더 참조). 전 1.5
const FILL_ALPHA := 0.30    # 판정 영역 전체의 옅은 채움. 전 0.20
const EDGE_ALPHA := 1.0     # 전 0.92
const SWIRL_TURNS := 1.7    # spin: 수명 동안 도는 바퀴 수
const SWIRL_WIDTH := 0.15   # spin: 회전 하이라이트 폭(한 살 구간 = 1)
const CORE_RATIO := 0.38    # beam: 축 심 반폭 / 반폭

# --- 이동형 「월륜」 (2026-08-02) — 🔴 **여기 상수 중 도달 거리를 만드는 것은 하나도 없다** ---
#   속도·거리·수명은 전부 `SkillDef.travel_*` → `CombatMath.skill_travel_lifetime_s`에서 온다.
#   아래는 "바퀴로 보이게 하는" 위상·질감뿐이다.
const TRAVEL_FADE_AT := 0.62        # 비행의 이 비율부터 알파 페이드 — 🔴 등속이라 **시간 비율 = 거리 비율**이다
                                    #   (사용자 요구 *"맵끝까지 가면서 서서히 사라지는"* 이 그대로 성립한다).
const TRAVEL_SWIRL_RATE := 1.35     # 초당 회전 수 — 🔴 **수명이 아니라 시간에 묶는다**. 수명 기준이면
                                    #   사거리가 길수록 천천히 도는 것처럼 보인다(같은 바퀴를 더 오래 굴린다).
const TRAVEL_SPOKES := 3.0          # 살 개수 — 한 줄은 "선"이고 셋이어야 "바퀴"로 읽힌다
const TRAVEL_SWIRL_WIDTH := 0.26    # 살 하나가 자기 구간에서 차지하는 폭(살이 늘면 구간이 좁아지므로 비율을 키운다)
const TRAVEL_RING_RATIO := 0.60     # 안쪽 고리 반경 / 판정 반경 — 🔴 **1 미만 = 경계보다 반드시 안쪽**
                                    #   (테두리 `rim`이 판정 경계이고, 이 고리를 그것으로 오해하면 도달을 짧게 읽는다)
const TRAVEL_RING_PX := 5.0
const TRAVEL_FILL_ALPHA := 0.22     # 굴러가는 원반은 오래 떠 있어 채움이 진하면 시야를 먹는다(단발보다 옅게)

# 🔴 2×2(1×1 아님) — 1×1은 centered 오프셋이 -0.5px 서브픽셀이라, 거대 scale을 곱하면 그 반올림
#   오차가 half-quad만큼 통째로 어긋난다(boss.gd `_telegraph_quad_tex`의 실측 사고 — 콘 apex가
#   회전 방향으로 -123px 튀었다). 2×2면 오프셋 = -1px 정수라 scale과 정확히 맞물린다.
static var _quad_tex: ImageTexture = null

var _life: float = 0.0
var _life_total: float = LIFE   # 이 장의 수명(s) — 단발 = LIFE · 다단 = multi_life_s (아래)
var _base_a: float = 1.0
var _mat: ShaderMaterial = null
# 이동형 속도 벡터(px/s). ZERO = 제자리 = 이동형 도입 전과 **완전 항등**.
var _vel: Vector2 = Vector2.ZERO
var _fade_at: float = FADE_AT


# 그 스킬 한 장의 수명 — 🔴 **호출부가 자기 식을 갖지 않게 여기 하나로 모은다**(`slash_fx`의
#   두께 유도와 같은 자리). 단발(1타)은 `LIFE` 그대로 = 이 축 도입 전과 **완전 항등**이다.
static func multi_life_s(hit_count: int, hit_interval_s: float) -> float:
	if CombatMath.clamp_skill_hit_count(hit_count) <= 1:
		return LIFE
	return minf(LIFE, CombatMath.clamp_skill_hit_interval(hit_interval_s) * MULTI_LIFE_RATIO)


static func _quad_texture() -> ImageTexture:
	if _quad_tex == null:
		var img := Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_quad_tex = ImageTexture.create_from_image(img)
	return _quad_tex


# origin = **판정 원점**(= 시전자 위치, 호스트가 `net_anchor()`로 보는 그 자리) · angle = 발동 방향(rad)
# tint = 하위 직업/무기 합성 틴트(`player._fx_color`) · radius/length = SkillDef 그대로(월드 px)
# 🔴 노드 위치를 **여기서** 정한다 — beam은 캡슐 축 선분의 **중점**이라 `origin + 방향 × length/2`다.
#   호출부에 두면 그 오프셋이 셰이더 규약의 사본이 되어, 다음에 형태가 늘 때 한쪽만 고쳐진다.
# life_s = 이 장의 수명(s). 0 이하 = `LIFE`(단발 기본) — 다단은 `multi_life_s`가 준다.
# travel_speed = 이동형 검기의 전진 속도(px/s). 0 = 제자리 = 이동형 도입 전과 **완전 항등**.
# 🔴 **호출부가 `SkillDef.travel_speed`와 `CombatMath.skill_travel_lifetime_s`를 그대로 넘긴다** —
#   여기서 거리를 다시 계산하면 그것이 곧 판정 수명의 사본이 되어, 다음 튜닝에서 "검기는 아직
#   날아가는데 판정은 끝났다"(또는 그 반대)가 된다(`arrow_lifetime_s`와 같은 관용구).
func setup(shape: String, origin: Vector2, angle: float, tint: Color,
		radius: float, length: float, life_s: float = 0.0,
		travel_speed: float = 0.0) -> void:
	_life_total = life_s if (is_finite(life_s) and life_s > 0.0) else LIFE
	# 🔴 속도도 **판정과 같은 clamp**를 지난다 — 데이터가 상한을 넘으면 호스트는 잘린 속도로 미는데
	#   FX만 원본으로 날아가면 그 차이가 통째로 "보이는데 안 맞는" 어긋남이 된다(반경 clamp와 같은 이유).
	var tspeed := CombatMath.clamp_skill_travel_speed(travel_speed)
	var is_travel := tspeed > 0.0
	_vel = Vector2.RIGHT.rotated(angle) * tspeed if is_travel else Vector2.ZERO
	_fade_at = TRAVEL_FADE_AT if is_travel else FADE_AT
	# 🔴 clamp도 **판정과 같은 함수**를 지난다 — 데이터가 상한을 넘으면 호스트는 잘라서 판정하는데
	#   FX만 원본 크기로 그리면 그 차이가 통째로 "보이는데 안 맞는" 띠가 된다.
	var r := maxf(CombatMath.clamp_skill_radius(radius), 1.0)
	var half_len := 0.0
	var is_beam := shape == SkillDef.SHAPE_BEAM
	if is_beam:
		half_len = CombatMath.clamp_skill_length(length) * 0.5
	var quad := 2.0 * (half_len + r + AA_PX + QUAD_MARGIN_PX)

	texture = _quad_texture()
	centered = true
	offset = Vector2.ZERO
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rotation = angle
	global_position = origin + Vector2.RIGHT.rotated(angle) * half_len  # spin은 half_len = 0 = origin
	# 텍스처가 2×2라 월드 한 변 = 2*scale → scale = quad/2. 🔴 **균일 스케일만** — 비균일이면
	#   정원이 타원이 되어 판정과 어긋난다(rules §3 콘 계약이 두 번 기각한 우회로).
	scale = Vector2.ONE * (quad * 0.5)
	z_index = 3                            # 몸(1)·무기(0~2) 위 — slash_fx와 같은 층
	_base_a = tint.a
	modulate = tint                        # 🔴 색은 여기서만 들어간다(셰이더는 중립) — 페이드도 이 채널

	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	material = _mat
	_mat.set_shader_parameter(&"quad_px", quad)
	_mat.set_shader_parameter(&"radius_px", r)
	_mat.set_shader_parameter(&"half_len_px", half_len)
	_mat.set_shader_parameter(&"aa_px", AA_PX)
	_mat.set_shader_parameter(&"rim_px", RIM_PX)
	_mat.set_shader_parameter(&"fill_color",
		Color(1, 1, 1, TRAVEL_FILL_ALPHA if is_travel else FILL_ALPHA))
	_mat.set_shader_parameter(&"edge_color", Color(1, 1, 1, EDGE_ALPHA))
	_mat.set_shader_parameter(&"edge_glow", EDGE_GLOW)
	# 🔴 두 강조는 **배타적으로** 심는다 — 안 그러면 beam에 회전 스포크가, spin에 축 심이 겹쳐
	#   형태가 무엇인지 안 읽힌다(셰이더는 켜진 쪽만 계산하도록 amp = 0을 존중한다).
	_mat.set_shader_parameter(&"swirl_amp", 0.0 if is_beam else 1.0)
	# 🔴 이동형만 「초당 회전 수 × 수명」으로 바퀴 수를 유도한다 — 상수 주석이 근거(수명에 묶으면
	#   사거리가 길수록 느리게 도는 것처럼 보인다). 제자리는 `SWIRL_TURNS` 그대로 = 완전 항등.
	_mat.set_shader_parameter(&"swirl_turns",
		(TRAVEL_SWIRL_RATE * _life_total) if is_travel else SWIRL_TURNS)
	_mat.set_shader_parameter(&"swirl_width", TRAVEL_SWIRL_WIDTH if is_travel else SWIRL_WIDTH)
	_mat.set_shader_parameter(&"swirl_spokes", TRAVEL_SPOKES if is_travel else 1.0)  # 1.0 = 도입 전 항등
	_mat.set_shader_parameter(&"ring_amp", 1.0 if is_travel else 0.0)                # 0.0 = 도입 전 항등
	_mat.set_shader_parameter(&"ring_ratio", TRAVEL_RING_RATIO)
	_mat.set_shader_parameter(&"ring_px", TRAVEL_RING_PX)
	_mat.set_shader_parameter(&"core_amp", 1.0 if is_beam else 0.0)
	_mat.set_shader_parameter(&"core_ratio", CORE_RATIO)
	_mat.set_shader_parameter(&"progress", 0.0)


# ⚠ `_process`(시각)다 — 충돌·판정이 없는 순수 표시라 물리 프레임에 묶을 이유가 없다(slash_fx와 같은 자리).
# ⚠ **호스트 판정은 `_physics_process`에서 민다**(combat_authority) — 프레임 격자가 달라 최대 한
#   프레임(≈16ms = 5px)만큼 어긋날 수 있다. 판정 반경 46 + 몸 반경 12에 비해 무시 가능하고,
#   화살(arrow.gd)이 이미 같은 비대칭으로 살고 있다(표시는 `_process`·권한은 `_physics_process`).
func _process(delta: float) -> void:
	_life += delta
	# 🔴 이동형 전진 — 속도는 `setup`이 받은 것 그대로다(여기서 만들지 않는다). 제자리면 ZERO = 항등.
	if _vel != Vector2.ZERO:
		global_position += _vel * delta
	var total := maxf(_life_total, 0.0001)
	if _mat != null:
		_mat.set_shader_parameter(&"progress", clampf(_life / total, 0.0, 1.0))
	if _life >= total * _fade_at:
		var t := (_life - total * _fade_at) / maxf(total * (1.0 - _fade_at), 0.0001)
		modulate.a = _base_a * maxf(0.0, 1.0 - t)
	if _life >= total:
		queue_free()

# 🔴 **`material = null`로 떼지 않는다** — rules §5의 "끝나면 머티리얼을 떼라"가 겨누는 것은
#   `hit_flash`처럼 **평상시에도 렌더되는 노드**다(웹 Compatibility에서 amount=0이 항등이 아니라
#   "한 대 맞고 색이 안 돌아옴"이 된다). 이 노드는 셰이더가 곧 비주얼이고 수명이 끝나면 통째로
#   `queue_free`되므로 "항등을 물을 off 상태"가 존재하지 않는다 — slash_fx·보스 텔레그래프와 같은 예외다.
#   ⚠ 떼면 남는 것이 2×2 흰 쿼드라 오히려 거대한 흰 사각이 한 프레임 뜬다.
