---
name: resource-pattern
description: Godot에서 데이터 컨테이너를 만들 때 사용한다 — 설정, 아이템, 스탯을 위한 커스텀 Resource와 에디터 통합
---

# Godot 4.3+의 Resource 패턴

Resource는 Godot의 내장 데이터 컨테이너다. 설정, 아이템 정의, 캐릭터 스탯, 그리고 씬 트리 바깥에 존재하는 모든 데이터에 쓴다. 모든 예제는 Godot 4.3+를 대상으로 하며 폐기된 API를 쓰지 않는다.

> **관련 스킬:** Resource 기반 아이템 정의는 **inventory-system**, Resource 직렬화는 **save-load**, 데이터 주도 컴포넌트 설정은 **component-system**, 이 패턴 위에 세워진 Resource 기반 능력 정의는 **ability-system**을 참고하라.

---

## 1. Resource란 무엇인가

`Resource`는 참조 카운트되는 데이터 객체로:

- 디스크에 `.tres`(텍스트) 또는 `.res`(바이너리) 파일로 저장된다
- Godot 인스펙터에서 직접 편집할 수 있다
- **기본적으로 한 번 로드되어 공유된다** — 같은 경로를 로드하는 모든 노드가 동일한 메모리 내 객체를 얻는다
- 다른 Resource와 PackedScene 안에 중첩될 수 있다
- 씬 전환에도 살아남는다(씬 리로드 시 버려지는 Node 상태와 달리)

Resource는 기본적으로 공유되므로 읽기 전용 데이터(아이템 정의, 오디오 설정, 능력 청사진)에 이상적이다. 인스턴스별 가변 상태에는 `make_unique()`나 `duplicate()`를 호출하라 — 8절을 보라.

---

## 2. Resource를 언제 쓰나

| 사용 사례 | 예시 Resource | 대안 |
|---|---|---|
| 아이템 정의 | 이름·아이콘·값을 가진 `ItemData` | Dictionary(타입 안전성 상실) |
| 적 설정 | 체력·속도·데미지를 가진 `EnemyStats` | Node의 export 변수(재사용 불가) |
| 캐릭터 스탯 | 기본값을 가진 `CharacterStats` | 오토로드(전역 상태, 테스트 어려움) |
| 능력 정의 | 쿨다운·비용·효과를 가진 `AbilityData` | 하드코딩된 상수 |
| 레벨 메타데이터 | 음악·시간 제한·목표를 가진 `LevelConfig` | JSON(에디터 통합 없음) |
| 오디오 / 비주얼 테마 | 색 팔레트·폰트를 가진 `UIThemeData` | Theme 리소스(같은 발상, 내장) |
| 대화 트리 | 다음 줄을 참조하는 `DialogueLine` | JSON(타입 검사 없음) |

**인스펙터 편집 + 타입 지정 데이터 + 씬 간 공유**를 원할 때는 언제든 커스텀 Resource를 써라.

---

## 3. 기본 커스텀 Resource

### GDScript

```gdscript
# item_data.gd
class_name ItemData
extends Resource

enum ItemType { WEAPON, ARMOUR, CONSUMABLE, QUEST }

@export var name:        String   = ""
@export var description: String   = ""
@export var icon:        Texture2D
@export var value:       int      = 0
@export var item_type:   ItemType = ItemType.CONSUMABLE
```

에디터에서 인스턴스를 생성하라: FileSystem 패널에서 **우클릭** → **New Resource** → `ItemData` 선택. 인스펙터 필드를 채우고 `res://data/items/health_potion.tres`로 저장한다.

런타임에 로드:

```gdscript
var potion: ItemData = load("res://data/items/health_potion.tres")
print(potion.name)        # "Health Potion"
print(potion.value)       # 50
```

### C#

```csharp
// ItemData.cs
using Godot;

[GlobalClass]
public partial class ItemData : Resource
{
    public enum ItemType { Weapon, Armour, Consumable, Quest }

    [Export] public string   Name        { get; set; } = "";
    [Export] public string   Description { get; set; } = "";
    [Export] public Texture2D Icon       { get; set; }
    [Export] public int      Value       { get; set; } = 0;
    [Export] public ItemType Type        { get; set; } = ItemType.Consumable;
}
```

> C#에서는 에디터가 클래스를 인식하고 **New Resource**에 표시하도록 `[GlobalClass]`가 필요하다.

```csharp
var potion = GD.Load<ItemData>("res://data/items/health_potion.tres");
GD.Print(potion.Name);   // "Health Potion"
GD.Print(potion.Value);  // 50
```

---

## 4. 에디터 통합

`class_name`, `@tool`, `@icon`을 써서 커스텀 Resource를 인스펙터의 일급 시민으로 만들어라 — Resource 선택기에 나타나고, 우클릭 "New Resource"로 생성할 수 있으며, 커스텀 아이콘을 표시한다. `@export_group`과 `@export_subgroup`은 프로퍼티를 정리한다.
---

## 5. 설정으로서의 Resource

가장 강력한 사용 사례: 데이터 주도 게임 콘텐츠. 루트 테이블, 적 스탯, 능력 정의, 아이템 카탈로그가 모두 커스텀 Resource가 된다. 디자이너는 인스펙터에서 `.tres` 파일을 조정하고, 프로그래머는 로더를 배선한다. JSON의 느슨한 스키마와 문자열 타입 파싱을 피한다.
---

## 6. Resource 컬렉션

`@export var entries: Array[Entry] = []`는 인스펙터에 타입 지정 배열을 노출한다 — 여러 Resource 파일을 드래그 앤 드롭한다. 시작 시 로드되는 세트에는 `ResourcePreloader`를 써라. 런타임에 에셋 폴더를 탐색하려면 `DirAccess`를 순회하라.
---

## 7. Resource 대 Node

| 측면 | Resource | Node |
|---|---|---|
| 목적 | 데이터 저장과 설정 | 동작, 렌더링, 물리, 입력 |
| 씬 트리 | 트리에 없음 | 씬 트리에 존재 |
| 생명주기 훅 | 없음(`_init`만) | `_ready`, `_process`, `_physics_process` 등 |
| 공유 | 기본적으로 공유(같은 경로 = 같은 객체) | 각 인스턴스가 독립 |
| 직렬화 | `.tres` / `.res`로 저장, 인스펙터 편집 가능 | `.tscn` 안에 저장 |
| 시그널 | 지원 | 지원 |
| 용도 | 아이템 데이터, 스탯, 설정, 능력 청사진 | 플레이어, 적, UI 위젯, 카메라 |
| 피해야 할 것 | 매 프레임 갱신이나 씬 쿼리가 필요한 것 | 런타임에 절대 변하지 않는 정적 데이터 |

**경험칙:** 동작이 없고 씬 트리에 존재할 필요가 없다면 Resource로 만들어라. 움직이거나, 렌더하거나, 입력을 받거나, 매 프레임 로직을 돌려야 한다면 Node로 만들어라.

---

## 8. 공유 대 고유

기본적으로 Resource는 참조로 공유된다. `res://items/sword.tres`를 참조하는 두 씬은 동일한 인스턴스를 본다 — 하나를 변경하면 둘 다 변한다. 인스턴스별 상태에는 `.duplicate()`(얕은 복사) 또는 `.duplicate(true)`(깊은 복사)를 써라.
---

## 9. 커스텀 Resource 저장

`ResourceSaver.save(resource, path)`는 `.tres`(텍스트) 또는 `.res`(바이너리) 파일로 쓴다. 강한 타이핑을 원할 때 세이브 게임(스키마가 Resource 서브클래스로 코드에 존재)에 손수 만든 JSON 대신 쓴다.
---

## 10. 안티패턴

### `duplicate()` 없는 가변 공유 Resource — 의도치 않은 공유 상태

```gdscript
# BAD — all enemies share the same EnemyStats object.
# Damaging one enemy damages all of them.
class_name Enemy
extends CharacterBody2D

@export var stats: EnemyStats  # loaded from .tres, shared

func take_damage(amount: int) -> void:
    stats.health -= amount  # mutates the shared Resource!
```

```gdscript
# GOOD — each enemy owns its own copy.
func _ready() -> void:
    stats = stats.duplicate()  # now safe to mutate
```

### Resource 안의 게임 로직

```gdscript
# BAD — Resources have no scene tree access, no _process, no signals from nodes.
class_name EnemyStats
extends Resource

func update_health_regen(delta: float) -> void:
    # Can't call get_tree(), can't read Input, can't access nodes.
    # This logic belongs in a Node.
    health = min(health + regen_rate * delta, max_health)
```

```gdscript
# GOOD — keep logic in Nodes, data in Resources.
# enemy.gd
func _process(delta: float) -> void:
    _current_health = minf(_current_health + stats.regen_rate * delta, stats.max_health)
```

### 거대한 단일 Resource

```gdscript
# BAD — one Resource holds everything; impossible to reuse parts.
class_name GameConfig
extends Resource

@export var player_health: int
@export var player_speed: float
@export var enemy_goblin_health: int
@export var enemy_goblin_speed: float
@export var enemy_troll_health: int
# ... 200 more properties
```

```gdscript
# GOOD — small focused Resources, composed together.
class_name PlayerConfig
extends Resource

@export var health: int   = 100
@export var speed:  float = 200.0
```

```gdscript
class_name EnemyConfig
extends Resource

@export var health: int   = 50
@export var speed:  float = 80.0
```

```csharp
// ❌ Anti-pattern: mutating a shared Resource — accidental shared state
// All enemies share the same EnemyStats object loaded from the .tres file.
// Damaging one enemy damages all of them.
[GlobalClass]
public partial class Enemy : CharacterBody2D
{
    [Export] public EnemyStats Stats;  // loaded from .tres, shared by default

    public void TakeDamage(int amount)
    {
        Stats.Health -= amount;  // mutates the shared Resource — affects every Enemy!
    }
}

// ✅ Correct: duplicate before mutating so each instance owns its own copy.
public partial class EnemyGood : CharacterBody2D
{
    [Export] public EnemyStats Stats;

    public override void _Ready()
    {
        Stats = (EnemyStats)Stats.Duplicate();  // now safe to mutate independently
    }

    public void TakeDamage(int amount)
    {
        Stats.Health -= amount;  // only affects this instance
    }
}

// ❌ Anti-pattern: game logic inside a Resource
// Resources have no scene-tree access, no _Process, and cannot call GetTree() or read Input.
[GlobalClass]
public partial class EnemyStatsBad : Resource
{
    [Export] public float Health    { get; set; }
    [Export] public float MaxHealth { get; set; }
    [Export] public float RegenRate { get; set; }

    // This logic belongs in a Node, not a Resource.
    public void UpdateHealthRegen(double delta)
    {
        // Cannot call GetTree(), cannot access nodes, cannot read Input.
        Health = Mathf.Min(Health + RegenRate * (float)delta, MaxHealth);
    }
}

// ✅ Correct: keep logic in Nodes, data in Resources.
public partial class EnemyCorrect : CharacterBody2D
{
    [Export] public EnemyStats Stats;
    private float _currentHealth;

    public override void _Ready()
    {
        Stats = (EnemyStats)Stats.Duplicate();
        _currentHealth = Stats.MaxHealth;
    }

    public override void _Process(double delta)
    {
        _currentHealth = Mathf.Min(_currentHealth + Stats.RegenRate * (float)delta, Stats.MaxHealth);
    }
}

// ❌ Anti-pattern: giant monolithic Resource
// One Resource holds everything; impossible to reuse individual pieces.
[GlobalClass]
public partial class GameConfigBad : Resource
{
    [Export] public int   PlayerHealth      { get; set; }
    [Export] public float PlayerSpeed       { get; set; }
    [Export] public int   EnemyGoblinHealth { get; set; }
    [Export] public float EnemyGoblinSpeed  { get; set; }
    [Export] public int   EnemyTrollHealth  { get; set; }
    // ... 200 more properties
}

// ✅ Correct: small focused Resources, composed together.
[GlobalClass]
public partial class PlayerConfig : Resource
{
    [Export] public int   Health { get; set; } = 100;
    [Export] public float Speed  { get; set; } = 200.0f;
}

[GlobalClass]
public partial class EnemyConfig : Resource
{
    [Export] public int   Health { get; set; } = 50;
    [Export] public float Speed  { get; set; } = 80.0f;
}
```

---

## 11. 체크리스트

- [ ] Resource 서브클래스가 `class_name`을 써서 에디터가 **New Resource**에서 찾을 수 있다
- [ ] C# 클래스에 `[GlobalClass]` 어트리뷰트가 있다
- [ ] 모든 인스펙터 편집 가능 필드가 `@export` / `[Export]`를 쓴다
- [ ] 디자이너가 조정할 범위가 있는 숫자 필드에 `@export_range`를 썼다
- [ ] 필드가 많은 Resource의 인스펙터 레이아웃 정리에 `@export_group`과 `@export_category`를 썼다
- [ ] 인스턴스별 가변 Resource는 `_ready()`에서 `duplicate()`된다
- [ ] 읽기 전용 공유 Resource(정의, 청사진)는 복제하지 **않는다**
- [ ] 게임 로직(매 프레임 갱신, 씬 쿼리)은 Resource가 아니라 Node에 있다
- [ ] 큰 데이터 세트는 단일 책임 Resource로 쪼갠다
- [ ] 개발 중에는 `.tres`를 쓰고, 출시 프로덕션 데이터에는 `.res`를 고려한다
- [ ] `ResourceSaver.save()` 반환값을 확인하고 에러를 `push_error()`로 보고한다
- [ ] `.tres` / `.res` 파일을 신뢰할 수 없는 외부 출처에서 절대 로드하지 않는다
