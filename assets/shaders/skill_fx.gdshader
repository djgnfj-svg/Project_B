shader_type canvas_item;
// 하위 직업 스킬 FX(회전 베기 · 비검) — 🔴 **판정식을 그대로 그린다.**
//
// 왜 새로 만들었나 (재사용 검토 결과 — 두 후보 다 형태가 안 맞았다):
//   ⑴ `slash_crescent.gdshader`(검성 검기)는 **고리 부채꼴의 테두리**를 그린다. 스킬 판정은
//      `is_skill_hit` = **채워진 영역**(원 / 캡슐)이라, 그걸로 그리면 바깥 반경이
//      `mid_r + thick/2`로 나와 **판정 반경의 역산 미러**가 호출부(player.gd)에 생긴다 —
//      "사람이 지키는 미러는 조용히 갈라진다"(rules §3 콘 텔레그래프 판례)에 그대로 걸린다.
//      또 beam(띠)은 고리 부채꼴로 표현할 수 없다.
//   ⑵ `boss_telegraph.gdshader`는 기하가 정확히 맞다(캡슐 uniform까지 있다). 하지만 그것이 그리는
//      것은 **위험 예고**다 — 공사장 빗금 해칭 · 알파 맥동 · 차오름(임박도) · 마지막 번쩍.
//      플레이어 자기 공격에 그 언어를 쓰면 "이건 피해야 하는 장판"으로 읽힌다. 유니폼으로
//      중화할 수는 있으나(duty=1·pulse=0) 그러면 `progress`의 뜻(임박도)까지 반대가 되어
//      다음 사람이 보스 예고를 튜닝할 때 이쪽이 조용히 따라 바뀐다.
//
// 그래서 **기하만** 같은 유도를 쓰고 색·연출은 공격 언어로 새로 썼다. 기하 식은 아래 한 줄이고
// 그것이 `CombatMath.is_skill_hit`이 평가하는 조건 **그 자체**다:
//   qx = max(|p.x| - half_len_px, 0)      (캡슐 축 선분 밖으로 나간 만큼만)
//   r  = length(vec2(qx, p.y))            (선분까지의 최단거리)
//   안쪽 ⟺ r <= radius_px
//   🔴 **half_len_px = 0이면 원과 비트 단위로 동일하다** — qx = |p.x| 이고
//      length(vec2(|p.x|, p.y)) = sqrt(p.x*p.x + p.y*p.y) = length(p) (부호 무관, 반올림까지 같다).
//      ⇒ spin = `is_strike_hit(적, 시전자, radius)` · beam = `capsule_depth(적, 시전자, 끝, radius) >= 0`.
//      (boss_telegraph 헤더의 항등 증명과 같은 것 — 같은 유도를 두 번 쓰는 것이 아니라
//       **같은 CombatMath 함수**를 두 셰이더가 각자 그리는 것이다.)
//
// 좌표 규약 (skill_fx.gd `setup`과 미러 — 한쪽을 고치면 같이 고친다):
//   쿼드 = 2×2 흰 텍스처 + centered + **균일** scale(= quad_px/2) → 월드 한 변 = quad_px
//     🔴 1×1을 쓰지 마라 — centered 오프셋 -0.5px가 거대 scale에 곱해져 half-quad만큼 어긋난다
//       (boss.gd `_telegraph_quad_tex` 실측 사고: 콘 apex가 -123px 튀었다).
//   🔴 노드 원점 = **캡슐 축 선분의 중점**이다(원의 중심이 아니다). spin은 half_len = 0이라
//     중점 = 시전자 위치로 같아진다. beam은 `시전자 + 방향 × length/2`.
//   rotation = 발동 방향 · p = (UV - 0.5) * quad_px 는 **월드 px 오프셋**(로컬 = 방향 정렬 프레임).
//   회전 + 균일 스케일은 닮음변환이라 길이·각비가 보존된다 — 전단·타원 없음.
//   🔴 quad_px는 반경과 **분리된** 값이다. 딱 2*(half_len + radius)로 두면 경계에서 프래그먼트가
//     아예 안 돌아 **판정 안인데 안 그려지는** 픽셀이 생긴다 → 여유(aa + 마진)를 더해 받는다.
//
// 🔴 **크기를 여기서 만들지 않는다.** radius_px·half_len_px는 `SkillDef.radius`/`length`에서
//   그대로 온다(연출 배율 0개). 스킬 범위를 바꾸려면 `.tres`를 고쳐라 = 밸런스 변경.
//
// 웹(Compatibility/GLES3) 안전: length·atan·fract·min·max·mix·smoothstep·clamp + UV/COLOR/TEXTURE만.
//   🔴 **fwidth/derivative 없음**(안전 목록 밖, rules §5) — 경계 폭은 전부 월드 px(`aa_px`)로 직접 준다.
//   🔴 **격자 스냅 없음** — boss_telegraph가 2026-08-02에 폐기한 기법이다(줌 1.5에서 3px 계단).
//   🔴 **`TIME` 없음** — 같은 프레임에 태어난 두 FX의 위상이 갈리지 않게 `progress`를 스크립트가 심는다
//     (slash_crescent와 같은 규약).

// ⚠ 기본값도 유도식을 따른다(radius 88 · half_len 0 기준) — 런타임엔 skill_fx.gd가 전량 덮어쓰지만,
//   기본값이 유도와 어긋나면 에디터 프리뷰가 틀린 도형을 보여준다.
uniform float quad_px = 181.4;      // = 2*(half_len + radius + aa_px + 마진)
uniform float radius_px = 88.0;     // spin = 판정 원 반경 / beam = 관통 띠의 **반폭** (= SkillDef.radius)
uniform float half_len_px = 0.0;    // beam = SkillDef.length / 2 · 🔴 spin = 0 = 원과 완전 항등
uniform float aa_px = 1.2;          // 경계 소프트 폭(월드 px)
uniform float rim_px = 7.0;         // 테두리 밝은 띠의 두께(경계 **안쪽**으로)

// --- 색 ---
// 🔴 **중립(무채)로 두고 색은 `modulate`가 입힌다** — §4 「폭발 텍스처는 그레이스케일 + swing_color」와
//   같은 관용구다. 여기에 색을 박으면 하위 직업 틴트(검성 하늘 / 광전사 붉음)가 먹혀 갈라진다.
uniform vec4 fill_color : source_color = vec4(1.0, 1.0, 1.0, 0.20);  // 판정 영역 전체(옅게 — "여기가 범위다")
uniform vec4 edge_color : source_color = vec4(1.0, 1.0, 1.0, 0.92);  // 테두리·심(밝고 진하다)
// 강조부 rgb 증폭 — 🔴 곱으로는 "흰색으로 뜨겁게"가 안 나온다(틴트가 이미 곱해져 색상이 고정된다).
//   1보다 크게 올려 채널을 포화시키면 하늘색 → 시안-화이트로 뜨거워진다(slash_crescent와 같은 값싼 desaturate).
uniform float edge_glow = 1.5;

// --- 수명(progress) — 회전 하이라이트의 위상만 굴린다. 🔴 **형태는 안 건드린다** ---
//   판정은 한순간이고 FX는 그것을 몇 프레임에 걸쳐 보여줄 뿐이라, 크기가 자라면 그 사이가
//   「표시 < 판정」이 된다(§3 금지 방향). 그래서 태어난 첫 프레임부터 **판정 전체 크기**다.
uniform float progress = 0.0;

// 회전 하이라이트(spin 전용 — 도는 칼날). beam에서는 amp = 0.
uniform float swirl_amp = 0.0;
uniform float swirl_turns = 1.7;    // 수명 동안 도는 바퀴 수
uniform float swirl_width = 0.15;   // 하이라이트 폭(**한 살 구간**을 1로 본 비율)
// 살(스포크) 개수 — 🔴 **1.0 = 도입 전과 비트 단위로 동일**(`fract(x * 1.0)` = `fract(x)`).
//   이동형 「월륜」이 **바퀴**로 읽히려면 살이 하나로는 부족하다(한 줄은 "선"이지 "바퀴"가 아니다).
// ⚠ 각 축에 곱하므로 살 간격은 정확히 1/n로 균등하고, 회전 속도는 `swirl_turns` 그대로다
//   (`(base + rot) * n` 이라 살 위치가 `base = -rot + k/n` — rot 계수가 1로 유지된다).
uniform float swirl_spokes = 1.0;
// 축 심(beam 전용 — 앞으로 뻗는 검기의 날). spin에서는 amp = 0.
uniform float core_amp = 0.0;
uniform float core_ratio = 0.38;    // 심 반폭 / radius_px
// 안쪽 밝은 고리(이동형 「월륜」 전용) — 🔴 **0 = 도입 전 항등**.
// ⚠ 이것은 **판정 경계가 아니다**(그건 `rim`이다). 바퀴의 테를 하나 더 그려 "굴러간다"를 만드는
//   순수 장식이라, 여기 반경을 판정 도달로 착각하지 않도록 `rim`보다 **안쪽**에만 둔다.
uniform float ring_amp = 0.0;
uniform float ring_ratio = 0.62;    // 고리 반경 / radius_px (1 미만 = 반드시 경계 안쪽)
uniform float ring_px = 5.0;        // 고리 두께(월드 px)

void fragment() {
	// 🔴 incoming COLOR = modulate × self_modulate × vertex color. fragment를 오버라이드하면
	// 기본 캔버스 렌더(텍스처×모듈레이트)가 사라지므로 **직접 곱해 재현한다**(rules §2 등재 계약).
	// 안 곱하면 `skill_fx.gd`의 꼬리 페이드(`modulate.a`)가 **에러 없이 안 먹는다** — 이 프로젝트
	// FX 페이드가 전부 그 관용구다(afterimage·damage_numbers·slash_fx). COLOR는 inout이라 먼저 잡는다.
	vec4 mod_c = COLOR;
	vec2 p = (UV - vec2(0.5)) * quad_px;

	// 🔴 판정식 그 자체 (헤더의 항등 증명 참조) — half_len_px = 0이면 원.
	float qx = max(abs(p.x) - half_len_px, 0.0);
	float r = length(vec2(qx, p.y));
	float d = radius_px - r;                      // + = 판정 안쪽
	float aa = max(aa_px, 0.0001);
	// 🔴 판정 안(d >= 0) = 알파 1, **바깥으로만** aa px에 걸쳐 사라진다 — boss_telegraph와 같은 부호다.
	//   `smoothstep(0, aa, d)`처럼 안쪽으로 옮기면 경계 안쪽 aa px가 반투명해져 "판정 안인데 흐린" 띠가 생긴다.
	float inside = smoothstep(-aa, 0.0, d);

	// 테두리 — 경계에서 안쪽으로 rim_px. 여기가 "여기까지 닿는다"를 읽게 하는 한 겹이다.
	float rim = 1.0 - smoothstep(0.0, max(rim_px, 0.0001), d);
	// 축 심(beam) — 축까지의 거리 r이 0에 가까울수록 밝다. 띠 한가운데를 지나는 검기의 날.
	float core = core_amp * (1.0 - smoothstep(0.0, max(radius_px * core_ratio, 0.0001), r));
	// 회전 하이라이트(spin) — 각 방향 스포크가 수명 동안 돈다("몸을 축으로 돌아 벤다").
	// ⚠ fract 랩(1→0)에서도 끊기지 않게 0까지의 **환형 거리**로 잰다.
	float ang = fract((atan(p.y, p.x) / (2.0 * PI) + progress * swirl_turns) * max(swirl_spokes, 1.0));
	float sw = max(swirl_width, 0.0001);
	float swirl = swirl_amp * (1.0 - smoothstep(0.0, sw, min(ang, 1.0 - ang)));
	// 안쪽 고리(이동형 「월륜」) — 판정 경계가 아니라 장식이다(uniform 주석이 근거).
	float ring = ring_amp
		* (1.0 - smoothstep(0.0, max(ring_px, 0.0001), abs(r - radius_px * clamp(ring_ratio, 0.0, 1.0))));

	float hi = clamp(max(max(rim, core), max(swirl, ring)), 0.0, 1.0);
	vec4 col = mix(fill_color, edge_color, hi);
	col.rgb *= mix(1.0, max(edge_glow, 0.0), hi);

	// 텍스처는 "무늬"로만 곱한다 — 2×2 흰색이면 정확히 항등이다.
	// ⚠ **형태를 그린 텍스처를 물리지 마라** — 알파가 셰이더 형태를 다시 잘라 정합이 깨진다
	//   (boss_telegraph·slash_crescent 헤더의 같은 조항).
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(col.rgb * tex.rgb, clamp(col.a * tex.a * inside, 0.0, 1.0)) * mod_c;
}
