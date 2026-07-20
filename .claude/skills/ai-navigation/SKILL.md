---
name: ai-navigation
description: AI 이동을 구현할 때 사용한다 — NavigationAgent2D/3D, 조향(steering) 동작, 행동 트리, 순찰 패턴
---

# Godot 4.3+의 AI 내비게이션

NavigationAgent2D/3D, 조향 동작, 행동 트리, 순찰 패턴을 다룬다. 모든 예제는 Godot 4.3+를 대상으로 하며 폐기된 API를 쓰지 않는다.

> **관련 스킬:** AI 상태 관리는 **state-machine**, 모듈식 AI 동작은 **component-system**, 이동 물리 패턴은 **player-controller**, 경로 탐색 벡터·조향 수학은 **math-essentials**, 비주얼 에디터가 있는 BT + HSM는 **limboai**, 가벼운 GDScript 행동 트리는 **beehave**를 참고하라. 조향/내비게이션이 아니라 구조화된 행동 트리가 필요하면 **limboai**와 **beehave**의 비교 표를 보라.

---

## 1. 내비게이션 설정

### 씬 구조

```
World (Node2D or Node3D)
└── NavigationRegion2D (or NavigationRegion3D)
    ├── TileMapLayer / StaticBody2D (geometry)
    └── Enemy (CharacterBody2D with NavigationAgent2D child)
```

### NavigationRegion2D / NavigationRegion3D

1. 씬에 **NavigationRegion2D**(또는 **NavigationRegion3D**) 노드를 추가한다.
2. 여기에 **NavigationPolygon**(2D)이나 **NavigationMesh**(3D) 리소스를 할당한다.
3. NavigationPolygon 에디터에서 이동 가능 영역을 그리거나, 3D에서 NavigationMesh 바운드를 구성한다.
4. **편집 시점에 메시를 굽는다:** NavigationRegion 노드를 선택 → 툴바에서 **Bake NavigationPolygon**(2D) 또는 **Bake NavigationMesh**(3D)를 클릭.
5. 월드가 동적으로 바뀔 때 **런타임에 굽는다**:

```gdscript
# 2D
$NavigationRegion2D.bake_navigation_polygon()

# 3D
$NavigationRegion3D.bake_navigation_mesh()
```

```csharp
// 2D
GetNode<NavigationRegion2D>("NavigationRegion2D").BakeNavigationPolygon();

// 3D
GetNode<NavigationRegion3D>("NavigationRegion3D").BakeNavigationMesh();
```

### 비동기 내비게이션 베이킹 (Godot 4.4+)

큰 맵에서는 내비게이션 베이킹이 프레임 드랍을 일으킬 수 있다. Godot 4.4는 백그라운드 스레드 베이킹을 지원한다: `bake_navigation_polygon(true)`(2D) 또는 `bake_navigation_mesh(true)`(3D)에 `true`를 전달하고, 메시가 준비됐음을 알기 위해 리전의 `bake_finished` 시그널을 연결한다(`CONNECT_ONE_SHOT` 사용).

> **언제 비동기 베이킹을 쓰나:** 절차적으로 생성된 레벨, 파괴 가능한 지형, 또는 내비게이션 메시를 런타임에 다시 빌드해야 하는 모든 씬. 메시가 구워지는 동안 게임은 계속 돌아간다.

### 내비게이션 레이어

내비게이션 레이어는 서로 다른 에이전트 타입(지상 부대, 비행 유닛, 큰 적)의 이동 가능 영역을 분리한다.

```gdscript
# Assign layer bits on the NavigationRegion (Inspector or code)
# Layer 1 = ground, Layer 2 = air, Layer 3 = large

# On the NavigationAgent, set matching layers:
$NavigationAgent2D.navigation_layers = 1   # ground only
$NavigationAgent2D.navigation_layers = 2   # air only
$NavigationAgent2D.navigation_layers = 1 | 2  # both (bitwise OR)
```

```csharp
// Assign layer bits on the NavigationRegion (Inspector or code)
// Layer 1 = ground, Layer 2 = air, Layer 3 = large

var navAgent = GetNode<NavigationAgent2D>("NavigationAgent2D");
navAgent.NavigationLayers = 1;       // ground only
navAgent.NavigationLayers = 2;       // air only
navAgent.NavigationLayers = 1 | 2;   // both (bitwise OR)
```

> `navigation_layers`를 **NavigationRegion**과 **NavigationAgent** 양쪽에 설정해 서로 맞춰라. 레이어 불일치는 에이전트가 경로를 못 찾는 가장 흔한 이유 중 하나다.

---

## 2. NavigationAgent2D 기본 사용

### GDScript

```gdscript
extends CharacterBody2D

@export var speed: float = 120.0

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D


func _ready() -> void:
	# velocity_computed fires when avoidance calculates a safe velocity
	nav_agent.velocity_computed.connect(_on_velocity_computed)


func _physics_process(delta: float) -> void:
	if nav_agent.is_navigation_finished():
		return

	var next_pos: Vector2 = nav_agent.get_next_path_position()
	var direction: Vector2 = (next_pos - global_position).normalized()
	var desired_velocity: Vector2 = direction * speed

	if nav_agent.avoidance_enabled:
		# Hand desired velocity to the avoidance system; wait for the signal
		nav_agent.velocity = desired_velocity
	else:
		velocity = desired_velocity
		move_and_slide()


func _on_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity
	move_and_slide()


func set_target(target_pos: Vector2) -> void:
	nav_agent.target_position = target_pos
```

**핵심 NavigationAgent2D 속성:**

| 속성 | 목적 |
|---|---|
| `target_position` | 월드 공간 목적지 |
| `path_desired_distance` | 각 웨이포인트에 도달로 간주하는 근접 거리 (기본 1) |
| `target_desired_distance` | 최종 목표에 완료로 간주하는 근접 거리 (기본 10) |
| `avoidance_enabled` | RVO 장애물 회피 활성화 |
| `radius` | 회피용 에이전트 충돌 반경 |
| `time_horizon_agents` | 회피 예측 시간(초) (흔들림을 줄이도록 튜닝) |

### C#

```csharp
using Godot;

public partial class Enemy2D : CharacterBody2D
{
    [Export] public float Speed { get; set; } = 120f;

    private NavigationAgent2D _navAgent;

    public override void _Ready()
    {
        _navAgent = GetNode<NavigationAgent2D>("NavigationAgent2D");
        _navAgent.VelocityComputed += OnVelocityComputed;
    }

    public override void _PhysicsProcess(double delta)
    {
        if (_navAgent.IsNavigationFinished()) return;

        Vector2 nextPos = _navAgent.GetNextPathPosition();
        Vector2 direction = (nextPos - GlobalPosition).Normalized();
        Vector2 desiredVelocity = direction * Speed;

        if (_navAgent.AvoidanceEnabled)
            _navAgent.Velocity = desiredVelocity;
        else
        {
            Velocity = desiredVelocity;
            MoveAndSlide();
        }
    }

    private void OnVelocityComputed(Vector2 safeVelocity)
    {
        Velocity = safeVelocity;
        MoveAndSlide();
    }

    public void SetTarget(Vector2 targetPos) => _navAgent.TargetPosition = targetPos;
}
```

---

## 3. NavigationAgent3D 기본 사용

### GDScript

```gdscript
extends CharacterBody3D

@export var speed: float = 4.0
@export var gravity: float = 9.8

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D


func _ready() -> void:
	nav_agent.velocity_computed.connect(_on_velocity_computed)


func _physics_process(delta: float) -> void:
	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	if nav_agent.is_navigation_finished():
		move_and_slide()
		return

	var next_pos: Vector3 = nav_agent.get_next_path_position()
	var direction: Vector3 = (next_pos - global_position)
	direction.y = 0.0
	direction = direction.normalized()
	var desired_velocity: Vector3 = direction * speed
	desired_velocity.y = velocity.y  # preserve gravity

	if nav_agent.avoidance_enabled:
		nav_agent.velocity = desired_velocity
	else:
		velocity = desired_velocity
		move_and_slide()


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	velocity = safe_velocity
	move_and_slide()


func set_target(target_pos: Vector3) -> void:
	nav_agent.target_position = target_pos
```

### C#

```csharp
using Godot;

public partial class Enemy3D : CharacterBody3D
{
    [Export] public float Speed   { get; set; } = 4f;
    [Export] public float Gravity { get; set; } = 9.8f;

    private NavigationAgent3D _navAgent;

    public override void _Ready()
    {
        _navAgent = GetNode<NavigationAgent3D>("NavigationAgent3D");
        _navAgent.VelocityComputed += OnVelocityComputed;
    }

    public override void _PhysicsProcess(double delta)
    {
        var vel = Velocity;
        if (!IsOnFloor()) vel.Y -= Gravity * (float)delta;

        if (_navAgent.IsNavigationFinished())
        {
            Velocity = vel;
            MoveAndSlide();
            return;
        }

        Vector3 nextPos = _navAgent.GetNextPathPosition();
        var direction = (nextPos - GlobalPosition) with { Y = 0f };
        direction = direction.Normalized();
        vel.X = direction.X * Speed;
        vel.Z = direction.Z * Speed;

        if (_navAgent.AvoidanceEnabled)
            _navAgent.Velocity = vel;
        else
        {
            Velocity = vel;
            MoveAndSlide();
        }
    }

    private void OnVelocityComputed(Vector3 safeVelocity)
    {
        Velocity = safeVelocity;
        MoveAndSlide();
    }

    public void SetTarget(Vector3 targetPos) => _navAgent.TargetPosition = targetPos;
}
```

---

## 4. 조향(Steering) 동작

내비게이션 메시 없이 자연스러운 움직임을 만드는 가벼운 매 프레임 계산(seek, flee, arrive, wander)이다. 반환된 벡터를 합산해 조합하거나, 하나를 골라 매 `_physics_process` 틱마다 `velocity`에 할당한다.

---

## 5. 순찰 패턴

`NavigationAgent2D`에 `Marker2D` 웨이포인트 배열과 각 지점에서 멈추는 `Timer`를 더하면 깔끔한 순찰 루프가 된다. `wait_timer.timeout`에서 인덱스를 순환하고, `nav_agent.target_position`을 다음 웨이포인트로 설정하며, `is_navigation_finished()`로 이동을 게이트한다.

---

## 6. 행동 트리 개념

행동 트리(BT)는 매 틱마다 평가되는 노드 트리다. 세 가지 핵심 노드 타입:

| 타입 | 성공하는 때 | 실패하는 때 |
|---|---|---|
| **Sequence** | 모든 자식이 성공(AND) | 어느 자식이든 실패 |
| **Selector** | 어느 자식이든 성공(OR) | 모든 자식이 실패 |
| **Action** | 리프 액션이 완료 | 리프가 실패를 보고 |

Sequence는 "A 다음 B 다음 C를 한다"를 모델링한다. Selector는 "A를 시도, 안 되면 B, 안 되면 C"를 모델링한다.

---

## 7. 추격 + 공격 패턴

NavigationAgent2D를 상태 머신과 결합한다. 전체 FSM 인프라는 **state-machine** 스킬을 참고하라.

### 상태

| 상태 | 진입 조건 | 종료 조건 |
|---|---|---|
| PATROL | 기본 / 플레이어 도주 | 플레이어가 detect_range 진입 |
| CHASE | 플레이어가 detect_range 안 | 플레이어가 attack_range 안 OR 플레이어 도주 |
| ATTACK | 플레이어가 attack_range 안 | 플레이어가 attack_range를 벗어남 |

> 더 큰 프로젝트에서는 **state-machine** 스킬을 써서 각 상태를 자체 노드 클래스로 뽑아내고, 부모에서 `NavigationAgent2D` 참조를 주입하라.

---

## 8. 전용 2D 내비게이션 서버 (Godot 4.5+)

Godot 4.5 이전에는 `NavigationServer2D`가 내부적으로 모든 작업을 3D 내비게이션 서버에 위임하는 얇은 프런트엔드였다. Godot 4.5는 이 둘을 완전히 독립된 서버로 분리한다. 이 변경은 **투명하다** — API 변경도, 코드 마이그레이션도 필요 없다 — 하지만 두 가지 실질적 이점을 가져온다:

- **성능:** 2D 경로 탐색이 더 이상 서버 자원을 두고 3D 내비게이션과 경쟁하지 않는다. 에이전트가 많은 큰 2D 씬은 CPU 오버헤드가 낮아진다.
- **2D 전용 게임의 더 작은 익스포트:** 3D 내비게이션 서버를 2D 전용 익스포트 템플릿에서 제거해 바이너리 크기를 줄일 수 있다.

```gdscript
# No code change needed — NavigationServer2D calls work identically.
# The split is internal; you continue using NavigationServer2D as before.

# Example: query a path directly via the server (unchanged API).
func get_path_to(target: Vector2) -> PackedVector2Array:
    var map: RID = get_world_2d().get_navigation_map()
    return NavigationServer2D.map_get_path(
        map,
        global_position,
        target,
        true  # optimize path
    )
```

```csharp
// No code change needed — NavigationServer2D calls work identically.
public PackedVector2Array GetPathTo(Vector2 target)
{
    var map = GetWorld2D().GetNavigationMap();
    return NavigationServer2D.MapGetPath(map, GlobalPosition, target, true);
}
```

> **2D 전용 프로젝트:** **Project Settings → Modules**에서 `NavigationServer3D` 모듈을 비활성화해 익스포트 크기를 줄일 수 있다. 프로젝트 어디에도 3D 내비게이션 노드(`NavigationRegion3D`, `NavigationAgent3D`)를 쓰지 않을 때만 안전하다.

---

## 9. 흔한 함정

| 함정 | 증상 | 해결 |
|---|---|---|
| **내비게이션 메시를 안 구움** | 에이전트가 가만히 있음; 경로 없음 | 실행 전에 NavigationPolygon/NavigationMesh를 굽거나, 씬 로드 후 런타임에 `bake_navigation_polygon()` 호출 |
| **`agent_radius`가 너무 큼** | 에이전트가 출입구나 좁은 통로를 통과 못 함 | NavigationAgent의 `radius`를 통로 폭 절반보다 살짝 작게 낮춤 |
| **회피 지터** | 다른 에이전트 근처에서 에이전트가 떨거나 진동 | `time_horizon_agents`를 늘리거나(2–4초 시도) 에이전트의 `max_speed`를 약간 낮춤 |
| **경로 재계산이 너무 잦음** | 매 프레임 CPU 스파이크; 에이전트 지연 | `Timer`(0.2–0.5초)를 추가하고 매 물리 프레임이 아니라 타이머가 발동할 때만 `target_position`을 설정 |
| **잘못된 내비게이션 레이어** | 에이전트가 일부 리전을 무시하거나 경로를 못 찾음 | `navigation_layers` 비트마스크가 NavigationRegion과 NavigationAgent 간에 일치하는지 확인 |
| **NavigationServer가 준비되기 전에 목표 설정** | 첫 프레임에 경로가 비어 있음 | `target_position` 할당을 `_ready()`로 미루거나 `NavigationServer2D.map_changed`를 await |
| **3D에서 중력 무시** | 에이전트가 뜨거나 바닥에 가라앉음 | 항상 `velocity.y`를 중력으로 별도로 누적; nav 방향에서는 X/Z만 0으로 만듦 |
| **베이킹이 프레임 드랍 유발** | 큰 맵의 동기 베이킹이 메인 스레드를 막음 | 비동기 베이킹 사용: `bake_navigation_mesh(true)`(Godot 4.4+); `bake_finished` 시그널 연결 |

> ⚠️ **Godot 4.7에서 변경됨:** `NavigationServer3D.map_get_closest_point_normal(map, to_point)`가 이제 정규화된 벡터를 반환한다([GH-119022](https://github.com/godotengine/godot/pull/119022)) — 이전에는 반환된 표면 노멀이 정규화되지 않았을 수 있었다. 결과에 `normalized()`를 호출해 보정하던 코드는 계속 동작하고, 정규화되지 않은 크기에 의존하던 코드는 깨진다.

---

## 10. 체크리스트

- [ ] NavigationRegion2D/3D가 NavigationPolygon/NavigationMesh 리소스와 함께 씬에 추가돼 있다
- [ ] 내비게이션 메시가 구워졌다(편집 시점이나, 에이전트가 경로를 필요로 하기 전 런타임에)
- [ ] `navigation_layers` 비트마스크가 NavigationRegion과 NavigationAgent 간에 일치한다
- [ ] `NavigationAgent2D`/`NavigationAgent3D`가 적 노드의 **자식**이다
- [ ] `get_target_position()`이 아니라 `get_next_path_position()`이 매 물리 프레임 호출된다
- [ ] `avoidance_enabled`가 `true`일 때 `velocity_computed` 시그널이 연결돼 있다
- [ ] 목적지에서의 지터를 피하려고 이동 전에 `is_navigation_finished()`를 확인한다
- [ ] 이동하는 플레이어를 따라갈 때 경로 목표를 매 프레임이 아니라 스로틀 타이머로 갱신한다
- [ ] `agent_radius`가 레벨의 가장 좁은 통로를 통과할 만큼 작다
- [ ] 중력이 수평 nav 속도와 독립적으로 적용된다(3D만)
- [ ] 크거나 동적인 맵은 프레임 드랍을 피하려고 비동기 베이킹(`bake_navigation_mesh(true)`)을 쓴다(Godot 4.4+)
- [ ] Godot 4.5+의 2D 전용 프로젝트는 익스포트 크기를 줄이려고 Project Settings에서 `NavigationServer3D`를 비활성화할 수 있다
