---
name: gdscript-patterns
description: GDScript를 쓸 때 사용한다 — 정적 타이핑, await/코루틴, 람다, match 패턴, export 어노테이션, 내부 클래스, 흔한 관용구
---

# Godot 4.3+ GDScript 패턴

모든 예제는 Godot 4.3+ 대상이며 폐기된(deprecated) API를 쓰지 않는다.

> **관련 스킬:** 프로덕션 수준 깊이(성능 관용구, 메타프로그래밍, @tool 생명주기, 프로파일러 기반 관용구)는 **gdscript-advanced**, 스타일 규칙과 안티패턴은 **godot-code-review**, GDScript→C# 번역은 **csharp-godot**, 상태 패턴은 **state-machine**, 시그널 아키텍처는 **event-bus**.

> **참고:** 이 스킬은 설계상 GDScript 전용이다. C# 패턴은 **csharp-godot**와 **csharp-signals**를 보라.

---

## 1. 정적 타이핑

### 타입 힌트

항상 타입 힌트를 붙여라 — 파싱 시점에 버그를 잡고, 자동완성을 개선하고, 성능을 높인다.

```gdscript
# Variables
var health: int = 100
var speed: float = 200.0
var player_name: String = "Hero"
var direction: Vector2 = Vector2.ZERO

# Constants
const MAX_HEALTH: int = 100
const GRAVITY: float = 980.0

# Functions — parameters and return type
func take_damage(amount: int) -> void:
    health -= amount

func get_direction() -> Vector2:
    return Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

# Inferred typing with :=
var pos := Vector2(100, 200)     # inferred as Vector2
var items := []                  # inferred as Array (untyped)
var count := 0                   # inferred as int
```

### 타입 컬렉션

```gdscript
# Typed arrays — only accepts the specified type
var enemies: Array[Enemy] = []
var scores: Array[int] = [10, 20, 30]
var names: Array[String] = ["Alice", "Bob"]

# Typed dictionaries (Godot 4.4+)
var inventory: Dictionary[String, int] = {"sword": 1, "potion": 5}

# Typed loop variable
for enemy: Enemy in enemies:
    enemy.take_damage(10)

# Typed array methods work with type safety
var filtered: Array[Enemy] = enemies.filter(func(e: Enemy) -> bool: return e.health > 0)
```

### `as`와 `is`로 캐스팅

```gdscript
# 'is' — type check (returns bool)
func _on_body_entered(body: Node2D) -> void:
    if body is Player:
        var player: Player = body as Player
        player.take_damage(10)

# 'as' — cast (returns null on failure, no error)
var sprite := get_node("Sprite") as Sprite2D
if sprite:
    sprite.modulate = Color.RED

# Prefer 'is' check + cast over bare 'as' to avoid null surprises
```

### 엄격한 타이핑 경고 켜기

**Project > Project Settings > Debug > GDScript**에서:

| 경고                 | 효과                                      |
|-------------------------|---------------------------------------------|
| `UNTYPED_DECLARATION`   | 타입 없는 변수/파라미터에 경고     |
| `INFERRED_DECLARATION`  | `:=`에 경고(명시 타입 선호)      |
| `UNSAFE_CAST`           | 안전하지 않은 `as` 캐스트에 경고                  |
| `UNSAFE_CALL_ARGUMENT`  | 함수에 잘못된 타입을 넘길 때 경고 |

> 팀 프로젝트에서 엄격히 강제하려면 경고를 **Error**로 설정하라.

### 오버라이드에서의 타입 반환 상속

> ⚠️ **Godot 4.7에서 변경:** 타입 반환을 가진 메서드를 오버라이드하는 메서드는 이제 반환 타입을 상속하므로, 명시적 `return` 문 없는 오버라이드는 에러가 된다. 오버라이드 끝에 `return null`(또는 타입 반환 값)을 추가하라. [4.7 마이그레이션 가이드](https://docs.godotengine.org/en/latest/tutorials/migrating/upgrading_to_godot_4.7.html) 참조.

```gdscript
class Enemy:
    var weapon: Node
    func get_weapon() -> Node:
        return weapon

class UnarmedEnemy extends Enemy:
    func get_weapon():  # 4.7+: inherits -> Node from Enemy
        return null     # explicit return now required — omitting it is an error
```

---

## 2. Await & 코루틴

### 신호 await

`await`는 신호가 발화할 때까지 함수를 멈추고, 그 뒤 재개한다. 함수는 코루틴이 된다.

```gdscript
func death_sequence() -> void:
    $AnimationPlayer.play("death")
    await $AnimationPlayer.animation_finished  # pauses here

    $Sprite2D.visible = false
    await get_tree().create_timer(1.0).timeout  # wait 1 second

    queue_free()
```

### 반환 값과 함께 await

```gdscript
# Signal that passes data
signal dialogue_choice_made(choice: int)

func show_dialogue(options: Array[String]) -> int:
    # ... display UI ...
    var choice: int = await dialogue_choice_made
    return choice

# Caller:
func _on_npc_interact() -> void:
    var result := await show_dialogue(["Yes", "No"])
    if result == 0:
        print("Player said yes")
```

### 타이머 패턴

```gdscript
# One-shot delay
await get_tree().create_timer(0.5).timeout

# Repeating with await (simple but blocks the function)
for i in 5:
    do_something()
    await get_tree().create_timer(0.2).timeout

# Non-blocking timer — use SceneTreeTimer or Tween instead
get_tree().create_timer(2.0).timeout.connect(_on_delayed_action)
```

### 코루틴 안전

```gdscript
# DANGER: node may be freed while awaiting
func unsafe_coroutine() -> void:
    await get_tree().create_timer(5.0).timeout
    position = Vector2.ZERO  # crash if node was freed during wait!

# SAFE: check validity after await
func safe_coroutine() -> void:
    await get_tree().create_timer(5.0).timeout
    if not is_instance_valid(self):
        return
    position = Vector2.ZERO
```

---

## 3. 람다 함수

람다는 인라인 익명 함수로, 콜백·정렬·필터링에 유용하다.

### 기본 문법

```gdscript
# Single-expression lambda
var double := func(x: int) -> int: return x * 2

# Multi-line lambda
var greet := func(name: String) -> void:
    print("Hello, %s!" % name)
    print("Welcome!")

# Calling a lambda
double.call(5)  # returns 10
greet.call("Player")
```

### 시그널과 함께

```gdscript
# Inline signal connection (one-off use)
$Button.pressed.connect(func(): print("Button pressed!"))

# With arguments
$Timer.timeout.connect(func():
    health -= 1
    if health <= 0:
        die()
)

# One-shot connection (auto-disconnects after first call)
$Timer.timeout.connect(func(): print("Once!"), CONNECT_ONE_SHOT)
```

### 배열 메서드와 함께

```gdscript
var numbers: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8]

# Filter — keep elements where lambda returns true
var evens: Array[int] = numbers.filter(func(n: int) -> bool: return n % 2 == 0)
# [2, 4, 6, 8]

# Map — transform each element
var doubled: Array[int] = numbers.map(func(n: int) -> int: return n * 2)
# [2, 4, 6, 8, 10, 12, 14, 16]

# Reduce — accumulate into single value
var total: int = numbers.reduce(func(acc: int, n: int) -> int: return acc + n, 0)
# 36

# Any / All
var has_negative: bool = numbers.any(func(n: int) -> bool: return n < 0)
var all_positive: bool = numbers.all(func(n: int) -> bool: return n > 0)

# Sort with custom comparison
var items: Array[Dictionary] = [{"name": "B", "value": 2}, {"name": "A", "value": 1}]
items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["value"] < b["value"])
```

### 클로저 (변수 캡처)

```gdscript
func create_counter(start: int) -> Callable:
    var count := start
    return func() -> int:
        count += 1
        return count

var counter := create_counter(0)
print(counter.call())  # 1
print(counter.call())  # 2
```

---

## 4. Match / 패턴 매칭

GDScript의 `match`는 `switch`와 비슷하지만 패턴을 지원한다.

### 기본 Match

```gdscript
match state:
    State.IDLE:
        play_idle()
    State.RUNNING:
        play_run()
    State.JUMPING, State.FALLING:  # multiple patterns
        play_air()
    _:  # default (wildcard)
        push_warning("Unknown state: %s" % state)
```

### 패턴 타입

```gdscript
# Literal patterns
match value:
    42:
        print("The answer")
    "hello":
        print("Greeting")
    true:
        print("Boolean true")

# Binding pattern — captures value into a variable
match command:
    ["move", var direction]:
        move(direction)
    ["attack", var target, var damage]:
        attack(target, damage)

# Array pattern
match input:
    [1, 2, 3]:
        print("Exact match")
    [1, ..]:
        print("Starts with 1")
    [var first, _, var last]:
        print("First: %s, Last: %s" % [first, last])

# Dictionary pattern
match event:
    {"type": "damage", "amount": var amt}:
        take_damage(amt)
    {"type": "heal", "amount": var amt}:
        heal(amt)

# Nested condition inside a branch
match enemy_type:
    "boss":
        if health < 50:
            enter_rage_mode()
        else:
            normal_attack()
```

---

## 5. Export 어노테이션

`@export`는 변수를 인스펙터에 노출한다. 힌트 변형(`@export_range`, `@export_enum`, `@export_file`)은 에디터 입력을 제약한다. `@export_group`과 `@export_subgroup`으로 정리하라. 노드와 Resource export는 NodePath / 타입 Resource 참조를 쓴다.

---

## 6. 내부 클래스 & class_name

### class_name

스크립트를 전역 클래스 이름으로 등록한다 — `preload` 없이 어디서든 쓸 수 있다.

```gdscript
# item_data.gd
class_name ItemData
extends Resource

@export var name: String
@export var icon: Texture2D
@export var value: int

# Now usable anywhere:
# var item: ItemData = ItemData.new()
# var items: Array[ItemData] = []
```

### 내부 클래스

```gdscript
# Define a class inside another script
class HitResult:
    var damage: int
    var critical: bool
    var knockback: Vector2

    func _init(dmg: int, crit: bool, kb: Vector2 = Vector2.ZERO) -> void:
        damage = dmg
        critical = crit
        knockback = kb

# Usage
func calculate_hit() -> HitResult:
    var crit := randf() < 0.2
    var dmg := 10 * (2 if crit else 1)
    return HitResult.new(dmg, crit, Vector2.RIGHT * 50)
```

---

## 7. 가상 메서드에서의 super()

엔진이 부르는 가상 메서드(`_ready`, `_process`, `_input` 등)를 오버라이드하는데 부모 클래스도 그것을 구현했다면, `super()`를 불러 부모의 동작을 이어라. `super._ready()` 호출을 빠뜨리는 것이 "내 베이스 클래스 init이 실행 안 됐다" 버그의 가장 흔한 원인이다.

---

## 8. 흔한 관용구

반복되는 작은 패턴들: 삼항 표현식(`value if cond else other`), printf 스타일 문자열 포매팅(`"%s %d" % [a, b]`), null/빈 검사(`is_instance_valid` vs `!= null`, 빈 Array/String 검사), Dictionary 접근(`get(key, default)`), Array 연산(`Array.has`, `Array.find`, `Array.has_all`), `set`과 `get` 접근자를 통한 setget.

---

## 9. 어노테이션 레퍼런스

| 어노테이션            | 용도                                    |
|-----------------------|--------------------------------------------|
| `@export`             | 인스펙터에 변수 노출               |
| `@export_range`       | 슬라이더가 있는 숫자                        |
| `@export_enum`        | 문자열 목록에서 드롭다운                 |
| `@export_file`        | 파일 경로 선택기                           |
| `@export_dir`         | 디렉터리 선택기                           |
| `@export_multiline`   | 여러 줄 텍스트 상자                        |
| `@export_group`       | 인스펙터의 그룹 헤딩                 |
| `@export_subgroup`    | 하위 그룹 헤딩                            |
| `@export_category`    | 카테고리 구분선                          |
| `@onready`            | 노드가 트리에 들어올 때, `_ready()` 본문 직전에 초기화 |
| `@tool`               | 에디터에서 스크립트 실행                       |
| `@icon`               | 스크립트용 커스텀 아이콘                 |
| `@warning_ignore`     | 다음 줄의 특정 경고 억제     |
| `@static_unload`      | 정적 변수 해제 허용         |

---

## 10. 흔한 함정

| 증상                               | 원인                                       | 해결                                                              |
|---------------------------------------|----------------------------------------------|------------------------------------------------------------------|
| `as` 캐스트가 조용히 `null` 반환     | 타입 불일치 — `as`는 에러를 안 낸다          | 먼저 `is`로 검사한 뒤 캐스트                                  |
| Await가 절대 재개 안 됨                   | 신호가 발화 안 됐거나 노드가 해제됨          | await 후 `is_instance_valid(self)` 검사; 신호가 발화하는지 확인 |
| 람다가 오래된 변수를 캡처        | 루프 변수가 참조로 캡처됨          | 람다 전에 지역 변수로 복사: `var local := i`                |
| `UNTYPED_DECLARATION` 경고 폭주  | 경고는 켜졌지만 코드베이스가 타입 미지정     | 점진적으로 타입 붙이기; 레거시 코드엔 `@warning_ignore`        |
| 타입 배열이 유효한 항목을 거부       | 항목 타입이 정확히 일치하지 않음              | 항목이 선언된 타입과 일치하게 하라(암묵적 업캐스팅 없음)     |
| `@onready`가 `null`                  | `_ready()` 실행 전에 접근됨              | `_init()`이나 변수 선언에서 `@onready` 변수에 절대 접근 마라 |
| Match가 아무 분기도 안 탐        | 매칭 패턴이 없고 `_:` 와일드카드도 없음     | 항상 `_:` 기본 분기를 추가하라                                   |
| `class_name` 충돌                 | 두 스크립트가 같은 `class_name`을 가짐           | 고유 이름을 써라; Project에서 중복 확인            |
| Export 그룹이 잘못된 변수에 적용     | 그룹 스코프가 다음 그룹까지 계속됨       | 그룹 스코프를 끝내려면 새 `@export_group("")`를 추가하라       |
| 부모 `_ready()` 로직이 자식에서 실행 안 됨 | 자식의 `_ready()`에 `super()` 호출 누락 | 첫 줄에 `super()` 추가; 7절 참조 |
| `type_exists()`가 폐기로 표시됨 | Godot 4.7에서 폐기됨                      | 대신 `ClassDB.class_exists()`를 써라                             |

> ⚠️ **Godot 4.7에서 변경:** 전역 `type_exists()` 함수가 폐기됐다 — `type_exists("Sprite2D")`를 `ClassDB.class_exists("Sprite2D")`로 바꿔라. [GH-116899](https://github.com/godotengine/godot/pull/116899) 참조.

---

## 12. 가변 인자 함수 (Godot 4.5+)

Godot 4.5는 `...args`로 후행 인자 배열을 추가했다. 인자들은 `Array`로 수집된다. 오버로드 없이 printf 스타일 헬퍼와 유연한 API에 유용하다.

---

## 13. 추상 클래스와 메서드 (Godot 4.5+)

`@abstract` 어노테이션은 클래스의 직접 인스턴스화를 막고, 서브클래스가 `@abstract`로 표시된 메서드를 구현하도록 강제한다(C#의 `abstract` 키워드와 유사).

---

## 11. 구현 체크리스트

- [ ] 모든 변수, 파라미터, 반환 타입에 명시적 타입 힌트가 있다
- [ ] 가능한 곳에서 타입 미지정 `Array` 대신 타입 배열(`Array[Type]`)을 쓴다
- [ ] 노드가 해제될 수 있는 경우 `await` 호출 뒤에 `is_instance_valid(self)` 검사가 따른다
- [ ] 신호에 연결된 람다는 단순하다 — 복잡한 로직은 이름 있는 메서드로
- [ ] `match` 문에 `_:` 기본 분기가 들어 있다
- [ ] `@export` 변수가 적절한 힌트(`@export_range`, `@export_enum` 등)를 쓴다
- [ ] `@export_group`이 인스펙터 프로퍼티를 논리적 섹션으로 정리한다
- [ ] `class_name`은 전역 가시성이 필요한 스크립트에만 쓴다
- [ ] 타입이 보장되지 않을 때 `as` 캐스트 앞에 `is` 타입 검사가 온다
- [ ] 세터가 있는 프로퍼티는 값을 검증하고 clamp한다
- [ ] 오버라이드한 가상 메서드가 내장이 아닌 베이스 클래스를 확장할 때 `super()`를 부른다
- [ ] 후행 인자 개수가 열려 있을 때 가변 인자 함수(`...args`)를 쓴다 (Godot 4.5+)
- [ ] 인스턴스화되면 안 되는 베이스 클래스는 `@abstract`를 쓰고, 필수 메서드는 `@abstract func`를 쓴다 (Godot 4.5+)
