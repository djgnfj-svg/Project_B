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
//     아예 안 돈다). 그래서 boss.gd가 여유(aa + 마진)를 더해 넘긴다.
//   따라서:
//     length(p) <= radius_px                      ≡ is_strike_hit(pt, center, range)
//     위 + |atan(p.y, p.x)| <= half_angle          ≡ is_hit_in_cone(pt, apex, facing, half_angle, range)
//       (로컬 프레임에서 facing = +x = 각 0 ⇒ angle_difference(facing, 각) = atan 결과 그대로.
//        UV.y·로컬 y·Godot 각 모두 아래가 +y로 같은 손잡이라 부호가 일치한다.)
//
// 캡슐(띠) — 횡단 돌진 경로 예고 (2026-08-02):
//   원의 중심을 로컬 x축 [-half_len_px, +half_len_px] 선분으로 늘린 것 = CombatMath.capsule_depth.
//     qx    = max(|p.x| - half_len_px, 0)          (선분 밖으로 나간 만큼만 남긴다)
//     d_lat = length(vec2(qx, p.y))                (선분까지의 최단거리)
//   🔴 **항등 증명 — half_len_px = 0이면 원·콘과 IEEE 비트 단위로 같다.**
//     qx = max(|p.x| - 0, 0) = |p.x| 이고 length(vec2(|p.x|, p.y)) = sqrt(p.x*p.x + p.y*p.y)
//     = length(p). `|p.x| * |p.x| == p.x * p.x`는 부호 무관이라 반올림까지 동일하다.
//     ⇒ 기존 원·콘 예고는 **한 픽셀도 안 바뀐다**(이 uniform 하나가 캡슐 채택의 안전 근거 전부다).
//   🔴 노드 원점 = **선분의 중점**(원의 중심이 아니다) · rotation = 진행 방향.
//     boss.gd `_begin_windup`이 `보스 위치 + 진행방향 × charge_travel_max/2`로 중점을 만든다.
//   🔴 판정은 여전히 **이동하는 원**이고 캡슐은 그 합집합이다 — 프레임 사이 가리비가 캡슐
//     **안쪽으로** 파이므로(CombatMath.SWEEP_SCALLOP_MAX_PX) 판정 ⊆ 표시가 기하로 성립한다.
//
// 경계 처리 (2026-08-02 개정 — **격자 스냅 폐기**):
//   ⚠ 옛 버전은 표본점을 월드 2px 격자 셀 중심으로 스냅해 "16px 도트와 같은 계단"을 만들었다.
//     그 근거는 **16px 세대 기준**이었고, 지금은 캐릭터 32px + 카메라 줌 1.5라 화면에서 3px 계단으로
//     보였다(사용자 신고: *"너무 픽셀 같고 뭔가 이상하다"*). 스냅을 빼고 부드러운 경계로 바꿨다.
//   🔴 **정합성은 오히려 좋아진다.** 스냅은 표본점을 최대 셀 반대각선(0.7071*pixel_px = 1.41px)만큼
//     옮겼고, 그래서 `edge_bias_px`로 그만큼 **바깥으로 관대하게** 칠해야 무예고가 0이었다(실측 과예고
//     최대 2.83px). 스냅이 없어지면 표본점이 진짜 그 자리이므로 여유 자체가 필요 없다.
//   🔴 **틀리는 방향은 여전히 항상 과예고다** — 알파 램프를 `smoothstep(-aa, 0, d)`로 잡아
//     **d >= 0(판정 안)에서 알파 1**, 밖으로만 aa_px에 걸쳐 사라지게 했다. 즉 무예고 0(이 모델 안에서),
//     과예고 최대 aa_px(그것도 반투명). 램프를 `smoothstep(0, aa, d)`처럼 **안쪽으로** 옮기지 마라 —
//     그 순간 판정 경계 안쪽 aa px가 반투명해져 "판정 안인데 안 보이는" 띠가 생긴다.
//   ⚠ 화면 픽셀 양자화 잔차는 남는다(프래그먼트는 픽셀 중심에서만 표본) — 줌 1.5에서 최대 0.33 월드px.
//     aa_px(1.0)가 그보다 크므로 실질적으로 덮이지만 "0"으로 못 박고 그 위에 보장을 쌓지 마라.
//   🔴 안티에일리어싱에 **fwidth/derivative를 쓰지 않는다**(웹 Compatibility 안전 목록 밖, rules §5).
//     폭은 전부 **월드 px**로 직접 준다 — p가 이미 월드 px라 smoothstep 인자에 그대로 넣으면 된다.
//
// 웹(Compatibility/GLES3) 안전: atan·length·mix·sin·smoothstep·fract·clamp + TIME/UV/COLOR/TEXTURE만.
//   스크린 텍스처·derivative(fwidth)·커스텀 블렌드·discard 없음.

// ⚠ 기본값도 유도식을 따른다(radius 64 기준) — 런타임엔 boss.gd가 전량 덮어쓰지만, 기본값이
//   유도와 어긋나면 에디터 프리뷰가 틀린 도형을 보여준다.
uniform float quad_px = 132.0;       // 쿼드 월드 한 변 = 2*(radius + aa_px + 마진)
uniform float radius_px = 64.0;      // 판정 반경(원) / 사거리(부채꼴) = BossPatternDef.range
uniform float half_angle = 3.15;     // 반각(rad). PI-0.01 이상 = 각 제한 없음(원)
// 캡슐 반길이(월드 px). 🔴 **0 = 원/콘 = 현행과 완전 항등**(헤더 「캡슐」 항등 증명).
// ⚠ boss.gd `_apply_telegraph_geometry`가 캡슐이 아닐 때도 **무조건 0을 심는다** — Telegraph
//   노드가 재사용되므로 안 심으면 다음 원 예고가 캡슐로 그려진다(에러 없음).
uniform float half_len_px = 0.0;
// 경계 소프트 폭(월드 px). 🔴 **바깥으로만** 퍼진다(위 주석) — 안쪽 알파는 항상 1이다.
uniform float aa_px = 1.0;
// 테두리 밴드 = d ∈ [경계, border_px]. 소프트 폭 aa_px가 양옆에 붙는다.
uniform float border_px = 3.0;
uniform vec4 fill_color : source_color = vec4(0.910, 0.275, 0.110, 0.306);
uniform vec4 border_color : source_color = vec4(1.000, 0.604, 0.235, 0.729);
uniform float fill_fade = 0.25;      // 채움 알파가 바깥으로 갈수록 옅어지는 정도(0 = 균일)
// 알파 맥동. 🔴 **등속이어야 한다 — `TIME`에서 "임박도"를 유도하지 마라** (netreview 2026-07-27).
// 지금 위상은 클라마다 자유롭지만 **타이밍 정보를 전혀 싣지 않아** 무해하다. 임박도는 아래
// `progress` uniform이 싣는다 — 그 값은 각 클라가 **자기 예고 창**(boss.gd `_telegraph_duration`)으로
// 리졸브한 것이라 호스트의 지연 보상분(strike_delay_s)이 클라마다 달라도 각자 옳다.
uniform float pulse_amp = 0.10;      // 알파 맥동 폭
uniform float pulse_hz = 2.2;        // 알파 맥동 주기(등속 — 위 주석)
// 대각 위험 줄무늬(공사장 경고 톤). 🔴 흐름은 `TIME` **등속만**(임박도는 progress가 싣는다).
// 스냅 폐기 후 duty 경계도 월드 px 폭(aa_px)으로 부드럽게 — 안 그러면 대각선 계단이 그대로 남는다.
// 전부 손맛 상수라 boss.gd가 안 심어도 패턴마다 값이 같아 "이전 패턴 값 잔류" 문제가 없다.
uniform float stripe_period = 12.0;  // 빗금 간격(월드 px)
uniform float stripe_speed = 0.6;    // 흐름 속도(등속)
uniform vec4 stripe_dark : source_color = vec4(0.541, 0.157, 0.063, 0.353);  // 어두운 줄(밝은 줄 = fill_color)
uniform float duty = 0.5;            // 밝은 줄 비율

// --- 차오름(임박도) — 2026-08-02 ---
// 🔴 **판정 형태를 바꾸지 않는다.** 아래 `inside`(= 판정 조건)만이 무엇이 그려질지를 정하고,
//   progress는 그 **안에서** 색만 바꾼다. 차오름 반지름(fill_r)을 `inside`에 섞지 마라 —
//   그 순간 "예고가 아직 안 닿았는데 맞는" 구간이 생겨 §3이 뒤집힌다.
// 🔴 **`TIME`에서 유도하지 마라** — 호스트 예고 창은 `strike_delay_s`만큼 길어 남은 시간이 클라마다
//   다르다. 게스트가 TIME으로 임박도를 만들면 **틀린 신호**를 읽고, 그건 §3 지연 보상이 없애려던
//   손해 방향 그 자체다. boss.gd가 자기 `_telegraph_duration`으로 나눈 값을 매 프레임 심는다.
uniform float progress = 0.0;        // 0 = 예고 시작, 1 = 타격 순간
uniform vec4 charge_color : source_color = vec4(1.000, 0.451, 0.129, 0.620);  // 다 찬 구역
uniform float lead_px = 7.0;         // 차오름 선단(밝은 파면) 두께(월드 px)
uniform vec4 flash_color : source_color = vec4(1.000, 0.925, 0.722, 0.880);   // 마지막 순간 번쩍
uniform float flash_start = 0.86;    // 이 진행도부터 번쩍이 올라온다

void fragment() {
	// 🔴 incoming COLOR = modulate × self_modulate × vertex color. fragment를 오버라이드하면
	// 기본 캔버스 렌더(텍스처×모듈레이트)가 사라지므로 **직접 곱해 재현한다** —
	// `hit_flash.gdshader`(웹 실기 검증됨)와 같은 전제다. 안 곱하면 이 프로젝트 FX 페이드
	// 관용구인 `modulate:a` 트윈(afterimage·damage_numbers·coop_authority가 전부 이 방식)이
	// 예고에서만 **에러 없이 안 먹는다**. COLOR는 inout이라 덮기 전에 잡아 둔다.
	vec4 mod_c = COLOR;
	// 월드 px 오프셋. **스냅하지 않는다** — 판정식이 보는 점 = 이 점 그대로다(헤더 「경계 처리」).
	vec2 p = (UV - vec2(0.5)) * quad_px;

	// 선분(캡슐 축)까지의 최단거리. half_len_px = 0이면 length(p)와 **비트 단위 동일**(헤더 증명).
	float qx = max(abs(p.x) - half_len_px, 0.0);
	float r = length(vec2(qx, p.y));
	float d_arc = radius_px - r;                 // 원호 경계까지의 거리(양수 = 안쪽)
	float d_side = 1.0e9;                        // 부채꼴 옆면까지 (원이면 제한 없음)
	// ⚠ `< PI`가 아니라 여유를 둔다: GDScript가 넘긴 PI가 float32 반올림으로 셰이더 PI보다 아주 조금
	//   작아지면 원이 콘 분기로 새고, 그러면 뒤쪽(dev=π)에서 d_side가 0이 되어 **정반대 방향에
	//   테두리 이음매**가 한 줄 그려진다(에러 없음). 179.4° 이상 반각은 어차피 전방위다.
	if (half_angle < PI - 0.01) {
		float dev = abs(atan(p.y, p.x));         // 로컬 프레임 facing = 0
		// 옆면(경계 반직선)까지의 **수직거리** = r*sin(half_angle - dev). 각이 아니라 거리로 재야
		// aa_px와 단위가 같아 "판정 안은 알파 1"이 각 축에서도 그대로 성립한다.
		// ⚠ clamp: |half_angle - dev| > 90°면 sin이 다시 줄어 깊숙한 안/밖을 경계로 오판한다 → 포화.
		d_side = r * sin(clamp(half_angle - dev, -PI * 0.5, PI * 0.5));
	}
	float d = min(d_arc, d_side);                // 경계까지 최단 거리(안쪽 양수)
	float aa = max(aa_px, 0.0001);
	// 🔴 판정 안(d >= 0) = 알파 1. 밖으로만 aa px에 걸쳐 사라진다 = 과예고 방향으로만 틀린다.
	float inside = smoothstep(-aa, 0.0, d);

	float t = clamp(r / max(radius_px, 0.0001), 0.0, 1.0);
	// 대각 위험 해칭 — duty 경계를 월드 px 폭으로 부드럽게. sw는 stripe 좌표(0..1) 단위로 환산한 aa.
	float period = max(stripe_period, 0.0001);
	float sw = clamp(aa / period, 0.0001, 0.25);
	float sf = fract((p.x + p.y) / period - TIME * stripe_speed);
	// fract 랩(1→0)에서도 밝은 줄이 안 끊기게 위쪽 끝을 같이 내린다.
	float dark = smoothstep(duty - sw, duty + sw, sf) * (1.0 - smoothstep(1.0 - sw, 1.0, sf));
	vec4 base = mix(fill_color, stripe_dark, dark);
	base.a *= mix(1.0, 1.0 - fill_fade, t);

	// --- 차오름: apex(콘)/중심(원)에서 바깥으로 차오른다 ---
	// ⚠ 안 찬 구역은 **도입 전과 같은 밝기로 그대로 보인다**(fill_color + 해칭). 도형의 전체 범위를
	//   t=0부터 끝까지 볼 수 있어야 회피 판단이 서므로, 차오름은 "덜 보이게" 하는 것이 아니라
	//   "더 뜨겁게" 하는 방향으로만 쓴다.
	float pr = clamp(progress, 0.0, 1.0);
	// 차오름 좌표 — 원/콘은 중심(apex)에서 **바깥으로**, 캡슐은 **길이 방향**(진행 방향)으로 찬다.
	// 🔴 캡슐에서 반지름 방향으로 채우면 임박도는 실리지만 **방향이 안 실린다** — 이 패턴은
	//   "어디서 어디로 지나가는가"가 곧 회피 정보라 축이 곧 정보다(설계 §7-1).
	// ⚠ half_len_px = 0이면 아래 두 줄이 정확히 `r` / `radius_px`로 떨어져 **현행과 항등**이다.
	float fill_axis = r;
	float fill_span = radius_px;
	if (half_len_px > 0.0) {
		fill_axis = p.x + half_len_px;      // 선분 시작단(로컬 -x)에서 잰 거리
		fill_span = 2.0 * half_len_px;
	}
	float fill_r = fill_span * pr;
	float filled = 1.0 - smoothstep(fill_r - aa, fill_r + aa, fill_axis);
	base = mix(base, charge_color, filled);
	// 선단 파면 — 지금 차오르고 있는 자리를 밝게. 원이면 퍼지는 링, 콘이면 apex에서 나가는 호,
	// 캡슐이면 띠를 가로지르는 수직 파면(= 보스가 지금 어디까지 왔는가).
	float wave = clamp(1.0 - abs(fill_axis - fill_r) / max(lead_px, 0.0001), 0.0, 1.0);
	base = mix(base, border_color, wave);
	// 바깥 테두리 밴드 — 도형의 실제 경계(= 판정 경계)를 언제나 또렷하게 남긴다.
	float rim = 1.0 - smoothstep(border_px - aa, border_px + aa, d);
	base = mix(base, border_color, rim);
	// 마지막 순간 번쩍 — "지금 터진다".
	float flash = smoothstep(clamp(flash_start, 0.0, 0.999), 1.0, pr);
	base = mix(base, flash_color, flash);

	// 텍스처는 "무늬"로만 곱한다 — 2×2 흰색이면 정확히 항등이다. 나중에 정사각 풀블리드(알파 1)
	// 패턴을 얹고 싶으면 `boss.gd`의 `_telegraph_quad_tex()`를 갈아야 한다(형태는 계속 셰이더가
	// 정한다 — ⚠ **형태를 그린 텍스처는 안 된다**. 알파가 셰이더 형태를 다시 잘라 정합이 깨진다).
	vec4 tex = texture(TEXTURE, UV);
	float pulse = 1.0 + pulse_amp * sin(TIME * pulse_hz * TAU);
	COLOR = vec4(base.rgb * tex.rgb, clamp(base.a * tex.a * pulse * inside, 0.0, 1.0)) * mod_c;
}
