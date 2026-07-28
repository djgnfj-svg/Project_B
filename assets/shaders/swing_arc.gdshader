shader_type canvas_item;
// 근접 스윙 궤적 — 🔴 **각·도달을 데이터가 그린다** (무기 모션 축 2026-07-28).
//
// 왜: 궤적의 호 각이 PNG 픽셀에 박혀 있으면 `EquipDef.swing_arc`(= 판정 반각)를 튜닝하는 순간
//   "보이는 곳"과 "맞는 곳"이 에러 없이 갈라진다. 실제로 갈라져 있었다 — 실측(2026-07-28):
//     swoosh_worn.png  63~64°  vs  worn_greatsword  109°   → 양옆 각각 **+45°가 안 보이는데 맞았다**
//     swoosh_iron.png  76.4°   vs  iron_greatsword  137.5° → **+61°**
//   보스 콘 텔레그래프가 68.6° 텍스처 vs 85.9° 판정으로 겪은 것과 **같은 결함 클래스**이고,
//   거기서 내린 결론(사람이 지키는 미러는 조용히 깨진다 → 셰이더가 데이터에서 직접 그린다)을
//   그대로 적용한다. 창(±17°)처럼 좁은 무기가 오면 텍스처 방식은 아예 성립하지 않는다.
//
// 보스 텔레그래프와 **같은 좌표 규약**이다 (`boss_telegraph.gdshader` 주석이 정본 — 여기선 요약):
//   쿼드 = 1×1 텍스처 + centered + **균일** scale(= quad_px) ⇒ 노드 원점 = apex,
//   p = (UV - 0.5) * quad_px 는 월드 px 오프셋(로컬 프레임 = facing 정렬, +x = 각 0).
//   🔴 **비균일 스케일 금지** — 정원이 타원이 되어 축 방향 말고는 어긋난다.
//   🔴 quad_px는 반지름과 분리된 값이다(딱 지름이면 호 끝에서 셀 중심이 쿼드를 벗어나 안 그려진다).
//
// 🔴 **틀리는 방향은 "판정보다 넓게"로 고정한다** — 보스의 과예고 규약과 같은 부호다.
//   여기서 표시 < 판정이면 "안 보이는데 맞는다"(§3 금지), 표시 > 판정이면 "휘둘렀는데 안 맞는다"로
//   답답할 뿐 부당한 피해가 없다. 그래서 격자 스냅 여유(edge_bias_px)를 바깥으로만 준다.
//
// 룩의 차이: 보스는 "경고"라 부채꼴을 **채우고**, 이쪽은 "베고 지나간 자국"이라 바깥 **호 밴드**만
//   그린다. ⚠ 안쪽을 비우는 것은 순수 연출이고 **각과 도달은 판정 그대로**다 — 칼날 끝이 지나간
//   자리를 그리는 관용구라, 안쪽 여백을 "판정이 좁다"로 읽으면 안 된다.
//
// 웹(Compatibility/GLES3) 안전: atan·floor·length·mix·smoothstep + UV/COLOR/TEXTURE만 쓴다.
//   스크린 텍스처·derivative(fwidth)·커스텀 블렌드·discard 없음.

// ⚠ 기본값도 유도식을 따른다(radius 42 = 전사 기본 기준) — 런타임엔 player.gd가 전량 덮어쓰지만,
//   기본값이 유도와 어긋나면 에디터 프리뷰가 틀린 도형을 보여준다.
uniform float quad_px = 89.66;      // 쿼드 월드 한 변 = 노드 scale = 2*(radius + pixel + edge_bias)
uniform float radius_px = 42.0;     // 도달 거리 = CombatMath.effective_attack_range (판정 그대로)
uniform float half_angle = 1.9;     // 반각(rad) = EquipDef.swing_arc (판정 그대로). PI-0.01 이상 = 전방위
uniform float inner_ratio = 0.55;   // 호 밴드 안쪽 시작 = radius * 이 값 (연출 — 판정 아님)
uniform float pixel_px = 2.0;       // 픽셀 양자화 격자(월드 px) — 전 게임 도트와 같은 계단
uniform float edge_bias_px = 1.4142;// 경계 여유 = 0.7071*pixel_px — 항상 바깥(과다 표시)으로만 틀리게
// ⚠ **색 유니폼은 두지 않는다** — 색은 `modulate`(= player.gd `_fx_color()` = `EquipDef.swing_color`)
//   하나가 쥔다. 여기 `tint`를 또 두면 같은 것을 정하는 자리가 둘이 되어, 무기 색을 바꿨는데
//   한쪽만 따라오는 갈라짐이 생긴다(이 파일이 없애려는 결함 클래스 그 자체다).
uniform float edge_soft_px = 3.0;   // 밴드 안/바깥 가장자리 페이드 폭(px) — 궤적 느낌
uniform float tip_boost = 0.35;     // 바깥쪽으로 갈수록 진해지는 정도(0 = 균일) — 칼끝이 밝게

void fragment() {
	// 🔴 incoming COLOR = modulate × self_modulate × vertex color. fragment를 오버라이드하면
	// 기본 캔버스 렌더가 사라지므로 **직접 곱해 재현한다**(`hit_flash.gdshader`·보스 셰이더와 같은
	// 전제). 안 곱하면 이 프로젝트 FX 페이드 관용구인 `modulate:a` 트윈이 **에러 없이 안 먹는다** —
	// player.gd의 `_fx_color()` 페이드가 정확히 그 방식이다. COLOR는 inout이라 덮기 전에 잡아 둔다.
	vec4 mod_c = COLOR;
	vec2 p = (UV - vec2(0.5)) * quad_px;
	float grid = max(pixel_px, 0.0001);
	vec2 q = (floor(p / grid) + vec2(0.5)) * grid;   // 격자 셀 중심으로 스냅 (도트 계단)

	float r = length(q);
	float inner_px = radius_px * clamp(inner_ratio, 0.0, 0.999);

	// 바깥 호 경계까지의 거리(양수 = 안쪽). 여유만큼 바깥으로 관대하게 — 과다 표시 방향.
	float d_outer = radius_px - r;
	// 안쪽 경계 — 연출이라 여유를 주지 않는다(안쪽으로 번지면 부채꼴을 채운 것처럼 보인다).
	float d_inner = r - inner_px;
	float d_side = 1.0e9;
	// ⚠ `< PI`가 아니라 여유를 둔다: GDScript가 넘긴 PI가 float32 반올림으로 셰이더 PI보다 아주
	//   조금 작아지면 전방위가 각 분기로 새어 정반대 방향에 이음매가 한 줄 그려진다(보스와 같은 가드).
	if (half_angle < PI - 0.01) {
		float dev = abs(atan(q.y, q.x));   // 로컬 프레임 facing = 0
		// 옆면까지의 **수직거리** = r*sin(half_angle - dev). 각이 아니라 거리로 재야 edge_bias_px와
		// 단위가 같아 "판정 안은 반드시 칠한다" 보장이 성립한다. clamp는 |Δ| > 90°에서 sin이 다시
		// 줄어 깊숙한 안/밖을 경계로 오판하는 것을 막는다(보스와 같은 유도).
		d_side = r * sin(clamp(half_angle - dev, -PI * 0.5, PI * 0.5));
	}

	// 판정 밖(여유분 초과) 또는 밴드 안쪽 → 그리지 않는다.
	if (d_outer < -edge_bias_px || d_side < -edge_bias_px || d_inner < 0.0) {
		COLOR = vec4(0.0);
	} else {
		float soft = max(edge_soft_px, 0.0001);
		// 세 경계 각각에서 부드럽게 — 바깥/옆면은 여유분까지 살려 두고(과다 표시), 안쪽만 빠르게 뜬다.
		float a_outer = smoothstep(-edge_bias_px, -edge_bias_px + soft, d_outer);
		float a_side = smoothstep(-edge_bias_px, -edge_bias_px + soft, d_side);
		float a_inner = smoothstep(0.0, soft, d_inner);
		// 칼끝(바깥)이 밝게 — 밴드 안에서의 상대 위치
		float band = clamp((r - inner_px) / max(radius_px - inner_px, 0.0001), 0.0, 1.0);
		float shade = mix(1.0 - tip_boost, 1.0, band);
		vec4 tex = texture(TEXTURE, UV);   // 1×1 흰색이면 정확히 항등
		float a = a_outer * a_side * a_inner * shade;
		COLOR = vec4(tex.rgb, clamp(a * tex.a, 0.0, 1.0)) * mod_c;
	}
}
