---
name: limboai
description: LimboAI 애드온을 쓸 때 사용 — 비주얼 에디터가 있는 행동 트리와 계층적 상태 기계(C++ GDExtension), BTTask 서브클래싱, 블랙보드
---

# LimboAI

> **관련 스킬:** 태스크가 구동하는 이동은 **ai-navigation**, 코어 엔진 FSM(애드온이 필요 없을 때)은 **state-machine**, AI 접근법 선택은 **godot-brainstorming**을 보라.

> **애드온:** LimboAI · 버전 `v1.7.1` · Godot 4.6+ · MIT · 소스: https://github.com/limbonaut/limboai · C++로 작성됨(GDExtension; 엔진 모듈 빌드도 있음). GDExtension은 GDScript를 노출한다. **C#은 모듈 빌드가 필요하다**(v1.7.1에서 GDExtension이 아님).

---

## 1. 언제 LimboAI를 쓰나

| 접근법 | 적합한 대상 |
|---|---|
| 코어 엔진 FSM (`state-machine` 스킬) | 단순 에이전트, 상태 5개 미만, 애드온 없음 |
| **Beehave** (GDScript 애드온) | 경량 BT, GDScript 전용 프로젝트 |
| **LimboAI** | BT **와** HSM 동시, 비주얼 에디터, C++ 성능, C# 지원(모듈 빌드) |

세련된 비주얼 디버거가 있는 행동 트리가 필요하거나, 이를 계층적 상태 기계와 결합하고 싶거나(`BTState`가 둘을 잇는다), C++ 태스크 실행 속도가 필요할 때 LimboAI를 골라라. 주의: LimboAI는 **Godot 4.6+**가 필요하며 4.3–4.5에서는 쓸 수 없다. 더 단순한 GDScript 전용 행동 트리로는 Beehave가 가벼운 대안이다. BT 없이 평범한 상태 기계만 필요하면 대신 내장 `state-machine` 스킬을 써라.

---

## 2. 설치 & 설정

### GDExtension (권장 — 커스텀 엔진 없음)

1. **Godot AssetLib** → "LimboAI" 검색 → Download → 프로젝트 리로드.  
   또는 GitHub Releases에서 다운로드해 `addons/limboai/`를 `res://addons/limboai/`에 둔다.
2. 플러그인 활성화: **Project → Project Settings → Plugins** → LimboAI 체크.
3. `.gdextension` 매니페스트가 `res://addons/limboai/bin/`에 배포된다:

```ini
[configuration]
entry_symbol = "limboai_init"
compatibility_minimum = "4.2"

[libraries]
windows.debug.x86_64   = "res://addons/limboai/bin/liblimboai.windows.editor.x86_64.dll"
windows.release.x86_64 = "res://addons/limboai/bin/liblimboai.windows.template_release.x86_64.dll"
linux.debug.x86_64     = "res://addons/limboai/bin/liblimboai.linux.editor.x86_64.so"
linux.release.x86_64   = "res://addons/limboai/bin/liblimboai.linux.template_release.x86_64.so"
macos.debug            = "res://addons/limboai/bin/liblimboai.macos.editor.framework"
macos.release          = "res://addons/limboai/bin/liblimboai.macos.template_release.framework"
# ... (additional platform entries for linux arm64/rv64, android, iOS, web)
```

**GDExtension 제약:** 에디터 내 문서 툴팁 없음; 인스펙터에서 `BBParam` 프로퍼티 에디터 사용 불가.

### 모듈 버전 (C# 또는 완전한 에디터 통합)

[GitHub Releases](https://github.com/limbonaut/limboai/releases)에서 사전 컴파일된 에디터 + 익스포트 템플릿을 다운로드하라. 익스포트에 커스텀 엔진이 필요하다. 모듈 빌드는 C#용 NuGet 패키지를 배포한다:

```ini
# Add local NuGet source to your project:
# dotnet nuget add source path/to/nupkgs --name LimboNugetSource
```

---

## 3. 행동 트리

`BehaviorTree` 리소스가 태스크 트리를 담는다. `BTPlayer`가 매 물리 프레임(또는 idle/manual)마다 실행한다. `BTPlayer`를 에이전트 노드의 자식으로 추가하고 `BehaviorTree` 리소스를 할당하라.

### GDScript

```gdscript
# EnemyAI.gd — assign behavior_tree in the Inspector or here
extends CharacterBody2D

@onready var bt_player: BTPlayer = $BTPlayer

func _ready() -> void:
    # BTPlayer starts executing automatically (active = true by default).
    # Connect to updated(status) to react when the tree finishes.
    bt_player.updated.connect(_on_bt_updated)

func _on_bt_updated(status: int) -> void:
    if status == BT.SUCCESS:
        bt_player.restart()  # loop the tree
```

### C#

```csharp
// EnemyAI.cs
using Godot;

public partial class EnemyAI : CharacterBody2D
{
    [Export] private BTPlayer _btPlayer;

    public override void _Ready()
    {
        _btPlayer.Updated += OnBtUpdated;
    }

    private void OnBtUpdated(int status)
    {
        if (status == (int)BT.Status.Success)
            _btPlayer.Restart();
    }
}
```

`BTPlayer.UpdateMode`가 트리가 언제 틱하는지 제어한다: `IDLE`(매 `_process`), `PHYSICS`(매 `_physics_process`, 기본), `MANUAL`(직접 `bt_player.update(delta)` 호출).

---

## 4. 커스텀 태스크

`BTAction`(다중 틱 작업)이나 `BTCondition`(즉시 확인)을 서브클래싱하라. 에디터에서 `_generate_name()`과 `_get_configuration_warnings()`가 동작하도록 `@tool`을 붙여라. 스크립트를 `res://ai/tasks/` 아래에 두라; 하위 폴더가 태스크 카테고리가 된다.

### GDScript

```gdscript
@tool
extends BTAction
## Moves the agent toward a blackboard position each tick.

@export var target_pos_var: StringName = &"target_pos"
@export var speed: float = 200.0

func _generate_name() -> String:
    return "MoveToward %s" % LimboUtility.decorate_var(target_pos_var)

func _setup() -> void:
    pass  # one-time init; agent and blackboard are available here

func _enter() -> void:
    pass  # called when task transitions from non-RUNNING → RUNNING

func _tick(delta: float) -> Status:
    var target: Vector2 = blackboard.get_var(target_pos_var, Vector2.ZERO)
    if agent.global_position.distance_to(target) < 5.0:
        return SUCCESS
    agent.velocity = agent.global_position.direction_to(target) * speed
    agent.move_and_slide()
    return RUNNING

func _exit() -> void:
    pass  # cleanup after SUCCESS or FAILURE
```

```gdscript
@tool
extends BTCondition
## Returns SUCCESS if the agent is within range of a target node.

@export var target_var: StringName = &"target"
@export var distance_max: float = 150.0

var _max_sq: float

func _setup() -> void:
    _max_sq = distance_max * distance_max

func _tick(_delta: float) -> Status:
    var target: Node2D = blackboard.get_var(target_var, null)
    if not is_instance_valid(target):
        return FAILURE
    var in_range := agent.global_position.distance_squared_to(
        target.global_position) <= _max_sq
    return SUCCESS if in_range else FAILURE
```

### C#

```csharp
// MoveTowardTask.cs — place in res://ai/tasks/
using Godot;

[Tool]
public partial class MoveTowardTask : BTAction
{
    [Export] public StringName TargetPosVar { get; set; } = "target_pos";
    [Export] public float Speed { get; set; } = 200f;

    public override string _GenerateName() =>
        $"MoveToward {LimboUtility.DecorateVar(TargetPosVar)}";

    public override void _Setup() { }

    public override void _Enter() { }

    public override Status _Tick(double delta)
    {
        var target = (Vector2)Blackboard.GetVar(TargetPosVar, Vector2.Zero);
        var body = (CharacterBody2D)Agent;
        if (body.GlobalPosition.DistanceTo(target) < 5f)
            return Status.Success;
        body.Velocity = body.GlobalPosition.DirectionTo(target) * Speed;
        body.MoveAndSlide();
        return Status.Running;
    }

    public override void _Exit() { }
}
```

```csharp
// InRangeCondition.cs
using Godot;

[Tool]
public partial class InRangeCondition : BTCondition
{
    [Export] public StringName TargetVar { get; set; } = "target";
    [Export] public float DistanceMax { get; set; } = 150f;

    private float _maxSq;

    public override void _Setup() => _maxSq = DistanceMax * DistanceMax;

    public override Status _Tick(double delta)
    {
        var target = Blackboard.GetVar(TargetVar, default(Variant)).As<Node2D>();
        if (!GodotObject.IsInstanceValid(target))
            return Status.Failure;
        var agent2D = (Node2D)Agent;
        bool inRange = agent2D.GlobalPosition.DistanceSquaredTo(
            target.GlobalPosition) <= _maxSq;
        return inRange ? Status.Success : Status.Failure;
    }
}
```

태스크 생명주기: 첫 틱 전에 `_setup()` 한 번 → 상태가 non-RUNNING에서 전이할 때 `_enter()` → 매 실행마다 `_tick(delta)` → SUCCESS 또는 FAILURE 뒤 `_exit()`.

---

## 5. 블랙보드

`Blackboard`는 트리의 모든 태스크가 공유하는 `RefCounted` 키/값 저장소다. `StringName` 키(`&"key"`)를 쓰고, 인스펙터가 피커를 보이도록 태스크 프로퍼티로 export하라.

### GDScript

```gdscript
@tool
extends BTAction

@export var speed_var: StringName = &"speed"
@export var target_var: StringName = &"target"

func _tick(delta: float) -> Status:
    # Read with a default; use no type annotation for object vars
    # to avoid errors if the stored instance was freed.
    var speed: float = blackboard.get_var(speed_var, 100.0)
    var obj = blackboard.get_var(target_var, null)
    if not is_instance_valid(obj):
        return FAILURE

    # Write back
    blackboard.set_var(speed_var, speed * 1.1)
    return RUNNING
```

### C#

```csharp
// C# has no generic GetVar<T> — cast the returned Variant.
using Godot;

[Tool]
public partial class SampleTask : BTAction
{
    [Export] public StringName SpeedVar { get; set; } = "speed";
    [Export] public StringName TargetVar { get; set; } = "target";

    public override Status _Tick(double delta)
    {
        float speed = (float)Blackboard.GetVar(SpeedVar, 100f);
        var obj = Blackboard.GetVar(TargetVar, default(Variant)).As<GodotObject>();
        if (!GodotObject.IsInstanceValid(obj))
            return Status.Failure;

        Blackboard.SetVar(SpeedVar, speed * 1.1f);
        return Status.Running;
    }
}
```

유용한 `Blackboard` 메서드: `has_var(name)`, `erase_var(name)`, `list_vars()`, `get_vars_as_dict()`, `bind_var_to_property(name, obj, prop)`, `link_var(name, target_bb, target_name)`, `print_state()`(디버그).

`BlackboardPlan`이 변수 스키마(타입, 기본값, 힌트)를 정의하며 `BTPlayer`나 `LimboHSM`의 인스펙터에서 편집된다. `blackboard_plan.create_blackboard(scene_root)`을 호출해 런타임에 스코프된 `Blackboard`를 생성하라.

---

## 6. 계층적 상태 기계 (LimboHSM)

`LimboHSM`은 자식 `LimboState` 노드를 관리하는 `LimboState` 노드다. 상태가 `dispatch(event)`를 호출하면 전이가 발화된다.

### GDScript — 씬 트리 설정

```gdscript
# Character.gd — scene tree: Character → LimboHSM → IdleState, MoveState
extends CharacterBody2D

@onready var hsm: LimboHSM = $LimboHSM
@onready var idle: LimboState = $LimboHSM/IdleState
@onready var move: LimboState = $LimboHSM/MoveState

func _ready() -> void:
    hsm.add_transition(idle, move, idle.EVENT_FINISHED)
    hsm.add_transition(move, idle, move.EVENT_FINISHED)
    hsm.initialize(self)
    hsm.set_active(true)
```

### C# — 씬 트리 설정

```csharp
// Character.cs
using Godot;

public partial class Character : CharacterBody2D
{
    [Export] private LimboHSM _hsm;
    [Export] private LimboState _idle;
    [Export] private LimboState _move;

    public override void _Ready()
    {
        _hsm.AddTransition(_idle, _move, _idle.EventFinished);
        _hsm.AddTransition(_move, _idle, _move.EventFinished);
        _hsm.Initialize(this);
        _hsm.SetActive(true);
    }
}
```

### GDScript — 상태 스크립트

```gdscript
# IdleState.gd
extends LimboState

func _setup() -> void:
    pass  # agent and blackboard available; runs once during hsm.initialize()

func _enter() -> void:
    agent.get_node("AnimationPlayer").play("idle")

func _exit() -> void:
    pass

func _update(delta: float) -> void:
    if Input.get_vector(&"ui_left", &"ui_right", &"ui_up", &"ui_down").length() > 0.1:
        dispatch(EVENT_FINISHED)
```

### C# — 상태 스크립트

```csharp
// IdleState.cs
using Godot;

public partial class IdleState : LimboState
{
    public override void _Setup() { }

    public override void _Enter()
    {
        Agent.GetNode<AnimationPlayer>("AnimationPlayer").Play("idle");
    }

    public override void _Exit() { }

    public override void _Update(double delta)
    {
        if (Input.GetVector("ui_left", "ui_right", "ui_up", "ui_down").Length() > 0.1f)
            Dispatch(EventFinished);
    }
}
```

---

## 구현 체크리스트

- [ ] `BTPlayer`가 에이전트의 자식으로 추가됨; `behavior_tree` 리소스가 할당됨
- [ ] 커스텀 태스크가 에디터 표시를 위해 `@tool`(GDScript) 또는 `[Tool]`(C#)로 주석됨
- [ ] 모든 `_tick`이 `SUCCESS`, `FAILURE`, `RUNNING`을 반환함 — 절대 `void`/`null` 아님
- [ ] 블랙보드 키가 export된 `StringName` 프로퍼티(접미사 `_var`)로 문서화됨
- [ ] C# 블랙보드 읽기가 `Variant`를 명시적으로 캐스트함(`(float)Blackboard.GetVar(...)`)
- [ ] C#은 C# 지원을 위해 모듈 빌드를 씀(GDExtension 아님)
- [ ] 폐기된 `behavior_tree_finished`가 아닌 `BTPlayer.updated` 시그널을 씀
- [ ] HSM: 모든 `LimboState` 노드가 `initialize()` 전에 `add_transition`으로 배선됨
- [ ] HSM: `initialize()` 뒤에 `set_active(true)`가 호출됨
- [ ] HSM 전이가 빠짐없음 — 도달 가능한 모든 상태에 나가는 경로가 있음
- [ ] `BBParam` 인스펙터 바인딩: 모듈 빌드를 씀; GDExtension에는 param 에디터 UI가 없음
