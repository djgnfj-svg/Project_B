shader_type canvas_item;
// 히트 플래시 — 맞는 순간 스프라이트를 flash_color(기본 흰색)로 물들인다.
// flash_amount 0=원본, 1=완전 흰색. `COLOR = texture * COLOR`로 기본 캔버스 렌더(텍스처×모듈레이트)를
// 그대로 재현한 뒤 그 위에서 흰색으로 mix — amount=0이면 정확히 기본 렌더와 동일(항등).
// ⚠ 그래도 헬퍼(hit_flash.gd)가 플래시 종료 시 머티리얼을 떼어 평상시엔 셰이더가 아예 안 걸리게 한다
//   (웹 Compatibility 렌더러 변수 차단 — 이중 안전).

uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	COLOR = texture(TEXTURE, UV) * COLOR;
	COLOR.rgb = mix(COLOR.rgb, flash_color.rgb, flash_amount);
}
