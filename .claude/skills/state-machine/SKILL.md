---
name: state-machine
description: Godot에서 상태 기계를 구현할 때 사용한다 — enum 기반, 노드 기반, 리소스 기반 FSM 패턴과 그 트레이드오프
---

# Godot 4.3+의 상태 기계

복잡도 수준에 맞는 FSM 패턴을 골라라. 모든 예제는 Godot 4.3+를 대상으로 하며 폐기된 API를 쓰지 않는다.

> **관련 스킬:** 이동 상태 통합은 **player-controller**, AI 상태 패턴은 **ai-navigation**, 리소스 기반 상태 설정은 **resource-pattern**, FSM이 구동하는 AnimationTree 상태는 **animation-system**, 상태 기계로서의 대화 흐름은 **dialogue-system**, 시전자 상태 게이팅(시전 중/기절)은 **ability-system**, FSM과 함께 행동 트리가 필요하면 LimboAI 애드온의 HSM(`BTState`)은 **limboai**, GDScript 전용 BT 대안은 **beehave**를 참고하라.

> **애드온을 언제 손에 쥐나:** 이 스킬은 내장 FSM 패턴(enum, 노드 기반, 리소스 기반)을 다룬다. 에이전트에 완전한 행동 트리가 필요하면 대신 **limboai**(C++ + HSM, Godot 4.6+)나 **beehave**(순수 GDScript, Godot 4.1+)를 보라.

---

## 1. 접근법 비교

| 접근법       | 복잡도 | 적합한 용도                              |
|----------------|------------|---------------------------------------|
| Enum 기반     | 낮음        | 단순 오브젝트, 상태 5개 미만   |
| 노드 기반     | 중간     | 복잡한 동작을 가진 캐릭터      |
| 리소스 기반 | 높음       | 데이터 주도 또는 에디터 설정 가능 AI |

---

## 2. 접근법 1: Enum 기반 (가장 단순)

상태 수가 적고 이렇다 할 enter/exit 로직이 없을 때 쓴다.

### GDScript

```gdscript
extends CharacterBody2D

enum State { IDLE, PATROL, CHASE, ATTACK }

@export var patrol_range: float = 200.0
@export var chase_range: float = 300.0
@export var attack_range: float = 50.0
@export var speed: float = 80.0

var current_state: State = State.IDLE
var patrol_target: Vector2 = Vector2.ZERO

@onready var player: Node2D = get_tree().get_first_node_in_group("player")


func _physics_process(delta: float) -> void:
	match current_state:
		State.IDLE:
			_state_idle()
		State.PATROL:
			_state_patrol()
		State.CHASE:
			_state_chase()
		State.ATTACK:
			_state_attack()

	move_and_slide()


func _state_idle() -> void:
	velocity = Vector2.ZERO
	if _player_in_range(chase_range):
		current_state = State.CHASE
	elif randf() < 0.005:
		patrol_target = global_position + Vector2(randf_range(-patrol_range, patrol_range), 0.0)
		current_state = State.PATROL


func _state_patrol() -> void:
	var direction := (patrol_target - global_position)
	if direction.length() < 4.0:
		current_state = State.IDLE
		return
	velocity = direction.normalized() * speed
	if _player_in_range(chase_range):
		current_state = State.CHASE


func _state_chase() -> void:
	if not is_instance_valid(player):
		current_state = State.IDLE
		return
	if _player_in_range(attack_range):
		current_state = State.ATTACK
		return
	if not _player_in_range(chase_range):
		current_state = State.PATROL
		return
	velocity = (player.global_position - global_position).normalized() * speed


func _state_attack() -> void:
	velocity = Vector2.ZERO
	if not _player_in_range(attack_range):
		current_state = State.CHASE


func _player_in_range(range: float) -> bool:
	if not is_instance_valid(player):
		return false
	return global_position.distance_to(player.global_position) <= range
```

### C# 등가

```csharp
using Godot;

public partial class SimpleEnemy : CharacterBody2D
{
    private enum State { Idle, Patrol, Chase, Attack }

    [Export] public float PatrolRange { get; set; } = 200f;
    [Export] public float ChaseRange  { get; set; } = 300f;
    [Export] public float AttackRange { get; set; } = 50f;
    [Export] public float Speed       { get; set; } = 80f;

    private State _currentState = State.Idle;
    private Vector2 _patrolTarget = Vector2.Zero;
    private Node2D _player;

    public override void _Ready()
    {
        _player = GetTree().GetFirstNodeInGroup("player") as Node2D;
    }

    public override void _PhysicsProcess(double delta)
    {
        switch (_currentState)
        {
            case State.Idle:   StateIdle();   break;
            case State.Patrol: StatePatrol(); break;
            case State.Chase:  StateChase();  break;
            case State.Attack: StateAttack(); break;
        }
        MoveAndSlide();
    }

    private void StateIdle()
    {
        Velocity = Vector2.Zero;
        if (PlayerInRange(ChaseRange))
        {
            _currentState = State.Chase;
        }
        else if (GD.Randf() < 0.005f)
        {
            _patrolTarget = GlobalPosition + new Vector2(GD.RandRange(-PatrolRange, PatrolRange), 0f);
            _currentState = State.Patrol;
        }
    }

    private void StatePatrol()
    {
        var direction = _patrolTarget - GlobalPosition;
        if (direction.Length() < 4f) { _currentState = State.Idle; return; }
        Velocity = direction.Normalized() * Speed;
        if (PlayerInRange(ChaseRange)) _currentState = State.Chase;
    }

    private void StateChase()
    {
        if (!IsInstanceValid(_player)) { _currentState = State.Idle; return; }
        if (PlayerInRange(AttackRange)) { _currentState = State.Attack; return; }
        if (!PlayerInRange(ChaseRange)) { _currentState = State.Patrol; return; }
        Velocity = (_player.GlobalPosition - GlobalPosition).Normalized() * Speed;
    }

    private void StateAttack()
    {
        Velocity = Vector2.Zero;
        if (!PlayerInRange(AttackRange)) _currentState = State.Chase;
    }

    private bool PlayerInRange(float range) =>
        IsInstanceValid(_player) && GlobalPosition.DistanceTo(_player.GlobalPosition) <= range;
}
```

> **enum 기반에서 벗어나야 할 때:**
> - enter/exit 로직이 상태 메서드 전반에 중복되기 시작한다
> - 애니메이션 동기화에 명시적 enter/exit 훅이 필요하다
> - `match`/`switch` 블록이 ~100줄을 넘어 커진다

---

## 3. 접근법 2: 노드 기반 (캐릭터에 권장)

각 상태가 자체 노드다. `StateMachine` 노드는 입력과 process 호출을 활성 상태에게 위임하고, 상태들은 이름으로 전이를 촉발한다.

### 씬 트리

```
Player (CharacterBody2D)
└── StateMachine (Node)
    ├── Idle  (State)
    ├── Run   (State)
    ├── Jump  (State)
    └── Attack (State)
```

### State 베이스 클래스

**GDScript (`state.gd`)**

```gdscript
class_name State
extends Node

## Populated by StateMachine._ready()
var entity: CharacterBody2D
var state_machine: StateMachine


## Called when this state becomes active.
func enter() -> void:
	pass


## Called when this state is deactivated.
func exit() -> void:
	pass


## Mirrors _process. Return a state name string to transition, or "" to stay.
func update(delta: float) -> String:
	return ""


## Mirrors _physics_process. Return a state name string to transition, or "".
func physics_update(delta: float) -> String:
	return ""


## Mirrors _unhandled_input.
func handle_input(event: InputEvent) -> String:
	return ""
```

**C# (`State.cs`)**

```csharp
using Godot;

public partial class State : Node
{
    /// Populated by StateMachine._Ready()
    public CharacterBody2D Entity { get; set; }
    public StateMachine StateMachine { get; set; }

    public virtual void Enter() { }
    public virtual void Exit() { }
    public virtual string Update(double delta) => string.Empty;
    public virtual string PhysicsUpdate(double delta) => string.Empty;
    public virtual string HandleInput(InputEvent @event) => string.Empty;
}
```

### StateMachine 클래스

**GDScript (`state_machine.gd`)**

```gdscript
class_name StateMachine
extends Node

@export var initial_state: State

var current_state: State
var states: Dictionary = {}


func _ready() -> void:
	for child in get_children():
		if child is State:
			states[child.name] = child
			child.entity = owner as CharacterBody2D
			child.state_machine = self

	if initial_state:
		current_state = initial_state
		current_state.enter()


func _unhandled_input(event: InputEvent) -> void:
	var next := current_state.handle_input(event)
	if next:
		transition_to(next)


func _process(delta: float) -> void:
	var next := current_state.update(delta)
	if next:
		transition_to(next)


func _physics_process(delta: float) -> void:
	var next := current_state.physics_update(delta)
	if next:
		transition_to(next)


func transition_to(state_name: String) -> void:
	if not states.has(state_name):
		push_error("StateMachine: unknown state '%s'" % state_name)
		return
	current_state.exit()
	current_state = states[state_name]
	current_state.enter()
```

**C# (`StateMachine.cs`)**

```csharp
using System.Collections.Generic;
using Godot;

public partial class StateMachine : Node
{
    [Export] public State InitialState { get; set; }

    public State CurrentState { get; private set; }
    private readonly Dictionary<string, State> _states = new();

    public override void _Ready()
    {
        foreach (var child in GetChildren())
        {
            if (child is State state)
            {
                _states[state.Name] = state;
                state.Entity = Owner as CharacterBody2D;
                state.StateMachine = this;
            }
        }

        if (InitialState != null)
        {
            CurrentState = InitialState;
            CurrentState.Enter();
        }
    }

    public override void _UnhandledInput(InputEvent @event)
    {
        var next = CurrentState.HandleInput(@event);
        if (!string.IsNullOrEmpty(next)) TransitionTo(next);
    }

    public override void _Process(double delta)
    {
        var next = CurrentState.Update(delta);
        if (!string.IsNullOrEmpty(next)) TransitionTo(next);
    }

    public override void _PhysicsProcess(double delta)
    {
        var next = CurrentState.PhysicsUpdate(delta);
        if (!string.IsNullOrEmpty(next)) TransitionTo(next);
    }

    public void TransitionTo(string stateName)
    {
        if (!_states.TryGetValue(stateName, out var next))
        {
            GD.PushError($"StateMachine: unknown state '{stateName}'");
            return;
        }
        CurrentState.Exit();
        CurrentState = next;
        CurrentState.Enter();
    }
}
```

### 구체 예제: IdleState

**GDScript (`idle_state.gd`)**

```gdscript
class_name IdleState
extends State


func enter() -> void:
	entity.get_node("AnimationPlayer").play("idle")


func physics_update(delta: float) -> String:
	if not entity.is_on_floor():
		return "Jump"
	if Input.get_axis("move_left", "move_right") != 0.0:
		return "Run"
	return ""


func handle_input(event: InputEvent) -> String:
	if event.is_action_pressed("jump") and entity.is_on_floor():
		return "Jump"
	if event.is_action_pressed("attack"):
		return "Attack"
	return ""
```

---

## 4. 접근법 3: 리소스 기반 (데이터 주도)

디자이너가 코드를 수정하지 않고 Godot 인스펙터에서 상태를 설정해야 할 때 쓴다.

### StateData 리소스

```gdscript
class_name StateData
extends Resource

@export var state_name: String = ""
@export var animation_name: String = ""
@export var move_speed: float = 0.0
@export var can_transition_to: Array[String] = []
```

AI 컨트롤러에 `Array[StateData]`를 export한다. 디자이너가 인스펙터에서 각 항목을 채운다 — 동작을 튜닝하거나 상태를 추가하는 데 코드 변경이 필요 없다. 런타임은 `can_transition_to`를 읽어 전이를 검증하고, 각 활성 상태의 `animation_name` / `move_speed`를 고른다.

```csharp
using Godot;

[GlobalClass]
public partial class StateData : Resource
{
    [Export] public string StateName { get; set; } = string.Empty;
    [Export] public string AnimationName { get; set; } = string.Empty;
    [Export] public float MoveSpeed { get; set; } = 0f;
    [Export] public Godot.Collections.Array<string> CanTransitionTo { get; set; } = new();
}
```

AI 컨트롤러 클래스에 `Array[StateData]` export를 붙여라(`[Export] public Godot.Collections.Array<StateData> States`). 런타임에 `StateName`으로 활성 `StateData`를 찾아 `AnimationName` / `MoveSpeed`를 읽어 동작을 구동하고, `CanTransitionTo`로 `TransitionTo` 호출을 가드하라.

---

## 5. 계층적 및 병렬 상태 기계

평면 FSM이 ~8개 상태를 넘거나 여러 관심사(이동 + 전투 + 애니메이션)에 걸치면, **계층적** 기계(상태가 하위 상태 기계를 소유, 예: `Idle/Walk/Run`을 담은 `OnGround`)나 **병렬** 기계(이동·전투·애니메이션을 위한 독립 FSM이 나란히 돎)로 쪼개라. 둘 다 상태 수를 곱셈이 아니라 덧셈으로 유지한다.
---

## 6. 결정 순서도

```
Start
  │
  ▼
Fewer than 5 states?
  ├─ Yes ──────────────────────────────────► Enum-Based
  └─ No
       │
       ▼
     Multiple independent concerns
     (movement + combat + animation)?
       ├─ Yes ──────────────────────────────► Parallel State Machines
       └─ No
            │
            ▼
          States naturally nest
          (sub-states within states)?
            ├─ Yes ────────────────────────► Hierarchical State Machine
            └─ No
                 │
                 ▼
               Designers need to configure
               states in the Inspector?
                 ├─ Yes ──────────────────► Resource-Based
                 └─ No ──────────────────► Node-Based
```

---

## 7. 구현 체크리스트

- [ ] 실제 복잡도에 맞는 접근법을 골랐다(enum / 노드 / 리소스)
- [ ] 모든 상태에 명시적 `enter()`와 `exit()` 메서드(또는 등가물)가 있다
- [ ] 모든 전이가 명시적으로 이름 지어졌다 — 상태 간 암묵적 폴스루가 없다
- [ ] 필요한 곳에서 애니메이션을 `enter()`에서 시작하고 `exit()`에서 정리한다
- [ ] 한 프레임 안에 무한 재귀를 일으킬 수 있는 순환 전이 루프가 없다
- [ ] 상태가 ~8개를 넘거나 여러 관심사에 걸치면 평면 FSM을 계층적 또는 병렬로 교체한다
- [ ] 병렬 상태 기계가 같은 상태를 수정하지 않는다(예: 둘 다 velocity 설정) — 기계당 관심사 하나
