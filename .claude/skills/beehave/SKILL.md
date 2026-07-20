---
name: beehave
description: Beehave 애드온을 사용할 때 쓴다 — composite·decorator·leaf·blackboard·시각 런타임 디버거를 갖춘 순수 GDScript 행동 트리
---

# Beehave

> **관련 스킬:** leaf가 구동하는 이동은 **ai-navigation**, 코어 엔진 FSM은 **state-machine**, 더 무거운 C++ BT+HSM 대안은 **limboai**, AI 접근법 선택은 **godot-brainstorming**을 참고하라.

> **애드온:** Beehave · 버전 `v2.9.2` · Godot 4.1+ · MIT · 소스: https://github.com/bitbrain/beehave · GDScript로 작성됨(공식 C# API 없음 — 이 스킬은 설계상 GDScript 전용이다).

---

## 1. Beehave를 언제 쓰나

| 접근법 | 적합한 경우 |
|---|---|
| 코어 엔진 FSM (`state-machine` 스킬) | 단순 에이전트, 상태 5개 미만, 애드온 없음 |
| **Beehave** (GDScript 애드온) | 가벼운 BT, GDScript 전용 프로젝트, 빠른 반복 |
| **LimboAI** | BT **와** HSM을 함께, 시각 에디터, C++ 성능, C# 지원(모듈 빌드) |

프로젝트가 GDScript 전용이고, 커스텀 엔진 빌드 없이 행동 트리를 원하며, 씬 트리 안에 노드를 배치하는 단순한 저작 워크플로를 중시할 때 Beehave를 골라라. Beehave 트리는 전적으로 씬 트리 안에 존재한다 — 모든 composite·decorator·leaf가 평범한 `Node` 자식이다. HSM 통합이 있는 더 무거운 C++/C# 솔루션이 필요하면 대신 `limboai` 스킬을 써라. BT 없이 순수 상태 기계가 필요하면 내장 `state-machine` 스킬을 써라.

**C# 참고:** Beehave에는 공식 C# API가 없다(`addons/beehave/`에 `.cs` 파일이 0개다). C#에서는 Godot 크로스 언어 상호운용(`GetNode<Node>(...).Call("tick", actor, blackboard)`)을 통해 GDScript API를 호출할 수 있지만, Beehave는 타입이 지정된 C# 클래스를 제공하지 않는다.

---

## 2. 설치 및 활성화

1. **Godot AssetLib** → "Beehave" 검색 → Download → Reload project.  
   또는 [GitHub 릴리스](https://github.com/bitbrain/beehave/releases)의 `addons/beehave/` 폴더를 `res://addons/beehave/`로 복사한다.
2. 플러그인을 활성화한다: **Project → Project Settings → Plugins** → **Beehave** 체크.  
   오토로드 두 개가 등록된다: `BeehaveGlobalMetrics`와 `BeehaveGlobalDebugger`.
3. 선택 사항 — leaf 스캐폴딩 템플릿을 위해 애드온의 `script_templates/`를 프로젝트 루트로 복사한다.

---

## 3. 트리 구성

Beehave 트리는 세 종류의 노드로 만들어지며, 모두 평범한 씬 트리 자식으로 배치된다:

| 역할 | 노드 | 동작 |
|---|---|---|
| **트리 루트** | `BeehaveTree` | 매 프레임(또는 physics/수동) 자식을 tick; `Node`를 확장(`BeehaveNode`가 아님) |
| **Composite** | `SequenceComposite`, `SelectorComposite`, `SimpleParallelComposite`, … | 흐름 제어 — AND / OR / 병렬 로직 |
| **Decorator** | `InverterDecorator`, `CooldownDecorator`, `RepeaterDecorator`, … | 자식 하나를 감싸 결과를 변형 |
| **Leaf** | `ActionLeaf`, `ConditionLeaf` 서브클래스 | 네 커스텀 게임 로직 |

### Composite 빠른 참조

| 클래스 | 로직 |
|---|---|
| `SequenceComposite` | AND — 모든 자식이 성공해야 함; 첫 실패에서 실패 |
| `SequenceReactiveComposite` | AND — running 동안 매 tick 첫 자식부터 재평가 |
| `SelectorComposite` | OR — 첫 성공에서 성공; 모두 실패하면 실패 |
| `SelectorReactiveComposite` | OR — running 동안 매 tick 첫 자식부터 재평가 |
| `SimpleParallelComposite` | 두 자식을 동시 실행; 결과는 primary(자식 0)를 따름 |
| `SequenceRandomComposite` | 셔플된 AND — 자식을 무작위 순서로 실행 |
| `SelectorRandomComposite` | 셔플된 OR — 자식을 무작위 순서로 시도 |

### Decorator 빠른 참조

| 클래스 | 효과 |
|---|---|
| `InverterDecorator` | `SUCCESS` ↔ `FAILURE` 뒤집음; `RUNNING`은 통과 |
| `AlwaysSucceedDecorator` | `SUCCESS` 강제; `RUNNING`은 통과 |
| `AlwaysFailDecorator` | `FAILURE` 강제; `RUNNING`은 통과 |
| `RepeaterDecorator` | 자식이 `repetitions`번 성공할 때까지 재실행 |
| `LimiterDecorator` | 자식을 `max_count` running tick으로 제한, 이후 `FAILURE` |
| `CooldownDecorator` | 자식이 끝난 뒤 `wait_time`초 동안 재실행 차단 |
| `TimeLimiterDecorator` | 자식에 `wait_time`초를 줌; 여전히 running이면 중단 |
| `DelayDecorator` | 자식을 처음 실행하기 전 `wait_time`초 대기 |
| `UntilFailDecorator` | 자식이 `FAILURE`를 반환할 때까지 반복, 그 뒤 `SUCCESS` 반환 |

### 최소 씬 트리 예시

```gdscript
# Scene tree:
#   Enemy (CharacterBody2D)
#     BeehaveTree               ← tick_rate = 1, process_thread = PHYSICS
#       SelectorComposite
#         SequenceComposite     ← "attack if in range"
#           IsInRangeCondition
#           AttackAction
#         PatrolAction          ← fallback

# BeehaveTree exports:
# @export var enabled: bool = true
# @export var tick_rate: int = 1          (1 = every frame; 3 = every 3 frames)
# @export var process_thread: ProcessThread = PHYSICS
# @export var blackboard: Blackboard      (auto-created if not set)
# @export_node_path var actor_node_path   (defaults to parent node)

# Access the tree from code if you need manual control:
@onready var bt: BeehaveTree = $BeehaveTree

func _ready() -> void:
    # Reduce tick cost: evaluate AI every 3 physics frames
    bt.tick_rate = 3
    # Default process_thread is PHYSICS — switch to IDLE if actor uses _process
    bt.process_thread = BeehaveTree.ProcessThread.IDLE
```

> **tick_rate 참고:** `tick_rate = 1`은 매 프레임 평가하고, `tick_rate = 3`은 3프레임마다 평가한다. 멀리 있거나 배경의 NPC는 값을 높여 CPU를 아껴라. 기본 process thread는 `PHYSICS`다 — 액터 스크립트가 `_physics_process` 대신 `_process`를 쓰면 `process_thread = IDLE`로 설정해 동기화를 유지하라.

---

## 4. leaf 계약

leaf가 네 게임 로직을 담는다. 여러 tick에 걸친 작업은 `ActionLeaf`, 단일 프레임 검사는 `ConditionLeaf`를 서브클래싱한 뒤 `tick(actor, blackboard)`를 오버라이드하라.

```gdscript
# IsInRangeCondition.gd
class_name IsInRangeCondition
extends ConditionLeaf

@export var detection_range: float = 150.0

func tick(actor: Node, blackboard: Blackboard) -> int:
    # Beehave types `actor` as Node; cast to your concrete type for 2D members.
    var body := actor as Node2D
    var target: Node2D = blackboard.get_value("target")
    if body == null or not is_instance_valid(target):
        return FAILURE
    var in_range := body.global_position.distance_to(target.global_position) <= detection_range
    return SUCCESS if in_range else FAILURE
```

```gdscript
# AttackAction.gd
class_name AttackAction
extends ActionLeaf

@export var attack_duration: float = 0.5

func tick(actor: Node, blackboard: Blackboard) -> int:
    var elapsed: float = blackboard.get_value("attack_elapsed", 0.0)
    elapsed += get_physics_process_delta_time()

    if elapsed >= attack_duration:
        blackboard.erase_value("attack_elapsed")
        # `actor` is typed Node; guard game-specific methods (or cast to your actor type).
        if actor.has_method("play_attack_animation"):
            actor.call("play_attack_animation")
        return SUCCESS

    blackboard.set_value("attack_elapsed", elapsed)
    return RUNNING

func after_run(actor: Node, blackboard: Blackboard) -> void:
    # Clean up any per-run state when the tree interrupts this action
    blackboard.erase_value("attack_elapsed")
```

**반환 코드** (`BeehaveNode`에 정의됨):
- `SUCCESS` — 액션 완료 / 조건 충족.
- `FAILURE` — 액션 실패 / 조건 불충족; 부모 composite가 다음에 무엇을 할지 정한다.
- `RUNNING` — 액션이 더 많은 프레임이 필요함; 트리가 다음 프레임에 `tick()`을 다시 호출한다(`ActionLeaf` 전용 — `ConditionLeaf`는 절대 `RUNNING`을 반환하면 안 된다).

**선택적 오버라이드:**
- `before_run(actor, blackboard)` — 한 run의 첫 tick 전에 한 번 호출된다.
- `after_run(actor, blackboard)` — 자식이 끝나거나(`SUCCESS`/`FAILURE`) 중단될 때 호출된다.
- `interrupt(actor, blackboard)` — 트리가 running 노드를 중단할 때 호출된다.

---

## 5. Blackboard

`Blackboard` 노드는 모든 `tick()` 호출에 전달되는 공유 키/값 저장소다. 외부 `Blackboard` 노드를 할당하지 않으면 `BeehaveTree`가 내부용을 자동 생성한다.

```gdscript
# Share one Blackboard across multiple BeehaveTrees on the same actor.
# Assign the same exported Blackboard node to each tree in the Inspector.

# Read / write from any leaf's tick():
func tick(actor: Node, blackboard: Blackboard) -> int:
    # Write
    blackboard.set_value("target", actor.get_nearest_enemy())

    # Read with default
    var speed: float = blackboard.get_value("move_speed", 200.0)

    # Conditional check
    if blackboard.has_value("stunned"):
        return FAILURE

    # Erase (sets key to null; has_value returns false after erase)
    blackboard.erase_value("temp_flag")

    return SUCCESS
```

> **이름 있는 네임스페이스:** 모든 메서드는 선택적 `blackboard_name: String` 매개변수(기본 `"default"`)를 받는다. 이를 사용해 이름 충돌 없이 한 `Blackboard` 노드에 별도 네임스페이스를 유지하라(예: 적별 상태 vs. 공유 월드 상태).

> **내장 표현식 leaf:** `BlackboardSetAction`, `BlackboardEraseAction`, `BlackboardHasCondition`, `BlackboardCompareCondition`는 Inspector export만으로 Blackboard를 조작하게 해준다(GDScript 불필요). 표현식은 Godot의 `Expression.execute([], blackboard)`로 실행된다 — 따라서 표현식 문자열 안에서 `get_value("key")`를 직접 호출할 수 있다.

---

## 6. 시각 디버거

Beehave는 `EditorDebuggerPlugin`을 제공하는데, 게임이 실행되는 동안 하단 에디터 패널에 **🐝 Beehave** 탭을 추가한다:

1. Godot 에디터에서 프로젝트를 실행한다.
2. **Debugger** 패널을 연다 → **🐝 Beehave** 탭을 클릭한다.
3. 목록에서 트리를 선택해 실시간 시각화를 활성화한다 — 활성 노드가 매 tick 강조된다.
4. 선택 사항: detach 버튼을 눌러 패널을 띄우거나, **Project Settings → beehave/debugger/start_detached = true**로 항상 분리된 채 시작하게 한다.

**Performance** 패널에서 트리별 CPU 비용을 추적하려면 `BeehaveTree` 노드에 `custom_monitor = true`를 설정하라. 이는 `beehave [microseconds]/process_time_<actor_name>-<id>`를 Performance monitor로 등록한다.

---

## 구현 체크리스트

- [ ] `addons/beehave/`를 프로젝트에 복사; **Project Settings → Plugins**에서 플러그인 활성화
- [ ] `BeehaveTree`를 액터의 자식으로 추가; `actor_node_path` 설정(또는 비워 부모로 기본 설정)
- [ ] `process_thread`가 액터의 루프와 일치: `_physics_process`면 `PHYSICS`, `_process`면 `IDLE`
- [ ] `tick_rate` 튜닝 — 배경 NPC는 값을 높여(예: `3`) 프레임당 비용을 줄임
- [ ] 모든 `tick()` 오버라이드가 `SUCCESS`, `FAILURE`, `RUNNING` 중 하나를 반환 — 절대 `void`/`null` 아님
- [ ] `ConditionLeaf` 서브클래스는 절대 `RUNNING`을 반환하지 않음
- [ ] run별 상태는 leaf 노드 자체가 아니라 `Blackboard`에 기록(leaf 노드는 공유됨)
- [ ] `after_run` 또는 `interrupt`가 액션이 쓴 Blackboard 키를 정리
- [ ] 여러 `BeehaveTree` 노드가 같은 데이터를 필요로 할 때 외부 `Blackboard` 노드를 export해 공유
- [ ] AI 로직 출시 전 런타임에 시각 디버거로 tick 흐름 확인
