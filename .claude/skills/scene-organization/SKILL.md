---
name: scene-organization
description: 씬 트리 구조를 설계할 때 사용한다 — 조합 대 상속, 씬을 언제 쪼갤지, 노드 계층 패턴
---

# 씬 조직

Godot 4.3+ 씬 트리를 구조화하는 가이드: 언제 쪼개고, 언제 조합하며, 노드가 어떻게 소통해야 하는가.

> **관련 스킬:** 조합 패턴은 **component-system**, 결합도 낮은 통신은 **event-bus**, 씬 트리 계획은 **godot-brainstorming**, TileMapLayer와 CanvasLayer 조직은 **2d-essentials**를 참고하라.

---

## 1. 핵심 원칙

씬은 빌딩 블록이다. 각 씬은 정확히 하나의 개념을 캡슐화한다 — 플레이어, 적, 체력 바, 무기. 씬은 홀로 이해될 수 있고, 수정 없이 재사용될 수 있고, 이웃을 깨뜨리지 않고 교체될 수 있어야 한다.

> 씬 하나 = 책임 하나. 씬을 두 단어 이하로 이름 짓기 어렵다면, 아마 너무 많은 일을 하고 있는 것이다.

---

## 2. 상속보다 조합

### 플레이어 씬 — 재사용 부품으로 조합

```
Player (CharacterBody2D)
├── Sprite2D
├── CollisionShape2D
├── HealthComponent
├── HitboxComponent
├── StateMachine
└── AnimationPlayer
```

`HealthComponent`, `HitboxComponent`, `StateMachine`은 자식 씬으로 인스턴스화되는 별개의 `.tscn` 파일이다. 체력이 필요한 어떤 개체든 — 적, 파괴 가능한 상자, 보스 — 로직을 중복하지 않고 `HealthComponent`를 포함할 수 있다.

### HealthComponent — 전체 예제

**GDScript**

```gdscript
# health_component.gd
class_name HealthComponent
extends Node

signal health_changed(old_value: int, new_value: int)
signal died

@export var max_health: int = 100

var current_health: int

func _ready() -> void:
    current_health = max_health

func take_damage(amount: int) -> void:
    if amount <= 0:
        return
    var old_health := current_health
    current_health = max(0, current_health - amount)
    health_changed.emit(old_health, current_health)
    if current_health == 0:
        died.emit()

func heal(amount: int) -> void:
    if amount <= 0:
        return
    var old_health := current_health
    current_health = min(max_health, current_health + amount)
    health_changed.emit(old_health, current_health)

func is_alive() -> bool:
    return current_health > 0
```

**C#**

```csharp
// HealthComponent.cs
using Godot;

[GlobalClass]
public partial class HealthComponent : Node
{
    [Signal]
    public delegate void HealthChangedEventHandler(int oldValue, int newValue);

    [Signal]
    public delegate void DiedEventHandler();

    [Export]
    public int MaxHealth { get; set; } = 100;

    public int CurrentHealth { get; private set; }

    public override void _Ready()
    {
        CurrentHealth = MaxHealth;
    }

    public void TakeDamage(int amount)
    {
        if (amount <= 0)
            return;
        int oldHealth = CurrentHealth;
        CurrentHealth = Mathf.Max(0, CurrentHealth - amount);
        EmitSignal(SignalName.HealthChanged, oldHealth, CurrentHealth);
        if (CurrentHealth == 0)
            EmitSignal(SignalName.Died);
    }

    public void Heal(int amount)
    {
        if (amount <= 0)
            return;
        int oldHealth = CurrentHealth;
        CurrentHealth = Mathf.Min(MaxHealth, CurrentHealth + amount);
        EmitSignal(SignalName.HealthChanged, oldHealth, CurrentHealth);
    }

    public bool IsAlive() => CurrentHealth > 0;
}
```

### 대신 상속을 언제 쓰나

상속은 씬이 단지 동작이 아니라 **구조**를 공유하는 경우에 맞는다 — 자식 씬들이 동일한 노드 레이아웃을 가진 같은 것의 변형이고 몇 개의 export 프로퍼티만 다를 때.

좋은 후보:

- `Enemy` → `Orc`, `Goblin` — 같은 뼈대(Sprite2D, CollisionShape2D, HealthComponent, AI), 다른 스탯과 아트
- `Weapon` → `Sword`, `Bow` — 같은 슬롯 부착 로직, 다른 애니메이션과 데미지 타입
- `Pickup` → `HealthPickup`, `AmmoPickup` — 같은 Area2D + CollisionShape2D + 애니메이션, 획득 시 다른 효과

### 경험칙

| 시나리오 | 패턴 |
|---|---|
| 씬 전체를 복사-붙여넣기하고 몇 개의 export 프로퍼티만 바꿀 것 같다 | **상속** |
| 서로 다른 개체 타입 전반에 노드의 일부를 섞어 쓰고 싶다 | **조합** |

---

## 3. 씬 분할 규칙

### 씬을 쪼개는 경우:

- **재사용** — 서브 씬이 둘 이상의 부모 씬에서 필요하다
- **복잡도** — 씬이 대략 15개 노드를 넘는다; 하나 이상의 관심사를 지고 있다
- **독립성** — 서브 씬을 부모를 열지 않고 테스트·미리보기·수정할 수 있다
- **팀** — 여러 사람이 같은 기능을 작업할 때 별개의 씬이 병합 충돌을 줄인다

### 노드를 함께 두는 경우:

- 노드가 **긴밀하게 결합**돼 있다 — 쪼개면 직접 노드 참조가 깔끔하게 하던 것을 복제하려고 과도한 시그널 배선이 필요하다
- 그룹핑이 **작고 한 번만 쓰인다** — 단일 씬에 존재하는 두 노드짜리 헬퍼는 자체 `.tscn` 파일이 필요 없다
- 쪼개면 **단순 작업 오버헤드**가 생긴다 — 부모가 자식에게 "너 맞았어"라고 알리려고 시그널 셋을 배선해야 한다면, 그 분할은 값을 못 한다

---

## 4. 노드 통신 패턴

```
        [Parent]
        /      \
  [Child A]  [Child B]
       \
     [Child C]
```

### 시그널은 위로 간다 (자식 → 부모)

자식 노드는 무언가 일어났다고 알린다. 부모 — 또는 시그널에 연결한 어떤 노드든 — 그것에 대해 무엇을 할지 결정한다. 이렇게 하면 자식은 자기 맥락을 모른 채 완전히 재사용 가능해진다.

```gdscript
# Child emits; it does not know who is listening
health_component.died.connect(_on_player_died)
```

### 메서드 호출은 아래로 간다 (부모 → 자식)

부모는 자식의 메서드를 직접 호출해 자식을 구동한다. 부모가 참조를 소유하고, 자식은 깔끔한 API를 노출하며 부모에 대해 알 필요가 없다.

```gdscript
# Parent calls into child
$HealthComponent.take_damage(10)
$AnimationPlayer.play("hurt")
```

### EventBus는 옆으로 간다 (동료 → 동료)

조상-후손 관계가 없는 씬 간 통신에는 — 예: 적이 HUD에 알림 — 오토로드 이벤트 버스를 써라. 버스로 emit하면 발신자와 수신자가 완전히 분리된다.

```gdscript
# Autoload: EventBus.gd
signal enemy_killed(enemy: Enemy)

# Enemy scene
EventBus.enemy_killed.emit(self)

# HUD scene
EventBus.enemy_killed.connect(_on_enemy_killed)
```

**C#**

```csharp
// Pattern 1: Signals travel up (child → parent)
// Child emits; it does not know who is listening.
public partial class Player : CharacterBody2D
{
    public override void _Ready()
    {
        var health = GetNode<HealthComponent>("HealthComponent");
        health.Died += OnPlayerDied;
    }

    private void OnPlayerDied()
    {
        // Parent reacts — child HealthComponent stays ignorant of context
    }
}

// Pattern 2: Method calls travel down (parent → child)
// Parent drives children by calling their methods directly.
public partial class Level : Node2D
{
    public override void _Ready()
    {
        var health = GetNode<HealthComponent>("Player/HealthComponent");
        health.TakeDamage(10);

        var anim = GetNode<AnimationPlayer>("Player/AnimationPlayer");
        anim.Play("hurt");
    }
}

// Pattern 3: EventBus travels sideways (peer → peer)
// EventBus.cs — registered as an Autoload singleton named "EventBus"
public partial class EventBus : Node
{
    [Signal] public delegate void EnemyKilledEventHandler(Enemy enemy);
}

// Enemy scene — emits on the bus; does not reference HUD
public partial class Enemy : CharacterBody2D
{
    private void Die()
    {
        var bus = GetNode<EventBus>("/root/EventBus");
        bus.EmitSignal(EventBus.SignalName.EnemyKilled, this);
        QueueFree();
    }
}

// HUD scene — subscribes on the bus; does not reference Enemy
public partial class Hud : CanvasLayer
{
    public override void _Ready()
    {
        var bus = GetNode<EventBus>("/root/EventBus");
        bus.EnemyKilled += OnEnemyKilled;
    }

    private void OnEnemyKilled(Enemy enemy)
    {
        // Update kill counter, score, etc.
    }
}
```

---

## 5. 씬 트리 패턴

### 개체-컴포넌트 패턴

```
Enemy (CharacterBody2D)
├── Visuals
│   ├── Sprite2D
│   └── AnimationPlayer
├── Collision
│   └── CollisionShape2D
├── Components
│   ├── HealthComponent
│   └── HitboxComponent
└── AI
    ├── NavigationAgent2D
    └── StateMachine
```

일반 `Node` 컨테이너(`Visuals`, `Collision`, `Components`, `AI`)로 관심사별로 묶어라. 각 서브 그룹을 에디터에서 접을 수 있고 독립적으로 작업할 수 있다.

### UI 씬 패턴

```
HUD (CanvasLayer)
├── MarginContainer
│   ├── TopBar
│   │   ├── HealthBar
│   │   └── ResourceBar
│   └── BottomBar
│       ├── Hotbar
│       └── MiniMap
└── PauseMenu
```

`CanvasLayer`는 HUD 요소가 항상 위에 렌더되도록 보장한다. `MarginContainer`는 세이프 에어리어 패딩을 처리한다. `TopBar`, `BottomBar`, `PauseMenu`는 별개의 인스턴스화된 씬이라 각각을 루트 HUD 씬을 열지 않고 편집할 수 있다.

### 레벨 씬 패턴

```
Level01 (Node2D)
├── TileMapLayer
├── Entities
│   ├── Player (instance)
│   └── Enemies (Node2D)
│       ├── Orc (instance)
│       └── Goblin (instance)
├── Pickups (Node2D)
├── Navigation
│   └── NavigationRegion2D
└── Camera2D
```

레벨 씬은 조합 루트다 — 레이아웃을 소유하고 인스턴스를 스폰하지만, 그 자체에는 게임플레이 로직이 없다. `Entities`, `Pickups`, `Navigation`은 조직적 그룹핑과 `get_children()` 순회 단순화를 위한 일반 `Node2D` 컨테이너다.

---

## 6. 체크리스트

- [ ] 각 씬이 정확히 하나의 책임을 가지며, 두 단어 이하로 이름 지어진다
- [ ] 재사용 컴포넌트(`HealthComponent`, `StateMachine` 등)가 별개의 `.tscn` 파일이다
- [ ] 함께 둘 문서화된 이유 없이 ~15개 노드를 넘는 씬이 없다
- [ ] 자식은 시그널을 위로 emit하고, 부모는 메서드를 아래로 호출한다
- [ ] 동료 간 통신은 `get_parent()` 체인이 아니라 EventBus 오토로드를 쓴다
- [ ] 코드에 `get_parent().get_parent()`나 `get_node("../../SomeNode")` 경로가 없다
- [ ] 가독성을 위해 노드가 논리적 컨테이너(`Visuals`, `Components`, `AI` 등)로 묶여 있다
