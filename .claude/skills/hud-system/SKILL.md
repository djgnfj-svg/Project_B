---
name: hud-system
description: 인게임 HUD를 만들 때 사용 — 체력 바, 점수 표시, 미니맵, 알림, 피해 숫자
---

# Godot 4.3+의 HUD 시스템

모든 예제는 폐기된 API 없이 Godot 4.3+를 대상으로 한다. GDScript를 먼저, 그다음 C#을 보여준다.

> **관련 스킬:** Control 노드 레이아웃과 테마는 **godot-ui**, HealthComponent 통합은 **component-system**, 점수/알림 시그널은 **event-bus**, 인벤토리 UI 패턴은 **inventory-system**, CanvasLayer 설정과 그리기 순서는 **2d-essentials**, 쿨다운 바·자원 바 바인딩 패턴은 **ability-system**을 보라.

---

## 1. HUD 아키텍처

### 왜 CanvasLayer인가

`CanvasLayer`는 자식을 어떤 `Camera2D`나 `Camera3D` 변환과도 완전히 독립된 고정 화면 공간 레이어에 렌더한다. 그것 없이 씬 루트에 붙은 HUD 노드는 화면을 이동/줌할 때 카메라를 따라 움직인다. 모든 HUD 노드를 `CanvasLayer`(레이어 `≥ 1`)로 감싸면 카메라 움직임과 무관하게 HUD가 항상 제자리에 머문다.

### 씬 트리

```
World (Node2D / Node3D)
├── TileMapLayer          ← game world
├── Player (CharacterBody2D)
│   ├── Camera2D
│   ├── HealthComponent
│   └── HurtboxComponent
├── Enemies
└── HUD (CanvasLayer — layer: 1)
    ├── MarginContainer (anchor: Full Rect — provides edge padding)
    │   ├── TopBar (HBoxContainer)
    │   │   ├── HealthBarPanel (PanelContainer)
    │   │   │   └── HealthBar (TextureProgressBar or ProgressBar)
    │   │   └── ScoreLabel (Label)
    │   └── BottomBar (HBoxContainer)
    │       └── InteractionPrompt (Label — hidden by default)
    ├── DamageNumbersLayer (Node2D — world-space spawning point)
    ├── MinimapContainer (SubViewportContainer)
    │   └── MinimapViewport (SubViewport)
    │       ├── MinimapCamera (Camera2D)
    │       └── MinimapWorld (mirrors or references world nodes)
    └── NotificationStack (VBoxContainer — anchored top-right)
```

**핵심 규칙:**
- 모든 HUD 씬을 단일 `CanvasLayer` 아래에 두라. HUD 노드를 게임 월드 트리에 섞지 마라.
- 메인 HUD에는 `layer = 1`을 써라. HUD 위에 나타나야 하는 오버레이나 일시정지 메뉴에는 더 높은 값(예: `10`)을 써라.
- 피해 숫자는 예외다 — `CanvasLayer`의 `Node2D` 자식에 둘 수 있으며, `get_viewport().get_screen_transform()`으로 월드 위치를 화면 위치로 변환한다.

---

## 2. 체력 바

### ProgressBar vs TextureProgressBar

| 노드 | 언제 쓰나 |
|---|---|
| `ProgressBar` | 프로토타이핑, 단색 바 |
| `TextureProgressBar` | 스프라이트 시트를 쓰는 픽셀 아트 또는 스타일화된 바 |

둘 다 `min_value`, `max_value`, `value`를 노출한다. 트위닝이 정수 단계로 스냅하지 않고 부드러운 애니메이션을 내도록 `step = 0`을 설정하라.

### GDScript

```gdscript
## health_bar.gd — attach to a ProgressBar or TextureProgressBar
class_name HealthBar
extends ProgressBar

## Reference to the HealthComponent this bar tracks.
## Assign in the Inspector or connect programmatically from the HUD root.
@export var health_component: HealthComponent

## Duration (seconds) for the smooth tween on health change.
@export var tween_duration: float = 0.25

var _tween: Tween


func _ready() -> void:
    step = 0.0  # allow fractional values for smooth animation
    if health_component:
        _connect_component(health_component)


## Call this if the HealthComponent is not available at _ready time
## (e.g. the player spawns after the HUD).
func bind(component: HealthComponent) -> void:
    if health_component:
        health_component.health_changed.disconnect(_on_health_changed)
    health_component = component
    _connect_component(component)


func _connect_component(component: HealthComponent) -> void:
    max_value = component.max_health
    value     = component.current_health
    component.health_changed.connect(_on_health_changed)


func _on_health_changed(current: int, maximum: int) -> void:
    max_value = maximum
    _animate_to(current)


func _animate_to(target_value: float) -> void:
    if _tween:
        _tween.kill()
    _tween = create_tween()
    _tween.set_ease(Tween.EASE_OUT)
    _tween.set_trans(Tween.TRANS_QUAD)
    _tween.tween_property(self, "value", target_value, tween_duration)
```

### C#

```csharp
// HealthBar.cs — attach to a ProgressBar or TextureProgressBar
using Godot;

public partial class HealthBar : ProgressBar
{
    [Export] public HealthComponent HealthComponent { get; set; }
    [Export] public float TweenDuration { get; set; } = 0.25f;

    private Tween _tween;

    public override void _Ready()
    {
        Step = 0.0;
        if (HealthComponent != null)
            ConnectComponent(HealthComponent);
    }

    /// <summary>Call this when the HealthComponent is not available at _Ready time.</summary>
    public void Bind(HealthComponent component)
    {
        if (HealthComponent != null)
            HealthComponent.HealthChanged -= OnHealthChanged;
        HealthComponent = component;
        ConnectComponent(component);
    }

    private void ConnectComponent(HealthComponent component)
    {
        MaxValue = component.MaxHealth;
        Value    = component.CurrentHealth;
        component.HealthChanged += OnHealthChanged;
    }

    private void OnHealthChanged(int current, int maximum)
    {
        MaxValue = maximum;
        AnimateTo(current);
    }

    private void AnimateTo(float targetValue)
    {
        _tween?.Kill();
        _tween = CreateTween();
        _tween.SetEase(Tween.EaseType.Out);
        _tween.SetTrans(Tween.TransitionType.Quad);
        _tween.TweenProperty(this, "value", targetValue, TweenDuration);
    }
}
```

**팁:** `TextureProgressBar`를 쓴다면 `fill_mode`를 `FILL_LEFT_TO_RIGHT`로 설정하고 바 텍스처를 `texture_progress`에 할당하라. `value` / `max_value` 비율이 텍스처가 얼마나 드러날지 구동한다.

---

## 3. 점수 / Label 표시

### GDScript

```gdscript
## score_display.gd — attach to a Label
class_name ScoreDisplay
extends Label

## Duration (seconds) to count from old to new score value.
@export var count_duration: float = 0.4

var _displayed_score: int = 0
var _tween: Tween


func _ready() -> void:
    EventBus.score_changed.connect(_on_score_changed)
    text = "0"


func _on_score_changed(new_score: int) -> void:
    _animate_counter(_displayed_score, new_score)


func _animate_counter(from: int, to: int) -> void:
    if _tween:
        _tween.kill()

    _tween = create_tween()
    _tween.set_ease(Tween.EASE_OUT)
    _tween.set_trans(Tween.TRANS_QUAD)
    # Tween an intermediate float; update the label text each step.
    _tween.tween_method(_set_counter_value, float(from), float(to), count_duration)


func _set_counter_value(value: float) -> void:
    _displayed_score = int(value)
    text = str(_displayed_score)
```

### C#

```csharp
// ScoreDisplay.cs — attach to a Label
using Godot;

public partial class ScoreDisplay : Label
{
    [Export] public float CountDuration { get; set; } = 0.4f;

    private int _displayedScore = 0;
    private Tween _tween;

    public override void _Ready()
    {
        EventBus.Instance.ScoreChanged += OnScoreChanged;
        Text = "0";
    }

    private void OnScoreChanged(int newScore)
    {
        AnimateCounter(_displayedScore, newScore);
    }

    private void AnimateCounter(int from, int to)
    {
        _tween?.Kill();
        _tween = CreateTween();
        _tween.SetEase(Tween.EaseType.Out);
        _tween.SetTrans(Tween.TransitionType.Quad);
        _tween.TweenMethod(
            Callable.From<double>(SetCounterValue),
            (double)from,
            (double)to,
            CountDuration
        );
    }

    private void SetCounterValue(double value)
    {
        _displayedScore = (int)value;
        Text = _displayedScore.ToString();
    }
}
```

**필요한 EventBus 시그널:**

```gdscript
# autoloads/event_bus.gd
signal score_changed(new_score: int)
```

```csharp
// EventBus.cs (partial — score signal)
[Signal] public delegate void ScoreChangedEventHandler(int newScore);
```

점수가 주어지는 곳 어디서든 발신한다:

```gdscript
# Inside a collectible or enemy death handler
EventBus.score_changed.emit(GameState.score)
```

```csharp
// Inside a collectible or enemy death handler
EventBus.Instance.EmitSignal(EventBus.SignalName.ScoreChanged, GameState.Score);
```

---

## 4. 피해 숫자

타격 지점 위로 떠올라 사라지는 "−25" 라벨. HUD 쪽 스포너에서 풀링되며, 월드 위치는 `get_viewport().get_canvas_transform()`으로 화면 좌표로 변환된다. 스폰 전 선택적 크리티컬 색칠.

---

## 5. 알림 시스템

토스트 / 알림 스택 — 우상단에 앵커된 `VBoxContainer`로 `max_visible` 클램핑과 큐 주도 해제를 가진다. 새 토스트는 옛 것이 만료되어야 표시된다.

---

## 6. 미니맵 개념

플레이어를 따라가는 전용 `SubViewport` + `Camera2D`로 탑다운 뷰를 렌더한다. SubViewport 텍스처를 HUD 안의 `TextureRect`에 표시한다. `ColorRect` 셰이더로 선택적 원형 마스크. `render_target_update_mode = UPDATE_ALWAYS`를 설정하라.

---

## 7. 상호작용 프롬프트

화면 공간의 "Press [E] to interact" 프롬프트 — 매 프레임 상호작용 대상의 화면 위치를 따라가는 HUD 안의 `Label`. 상호작용 대상의 `Area2D`에서 `body_entered` / `body_exited`로 구동된다. `InputMap.action_get_events(name)`으로 플레이어의 현재 바인딩에 맞는 키를 표시하라.

---

## 8. 체크리스트

- [ ] 모든 HUD 노드가 카메라 변환의 영향을 받지 않도록 `layer >= 1`인 `CanvasLayer`의 자식이다
- [ ] 부드러운 트윈 애니메이션을 위해 `ProgressBar.step`이 정수 스냅이 아닌 `0.0`으로 설정됨
- [ ] 체력 바가 `HealthComponent.health_changed` 시그널에 바인딩됨 — `_process`에서 폴링하지 않음
- [ ] 빠른 피해가 애니메이션을 쌓지 않도록 새 트윈 시작 전에 트윈이 종료됨(`_tween.kill()`)
- [ ] 점수 카운터가 표시 정수를 보간하려고 `tween_method`를 씀 — 점프 컷이 아님
- [ ] 피해 숫자 위치가 `get_viewport().get_canvas_transform()`으로 월드 공간에서 화면 공간으로 변환됨
- [ ] 피해 숫자 풀 크기가 라벨이 트윈 완료 전에 재활용되지 않을 만큼 충분히 큼
- [ ] 알림 스택이 `max_visible`을 강제하고 각 해제 후 큐를 다시 확인함
- [ ] 토스트 자동 해제가 `await get_tree().create_timer()`가 아닌 `Timer` 노드를 씀
- [ ] 미니맵용 `SubViewport`가 `render_target_update_mode = UPDATE_ALWAYS`를 가짐
- [ ] 미니맵 `Camera2D`의 줌과 컬 마스크가 의도한 레이어만 보이도록 구성됨
- [ ] 상호작용 프롬프트가 매 프레임 상호작용 대상의 월드 위치를 변환함 — 스폰 시점에 캐시하지 않음
- [ ] 플레이어의 현재 바인딩에 맞는 키를 표시하려고 `InputMap.action_get_events()`를 씀
- [ ] 입력이 필요 없는 HUD 노드는 게임 클릭을 막지 않도록 `mouse_filter = MOUSE_FILTER_IGNORE`를 설정함
