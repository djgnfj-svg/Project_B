---
name: component-system
description: 재사용 가능한 노드 컴포넌트를 만들 때 쓴다 — 조합(composition) 패턴, 컴포넌트 간 통신, 인터페이스 설계
---

# Godot 4.3+ 컴포넌트 시스템

조합을 통해 행동을 구축하라. 상속 사슬을 오르는 대신, 작고 집중된 컴포넌트를 아무 엔티티에나 붙여라. 모든 예제는 Godot 4.3+를 대상으로 하며 폐기된 API를 쓰지 않는다.

> **관련 스킬:** 씬 트리 조합은 **scene-organization**, 결합을 끊은 컴포넌트 통신은 **event-bus**, 데이터 주도 컴포넌트 설정은 **resource-pattern**, Area2D/3D 겹침 감지와 충돌 셰이프는 **physics-system**, 이 패턴 위에 세운 AbilityComponent 예시는 **ability-system**.

---

## 1. 왜 컴포넌트인가

| 상속의 문제 | 컴포넌트가 푸는 방식 |
|--------------------------|-------------------------|
| 깊은 사슬은 취약하다 — 한 클래스를 바꾸면 여럿이 깨진다 | 각 컴포넌트는 한 가지 일만 하는 독립 씬 |
| 무관한 엔티티 간 행동 공유는 어색한 베이스 클래스를 요구한다 | 그 행동이 필요한 아무 엔티티에나 컴포넌트를 얹는다 |
| 새 조합을 추가하려면 새 서브클래스가 필요하다 | 씬 수준에서 컴포넌트를 자유롭게 섞는다 |

핵심 이점:

- **엔티티 간 재사용** — `HealthComponent`는 플레이어, 적, 파괴 가능한 상자, 보스에 코드 변경 없이 동작한다.
- **관심사 분리** — 피해 감지, 체력 추적, 상태 애니메이션이 각자 파일이다. 디버깅이 국소적이다.
- **행동 섞기** — 적에게 `HitboxComponent`와 `PatrolComponent`를 독립적으로 준다. 하나를 제거해도 다른 하나는 영향받지 않는다.

---

## 2. 컴포넌트 설계 규칙

1. **컴포넌트 하나에 책임 하나.** `HealthAndShieldAndRegenComponent`라고 이름 짓게 된다면 분리하라.
2. **직접 형제 접근이 아니라 시그널로 통신하라.** 컴포넌트는 `get_parent().get_node("SiblingComponent")`를 호출하면 안 된다. 대신 시그널을 emit하라.
3. **가능하면 무상태로.** 가변 상태를 저장하기보다 입력과 `@export` 설정에서 상태를 유도하는 것을 선호하라. 상태가 필요하면 private으로 유지하라.
4. **모든 설정에 `@export`를 써라.** 피해량, 쿨다운 지속시간, 레이어 마스크는 하드코딩 상수가 아니라 Inspector에 둔다.

---

## 3. 흔한 컴포넌트

| 컴포넌트 | 목적 | 주요 시그널 |
|---|---|---|
| `HealthComponent` | 현재/최대 HP 추적, 피해와 회복 적용 | `health_changed(current, maximum)`, `died` |
| `HitboxComponent` | 겹치는 hurtbox 감지 후 피해 트리거 | `hit(target_hurtbox)` |
| `HurtboxComponent` | 히트 수신, 피해를 `HealthComponent`로 라우팅 | `hurt(damage_amount)` |
| `InteractableComponent` | 엔티티를 상호작용 가능으로 표시, 플레이어 겹침 시 발동 | `interacted(interactor)` |
| `StateMachineComponent` | `_process`와 `_physics_process`를 자식 상태 노드에 위임 | `state_changed(from, to)` |

---

## 4. HitboxComponent

피해를 주는 아무 엔티티에나 붙인다. Inspector에서 `damage`를 설정한다.

### GDScript (`hitbox_component.gd`)

```gdscript
class_name HitboxComponent
extends Area2D

## Damage dealt to the target hurtbox on contact.
@export var damage: int = 10

## Minimum seconds between successive hits (0 = no cooldown).
@export var cooldown_duration: float = 0.5

signal hit(target_hurtbox: HurtboxComponent)

var _on_cooldown: bool = false

@onready var _cooldown_timer: Timer = _build_timer()


func _ready() -> void:
	area_entered.connect(_on_area_entered)


func _on_area_entered(area: Area2D) -> void:
	if _on_cooldown:
		return
	if area is not HurtboxComponent:
		return
	hit.emit(area)
	area.receive_hit(damage)
	if cooldown_duration > 0.0:
		_on_cooldown = true
		_cooldown_timer.start(cooldown_duration)


func _on_cooldown_timeout() -> void:
	_on_cooldown = false


func _build_timer() -> Timer:
	var t := Timer.new()
	t.one_shot = true
	t.timeout.connect(_on_cooldown_timeout)
	add_child(t)
	return t
```

### C# (`HitboxComponent.cs`)

```csharp
using Godot;

public partial class HitboxComponent : Area2D
{
    /// <summary>Damage dealt to the target hurtbox on contact.</summary>
    [Export] public int Damage { get; set; } = 10;

    /// <summary>Minimum seconds between successive hits (0 = no cooldown).</summary>
    [Export] public float CooldownDuration { get; set; } = 0.5f;

    [Signal] public delegate void HitEventHandler(HurtboxComponent targetHurtbox);

    private bool _onCooldown;
    private Timer _cooldownTimer;

    public override void _Ready()
    {
        _cooldownTimer = new Timer { OneShot = true };
        _cooldownTimer.Timeout += OnCooldownTimeout;
        AddChild(_cooldownTimer);

        AreaEntered += OnAreaEntered;
    }

    private void OnAreaEntered(Area2D area)
    {
        if (_onCooldown) return;
        if (area is not HurtboxComponent hurtbox) return;

        EmitSignal(SignalName.Hit, hurtbox);
        hurtbox.ReceiveHit(Damage);

        if (CooldownDuration > 0f)
        {
            _onCooldown = true;
            _cooldownTimer.Start(CooldownDuration);
        }
    }

    private void OnCooldownTimeout() => _onCooldown = false;
}
```

---

## 5. HurtboxComponent

피해를 받을 수 있는 아무 엔티티에나 붙인다. `@export`로 형제 `HealthComponent`에 연결한다.

### GDScript (`hurtbox_component.gd`)

```gdscript
class_name HurtboxComponent
extends Area2D

## Reference to the HealthComponent on the same entity.
@export var health_component: HealthComponent

## Invincibility frame duration in seconds (0 = none).
@export var invincibility_duration: float = 0.0

signal hurt(damage_amount: int)

var _invincible: bool = false

@onready var _iframes_timer: Timer = _build_timer()


func receive_hit(damage: int) -> void:
	if _invincible:
		return
	hurt.emit(damage)
	if health_component:
		health_component.take_damage(damage)
	if invincibility_duration > 0.0:
		_invincible = true
		_iframes_timer.start(invincibility_duration)


func _on_iframes_timeout() -> void:
	_invincible = false


func _build_timer() -> Timer:
	var t := Timer.new()
	t.one_shot = true
	t.timeout.connect(_on_iframes_timeout)
	add_child(t)
	return t
```

### C# (`HurtboxComponent.cs`)

```csharp
using Godot;

public partial class HurtboxComponent : Area2D
{
    /// <summary>Reference to the HealthComponent on the same entity.</summary>
    [Export] public HealthComponent HealthComponent { get; set; }

    /// <summary>Invincibility frame duration in seconds (0 = none).</summary>
    [Export] public float InvincibilityDuration { get; set; } = 0f;

    [Signal] public delegate void HurtEventHandler(int damageAmount);

    private bool _invincible;
    private Timer _iframesTimer;

    public override void _Ready()
    {
        _iframesTimer = new Timer { OneShot = true };
        _iframesTimer.Timeout += OnIframesTimeout;
        AddChild(_iframesTimer);
    }

    public void ReceiveHit(int damage)
    {
        if (_invincible) return;

        EmitSignal(SignalName.Hurt, damage);
        HealthComponent?.TakeDamage(damage);

        if (InvincibilityDuration > 0f)
        {
            _invincible = true;
            _iframesTimer.Start(InvincibilityDuration);
        }
    }

    private void OnIframesTimeout() => _invincible = false;
}
```

---

## 6. 컴포넌트 통신

컴포넌트는 형제의 메서드를 직접 호출하면 안 된다. 결합을 끊으려면 시그널을 써라.

```
┌─────────────────────────────────────────────────────┐
│  Entity (CharacterBody2D)                            │
│                                                      │
│  ┌──────────────┐    hit(hurtbox)                    │
│  │ HitboxComponent ──────────────────────────────┐  │
│  └──────────────┘                                 │  │
│                                                   ▼  │
│                              ┌─────────────────────┐ │
│                              │  HurtboxComponent   │ │
│                              │  receive_hit(dmg)   │ │
│                              │  ──── calls ──────► │ │
│                              │  HealthComponent    │ │
│                              │  .take_damage(dmg) │ │
│                              └────────┬────────────┘ │
│                                       │              │
│                              health_changed / died   │
│                                       │              │
│                              ┌────────▼────────────┐ │
│                              │  HealthComponent    │ │
│                              │  emits: died        │ │
│                              └─────────────────────┘ │
└─────────────────────────────────────────────────────┘
```

**흐름 설명:**

1. `HitboxComponent`가 `area_entered`를 통해 겹치는 `HurtboxComponent`를 감지한다.
2. `hit(target_hurtbox)`를 emit하고(엔티티 자체 로직용, 예: 소리 재생) `target_hurtbox.receive_hit(damage)`를 호출한다 — 유일한 교차 컴포넌트 호출이며, 형제가 아니라 hurtbox의 직접 인터페이스를 대상으로 한다.
3. `HurtboxComponent.receive_hit()`가 애니메이션/VFX용으로 `hurt(damage_amount)`를 emit한 뒤, 명시적으로 연결된 참조에서 `health_component.take_damage(damage)`를 호출한다.
4. `HealthComponent.take_damage()`가 HP를 갱신하고 `health_changed` 또는 `died`를 emit한다. 리스너(UI, GameManager 등)는 전투 컴포넌트를 건드리지 않고 그 시그널에 연결한다.

---

## 7. 컴포넌트 연결

선호 순서대로 세 가지 패턴:

### @export NodePath — 가장 유연, 씬 트리 전역에서 동작

```gdscript
# hurtbox_component.gd
@export var health_component: HealthComponent

# Inspector: drag the HealthComponent node into the slot.
```

> **함정:** `@export` 노드 참조는 에디터 인스펙터를 통해 연결된다. 씬을 프로그래밍으로 만들거나 `.tscn` 파일을 손으로 작성하면 런타임에 참조가 null일 수 있다. 그럴 때는 부모의 `_ready()`에서 명시적으로 연결하라:
> ```gdscript
> hurtbox.health_component = health_component
> ```

### @onready 직접 자식 — 컴포넌트가 알려진 자식일 때 간단

```gdscript
# enemy.gd
@onready var health: HealthComponent = $HealthComponent
@onready var hurtbox: HurtboxComponent = $HurtboxComponent
```

### get_node 패턴 — 경로가 동적이거나 선택적일 때

```gdscript
func _ready() -> void:
	var health := get_node_or_null("HealthComponent") as HealthComponent
	if health:
		health.died.connect(_on_died)
```

> 연결할 노드가 트리 다른 곳에 있으면 `@export`를 선호하라. 항상 존재하는 직접 자식에는 `@onready`를 선호하라. 컴포넌트가 선택적이면 `get_node_or_null`을 써라.

### C# 대응

```csharp
// Pattern 1: [Export] property — drag-and-drop in the Inspector.
public partial class HurtboxComponent : Area3D
{
    [Export] public HealthComponent Health { get; set; }
}

// Pattern 2: GetNode<T> for a known child path (equivalent to @onready var x := $Path).
public partial class Enemy : CharacterBody3D
{
    private HealthComponent _health;
    private HurtboxComponent _hurtbox;

    public override void _Ready()
    {
        _health = GetNode<HealthComponent>("HealthComponent");
        _hurtbox = GetNode<HurtboxComponent>("HurtboxComponent");
        _health.Died += QueueFree;
    }
}

// Pattern 3: GetNodeOrNull<T> when the component is optional (equivalent to get_node_or_null).
public partial class Pickup : Node3D
{
    public override void _Ready()
    {
        var health = GetNodeOrNull<HealthComponent>("HealthComponent");
        if (health != null)
            health.Died += OnDied;
    }

    private void OnDied() { /* ... */ }
}
```

---

## 8. 런타임에 컴포넌트 찾기

정적 유틸리티를 사용해 아무 엔티티에서 주어진 타입의 첫 컴포넌트를 찾아라. 이는 서로 다른 엔티티 씬에서 노드 이름을 하드코딩하는 것을 피한다.

### GDScript (`component_utils.gd`)

```gdscript
class_name ComponentUtils


## Returns the first child of [param entity] that is an instance of [param component_type],
## or null if none is found.
static func get_component(entity: Node, component_type: GDScript) -> Node:
	for child in entity.get_children():
		if is_instance_of(child, component_type):
			return child
	return null


## Example usage:
##   var health := ComponentUtils.get_component(enemy, HealthComponent) as HealthComponent
##   if health:
##       health.take_damage(5)
```

### C# (`ComponentUtils.cs`)

```csharp
using Godot;

public static class ComponentUtils
{
    /// <summary>
    /// Returns the first child of <paramref name="entity"/> that is of type
    /// <typeparamref name="T"/>, or null if none is found.
    /// </summary>
    public static T GetComponent<T>(Node entity) where T : Node
    {
        foreach (var child in entity.GetChildren())
        {
            if (child is T component)
                return component;
        }
        return null;
    }
}

// Example usage:
//   var health = ComponentUtils.GetComponent<HealthComponent>(enemy);
//   health?.TakeDamage(5);
```

---

## 9. 구현 체크리스트

- [ ] 각 컴포넌트가 자기 `.tscn` 씬으로 저장되고 인스턴싱으로 재사용됨
- [ ] 컴포넌트가 시그널로 통신 — `get_parent().get_node("Sibling")` 호출 없음
- [ ] 컴포넌트 스크립트 어디에도 직접 형제 접근 없음
- [ ] 모든 조정 가능한 값(`damage`, `max_health`, `cooldown_duration`)이 `@export`
- [ ] 각 컴포넌트를 최소 테스트 씬에 격리해 붙여 테스트 가능
