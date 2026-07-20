---
name: input-handling
description: 입력을 구현할 때 사용 — InputEvent 시스템, Input Map 액션, 컨트롤러/게임패드, 마우스/터치, 액션 리바인딩, 입력 아키텍처
---

# Godot 4.3+의 입력 처리

모든 예제는 폐기된 API 없이 Godot 4.3+를 대상으로 한다. GDScript를 먼저, 그다음 C#을 보여준다.

> **관련 스킬:** 입력으로 구동되는 이동은 **player-controller**, UI 입력 포커스와 내비게이션은 **godot-ui**, 커스텀 키 바인딩 영속화는 **save-load**, 터치 vs 데스크톱 입력 적응은 **responsive-ui**, XR 컨트롤러·핸드 트래킹 입력은 **xr-development**, 모바일 센서·앱 생명주기는 **mobile-development**를 보라.

---

## 1. 핵심 개념

### 입력 흐름

```
Hardware Event (key, mouse, gamepad)
    ↓
Engine converts to InputEvent
    ↓
_input()              ← raw input, runs first
    ↓
_shortcut_input()     ← for global shortcuts
    ↓
UI Control nodes      ← buttons, sliders consume events
    ↓
_unhandled_key_input() ← unhandled key-only events
    ↓
_unhandled_input()    ← game input (movement, actions)
```

### 입력을 어디서 처리할까

| 메서드                    | 무엇에 쓰나                                | 언제 실행되나     |
|---------------------------|--------------------------------------------|------------------|
| `_input()`                | 카메라 룩, 전역 핫키                        | 가장 먼저 — 모든 것 이전 |
| `_shortcut_input()`       | 전역 단축키(일시정지, 스크린샷)            | `_input` 이후, UI 이전 |
| `_unhandled_key_input()`  | UI가 소비하지 않은 키 전용 이벤트          | UI 이후, 키만 |
| `_unhandled_input()`      | 게임플레이 액션(점프, 공격, 상호작용)      | 가장 마지막 — UI가 소비한 뒤 |
| `_physics_process()`의 `Input.is_action_pressed()` | 연속 이동 | 해당 없음 — 이벤트가 아닌 폴링 |

**어림잡는 규칙:** 개별 게임 액션(점프, 공격)에는 `_unhandled_input()`을 써라. 연속 이동에는 `_physics_process()`에서 `Input` 폴링을 써라. UI가 소비하기 전에 입력이 필요할 때(예: 마우스 룩)만 `_input()`을 써라.

### InputEvent 계층

```
InputEvent
├── InputEventKey              ← keyboard
├── InputEventMouseButton      ← mouse clicks
├── InputEventMouseMotion      ← mouse movement
├── InputEventJoypadButton     ← gamepad buttons
├── InputEventJoypadMotion     ← gamepad sticks/triggers
├── InputEventScreenTouch      ← touchscreen tap
├── InputEventScreenDrag       ← touchscreen drag
├── InputEventAction           ← synthetic action events
├── InputEventMIDI             ← MIDI devices
└── InputEventGesture          ← pinch, pan gestures
    ├── InputEventMagnifyGesture
    └── InputEventPanGesture
```

---

## 2. Input Map 설정

원시 키코드를 확인하는 대신 **Project > Project Settings > Input Map**에서 액션을 정의하라. 이는 게임 로직을 특정 키에서 분리하고 리바인딩을 가능하게 한다.

### 기본 프로젝트 액션

Godot는 `ui_*` 액션을 제공한다: `ui_accept`, `ui_cancel`, `ui_left`, `ui_right`, `ui_up`, `ui_down` 등. 이들은 UI 컨트롤의 키보드 내비게이션에 쓰인다. 게임플레이에 써도 되지만 충돌을 피하려면 커스텀 액션을 만드는 편이 낫다.

### 코드로 액션 추가하기

액션은 런타임에 `InputMap.add_action()` + `InputMap.action_add_event()`로 생성할 수 있다 — 보통 오토로드 `_ready()`에서 `InputMap.has_action()`으로 가드한다. 액션은 에디터 Input Map에서 정의하라. 동적으로 생성되는 바인딩이나 모드 지원에만 코드로 추가하라.

### 권장 액션 이름

키 이름 대신 서술적이고 게임 특화된 이름을 써라:

| 좋음                | 나쁨             | 이유                                  |
|---------------------|------------------|--------------------------------------|
| `move_left`         | `press_a`        | 물리적 키에서 분리됨                  |
| `attack`            | `left_click`     | 마우스와 게임패드 둘 다 동작          |
| `interact`          | `press_e`        | 로직 변경 없이 리바인딩 가능          |
| `sprint`            | `hold_shift`     | 입력 무관                             |
| `pause`             | `press_escape`   | 게임패드 Start 버튼에도 매핑 가능      |

---

## 3. 입력 읽기 — 이벤트 vs 폴링

### 이벤트 주도 (개별 액션)

일회성 액션(점프, 공격, 상호작용, 일시정지)에는 `_unhandled_input()`을 써라.

#### GDScript

```gdscript
func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("jump"):
        _jump()
        get_viewport().set_input_as_handled()  # prevent further propagation

    if event.is_action_pressed("interact"):
        _interact()

    if event.is_action_pressed("pause"):
        get_tree().paused = not get_tree().paused
        get_viewport().set_input_as_handled()
```

#### C#

```csharp
public override void _UnhandledInput(InputEvent @event)
{
    if (@event.IsActionPressed("jump"))
    {
        Jump();
        GetViewport().SetInputAsHandled();
    }

    if (@event.IsActionPressed("interact"))
        Interact();

    if (@event.IsActionPressed("pause"))
    {
        GetTree().Paused = !GetTree().Paused;
        GetViewport().SetInputAsHandled();
    }
}
```

### 폴링 (연속 입력)

눌린 채인 버튼과 아날로그 축에는 `_physics_process()`에서 `Input` 싱글턴을 써라.

#### GDScript

```gdscript
func _physics_process(delta: float) -> void:
    # Movement vector from 4 directional actions
    var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
    velocity = direction * speed

    # Check if a button is held
    if Input.is_action_pressed("sprint"):
        velocity *= 1.5

    move_and_slide()
```

#### C#

```csharp
public override void _PhysicsProcess(double delta)
{
    Vector2 direction = Input.GetVector("move_left", "move_right", "move_up", "move_down");
    Velocity = direction * Speed;

    if (Input.IsActionPressed("sprint"))
        Velocity *= 1.5f;

    MoveAndSlide();
}
```

### 핵심 입력 메서드

| 메서드                            | 반환    | 무엇에 쓰나                          |
|-----------------------------------|---------|--------------------------------------|
| `Input.is_action_pressed()`       | `bool`  | 눌린 채의 버튼(질주, 웅크리기, 발사) |
| `Input.is_action_just_pressed()`  | `bool`  | 일회성 트리거(점프, 상호작용)        |
| `Input.is_action_just_released()` | `bool`  | 릴리스 트리거(가변 점프 컷)          |
| `Input.get_action_strength()`     | `float` | 아날로그 압력(0.0–1.0)              |
| `Input.get_axis()`                | `float` | 단일 축(-1.0 ~ 1.0)                 |
| `Input.get_vector()`              | `Vector2` | 2D 방향, 정규화됨                 |
| `event.is_action_pressed()`       | `bool`  | `_unhandled_input` 콜백에서 확인     |
| `event.is_action_released()`      | `bool`  | `_unhandled_input` 콜백에서 확인     |

> **`_physics_process()`의 `Input.is_action_just_pressed()`는 입력을 놓칠 수 있다** — 물리 프레임레이트가 렌더 프레임레이트보다 낮으면. 신뢰성을 위해 일회성 액션을 `_unhandled_input()`에서 잡아 플래그를 세우거나, 아래의 입력 버퍼링 패턴을 써라.

### 입력 버퍼링

개별 액션이 물리 프레임 사이에 사라지지 않도록 버퍼링하라: `_unhandled_input()`에서 액션을 잡고, 짧은 타이머(보통 0.1초)와 함께 플래그를 세우고, `_physics_process()`에서 플래그를 소비하라.

---

## 4. 마우스 입력

카메라 룩에는 `InputEventMouseMotion.relative`(`Input.MOUSE_MODE_CAPTURED`와 함께), 클릭에는 `InputEventMouseButton`. 마우스 모드: `VISIBLE`, `HIDDEN`, `CAPTURED`, `CONFINED`. 커스텀 커서는 `Input.set_custom_mouse_cursor(texture, shape, hotspot)`.

---

## 5. 컨트롤러 / 게임패드 지원

런타임 감지에는 `Input.get_connected_joypads()`, 핫플러그에는 `Input.joy_connection_changed` 시그널. 이식성을 위해 조이패드 버튼 이벤트가 있는 Input Map 액션을 써라. 아날로그 스틱: `Input.get_vector("left", "right", "up", "down", deadzone)`은 내장 데드존이 있는 길이 제한 Vector2를 반환한다.

> **Godot 4.7+:** 조이패드 모션 센서 — `Input.get_joy_accelerometer(device)` / `get_joy_gyroscope(device)`(둘 다 `Vector3`), `has_joy_motion_sensors()`로 가드하고 `set_joy_motion_sensors_enabled()`로 활성화. 진동을 이제 조회할 수 있다 — `Input.has_joy_vibration(device)` 및 `get_joy_vibration_strength/duration/remaining_duration()`. `JoyButton`에 `JOY_BUTTON_MISC2`(`21`)부터 `JOY_BUTTON_MISC6`(`25`)이 추가됐다(C#: `JoyButton.Misc2`…). 새 프로젝트 설정 `input_devices/joypads/ignore_joypad_on_unfocused_application`(기본 `false`)은 앱이 포커스를 잃은 동안 조이패드 입력(모션 센서 포함)과 LED 변경을 무시하고 진동을 멈춘다.

---

## 6. 터치 입력

탭/릴리스에는 `InputEventScreenTouch`, 손가락 드래그에는 `InputEventScreenDrag`. 멀티터치는 `event.index`로 추적한다. 데스크톱에서 테스트하려면 **Project Settings → Input Devices → Pointing → Emulate Touch From Mouse**를 활성화하라.

### VirtualJoystick (Godot 4.7+)

Godot 4.7은 온스크린 터치 조이스틱을 위한 내장 `VirtualJoystick` Control 노드를 추가한다. `CanvasLayer`에 추가하고, 그 `action_up/down/left/right` 프로퍼티(`StringName`, 기본값 `&"ui_up"` 등)를 이동 액션으로 가리키게 하면 물리 스틱처럼 그 액션을 트리거한다.

```gdscript
@onready var joystick: VirtualJoystick = $CanvasLayer/VirtualJoystick

func _ready() -> void:
    joystick.action_left = &"move_left"
    joystick.action_right = &"move_right"
    joystick.action_up = &"move_up"
    joystick.action_down = &"move_down"
    joystick.joystick_mode = VirtualJoystick.JOYSTICK_DYNAMIC  # recenters on touch
    joystick.visibility_mode = VirtualJoystick.VISIBILITY_WHEN_TOUCHED

func _physics_process(_delta: float) -> void:
    # The joystick drives the actions — normal polling just works
    var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
```

```csharp
private VirtualJoystick _joystick;

public override void _Ready()
{
    _joystick = GetNode<VirtualJoystick>("CanvasLayer/VirtualJoystick");
    _joystick.ActionLeft = "move_left";
    _joystick.ActionRight = "move_right";
    _joystick.ActionUp = "move_up";
    _joystick.ActionDown = "move_down";
    _joystick.JoystickMode = VirtualJoystick.JoystickModeEnum.Dynamic;
    _joystick.VisibilityMode = VirtualJoystick.VisibilityModeEnum.WhenTouched;
}

public override void _PhysicsProcess(double delta)
{
    Vector2 direction = Input.GetVector("move_left", "move_right", "move_up", "move_down");
}
```

`deadzone_ratio`(기본 `0.0` — InputMap 액션 데드존이 그 위에 적용됨), `clampzone_ratio`(`1.0`), `joystick_size`(`100.0` px), `tip_size`(`50.0` px)를 조율하라. `normal_joystick`/`normal_tip`, `pressed_joystick`/`pressed_tip` StyleBox 테마 슬롯으로 재스타일링하라. `released(input_vector)`와 `flicked(input_vector)` 시그널이 최종 방향과 강도를 보고한다.

---

## 7. 런타임 액션 리바인딩

세 단계: (1) "리바인딩" 모드 동안 `_input`으로 사용자가 고른 키를 캡처, (2) `InputMap.action_erase_events(action)` 다음 `InputMap.action_add_event(action, new_event)` 호출, (3) `ConfigFile`로 영속화하고 실행 시 다시 로드.

---

## 8. 입력 소비와 전파

입력은 **씬 트리 역순**(가장 깊은 자식 먼저, 루트 마지막)으로 전파된다. 이벤트를 소비한 뒤 다른 노드에 도달하지 않게 하려면 `get_viewport().set_input_as_handled()`를 호출하라. 일시정지 중에는 `process_mode = PROCESS_MODE_ALWAYS`인 노드만 입력을 받는다.

---

## 9. 흔한 함정

| 증상                                 | 원인                                             | 해결                                                               |
|--------------------------------------|--------------------------------------------------|--------------------------------------------------------------------|
| 액션이 인식되지 않음                 | Input Map에 액션 이름이 정의되지 않음            | Project > Project Settings > Input Map에 액션 추가                 |
| `is_action_just_pressed()`가 입력을 놓침 | 낮은 틱 레이트의 `_physics_process`에서 호출됨 | 대신 `_unhandled_input()`에서 개별 액션을 잡음                     |
| UI가 열려도 입력이 발화됨            | `_unhandled_input()` 대신 `_input()` 사용        | `_unhandled_input()`으로 전환해 UI가 먼저 이벤트를 소비하게 함     |
| 메뉴를 통과해 마우스 룩이 동작함    | 모드 확인 없이 `_input()`의 마우스 모션          | `if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED`로 가드          |
| 게임패드 스틱이 드리프트함          | 데드존이 너무 낮거나 미설정                       | Input Map에서 액션별 데드존 설정(0.2가 좋은 기본값)               |
| 컨트롤러가 감지되지 않음            | 게임 시작 전에 연결되지 않음                      | `joy_connection_changed` 시그널 연결, 핫플러그 처리                |
| 키 리바인딩이 수정자 키를 캡처함    | Shift/Ctrl/Alt 단독에 대한 필터 없음             | 키코드가 수정자 키인 이벤트를 건너뜀                               |
| 데스크톱에서 터치 입력이 동작 안 함 | "Emulate Touch From Mouse"가 비활성              | Project Settings > Input Devices > Pointing에서 활성화             |
| 일시정지 중 입력이 발화됨           | 노드 `process_mode`가 `INHERIT`(부모와 함께 일시정지) | 일시정지 메뉴를 `PROCESS_MODE_ALWAYS`로 설정                   |
| 한 번 누름에 액션이 두 번 발동함    | 같은 액션을 `_input`과 `_unhandled_input` 둘 다에서 확인 | 액션당 콜백 하나만 고름                                    |

> ⚠️ **Godot 4.7에서 변경:** 마우스와 키보드 장치 ID가 `0`에서 `InputEvent.DEVICE_ID_MOUSE`(`32`)와 `InputEvent.DEVICE_ID_KEYBOARD`(`16`)로 바뀌었다 — 일부 조이패드가 `0`을 장치 ID로 쓰기 때문이다. 키보드/마우스 입력을 감지하려고 `event.device == 0`을 확인하는 코드는 조용히 깨진다 — 상수와 비교하거나 이벤트 타입(`event is InputEventKey`)을 확인하라. [4.7 마이그레이션 가이드](https://docs.godotengine.org/en/latest/tutorials/migrating/upgrading_to_godot_4.7.html)를 보라.

---

## 10. 구현 체크리스트

- [ ] 모든 게임플레이 액션이 Input Map에 정의됨 — 게임 로직에 원시 키코드 없음
- [ ] 개별 액션(점프, 공격)이 `_physics_process()`의 폴링이 아니라 `_unhandled_input()`을 씀
- [ ] 연속 입력(이동, 질주)이 `_physics_process()`에서 `Input.get_vector()` / `Input.is_action_pressed()`를 씀
- [ ] 메뉴를 통과해 회전하지 않도록 마우스 룩이 `Input.mouse_mode == MOUSE_MODE_CAPTURED`를 가드함
- [ ] 컨트롤러 지원을 위해 각 Input Map 액션이 키보드와 게임패드 바인딩을 둘 다 가짐
- [ ] 게임패드 데드존이 Input Map에서 액션별로 설정됨(기본 0.2)
- [ ] 일시정지 메뉴 노드가 일시정지 중 입력을 받도록 `process_mode = PROCESS_MODE_ALWAYS`를 가짐
- [ ] 전파되면 안 되는 이벤트를 소비한 뒤 `get_viewport().set_input_as_handled()`가 호출됨
- [ ] 키보드 vs 게임패드 UI 프롬프트를 표시한다면 입력 장치 감지가 존재함
- [ ] 키 리바인딩이 게임 실행 시 `user://`에 저장·로드됨
