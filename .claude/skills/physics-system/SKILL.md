---
name: physics-system
description: 물리 바디, 충돌 형태, 레이캐스팅, 영역(area), 리지드바디, 래그돌, 소프트바디, Jolt 물리, 그리고 Godot 4.3+의 물리 보간을 다룰 때 사용한다
---

# Godot 4.3+에서의 물리 시스템

모든 예제는 Godot 4.3+를 대상으로 하며 폐기된 API를 쓰지 않는다. GDScript를 먼저 보이고, 그다음 C#을 보인다.

> **관련 스킬:** CharacterBody2D/3D 이동 패턴은 **player-controller**, hitbox/hurtbox 조합은 **component-system**, 물리 성능 튜닝은 **godot-optimization**, 카메라 추적과 보간은 **camera-system**, 네트워크 물리는 **multiplayer-sync**, 타일 충돌 설정과 2D 캔버스 레이어는 **2d-essentials**를 보라.

---

## 1. 물리 바디 타입

네 가지 충돌 객체 타입(뒤 셋은 `PhysicsBody2D`/`3D`를 확장한다):

| Type | Moved by | Use for |
|------|----------|---------|
| `Area2D/3D` | 코드 | 겹침 감지, 중력 영역, 오디오 영역 |
| `StaticBody2D/3D` | 이동 안 됨(또는 `constant_linear_velocity`) | 벽, 바닥, 컨베이어 벨트 |
| `RigidBody2D/3D` | 물리 엔진 | 상자, 투사체, 파편, 래그돌 |
| `CharacterBody2D/3D` | 코드 | 플레이어, 적, NPC (**player-controller** 참고) |

모든 충돌 객체는 최소 하나의 `CollisionShape2D`/`3D`(또는 `CollisionPolygon2D`/`3D`) 자식이 필요하다. **Jolt Physics는 4.4부터 기본 3D 엔진**(4.6부터 비실험적)이다 — 8절 참고. 2D는 항상 GodotPhysics를 쓴다.

> **핵심 규칙:** 충돌 형태나 물리 바디를 `scale`로 절대 스케일하지 마라. 형태 자체의 크기 파라미터(radius, extents, height)를 써라 — 스케일된 형태는 잘못된 충돌 결과를 낸다.

---

## 2. RigidBody2D/3D

### 힘(Force) vs 임펄스(Impulse)

| Method | Effect | When to use |
|---|---|---|
| `apply_force(force, position)` | 점에서의 연속 가속 | 추진기, 바람, 자석 |
| `apply_central_force(force)` | 중심에서의 연속 가속 | 중력, 일정한 밀어냄 |
| `apply_impulse(impulse, position)` | 점에서의 즉각 속도 변화 | 총알 명중, 폭발 |
| `apply_central_impulse(impulse)` | 중심에서의 즉각 속도 변화 | 점프, 넉백 |
| `apply_torque(torque)` | 연속 각가속 | 조향, 회전 |
| `apply_torque_impulse(impulse)` | 즉각 각속도 변화 | 충격 회전 |
### _integrate_forces() — 안전한 물리 수정

RigidBody의 트랜스폼, 속도, 각속도를 읽거나 수정해야 할 때는 `_physics_process()` 대신 `_integrate_forces(state)`를 써라. `_physics_process()`에서 `position`이나 `linear_velocity`를 직접 설정하면 물리 엔진과 싸운다.

> **경고:** `_integrate_forces()`는 바디가 잠자는(sleeping) 동안 호출되지 않는다. 연속 콜백이 필요하면 `can_sleep = false`로 설정하고, 아니면 성능을 위해 바디가 잠들게 두는 편을 우선하라.
### 접촉 모니터링, PhysicsMaterial, Freeze, look_at

- **접촉 시그널**은 `contact_monitor = true` + `max_contacts_reported > 0`이 필요하다. 그러면 `body_entered`/`body_exited`가 기대대로 발생한다.
- **`PhysicsMaterial`** 리소스가 `friction`(0 얼음 → 1 고무)과 `bounce`(0 → 1)를 제어한다.
- **Freeze 모드:** `FREEZE_MODE_STATIC`(StaticBody처럼 동작) 또는 `FREEZE_MODE_KINEMATIC`(코드로 이동, 다른 것을 밀어냄).
- **RigidBody3D 방향:** RigidBody에 절대 `look_at()`을 쓰지 마라 — `_integrate_forces`를 쓰고 외적 조향 항으로 `state.angular_velocity`를 설정하라.
---

## 3. StaticBody2D/3D

`StaticBody`는 물리 엔진이 이동시키지 않지만 `constant_linear_velocity`로 다른 바디를 밀어낼 수 있다(예: 컨베이어 벨트). 코드로 이동하면서 CharacterBody를 미는 발판에는 **`AnimatableBody2D`/`3D`**를 써라 — 코드로 이동한 순수 `StaticBody`는 CharacterBody를 안정적으로 밀지 못한다.
---

## 4. Area2D/3D

Area는 겹침을 감지하고 자기 경계 안의 물리 속성을 오버라이드한다. 충돌 반응은 만들지 않는다 — 바디가 통과한다. 바디 겹침은 `body_entered` / `body_exited`를, Area-대-Area(hitbox vs hurtbox — **component-system** 참고)는 `area_entered` / `area_exited`를 연결하라. Area는 또한 중력(무중력 영역, 점 중력 / 블랙홀), `linear_damp` / `angular_damp`(물, 슬로모)를 오버라이드하고 오디오를 특정 `AudioBus`로 리다이렉트할 수 있다. 여러 area가 겹치면 `priority`가 순서를 정한다; `space_override` 모드(`COMBINE`, `REPLACE`, `COMBINE_REPLACE`, `REPLACE_COMBINE`)를 골라라.
> ⚠️ **Godot 4.7에서 변경됨:** Jolt Physics에서 `Area3D`는 이제 시그널과 메서드로 `SoftBody3D`와의 겹침을 보고한다. 원치 않는 `Area3D` ↔ `SoftBody3D` 상호작용이 무시되도록 충돌 레이어/마스크를 구성하라. [4.7 마이그레이션 가이드](https://docs.godotengine.org/en/latest/tutorials/migrating/upgrading_to_godot_4.7.html)를 보라.

---

## 5. 충돌 형태

| Shape (2D / 3D) | Use case |
|---|---|
| `Rectangle` / `Box` | 상자, 발판, 방 |
| `Circle` / `Sphere` | 공, 투사체, 단순 캐릭터, 트리거 영역 |
| `Capsule` (2D & 3D) | 캐릭터 — 둥글고, 모서리를 넘어 미끄러짐 |
| `Segment2D` / — | 얇은 벽, 레이저 빔 |
| `SeparationRay2D` / — | 캐릭터 지면 스냅 |
| `WorldBoundary2D` / — | 무한 바닥/벽/천장 |
| — / `Cylinder3D` | 기둥, 통 (Jolt 전용 — GodotPhysics에선 불안정) |

### Convex vs Concave

| Type | Usable with | Cost | Notes |
|---|---|---|---|
| Primitive | 모든 바디 | 가장 저렴 | 동적 바디엔 항상 우선 |
| `ConvexPolygonShape` | 모든 바디 | 빠름 | 구멍이나 안쪽 곡선 없음 |
| `ConcavePolygonShape` | **StaticBody 전용** | 가장 느림 | 레벨 지오메트리에 정확; 부피 없음 |

**형태 생성:** 3D는 `MeshInstance3D` → **Mesh** 메뉴 → Create Single Convex / Multiple Convex (V-HACD) / Trimesh (ConcavePolygonShape). 2D는 `Sprite2D` → **Sprite2D** 메뉴 → Create CollisionPolygon2D Sibling(Simplification / Shrink / Grow 조정).

### 성능 규칙

동적 바디엔 primitive를 선호하라; 바디당 형태 수를 최소화하라(각각 narrow-phase 검사 비용); CollisionShape 노드를 절대 이동/회전/스케일하지 마라 — 변환되지 않은 단일 형태는 broad-phase 최적화를 가능케 한다; concave 형태는 StaticBody에만(O(n) 삼각형 검사); 한 바디의 여러 형태는 서로 충돌하지 않는다(버그가 아니라 정상); 형태는 직계 자식이어야 한다 — 간접 자식은 무시된다.

### 단방향 충돌 방향 (Godot 4.7+)

`CollisionShape2D.one_way_collision_direction: Vector2`(기본 `Vector2(0, 1)`)는 단방향 충돌에 쓰는 방향을 설정한다 — 2D 단방향 발판이 커스텀 통과 방향을 쓸 수 있다. `PhysicsServer2D.body_set_shape_as_one_way_collision()`도 맞물리는 선택적 `direction: Vector2 = Vector2(0, 1)` 파라미터를 얻는다.

```gdscript
var shape: CollisionShape2D = $CollisionShape2D
shape.one_way_collision = true
shape.one_way_collision_direction = Vector2(1, 0)  # Sideways one-way wall (default: Vector2(0, 1))
```

```csharp
var shape = GetNode<CollisionShape2D>("CollisionShape2D");
shape.OneWayCollision = true;
shape.OneWayCollisionDirection = new Vector2(1, 0); // Sideways one-way wall (default: Vector2(0, 1))
```

---

## 6. 충돌 레이어와 마스크

Godot은 차원당 32개의 물리 레이어를 제공한다(2D와 3D 별도).

- **collision_layer** — 이 객체가 **존재하는** 레이어(다른 것들이 여기서 스캔한다)
- **collision_mask** — 이 객체가 **스캔하는** 레이어(무엇을 감지하나)

> **멘탈 모델:** Layer = "나는 있다", Mask = "나는 스캔한다". 객체 A의 mask가 객체 B의 layer를 포함하거나, 그 반대일 때 충돌이 일어난다.

레이어 이름은 **Project Settings → Layer Names → 2D Physics**(또는 3D Physics)에서 짓고; 코드에서는 `set_collision_layer_value(N, true)` / `set_collision_mask_value(N, true)`(1-인덱스)로 설정한다.
---

## 7. 레이캐스팅과 물리 쿼리

### RayCast2D/3D 노드 (단순한 프레임당 레이)

`RayCast2D` / `RayCast3D`를 자식 노드로 추가하라 — 매 물리 프레임 자동으로 캐스트한다. `is_colliding()`과 `get_collider()` / `get_collision_point()` / `get_collision_normal()`로 읽는다.
### 코드 기반 레이캐스팅 (PhysicsDirectSpaceState)

온디맨드 쿼리는 `get_world_2d().direct_space_state`(또는 `get_world_3d()`)로 space state에 접근하고 `PhysicsRayQueryParameters2D/3D.create(from, to)`로 `intersect_ray(query)`를 호출한다. 자기 자신을 건너뛰려면 `query.exclude = [get_rid()]`, 레이어 필터링은 `query.collision_mask`를 설정하라. **`_physics_process()` 안에서만 안전하다** — 렌더링 중에는 물리 공간이 잠긴다.
### 레이 결과, 기타 쿼리, 3D 마우스 피킹

`intersect_ray` 결과 딕셔너리는 `position`, `normal`, `collider`, `collider_id`, `rid`, `shape`를 담는다. `PhysicsDirectSpaceState`는 또한 `intersect_point`(한 점에서 겹치는 형태), `intersect_shape`(area 쿼리), `cast_motion`(형태 스윕), `collide_shape`(접촉점), `get_rest_info`(정지 충돌 정보)를 지원한다. 3D 마우스 피킹은 `Camera3D.project_ray_origin(screen_pos)` + `project_ray_normal(screen_pos)`로 레이를 만든다.
---

## 8. Jolt Physics

Jolt은 Godot 4.4부터 제공되는 내장 대체 물리 엔진이다. 4.4부터 **새 3D 프로젝트의 기본**이다. **(Godot 4.6+)** Jolt은 더 이상 실험적으로 표시되지 않으며 모든 새 3D 프로젝트의 확정된 안정 기본값이다.

### Jolt 활성화

**Project Settings → Physics → 3D → Physics Engine** → `Jolt Physics` → 저장 → 에디터 재시작. (3D 전용; 2D는 항상 GodotPhysics.)

### 왜 & 차이점

**장점:** 더 나은 스태킹 안정성, 신뢰할 수 있는 `CylinderShape3D`, 더 나은 `SoftBody3D`, 선택적 스레드 안전 모드, active-edge 감지(유령 충돌 수정).
> ⚠️ **Godot 4.7에서 변경됨:** Jolt Physics에서 `WorldBoundaryShape3D.plane.d`는 이제 Godot Physics와 같은 부호 관례를 따른다 — 평면 거리가 Godot 4.6과 반대 부호로 해석된다. 4.6 동작을 유지하려면 부호를 직접 뒤집어라. [4.7 마이그레이션 가이드](https://docs.godotengine.org/en/latest/tutorials/migrating/upgrading_to_godot_4.7.html)를 보라.

---

## 9. 물리 보간

물리 틱 사이의 시각적 움직임을 부드럽게 해, 틱 레이트 ≠ 프레임 레이트일 때의 "계단" 지터를 없앤다. **Project Settings → Physics → Common → Physics Interpolation**에서 활성화한다. **Godot 4.5+**는 중첩 트랜스폼에서 더 정확한 결과를 위해 3D 보간 파이프라인(`RenderingServer` → `SceneTree`)을 재구성했다 — API 변경 없이 업그레이드 시 자동 개선.

### 핵심 규칙

1. **모든 게임 로직을 `_physics_process()`로 옮겨라** — 물리 틱 밖에서 설정된 트랜스폼은 지터를 일으킨다
2. 물리 객체를 움직이는 **Tween과 AnimationPlayer**는 물리 틱 타이밍을 써야 한다
3. 순간이동이나 최초 배치 후 "번짐(streaking)"을 막으려면 **`reset_physics_interpolation()`을 호출**하라
### 카메라 보간

카메라는 물리 보간 하에서 특별한 처리가 필요하다. 카메라를 독립시키고(또는 `top_level = true`), `_physics_process()`가 아니라 `_process()`에서 갱신하며, 타깃의 부드러운 위치를 `get_global_transform_interpolated()`로 읽어라.
---

## 10. 래그돌 시스템

래그돌은 절차적 죽음, 폭발, 축 늘어진 캐릭터를 위해 애니메이션을 물리로 대체한다. `Skeleton3D` → **Skeleton** 메뉴 → **Create Physical Skeleton**으로 생성한다. 어깨/엉덩이/목엔 `ConeJoint`, 팔꿈치/무릎엔 `HingeJoint`를 써라 — `PinJoint`(기본)는 구겨지기 쉽다. `physical_bones_start_simulation()`으로 구동하고 `Influence`로 블렌드한다.
---

## 11. SoftBody3D

`SoftBody3D`는 변형 가능한 객체(천, 망토, 젤리)를 시뮬레이션한다. 메시 세분화가 시뮬레이션을 구동한다; `CollisionShape` 자식은 필요 없다. **Jolt Physics 권장.** 붕괴를 막으려면 `Simulation Precision ≥ 5`로 설정하라. `Pressure > 0.0`은 닫힌 메시에만.

Godot 4.5+는 `RigidBody3D` 스타일의 힘 적용을 위해 `apply_central_impulse()` / `apply_central_force()`를 추가했다 — 모든 시뮬레이션 점에 분산한다.
> ⚠️ **Godot 4.7에서 변경됨:** Jolt Physics에서 `SoftBody3D` 질량은 더 이상 `0`(점당 1 kg를 자동 계산해 매우 높은 총 질량을 줬다)을 기본으로 하지 않는다 — 이제 전체 바디에 1 kg를 기본으로 하며, Godot Physics와 일치한다. `linear_stiffness`도 다르게 적용되므로, 업그레이드 후 `linear_stiffness`와 `damping_coefficient`를 재조정하라. [4.7 마이그레이션 가이드](https://docs.godotengine.org/en/latest/tutorials/migrating/upgrading_to_godot_4.7.html)를 보라.

---

## 13. 물리 문제 해결

증상 → 원인 & 수정 빠른 표로 터널링, 흔들리는 스택, 스케일된 형태, 타일 충돌 튐, 불안정한 실린더, 물리의 죽음의 나선(spiral of death), 원점에서 먼 곳의 float 정밀도 문제를 다룬다.
---

## 14. 구현 체크리스트

- [ ] 동적 바디는 primitive 충돌 형태를 쓴다; concave 형태는 StaticBody에만
- [ ] 충돌 레이어를 Project Settings에서 명명; 바디별로 layer/mask를 올바르게 설정
- [ ] 충돌 형태나 바디에 `scale` 없음 — 형태 크기 파라미터를 직접 써라
- [ ] RigidBody는 `_physics_process()`가 아니라 `_integrate_forces()`로 상태를 수정
- [ ] 접촉 시그널이 필요한 RigidBody는 `contact_monitor = true` + `max_contacts_reported > 0`을 설정
- [ ] 움직이는 발판은 `AnimatableBody2D/3D`를 쓴다(수동으로 이동한 StaticBody가 아니라)
- [ ] 코드 레이캐스트는 `_physics_process()` 안에서만 `PhysicsDirectSpaceState`를 쓴다
- [ ] 물리 보간 활성화; 순간이동 / 최초 배치 후 `reset_physics_interpolation()` 호출
- [ ] 래그돌 뼈는 캐릭터 캡슐과 별도 충돌 레이어에
- [ ] 3D 프로젝트는 Jolt을 쓴다(Godot 4.6+에서 비실험적 기본)
