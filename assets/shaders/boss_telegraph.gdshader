shader_type canvas_item;
// 보스 예고(텔레그래프) — 🔴 **기하를 코드가 그린다.**
//
// 왜: 각·반지름이 텍스처 픽셀에 박혀 있으면 데이터(BossPatternDef.range/half_angle)를 튜닝하는
//   순간 "보이는 곳"과 "맞는 곳"이 에러 없이 갈라진다. 실제로 2026-07-26에 68.6° 텍스처 vs
//   85.9° 판정이었고, range 130에서 좌우 각 8.6° = 19px(캐릭터 16px보다 넓다)가 무예고 피격이었다.
//   여기서 그리는 도형 = CombatMath.is_strike_hit(원) / is_hit_in_cone(부채꼴)의 **조건 그 자체**다.
//
// 좌표 규약 (boss.gd `_apply_telegraph_geometry`와 미러 — 한쪽을 고치면 같이 고친다):
//   쿼드 = 2×2 텍스처 + centered + **균일** scale(= quad_px/2) → 월드 한 변 = quad_px
//     ⚠ 텍스처가 2×2인 이유: 1×1이면 centered 오프셋 -0.5px가 거대 scale에 곱해져 half-quad 어긋난다
//       (콘 apex가 회전 방향으로 -123px 튐, boss.gd `_telegraph_quad_tex` 주석 미러 — 같이 고쳐라).
//     ⇒ 노드 원점 = 원 중심 / 부채꼴 apex, 쿼드가 덮는 월드 영역 = 원점 중심 한 변 quad_px 정사각.
//     ⇒ p = (UV - 0.5) * quad_px 는 **월드 px 오프셋**이다(노드 로컬 = facing 정렬 프레임).
//       회전+균일스케일은 닮음변환이라 길이는 그대로고 각은 facing만큼만 돌아간다 — 전단·타원 없음.
//   🔴 quad_px는 반지름과 **분리된** 값이다. 딱 2*radius_px로 두면 원호의 상하좌우 끝에서
//     셀 중심이 쿼드 밖으로 나가 **판정 안인데 안 그려지는** 픽셀이 생긴다(쿼드 밖은 프래그먼트가
//     아예 안 돈다). 그래서 boss.gd가 여유(격자+여유분)를 더해 넘긴다.
//   따라서:
//     length(p) <= radius_px                      ≡ is_strike_hit(pt, center, range)
//     위 + |atan(p.y, p.x)| <= half_angle          ≡ is_hit_in_cone(pt, apex, facing, half_angle, range)
//       (로컬 프레임에서 facing = +x = 각 0 ⇒ angle_difference(facing, 각) = atan 결과 그대로.
//        UV.y·로컬 y·Godot 각 모두 아래가 +y로 같은 손잡이라 부호가 일치한다.)
//
// 픽셀 양자화: 판정 전에 표본점을 **월드 px 격자 셀 중심**으로 스냅한다 — 전 게임 16px 도트와
//   같은 계단이 생기고, 격자가 월드 단위라 range가 커져도 계단 크기가 일정하다.
//   ⚠ 스냅은 표본점을 최대 **셀 반대각선**(0.7071*pixel_px)만큼 옮긴다. 그래서 경계 판정을
//     그만큼 바깥으로 관대하게(edge_bias_px) 한다 — 그러면 판정 안의 점은 **어느 것도** 안 칠해지는
//     일이 없고, 틀리는 방향이 "과예고"로만 고정된다(= 이 변경이 없애려는 무예고의 정반대).
//     경계까지의 거리는 각이 아니라 **px 거리**로 잰다 — 여유값과 단위가 같아야 이 보장이 성립한다.
//   ⚠ **"무예고 0"은 이 격자 모델 안에서다** (리뷰 실측 2026-07-27, 430만 표본). 화면 픽셀
//     양자화까지 넣으면 최악 위상에서 **최대 0.34px = 0.7 화면픽셀**이 남는다. 고친 결함이 19px
//     이었으니 실질 무의미하지만, "0"으로 못 박으면 다음 사람이 그 위에 다른 보장을 쌓는다.
//
// 웹(Compatibility/GLES3) 안전: atan·floor·length·mix·sin + TIME/UV/COLOR/TEXTURE만 쓴다.
//   스크린 텍스처·derivative(fwidth)·커스텀 블렌드·discard 없음.

// ⚠ 기본값도 유도식을 따른다(radius 64 기준) — 런타임엔 boss.gd가 전량 덮어쓰지만, 기본값이
//   유도와 어긋나면 에디터 프리뷰가 틀린 도형을 보여준다.
uniform float quad_px = 134.83;      // 쿼드 월드 한 변 = 노드 scale = 2*(radius + pixel + edge_bias)
uniform float radius_px = 64.0;      // 판정 반경(원) / 사거리(부채꼴) = BossPatternDef.range
uniform float half_angle = 3.15;     // 반각(rad). PI-0.01 이상 = 각 제한 없음(원)
uniform float pixel_px = 2.0;        // 픽셀 양자화 격자(월드 px)
uniform float edge_bias_px = 1.4142; // 경계 여유 = 0.7071*pixel_px — 항상 바깥(과예고)으로만 틀리게
// 테두리 밴드 = d ∈ [-edge_bias_px, border_px]. 🔴 **경계 "안쪽"이 아니다** — 과예고 여유만큼
// 바깥으로도 나간다(실측 최대 2.83px). 여유와 같은 크기라 새 갈라짐은 아니지만, 두께를 키우면
// 그만큼 **판정보다 넓게** 보이는 것을 알고 키워라.
uniform float border_px = 3.0;
uniform vec4 fill_color : source_color = vec4(0.910, 0.275, 0.110, 0.306);
uniform vec4 border_color : source_color = vec4(1.000, 0.604, 0.235, 0.729);
uniform float fill_fade = 0.25;      // 채움 알파가 바깥으로 갈수록 옅어지는 정도(0 = 균일)
// 알파 맥동. 🔴 **등속이어야 한다 — `TIME`에서 "임박도"를 유도하지 마라** (netreview 2026-07-27).
// 지금은 위상이 클라마다 자유롭지만 **타이밍 정보를 전혀 싣지 않아** 무해하다. 그런데 "타격이
// 가까울수록 빨라진다/진해진다"로 바꾸는 순간 계약 위반이 된다: 호스트의 예고 창은 지연 보상분
// (`strike_delay_s`)만큼 길어 **남은 시간이 클라마다 다르므로**, `TIME`에서 유도하면 게스트가 **틀린
// 임박 신호**를 읽는다(§3 지연 보상이 없애려던 바로 그 손해 방향). 남은 시간을 정말 싣고 싶으면
// `_telegraph_left`를 uniform으로 넘겨라 — 그 값은 각 클라가 자기 예고 창으로 리졸브한 것이다.
uniform float pulse_amp = 0.10;      // 알파 맥동 폭
uniform float pulse_hz = 2.2;        // 알파 맥동 주기(등속 — 위 주석)
// 대각 위험 줄무늬(공사장 경고 톤 — swing_cone.md §3 B안). 판정-안 채움을 밝은/어두운 대각 빗금으로.
// 🔴 흐름은 `TIME` **등속만** — 임박도(남은 시간)를 TIME에서 유도 금지(위 pulse 계약과 동일). 격자 스냅된
//   q로 좌표를 만들어 빗금도 도트 블록으로 계단진다(16px 톤 유지). 전부 손맛 상수라 boss.gd가 안 심어도
//   패턴마다 값이 같아 "이전 패턴 값 잔류" 문제가 없다(기하 uniform과 다른 점).
uniform float stripe_period = 12.0;  // 빗금 간격(월드 px) — 도트 격자와 어울리는 값
uniform float stripe_speed = 0.6;    // 흐름 속도(등속)
uniform vec4 stripe_dark : source_color = vec4(0.541, 0.157, 0.063, 0.353);  // 어두운 줄(밝은 줄 = fill_color)
uniform float duty = 0.5;            // 밝은 줄 비율

void fragment() {
	// 🔴 incoming COLOR = modulate × self_modulate × vertex color. fragment를 오버라이드하면
	// 기본 캔버스 렌더(텍스처×모듈레이트)가 사라지므로 **직접 곱해 재현한다** —
	// `hit_flash.gdshader`(웹 실기 검증됨)와 같은 전제다. 안 곱하면 이 프로젝트 FX 페이드
	// 관용구인 `modulate:a` 트윈(afterimage·damage_numbers·coop_authority가 전부 이 방식)이
	// 예고에서만 **에러 없이 안 먹는다**. COLOR는 inout이라 덮기 전에 잡아 둔다.
	vec4 mod_c = COLOR;
	// 월드 px 오프셋 → 격자 셀 중심으로 스냅. 이후 판정은 전부 스냅된 점 q로 한다.
	// 격자 경계가 원점에 걸리므로(floor 기준) 부채꼴 축(y=0) 좌우 계단이 대칭이다.
	vec2 p = (UV - vec2(0.5)) * quad_px;
	float grid = max(pixel_px, 0.0001);
	vec2 q = (floor(p / grid) + vec2(0.5)) * grid;

	float r = length(q);
	float d_arc = radius_px - r;                 // 원호 경계까지의 거리(양수 = 안쪽)
	float d_side = 1.0e9;                        // 부채꼴 옆면까지 (원이면 제한 없음)
	// ⚠ `< PI`가 아니라 여유를 둔다: GDScript가 넘긴 PI가 float32 반올림으로 셰이더 PI보다 아주 조금
	//   작아지면 원이 콘 분기로 새고, 그러면 뒤쪽(dev=π)에서 d_side가 0이 되어 **정반대 방향에
	//   테두리 이음매**가 한 줄 그려진다(에러 없음). 179.4° 이상 반각은 어차피 전방위다.
	if (half_angle < PI - 0.01) {
		float dev = abs(atan(q.y, q.x));         // 로컬 프레임 facing = 0
		// 옆면(경계 반직선)까지의 **수직거리** = r*sin(half_angle - dev). 각이 아니라 거리로 재야
		// edge_bias_px와 단위가 같아 "판정 안은 반드시 칠한다" 보장이 성립한다.
		// ⚠ clamp: |half_angle - dev| > 90°면 sin이 다시 줄어 깊숙한 안/밖을 경계로 오판한다 → 포화.
		d_side = r * sin(clamp(half_angle - dev, -PI * 0.5, PI * 0.5));
	}
	float d = min(d_arc, d_side);                // 경계까지 최단 거리(안쪽 양수)

	if (d < -edge_bias_px) {
		COLOR = vec4(0.0);                       // 판정 밖 — 여유분만큼만 관대하게 칠한다
	} else {
		float t = clamp(r / max(radius_px, 0.0001), 0.0, 1.0);
		vec4 base = fill_color;
		// 대각 위험 줄무늬 — q(격자 스냅점)로 계단진 빗금. s의 대각선 = (x+y), 흐름은 TIME 등속(위 주석 계약).
		float stripe_s = (q.x + q.y) / max(stripe_period, 0.0001) - TIME * stripe_speed;
		if (fract(stripe_s) >= duty) {
			base = stripe_dark;                  // 어두운 줄 (밝은 줄 = fill_color 그대로)
		}
		base.a *= mix(1.0, 1.0 - fill_fade, t);
		if (d <= border_px) {
			base = border_color;                 // 경계 테두리 밴드(위 border_px 주석 — 안쪽만이 아니다)
		}
		// 텍스처는 "무늬"로만 곱한다 — 2×2 흰색이면 정확히 항등이다. 나중에 정사각 풀블리드(알파 1)
		// 패턴을 얹고 싶으면 `boss.gd`의 `_telegraph_quad_tex()`를 갈아야 한다(형태는 계속 셰이더가
		// 정한다 — ⚠ **형태를 그린 텍스처는 안 된다**. 알파가 셰이더 형태를 다시 잘라 정합이 깨진다).
		vec4 tex = texture(TEXTURE, UV);
		float pulse = 1.0 + pulse_amp * sin(TIME * pulse_hz * TAU);
		COLOR = vec4(base.rgb * tex.rgb, clamp(base.a * tex.a * pulse, 0.0, 1.0)) * mod_c;
	}
}
