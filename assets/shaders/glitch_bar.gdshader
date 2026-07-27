shader_type canvas_item;
// 보스 HP바 채움용 글리치 셰이더 — 청록 베이스에 스캔라인 + 노이즈 명멸 + 간헐 다크밴드(손상 데이터).
// ColorRect에 걸어 쓴다(COLOR를 통째로 덮으므로 ColorRect.color는 무시). 웹 Compatibility 안전.
// 🔴 모든 uniform은 스크립트가 심는다(기본값 의존 금지 — 웹 검정 렌더 함정).

uniform vec3 base_color : source_color = vec3(0.24, 0.85, 0.66);
uniform vec3 hi_color : source_color = vec3(0.70, 1.0, 0.88);
uniform float rows = 7.0;          // 세로 스캔밴드 수
uniform float scan_speed = 5.0;    // 스캔라인 흐름
uniform float noise_amt : hint_range(0.0, 1.0) = 0.35;
uniform float glitch_amt : hint_range(0.0, 1.0) = 0.35;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float row = floor(uv.y * rows);
	// 행별 시간 명멸(계단식 글리치) — 가끔 한 행이 어두워진다
	float rf = hash(vec2(row, floor(TIME * 9.0)));
	float dark = mix(0.45, 1.0, step(glitch_amt * 0.2, rf));
	// 스캔라인
	float sl = 0.62 + 0.38 * sin((uv.y * rows + TIME * scan_speed) * 6.2831853);
	// 미세 노이즈
	float n = hash(floor(uv * vec2(90.0, 30.0)) + floor(TIME * 22.0));
	float bright = sl * dark * (1.0 - noise_amt * n);
	vec3 col = mix(base_color, hi_color, clamp(bright, 0.0, 1.0));
	COLOR = vec4(col, 1.0);
}
