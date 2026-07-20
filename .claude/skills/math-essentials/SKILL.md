---
name: math-essentials
description: 게임 수학을 구현할 때 사용한다 — 벡터, 트랜스폼, 보간, 커브, 난수 생성, 그리고 흔한 기하 레시피
---

# Godot 4.3+에서의 게임 수학

모든 예제는 Godot 4.3+를 대상으로 하며 폐기된 API를 쓰지 않는다. GDScript를 먼저 보이고, 그다음 C#을 보인다.

> **관련 스킬:** 이동 물리는 **player-controller**, 길찾기 수학은 **ai-navigation**, 카메라 보간은 **camera-system**, 이징 커브는 **tween-animation**, 충돌 수학은 **physics-system**을 참고하라.

---

## 1. 벡터 연산

### 필수 벡터 메서드

| Method                  | Returns   | Description                                   |
|-------------------------|-----------|-----------------------------------------------|
| `length()`              | `float`   | 벡터의 크기                                    |
| `length_squared()`      | `float`   | 크기의 제곱 (더 빠름, sqrt 생략)               |
| `normalized()`          | `Vector`  | 같은 방향의 단위 벡터(길이 1)                  |
| `distance_to(b)`        | `float`   | 두 점 사이의 거리                              |
| `distance_squared_to(b)` | `float` | 거리의 제곱 (비교 시 더 빠름)                  |
| `direction_to(b)`       | `Vector`  | 이 점에서 b로 향하는 정규화된 방향             |
| `angle_to(b)`           | `float`   | 두 벡터 사이의 각도(라디안)                    |
| `angle_to_point(b)`     | `float`   | 이 점에서 b로 향하는 각도 (2D)                 |
| `dot(b)`                | `float`   | 내적                                           |
| `cross(b)`              | `float/Vector3` | 외적 (2D는 float, 3D는 벡터 반환)         |
| `rotated(angle)`        | `Vector2` | 라디안만큼 회전 (2D)                           |
| `move_toward(to, delta)` | `Vector` | 최대 delta만큼 목표를 향해 이동                |
| `clamp(min, max)`       | `Vector`  | 각 성분을 클램프                               |
| `snapped(step)`         | `Vector`  | 격자에 스냅                                    |
| `reflect(normal)`       | `Vector`  | 표면에서 반사                                  |
| `bounce(normal)`        | `Vector`  | 표면에서 튕김 (반사의 반전)                    |
| `slide(normal)`         | `Vector`  | 표면을 따라 미끄러짐                           |

### 방향과 거리

```gdscript
# Get direction from A to B (normalized)
var dir: Vector2 = global_position.direction_to(target.global_position)

# Get distance
var dist: float = global_position.distance_to(target.global_position)

# Use squared distance for comparisons (faster — avoids sqrt)
if global_position.distance_squared_to(target.global_position) < detection_range * detection_range:
    chase_target()
```

```csharp
Vector2 dir = GlobalPosition.DirectionTo(target.GlobalPosition);
float dist = GlobalPosition.DistanceTo(target.GlobalPosition);

if (GlobalPosition.DistanceSquaredTo(target.GlobalPosition) < detectionRange * detectionRange)
    ChaseTarget();
```

### 내적(Dot Product)

내적은 두 벡터가 얼마나 정렬되어 있는지를 알려 준다.

```gdscript
# Is the target in front of us? (dot > 0 = in front, < 0 = behind)
var forward: Vector2 = Vector2.RIGHT.rotated(rotation)
var to_target: Vector2 = global_position.direction_to(target.global_position)
var dot: float = forward.dot(to_target)

if dot > 0.7:  # roughly within ~45° cone
    print("Target is ahead")
elif dot < -0.7:
    print("Target is behind")
```

```csharp
Vector2 forward = Vector2.Right.Rotated(Rotation);
Vector2 toTarget = GlobalPosition.DirectionTo(target.GlobalPosition);
float dot = forward.Dot(toTarget);

if (dot > 0.7f) GD.Print("Target is ahead");
```

### 외적(Cross Product, 3D)

외적은 두 입력 벡터에 수직인 벡터를 준다.

```gdscript
# Get the surface normal from two edge vectors
var edge1: Vector3 = vertex_b - vertex_a
var edge2: Vector3 = vertex_c - vertex_a
var normal: Vector3 = edge1.cross(edge2).normalized()
```

```csharp
Vector3 edge1 = vertexB - vertexA;
Vector3 edge2 = vertexC - vertexA;
Vector3 normal = edge1.Cross(edge2).Normalized();
```

---

## 2. 트랜스폼(Transforms)

### Transform2D

2D 트랜스폼은 위치·회전·스케일을 담는다.

```gdscript
# Get the global transform
var xform: Transform2D = global_transform

# Convert between local and global space
var local_point: Vector2 = to_local(global_point)
var world_point: Vector2 = to_global(local_point)

# Apply transform to a point
var transformed: Vector2 = xform * Vector2(10, 0)  # point in local space → global

# Inverse transform
var local: Vector2 = xform.affine_inverse() * global_point
```

```csharp
Transform2D xform = GlobalTransform;
Vector2 localPoint = ToLocal(globalPoint);
Vector2 worldPoint = ToGlobal(localPoint);
Vector2 transformed = xform * new Vector2(10, 0);
Vector2 local = xform.AffineInverse() * globalPoint;
```

### Transform3D & Basis

```gdscript
# Basis holds rotation and scale as 3 column vectors
var basis: Basis = global_transform.basis

# Forward direction (looking along -Z in Godot)
var forward: Vector3 = -basis.z
var right: Vector3 = basis.x
var up: Vector3 = basis.y

# Look at a target
look_at(target.global_position, Vector3.UP)

# Rotate around an axis
rotate_y(deg_to_rad(90.0))
rotate_object_local(Vector3.UP, deg_to_rad(45.0))

# Interpolate between two transforms (smooth transition)
var a: Transform3D = $Start.global_transform
var b: Transform3D = $End.global_transform
global_transform = a.interpolate_with(b, 0.5)  # halfway
```

```csharp
Basis basis = GlobalTransform.Basis;
Vector3 forward = -basis.Z;
Vector3 right = basis.X;
Vector3 up = basis.Y;

LookAt(target.GlobalPosition, Vector3.Up);
RotateY(Mathf.DegToRad(90.0f));

Transform3D a = GetNode<Node3D>("Start").GlobalTransform;
Transform3D b = GetNode<Node3D>("End").GlobalTransform;
GlobalTransform = a.InterpolateWith(b, 0.5f);
```

### is_orthonormal() (Godot 4.7+)

`Basis.is_orthonormal()` (const)는 basis가 *직교*(축들이 서로 수직)이고 **동시에** *정규화*(모든 축의 길이가 `1.0`)되어 있으면 `true`를 반환한다 — 특히 물리 계산 중에 유용하다. `orthonormalized()`를 보완한다: 먼저 검사하고, 누적된 부동소수점 드리프트로 basis가 비정규화됐을 때만 다시 정규직교화하라.

```gdscript
if not global_transform.basis.is_orthonormal():
    global_transform.basis = global_transform.basis.orthonormalized()
```

```csharp
if (!GlobalTransform.Basis.IsOrthonormal())
{
    GlobalTransform = new Transform3D(
        GlobalTransform.Basis.Orthonormalized(), GlobalPosition);
}
```

---

## 3. 보간(Interpolation)

### lerp — 선형 보간

```gdscript
# Interpolate between two values (t = 0.0 to 1.0)
var mid: float = lerp(0.0, 100.0, 0.5)   # 50.0
var pos: Vector2 = lerp(start_pos, end_pos, 0.75)  # 75% of the way

# Smooth following — lerp with delta for frame-rate independence
func _process(delta: float) -> void:
    position = position.lerp(target_position, 5.0 * delta)
```

```csharp
float mid = Mathf.Lerp(0.0f, 100.0f, 0.5f);
Vector2 pos = startPos.Lerp(endPos, 0.75f);

public override void _Process(double delta)
{
    Position = Position.Lerp(targetPosition, 5.0f * (float)delta);
}
```

> **경고:** `lerp(a, b, speed * delta)`는 프레임 레이트에 의존하며 목표에 완전히 도달하지 못한다. 정밀한 이동에는 `move_toward()`를 대신 써라.

### move_toward — 고정 속도 접근

```gdscript
# Move exactly `speed * delta` units toward target each frame
position.x = move_toward(position.x, target_x, speed * delta)

# Vector version
position = position.move_toward(target_position, speed * delta)
```

```csharp
float newX = Mathf.MoveToward(Position.X, targetX, speed * (float)delta);
Position = Position.MoveToward(targetPosition, speed * (float)delta);
```

### slerp — 구면 보간

부드러운 회전 보간용(직선이 아니라 호를 보존한다).

```gdscript
# Quaternion slerp for smooth 3D rotation
var current_quat: Quaternion = global_transform.basis.get_rotation_quaternion()
var target_quat: Quaternion = target_transform.basis.get_rotation_quaternion()
var result: Quaternion = current_quat.slerp(target_quat, 5.0 * delta)
global_transform.basis = Basis(result)
```

```csharp
Quaternion currentQuat = GlobalTransform.Basis.GetRotationQuaternion();
Quaternion targetQuat = targetTransform.Basis.GetRotationQuaternion();
Quaternion result = currentQuat.Slerp(targetQuat, 5.0f * (float)delta);
GlobalTransform = new Transform3D(new Basis(result), GlobalPosition);
```

### smoothstep — S-커브 이징

```gdscript
# Returns 0.0 when x <= from, 1.0 when x >= to, smooth curve between
var t: float = smoothstep(0.0, 10.0, distance)  # 0→1 as distance goes 0→10

# Useful for soft thresholds (fog density, volume falloff)
var fog_intensity: float = smoothstep(50.0, 100.0, camera_distance)
```

### cubic_interpolate — 부드러운 경로 추적

```gdscript
# Smooth interpolation using 4 control points (catmull-rom style)
var point: Vector2 = p1.cubic_interpolate(p2, p0, p3, t)
# p0 = before start, p1 = start, p2 = end, p3 = after end
```

### 보간 비교

| Function           | Speed          | Reaches Target | Smooth | Use For                    |
|--------------------|----------------|----------------|--------|----------------------------|
| `lerp(a, b, t)`   | 가변           | t=1일 때만     | 예     | UI 전환, 블렌딩            |
| `move_toward()`    | 일정           | 예             | 아니오 | 이동, 타이머               |
| `slerp()`          | 가변           | t=1일 때만     | 예     | 회전 블렌딩                |
| `smoothstep()`     | S-커브         | 부드러운 임계  | 예     | 안개, 볼륨, 임계값         |
| `cubic_interpolate()` | 가변        | t=1일 때만     | 매우   | 경로, 카메라 레일          |

---

## 4. 커브와 경로

값-시간 변화용 `Curve` 리소스(예: 피해 감쇠 커브). 공간 경로용 `Path2D` / `Path3D`는 `PathFollow2D` / `PathFollow3D`로 샘플링한다 — 움직이는 발판, 미사일 유도, 카메라 레일에 쓴다.

---

## 5. 난수 생성

일회성 난수는 전역 함수(`randf()`, `randi() % N`, `randf_range(a, b)`). 시드 기반의 재현 가능한 난수(절차적 생성, 리플레이, 세이브 상태)는 `RandomNumberGenerator`. 가중 선택은 누적합 또는 별칭(alias) 방법으로.

---

## 6. 흔한 게임 수학 레시피

다섯 가지 레시피: **목표 바라보기**(2D `Vector2.angle_to_point`), **한 점 주위 공전**(극좌표), **사인파 위아래 흔들림**(떠 있는 UI 요소, 보물), **각도 래핑**(-PI..PI 정규화), **데드존이 있는 클램프된 접근**(아날로그 입력 + 작은 입력 무시).

---

## 7. 흔한 함정

| Symptom                              | Cause                                       | Fix                                                              |
|--------------------------------------|----------------------------------------------|------------------------------------------------------------------|
| `lerp`가 목표에 도달하지 못함        | 매 프레임 `lerp(a, b, speed * delta)` 사용   | 정확한 도달에는 `move_toward()`를 써라                          |
| 180°에서 회전이 튐                   | `lerp_angle` 대신 `lerp` 사용                | 각도 보간에는 항상 `lerp_angle()`을 써라                        |
| 물체가 엉뚱한 방향을 봄 (3D)         | Godot이 -Z를 전방으로 쓴다는 걸 잊음         | 전방은 `-global_transform.basis.z`다                            |
| 거리 검사가 너무 느림                | 많은 물체에 `distance_to` 호출               | `distance_squared_to`를 쓰고 `range * range`와 비교하라         |
| 영벡터 정규화가 크래시               | `Vector2.ZERO`에 `normalized()` 호출         | 먼저 `length() > 0`을 검사하거나 `direction_to()`를 써라        |
| 트랜스폼 보간이 이상해 보임          | 쿼터니언 대신 오일러 각을 lerp함             | `Quaternion.slerp()` 또는 `Transform3D.interpolate_with()`를 써라 |
| 재시작 후 난수 결과가 반복됨         | `RandomNumberGenerator`에 고정 시드 사용     | Godot 4.x는 전역 RNG를 자동 시드한다; `RandomNumberGenerator`는 `randomize()`를 쓰거나 `seed`를 설정하라 |
| 노이즈 값이 전부 ~0                  | `frequency`가 너무 낮음                      | `FastNoiseLite.frequency`를 높여라 (0.01–0.1 시도)              |

---

## 8. 구현 체크리스트

- [ ] 거리 비교는 성능을 위해 `distance_squared_to()`를 쓴다
- [ ] 각도 보간은 `lerp()`가 아니라 `lerp_angle()`을 쓴다
- [ ] 3D 전방은 `+z`가 아니라 `-transform.basis.z`다
- [ ] 목표에 정확히 도달해야 할 때 `move_toward()`를 쓴다
- [ ] `lerp(a, b, speed * delta)`는 정확한 이동이 아니라 프레임 레이트에 의존하는 부드러운 추적으로 이해한다
- [ ] 결정론적/시드 기반 난수(절차적 생성, 리플레이)에는 `RandomNumberGenerator`를 쓴다
- [ ] 노이즈 기반 생성은 적절한 frequency와 seed로 `FastNoiseLite`를 쓴다
- [ ] 전리품 테이블과 확률 기반 시스템에는 가중 난수 선택을 쓴다
- [ ] 경로 추적은 `PathFollow2D/3D`의 `progress` 또는 `progress_ratio`를 쓴다
- [ ] 3D 회전 보간은 오일러 각 대신 쿼터니언 slerp를 쓴다
