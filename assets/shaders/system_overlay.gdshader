shader_type canvas_item;
// 풀스크린 포스트 오버레이 — "손상된 시스템 안" 룩. 스크린 텍스처를 안 읽는다(웹 Compatibility 안전):
// 화면 위에 알파 블렌드로 ⑴ 가장자리 비네트 ⑵ 옅은 청록 틴트 ⑶ 움직이는 스캔라인을 얹을 뿐.
// 진짜 화면 왜곡(수차·변위)은 BackBufferCopy가 필요해 웹에서 위험 → 넣지 않는다.
// 🔴 모든 uniform은 스크립트가 심는다(기본값 의존 금지 — 웹 검정 렌더 함정, hit_flash와 같은 규율).

uniform float vignette_strength : hint_range(0.0, 1.0) = 0.55;  // 가장자리 어둡기
uniform float vignette_start : hint_range(0.0, 1.5) = 0.35;     // 어두워지기 시작하는 중심거리(정규)
uniform float vignette_end : hint_range(0.0, 1.5) = 0.95;       // 완전히 어두워지는 거리
uniform vec3 vignette_color : source_color = vec3(0.02, 0.03, 0.05);
uniform vec3 tint_color : source_color = vec3(0.10, 0.25, 0.28); // 옅은 청록 틴트
uniform float tint_amount : hint_range(0.0, 0.5) = 0.06;
uniform float scan_amount : hint_range(0.0, 0.3) = 0.05;         // 스캔라인 세기
uniform float scan_count = 220.0;                                // 화면 세로 스캔라인 개수
uniform float scan_speed = 8.0;                                  // 스캔라인 흐름 속도
uniform float corruption : hint_range(0.0, 1.0) = 0.0;           // 페이즈2 오염(⑤에서 올림) — 지금은 0

void fragment() {
	// 중심(0) → 코너(≈1) 정규 거리
	float d = distance(UV, vec2(0.5)) * 1.41421356;
	float vig = smoothstep(vignette_start, vignette_end, d) * vignette_strength;
	// 움직이는 스캔라인 (0..1)
	float sl = 0.5 + 0.5 * sin((UV.y * scan_count + TIME * scan_speed) * 6.2831853);
	float scan = sl * scan_amount;
	// 페이즈2 오염 시 스캔라인만 강해진다(붉은 틴트는 제거 — 화면 빨개짐 없앰, 사용자 요청).
	vec3 col = mix(tint_color, vignette_color, vig);
	float a = clamp(vig + tint_amount + scan * (1.0 + corruption), 0.0, 1.0);
	COLOR = vec4(col, a);
}
