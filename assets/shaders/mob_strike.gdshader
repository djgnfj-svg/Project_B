shader_type canvas_item;
// 잔몹 타격 순간 충격파 — "지금 여기가 맞았다"를 읽히게 한다 (2026-08-02).
//
// 🔴 **표시 전용이다.** 판정은 `CombatMath.is_strike_hit` + `CombatAuthority._on_mob_strike`가 이미
//   따로 확정한다 — 여기 기하는 그 원을 **그릴 뿐**이고, 반경은 코드가 `EnemyDef.strike_radius`를
//   그대로 넘긴다. 🔴 상수로 키우지 마라: 그 순간 "보이는 곳 ≠ 맞는 곳"이 된다(rules §3).
//
// 좌표 규약 = `boss_telegraph.gdshader`와 **같다**(같은 2×2 흰 쿼드 · centered · **균일** scale —
//   `src/feel/telegraph_fx.gd`의 `fit_quad`가 단일 소스):
//     p = (UV - 0.5) * quad_px 는 **월드 px 오프셋**, 노드 원점 = 타격 원 중심.
//   🔴 비균일 scale 금지 — 정원이 타원이 된다.
//   🔴 quad_px는 지름과 **분리된** 값이다(2*(radius + aa + margin)). 딱 지름이면 원호 상하좌우 끝의
//     프래그먼트가 아예 안 돌아 링 끝이 잘린다.
//
// 웹(Compatibility/GLES3) 안전: length·smoothstep·mix·clamp·max·abs + UV/COLOR/TEXTURE만.
//   🔴 `fwidth`(derivative)·스크린 텍스처·커스텀 블렌드·discard **없다**(rules §5) — 소프트 폭은
//   전부 **월드 px**로 직접 받는다(p가 이미 월드 px라 smoothstep 인자에 그대로 들어간다).

uniform float quad_px = 64.0;     // 쿼드 월드 한 변 = 2*(radius + aa + margin)
uniform float radius_px = 22.0;   // = EnemyDef.strike_radius = 판정 반경
uniform float progress = 0.0;     // 0 = 타격 프레임, 1 = 소멸. 🔴 TIME이 아니라 코드가 심는다
uniform float ring_px = 4.0;      // 충격파 링 두께(월드 px)
uniform float aa_px = 1.0;        // 경계 소프트 폭(월드 px)
uniform float core_end = 0.34;    // 중심 섬광이 사라지는 진행도
uniform float fade_start = 0.55;  // 전체가 옅어지기 시작하는 진행도
uniform vec4 core_color : source_color = vec4(1.000, 0.945, 0.812, 0.880);
uniform vec4 ring_color : source_color = vec4(1.000, 0.494, 0.208, 0.950);

void fragment() {
	// 🔴 incoming COLOR(= modulate × self_modulate × vertex color)를 **직접 곱해** 기본 캔버스
	//   렌더를 재현한다 — 안 곱하면 이 노드에서만 `modulate`가 **에러 없이** 안 먹고, 이 프로젝트
	//   FX 페이드 관용구가 전부 `modulate:a` 트윈이라 다음 사람이 페이드를 붙여도 아무 일이 안
	//   일어난다(rules §2). COLOR는 inout이라 덮기 전에 잡아 둔다.
	vec4 mod_c = COLOR;
	vec2 p = (UV - vec2(0.5)) * quad_px;
	float r = length(p);
	float pr = clamp(progress, 0.0, 1.0);
	float aa = max(aa_px, 0.0001);

	// 링이 중심 → 판정 반경으로 퍼진다. ease-out(초반이 빠르다) = "퍽" 하고 터지는 타격감.
	float er = radius_px * (1.0 - (1.0 - pr) * (1.0 - pr));
	float ring = 1.0 - smoothstep(0.0, max(ring_px, 0.0001), abs(r - er));
	// 🔴 판정 원 **밖으로는 안 나간다** — 충격파가 판정보다 커 보이면 "저기까지 맞나?"를 만든다.
	//   예고(과예고 허용)와 부호가 반대인 것은 의도다: 이건 예고가 아니라 **결과 표시**라,
	//   틀리는 방향이 "실제로 닿은 범위보다 작게"여야 안전하다.
	ring *= 1.0 - smoothstep(radius_px - aa, radius_px + aa, r);

	// 중심 섬광 — 첫 순간에만 판정 원 전체를 채워 "여기가 맞은 자리"를 못 박는다.
	float disc = 1.0 - smoothstep(radius_px - aa, radius_px, r);
	float core = disc * (1.0 - smoothstep(0.0, max(core_end, 0.0001), pr));

	vec4 c = vec4(ring_color.rgb, ring_color.a * ring);
	c = mix(c, vec4(core_color.rgb, core_color.a * core), core);
	float fade = 1.0 - smoothstep(clamp(fade_start, 0.0, 0.999), 1.0, pr);

	// 텍스처는 "무늬"로만 곱한다 — 2×2 흰색이면 정확히 항등이다(형태는 언제나 코드가 정한다).
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(c.rgb * tex.rgb, clamp(c.a * tex.a * fade, 0.0, 1.0)) * mod_c;
}
