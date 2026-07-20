---
name: event-bus
description: 노드 간 결합을 끊은 통신을 구현할 때 쓴다 — 타입 지정 시그널을 갖춘 전역 EventBus 오토로드
---

# Godot 4.3+ 이벤트 버스

서로 참조를 쥐지 않고도 무관한 노드가 통신하게 해주는 전역 시그널 허브. 모든 예제는 Godot 4.3+를 대상으로 하며 폐기된 API를 쓰지 않는다.

> **관련 스킬:** 컴포넌트 간 직접 시그널 통신은 **component-system**, C# 특화 시그널 패턴은 **csharp-signals**, 대체 결합 해제 방식은 **dependency-injection**, ability 이벤트로 EventBus를 쓰는 예시는 **ability-system**.

---

## 1. 이벤트 버스란

EventBus는 시그널의 중앙 레지스트리 역할을 하는 싱글톤 오토로드다. 노드가 서로 직접 연결하는 대신, 모든 노드가 공유 EventBus에 연결하거나 그 위에서 emit한다. 이는 한 노드가 다른 노드의 참조를 쥘 필요를 없앤다.

```
Without EventBus             With EventBus
──────────────               ──────────────────────────
NodeA ──signal──► NodeB      NodeA ──emit──► EventBus ──signal──► NodeB
                                                       ──signal──► NodeC
                                                       ──signal──► NodeD
```

**흐름 다이어그램**

```
┌─────────┐   emit(player_died)   ┌───────────┐   player_died   ┌──────────┐
│  NodeA  │ ────────────────────► │ EventBus  │ ───────────────► │  NodeB   │
│(Player) │                       │(Autoload) │                  │   (UI)   │
└─────────┘                       └───────────┘ ───────────────► └──────────┘
                                                  player_died    ┌──────────┐
                                                                 │  NodeC   │
                                                                 │(AudioMgr)│
                                                                 └──────────┘
```

NodeA가 시그널을 emit한다. NodeB와 NodeC는 각각 독립적으로 EventBus에 연결됐다. 어느 쪽도 상대의 존재를 모른다.

---

## 2. 직접 시그널 대비 언제 쓰나

| 시나리오                                   | 권장 접근법          |
|--------------------------------------------|-------------------------------|
| 부모가 자기 자식에게 알림             | 직접 시그널 또는 메서드 호출  |
| 자식이 부모에게 알림                 | 직접 시그널(위로 버블)     |
| 같은 부모를 둔 두 노드             | 부모를 통한 직접 시그널       |
| 트리에서 완전히 무관한 노드     | 이벤트 버스                     |
| UI가 게임플레이 상태 변화에 반응      | 이벤트 버스                     |
| 오디오 매니저가 게임 이벤트에 반응      | 이벤트 버스                     |
| 데이터 매니저 / 저장 시스템이 반응        | 이벤트 버스                     |
| 촘촘하고 성능에 민감한 내부 루프    | 직접 메서드 호출            |

**경험칙:** `get_node("../../SomeDistantNode")`나 하드코딩된 NodePath가 달리 필요해진다면, 이벤트 버스가 더 낫다.

---

## 3. 기본 EventBus

`res://autoloads/event_bus.gd`(또는 `EventBus.cs`)를 만든 뒤, **Project → Project Settings → Autoload**에서 `EventBus`라는 이름으로 등록하라.

### GDScript (`autoloads/event_bus.gd`)

```gdscript
extends Node

## Emitted when the player character has died.
signal player_died

## Emitted whenever the score changes.
signal score_changed(new_score: int)

## Emitted when a level finishes successfully.
signal level_completed(level_id: int)

## Emitted when the player picks up a collectible.
signal item_collected(item_name: String)

## Emitted when the player's health changes.
signal health_changed(current: int, maximum: int)
```

### C# (`Autoloads/EventBus.cs`)

```csharp
using Godot;

/// <summary>
/// Global signal hub. Register as an autoload named "EventBus".
/// </summary>
public partial class EventBus : Node
{
    /// <summary>Emitted when the player character has died.</summary>
    [Signal] public delegate void PlayerDiedEventHandler();

    /// <summary>Emitted whenever the score changes.</summary>
    [Signal] public delegate void ScoreChangedEventHandler(int newScore);

    /// <summary>Emitted when a level finishes successfully.</summary>
    [Signal] public delegate void LevelCompletedEventHandler(int levelId);

    /// <summary>Emitted when the player picks up a collectible.</summary>
    [Signal] public delegate void ItemCollectedEventHandler(string itemName);

    /// <summary>Emitted when the player's health changes.</summary>
    [Signal] public delegate void HealthChangedEventHandler(int current, int maximum);
}
```

---

## 4. 이벤트에 연결하기

소비자는 `_ready()`에서 연결한다. C#에서는 매달린 델리게이트와 메모리 누수를 피하기 위해 항상 `_ExitTree()`에서 연결을 끊어라.

### GDScript

```gdscript
extends CanvasLayer

# GDScript connections are reference-counted and cleaned up automatically
# when the node is freed, but explicit disconnection is still good practice
# for long-lived nodes that reconnect frequently.

func _ready() -> void:
    EventBus.player_died.connect(_on_player_died)
    EventBus.score_changed.connect(_on_score_changed)
    EventBus.health_changed.connect(_on_health_changed)


func _exit_tree() -> void:
    EventBus.player_died.disconnect(_on_player_died)
    EventBus.score_changed.disconnect(_on_score_changed)
    EventBus.health_changed.disconnect(_on_health_changed)


func _on_player_died() -> void:
    $DeathScreen.show()


func _on_score_changed(new_score: int) -> void:
    $ScoreLabel.text = "Score: %d" % new_score


func _on_health_changed(current: int, maximum: int) -> void:
    $HealthBar.value = float(current) / float(maximum) * 100.0
```

### C#

```csharp
using Godot;

public partial class HudLayer : CanvasLayer
{
    private EventBus _eventBus;

    public override void _Ready()
    {
        _eventBus = GetNode<EventBus>("/root/EventBus");

        // Connect using strongly-typed delegate handlers
        _eventBus.PlayerDied      += OnPlayerDied;
        _eventBus.ScoreChanged    += OnScoreChanged;
        _eventBus.HealthChanged   += OnHealthChanged;
    }

    // IMPORTANT: Always disconnect in _ExitTree() in C#.
    // C# delegates are not automatically cleaned up when a node is freed.
    // Failing to disconnect causes the EventBus to hold a reference to the
    // freed node, leading to memory leaks and InvalidOperationExceptions.
    public override void _ExitTree()
    {
        _eventBus.PlayerDied    -= OnPlayerDied;
        _eventBus.ScoreChanged  -= OnScoreChanged;
        _eventBus.HealthChanged -= OnHealthChanged;
    }

    private void OnPlayerDied()
    {
        GetNode<Control>("DeathScreen").Show();
    }

    private void OnScoreChanged(int newScore)
    {
        GetNode<Label>("ScoreLabel").Text = $"Score: {newScore}";
    }

    private void OnHealthChanged(int current, int maximum)
    {
        GetNode<ProgressBar>("HealthBar").Value = (double)current / maximum * 100.0;
    }
}
```

---

## 5. 이벤트 emit하기

생산자는 `EventBus.<signal_name>.emit(...)`(GDScript) 또는 `EmitSignal(SignalName.*)`(C#)를 호출한다. 생산자는 어느 노드가 듣고 있는지 모른다.

### GDScript

```gdscript
extends CharacterBody2D

@export var max_health: int = 100
var current_health: int = max_health
var score: int = 0


func take_damage(amount: int) -> void:
    current_health = clampi(current_health - amount, 0, max_health)
    EventBus.health_changed.emit(current_health, max_health)

    if current_health == 0:
        EventBus.player_died.emit()


func add_score(points: int) -> void:
    score += points
    EventBus.score_changed.emit(score)


func collect_item(item_name: String) -> void:
    EventBus.item_collected.emit(item_name)


func complete_level(level_id: int) -> void:
    EventBus.level_completed.emit(level_id)
```

### C#

```csharp
using Godot;

public partial class Player : CharacterBody2D
{
    [Export] public int MaxHealth { get; set; } = 100;

    private int _currentHealth;
    private int _score;
    private EventBus _eventBus;

    public override void _Ready()
    {
        _currentHealth = MaxHealth;
        _eventBus = GetNode<EventBus>("/root/EventBus");
    }

    public void TakeDamage(int amount)
    {
        _currentHealth = Mathf.Clamp(_currentHealth - amount, 0, MaxHealth);
        _eventBus.EmitSignal(EventBus.SignalName.HealthChanged, _currentHealth, MaxHealth);

        if (_currentHealth == 0)
            _eventBus.EmitSignal(EventBus.SignalName.PlayerDied);
    }

    public void AddScore(int points)
    {
        _score += points;
        _eventBus.EmitSignal(EventBus.SignalName.ScoreChanged, _score);
    }

    public void CollectItem(string itemName)
    {
        _eventBus.EmitSignal(EventBus.SignalName.ItemCollected, itemName);
    }

    public void CompleteLevel(int levelId)
    {
        _eventBus.EmitSignal(EventBus.SignalName.LevelCompleted, levelId);
    }
}
```

---

## 6. 타입 지정 시그널 매개변수

여러 관련 값을 넘겨야 하는 시그널은 평범한 `Dictionary`(유연하지만 타입 없음)보다 전용 `Resource`(강타입, Inspector 친화적)를 선호하라.

### 옵션 A — Resource 페이로드 (구조화된 데이터에 권장)

```gdscript
# combat_event_data.gd
class_name CombatEventData
extends Resource

@export var attacker_id: int = 0
@export var target_id: int = 0
@export var damage_amount: int = 0
@export var damage_type: String = "physical"
@export var is_critical: bool = false
```

```gdscript
# In event_bus.gd — add the signal:
signal combat_hit(data: CombatEventData)
```

```gdscript
# Producer
var data := CombatEventData.new()
data.attacker_id   = get_instance_id()
data.target_id     = target.get_instance_id()
data.damage_amount = 25
data.damage_type   = "fire"
data.is_critical   = true
EventBus.combat_hit.emit(data)
```

```gdscript
# Consumer
func _on_combat_hit(data: CombatEventData) -> void:
    if data.is_critical:
        _show_critical_text(data.target_id, data.damage_amount)
```

```csharp
// CombatEventData.cs — Resource-based payload (Inspector-friendly, fully typed)
using Godot;

public partial class CombatEventData : Resource
{
    [Export] public int AttackerId   { get; set; }
    [Export] public int TargetId     { get; set; }
    [Export] public int DamageAmount { get; set; }
    [Export] public string DamageType { get; set; } = "physical";
    [Export] public bool IsCritical  { get; set; }
}

// In EventBus.cs — add the signal:
// [Signal] public delegate void CombatHitEventHandler(CombatEventData data);

// Producer
public void FireCombatHit(Node target, int damageAmount, string damageType, bool isCritical)
{
    var data = new CombatEventData
    {
        AttackerId   = (int)GetInstanceId(),
        TargetId     = (int)target.GetInstanceId(),
        DamageAmount = damageAmount,
        DamageType   = damageType,
        IsCritical   = isCritical,
    };
    _eventBus.EmitSignal(EventBus.SignalName.CombatHit, data);
}

// Consumer
private void OnCombatHit(CombatEventData data)
{
    if (data.IsCritical)
        ShowCriticalText(data.TargetId, data.DamageAmount);
}
```

### 옵션 B — Dictionary 페이로드 (프로토타이핑에 허용)

```gdscript
# In event_bus.gd:
signal combat_hit(data: Dictionary)

# Producer
EventBus.combat_hit.emit({
    "attacker_id":   get_instance_id(),
    "target_id":     target.get_instance_id(),
    "damage_amount": 25,
    "is_critical":   true,
})

# Consumer — note: no compile-time safety
func _on_combat_hit(data: Dictionary) -> void:
    if data.get("is_critical", false):
        _show_critical_text(data["target_id"], data["damage_amount"])
```

C# 대응은 Resource 타입 대신 `Godot.Collections.Dictionary`를 쓰고 값을 읽을 때 `data["key"].AsInt32()` / `.AsString()`을 사용한다 — 컴파일 타임 안전성 없음.

필드가 2~3개를 넘는 구조화·재사용 페이로드에는 **Resource를 선호하라**. 프로토타이핑 중이거나 형태가 자주 바뀔 때만 **Dictionary를 써라**.

---

## 7. 안티패턴

### 모든 것에 이벤트 버스 쓰기 (과도한 결합 해제)

```gdscript
# BAD — a parent querying its own child through the event bus
# is unnecessarily indirect and hard to follow.
func _ready() -> void:
    EventBus.request_player_position.connect(_on_request_player_position)

func _on_request_player_position() -> void:
    EventBus.player_position_response.emit(global_position)

# GOOD — a parent can access its child directly.
var player_pos: Vector2 = $Player.global_position
```

### 시그널을 더 emit하는 핸들러 안의 부작용

```gdscript
# BAD — handler emits another signal, which triggers another handler,
# which emits another signal. Tracing the flow requires reading all handlers.
func _on_player_died() -> void:
    _save_high_score()          # side effect
    EventBus.high_score_saved.emit()  # triggers yet another chain

# GOOD — each handler does one thing; orchestration lives in one place.
func _on_player_died() -> void:
    _show_death_screen()

# A dedicated GameManager handles multi-step reactions:
func _on_player_died() -> void:
    _save_high_score()
    get_tree().reload_current_scene()
```

### 순환 이벤트 사슬

```gdscript
# BAD — PlayerHealth connects to health_changed and re-emits it.
func _on_health_changed(current: int, maximum: int) -> void:
    _current = current
    EventBus.health_changed.emit(_current, maximum)  # infinite loop

# GOOD — update internal state only; let the original emitter own the signal.
func _on_health_changed(current: int, maximum: int) -> void:
    _current = current
    _update_display()
```

### C#에서 끊지 않고 연결하기

```csharp
// BAD — node is freed but EventBus still holds a reference to the delegate.
// The next emission raises an InvalidOperationException or silently leaks memory.
public override void _Ready()
{
    GetNode<EventBus>("/root/EventBus").PlayerDied += OnPlayerDied;
    // No _ExitTree() override — memory leak.
}

// GOOD — always pair Connect with Disconnect in C#.
public override void _ExitTree()
{
    GetNode<EventBus>("/root/EventBus").PlayerDied -= OnPlayerDied;
}
```

---

## 8. 테스트

[GUT](https://github.com/bitwes/Gut)를 사용해 생산자 측 emit(`watch_signals(event_bus)` 후 `assert_signal_emitted_with_parameters(...)`)과 소비자 측 반응(버스에 emit한 뒤 소비자 상태를 assert) 둘 다를 검증하라. 항상 새 인스턴스가 아니라 `get_tree().root.get_node("EventBus")`로 얻은 실제 오토로드 EventBus를 대상으로 테스트하라.

---

## 9. 체크리스트

- [ ] `EventBus` 오토로드가 **Project → Project Settings → Autoload**에 등록됨
- [ ] 모든 시그널이 타입 지정 매개변수(`signal foo(bar: int)`)를 사용 — 타입 없는 시그널 없음
- [ ] 모든 소비자가 `_ready()`에서 연결하고 `_exit_tree()`에서 끊음(C#에서 필수)
- [ ] 생산자가 소비자 메서드를 직접 호출하지 않고 `EventBus`를 통해 emit
- [ ] 시그널을 emit하거나 받으려는 목적만으로 다른 무관한 노드의 직접 참조를 쥔 노드 없음
- [ ] 복잡한 페이로드가 원시 `Dictionary`가 아니라 `Resource` 서브클래스를 사용
- [ ] 방금 받은 시그널을 다시 emit하는 핸들러 없음(무한 루프 방지)
- [ ] 직접 부모-자식 호출이나 시그널이 더 간단한 곳에 이벤트 버스 시그널을 쓰지 않음
- [ ] GUT 테스트가 중요한 시그널의 emit(생산자)과 수신(소비자)을 모두 커버
- [ ] C# 핸들러가 머지 전에 `_ExitTree()`에서 끊는지 검증됨
