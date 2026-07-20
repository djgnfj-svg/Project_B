---
name: 2d-essentials
description: 2D 전용 시스템을 다룰 때 사용한다 — TileMap, 시차(parallax) 스크롤, 2D 조명과 그림자, 캔버스 레이어, 2D 파티클, 커스텀 드로잉, Godot 4.3+의 2D 메시
---

# Godot 4.3+의 2D 필수 요소

모든 예제는 Godot 4.3+를 대상으로 하며 폐기된(deprecated) API를 쓰지 않는다. GDScript를 먼저 보이고, 그다음 C#을 보인다.

> **관련 스킬:** CharacterBody2D 이동 패턴은 **player-controller**, AnimatedSprite2D와 스프라이트 애니메이션은 **animation-system**, 충돌 셰이프와 레이캐스팅은 **physics-system**, Camera2D 추적·흔들림은 **camera-system**, 2D 셰이더와 후처리는 **shader-basics**, 렌더링·드로우콜 튜닝은 **godot-optimization**을 참고하라.

---

## 1. 캔버스 레이어와 그리기 순서

### 그리기 순서 규칙

한 캔버스 레이어 안에서 노드는 **씬 트리 순서**로 그려진다 — Scene 패널에서 아래쪽에 있는 노드가 **위에** 그려진다. 트리를 재배치하지 않고 덮어쓰려면 `z_index`를 쓴다.

```gdscript
# Draw this node above siblings (default z_index is 0)
z_index = 10

# Make z_index relative to parent (default: false = global)
z_as_relative = true
```

### CanvasLayer

`CanvasLayer`는 카메라와 독립적인 자체 트랜스폼을 가진 별도의 렌더링 레이어를 만든다. `layer` 값이 클수록 위에 그려진다.

| Layer | 대표 용도 |
|-------|-------------|
| -1 | 시차 배경 |
| 0 | 기본 게임 레이어 (CanvasLayer 없는 모든 Node2D) |
| 1 | HUD / UI 오버레이 |
| 2 | 일시정지 메뉴, 화면 전환 |

```
# Scene tree example
Main
├── ParallaxBackground (CanvasLayer, layer = -1)
│   └── Parallax2D
├── World (Node2D — default layer 0)
│   ├── TileMapLayer
│   └── Player
└── HUD (CanvasLayer, layer = 1)
    └── Control
```

> **참고:** CanvasLayer가 그리기 순서를 제어하는 데 반드시 필요한 건 아니다. 같은 게임 월드 안 오브젝트라면 `z_index`나 씬 트리 순서를 써라. CanvasLayer는 카메라와 독립적이어야 하는 요소(HUD, 시차, 전환)를 위한 것이다.

### 캔버스 트랜스폼

`Camera2D`는 뷰포트의 `canvas_transform`을 수정하는 방식으로 동작한다. 수동으로 제어하려면:

```gdscript
# Scroll the canvas directly (equivalent to camera movement)
get_viewport().canvas_transform = Transform2D(0, Vector2(-200, 0))
```

### 좌표 변환

```gdscript
# Local to canvas (world) coordinates
var world_pos: Vector2 = get_global_transform() * local_pos
var local_pos: Vector2 = get_global_transform().affine_inverse() * world_pos

# Local to screen coordinates (accounts for camera, stretch, window)
var screen_pos: Vector2 = get_viewport().get_screen_transform() * get_global_transform_with_canvas() * local_pos
```

```csharp
// Local to canvas (world) coordinates
Vector2 worldPos = GetGlobalTransform() * localPos;
Vector2 localFromWorld = GetGlobalTransform().AffineInverse() * worldPos;

// Local to screen coordinates
Vector2 screenPos = GetViewport().GetScreenTransform() * GetGlobalTransformWithCanvas() * localPos;
```

---


## 2. TileMap 시스템

`TileMapLayer`(Godot 4.5+)가 현대적 API다 — 타일맵 하나 = 노드 하나 = 레이어 하나. 페인팅은 `TileSet` 리소스(아틀라스 + 속성 + 물리 + 커스텀 데이터)로 구동한다. 바이옴을 인식한 타일 선택에는 **지형 오토타일링(terrain autotiling)**, 타일 위에 씬 인스턴스를 배치하려면 **씬 컬렉션 타일(scene collection tiles)**을 써라.

---

## 3. 시차(Parallax) 스크롤

`Parallax2D`(Godot 4.4+)가 예전의 `ParallaxBackground`/`ParallaxLayer` 쌍을 대체한다. 레이어마다 `scroll_scale`을 설정한다(0 = 정지, 1 = 카메라를 1:1로 따라감, 소수 값은 깊이감용). 무한 타일링에는 `repeat_size`를 추가한다.

---

## 4. 2D 조명과 그림자

`PointLight2D`와 `DirectionalLight2D`는 스프라이트에 조명을 비춘다 — 노멀 맵과 함께 쓰면 3D 스타일 셰이딩이 되고, 평면 스프라이트에는 가산 블렌드(additive) 조명을 쓴다. `LightOccluder2D`로 그림자를 드리운다.

---

## 5. 2D 파티클 시스템

`GPUParticles2D`는 많은 개수(≥ 50 파티클, GPU 구동)에, `CPUParticles2D`는 적은 개수나 GPU 미지원 플랫폼에 쓴다. 둘 다 같은 `ParticleProcessMaterial` 인터페이스를 공유하며, 차이는 주로 성능이다.

---

## 6. 커스텀 드로잉

아무 `CanvasItem`에서나 `_draw()`를 재정의해 선, 폴리곤, 텍스트, 임의의 도형을 그린다. 재렌더를 트리거하려면 `queue_redraw()`를 호출한다(절대 `_draw()`를 직접 부르지 마라).

> **Godot 4.7+:** `DrawableTexture2D` — 런타임에 그릴 수 있는 텍스처 타입 — 은 4.7에 실험적(experimental)으로 나왔으며 아직 프로덕션에는 권장되지 않는다.

---

## 7. 2D 메시

### 언제 쓰나

투명 영역이 넓어 GPU 필레이트(fill rate)를 낭비할 때 `MeshInstance2D`가 `Sprite2D`를 대체한다. GPU는 완전히 투명한 픽셀까지 포함해 텍스처 쿼드 전체를 그리는데, 메시는 그 부분을 없앤다.

### Sprite2D를 MeshInstance2D로 변환

1. `Sprite2D`를 선택한다
2. 메뉴: **Sprite2D → Convert to MeshInstance2D**
3. 성장(growth)·단순화(simplification) 파라미터를 조정한다
4. "Convert 2D Mesh"를 클릭한다

가장 적합한 후보:
- 투명도가 있는 화면 크기 이미지
- 불규칙한 모양의 시차 레이어
- 넓은 투명 여백이 있는 레이어드 이미지
- 모바일/저사양 GPU 타깃

---

## 8. 2D 안티에일리어싱

### 노드별 안티에일리어싱 (권장)

많은 드로잉 메서드가 `antialiased` 파라미터를 지원한다:

```gdscript
draw_line(Vector2.ZERO, Vector2(100, 50), Color.WHITE, 2.0, true)  # antialiased = true
```

```csharp
// Equivalent in a CanvasItem subclass (e.g., a custom Control or Node2D):
public override void _Draw()
{
    DrawLine(new Vector2(0, 0), new Vector2(100, 50), Colors.White, width: 2.0f, antialiased: true);
}
```

`Line2D`에는 인스펙터에 `Antialiased` 속성이 있다 — C#에서는 `line2D.Antialiased = true`로, 에디터에서는 인스펙터 토글로 설정한다. 이는 추가 지오메트리를 생성하는 방식으로 동작한다 — MSAA가 필요 없다.

> ⚠️ **Godot 4.7에서 변경됨:** `CanvasItem` 안티에일리어싱 선 그리기가 더 이상 안티에일리어싱 페더(feather)를 추가하지 않는다. 페더가 `draw_line()` 계열 선을 의도보다 두껍게 보이게 했으므로, 업그레이드 후 안티에일리어싱 선은 더 얇게 렌더링된다 — 예전 모습에 의존하던 프로젝트는 `width`를 더 두껍게 그려야 한다. [4.7 마이그레이션 가이드](https://docs.godotengine.org/en/latest/tutorials/migrating/upgrading_to_godot_4.7.html)를 참고하라.

### MSAA 2D

Forward+와 Mobile 렌더러에서만 사용할 수 있다(Compatibility에서는 아님).

**Project Settings → Rendering → Anti Aliasing → Quality → MSAA 2D**

레벨: 2x, 4x, 8x.

| MSAA가 영향을 주는 것 | MSAA가 영향을 주지 않는 것 |
|-------------|---------------------|
| 지오메트리 가장자리(선, 폴리곤) | 최근접 이웃(nearest-neighbor) 텍스처 내부의 에일리어싱 |
| 텍스처 가장자리에 닿는 스프라이트 가장자리 | 커스텀 2D 셰이더 출력 |
| | 폰트 렌더링 |
| | Light2D의 스페큘러 에일리어싱 |

> **픽셀 아트의 경우:** MSAA 2D를 켜지 마라 — 의도적으로 날카롭게 만든 가장자리를 흐리게 한다. 노드별 `antialiased` 파라미터를 선택적으로 써라.

---

## 9. 2D 스냅과 픽셀 퍼펙트

### 에디터 스냅

2D 툴바의 점 세 개 메뉴:
- **Grid Step** — 그리드에 스냅(Grid Offset과 Step 구성)
- **Rotation Step** — 회전을 각도 단위로 스냅
- **Smart Snap** — 부모, 노드 앵커, 변, 중심, 가이드에 스냅

### 런타임 픽셀 스냅

픽셀 아트 게임에서는 서브픽셀 흔들림을 막으려고 픽셀 스냅을 켠다:

- **Node2D:** Project Settings → Rendering → 2D → Snapping → `Snap 2D Transforms to Pixel`
- **정점(Vertices):** Project Settings → Rendering → 2D → Snapping → `Snap 2D Vertices to Pixel`
- **Control:** Project Settings → GUI → General → `Snap Controls to Pixels`

---

## 10. 구현 체크리스트

- [ ] 배경이 Sprite2D나 ColorRect다(기본 클리어 색이 아님) — 그래야 2D 조명을 받는다
- [ ] TileSet이 외부 `.tres` 리소스로 저장돼 여러 레벨에서 재사용된다
- [ ] TileSet에 `Use Texture Padding`이 켜져 텍스처 번짐을 막는다
- [ ] Parallax2D 텍스처의 좌상단이 (0,0)에 있다(가운데 정렬이 아님)
- [ ] `repeat_size`가 실제 텍스처 크기와 일치한다
- [ ] 카메라가 줌아웃할 수 있으면 `repeat_times`를 늘린다
- [ ] 그림자를 켰을 때 그림자를 드리우는 오브젝트에 LightOccluder2D 노드를 추가한다
- [ ] 불필요한 조명 계산을 피하도록 라이트와 오클루더의 컬 마스크를 구성한다
- [ ] GPUParticles2D에 유효한 Visibility Rect가 있다(Particles 메뉴로 자동 생성)
- [ ] 커스텀 드로잉 상태가 바뀌면 `queue_redraw()`를 호출한다
- [ ] 타일의 충돌 셰이프는 수동 CollisionShape2D 노드가 아니라 Physics Layer 시스템을 쓴다
- [ ] 크고 투명한 스프라이트는 모바일/저사양 타깃에서 MeshInstance2D로 변환한다
