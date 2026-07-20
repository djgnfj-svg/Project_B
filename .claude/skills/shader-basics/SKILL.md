---
name: shader-basics
description: 셰이더를 구현할 때 사용한다 — Godot 셰이더 언어, 비주얼 셰이더, 흔한 비주얼 레시피, 후처리 효과
---

# Godot 4.3+의 셰이더

모든 예제는 Godot 4.3+를 대상으로 하며 폐기된 API를 쓰지 않는다.

> **관련 스킬:** 히트 플래시 같은 셰이더 구동 효과는 **animation-system**, 셰이더 성능 고려사항은 **godot-optimization**, 후처리 카메라 효과는 **camera-system**, 2D 조명·픽셀 아트 셰이더·CanvasTexture 노멀 맵은 **2d-essentials**, 스페이셜 셰이더와 환경 머티리얼은 **3d-essentials**, 커스텀 파티클 셰이더는 **particles-vfx**, 런타임에 셰이더 파라미터를 애니메이트하는 것은 **tween-animation**을 참고하라.

---

## 1. 핵심 개념

### 셰이더 타입

| 셰이더 타입      | 적용 대상               | 용도                                          |
|------------------|--------------------------|--------------------------------------------------|
| `canvas_item`    | 2D 노드(Sprite2D, Control 등) | 2D 효과 — 외곽선, 디졸브, 색 교체 |
| `spatial`        | 3D 메시(MeshInstance3D)         | 3D 머티리얼 — 물, 지형, 툰 셰이딩 |
| `particles`      | GPUParticles2D/3D                  | 커스텀 파티클 동작                    |
| `sky`            | WorldEnvironment                   | 절차적 하늘 렌더링                    |
| `fog`            | FogVolume                          | 볼류메트릭 안개 효과                      |

### 셰이더 대 ShaderMaterial

```
Shader (.gdshader)        → The code (GLSL-like language)
ShaderMaterial            → Instance of a shader with specific uniform values
CanvasItemMaterial / StandardMaterial3D → Built-in materials (no code needed)
```

여러 노드가 같은 Shader를 공유하되 서로 다른 uniform 값을 가진 서로 다른 ShaderMaterial 인스턴스를 가질 수 있다(예: 같은 디졸브 셰이더지만 적마다 다른 디졸브 진행도).

### 셰이더 만들기

1. 노드를 선택한다(예: Sprite2D)
2. 인스펙터 → Material → New ShaderMaterial
3. ShaderMaterial에서 → Shader → New Shader
4. 내장 에디터에서 `.gdshader` 파일을 편집한다

또는 FileSystem 독에서 직접 `.gdshader` 파일을 만든다.

---

## 2. Godot 셰이더 언어 기초

Godot는 GLSL ES 3.0 유사 언어에 Godot 고유 추가사항을 얹어 쓴다.

### 최소 Canvas Item 셰이더

```glsl
shader_type canvas_item;

void fragment() {
    // COLOR is the output pixel color
    // TEXTURE is the sprite's texture
    // UV is the texture coordinate (0,0 top-left to 1,1 bottom-right)
    vec4 tex = texture(TEXTURE, UV);
    COLOR = tex;
}
```

### 최소 Spatial 셰이더

```glsl
shader_type spatial;

void fragment() {
    // ALBEDO is the base color (vec3)
    ALBEDO = vec3(0.8, 0.2, 0.2);
}
```

### 내장 변수 (canvas_item)

| 변수   | 타입   | 설명                           |
|------------|--------|---------------------------------------|
| `UV`       | `vec2` | 텍스처 좌표                   |
| `COLOR`    | `vec4` | 출력 색(`fragment()`에서 설정) |
| `TEXTURE`  | `sampler2D` | 노드의 텍스처                |
| `VERTEX`   | `vec2` | 정점 위치(`vertex()`에서)       |
| `TIME`     | `float`| 경과 시간(초)               |
| `SCREEN_UV`| `vec2` | 스크린 공간 UV(화면 효과용)  |

> `SCREEN_TEXTURE`는 Godot 4.0에서 제거됐다. 화면을 읽으려면 uniform을 선언하라: `uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;`

### 내장 변수 (spatial)

| 변수    | 타입   | 설명                           |
|-------------|--------|---------------------------------------|
| `ALBEDO`    | `vec3` | 기본 표면 색                    |
| `METALLIC`  | `float`| 메탈릭 값(0.0–1.0)             |
| `ROUGHNESS` | `float`| 러프니스 값(0.0–1.0)            |
| `NORMAL`    | `vec3` | 표면 노멀(노멀 매핑용)   |
| `EMISSION`  | `vec3` | 발광 색                        |
| `ALPHA`     | `float`| 투명도(render mode에서 활성화)  |
| `VERTEX`    | `vec3` | 정점 위치(`vertex()`에서)       |

### Uniform (셰이더 파라미터)

Uniform은 셰이더 값을 인스펙터와 코드에 노출한다.

```glsl
shader_type canvas_item;

uniform float speed : hint_range(0.0, 10.0, 0.1) = 1.0;
uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D noise_texture : filter_linear_mipmap;

void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    COLOR = tex * tint_color;
}
```

### 흔한 Uniform 힌트

| 힌트                        | 타입         | 설명                         |
|-----------------------------|--------------|-------------------------------------|
| `hint_range(min, max, step)` | `float/int` | 인스펙터의 슬라이더                 |
| `source_color`              | `vec4`       | 인스펙터의 색 선택기           |
| `filter_linear_mipmap`      | `sampler2D`  | 텍스처 필터링 모드              |
| `repeat_enable`             | `sampler2D`  | 텍스처 타일링 허용                |
| `hint_normal`               | `sampler2D`  | 노멀 맵으로 취급                 |

### 코드에서 Uniform 설정

#### GDScript

```gdscript
var mat: ShaderMaterial = $Sprite2D.material
mat.set_shader_parameter("speed", 2.0)
mat.set_shader_parameter("tint_color", Color.RED)
```

#### C#

```csharp
var mat = GetNode<Sprite2D>("Sprite2D").Material as ShaderMaterial;
mat.SetShaderParameter("speed", 2.0f);
mat.SetShaderParameter("tint_color", Colors.Red);
```

---

## 3. 흔한 2D 셰이더 레시피

대부분의 프로젝트가 필요로 하는 canvas_item 레시피: **디졸브**(노이즈 + 가장자리 글로우), **외곽선**(이웃 샘플링, 알파 확장), **플래시-화이트**(uniform 구동 히트 효과), **색 교체**(팔레트 시프트), **UV 스크롤**(물/용암/구름), **웨이브 왜곡**.
---

## 4. 흔한 3D 셰이더 레시피

스페이셜 셰이더 레시피: **툰/셀 셰이딩**(밴딩된 NdotL), **림 라이팅 / 프레넬**(1 - NdotV), **간단한 물 표면**(UV 스크롤 + 노멀 맵 블렌드 + 프레넬).
---

## 5. 비주얼 셰이더

비주얼 셰이더는 노드 기반 그래프 에디터를 제공한다 — 코드가 필요 없다.

### 비주얼 셰이더를 언제 쓰나

| 비주얼 셰이더를 쓸 때        | 코드 셰이더를 쓸 때              |
|--------------------------------|------------------------------------|
| 효과를 빠르게 프로토타이핑    | 복잡한 수학이나 분기 로직    |
| 아티스트가 값을 조정해야 함   | 모든 줄을 정밀 제어해야 함 |
| 셰이더 개념 학습       | 성능이 중요한 셰이더       |
| 간단한 효과(색 조정, UV 스크롤) | 루프나 고급 기법 |

### 비주얼 셰이더 만들기

1. 노드 선택 → 인스펙터 → Material → New ShaderMaterial
2. Shader → New VisualShader
3. 셰이더를 클릭해 비주얼 셰이더 에디터를 연다
4. 팔레트에서 노드를 추가하고 핀을 연결한다
5. 출력 노드(Output, FragmentOutput)는 미리 배치돼 있다

### 핵심 비주얼 셰이더 노드

| 노드                | 목적                              |
|---------------------|--------------------------------------|
| `Texture2D`         | 텍스처 샘플링                     |
| `ColorConstant`     | 단색 값                    |
| `VectorOp`          | 벡터 수학 연산           |
| `ScalarOp`          | float 수학 연산            |
| `Mix`               | 두 값 사이 lerp              |
| `Step` / `SmoothStep` | 임계 / 부드러운 임계      |
| `Time`              | 현재 시간(애니메이션용)         |
| `UV`                | 텍스처 좌표                  |
| `Input` (커스텀)    | 인스펙터에 uniform 노출        |

> 비주얼 셰이더는 작성된 셰이더와 동일한 GPU 코드로 컴파일된다. 성능 차이는 없다.

> **Godot 4.7+:** 두 개의 새 스페이셜 `Input` 노드 — `in_shadow_pass`(vertex/fragment; `IN_SHADOW_PASS` 내장 변수에 매핑, 셰이더가 섀도 매핑 패스에서 렌더될 때 `true` — 섀도 맵에서 일반 패스와 다르게 객체를 렌더함)와 `specular_amount`(`light()`; `SPECULAR_AMOUNT`에 매핑 — OmniLight3D/SpotLight3D는 `2.0` × `light_specular`, DirectionalLight3D는 `1.0`).

> ⚠️ **Godot 4.7에서 변경됨:** `LinearToSRGB` 비주얼 셰이더 노드는 Forward+ 또는 Mobile 렌더러를 쓸 때 더 이상 출력을 `[0.0, 1.0]`으로 클램프하지 않는다 — `1.0`을 넘는 HDR 값이 이제 그대로 통과한다. 암묵적 클램프에 의존하던 그래프는 다른 출력을 낸다; 예전 동작을 복원하려면 명시적 `Clamp` 노드를 추가하라. [4.7 마이그레이션 가이드](https://docs.godotengine.org/en/latest/tutorials/migrating/upgrading_to_godot_4.7.html)를 보라.

---

## 6. 후처리 효과

표준 패턴: 게임플레이 캔버스 위에 canvas_item 셰이더를 얹은 전체 사각형 `ColorRect`. 3D의 경우 `WorldEnvironment`의 Adjustment, Glow, 또는 커스텀 셰이더를 쓴다. 연쇄 효과의 경우 월드를 `SubViewport`에 렌더한 뒤 최종 셰이더 패스에서 그 텍스처를 샘플링한다.
---

## 7. Compositor 효과 (Godot 4.3+)

`CompositorEffect`는 Godot 렌더 파이프라인 안에서(톤매핑 후 또는 전) 커스텀 렌더 패스를 돌린다. ColorRect 오버레이로 부족할 때 쓴다 — 멀티패스 효과, 깊이 인식 효과, 커스텀 AO/SSR 변형. 스크린 공간 셰이더보다 설정이 무겁다; 필요할 때만 손을 뻗어라.
---

## 8. 렌더 모드

렌더 모드는 `shader_type` 다음 첫 줄에 오며, 셰이더가 렌더링 파이프라인과 어떻게 상호작용하는지 제어한다.

### Canvas Item 렌더 모드

```glsl
shader_type canvas_item;
render_mode unshaded;           // Ignore all lighting
render_mode light_only;         // Only visible where lit
render_mode blend_add;          // Additive blending (glow, fire)
render_mode blend_mix;          // Standard alpha blending (default)
render_mode blend_premul_alpha; // Pre-multiplied alpha
```

### Spatial 렌더 모드

```glsl
shader_type spatial;
render_mode unshaded;              // No lighting calculations
render_mode cull_disabled;         // Render both sides of faces
render_mode depth_draw_always;     // Always write to depth buffer
render_mode specular_toon;         // Toon specular model
render_mode diffuse_toon;          // Toon diffuse model
render_mode blend_add;             // Additive blending
```

---

## 9. 스텐실 버퍼 효과 (Godot 4.5+)

Godot 4.5는 모든 렌더링 백엔드에서 `stencil_write_mode`, `stencil_read_mode`, `stencil_value` 등을 통해 스페이셜과 canvas_item 셰이더에 스텐실 쓰기/읽기를 노출한다. 이전에는 컴포지터 레벨 작업이 필요했던 포털, X-레이 시야, 외곽선 마스크, 지오메트리 구멍 효과를 가능하게 한다.
---

## 10. SMAA 안티에일리어싱 (Godot 4.5+)

서브픽셀 모폴로지컬 안티에일리어싱(SMAA 1x)은 Godot 4.5에 추가된 내장 후처리 AA 모드다. FXAA보다 더 선명하고 시간적으로 안정적인 결과를 내며, 디퍼드 중심 씬에서 MSAA보다 비용이 적다.

### SMAA 활성화

1. **Project Settings**를 연다
2. **Rendering → Anti Aliasing → Quality**로 이동한다
3. **Screen Space AA**를 **SMAA**로 설정한다

SMAA는 MSAA(지오메트리 가장자리 에일리어싱용)와 결합하거나 단독으로 쓸 수 있다. 셰이더 코드 변경이 필요 없다.

| AA 모드 | 선명도 | GPU 비용 | 고스팅 |
|---------|-----------|----------|----------|
| Disabled | 해당 없음 | 없음 | 없음 |
| FXAA | 낮음(흐림) | 매우 낮음 | 낮음 |
| **SMAA** | 높음 | 낮음 | 매우 낮음 |
| TAA | 중간(약간 흐림) | 중간 | 가능 |
| MSAA 4x | 높음 | 높음 | 없음 |

> **SMAA를 언제 쓰나:** 대부분의 데스크톱 프로젝트에서 FXAA보다 SMAA를 선호하라 — 비슷한 성능 프로파일로 눈에 띄게 선명한 텍스트와 가는 가장자리를 준다. 적당한 비용에 최고 품질을 원하면 SMAA + MSAA 2x를 결합하라.

이것은 에디터/익스포트 설정일 뿐이다 — 런타임 API가 필요 없다.

---

## 11. Shader Baker — 익스포트 시점 사전 컴파일 (Godot 4.5+)

Shader Baker는 익스포트 시점에 타깃 플랫폼용으로 프로젝트의 모든 셰이더를 사전 컴파일해, 게임에서 새 머티리얼이 처음 렌더될 때 플레이어가 겪는 스터터를 제거한다 — 셰이더 변환이 비싼 macOS/Apple Silicon(Metal)과 Windows(D3D12)에서 특히 심하다. 릴리스 빌드에서는 익스포트 프리셋별로 활성화하고, 개발 빌드에서는 익스포트를 빠르게 유지하려고 꺼둬라. Godot 익스포트 파이프라인 레벨에서 동작한다 — 익스포트 프리셋 설정은 **export-pipeline** 스킬을 보라.
---

## 12. 흔한 함정

| 증상                             | 원인                                             | 해결                                                              |
|-------------------------------------|----------------------------------------------------|------------------------------------------------------------------|
| 셰이더에 보이는 효과가 없음        | 머티리얼이 할당 안 됐거나 셰이더가 저장 안 됨           | 인스펙터에서 노드의 Material 프로퍼티를 확인하라                      |
| 투명 부분이 검게 렌더됨   | 셰이더에서 알파를 처리 안 함                        | `COLOR.a = tex.a;`를 설정하고 적절한 블렌드 모드를 써라            |
| Uniform이 인스펙터에 안 나타남 | uniform 이름 오타나 잘못된 타입                 | 셰이더를 다시 저장하라; 컴파일 에러를 확인하라                 |
| 텍스처가 늘어나거나 타일됨    | `repeat_enable` 누락이나 잘못된 UV 스케일          | sampler2D uniform에 `repeat_enable` 힌트를 추가하라                    |
| 에디터에선 되는데 게임에선 안 됨 | 스크린 텍스처 uniform에 백버퍼가 필요          | `sampler2D` uniform에 `hint_screen_texture`를 써라(Godot 4.x)  |
| 셰이더가 많으면 성능 저하 | 고유 셰이더마다 = 드로우콜 끊김               | ShaderMaterial 인스턴스를 공유하고 변형에는 uniform을 써라        |
| 스크린 공간 UV가 틀림            | `SCREEN_UV`가 일부 맥락에서 사용 불가         | 노드가 올바른 뷰포트에서 렌더되는지 확인하라              |
| 비주얼 셰이더 노드 사라짐          | 새 Godot 버전에서 노드가 이름 바뀌거나 제거됨 | 현재 노드 이름은 Godot 문서를 확인하라                       |

> ⚠️ **Godot 4.7에서 변경됨:** `textureQueryLod()`는 fragment 셰이더에서만 사용 가능하고, Godot 4.7은 컴파일 에러로 이를 강제한다 — `vertex()`에서 호출하던 셰이더는 업그레이드 후 컴파일이 멈춘다. 호출을 `fragment()`로 옮겨라. [GH-118962](https://github.com/godotengine/godot/pull/118962)를 보라.

---

## 13. 구현 체크리스트

- [ ] 셰이더 타입이 노드 타입과 맞는다(2D는 `canvas_item`, 3D는 `spatial`)
- [ ] Uniform이 적절한 힌트를 쓴다(`hint_range`, `source_color`, `filter_linear_mipmap`)
- [ ] 공유 비주얼 효과가 같은 Shader 리소스를 별개의 ShaderMaterial 인스턴스로 쓴다
- [ ] 후처리 셰이더가 게임 오브젝트가 아니라 CanvasLayer(2D)나 WorldEnvironment(3D)에 있다
- [ ] canvas_item 셰이더에서 `TEXTURE`를 샘플링한다(아니면 스프라이트 콘텐츠가 사라진다)
- [ ] 알파 투명 셰이더가 `COLOR.a`를 올바로 설정하고 `blend_mix` 렌더 모드를 쓴다
- [ ] 애니메이트되는 셰이더 파라미터(디졸브, 플래시)를 `_process`가 아니라 Tween이나 AnimationPlayer로 구동한다
- [ ] 화면을 읽는 셰이더가 `sampler2D` uniform에 `hint_screen_texture`를 쓴다(Godot 4.x 방식)
- [ ] 복잡한 셰이더를 Godot 프로파일러로 프로파일링해 GPU 프레임 시간을 확인한다
- [ ] 스텐실 효과가 올바른 렌더 우선순위로 2패스 머티리얼(쓰기 패스 먼저, 읽기 패스 다음)을 쓴다(Godot 4.5+)
- [ ] 데스크톱 빌드에서 FXAA보다 SMAA를 선호한다(선명한 가장자리, 비슷한 비용) — Project Settings → Rendering → Anti Aliasing에서 설정(Godot 4.5+)
- [ ] 첫 사용 컴파일 스터터를 제거하려고 모든 릴리스 익스포트 프리셋에서 Shader Baker를 활성화한다(Godot 4.5+)
