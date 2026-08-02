shader_type canvas_item;
// 검성 검기(날아가는 반달) — 🔴 **형태를 코드가 그린다.**
//
// 왜: 시트 방식이었을 때 1타 = 가로 스파크 · 2타 = 링 · 3타 = 초승달로 **셋이 서로 다른 형태**라
//   "같은 검기가 타수마다 커진다"로 안 읽혔고, 크기·각을 조이려면 매번 재작화가 필요했다.
//   (보스 텔레그래프가 텍스처 계약을 버린 것과 같은 이유 — 사람이 지키는 미러는 조용히 갈라진다.)
// ⚠ **이것은 표시 전용이고 판정이 없다**(GDD §6: 검기 자체 데미지 없음). 그래서 boss_telegraph와
//   달리 "판정식을 그대로 그린다"가 아니라 **판정에서 유도한 크기로 그린다** — 반경·반각의 출처는
//   `player.gd`의 `_crescent_radius`/`_crescent_half_angle`이고 둘 다 CombatMath 단일 소스를 지난다.
//
// 좌표 규약 (slash_fx.gd `_apply_geometry`와 미러 — 한쪽을 고치면 같이 고친다):
//   쿼드 = 2×2 흰 텍스처 + centered + **균일** scale(= quad_px/2) → 월드 한 변 = quad_px
//     🔴 1×1을 쓰지 마라 — centered 오프셋 -0.5px가 거대 scale에 곱해져 half-quad만큼 어긋난다
//       (boss.gd `_telegraph_quad_tex` 실측 사고: 콘 apex가 -123px 튀었다).
//   ⇒ 노드 원점 = **호의 곡률 중심** = 스윙 회전 중심(`WeaponPivot`), rotation = `_swing_dir`.
//   ⇒ p = (UV - 0.5) * quad_px 는 **월드 px 오프셋**(로컬 = 진행 방향 정렬 프레임).
//     회전 + 균일 스케일은 닮음변환이라 길이·각비가 보존된다 — 전단·타원 없음.
//   🔴 quad_px는 반경과 **분리된** 값이다. 딱 2*(mid_r + thick/2)로 두면 호 끝에서 프래그먼트가
//     아예 안 돌아 **그려져야 하는데 안 그려지는** 픽셀이 생긴다 → 여유(aa + 마진)를 더해 받는다.
//
// 형태 = 고리 부채꼴(annulus sector) + 끝 뾰족함:
//   r        = length(p)                       (곡률 중심에서의 거리)
//   dev      = |atan(p.y, p.x)|                (로컬 프레임 진행방향 = +x = 각 0)
//   half_th  = thick_px*0.5 * cos(clamp(dev/half_angle,0,1) * PI/2) ^ sharpness
//   안쪽     = |r - mid_r_px| <= half_th
//   🔴 **각 게이트가 따로 없다 — taper가 그 일을 겸한다.** dev >= half_angle이면 clamp가 1로 물려
//     cos(PI/2) = 0 → half_th = 0 → 어떤 r도 안쪽이 아니다. 별도 `d_side`를 더하면 같은 경계를
//     두 식이 정하게 되어 갈라질 축이 생긴다(보스 콘은 옆면이 **직선**이라 그쪽이 필요했다).
//   ⇒ 중앙이 가장 두껍고 양 끝으로 갈수록 0으로 수렴 = **초승달 끝의 뾰족함**.
//   🔴 **`sharpness`는 끝 모양의 지수다 — 방향의 정본은 `slash_fx.gd`의 상수 주석(유도 포함)이다.**
//     호 끝에서 남은 호 길이 e에 대해 `half_th ∝ e^sharpness`이므로:
//       지수 < 1 → e→0에서 기울기 무한 = 끝까지 살점이 붙은 **뭉툭한 뿔**(무거운 무기)
//       지수 > 1 → 기울기 0 = 접선으로 수렴하는 **바늘 끝**(가벼운 무기)
//     중앙(u=0) 두께는 지수와 무관하다(cos 0 = 1) — 두께 축(`thick_px`)과 **독립**이다.
//     ⚠ 2026-08-02 이전 이 줄은 *"sharpness < 1이 뾰족한 쪽"* 이라고 적혀 있었다. 그것은
//       「몸통이 두껍게 유지된다」는 뜻이었는데, 끝 모양을 정하는 축으로 읽으면 부호가 반대라
//       무게 유도를 거꾸로 넣게 된다. 값은 `slash_fx.gd`가 무기 무게에서 전량 덮어쓴다.
//
// 🔴 **볼록면(convex)이 진행 방향(+x)을 이끈다** — 이것이 사용자 결정이고(구 slash_fx.gd:23의
//   `flip_h` 꼼수가 하던 일), 여기서는 **형태로** 보장된다: 호의 바깥(r > mid_r)이 곧 +x 쪽이므로
//   미러링 자체가 필요 없다. flip 배선을 되살리지 마라.
//
// 수명 연출: 🔴 **`TIME`이 아니라 스크립트가 심는 `progress`로 구동한다.** TIME으로 만들면 같은
//   프레임에 태어난 두 검기가 **다른 위상**을 갖고(TIME은 전역 절대시각), 콤보를 이어 치면 2타가
//   1타의 중간 상태로 튀어나온다. progress는 각 노드가 자기 `_life / LIFE`로 심는다.
//   꼬리 페이드는 셰이더가 아니라 `modulate.a`가 한다(이 프로젝트 FX 관용구 — 아래 COLOR 항 참조).
//
// 웹(Compatibility/GLES3) 안전: atan·length·sin·cos·pow·mix·min·smoothstep·clamp + UV/COLOR/TEXTURE만.
//   🔴 **fwidth/derivative 없음**(안전 목록 밖, rules §5) — 경계 폭은 전부 월드 px(`aa_px`)로 직접 준다.
//   🔴 **격자 스냅 없음** — boss_telegraph가 2026-08-02에 폐기한 그 기법이다(캐릭터 32px + 줌 1.5에서
//     3px 계단이 되어 사용자가 *"너무 픽셀 같고 뭔가 이상하다"* 고 신고했다). 부드러운 경계로 간다.

// ⚠ 기본값도 유도식을 따른다(mid_r 48 · thick 14 기준) — 런타임엔 slash_fx.gd가 전량 덮어쓰지만,
//   기본값이 유도와 어긋나면 에디터 프리뷰가 틀린 도형을 보여준다.
uniform float quad_px = 116.0;      // 쿼드 월드 한 변 = 2*(mid_r + thick/2 + aa_px + 마진)
uniform float mid_r_px = 48.0;      // 날의 **중심선** 반경(곡률 중심 기준)
uniform float thick_px = 14.0;      // 중앙(dev=0)에서의 날 두께(월드 px)
uniform float half_angle = 1.0;     // 반각(rad) — 이 각에서 두께가 정확히 0이 된다 = 호의 끝
uniform float sharpness = 0.65;     // 끝 뾰족함. <1 = 몸통 두껍고 끝만 날카롭다(위 주석)
uniform float aa_px = 1.2;          // 경계 소프트 폭(월드 px)

// --- 색 ---
// 🔴 **중립(무채)로 두고 색은 `modulate`가 입힌다** — §4 「폭발 텍스처는 그레이스케일 + swing_color」와
//   같은 관용구다. 여기에 색을 박으면 하위 직업 틴트(검성 하늘 / 광전사 붉음)가 먹혀 갈라진다.
uniform vec4 edge_color : source_color = vec4(1.0, 1.0, 1.0, 0.58);  // 날의 몸통(반투명)
uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 0.96);  // 날 한가운데 심(밝고 진하다)
uniform float core_ratio = 0.40;    // 심 폭 / 그 자리 반두께 (0 = 심 없음)
// 심의 rgb 증폭 — 🔴 곱으로는 "흰색으로 뜨겁게"가 안 나온다(틴트가 이미 곱해져 색상이 고정된다).
//   1보다 크게 올려 채널을 포화시키면 **하늘색 → 시안-화이트**로 뜨거워진다(값싼 desaturate).
uniform float core_glow = 1.55;
// 볼록면(바깥 = 진행 방향)을 살짝 더 밝게 — "날이 앞을 이끈다"를 한 줄로.
uniform float lead_boost = 0.30;

// --- 수명(progress) — 얇고 좁게 태어나 퍼진다 ---
uniform float progress = 0.0;       // 0 = 태어난 순간, 1 = 수명 끝
uniform float grow_t = 0.28;        // 이 진행도까지 벌어진다(그 뒤는 다 벌어진 상태)
uniform float arc_start = 0.45;     // 태어날 때의 반각 비율(1 = 처음부터 다 벌어짐 = 연출 없음)
uniform float thin_start = 0.35;    // 태어날 때의 두께 비율
uniform float thin_end = 0.72;      // 수명 끝의 두께 비율(날이 늘어지며 얇아진다)

void fragment() {
	// 🔴 incoming COLOR = modulate × self_modulate × vertex color. fragment를 오버라이드하면
	// 기본 캔버스 렌더(텍스처×모듈레이트)가 사라지므로 **직접 곱해 재현한다**(rules §2 등재 계약).
	// 안 곱하면 `slash_fx.gd`의 꼬리 페이드(`modulate.a`)가 **에러 없이 안 먹는다** — 이 프로젝트
	// FX 페이드가 전부 그 관용구다(afterimage·damage_numbers·coop_authority). COLOR는 inout이라
	// 덮기 전에 잡아 둔다.
	vec4 mod_c = COLOR;
	vec2 p = (UV - vec2(0.5)) * quad_px;

	float pr = clamp(progress, 0.0, 1.0);
	float grow = smoothstep(0.0, max(grow_t, 0.0001), pr);
	// 벌어짐 — 반각과 두께가 같은 `grow`를 타므로 태어날 때 "짧고 얇은 결"이었다가 반달이 된다.
	float ha = max(half_angle * mix(arc_start, 1.0, grow), 0.0001);
	float th = max(thick_px * mix(thin_start, 1.0, grow) * mix(1.0, thin_end, pr), 0.0);

	float r = length(p);
	float dev = abs(atan(p.y, p.x));
	// 각 taper: 중앙 최대 → 반각에서 정확히 0 = **끝 뾰족함**을 만든다.
	// 🔴 이것이 각 게이트를 겸한다고 읽지 마라 — 겸하지 못한다(아래 `d_side` 주석이 근거).
	float u = clamp(dev / ha, 0.0, 1.0);
	float half_th = th * 0.5 * pow(max(cos(u * PI * 0.5), 0.0), max(sharpness, 0.0001));
	float band = r - mid_r_px;              // + = 바깥(볼록면 = 진행 방향 쪽)
	// 🔴 **각 게이트는 taper와 별개로 필요하다 — taper 혼자로는 반각 밖이 안 잘린다.**
	//   반각 밖에서 u가 1로 clamp돼 half_th = 0이 되지만, 정확히 중심선 반경 위(band ≈ 0)인 픽셀은
	//   d = 0이라 `smoothstep(-aa, 0, 0)` = **1(완전 불투명)** 이 된다. 그 픽셀들이 반경 mid_r_px의
	//   원을 한 바퀴 이어 **폭 ~2*aa_px의 링**을 그린다 — 2026-08-02에 사용자가 버린 `slash_2`(링)
	//   그림이 유령으로 되돌아오는 것이고, **반각이 좁을수록 심하다**(창 반각 10° = 원의 350°가 링).
	//   ⚠ 각이 아니라 옆면까지의 **수직거리**로 재야 aa_px와 단위가 같아 "안쪽 알파 1"이 각 축에서도
	//     그대로 성립한다(boss_telegraph의 `d_side`와 같은 유도 — clamp는 |ha-dev| > 90°에서 sin이
	//     다시 줄어 깊숙한 안/밖을 경계로 오판하는 것을 막는 포화다).
	float d_side = r * sin(clamp(ha - dev, -PI * 0.5, PI * 0.5));
	float d = min(half_th - abs(band), d_side);   // > 0 = 날 안쪽
	float aa = max(aa_px, 0.0001);
	// 🔴 안쪽(d >= 0)에서 알파 1, **바깥으로만** aa px에 걸쳐 사라진다 — boss_telegraph와 같은 부호다.
	//   `smoothstep(0, aa, d)`처럼 안쪽으로 옮기면 날 경계 안쪽 aa px가 반투명해져 얇은 끝이 통째로
	//   사라진다(창은 반각 0.3rad이라 그 손실이 특히 크다).
	float a = smoothstep(-aa, 0.0, d);

	// 심(core) — 날 한가운데의 밝고 진한 줄. 검기로 읽히게 하는 것이 이 한 겹이다.
	float core_w = half_th * clamp(core_ratio, 0.0, 1.0);
	float core = 1.0 - smoothstep(max(core_w - aa, 0.0), core_w + aa, abs(band));
	vec4 col = mix(edge_color, core_color, core);
	col.rgb *= mix(1.0, max(core_glow, 0.0), core);
	// 볼록면 쪽으로 갈수록 밝게(= 날의 앞날). half_th가 0에 수렴하는 끝에서도 0 나눗셈이 없게 가드.
	col.rgb *= 1.0 + lead_boost * clamp(band / max(half_th, 0.0001), 0.0, 1.0);

	// 텍스처는 "무늬"로만 곱한다 — 2×2 흰색이면 정확히 항등이다.
	// ⚠ **형태를 그린 텍스처를 물리지 마라** — 알파가 셰이더 형태를 다시 잘라 정합이 깨진다
	//   (boss_telegraph 헤더의 같은 조항).
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(col.rgb * tex.rgb, clamp(col.a * tex.a * a, 0.0, 1.0)) * mod_c;
}
