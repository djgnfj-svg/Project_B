shader_type canvas_item;
// 유령/데이터 FX 필터 — 기존 협동 이펙트 텍스처 위에 씌워 "반투명 유령 + 지직 데이터" 느낌으로 통일한다.
// 그림은 그대로 두고 질감만 얹는다(형태=텍스처 알파 유지). 스크린 텍스처 안 읽음(웹 Compatibility 안전).
// 🔴 모든 uniform은 스크립트가 심는다(기본값 의존 금지 — 웹 검정 렌더 함정, hit_flash·telegraph 규율).

uniform float alpha_mul : hint_range(0.0, 1.0) = 0.82;   // 반투명(유령감)
uniform float flicker : hint_range(0.0, 1.0) = 0.14;     // 전체 명멸
uniform float scan_amt : hint_range(0.0, 1.0) = 0.22;    // 스캔라인 세기
uniform float glitch : hint_range(0.0, 0.2) = 0.03;      // 가로 글리치 변위 폭(UV)
uniform float dissolve : hint_range(0.0, 1.0) = 0.22;    // 가장자리 지직 소멸(너울)

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	// 가로 글리치 — 가끔 한 밴드가 옆으로 밀린다(데이터 손상)
	float band = floor(uv.y * 18.0);
	float gb = hash(vec2(band, floor(TIME * 11.0)));
	uv.x += (gb - 0.5) * glitch * step(0.72, gb);
	vec4 tex = texture(TEXTURE, uv);
	// 스캔라인 밝기
	float sl = 0.7 + 0.3 * sin((uv.y * 30.0 + TIME * 6.0) * 6.2831853);
	// 전체 명멸(유령이 깜빡)
	float fl = 1.0 - flicker * (0.5 + 0.5 * sin(TIME * 8.0));
	// 너울 — 노이즈로 알파를 지직 깎아 가장자리가 흩어진다(ectoplasm)
	float n = hash(floor(uv * 46.0) + floor(TIME * 13.0));
	float diss = 1.0 - dissolve * step(0.74, n);
	float a = tex.a * alpha_mul * mix(1.0, sl, scan_amt) * fl * diss;
	COLOR = vec4(tex.rgb, a) * COLOR;   // 노드 modulate(각 FX 고유색) 존중
}
