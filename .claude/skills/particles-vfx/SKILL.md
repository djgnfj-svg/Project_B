---
name: particles-vfx
description: 파티클 효과를 구현할 때 사용한다 — GPUParticles2D/3D, ParticleProcessMaterial, 방출 형태, 서브에미터, 트레일, 어트랙터, 충돌, 그리고 흔한 VFX 레시피
---

# Godot 4.3+에서의 파티클 시스템

모든 예제는 Godot 4.3+를 대상으로 하며 폐기된 API를 쓰지 않는다. GDScript를 먼저 보이고, 그다음 C#을 보인다.

> **관련 스킬:** 커스텀 파티클 셰이더는 **shader-basics**, 파티클에 영향을 주는 조명과 환경은 **3d-essentials**, 2D 렌더링 컨텍스트는 **2d-essentials**, 코드 구동 VFX 타이밍은 **tween-animation**, 파티클 성능 튜닝은 **godot-optimization**을 보라.

---

## 1. 핵심 개념

### GPU vs CPU 파티클

| Node                | Processing | Features                                | Use For                        |
|---------------------|------------|-----------------------------------------|--------------------------------|
| `GPUParticles2D`    | GPU        | 전체 기능, 높은 개수, 트레일           | 대부분의 2D 효과               |
| `GPUParticles3D`    | GPU        | 전체 기능, 어트랙터, 충돌               | 대부분의 3D 효과               |
| `CPUParticles2D`    | CPU        | 더 단순, 트레일/어트랙터 없음           | 저사양 기기, 적은 파티클       |
| `CPUParticles3D`    | CPU        | 더 단순, 트레일/어트랙터 없음           | 저사양 기기, 적은 파티클       |

**경험칙:** 기본적으로 GPU 파티클을 써라. 저사양/웹 타깃이거나 CPU 측 파티클 위치가 필요할 때(예: 파티클 위치에 객체 스폰)만 CPU 파티클로 전환하라.

> 에디터에서 GPU와 CPU 파티클을 변환할 수 있다: 노드 선택 → 툴바 → **Convert to CPUParticles2D/3D** (또는 그 반대).

### 파티클 시스템 아키텍처

```
GPUParticles2D/3D
├── Process Material (ParticleProcessMaterial)   ← physics, emission, color
├── Draw Pass 1 (Mesh)                            ← what each particle looks like
└── (Optional) Draw Pass 2-4                      ← additional meshes
```

### 최소 설정

1. **GPUParticles2D**(또는 3D) 노드를 추가한다
2. 인스펙터 → Process Material → **New ParticleProcessMaterial**
3. **Amount**(파티클 수)를 설정한다
4. 방출, 방향, 속도, 중력을 구성한다
5. (2D) 파티클 외형용 **Texture**를 설정한다
6. (3D) **Draw Pass 1** 메시를 설정한다(빌보드용 QuadMesh, 또는 커스텀 메시)

---

## 2. 핵심 노드 속성

### GPUParticles2D/3D 속성

| Property          | Type     | Description                                         |
|-------------------|----------|-----------------------------------------------------|
| `emitting`        | `bool`   | 방출 시작/정지                                      |
| `amount`          | `int`    | 동시에 살아 있는 총 파티클 수                       |
| `lifetime`        | `float`  | 각 파티클이 사는 초                                 |
| `one_shot`        | `bool`   | 한 번 방출 후 정지                                  |
| `preprocess`      | `float`  | 첫 프레임 전에 이만큼의 초를 시뮬레이션             |
| `speed_scale`     | `float`  | 파티클 물리의 시간 배수                             |
| `explosiveness`   | `float`  | 0.0 = 수명에 걸쳐 분산, 1.0 = 전부 한 번에         |
| `fixed_fps`       | `int`    | 파티클 갱신 속도 고정 (0 = 렌더 FPS에 맞춤)         |
| `local_coords`    | `bool`   | 파티클이 노드와 함께 이동(true) 또는 월드에 머묾(false) |
| `draw_order`      | `enum`   | Index, Lifetime, 또는 Reverse Lifetime              |
| `amount_ratio`    | `float`  | 방출할 파티클 비율 (0.0–1.0)                        |

### One-Shot vs 연속

```gdscript
# Continuous emitter (fire, smoke, ambient dust)
$GPUParticles2D.one_shot = false
$GPUParticles2D.emitting = true

# One-shot burst (explosion, impact splash)
$GPUParticles2D.one_shot = true
$GPUParticles2D.emitting = false  # arm it
# Later, trigger:
$GPUParticles2D.restart()
$GPUParticles2D.emitting = true
```

```csharp
// Continuous
var particles = GetNode<GpuParticles2D>("GPUParticles2D");
particles.OneShot = false;
particles.Emitting = true;

// One-shot burst
particles.OneShot = true;
particles.Emitting = false;
// Trigger:
particles.Restart();
particles.Emitting = true;
```

### 로컬 빌보드 정렬 (Godot 4.7+)

`GPUParticles3D`는 `TRANSFORM_ALIGN_LOCAL_BILLBOARD`(`= 4`)를 얻는다: 각 파티클의 Z축이 카메라를 향하되 주어진 축(X 또는 Y, `transform_align_axis`로 선택)을 보존한다. 빌보드된 파티클의 경우, `transform_align_channel_filter`가 각도 계산에 읽을 커스텀 채널을 선택한다. `ParticleProcessMaterial`은 이를 축별 회전 속도와 짝짓는다: `use_rotation_velocity_3d`를 켜고, `rotation_velocity_3d_min/max`(`Vector3`, 파티클 로컬 축)와 선택적으로 `rotation_velocity_3d_curve`(수명에 걸친 축별 커브)를 설정하라.

```gdscript
# 3D only — billboard toward the camera while keeping the Y axis fixed.
# Assumes a ParticleProcessMaterial is assigned (section 1 setup).
$GPUParticles3D.transform_align = GPUParticles3D.TRANSFORM_ALIGN_LOCAL_BILLBOARD
$GPUParticles3D.transform_align_axis = RenderingServer.PARTICLES_ALIGN_AXIS_Y

var mat: ParticleProcessMaterial = $GPUParticles3D.process_material
mat.use_rotation_velocity_3d = true
mat.rotation_velocity_3d_min = Vector3(-2.0, 0.0, 0.0)
mat.rotation_velocity_3d_max = Vector3(2.0, 0.0, 0.0)
```

```csharp
// Assumes a ParticleProcessMaterial is assigned (section 1 setup).
var particles = GetNode<GpuParticles3D>("GPUParticles3D");
particles.TransformAlign = GpuParticles3D.TransformAlignEnum.LocalBillboard;
particles.TransformAlignAxis = RenderingServer.ParticlesTransformAlignAxis.Y;

var mat = (ParticleProcessMaterial)particles.ProcessMaterial;
mat.UseRotationVelocity3D = true;
mat.RotationVelocity3DMin = new Vector3(-2.0f, 0.0f, 0.0f);
mat.RotationVelocity3DMax = new Vector3(2.0f, 0.0f, 0.0f);
```

---

## 3. ParticleProcessMaterial — 핵심 속성

머티리얼이 파티클별 동작을 구동한다: **방출 형태**(Point / Sphere / Box / Ring / Points / Directed Points), **방향 + 확산 + 초기 속도**, **중력**, **수명에 걸친 스케일과 색**(`scale_curve` / `color_ramp`를 통해), **감쇠(damping)**, **방사/접선 가속도**, 그리고 **각속도**.
### 축별 3D 스케일 & 회전 (Godot 4.7+)

스케일과 초기 방향을 균일하게가 아니라 축별로 무작위화한다. `use_scale_3d`는 `scale_3d_min/max`(`Vector3` 파티클별 무작위 스케일)를 활성화하고; `use_rotation_3d`는 `rotation_3d_min/max`(`Vector3`, 도 — 3D에서만 동작)를 활성화한다.

```gdscript
mat.use_scale_3d = true
mat.scale_3d_min = Vector3(0.5, 1.0, 0.5)
mat.scale_3d_max = Vector3(1.0, 2.0, 1.0)

mat.use_rotation_3d = true  # 3D only
mat.rotation_3d_min = Vector3(0.0, -180.0, 0.0)  # degrees
mat.rotation_3d_max = Vector3(0.0, 180.0, 0.0)
```

```csharp
mat.UseScale3D = true;
mat.Scale3DMin = new Vector3(0.5f, 1.0f, 0.5f);
mat.Scale3DMax = new Vector3(1.0f, 2.0f, 1.0f);

mat.UseRotation3D = true;  // 3D only
mat.Rotation3DMin = new Vector3(0.0f, -180.0f, 0.0f);  // degrees
mat.Rotation3DMax = new Vector3(0.0f, 180.0f, 0.0f);
```

### 에미터 스케일 상속 (Godot 4.7+)

`particle_flag_inherit_emitter_scale`(기본 `false`): `true`면 파티클이 에미터 노드의 스케일을 상속한다. `local_coords`가 `true`일 때는 효과가 없다 — 로컬 공간의 파티클은 이미 에미터의 스케일에 영향받기 때문이다.

```gdscript
mat.particle_flag_inherit_emitter_scale = true
```

```csharp
mat.ParticleFlagInheritEmitterScale = true;
```

---

## 4. 흔한 VFX 레시피

대부분의 프로젝트가 필요로 하는 레시피: **불**(2D, 뜨거운 색 그라디언트 + 축소가 있는 반복 방출), **폭발 버스트**(one-shot, 높은 개수 짧은 수명), **먼지 / 발자국 퍼프**(one-shot, 확대 + 빠른 페이드).
---

## 5. 트레일 (Forward+와 Mobile 전용)

`GPUParticles2D/3D`에서 `trail_enabled = true`를 설정하고 `Mesh`(`RibbonTrailMesh` 또는 `TubeTrailMesh`)를 지정하라. 트레일은 Compatibility 렌더러에서 지원되지 않는다.
---

## 6. 서브에미터(Subemitters)

파티클은 생명주기 이벤트(탄생, 충돌, 죽음, 수동)에 다른 파티클 씬을 스폰할 수 있다. 부모 파티클 노드의 `ParticleProcessMaterial.SubEmitterMode` + `subemitter` 속성으로 구성한다.
> ⚠️ **Godot 4.7에서 변경됨:** 서브에미터 속도 상속이 재작업됐다([GH-118062](https://github.com/godotengine/godot/pull/118062)). `sub_emitter_keep_velocity = true`(기본 `false`)면 서브에미터 파티클이 스폰될 때 부모 파티클의 속도를 상속한다. 이전 버전에서 작성한 서브에미터 효과는 업그레이드 후 달라 보일 수 있다 — 영향받는 시스템의 초기 속도와 확산을 재확인하라.

---

## 7. 어트랙터 & 충돌 (3D)

`GPUParticlesAttractor*3D`(Box / Sphere / Vector Field)는 파티클을 영역으로 끌어당긴다. `GPUParticlesCollision*3D`(Box / Sphere / SDF / HeightField)는 파티클이 지오메트리에서 튕기게 한다. 둘 다 Forward+/Mobile 전용; 2D 등가물은 없다.
---

## 8. 난기류(Turbulence)

`ParticleProcessMaterial`에서 `turbulence_enabled = true`를 설정하고 `turbulence_noise_strength`(0.5–2.0 전형), `turbulence_noise_scale`(낮을수록 큰 소용돌이), `turbulence_noise_speed`(노이즈 필드 애니메이션)를 튜닝하라. "살아 있는" 연기, 불, 먼지에 저렴한 효과.

---

## 9. 플립북 애니메이션 (2D)

`ParticleProcessMaterial.AnimSpeedMin/Max` + 시트 레이아웃용 `CanvasItemMaterial.ParticlesAnimHFrames/VFrames`로 스프라이트 시트 애니메이션 파티클. 파티클이 수명에 걸쳐 프레임을 순환한다.
---

## 10. 성능 팁

| Technique                    | Savings              | When to Use                          |
|------------------------------|----------------------|--------------------------------------|
| `amount` 낮추기              | 선형 GPU 절감        | 항상 — 필요한 최소만 써라            |
| `fixed_fps = 30`             | 파티클 갱신 반감     | 배경 파티클, 앰비언트               |
| `amount_ratio` < 1.0         | 동적으로 축소        | 품질 설정 슬라이더                   |
| 더 작은 텍스처               | VRAM + 대역폭 절감   | 모바일, 많은 파티클 시스템          |
| `local_coords = true`        | 더 저렴한 트랜스폼   | 파티클이 노드와 함께 이동해야 할 때 |
| `turbulence` 비활성          | 3D 노이즈 비용 제거  | 모바일/웹 타깃                       |
| 더 적은 `trail_sections`     | 더 적은 트레일 지오메트리 | 트레일 부드러움이 중요치 않을 때 |
| `visibility_rect` (2D)       | 화면 밖 건너뜀       | 2D 파티클엔 항상 설정               |

### 파티클 타임라인 탐색 (Godot 4.7+)

`request_particles_process(process_time, process_time_residual = 0.0)` — `GPUParticles2D/3D`와 `CPUParticles2D/3D`에서 — 단일 프레임 동안 추가 처리 시간을 요청한다. `process_time`은 방출을 켠 채로 시뮬레이션되고, 4.7에 추가된 `process_time_residual`은 방출을 끈 채로 시뮬레이션된다. `speed_scale = 0.0`과 결합하면 일시정지된 파티클 시스템의 타임라인을 탐색할 수 있다(예: 컷신이나 리플레이에서 VFX 스크러빙).

```gdscript
$GPUParticles3D.speed_scale = 0.0
# Simulate 1.5s with emission on, then 0.25s with emission off
$GPUParticles3D.request_particles_process(1.5, 0.25)
```

```csharp
var particles = GetNode<GpuParticles3D>("GPUParticles3D");
particles.SpeedScale = 0.0f;
particles.RequestParticlesProcess(1.5f, 0.25f);
```

### 동적 품질 스케일링

```gdscript
# Adjust particle density based on quality setting
func set_particle_quality(level: float) -> void:
    # level: 0.25 (low) to 1.0 (high)
    for particles in get_tree().get_nodes_in_group("particles"):
        if particles is GPUParticles2D or particles is GPUParticles3D:
            particles.amount_ratio = level
```

```csharp
public void SetParticleQuality(float level)
{
    foreach (var node in GetTree().GetNodesInGroup("particles"))
    {
        if (node is GpuParticles2D p2d)
            p2d.AmountRatio = level;
        else if (node is GpuParticles3D p3d)
            p3d.AmountRatio = level;
    }
}
```

---

## 11. 흔한 함정

| Symptom                              | Cause                                          | Fix                                                              |
|--------------------------------------|-------------------------------------------------|------------------------------------------------------------------|
| 파티클이 안 보임                     | 텍스처 없음(2D) 또는 draw pass 메시 없음(3D)   | 텍스처를 설정하거나 Draw Pass 1에 메시를 지정                    |
| 파티클이 나타났다 즉시 사라짐        | `lifetime`이 너무 짧음                          | `lifetime`을 늘려라 (기본 1.0s)                                 |
| One-shot이 재트리거 안 됨            | `emitting = true` 전에 `restart()` 호출 필요   | `restart()` 후 `emitting = true`를 설정                         |
| 파티클이 엉뚱한 방향으로 방출        | `direction` 또는 `gravity` 오설정               | 2D에서 Y는 반전 — 위쪽은 `Vector3(0, -1, 0)`                    |
| 파티클이 노드를 안 따라감            | `local_coords`가 `false`                        | 부착 효과엔 `local_coords = true`로 설정                        |
| 파티클이 팝인됨 (프리웜 없음)        | `preprocess` 시간 미설정                        | 앰비언트 효과엔 `preprocess`를 `lifetime`의 1–2배로 설정        |
| 컬러 램프가 효과 없음                | 램프를 덮는 `color` 속성 사용                   | `color_ramp` 사용 시 기본 `color`를 지워라(흰색으로)            |
| 트레일이 렌더 안 됨                  | 트레일 머티리얼 설정 누락 또는 잘못된 렌더러    | 머티리얼에 "Use Particle Trails" 활성; Forward+ 또는 Mobile 사용 |
| 어트랙터가 효과 없음                 | `attractor_interaction_enabled`가 `false`       | ParticleProcessMaterial에서 활성화                              |
| 서브에미터가 안 스폰됨               | 자식 `amount`가 스폰을 감당하기엔 너무 낮음     | 자식 시스템의 `amount`를 늘려라                                 |
| 모바일에서 파티클이 깜빡임           | `fixed_fps` 미설정 또는 너무 높음               | 기기 간 일관성을 위해 `fixed_fps = 30`으로 설정                 |

---

## 12. 구현 체크리스트

- [ ] 파티클 `amount`가 시각 효과에 필요한 최소로 설정됨
- [ ] `lifetime`이 시각적 지속시간에 맞음 — 너무 짧지도 길지도 않음
- [ ] 버스트 효과(폭발, 충격)엔 `one_shot`이 활성화됨
- [ ] 항상 보이는 앰비언트 효과(불, 연기, 먼지)엔 `preprocess`가 설정됨
- [ ] 방출 형태가 소스 지오메트리에 맞음(폭발엔 sphere, 영역 효과엔 box)
- [ ] `color_ramp`가 끝에서 알파를 0으로 페이드해 파티클이 갑자기 사라지지 않음
- [ ] `scale_curve`가 수명에 걸쳐 파티클을 축소해 자연스러운 페이드
- [ ] `local_coords`가 올바르게 설정됨 — 부착 효과엔 `true`, 월드 공간엔 `false`
- [ ] One-shot 파티클은 `lifetime` + 여유 후 `queue_free`로 정리됨
- [ ] `visibility_rect`(2D)가 파티클의 조기 컬링을 막게 설정됨
- [ ] 동적 품질 스케일링이 플레이어 접근 가능한 품질 설정에 `amount_ratio`를 씀
- [ ] 성능 부담이 큰 기능(난기류, 트레일)이 저사양 타깃에서 비활성화됨
