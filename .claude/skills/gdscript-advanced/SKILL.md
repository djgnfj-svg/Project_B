---
name: gdscript-advanced
description: 프로덕션 수준의 GDScript를 쓸 때 사용한다 — 성능 관용구, 메타프로그래밍, @tool 생명주기, async 함정, signal/Callable 트레이드오프, 프로파일러 기반 관용구, 흔한 함정
---

# GDScript Advanced

프로덕션 수준의 GDScript 깊이 — 언어를 배우기 위한 것이 아니라 게임을 출시하기 위한 것이다. 기초는 **gdscript-patterns**와 함께 보라.

> **관련 스킬:** 언어 기초는 **gdscript-patterns**, 엔진 쪽 성능 작업은 **godot-optimization**, 런타임 진단은 **godot-debugging**, C# 대안은 **csharp-godot**.

> **의도:** 이 스킬은 설계상 GDScript 전용이다(허용 목록). C# 사용자는 `csharp-godot`를 읽어야 한다. 여기에 C# 대응을 더하면 대상 분리가 무너진다.

## 1. 언제 고급 GDScript로 가나

`gdscript-patterns`를 넘어선 때는:

- 프로파일러 병목에 부딪혀 어떤 관용구가 빠른지 알아야 할 때
- 에디터 툴을 짜면서 `@tool` 생명주기 정확성이 필요할 때
- `await` 데드락이나 `Callable` 수명 버그를 보고 있을 때
- 지뢰 없이 메타프로그래밍(이름으로 함수 호출, 동적 디스패치)이 필요할 때
- 실제 게임을 출시하려는데, 멀쩡해 보이지만 부하에서 깨지는 패턴을 피하고 싶을 때

이 스킬은 당신이 타입 파라미터, `@onready`, `await`, `match`, 람다(모두 `gdscript-patterns`에 있음)를 이미 안다고 가정한다.

## 2. 성능 관용구

**정적 변수와 메서드**(Godot 4.4+)는 인스턴스별 오버헤드를 피한다:

```gdscript
class_name Tally extends Node

static var _global_score: int = 0

static func add_score(amount: int) -> void:
    _global_score += amount

static func get_score() -> int:
    return _global_score
```

클래스의 정적 메서드로 될 일이면 싱글턴-오토로드를 피하라.

**Vector2i vs Vector2 / Vector3i vs Vector3** — 정수 벡터는 핫 패스(타일 좌표, 그리드 수학)에서 30~40% 더 빠르다. float로는 렌더링 경계에서만 변환하라:

```gdscript
var grid_pos: Vector2i = Vector2i(8, 12)              # cheap
var world_pos: Vector2 = Vector2(grid_pos) * TILE_SIZE  # convert at boundary
```

**PackedArray\* over generic Array** — `PackedInt32Array`, `PackedFloat32Array`, `PackedVector2Array` 등은 연속 메모리를 할당하고 Variant 박싱을 건너뛴다. 버퍼, 정점 배열, 핫 루프 누산기에 써라.

```gdscript
var positions: PackedVector3Array = PackedVector3Array()
positions.resize(1000)  # one allocation
for i in 1000:
    positions[i] = Vector3(i, 0, 0)
```

**타입 Dictionary 접근** — 타입 딕셔너리(Godot 4.4+)는 읽을 때마다 하는 Variant 언박싱을 건너뛴다:

```gdscript
var stats: Dictionary[String, int] = {}
stats["hp"] = 100  # no boxing
```

**`is_instance_valid` vs `null` 검사** — `is_instance_valid()`는 엔진 쪽 조회를 하고, `!= null`은 포인터 비교다. `@onready` 할당 이후에는 `!= null`을 선호하라. `is_instance_valid()`는 참조를 쥔 채 `queue_free`될 수 있는 노드에만 남겨 둬라.

> 흔한 함정: `_process`가 프레임마다 `if is_instance_valid(target)`를 한 번 하면 호출당 ~1µs를 태운다 — 호출당은 작지만 빠르게 곱해진다.

## 3. 메타프로그래밍

`Callable.bind`, `Callable.call`, `Callable.call_deferred`는 `Object.call(name)`의 보안 위험 없이 동적 디스패치를 준다.

**인자 바인딩:**

```gdscript
var greeter: Callable = print_named.bind("Player")
greeter.call()                    # prints "Hello, Player"

func print_named(name: String) -> void:
    print("Hello, %s" % name)
```

**지연 호출(deferred)** — 다음 프레임의 idle 단계에 실행되며, 크로스 스레드나 신호 폭주 안전에 유용하다:

```gdscript
heavy_recompute.call_deferred()
```

**`Object.set` / `Object.get` / `Object.has_method`** — 진짜 동적 코드(스크립트 리로드, 모딩)에:

```gdscript
if obj.has_method("on_damaged"):
    obj.call("on_damaged", 25)
```

> **보안 함정:** `user_string`이 세이브 파일, 네트워크, 모드 콘텐츠에서 온 것이라면 허용 목록 없이 `obj.call(user_string, ...)`를 절대 넘기지 마라. `call("queue_free")`는 공짜 크래시다. 알려진 집합에 대해 매칭하라:

```gdscript
const ALLOWED_RPCS: PackedStringArray = ["take_damage", "apply_buff", "set_position"]
if user_method in ALLOWED_RPCS and obj.has_method(user_method):
    obj.call(user_method, args)
```

## 4. `@tool` 생명주기

`@tool` 스크립트는 게임뿐 아니라 에디터에서도 실행된다. 두 가지 실패 모드가 지배적이다:
1. 에디터 전용 로직이 실수로 플레이 시점에 실행됨
2. 게임 로직이 실수로 에디터에서 실행돼 에디터를 크래시시킴

**가드:**

```gdscript
@tool
extends Node

func _ready() -> void:
    if Engine.is_editor_hint():
        _setup_editor_preview()
    else:
        _setup_game_runtime()
```

**에디터 알림(notification)** — 에디터 생명주기 이벤트(`NOTIFICATION_EDITOR_PRE_SAVE`, `NOTIFICATION_EDITOR_POST_SAVE`, `NOTIFICATION_PARENTED`)에는 `_notification`을 써라:

```gdscript
func _notification(what: int) -> void:
    if what == NOTIFICATION_EDITOR_PRE_SAVE:
        _bake_preview()
```

> 흔한 함정: 에디터 시점에 `get_tree().create_timer()`를 부르는 `@tool` 스크립트. 어떤 맥락에서는 에디터에 메인 루프가 없다 — `is_editor_hint()`로 가드하라.

## 5. async 함정

`await`는 신호 양보(signal-yielding)의 문법 설탕이다. 세 가지 함정 형태가 있다:

**함정 1 — `_ready` 안의 `await`**는 자식들의 ready 순서를 지연시킨다:

```gdscript
# BAD: children of this node ready BEFORE this _ready() finishes
func _ready() -> void:
    await get_tree().create_timer(1.0).timeout
    initialize_children()  # children already ready'd against an uninitialized parent
```

해결: `_ready`에서 `await`하지 마라. await를 별도 셋업 함수로 옮겨라.

**함정 2 — 절대 발화하지 않는 신호를 await**하면 호출 코루틴이 데드락된다:

```gdscript
# BAD if `health_changed` never fires (e.g., entity already at full HP)
await health.health_changed
```

해결: 타임아웃 경쟁을 써라:

```gdscript
var timer := get_tree().create_timer(2.0)
var winner := await Signal.any([health.health_changed, timer.timeout])
```

(또는 await 전에 선행 조건을 확인하라.)

**함정 3 — 해제된 객체를 참조하는 `Callable`** — await 도중 대기자가 해제되면 재개된 코루틴이 크래시한다. 엔진이 생명주기를 다루는 `await ToSignal()` 패턴을 써라.

## 6. Signal vs Callable 설계 선택

**Signal** — 다대다, 디커플링, 엣지 트리거. 연결 목록 조회에서 오는 약간의 emit당 오버헤드.

**Callable** — 일대일, 명시적, 레벨 트리거. 호출당은 더 싸지만 결합이 더 강하다.

시그널을 쓰는 경우:
- 크로스 시스템 이벤트(player_died, item_collected, level_complete)
- 게임플레이에서 오는 UI 갱신
- 0에서 N개의 리스너가 정상인 무엇이든

Callable을 쓰는 경우:
- 전략 주입(정렬 비교자, 술어 함수)
- 지연 작업 스케줄링(`call_deferred`)
- 트윈 메서드(`tween_method`는 Callable을 받는다)

> 흔한 함정: 람다를 신호에 연결하면 람다가 캡처한 환경을 영원히 저장한다. 캡처된 객체가 해제되면 경고가 뜬다. `_exit_tree`에서 명시적으로 disconnect하거나 바인딩된 메서드를 대신 써라.

## 7. 프로파일러 기반 관용구

**Debugger → Profiler** 패널을 연다. 가장 자주 나타나는 패턴:

| 프로파일러 핫 스팟 | 유력한 원인 | 해결 |
|---|---|---|
| `_process`의 `String` 할당 | 프레임마다 `print()` / `"%s" % var` | 루프 밖에서 미리 포맷하거나, 순환 버퍼로 로그를 배치 처리 |
| `Object.get_node`의 높은 self-time | 프레임마다 반복되는 `$Path/Sub/Node` | `@onready var`에 캐시 |
| `Signal.emit`의 높은 호출 수 | 프레임당 신호 폭주(예: 위치 갱신) | 10 Hz로 스로틀하거나 폴링 패턴 사용 |
| `CharacterBody.move_and_slide` self-time | 한 프레임에 많은 캐릭터 바디 | 카메라 거리로 스케일; 저렴한 감지에는 Area 사용 |
| GDScript GC 스파이크 | 임시 Array/String에서 오는 할당자 처닝 | 배열 풀링; 시작 시 사전 할당 |

## 8. 흔한 함정

**람다는 참조로 캡처한다** — 람다는 정의 시점 값이 아니라 캡처된 변수의 *현재* 값을 본다:

```gdscript
var callbacks: Array[Callable] = []
for i in 5:
    callbacks.append(func(): print(i))  # all five print 5 (or 4 — depends on engine)
```

해결: `bind`로 캡처하라:

```gdscript
for i in 5:
    callbacks.append((func(idx): print(idx)).bind(i))
```

**`@onready` 순서** — `@onready` 변수는 `_init` 후, `_ready` 전에 설정된다. 자식의 `_ready`가 부모의 `_ready`보다 먼저 실행된다. 그래서:
- 부모가 초기화됐다고 확신하지 않는 한 자식의 `_ready`에서 부모 상태를 참조하지 마라
- 크로스 노드 셋업은 부모가 자기 `_ready`에서 `child.setup_with(self)`를 부르는 편을 선호하라

**씬 리로드에 걸친 정적 변수 생명주기** — 클래스의 정적 변수는 씬이 아니라 *엔진*의 수명 동안 지속된다. 씬을 리로드해도 초기화되지 **않는다**. 씬별 싱글턴이 필요하면 정적 변수가 아니라 오토로드를 써라.

**Resource 공유의 함정** — `@export var item: ItemData`가 두 씬에서 같은 Resource 에셋을 쓰면 참조로 상태를 공유한다. 하나를 변경하면 다른 하나도 변경된다. 각 인스턴스가 자기 상태를 가져야 하면 `item.duplicate()`를 써라.

**Packed-array 프로퍼티 세터가 요소 쓰기를 건너뛴다**

> ⚠️ **Godot 4.7에서 변경:** packed-array 프로퍼티의 요소를 설정하는 것(예: `obj.packed_prop[i] = x`)이 더 이상 packed array 프로퍼티 전체의 세터를 부르지 않는다. 요소별 쓰기에 세터가 발화하는 데 의존한 코드는 조용히 깨진다 — 세터를 트리거하려면 배열 전체를 재할당하라. [4.7 마이그레이션 가이드](https://docs.godotengine.org/en/latest/tutorials/migrating/upgrading_to_godot_4.7.html) 참조.

```gdscript
var points: PackedVector2Array:
    set(value):
        points = value
        _rebuild_mesh()

func move_point() -> void:
    points[0] = Vector2.ONE    # 4.6: setter (and _rebuild_mesh) ran; 4.7+: it does NOT
    var updated := points      # fix: modify a copy...
    updated[0] = Vector2.ONE
    points = updated           # ...then reassign — the setter fires
```

> **Godot 4.7+:** 새 `CONFUSABLE_TEMPORARY_MODIFICATION` 경고는 임시(버려지는) 값을 수정하는 것을 표시한다 — 예: 복잡한 할당 체인이나 비-`const` 메서드 호출을 통해 변경된 내장 `Packed*Array` 프로퍼티에서, 임시 사본만 바뀌고 프로퍼티는 옛 값을 유지하는 경우. `debug/gdscript/warnings/confusable_temporary_modification`로 제어한다(기본 `1`, warn).

## 구현 체크리스트

- [ ] 어떤 성능 관용구가 적용되는지 파악했다(타입 벡터, PackedArray, 정적 메서드)
- [ ] 메타프로그래밍을 쓴다면 모든 동적 메서드 이름을 허용 목록에 넣었다
- [ ] `@tool`이라면 `Engine.is_editor_hint()`로 에디터 vs 런타임 분기를 가드했다
- [ ] `await` 호출을 데드락 위험(발화하지 않을 수 있는 신호)과 `_ready` 순서 버그에 대해 감사했다
- [ ] 트레이드오프 표에 따라 signal vs Callable을 골랐다; 람다는 `_exit_tree`에서 disconnect했다
- [ ] 최적화 전에 프로파일링했다; 핫 스팟을 7절 표에 맞췄다
- [ ] 람다 캡처, `@onready` 순서, 정적 변수 생명주기, Resource 공유, packed-array 프로퍼티 세터(Godot 4.7)를 나열된 함정에 대해 감사했다
