extends Sprite2D
# 검성 검기(날아가는 반달) — 표시 전용(판정 없음, GDD §6)·각 클라 로컬(네트워크 메시지·필드 0).
# 씬 루트에 붙어 `_swing_dir` 방향으로 전진한다. 형태는 `assets/shaders/slash_crescent.gdshader`가
# 그리고, 이 스크립트는 **기하를 셰이더에 심고 수명을 굴리는 일**만 한다.
#
# 🔴 **시트(AnimatedSprite2D + slash_1~3_frames.tres)에서 셰이더로 갈아탔다**(2026-08-02 사용자 확정).
#   옛 방식은 1타 = 가로 스파크 · 2타 = 링(원) · 3타 = 두꺼운 초승달로 **셋이 서로 다른 형태**라
#   "같은 검기가 타수마다 커진다"로 안 읽혔고, 색도 시트에 노랑으로 구워져 있어 하위 직업 틴트가
#   궤적 리본에만 걸리고 검기만 노란색으로 남았다.
#   ⚠ 잠깐 `vortex_fx.gd`(롤-어택 소용돌이)가 갈래로 살아 있었지만 **사용자 요청으로 제거**했다
#   (2026-08-02 같은 날). 지금 검성 검기의 배우는 이 파일 하나뿐이다.
#
# 🔴 **크기의 출처는 판정이다 — 여기서 만들지 않는다.** 반경·반각은 호출부(`player._crescent_radius`
#   /`_crescent_half_angle`)가 `CombatMath.effective_attack_range`·`melee_show_half_angle` 단일
#   소스에서 유도해 넘긴다. 아래 const에 도달 거리를 만들어 내는 값은 **하나도 없다**(전부 비율·연출).
#
# preload로만 쓴다(const SlashFx := preload(...)) — rules §0 `class_name` 금지.

const SHADER := preload("res://assets/shaders/slash_crescent.gdshader")

# --- 연출값 (rules §0 예외 = 손맛 상수. 밸런스가 아니다 — 판정에 한 픽셀도 안 닿는다) ---
const SPEED := 330.0        # 앞으로 날아가는 속도(px/s) — 시트 시절과 같은 값(체감 유지)
const LIFE := 0.7           # 수명(s)
const FADE_AT := 0.72       # 이 수명 비율부터 알파 페이드 시작
# 다단 한 타의 수명 = 타 간격 × 이 비율 (상한 `LIFE`). `skill_fx.MULTI_LIFE_RATIO`의 미러가 아니라
# **같은 관용구의 각자 값**이다 — 아래 `multi_life_s` 주석이 근거.
const MULTI_LIFE_RATIO := 1.6
# 날 두께 = 중심선 반경 × 이 비율. 🔴 **닮음이라 반경 하나만 키우면 두께가 따라온다** — 두께를
#   독립 상수(px)로 두면 좁은 무기(창 반각 0.3)에서만 뭉툭해지고 그 이유가 화면에 안 드러난다.
#
# 🔴🔴 **비율이 무기 무게에서 나온다** (2026-08-02 사용자 신고: *"검성 평타마다 검기가 날아가야
#   하는데 파쇄 도끼를 껴도 똑같음"*). 실측이 그 신고를 그대로 뒷받침했다 — 검기가 무기에서 받던
#   축은 **반경·반각뿐**이라 1타 기준 도끼 42px/68° vs 낡은 대검 46px/52°로 크기가 사실상 같았고,
#   두께는 상수 0.28을 곱한 결과 **도끼 11.8px < 대검 13.0px**로 오히려 도끼가 얇았다.
#   그런데 두 무기의 **무게는 4.4배** 차이다(`hit_shake` 4.4 vs 1.0).
# 🔴 **무게의 출처는 `CombatMath.weapon_weight` 하나다 — `EquipDef`에 두께·질감 필드를 만들지 마라**
#   (rules §3: 스크린셰이크·카메라 킥·적중 박힘·넉백이 전부 그 한 함수에서 나온다. 여기만 다른
#   숫자를 쥐면 "도끼를 무겁게 조였는데 검기만 그대로"가 된다).
# 🔴 **반경·반각은 한 픽셀도 안 건드린다** — 그 둘은 판정에서 유도되므로(`_crescent_radius`/
#   `_crescent_half_angle`) 손대는 순간 §3 「표시 ≥ 판정」이 흔들린다. 무게가 바꾸는 것은
#   **두께·뾰족함**뿐이고, 둘 다 호(弧) **위**의 성질이라 도달 거리·각을 만들지 않는다.
# ⚠ 정의역은 `HIT_WEIGHT_MIN`~`MAX`(= `weapon_weight`가 clamp하는 그 범위)다 — 데이터 실측값을
#   여기 적으면 무기가 하나 늘 때마다 갈라지는 두 번째 진실원이 된다.
#   현행 4종의 무게: 파쇄 도끼 2.933 · 철 대검 1.733 · 창 1.200 · 낡은 대검 0.667.
const THICK_RATIO_LIGHT := 0.16   # 무게 하한에서의 비율 — 얇은 결
const THICK_RATIO_HEAVY := 0.52   # 무게 상한에서의 비율 — 두꺼운 덩어리
#   ⇒ 1타 실측(검성 reach 0.3): 파쇄 도끼 **21.5px** vs 낡은 대검 **9.1px** = 2.4배 (전 12/13px)
# 🔴 **두께의 두 번째 상한 = 호 길이에서 유도한다.** 반경만 보면 창(반각 0.3rad · 도달 104px)에서
#   두께 20.8 vs 반호 길이 15.6이 되어 **반달이 아니라 덩어리**가 된다(길이보다 두꺼운 초승달은 없다).
#   ⚠ 좁은 무기에서만 걸리는 상한이라 대검·도끼는 위 비율 그대로다(= 넓은 무기 항등).
#   ⚠ 0.55 → **0.75**(같은 요청). 여전히 1.0 미만이라 "길이보다 두꺼운 초승달"은 원리적으로 안 나온다
#     — 이 상한을 1.0 위로 올리는 것이 곧 창 검기가 덩어리가 되는 순간이다.
const THICK_ARC_RATIO := 0.75
# 끝 모양 지수 — 셰이더의 `half_th ∝ cos(u·π/2)^sharpness` (u = 0 중앙 → 1 호 끝).
# 🔴 **방향을 계산으로 확인하고 넣었다.** 호 끝에서 남은 호 길이를 e라 하면 `half_th ∝ e^sharpness`다:
#     지수 < 1 → e→0에서 기울기가 **무한** = 두 모서리가 호에 거의 수직으로 만난다 = **뭉툭한 뿔**
#              (도끼 실측: 호 끝 5px 지점에서도 중앙 두께의 **42%**가 남는다)
#     지수 > 1 → 기울기가 **0** = 모서리가 접선으로 수렴한다 = **바늘처럼 길게 뽑힌 끝**
#              (낡은 대검 실측: 같은 5px 지점에서 **14%**)
#   ⇒ 무거운 무기는 지수를 **내려** 끝까지 두껍고 뭉툭하게, 가벼운 무기는 **올려** 얇고 날카롭게.
# ⚠ **`slash_crescent.gdshader` 헤더의 「sharpness < 1이 뾰족한 쪽」은 이 유도와 반대 표현이다** —
#   거기서는 *몸통이 두껍게 유지된다*는 뜻으로 「뾰족」을 썼다. 형태를 말할 때는 위 지수-기울기가
#   정본이다(리드 확인 대상 — 뒤집으려면 아래 두 값을 **맞바꾸기만** 하면 된다).
# ⚠ 중앙(u=0) 두께는 지수와 무관하다(cos 0 = 1) — 즉 이 축은 **두께 축과 독립**이라 둘을 같이 써야
#   "두껍고 뭉툭" / "얇고 날카롭게"가 한눈에 갈린다.
const SHARPNESS_LIGHT := 1.25   # 무게 하한 — 길게 뽑힌 바늘 끝
const SHARPNESS_HEAVY := 0.45   # 무게 상한 — 끝까지 살점이 붙은 뭉툭한 뿔
#   ⇒ 실측: 파쇄 도끼 0.470 · 철 대검 0.840 · 창 1.004 · 낡은 대검 1.168 (전: 전부 0.65)
# 🔴 아래 다섯은 **2026-08-02에 강렬화로 올렸다**(사용자: *"검기 임팩트? 리본들을 좀더 강렬하게"*).
#   올린 것은 **밝기·대비뿐이고 기하는 한 픽셀도 안 건드렸다** — 반경·반각은 판정에서, 두께·뾰족함은
#   무게에서 유도된 그대로다(위 상수들). 세기가 과하면 여기를 내려라, 저쪽이 아니다.
# ⚠ `EDGE_ALPHA`/`CORE_ALPHA`는 전에 셰이더 기본값(0.58/0.96)에 얹혀 있었다 — **이 파일이 검기 룩의
#   단일 소스**가 되도록 명시적으로 심는다(셰이더 기본값은 에디터 프리뷰용으로만 남는다).
const CORE_RATIO := 0.46    # 심 폭 / 반두께. 전 0.40
const CORE_GLOW := 2.0      # 심 rgb 증폭(틴트를 흰 쪽으로 태운다 — 셰이더 헤더 참조). 전 1.55
const LEAD_BOOST := 0.50    # 볼록면(진행 방향) 밝기 가산. 전 0.30
const EDGE_ALPHA := 0.74    # 날 몸통 알파. 전 0.58(셰이더 기본값)
const CORE_ALPHA := 1.0     # 심 알파. 전 0.96(셰이더 기본값)
const AA_PX := 1.2          # 경계 소프트 폭(월드 px)
# 🔴 쿼드 여유 — 딱 `2*(반경 + 반두께)`면 호 끝에서 프래그먼트가 아예 안 돌아 **그려져야 하는데
#   안 그려지는** 픽셀이 생긴다. 항 둘 = ⑴ 알파 램프가 바깥으로 퍼지는 폭(AA_PX) ⑵ 프래그먼트가
#   픽셀 **중심**에서만 생기는 데서 오는 화면 반픽셀(줌 1.5에서 0.33 월드px)을 넉넉히 잡은 값.
const QUAD_MARGIN_PX := 1.5
# 수명 연출 — 얇고 좁게 태어나 퍼진다. 🔴 **`TIME`이 아니라 여기서 심는다**(셰이더 헤더의 이유:
#   TIME이면 같은 프레임에 태어난 두 검기의 위상이 갈린다).
const GROW_T := 0.28
const ARC_START := 0.45
const THIN_START := 0.35
const THIN_END := 0.72

# 🔴 2×2(1×1 아님) — 1×1은 centered 오프셋이 -0.5px 서브픽셀이라, 거대 scale을 곱하면 그 반올림
#   오차가 half-quad만큼 통째로 어긋난다(boss.gd `_telegraph_quad_tex`의 실측 사고 — 콘 apex가
#   회전 방향으로 -123px 튀었다). 2×2면 오프셋 = -1px 정수라 scale과 정확히 맞물린다.
#   UV는 텍스처 크기와 무관하게 0..1이라 셰이더 `p = (UV-0.5)*quad_px`는 그대로다(scale만 절반).
static var _quad_tex: ImageTexture = null

var _dir: Vector2 = Vector2.RIGHT
var _life: float = 0.0
var _life_total: float = LIFE
var _speed: float = SPEED
var _base_a: float = 1.0
var _mat: ShaderMaterial = null


# 🔴 **두께 유도의 단일 소스** — `setup`과 아래 역함수(`mid_r_for_outer`)가 **같은 이 함수**를 지난다.
#   호출부가 두께 식을 복제하면 그것이 곧 미러이고, 그 순간 "바깥 끝을 판정 도달에 맞췄다"는 보장이
#   조용히 깨진다(rules §3 콘 텔레그래프가 두 번 값을 치른 그 실패 형태).
# thick_scale = 두께 배율. 🔴 **1.0 = 평타 검기 = 도입 전과 완전 항등**이고, 하위 직업 스킬
#   「환영검무」만 1보다 크게 넘긴다(그쪽은 판정이 **채워진 캡슐**이라 얇은 초승달로는 안쪽이 통째로
#   빈다 — `player._spawn_skill_slash` 주석이 그 유도의 정본).
# ⚠ 반환은 **중앙(dev=0) 두께**다. 호 끝으로 갈수록 셰이더의 taper가 0으로 줄인다.
static func thick_px(mid_r: float, half_angle: float, weight: float,
		thick_scale: float = 1.0) -> float:
	return mid_r * _thick_ratio(maxf(half_angle, 0.0001), _weight_t(weight), thick_scale)


# 두께 / 중심선 반경. 🔴 **mid_r에 의존하지 않는다** — 그래서 위 역함수가 정확히 닫힌 형태다.
# 🔴🔴 **`thick_scale`은 무게 램프에만 곱하고 호 길이 상한은 그대로 둔다 — 순서가 계약이다.**
#   상한 밖에서 곱하면 "길이보다 두꺼운 초승달"을 막는 **유일한 장치**가 우회되어(상수 주석)
#   좁은 무기에서 검기가 덩어리가 된다. 안에서 곱하면 무거운 무기가 상한에 **포화**할 뿐이다
#   — 실측(스킬 scale 4.0 · 반각 1.25): 낡은 대검만 0.788로 살아 있고 창·철 대검·도끼는 셋 다
#   0.9375로 포화한다(= 스킬 반달은 무기 무게로 크게 안 갈린다. 그건 의도다 — 그 축의 주인은
#   **하위 직업 틴트**이고 무게는 `sharpness`(끝 모양)로만 남는다).
static func _thick_ratio(half_angle: float, wt: float, thick_scale: float = 1.0) -> float:
	return minf(lerpf(THICK_RATIO_LIGHT, THICK_RATIO_HEAVY, wt) * maxf(thick_scale, 0.0001),
		half_angle * THICK_ARC_RATIO)


# 🔴 **바깥 끝(볼록면)이 정확히 `outer_px`에 닿는 중심선 반경** — 위 두께 유도의 **역함수**다.
#   `outer = mid_r + thick/2 = mid_r * (1 + ratio*scale/2)` 이고 ratio는 mid_r과 무관하므로 정확히 풀린다.
# 왜 필요한가: 스킬 검기는 **판정 도달(캡슐 끝)에서 크기를 유도해야** 한다(§3 "맞는 곳 = 보이는 곳").
#   호출부가 `mid_r`을 직접 정하면 그 값이 판정과 무관한 제2의 진실원이 되어, `.tres`의 `length`를
#   조이는 순간 검기만 그대로 남는다.
static func mid_r_for_outer(outer_px: float, half_angle: float, weight: float,
		thick_scale: float = 1.0) -> float:
	var ratio := _thick_ratio(maxf(half_angle, 0.0001), _weight_t(weight), thick_scale)
	return maxf(outer_px, 1.0) / (1.0 + ratio * 0.5)


# 다단 한 타의 수명(s) — 🔴 `skill_fx.multi_life_s`와 **같은 근거·같은 형태**다(타 간격보다 오래
#   살면 다섯 장이 통째로 겹쳐 한 번 크게 번쩍인 것과 구분이 안 되고, 그러면 "와다다다"가 화면에서
#   안 읽힌다 = 이 연출의 요구사항 전부). 상한만 이 파일의 `LIFE`다.
# ⚠ 두 파일이 같은 관용구를 각자 갖는 것은 **상한이 서로 다르기 때문**이다(반달 0.7 vs 원/띠 0.34).
#   합치려면 상한을 인자로 받는 공용 함수가 필요하고 그 자리는 core다 — 리드 판단 대기.
static func multi_life_s(hit_count: int, hit_interval_s: float) -> float:
	if CombatMath.clamp_skill_hit_count(hit_count) <= 1:
		return LIFE
	return minf(LIFE, CombatMath.clamp_skill_hit_interval(hit_interval_s) * MULTI_LIFE_RATIO)


# 무게 → 0~1 보간값. 🔴 정의역을 `weapon_weight`의 clamp 범위에서 **그대로 받는다** — 실측값을
#   여기 적으면 무기가 하나 늘 때 갈라지는 두 번째 진실원이 된다(상수 주석이 근거).
static func _weight_t(weight: float) -> float:
	if not is_finite(weight):
		return 0.0
	var lo := CombatMath.HIT_WEIGHT_MIN
	var hi := CombatMath.HIT_WEIGHT_MAX
	if hi - lo <= 0.0001:
		return 0.0
	return clampf((clampf(weight, lo, hi) - lo) / (hi - lo), 0.0, 1.0)


static func _quad_texture() -> ImageTexture:
	if _quad_tex == null:
		var img := Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_quad_tex = ImageTexture.create_from_image(img)
	return _quad_tex


# angle = 진행 방향(rad, 스윙 개시 때 고정된 `_swing_dir`) · tint = 하위 직업/무기 합성 틴트
# mid_r_px = 날 중심선 반경(곡률 중심 = 노드 원점 기준) · half_angle = 호가 벌어진 반각(rad)
# 🔴 노드 원점은 **호의 곡률 중심**이다 — 호출부가 스윙 회전 중심(`WeaponPivot`)에 놓으므로
#   검기가 "휘두른 호가 그대로 떨어져 나가" 앞으로 날아가는 그림이 된다.
# 🔴 **볼록면이 진행 방향(+x)을 이끄는 것은 형태가 보장한다**(셰이더 헤더) — 옛 `flip_h` 꼼수는
#   필요가 사라져 없앴다. 되살리면 오목면이 앞을 향해 사용자 결정(2026-08-02)이 뒤집힌다.
# weight = `CombatMath.weapon_weight(equip)` — 🔴 **여기서 만들지 않는다**(그 함수가 단일 소스).
#   기본 1.0 = 무장 해제 기준값이라 무게 축 도입 전과 같은 자리다(호출부는 무기가 있을 때만 부른다).
# thick_scale/life_s/speed_px_s = 🔴 **기본값이 곧 평타 검기의 값이라 기존 호출부는 완전 항등**이다.
#   하위 직업 스킬 「환영검무」만 셋 다 바꿔 넘긴다(두껍게 · 짧게 · 거의 제자리).
func setup(angle: float, tint: Color, mid_r_px: float, half_angle: float,
		weight: float = 1.0, thick_scale: float = 1.0,
		life_s: float = LIFE, speed_px_s: float = SPEED) -> void:
	var mid_r := maxf(mid_r_px, 1.0)
	var ha := maxf(half_angle, 0.0001)
	var wt := _weight_t(weight)
	_life_total = life_s if (is_finite(life_s) and life_s > 0.0) else LIFE
	_speed = speed_px_s if is_finite(speed_px_s) else SPEED
	# 🔴 두께 = min(무게 유도 비율, 반호 길이 비율) — 둘째 항이 좁은 무기에서만 걸린다(상수 주석).
	#   ⚠ **그 상한을 무게로 흔들지 마라** — 창처럼 좁은 무기에서 검기가 덩어리가 되는 것을 막는
	#     유일한 장치이고, 실제로 창은 이 항이 지배해 무게 축 도입 전과 **두께가 같다**(10.9px).
	#   🔴 유도는 `thick_px` **한 곳**이다(위 역함수와 같은 식을 지나야 "바깥 끝 = 판정 도달"이 산다).
	var thick := thick_px(mid_r, ha, weight, thick_scale)
	var sharp := lerpf(SHARPNESS_LIGHT, SHARPNESS_HEAVY, wt)
	# 최대 반경 확장 = 중심선 + 반두께(셰이더의 두께 배율은 1.0을 넘지 않는다) + 여유.
	var quad := 2.0 * (mid_r + thick * 0.5 + AA_PX + QUAD_MARGIN_PX)

	texture = _quad_texture()
	centered = true
	offset = Vector2.ZERO
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rotation = angle
	# 텍스처가 2×2라 월드 한 변 = 2*scale → scale = quad/2. 🔴 **균일 스케일만** — 비균일이면
	#   정원이 타원이 되어 호가 진행축 말고는 어긋난다(rules §3 콘 계약이 두 번 기각한 우회로).
	scale = Vector2.ONE * (quad * 0.5)
	z_index = 3                            # 몸(1)·무기(0~2) 위
	_dir = Vector2.RIGHT.rotated(angle)
	_base_a = tint.a
	modulate = tint                        # 🔴 색은 여기서만 들어간다(셰이더는 중립) — 페이드도 이 채널

	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	material = _mat
	_mat.set_shader_parameter(&"quad_px", quad)
	_mat.set_shader_parameter(&"mid_r_px", mid_r)
	_mat.set_shader_parameter(&"thick_px", thick)
	_mat.set_shader_parameter(&"half_angle", ha)
	_mat.set_shader_parameter(&"sharpness", sharp)
	_mat.set_shader_parameter(&"aa_px", AA_PX)
	# 🔴 색 알파도 여기서 심는다 — 셰이더 기본값에 얹혀 있으면 룩의 진실원이 둘이 된다(상수 주석).
	_mat.set_shader_parameter(&"edge_color", Color(1, 1, 1, EDGE_ALPHA))
	_mat.set_shader_parameter(&"core_color", Color(1, 1, 1, CORE_ALPHA))
	_mat.set_shader_parameter(&"core_ratio", CORE_RATIO)
	_mat.set_shader_parameter(&"core_glow", CORE_GLOW)
	_mat.set_shader_parameter(&"lead_boost", LEAD_BOOST)
	_mat.set_shader_parameter(&"grow_t", GROW_T)
	_mat.set_shader_parameter(&"arc_start", ARC_START)
	_mat.set_shader_parameter(&"thin_start", THIN_START)
	_mat.set_shader_parameter(&"thin_end", THIN_END)
	_mat.set_shader_parameter(&"progress", 0.0)


# ⚠ `_process`(시각)다 — 충돌·판정이 없는 순수 표시 이동이라 물리 프레임에 묶을 이유가 없다
#   (시트 시절과 같은 자리 = 체감 무변경).
func _process(delta: float) -> void:
	global_position += _dir * _speed * delta
	_life += delta
	var total := maxf(_life_total, 0.0001)
	if _mat != null:
		_mat.set_shader_parameter(&"progress", clampf(_life / total, 0.0, 1.0))
	if _life >= total * FADE_AT:
		var t := (_life - total * FADE_AT) / maxf(total * (1.0 - FADE_AT), 0.0001)
		modulate.a = _base_a * maxf(0.0, 1.0 - t)
	if _life >= total:
		queue_free()

# 🔴 **`material = null`로 떼지 않는다** — rules §5의 "끝나면 머티리얼을 떼라"가 겨누는 것은
#   `hit_flash`처럼 **평상시에도 렌더되는 노드**다(웹 Compatibility에서 amount=0이 항등이 아니라
#   "한 대 맞고 색이 안 돌아옴"이 된다). 이 노드는 셰이더가 곧 비주얼이고 수명이 끝나면 통째로
#   `queue_free`되므로 "항등을 물을 off 상태"가 존재하지 않는다 — 보스 텔레그래프와 같은 예외다.
#   ⚠ 떼면 남는 것이 2×2 흰 쿼드라 오히려 거대한 흰 사각이 한 프레임 뜬다.
