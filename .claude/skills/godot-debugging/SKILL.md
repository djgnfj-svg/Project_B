---
name: godot-debugging
description: Godot 프로젝트를 디버깅할 때 사용한다 — 원격 디버거, print 기법, 시그널 추적, 흔한 오류 패턴과 해결
---

# Godot 디버깅

이 스킬은 GDScript와 C# 양쪽의 Godot 4.3+ 프로젝트를 위한 체계적 디버깅을 다룬다. print 기법, 브레이크포인트, 시그널 추적, 내장 프로파일러, 씬 트리 검사, 흔한 오류 패턴, 단계별 디버깅 체크리스트를 다룬다.

> **관련 스킬:** 성능 프로파일링은 **godot-optimization**, 수정 후 회귀 테스트는 **godot-testing**, C# 시그널 디버깅 패턴은 **csharp-signals**.

---

## 1. Print 디버깅

### GDScript

Godot은 용도가 다른 여러 print 함수를 제공한다. 로깅하는 대상의 심각도와 맥락에 따라 골라라.

```gdscript
# print() — general output, space-separated values
print("Player position: ", position)
print("Health: ", health, " / ", max_health)

# print_rich() — BBCode-formatted output in the Output panel
print_rich("[color=yellow]WARNING:[/color] Enemy count exceeded limit: ", enemy_count)
print_rich("[b]State:[/b] [color=green]", current_state, "[/color]")

# push_error() — logs an error with a full stack trace; does NOT stop execution
push_error("save_game: file path is empty")

# push_warning() — logs a warning with stack trace; use for recoverable issues
push_warning("AudioStreamPlayer: bus '%s' not found, using Master" % bus_name)

# print_debug() — only prints in debug builds; stripped from release exports
print_debug("Frame delta: ", delta, " | FPS: ", Engine.get_frames_per_second())

# printerr() — prints to stderr; visible in external terminals and CI logs
printerr("Critical: physics state corrupted at frame ", Engine.get_process_frames())
```

**포맷된 출력 패턴:**

```gdscript
# String formatting with % operator
print("Actor [%s] dealt %d damage to [%s]" % [name, damage, target.name])

# String.format() with named placeholders
var msg := "Position: ({x}, {y}) at speed {spd}"
print(msg.format({"x": position.x, "y": position.y, "spd": velocity.length()}))

# Printing arrays and dictionaries — use str() for clean output
var inventory := {"sword": 1, "potion": 3}
print("Inventory: ", str(inventory))

# Conditional verbose logging using a project-level constant or autoload flag
if DebugConfig.verbose_ai:
    print_rich("[color=cyan][AI][/color] ", agent.name, " chose action: ", chosen_action)
```

```csharp
// String interpolation
GD.Print($"Actor [{Name}] dealt {damage} damage to [{target.Name}]");

// Printing collections
var inventory = new Godot.Collections.Dictionary { { "sword", 1 }, { "potion", 3 } };
GD.Print("Inventory: ", inventory);

// Conditional verbose logging
if (DebugConfig.VerboseAi)
    GD.PrintRich($"[color=cyan][AI][/color] {agent.Name} chose action: {chosenAction}");
```

**각 함수를 언제 쓰나:**

| 함수 | 릴리스에서 보임 | 스택 트레이스 | 용도 |
|---|---|---|---|
| `print()` | 예(스트립되지 않으면) | 없음 | 일반 값 검사 |
| `print_rich()` | 예 | 없음 | 분류된, 색상 코드 로그 |
| `push_error()` | 예 | 있음 | 잘못된 상태, 프로그래머 오류 |
| `push_warning()` | 예 | 있음 | 복구 가능한 문제 |
| `print_debug()` | 아니오 | 없음 | 상세한 프레임 수준 출력 |
| `printerr()` | 예 | 없음 | 외부 터미널 / CI 출력 |

### C\#

```csharp
using Godot;

public partial class Player : CharacterBody3D
{
    public override void _Ready()
    {
        // GD.Print — equivalent to GDScript print()
        GD.Print("Player position: ", Position);

        // GD.PrintRich — BBCode formatted
        GD.PrintRich("[color=yellow]Ready called on[/color] ", Name);

        // GD.PushError — logs error with stack trace
        GD.PushError("_Ready: required child node missing");

        // GD.PushWarning — logs warning with stack trace
        GD.PushWarning("AudioBus not found, falling back to Master");

        // GD.PrintErr — writes to stderr
        GD.PrintErr("Critical failure in _Ready");
    }

    private void HandleDamage(int amount)
    {
        // Formatted string output
        GD.Print($"[{Name}] took {amount} damage. HP: {_health}/{_maxHealth}");
    }
}
```

---

## 2. 브레이크포인트와 원격 디버거

### 브레이크포인트 설정

- 스크립트 에디터에서 거터(줄 번호 왼쪽)를 클릭해 브레이크포인트를 토글한다. 빨간 점이 나타난다.
- `F9`로 현재 줄의 브레이크포인트를 토글한다.
- GDScript에서 `breakpoint`를 문(statement)으로 써서 프로그래밍적 브레이크포인트를 유발한다:

```gdscript
func _physics_process(delta: float) -> void:
    if velocity.length() > MAX_SPEED:
        breakpoint  # execution pauses here during debug runs
    move_and_slide()
```

- C#에서는 `System.Diagnostics.Debugger.Break()`를 쓰거나 .NET 디버거(예: JetBrains Rider나 Godot 확장이 있는 VS Code)를 붙인다.

```csharp
public override void _PhysicsProcess(double delta)
{
    if (Velocity.Length() > MaxSpeed)
    {
        System.Diagnostics.Debugger.Break(); // pause if .NET debugger is attached
    }
    MoveAndSlide();
}
```

### 내장 디버거 패널 사용

브레이크포인트에서 실행이 멈추면 **Debugger** 패널(에디터 하단)이 제공하는 것:

- **Stack Frames** — 전체 호출 스택; 프레임을 클릭해 그 지역 변수를 검사.
- **Locals / Members / Globals** — 변수 값을 실시간으로 검사하고 수정.
- **Step Into (F11)** / **Step Over (F10)** / **Step Out (Shift+F11)** — 줄 단위로 실행 탐색.
- **Continue (F5)** — 다음 브레이크포인트까지 실행 재개.

### 원격 씬 인스펙터

실행 중인 게임이 멈췄거나 세션 중일 때:

1. 에디터에서 **Debugger > Remote** 탭을 연다.
2. Scene 패널의 **Remote**("Scene" 옆 좌상단 토글)를 클릭해 씬 트리를 라이브 뷰로 전환한다.
3. 라이브 노드를 클릭해 인스펙터에서 현재 프로퍼티를 검사한다.
4. 여기서 한 프로퍼티 변경은 테스트를 위해 즉시 적용된다.

### Monitors 탭

**Debugger > Monitors**는 실시간 엔진 지표를 표시한다:

- **FPS / Process time / Physics time** — 성능 회귀를 잡는다.
- **Video RAM / Object count / Node count** — 메모리 증가를 추적한다.
- **Physics 2D/3D collision pairs** — 비싼 물리 씬을 식별한다.
- **Audio latency** — 오디오 콜백 오버런을 잡는다.

모니터 이름을 클릭하면 그래프가 열린다. **Add** 버튼으로 커스텀 모니터 대시보드를 만든다.

---

## 3. 시그널 디버깅

런타임에 `node.get_signal_connection_list("signal_name")`으로 검사한다(`callable`, `flags`, `signal`을 가진 Dictionary의 Array를 반환). 가장 흔한 시그널 버그: 두 번 연결(핸들러가 두 번 발화), 해제 시 disconnect 잊음(경고 + 댕글링 참조), 잘못된 핸들러 시그니처(조용한 미스).

---

## 4. 흔한 오류 패턴

| 오류 메시지 | 원인 | 해결 |
|---|---|---|
| `Node not found: "Player" (relative to "...")` | 잘못된 노드 경로, 노드 이름 변경, 트리에 추가되기 전 접근 | `$NodeName`은 `_ready()` 안/후에만 사용. `print(get_node_or_null("Player"))`로 경로 검증. `@onready` 사용. |
| `Attempt to call function on a null instance` | 노드가 해제됨, export 미할당, 또는 `get_node()`가 null 반환 | `is_instance_valid(node)`로 가드. 인스펙터에서 export 확인. `@onready var _node := $Node` 선호. |
| `Can't change this state while flushing queries` | `body_entered` 같은 물리 콜백 안에서 물리 상태(예: CollisionShape 비활성화) 수정 | 변경을 defer: `collision_shape.set_deferred("disabled", true)`. |
| `Invalid call. Nonexistent function 'X' in base 'Y'` | 그 타입에 없는 메서드 호출, 또는 노드를 잘못된 타입으로 접근 | `class_name` 확인, `as`로 캐스트, 또는 스크립트가 붙어 있는지 검증. `has_method("X")`로 가드. |
| `Cyclic reference` (`JSON.stringify`나 리소스 저장 시) | Resource나 Dictionary가 직간접적으로 자신을 참조 | 순환을 끊어라. 가능한 곳에서 리소스 참조 대신 노드 참조 사용, 또는 서브 리소스를 로컬 전용으로 표시. |
| `Cannot access member without instance` | 인스턴스 메서드를 정적처럼 호출, 또는 `@static` 함수에서 `self` 접근 | 호출을 인스턴스 맥락으로 옮기거나 데이터를 인자로 받는 제대로 된 정적 헬퍼로 리팩터. |
| `Stack overflow / Maximum recursion depth reached` | 무한 재귀 — 자신을 트리거하는 시그널이나 자신을 설정하는 세터인 경우가 많음 | 세터에 가드 변수(`_updating := true`) 추가. Debugger에서 호출 스택 추적. |
| `Already connected` | `CONNECT_ONE_SHOT` 없이 같은 시그널/callable 쌍에 `connect()`를 두 번째로 호출 | 연결 전 `is_connected()` 확인, 또는 먼저 disconnect, 또는 `CONNECT_REFERENCE_COUNTED` 사용. |
| `Index out of bounds (index X out of size Y)` | Array나 PackedArray를 길이 너머로 접근 | 접근 전 인덱스 검증: `if index < array.size()`. 가능한 곳에 `array.get(index)` 사용. |
| `Condition "p_mbuf_current..." is true` / 오디오 언더런 | 오디오 콜백이 마감을 놓침; 오디오 스레드에서 너무 많이 처리 | 오디오 버스 이펙트 줄이기, 폴리포니 낮추기, 또는 Project Settings에서 오디오 버퍼 크기 늘리기. |

---

## 5. 성능 디버깅

프로파일러(Debugger → Profiler)는 함수별 self-time과 호출 수를 보여 준다. Monitors 탭은 프레임 타임, FPS, 드로우콜 수, 물리 틱 예산, 메모리를 추적한다. 가장 부하가 큰 게임플레이 시나리오 중에 둘 다 열고, 프로파일러를 **Self time**으로 정렬해 원인을 찾아라. 드로우콜 병목은 Monitors 탭의 `Visible/Per frame`을 지켜보라.

> 병목을 식별한 뒤의 해결은 **godot-optimization**도 참고하라.

---

## 6. 씬 트리 디버깅

`print_tree_pretty()`는 현재 씬 트리를 stdout으로 덤프한다 — 노드가 당신 생각대로 있는지 확인하는 가장 빠른 방법. 에디터의 **Remote** 탭은 게임이 도는 동안 라이브 씬 트리를 보여 준다. `@tool` 노드는 `_get_configuration_warnings()`를 구현해 에디터 SceneTree 도크에 설정 오류를 표면화하라.

---

## 7. 체계적 디버깅 방법

print, 브레이크포인트, 원격 검사가 버그를 바로 드러내지 않으면, 의도적 프로세스로 돌아가라: **재현 → 격리 → 가설 → 추적 → 수정 → 검증 → 테스트 추가.** 각 단계가 다음을 게이트한다; 건너뛰면 시간을 낭비한다.

---

## 8. 구현 체크리스트

- [ ] 릴리스 빌드에 나타나면 안 되는 상세한 프레임 수준 출력에는 `print_debug()`를 쓴다
- [ ] 잘못된 상태와 복구 가능한 문제에는 (`print()`가 아니라) `push_error()` / `push_warning()`을 쓴다 — 스택 트레이스를 포함한다
- [ ] print를 흩뿌리는 대신 `F9`나 `breakpoint` 문으로 브레이크포인트를 설정해 실행을 멈춘다
- [ ] 시그널이 제대로 배선됐다고 가정하기 전에 `get_signal_connection_list()`로 시그널 연결을 확인한다
- [ ] 디버그 세션 중 **Scene → Remote**로 라이브 씬 트리를 검사해 런타임 노드 상태를 검증한다
- [ ] 최적화 전에 **Debugger → Profiler**를 열어 Self time을 측정한다 — 진짜 병목을 먼저 식별한다
- [ ] 누수를 나타내는 Object Count나 Video RAM 증가를 **Debugger → Monitors**로 지켜본다
- [ ] `await` 뒤에 실행되는 코드는 대기 중 노드가 해제됐을 경우에 대비해 `is_instance_valid()`로 가드한다
- [ ] 재현 → 격리 → 가설 → 추적 → 수정 → 검증 → 테스트 순서를 따른다; 수정으로 건너뛰지 않는다
- [ ] 버그 수정 후 이름 붙은 회귀 테스트를 작성해 같은 실패가 조용히 재발할 수 없게 한다
