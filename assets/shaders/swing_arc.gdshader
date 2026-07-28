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

// --- 진행(무기 궤도 추종) — 궤적 진행 축 2026-07-28 ---
// 🔴 **왜 생겼나:** 전에는 부채꼴 **전체**를 한 번에 번쩍이고 칼은 그 안을 천천히 지나갔다. 시간
//   개념이 아예 없어서 "이펙트가 무기 궤에 안 맞는다"가 됐다(사용자 신고). 이제 `sweep_head`는
//   `player.gd`가 그 프레임 **무기의 각 그 자체**(`_motion_off`)를 넘긴 값이라 사본이 없다.
//
// 🔴🔴 **불변식 — 판정이 확정되는 순간 이 셋은 판정 부채꼴을 전부 덮는다.**
//   🔴 이 보장은 **CPU 쪽 선단 래치**(`player._draw_swing_trail`: `p >= 1`이면 `sweep_head`를
//     끝각으로 고정)가 만든다. 그 래치 없이 무기 각을 그대로 넘기면 판정 프레임엔 이미 복귀
//     분기라 선단이 물러나 있어 **최대 약 19°가 "맞는데 안 그려진" 채로** 굳는다(netreview M-2).
//   베기: [sweep_from, sweep_head] = ±swing_arc = 판정 반각과 같다(마무리 타는 더 넓다 = 안전).
//   찌르기: 각 창은 처음부터 ±half_angle 전체이고 `reach_ratio`가 완료 시 정확히 1.0.
//   `tail_floor`도 완료 시 1.0으로 수렴 → **그 순간의 그림은 도입 전과 완전히 같은 균일 부채꼴.**
//   그래서 위 "표시 < 판정 금지"가 **시간 축에서도** 깨지지 않는다. 스윕 도중엔 일부만 그려지지만
//   그때는 아직 판정이 없다(`player._swing_hit_pending`).
// ⚠ 여기에 자체 시간(TIME)을 쓰지 마라 — 셰이더가 자기 시계를 가지면 히트스톱·일시정지·haste에서
//   무기와 갈라진다(진행은 항상 CPU가 넘긴다).
uniform float sweep_from = -1.9;    // 스윕 시작각(rad, 로컬 프레임)
uniform float sweep_head = 1.9;     // 지금 선단각(rad) = 이 프레임 무기의 각 오프셋
uniform float reach_ratio = 1.0;    // 그려진 도달 비율(0~1) — 찌르기만 자란다(베기는 항상 1)
uniform float tail_floor = 1.0;     // 꼬리 최소 알파 — CPU가 진행에 따라 1.0으로 수렴시킨다

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
	// 그려진 도달 = 판정 도달 × 진행. 🔴 완료 시 reach_ratio = 1이므로 **정확히 판정 반경**이다.
	float r_now = radius_px * clamp(reach_ratio, 0.0, 1.0);
	// 밴드 안쪽도 진행과 같이 자란다 — 비율이라 완료 시 도입 전(`radius_px * inner_ratio`)과 항등.
	float inner_px = r_now * clamp(inner_ratio, 0.0, 0.999);

	// 바깥 호 경계까지의 거리(양수 = 안쪽). 여유만큼 바깥으로 관대하게 — 과다 표시 방향.
	float d_outer = r_now - r;
	// 안쪽 경계 — 연출이라 여유를 주지 않는다(안쪽으로 번지면 부채꼴을 채운 것처럼 보인다).
	float d_inner = r - inner_px;
	float d_side = 1.0e9;
	float ang = atan(q.y, q.x);        // 로컬 프레임 facing = 0
	// ⚠ `< PI`가 아니라 여유를 둔다: GDScript가 넘긴 PI가 float32 반올림으로 셰이더 PI보다 아주
	//   조금 작아지면 전방위가 각 분기로 새어 정반대 방향에 이음매가 한 줄 그려진다(보스와 같은 가드).
	if (half_angle < PI - 0.01) {
		float dev = abs(ang);
		// 옆면까지의 **수직거리** = r*sin(half_angle - dev). 각이 아니라 거리로 재야 edge_bias_px와
		// 단위가 같아 "판정 안은 반드시 칠한다" 보장이 성립한다. clamp는 |Δ| > 90°에서 sin이 다시
		// 줄어 깊숙한 안/밖을 경계로 오판하는 것을 막는다(보스와 같은 유도).
		d_side = r * sin(clamp(half_angle - dev, -PI * 0.5, PI * 0.5));
	}

	// 아직 칼이 지나가지 않은 각 — 같은 유도(수직거리)라 edge_bias_px와 단위가 맞는다.
	// ⚠ 창이 한 바퀴를 덮으면 검사를 건너뛴다 — 안 그러면 ±PI 이음매에서 한 줄이 뜬다.
	//   🔴 **이 가드가 발동하는 상황은 둘이고, 「전방위 무기」는 그중 하나일 뿐이다** (code-rv m-B 정정).
	//   나머지 하나는 **마무리 타의 넓은 창**이다: `COMBO_FINISH_ARC`(1.25)가 곱해져 `heavy_axe`는
	//   ±3.5 rad(> PI)가 되고, 선단이 2.763을 넘는 순간 span이 2PI-0.02를 넘겨 게이트가 꺼진다 →
	//   그 프레임에 궤적이 전체 부채꼴로 **약 2° 팝**한다. 방향은 과다표시(안전)이고 그 직후 판정
	//   시점엔 어차피 전 구간이 그려져 있어 불변식은 안 깨진다 — 수용한 잔차다.
	//   ⚠ 표시용 각을 ±PI로 clamp해 없애려 하지 마라: 전방위 무기(`half_angle >= PI`)에서는 창이
	//     반대로 판정보다 **좁아져** "표시 < 판정"이 된다(금지 방향).
	float lo = min(sweep_from, sweep_head);
	float hi = max(sweep_from, sweep_head);
	float d_sweep = 1.0e9;
	if (hi - lo < 2.0 * PI - 0.02) {
		d_sweep = r * sin(clamp(min(ang - lo, hi - ang), -PI * 0.5, PI * 0.5));
	}

	// 판정 밖(여유분 초과) · 아직 안 지나간 각 · 밴드 안쪽 → 그리지 않는다.
	if (d_outer < -edge_bias_px || d_side < -edge_bias_px || d_sweep < -edge_bias_px
			|| d_inner < 0.0) {
		COLOR = vec4(0.0);
	} else {
		float soft = max(edge_soft_px, 0.0001);
		// 경계마다 부드럽게 — 바깥/옆면/선단은 여유분까지 살려 두고(과다 표시), 안쪽만 빠르게 뜬다.
		float a_outer = smoothstep(-edge_bias_px, -edge_bias_px + soft, d_outer);
		float a_side = smoothstep(-edge_bias_px, -edge_bias_px + soft, d_side);
		float a_sweep = smoothstep(-edge_bias_px, -edge_bias_px + soft, d_sweep);
		float a_inner = smoothstep(0.0, soft, d_inner);
		// 칼끝(바깥)이 밝게 — 밴드 안에서의 상대 위치
		float band = clamp((r - inner_px) / max(r_now - inner_px, 0.0001), 0.0, 1.0);
		float shade = mix(1.0 - tip_boost, 1.0, band);
		// 꼬리 — 시작각 쪽이 옅고 선단이 진하다("벤 자국"). 🔴 tail_floor가 완료 시 1.0이므로
		//   판정 순간에는 이 항이 통째로 1.0 = 도입 전과 항등이다(위 불변식).
		float denom = sweep_head - sweep_from;
		float s = (abs(denom) < 0.0001) ? 1.0 : clamp((ang - sweep_from) / denom, 0.0, 1.0);
		float a_tail = mix(clamp(tail_floor, 0.0, 1.0), 1.0, s);
		vec4 tex = texture(TEXTURE, UV);   // 1×1 흰색이면 정확히 항등
		float a = a_outer * a_side * a_sweep * a_inner * shade * a_tail;
		COLOR = vec4(tex.rgb, clamp(a * tex.a, 0.0, 1.0)) * mod_c;
	}
}
