---
name: camera-system
description: 카메라를 구현할 때 쓴다 — 2D·3D의 부드러운 추적, 화면 흔들림, 카메라 존, 전환
---

# Godot 4.3+ 카메라 시스템

모든 예제는 Godot 4.3+를 대상으로 하며 폐기된 API를 쓰지 않는다. GDScript를 먼저 보이고, 이어서 C#을 보인다.

> **관련 스킬:** 1인칭 카메라 설정은 **player-controller**, 카메라 상태 전환은 **state-machine**, 카메라 컬링과 성능은 **godot-optimization**, 물리 보간과 카메라 스무딩은 **physics-system**, 캔버스 레이어·패럴랙스 스크롤·좌표 변환은 **2d-essentials**, smoothstep과 lerp 기반 보간은 **math-essentials**, 카메라 흔들림과 시네마틱 전환은 **tween-animation**.

---

## 1. Camera2D 기초

### 주요 속성

| 속성 | 타입 | 설명 |
|---|---|---|
| `position_smoothing_enabled` | `bool` | 내장 위치 스무딩 활성화(타깃 쪽으로 lerp) |
| `position_smoothing_speed` | `float` | 내장 스무딩 속도(기본 `5.0`) |
| `drag_horizontal_enabled` | `bool` | 수평 드래그 존 활성화; 타깃이 존을 벗어날 때만 카메라 이동 |
| `drag_vertical_enabled` | `bool` | 수직 드래그 존 활성화 |
| `limit_left` | `int` | 왼쪽 픽셀 경계 — 카메라가 이보다 더 스크롤하지 않음 |
| `limit_right` | `int` | 오른쪽 픽셀 경계 |
| `limit_top` | `int` | 위쪽 픽셀 경계 |
| `limit_bottom` | `int` | 아래쪽 픽셀 경계 |
| `zoom` | `Vector2` | 줌 레벨; `Vector2(2, 2)` = 2× 확대, `Vector2(0.5, 0.5)` = 축소 |

카메라가 월드 바깥을 절대 보이지 않도록 타일맵이나 레벨 경계에 맞춰 limit를 설정하라. limit는 타일이 아니라 월드 픽셀 단위다.

---

## 2. 부드러운 추적

수동 추적 카메라는 내장 스무딩보다 더 많은 제어를 준다 — look-ahead, 오프셋, 커스텀 이징을 추가할 수 있다.

### GDScript

```gdscript
extends Camera2D

## Target node to follow (assign in Inspector or via code)
@export var target: Node2D

## How quickly the camera catches up to the target (higher = snappier)
@export var follow_speed: float = 8.0

## How far ahead the camera leads in the movement direction
@export var look_ahead_distance: float = 80.0

## How quickly the look-ahead offset responds to direction changes
@export var look_ahead_speed: float = 4.0

var _look_ahead_offset: Vector2 = Vector2.ZERO
var _previous_target_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
    # Disable built-in smoothing — we handle it manually
    position_smoothing_enabled = false
    if target:
        _previous_target_pos = target.global_position
        global_position = target.global_position

func _process(delta: float) -> void:
    if not target:
        return

    # Compute movement direction from last frame
    var move_delta: Vector2 = target.global_position - _previous_target_pos
    _previous_target_pos = target.global_position

    # Smoothly steer look-ahead offset toward movement direction
    var desired_ahead: Vector2 = move_delta.normalized() * look_ahead_distance if move_delta.length() > 0.5 else Vector2.ZERO
    _look_ahead_offset = _look_ahead_offset.lerp(desired_ahead, look_ahead_speed * delta)

    # Lerp camera position toward target + look-ahead
    var desired_pos: Vector2 = target.global_position + _look_ahead_offset
    global_position = global_position.lerp(desired_pos, follow_speed * delta)
```

### C#

```csharp
using Godot;

public partial class SmoothFollowCamera : Camera2D
{
    [Export] public Node2D Target { get; set; }
    [Export] public float FollowSpeed { get; set; } = 8.0f;
    [Export] public float LookAheadDistance { get; set; } = 80.0f;
    [Export] public float LookAheadSpeed { get; set; } = 4.0f;

    private Vector2 _lookAheadOffset = Vector2.Zero;
    private Vector2 _previousTargetPos = Vector2.Zero;

    public override void _Ready()
    {
        PositionSmoothingEnabled = false;
        if (Target != null)
        {
            _previousTargetPos = Target.GlobalPosition;
            GlobalPosition = Target.GlobalPosition;
        }
    }

    public override void _Process(double delta)
    {
        if (Target == null)
            return;

        float dt = (float)delta;

        Vector2 moveDelta = Target.GlobalPosition - _previousTargetPos;
        _previousTargetPos = Target.GlobalPosition;

        Vector2 desiredAhead = moveDelta.Length() > 0.5f
            ? moveDelta.Normalized() * LookAheadDistance
            : Vector2.Zero;

        _lookAheadOffset = _lookAheadOffset.Lerp(desiredAhead, LookAheadSpeed * dt);

        Vector2 desiredPos = Target.GlobalPosition + _lookAheadOffset;
        GlobalPosition = GlobalPosition.Lerp(desiredPos, FollowSpeed * dt);
    }
}
```

---

## 3. 화면 흔들림

trauma 기반 시스템은 단순 사인파보다 더 자연스러운 흔들림을 만든다. 높은 trauma = 격렬한 흔들림; trauma는 시간에 따라 감쇠하고; 오프셋은 `trauma^2`로 스케일되어 작은 trauma 값은 미묘하게 느껴진다.

### GDScript

```gdscript
extends Camera2D

## Maximum pixel offset during maximum trauma
@export var max_offset: Vector2 = Vector2(20.0, 15.0)

## Maximum rotation offset in degrees during maximum trauma
@export var max_roll: float = 3.0

## Rate at which trauma decays per second (0–1 range)
@export var decay_rate: float = 1.5

var _trauma: float = 0.0  # 0.0 = no shake, 1.0 = maximum shake

# Optional: use noise for smooth, organic shake
var _noise: FastNoiseLite
var _noise_time: float = 0.0
@export var use_noise: bool = true
@export var noise_speed: float = 60.0

func _ready() -> void:
    _noise = FastNoiseLite.new()
    _noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
    _noise.seed = randi()

## Call this from any node to trigger a shake (amount in 0–1 range; can stack)
func add_trauma(amount: float) -> void:
    _trauma = minf(_trauma + amount, 1.0)

func _process(delta: float) -> void:
    if _trauma <= 0.0:
        offset = Vector2.ZERO
        rotation = 0.0
        return

    # Decay trauma over time
    _trauma = maxf(_trauma - decay_rate * delta, 0.0)
    _noise_time += delta * noise_speed

    var shake: float = _trauma * _trauma  # squaring gives subtle feel at low trauma

    if use_noise:
        offset.x = max_offset.x * shake * _noise.get_noise_2d(_noise_time, 0.0)
        offset.y = max_offset.y * shake * _noise.get_noise_2d(0.0, _noise_time)
        rotation = deg_to_rad(max_roll) * shake * _noise.get_noise_2d(_noise_time, _noise_time)
    else:
        offset.x = max_offset.x * shake * randf_range(-1.0, 1.0)
        offset.y = max_offset.y * shake * randf_range(-1.0, 1.0)
        rotation = deg_to_rad(max_roll) * shake * randf_range(-1.0, 1.0)
```

**다른 노드에서 흔들림 트리거:**

```gdscript
# Any node that can reach the camera
func on_explosion() -> void:
    var cam := get_viewport().get_camera_2d() as ScreenShakeCamera
    if cam:
        cam.add_trauma(0.6)
```

### C#

```csharp
using Godot;

public partial class ScreenShakeCamera : Camera2D
{
    [Export] public Vector2 MaxOffset { get; set; } = new Vector2(20f, 15f);
    [Export] public float MaxRoll { get; set; } = 3.0f;
    [Export] public float DecayRate { get; set; } = 1.5f;
    [Export] public bool UseNoise { get; set; } = true;
    [Export] public float NoiseSpeed { get; set; } = 60.0f;

    private float _trauma = 0f;
    private float _noiseTime = 0f;
    private FastNoiseLite _noise;

    public override void _Ready()
    {
        _noise = new FastNoiseLite();
        _noise.NoiseType = FastNoiseLite.NoiseTypeEnum.Simplex;
        _noise.Seed = (int)GD.Randi();
    }

    public void AddTrauma(float amount)
    {
        _trauma = Mathf.Min(_trauma + amount, 1.0f);
    }

    public override void _Process(double delta)
    {
        if (_trauma <= 0f)
        {
            Offset = Vector2.Zero;
            Rotation = 0f;
            return;
        }

        float dt = (float)delta;
        _trauma = Mathf.Max(_trauma - DecayRate * dt, 0f);
        _noiseTime += dt * NoiseSpeed;

        float shake = _trauma * _trauma;

        if (UseNoise)
        {
            Offset = new Vector2(
                MaxOffset.X * shake * _noise.GetNoise2D(_noiseTime, 0f),
                MaxOffset.Y * shake * _noise.GetNoise2D(0f, _noiseTime)
            );
            Rotation = Mathf.DegToRad(MaxRoll) * shake * _noise.GetNoise2D(_noiseTime, _noiseTime);
        }
        else
        {
            Offset = new Vector2(
                MaxOffset.X * shake * (float)GD.RandRange(-1.0, 1.0),
                MaxOffset.Y * shake * (float)GD.RandRange(-1.0, 1.0)
            );
            Rotation = Mathf.DegToRad(MaxRoll) * shake * (float)GD.RandRange(-1.0, 1.0);
        }
    }
}
```

---

## 4. 카메라 존 / 방

방 기반 게임(메트로배니아, 탑다운 던전)의 경우: 방마다 `Area2D`를 두고, `body_entered` 시 활성 `Camera2D`의 `limit_left` / `limit_right` / `limit_top` / `limit_bottom`을 방 경계로 tween하는 스크립트를 붙인다. 플레이어가 방 경계를 넘을 때 부드럽게 전환된다.

---

## 5. Camera3D 패턴

세 가지 정석 3D 카메라 설정: `SpringArm3D`를 쓴 **3인칭 추적**(벽 충돌 처리), 마우스 드래그 회전의 **오빗 카메라**, 카메라에서 마우스룩하는 **1인칭**.

---

## 6. 카메라 전환

`Tween` + `await ToSignal`을 통한 비동기 카메라 전환. 패턴은 이렇다: 다음 카메라의 position/zoom을 현재 카메라의 것에서 tween한 뒤, 다음 카메라에서 `make_current()`를 호출한다. 2D와 3D 모두에서 동작한다.

---

## 7. 분할 화면 (로컬 멀티플레이어)

여러 카메라를 별도의 `SubViewport`에 렌더한 뒤, `SubViewportContainer`를 레이아웃(`HBoxContainer`, `VBoxContainer`, `GridContainer`)에 배치한다. 각 플레이어의 카메라는 자기 뷰포트의 `current`로 설정한다.

---

## 8. 구현 체크리스트

- [ ] `Camera2D` limit가 레벨/타일맵 경계와 일치해 월드 밖 가장자리가 보이지 않음
- [ ] 부드러운 추적은 `_physics_process`가 아니라 `_process`(시각 보간)를 사용
- [ ] 화면 흔들림이 `_trauma`가 `0.0`에 도달할 때 `offset`과 `rotation`을 0으로 리셋
- [ ] `add_trauma()`가 `1.0`으로 클램프됨; 최대 흔들림을 넘지 않음
- [ ] 카메라 존 `Area2D` 충돌 레이어를 설정해 플레이어만 트리거함
- [ ] `SpringArm3D` 충돌 마스크가 벽 회피를 위해 모든 환경 레이어를 포함함
- [ ] 카메라 전환이 `make_current()` 호출 전 tween 완료를 await함
- [ ] 분할 화면 `SubViewport` 크기가 창 리사이즈 시 갱신됨(`get_tree().root.size_changed` 시그널)
- [ ] `audio_listener_enable_2d` 또는 `audio_listener_enable_3d`가 `true`인 `SubViewport`는 오직 하나
