---
name: dependency-injection
description: 시스템 간 의존성을 관리할 때 쓴다 — 오토로드, 서비스 로케이터, @export 주입, 씬 주입 패턴
---

# Godot 4.3+ 의존성 주입

노드가 느슨하게 결합되고, 교체 가능하고, 테스트 가능하게 유지되도록 시스템 간 의존성을 연결하는 패턴들. 모든 예제는 Godot 4.3+를 대상으로 하며 폐기된 API를 쓰지 않는다.

> **관련 스킬:** 테스트 친화적 아키텍처는 **godot-testing**, 시그널 기반 결합 해제는 **event-bus**, 오토로드 등록은 **godot-project-setup**.

---

## 1. 문제

강한 결합은 코드를 테스트·확장·교체하기 어렵게 만든다. Godot에서 가장 흔한 형태는 코드베이스 전역에서 전역 오토로드에 직접 손을 뻗는 것이다.

```gdscript
# BAD — tight coupling via direct autoload access scattered everywhere

# player.gd
func take_damage(amount: int) -> void:
    health -= amount
    AudioManager.play_sfx("hurt")          # hard dependency on AudioManager
    UIManager.update_health_bar(health)    # hard dependency on UIManager
    if health <= 0:
        GameState.record_death()           # hard dependency on GameState

# enemy.gd
func attack() -> void:
    AudioManager.play_sfx("attack")        # same AudioManager dependency again
```

```csharp
// BAD — tight coupling via direct autoload / global access scattered everywhere

// Player.cs
public partial class Player : CharacterBody3D
{
    private int _health = 100;

    public void TakeDamage(int amount)
    {
        _health -= amount;
        GetNode<AudioManager>("/root/AudioManager").PlaySfx("hurt");        // hard dependency
        GetNode<UIManager>("/root/UIManager").UpdateHealthBar(_health);     // hard dependency
        if (_health <= 0)
            GetNode<GameState>("/root/GameState").RecordDeath();            // hard dependency
    }
}

// Enemy.cs
public partial class Enemy : CharacterBody3D
{
    public void Attack()
    {
        GetNode<AudioManager>("/root/AudioManager").PlaySfx("attack");      // same dependency again
    }
}
```

**이 접근법의 문제:**

- `AudioManager`를 직접 호출하는 모든 노드가 그 구체 구현에 결합된다.
- `AudioManager`를 다른 구현으로 교체하려면 모든 호출자를 바꿔야 한다.
- `Player`를 격리해 단위 테스트하기가 불가능하다 — `AudioManager`, `UIManager`, `GameState`가 모두 존재하고 유효해야 한다.
- 오토로드 초기화 순서 버그가 씬 로드 시 동작을 조용히 깨뜨린다.
- 숨은 의존성 때문에 클래스가 실제로 무엇을 필요로 하는지 보기 어렵다.

---

## 2. 접근법 비교

| 패턴 | 복잡도 | 테스트 용이성 | 적합한 경우 |
|---|---|---|---|
| **오토로드** | 낮음 | 낮음 | 진짜 전역 싱글톤: 오디오, 설정, 플랫폼 서비스 |
| **@export 주입** | 낮음 | 높음 | 대부분의 노드 — 에디터에서 의존성 연결, 런타임 조회 불필요 |
| **서비스 로케이터** | 중간 | 중간 | 플러그인, 선택적 시스템, 런타임에 교체 가능한 구현 |
| **씬 주입** | 낮음 | 높음 | 부모→자식 연결: Level이 Enemy를 설정, HUD가 하위 패널을 설정 |

---

## 3. 싱글톤으로서의 오토로드

전역 접근을 위해 **Project Settings → Autoload**에 스크립트를 등록하라(`AudioManager.play_sfx(...)`, `GameState.score = 100`). 횡단 관심사에 가장 적합하다: 오디오, 저장 상태, 이벤트 버스, 설정. 도메인 특화 시스템의 오토로드는 자제하라(그런 것은 씬 주입해야 한다).

---

## 4. @export 노드 주입

협력 노드를 `@export var health_component: HealthComponent`로 노출한 뒤, Inspector나 부모 씬에서 연결하라. 수명주기: `@export` 속성은 `_ready()` 전에 할당된다.

---

## 5. 서비스 로케이터 패턴

`String` 키를 서비스 인스턴스에 매핑하는 중앙 레지스트리 오토로드. 서비스는 `_ready()`에서 자신을 등록하고, `_exit_tree()`에서 등록 해제하며, 소비자는 `ServiceLocator.get(name)`을 호출한다. 구현을 런타임에 유연하게 교체하고 싶을 때 유용하다(테스트, 모드, A/B 변형).

---

## 6. 씬 주입

부모 씬이 자식을 로드한 뒤, `_ready()`에서 트리를 순회하며 의존성을 할당한다(`enemy.player = $Player`). 자식은 `@export` 속성을 선언하지만 Inspector가 아니라 부모가 설정한다. 레벨마다 바뀌는 게임 특화 의존성에 가장 적합하다.

---

## 7. 의존성 주입으로 테스트하기

가짜(fake)/테스트 더블을 주입하는 것이 노드를 테스트 가능하게 만든다. 오토로드의 경우: 테스트 씬이 로드되기 전에 목으로 교체한다. `@export` 주입의 경우: export를 테스트 더블로 교체한다. 서비스 로케이터의 경우: 같은 키로 가짜를 등록한다.

---

## 8. 무엇을 언제 쓰나

| 상황 | 권장 패턴 |
|---|---|
| 거의 모든 씬의 거의 모든 노드가 쓰는 서비스 | 오토로드 싱글톤 |
| 노드가 의존성 1~3개 필요, 씬이 에디터에서 저작됨 | `@export` 주입 |
| 시스템이 런타임에 선택적이거나 교체 가능 | 서비스 로케이터 |
| 부모 씬이 자식을 구성하고 그 필요를 앎 | 씬 주입 |
| 외부 의존성이 있는 노드의 테스트 작성 | `@export` 또는 속성 주입 + 스텁 |
| 어떤 프로젝트에서도 동작해야 하는 플러그인 | 서비스 로케이터(자기 등록, 가정 없음) |
| 형제 노드 둘이 같은 의존성을 필요로 함 | 부모가 쥐고 아래로 주입하게 함 |

**빠른 결정 가이드:**

```
Does every scene in the project need it?
  YES → Autoload singleton
  NO  ↓

Is the dependency known at edit-time and wired in the Inspector?
  YES → @export injection
  NO  ↓

Does the dependency need to be swapped at runtime (plugins, A/B testing)?
  YES → Service Locator
  NO  ↓

Does a parent scene own both the consumer and the dependency?
  YES → Scene injection
  NO  → Reconsider — either promote to autoload or restructure ownership
```

---

## 9. 안티패턴

### 모든 것을 오토로드로

```gdscript
# BAD — GameManager, EnemySpawner, InventorySystem, DialogueSystem all as autoloads.
# Every node in the game is coupled to every other system at module level.
# Test one component → must initialise all autoloads.

# GOOD — Only AudioManager, Settings, and SceneTransition are autoloads.
# EnemySpawner is a node in the Level scene, injected into enemies that need it.
```

```csharp
// BAD — GameManager, EnemySpawner, InventorySystem, DialogueSystem all as autoloads.
// Every node in the game is coupled to every other system at module level.
// Test one component → must initialise all autoloads.

// GOOD — Only AudioManager, Settings, and SceneTransition are autoloads.
// EnemySpawner is a node in the Level scene, injected into enemies that need it.
```

### 깊은 의존성 사슬

```gdscript
# BAD — Player needs HealthComponent, which needs AudioManager,
# which needs SoundBank, which needs FileSystem...
# A change deep in the chain breaks everything above it.

# GOOD — flatten: HealthComponent takes only AudioManager (or a narrow interface).
# Each node declares only immediate dependencies.
```

```csharp
// BAD — Player needs HealthComponent, which needs AudioManager,
// which needs SoundBank, which needs FileSystem...
// A change deep in the chain breaks everything above it.

// GOOD — flatten: HealthComponent takes only AudioManager (or a narrow interface).
// Each node declares only immediate dependencies.
```

### 순환 의존성

```gdscript
# BAD
# PlayerController._ready() calls ServiceLocator.get_service("inventory")
# InventorySystem._ready() calls ServiceLocator.get_service("player")
# Neither can fully initialise because the other isn't ready yet.

# GOOD — break the cycle with a signal.
# InventorySystem emits item_used; PlayerController connects to it.
# PlayerController never holds a reference to InventorySystem at all.
```

```csharp
// BAD
// PlayerController._Ready() calls ServiceLocator.GetService("inventory")
// InventorySystem._Ready() calls ServiceLocator.GetService("player")
// Neither can fully initialise because the other isn't ready yet.

// GOOD — break the cycle with a signal.
// InventorySystem emits ItemUsed; PlayerController connects to it.
// PlayerController never holds a reference to InventorySystem at all.
```

### 신(god) 객체가 된 서비스 로케이터

```gdscript
# BAD — everything is registered: enemies, UI panels, individual nodes.
# ServiceLocator becomes a second, untyped scene tree.

# GOOD — only register stable, long-lived services (audio, analytics, save system).
# Short-lived nodes are wired by their parent via scene injection.
```

```csharp
// BAD — everything is registered: enemies, UI panels, individual nodes.
// ServiceLocator becomes a second, untyped scene tree.

// GOOD — only register stable, long-lived services (audio, analytics, save system).
// Short-lived nodes are wired by their parent via scene injection.
```

### 주입 후 null 검사 누락

```gdscript
# BAD — crashes if the @export was never set in the editor
func take_damage(amount: int) -> void:
    audio.play_sfx("hurt")   # NullReferenceError if audio was not wired

# GOOD — guard or assert clearly
func take_damage(amount: int) -> void:
    assert(audio != null, "HealthComponent: audio dependency was not injected")
    audio.play_sfx("hurt")

# OR — treat it as optional
func take_damage(amount: int) -> void:
    if audio != null:
        audio.play_sfx("hurt")
```

```csharp
// BAD — crashes if the [Export] was never set in the editor
public void TakeDamage(int amount)
{
    _audio.PlaySfx("hurt");   // NullReferenceException if _audio was not wired
}

// GOOD — guard or assert clearly
public void TakeDamage(int amount)
{
    if (_audio == null)
    {
        GD.PushError("HealthComponent: audio dependency was not injected");
        return;
    }
    _audio.PlaySfx("hurt");
}

// OR — treat it as optional
public void TakeDamage(int amount)
{
    _audio?.PlaySfx("hurt");
}
```

---

## 10. 체크리스트

- [ ] 오토로드는 진짜 전역 서비스(오디오, 설정, 플랫폼)에만 사용됨
- [ ] 노드가 먼 친척에게 `get_node`를 호출하는 대신 의존성을 명시적으로 선언(`@export` 또는 public 속성)
- [ ] `@export` 필드가 사용 전 검증됨(`assert` 또는 null 검사)
- [ ] 서비스 로케이터 서비스가 `_exit_tree()` / `_ExitTree()`에서 `unregister`를 호출
- [ ] 씬 주입은 자식이 완전히 초기화된 뒤 부모의 `_ready()`에서 수행됨
- [ ] 서비스나 오토로드 간 순환 의존성 없음
- [ ] 각 노드가 직접 협력자에게만 의존 — 깊은 사슬 없음
- [ ] 테스트 스텁/목이 실제 서비스와 같은 인터페이스를 구현하는 평범한 노드
- [ ] C# `@export`(`[Export]`) 의존성이 이벤트 구독을 쥐고 있으면 `_ExitTree()`에서 끊거나 비움
- [ ] 서비스 로케이터를 씬 특화나 단명 노드 저장에 쓰지 않음
