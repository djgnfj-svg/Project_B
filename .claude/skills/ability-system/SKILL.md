---
name: ability-system
description: 캐릭터 어빌리티를 만들 때 사용한다 — 비용/쿨다운/시전(cast)을 가진 Resource 기반 어빌리티, 버프/디버프, 스탯 수정자(stat modifier), 게임플레이 태그, HUD 바인딩
---

# 어빌리티 시스템

Godot 기본 부품으로 데이터 주도 어빌리티 시스템을 만든다: 어빌리티는 `Resource`이고, `AbilityComponent` 노드가 이를 소유하고 실행하며, 이펙트/스탯/태그가 그 위에 조합된다. 서드파티 애드온이 필요 없다.

> **관련 스킬:** `Resource` 데이터 컨테이너는 **resource-pattern**, 컴포넌트 노드 패턴은 **component-system**, 시스템 간 어빌리티 이벤트는 **event-bus**, 시전자 상태(예: 시전 중/기절)는 **state-machine**, 쿨다운 UI는 **hud-system**을 참고하라.

---

## 1. 아키텍처 개요

Godot 4.x의 어빌리티 시스템은 협력하는 세 계층으로 만든다:

- **데이터 계층 — `Ability` (Resource):** 각 어빌리티는 exported 필드(`ability_name`, `cost`, `cooldown`, `cast_time`)와 두 메서드를 가진 `Resource` 서브클래스다: 전제 조건을 검증하는 `can_activate(caster) -> bool`, 이펙트를 실행하는 `activate(caster) -> void`. 어빌리티를 Resource로 저장하면 디자이너가 코드를 건드리지 않고 Godot 에디터에서 어빌리티를 만들고 밸런싱할 수 있다.

- **동작 계층 — `AbilityComponent` (Node):** 어빌리티를 쓰는 엔티티에 붙이는 단일 노드다. 부여받은 어빌리티 집합을 들고, 비용/쿨다운을 강제하며, `Ability.activate()` 호출을 구동한다. 네 개의 시그널이 결합 없이 게임의 나머지에 정보를 알린다: `ability_activated(ability)`, `ability_failed(ability, reason)`, `cooldown_started(ability, duration)`, `cooldown_finished(ability)`. 런타임에 `grant(ability)`로 새 어빌리티를 부여하고 `try_activate(ability_name)`로 발동한다.

- **이펙트 계층 — 스탯 수정자, 버프/디버프, 게임플레이 태그:** 어빌리티는 시전자의 `StatSet`(이름 붙은 `StatModifier` 엔트리 딕셔너리를 소유하는 Resource)을 읽고 쓰며 일시적 또는 영구적 스탯 변경을 적용할 수 있다. 시전자의 자식인 `GameplayTagContainer` 노드가 발동을 게이트한다 — 예를 들어 "stunned" 태그는 어떤 어빌리티도 발동하지 못하게 막는다.
**핵심 규칙:** *데이터는 Resource에, 동작은 컴포넌트에, 통신은 시그널로.*

이 분리 덕분에 `Ability` 리소스는 Node 참조를 전혀 갖지 않으며, 다른 Godot Resource처럼 안전하게 복제·저장·로드할 수 있다. `AbilityComponent`가 런타임 상태(쿨다운 타이머, 활성 어빌리티 집합)를 소유하므로 `Ability` 리소스는 상태를 갖지 않고 여러 시전자에서 동시에 재사용될 수 있다.

---

## 2. 어빌리티 (비용 / 쿨다운 / 시전)

### GDScript

```gdscript
# ability.gd
class_name Ability
extends Resource

@export var ability_name: String
@export var cost: float = 0.0
@export var cooldown: float = 1.0
@export var cast_time: float = 0.0

# Override in subclasses or compose via exported effect resources.
func can_activate(caster: Node) -> bool:
    return true

func activate(caster: Node) -> void:
    pass
```

```gdscript
# ability_component.gd
class_name AbilityComponent
extends Node

signal ability_activated(ability: Ability)
signal ability_failed(ability: Ability, reason: String)
signal cooldown_started(ability: Ability, duration: float)
signal cooldown_finished(ability: Ability)

@export var resource_pool: float = 100.0

var _granted: Dictionary = {}        # ability_name -> Ability
var _cooldowns: Dictionary = {}      # ability_name -> seconds remaining

func grant(ability: Ability) -> void:
    _granted[ability.ability_name] = ability

func _process(delta: float) -> void:
    for name in _cooldowns.keys():
        _cooldowns[name] -= delta
        if _cooldowns[name] <= 0.0:
            _cooldowns.erase(name)
            if _granted.has(name):
                cooldown_finished.emit(_granted[name])

func try_activate(ability_name: String) -> bool:
    var ability: Ability = _granted.get(ability_name)
    if ability == null:
        return false
    if _cooldowns.has(ability_name):
        ability_failed.emit(ability, "on_cooldown")
        return false
    if resource_pool < ability.cost:
        ability_failed.emit(ability, "insufficient_resource")
        return false
    if not ability.can_activate(get_parent()):
        ability_failed.emit(ability, "conditions_unmet")
        return false
    resource_pool -= ability.cost
    ability.activate(get_parent())
    _cooldowns[ability_name] = ability.cooldown
    cooldown_started.emit(ability, ability.cooldown)
    ability_activated.emit(ability)
    return true
```

### C#

```csharp
// Ability.cs
using Godot;

[GlobalClass]
public partial class Ability : Resource
{
    [Export] public string AbilityName { get; set; } = "";
    [Export] public float Cost { get; set; } = 0.0f;
    [Export] public float Cooldown { get; set; } = 1.0f;
    [Export] public float CastTime { get; set; } = 0.0f;

    public virtual bool CanActivate(Node caster) => true;
    public virtual void Activate(Node caster) { }
}
```

```csharp
// AbilityComponent.cs
using Godot;
using System.Collections.Generic;

public partial class AbilityComponent : Node
{
    [Signal] public delegate void AbilityActivatedEventHandler(Ability ability);
    [Signal] public delegate void AbilityFailedEventHandler(Ability ability, string reason);
    [Signal] public delegate void CooldownStartedEventHandler(Ability ability, float duration);
    [Signal] public delegate void CooldownFinishedEventHandler(Ability ability);

    [Export] public float ResourcePool { get; set; } = 100.0f;

    private readonly Dictionary<string, Ability> _granted = new();
    private readonly Dictionary<string, float> _cooldowns = new();

    public void Grant(Ability ability) => _granted[ability.AbilityName] = ability;

    public override void _Process(double delta)
    {
        foreach (var name in new List<string>(_cooldowns.Keys))
        {
            _cooldowns[name] -= (float)delta;
            if (_cooldowns[name] <= 0.0f)
            {
                _cooldowns.Remove(name);
                if (_granted.TryGetValue(name, out var finished))
                    EmitSignal(SignalName.CooldownFinished, finished);
            }
        }
    }

    public bool TryActivate(string abilityName)
    {
        if (!_granted.TryGetValue(abilityName, out var ability)) return false;
        if (_cooldowns.ContainsKey(abilityName))
        {
            EmitSignal(SignalName.AbilityFailed, ability, "on_cooldown");
            return false;
        }
        if (ResourcePool < ability.Cost)
        {
            EmitSignal(SignalName.AbilityFailed, ability, "insufficient_resource");
            return false;
        }
        if (!ability.CanActivate(GetParent()))
        {
            EmitSignal(SignalName.AbilityFailed, ability, "conditions_unmet");
            return false;
        }
        ResourcePool -= ability.Cost;
        ability.Activate(GetParent());
        _cooldowns[abilityName] = ability.Cooldown;
        EmitSignal(SignalName.CooldownStarted, ability, ability.Cooldown);
        EmitSignal(SignalName.AbilityActivated, ability);
        return true;
    }
}
```

---

## 3. 버프 & 디버프 (시간 제한 이펙트)

이펙트는 `Resource` 서브클래스다 — 디자이너가 에디터에서 만들고 어빌리티가 적용한다. `EffectHolder` 노드가 런타임을 소유한다: 경과 시간을 추적하고, 주기적 틱을 호출하며, 만료되면 이펙트를 제거한다.

### GDScript

```gdscript
# effect.gd
class_name Effect
extends Resource

@export var effect_name: String
@export var duration: float = 5.0       # seconds; <= 0 means instant
@export var tick_interval: float = 0.0  # 0 = no periodic tick

func on_apply(target: Node) -> void: pass
func on_tick(target: Node) -> void: pass
func on_expire(target: Node) -> void: pass
```

```gdscript
# effect_holder.gd
class_name EffectHolder
extends Node

signal effect_applied(effect: Effect)
signal effect_expired(effect: Effect)

# effect -> [elapsed, tick_accum]
var _active: Dictionary = {}

func apply_effect(effect: Effect) -> void:
    effect.on_apply(get_parent())
    effect_applied.emit(effect)
    if effect.duration <= 0.0:
        effect.on_expire(get_parent())
        effect_expired.emit(effect)
        return
    _active[effect] = [0.0, 0.0]

func _process(delta: float) -> void:
    var to_remove: Array = []
    for effect in _active:
        _active[effect][0] += delta
        if effect.tick_interval > 0.0:
            _active[effect][1] += delta
            if _active[effect][1] >= effect.tick_interval:
                _active[effect][1] -= effect.tick_interval
                effect.on_tick(get_parent())
        if effect.duration > 0.0 and _active[effect][0] >= effect.duration:
            to_remove.append(effect)
    for effect in to_remove:
        _active.erase(effect)
        effect.on_expire(get_parent())
        effect_expired.emit(effect)
```

### C#

```csharp
// Effect.cs
using Godot;

[GlobalClass]
public partial class Effect : Resource
{
    [Export] public string EffectName { get; set; } = "";
    [Export] public float Duration { get; set; } = 5.0f;     // <= 0 = instant
    [Export] public float TickInterval { get; set; } = 0.0f; // 0 = no tick

    public virtual void OnApply(Node target) { }
    public virtual void OnTick(Node target) { }
    public virtual void OnExpire(Node target) { }
}
```

```csharp
// EffectHolder.cs
using Godot;
using System.Collections.Generic;

public partial class EffectHolder : Node
{
    [Signal] public delegate void EffectAppliedEventHandler(Effect effect);
    [Signal] public delegate void EffectExpiredEventHandler(Effect effect);

    private readonly Dictionary<Effect, (float Elapsed, float TickAccum)> _active = new();

    public void ApplyEffect(Effect effect)
    {
        effect.OnApply(GetParent());
        EmitSignal(SignalName.EffectApplied, effect);
        if (effect.Duration <= 0f)
        {
            effect.OnExpire(GetParent());
            EmitSignal(SignalName.EffectExpired, effect);
            return;
        }
        _active[effect] = (0f, 0f);
    }

    public override void _Process(double delta)
    {
        var toRemove = new List<Effect>();
        foreach (var effect in new List<Effect>(_active.Keys))
        {
            var (elapsed, tickAccum) = _active[effect];
            elapsed += (float)delta;
            if (effect.TickInterval > 0f)
            {
                tickAccum += (float)delta;
                if (tickAccum >= effect.TickInterval)
                {
                    tickAccum -= effect.TickInterval;
                    effect.OnTick(GetParent());
                }
            }
            if (effect.Duration > 0f && elapsed >= effect.Duration)
                toRemove.Add(effect);
            else
                _active[effect] = (elapsed, tickAccum); // still active — write back updated elapsed and tick accumulator
        }
        foreach (var effect in toRemove)
        {
            _active.Remove(effect);
            effect.OnExpire(GetParent());
            EmitSignal(SignalName.EffectExpired, effect);
        }
    }
}
```

> **함정(Footgun):** 엔트리를 제거하면서 `_active`를 직접 순회하지 마라. GDScript는 `to_remove` 리스트를 만들어 루프 뒤에 지우고, C#은 같은 이유로 `new List<Effect>(_active.Keys)`를 순회한다.

---

## 구현 체크리스트

- [ ] 어빌리티는 `Resource`다 — 동작은 데이터가 아니라 `AbilityComponent`에 있다.
- [ ] 발동은 자원을 소비하기 전에 비용, 쿨다운, `can_activate()`를 검증한다.
- [ ] 쿨다운은 `_process`/`_Process`에서 틱하며 시작/종료 시그널을 방출한다.
- [ ] 버프/디버프는 적용 → 틱 → 만료되고 시그널을 방출한다 — 지속시간은 소스별로 갱신되거나 누적된다.
- [ ] 스탯 수정자는 결정적으로 재계산되고(ADD → MULTIPLY → OVERRIDE) 클램프된다.
- [ ] 어빌리티 게이팅은 게임플레이 태그 컨테이너를 쓴다 — 면역은 이펙트를 막는다.
- [ ] HUD는 컴포넌트 시그널에 바인딩한다 — 쿨다운 상태를 매 프레임 폴링하지 않는다.
