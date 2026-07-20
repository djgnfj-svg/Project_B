---
name: player-controller
description: 플레이어 이동을 구현할 때 사용한다 — CharacterBody2D/3D 패턴, 입력 처리, 물리, 그리고 흔한 이동 레시피
---

# Godot 4.3+에서의 플레이어 컨트롤러

모든 예제는 Godot 4.3+를 대상으로 하며 폐기된 API를 쓰지 않는다. GDScript를 먼저 보이고, 그다음 C#을 보인다.

> **관련 스킬:** RigidBody·Area·레이캐스팅·충돌 형태는 **physics-system**, TileMap·패럴랙스·2D 조명은 **2d-essentials**, CharacterBody3D와 3D 이동 설정은 **3d-essentials**, 이동 상태 관리는 **state-machine**, 카메라 추적과 흔들림은 **camera-system**, hitbox/hurtbox 통합은 **component-system**, 이동 상태 기반 애니메이션은 **animation-system**, InputMap 액션과 컨트롤러 지원은 **input-handling**, 적 이동과 길찾기는 **ai-navigation**을 보라.

---

## 1. 핵심 개념

### CharacterBody vs RigidBody

| Body Type         | Use For                        | Physics Control | Notes                                                   |
|-------------------|--------------------------------|-----------------|----------------------------------------------------------|
| `CharacterBody2D/3D` | 플레이어, 적, NPC           | 수동(전체)      | 속도를 직접 제어; `move_and_slide()`가 충돌 처리 |
| `RigidBody2D/3D`  | 투사체, 소품, 파편             | 엔진 구동       | 물리 엔진이 힘을 적용; 정밀 제어가 어려움  |
| `RigidBody2D/3D`  | 튕기는 투사체                  | 엔진 구동       | `linear_velocity`를 한 번 설정; 물리가 튕김을 해결  |
| `CharacterBody2D` | 플랫포머, 탑다운, FPS          | 수동(전체)      | 신뢰할 수 있고 예측 가능; 반응성 좋은 게임감에 최적  |

**경험칙:** 타이트하고 반응성 좋은 제어가 필요하면 `CharacterBody`를 써라. 사실적인 물리 시뮬레이션을 원하면 `RigidBody`를 써라.

### 이동 루프

모든 물리 프레임은 이 순서를 따른다:

```
1. Read input          → get axis/action values
2. Apply forces        → gravity, friction, acceleration
3. Modify velocity     → move_toward, lerp, clamp
4. move_and_slide()    → engine resolves collisions, updates position
5. Post-movement state → check is_on_floor(), is_on_wall(), landing events
```

이 루프는 항상 `_physics_process(delta)`에 두고, 절대 `_process(delta)`에 두지 마라.

---

## 2. 2D 탑다운 컨트롤러

### GDScript

```gdscript
extends CharacterBody2D

@export var speed: float = 200.0
@export var acceleration: float = 1500.0
@export var friction: float = 1200.0

func _physics_process(delta: float) -> void:
    # 1. Read input (normalized 4-directional vector)
    var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

    # 2 & 3. Apply acceleration or friction to velocity
    if input_dir != Vector2.ZERO:
        velocity = velocity.move_toward(input_dir * speed, acceleration * delta)
    else:
        velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

    # 4. Move and resolve collisions
    move_and_slide()
```

### C#

```csharp
using Godot;

public partial class TopDownPlayer : CharacterBody2D
{
    [Export] public float Speed { get; set; } = 200.0f;
    [Export] public float Acceleration { get; set; } = 1500.0f;
    [Export] public float Friction { get; set; } = 1200.0f;

    public override void _PhysicsProcess(double delta)
    {
        // 1. Read input (normalized 4-directional vector)
        Vector2 inputDir = Input.GetVector("ui_left", "ui_right", "ui_up", "ui_down");

        // 2 & 3. Apply acceleration or friction
        if (inputDir != Vector2.Zero)
            Velocity = Velocity.MoveToward(inputDir * Speed, Acceleration * (float)delta);
        else
            Velocity = Velocity.MoveToward(Vector2.Zero, Friction * (float)delta);

        // 4. Move and resolve collisions
        MoveAndSlide();
    }
}
```

---

## 3. 2D 플랫포머 컨트롤러

### GDScript

```gdscript
extends CharacterBody2D

@export var speed: float = 200.0
@export var jump_velocity: float = -400.0
@export var acceleration: float = 1200.0
@export var deceleration: float = 900.0

# Coyote time and jump buffer
@export var coyote_time: float = 0.12
@export var jump_buffer_time: float = 0.12

var _gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _was_on_floor: bool = false

func _physics_process(delta: float) -> void:
    # Coyote time: allow jump briefly after walking off a ledge
    if is_on_floor():
        _coyote_timer = coyote_time
        _was_on_floor = true
    else:
        _coyote_timer -= delta

    # Jump buffer: register jump input before landing
    if Input.is_action_just_pressed("ui_accept"):
        _jump_buffer_timer = jump_buffer_time
    else:
        _jump_buffer_timer -= delta

    # Apply gravity when airborne
    if not is_on_floor():
        velocity.y += _gravity * delta

    # Jump: consume coyote time and buffer together
    var can_jump: bool = _coyote_timer > 0.0
    if _jump_buffer_timer > 0.0 and can_jump:
        velocity.y = jump_velocity
        _coyote_timer = 0.0
        _jump_buffer_timer = 0.0

    # Variable jump height: cut velocity when button released early
    if Input.is_action_just_released("ui_accept") and velocity.y < 0.0:
        velocity.y *= 0.5

    # Horizontal movement with deceleration
    var input_x: float = Input.get_axis("ui_left", "ui_right")
    if input_x != 0.0:
        velocity.x = move_toward(velocity.x, input_x * speed, acceleration * delta)
    else:
        velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)

    move_and_slide()
```

### C#

```csharp
using Godot;

public partial class PlatformerPlayer : CharacterBody2D
{
    [Export] public float Speed { get; set; } = 200.0f;
    [Export] public float JumpVelocity { get; set; } = -400.0f;
    [Export] public float Acceleration { get; set; } = 1200.0f;
    [Export] public float Deceleration { get; set; } = 900.0f;
    [Export] public float CoyoteTime { get; set; } = 0.12f;
    [Export] public float JumpBufferTime { get; set; } = 0.12f;

    private float _gravity = ProjectSettings.GetSetting("physics/2d/default_gravity").AsSingle();
    private float _coyoteTimer;
    private float _jumpBufferTimer;

    public override void _PhysicsProcess(double delta)
    {
        float dt = (float)delta;

        // Coyote time
        if (IsOnFloor())
            _coyoteTimer = CoyoteTime;
        else
            _coyoteTimer -= dt;

        // Jump buffer
        if (Input.IsActionJustPressed("ui_accept"))
            _jumpBufferTimer = JumpBufferTime;
        else
            _jumpBufferTimer -= dt;

        // Gravity
        if (!IsOnFloor())
        {
            Vector2 vel = Velocity;
            vel.Y += _gravity * dt;
            Velocity = vel;
        }

        // Jump
        if (_jumpBufferTimer > 0f && _coyoteTimer > 0f)
        {
            Vector2 vel = Velocity;
            vel.Y = JumpVelocity;
            Velocity = vel;
            _coyoteTimer = 0f;
            _jumpBufferTimer = 0f;
        }

        // Variable jump height
        if (Input.IsActionJustReleased("ui_accept") && Velocity.Y < 0f)
        {
            Vector2 vel = Velocity;
            vel.Y *= 0.5f;
            Velocity = vel;
        }

        // Horizontal movement
        float inputX = Input.GetAxis("ui_left", "ui_right");
        Vector2 velocity = Velocity;
        if (inputX != 0f)
            velocity.X = Mathf.MoveToward(velocity.X, inputX * Speed, Acceleration * dt);
        else
            velocity.X = Mathf.MoveToward(velocity.X, 0f, Deceleration * dt);

        Velocity = velocity;
        MoveAndSlide();
    }
}
```

---

## 4. 3D 1인칭 컨트롤러

### GDScript

```gdscript
extends CharacterBody3D

@export var move_speed: float = 5.0
@export var jump_velocity: float = 5.0
@export var mouse_sensitivity: float = 0.002

@onready var head: Node3D = $Head  # Child Node3D that holds Camera3D

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        # Horizontal look: rotate the body (yaw)
        rotate_y(-event.relative.x * mouse_sensitivity)
        # Vertical look: rotate the head (pitch), clamped to ±90°
        head.rotate_x(-event.relative.y * mouse_sensitivity)
        head.rotation.x = clamp(head.rotation.x, -PI / 2.0, PI / 2.0)

    if event.is_action_pressed("ui_cancel"):
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _physics_process(delta: float) -> void:
    # Gravity
    if not is_on_floor():
        velocity.y -= _gravity * delta

    # Jump
    if Input.is_action_just_pressed("ui_accept") and is_on_floor():
        velocity.y = jump_velocity

    # Movement relative to the direction the player is facing
    var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
    var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

    if direction != Vector3.ZERO:
        velocity.x = direction.x * move_speed
        velocity.z = direction.z * move_speed
    else:
        velocity.x = move_toward(velocity.x, 0.0, move_speed)
        velocity.z = move_toward(velocity.z, 0.0, move_speed)

    move_and_slide()
```

### C#

```csharp
using Godot;

public partial class FPSController : CharacterBody3D
{
    [Export] public float MoveSpeed { get; set; } = 5.0f;
    [Export] public float JumpVelocity { get; set; } = 5.0f;
    [Export] public float MouseSensitivity { get; set; } = 0.002f;

    private float _gravity = ProjectSettings.GetSetting("physics/3d/default_gravity").AsSingle();
    private Node3D _head;

    public override void _Ready()
    {
        _head = GetNode<Node3D>("Head");
        Input.MouseMode = Input.MouseModeEnum.Captured;
    }

    public override void _UnhandledInput(InputEvent @event)
    {
        if (@event is InputEventMouseMotion motion
            && Input.MouseMode == Input.MouseModeEnum.Captured)
        {
            // Horizontal look (yaw on body)
            RotateY(-motion.Relative.X * MouseSensitivity);
            // Vertical look (pitch on head), clamped to ±90°
            _head.RotateX(-motion.Relative.Y * MouseSensitivity);
            Vector3 rot = _head.Rotation;
            rot.X = Mathf.Clamp(rot.X, -Mathf.Pi / 2f, Mathf.Pi / 2f);
            _head.Rotation = rot;
        }

        if (@event.IsActionPressed("ui_cancel"))
            Input.MouseMode = Input.MouseModeEnum.Visible;
    }

    public override void _PhysicsProcess(double delta)
    {
        float dt = (float)delta;
        Vector3 vel = Velocity;

        // Gravity
        if (!IsOnFloor())
            vel.Y -= _gravity * dt;

        // Jump
        if (Input.IsActionJustPressed("ui_accept") && IsOnFloor())
            vel.Y = JumpVelocity;

        // Movement relative to facing direction
        Vector2 inputDir = Input.GetVector("ui_left", "ui_right", "ui_up", "ui_down");
        Vector3 direction = (Transform.Basis * new Vector3(inputDir.X, 0, inputDir.Y)).Normalized();

        if (direction != Vector3.Zero)
        {
            vel.X = direction.X * MoveSpeed;
            vel.Z = direction.Z * MoveSpeed;
        }
        else
        {
            vel.X = Mathf.MoveToward(vel.X, 0f, MoveSpeed);
            vel.Z = Mathf.MoveToward(vel.Z, 0f, MoveSpeed);
        }

        Velocity = vel;
        MoveAndSlide();
    }
}
```

---

## 5. 흔한 이동 레시피

위의 기본 이동 패턴을 넘어, 두 레시피는 워낙 자주 등장해 별도 블록을 받을 만하다: **대시(Dash)**(짧은 버스트를 위한 타이머 기반 속도 오버라이드)와 **월 점프(Wall Jump)**(수직 벽 미끄러짐 + 점프를 누르면 `GetWallNormal()`에서 튕김). 둘 다 `CharacterBody2D`에 적용되며 중력·수평 이동과 나란히 표준 `_physics_process` 루프에 들어간다.
---

## 6. 흔한 함정

| Symptom                        | Cause                                        | Fix                                                              |
|-------------------------------|----------------------------------------------|------------------------------------------------------------------|
| 플레이어가 벽에 붙음          | 기본 벽 차단 동작                            | CharacterBody에 `floor_block_on_wall = false`를 설정             |
| 지터 또는 프레임 레이트 의존 이동 | `_process`에서 이동                       | 모든 물리/속도 코드를 `_physics_process(delta)`로 옮겨라        |
| 일관되지 않은 점프 높이       | 고정 속도가 프레임 타이밍을 무시             | 가변 점프를 써라(버튼 릴리스 시 `velocity.y`를 잘라라)          |
| 플레이어가 경사면을 미끄러짐  | 스냅이나 각도 제한 없음                      | `floor_snap_length` > 0을 설정하고 `floor_max_angle`을 튜닝하라 |
| 마우스 시점이 반전됨          | 회전 델타의 부호가 잘못됨                    | yaw는 `event.relative.x`, pitch는 `event.relative.y`를 음수화하라 |

---

## 7. 구현 체크리스트

- [ ] 모든 이동 로직이 `_process`가 아니라 `_physics_process(delta)` 안에 있다
- [ ] 입력 액션 이름이 **Project > Project Settings > Input Map**에 정의된 것과 정확히 일치한다
- [ ] 중력 값을 하드코딩하지 않고 `ProjectSettings`(`physics/2d/default_gravity` 또는 `physics/3d/default_gravity`)에서 읽는다
- [ ] 매 프레임 모든 속도 수정 후에 `move_and_slide()`를 호출한다
- [ ] 플랫포머는 반응성 좋은 느낌을 위해 코요테 타임과 점프 버퍼링을 구현한다
- [ ] FPS 컨트롤러는 `_ready()`에서 마우스를 캡처하고 escape에서 해제한다
- [ ] 가변 점프 높이가 조기 릴리스 속도 감소로 처리된다
