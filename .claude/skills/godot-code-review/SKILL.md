---
name: godot-code-review
description: GDScript나 C# Godot 코드를 리뷰할 때 사용한다 — 모범 사례 체크리스트, 흔한 안티패턴, Godot 특유의 함정
---

# Godot 코드 리뷰

GDScript와 C#을 아우르는 Godot 4.3+ 프로젝트용 구조화된 리뷰 가이드. 각 체크리스트 섹션을 훑은 뒤, 맨 끝의 출력 템플릿으로 리뷰 요약을 만든다.

> **관련 스킬:** TDD와 테스트 커버리지는 **godot-testing**, 씬 트리 모범 사례는 **scene-organization**, 성능 리뷰는 **godot-optimization**.

---

## 1. 노드 & 씬 아키텍처

- [ ] 각 씬이 단일하고 명확한 책임을 갖는다 (플레이어, 적, UI 위젯 등)
- [ ] 상속 사슬이 얕다 — 깊은 `extends` 계층보다 자식 노드를 통한 컴포지션을 선호
- [ ] 오토로드(싱글턴)를 아껴 쓴다; 진짜 전역 상태만 거기에 속한다
- [ ] 노드 참조가 직속 자식까지만 순회한다 — `get_parent()` 사슬 없음
- [ ] `@onready`(GDScript)나 `GetNode<T>()`(C#)가 같은 씬 안의 직속 자식이나 이름 붙은 경로를 대상으로 한다

### 안티패턴 — `get_parent()` 사슬

```gdscript
# BAD: tight coupling, breaks if the tree changes
func take_damage(amount: int) -> void:
    get_parent().get_parent().get_node("HUD").update_health(health)
```

```csharp
// BAD: tight coupling, breaks if the tree changes
public void TakeDamage(int amount)
{
    GetParent().GetParent().GetNode("HUD").Call("UpdateHealth", _health);
}
```

### 해결 — 대신 시그널을 emit하라

```gdscript
# GOOD: parent/ancestor listens; child stays decoupled
signal health_changed(new_health: int)

func take_damage(amount: int) -> void:
    health -= amount
    health_changed.emit(health)
```

```csharp
// GOOD: parent/ancestor listens; child stays decoupled
[Signal]
public delegate void HealthChangedEventHandler(int newHealth);

public void TakeDamage(int amount)
{
    _health -= amount;
    EmitSignal(SignalName.HealthChanged, _health);
}
```

---

## 2. GDScript 스타일

- [ ] 변수와 함수가 `snake_case`를 쓴다
- [ ] `class_name`으로 선언한 클래스 이름이 `PascalCase`를 쓴다
- [ ] 상수가 `SCREAMING_SNAKE_CASE`를 쓴다
- [ ] 모든 함수 파라미터와 반환 타입이 타입 힌트를 갖는다
- [ ] `@export` 변수가 명시적 타입을 포함한다
- [ ] 시그널 선언이 변수보다 앞, 파일 상단에 나타난다

### 나쁨 — 타입 미지정

```gdscript
var speed = 200
var health = 100

func move(direction):
    position += direction * speed

func heal(amount):
    health += amount
    return health
```

```csharp
// BAD: no explicit types, weak contracts
float speed = 200;
int health = 100;

public void Move(object direction)
{
    Position += (Vector2)direction * speed;
}

public object Heal(object amount)
{
    health += (int)amount;
    return health;
}
```

### 좋음 — 타입 지정

```gdscript
class_name PlayerController
extends CharacterBody2D

signal health_changed(new_health: int)
signal player_died()

const MAX_HEALTH: int = 100
const BASE_SPEED: float = 200.0

@export var speed: float = BASE_SPEED
@export var max_health: int = MAX_HEALTH

var health: int = max_health

func move(direction: Vector2) -> void:
    velocity = direction * speed
    move_and_slide()

func heal(amount: int) -> int:
    health = mini(health + amount, max_health)
    health_changed.emit(health)
    return health
```

```csharp
// GOOD: strongly typed, proper C# conventions
public partial class PlayerController : CharacterBody2D
{
    [Signal]
    public delegate void HealthChangedEventHandler(int newHealth);
    [Signal]
    public delegate void PlayerDiedEventHandler();

    private const int MaxHealth = 100;
    private const float BaseSpeed = 200f;

    [Export] public float Speed { get; set; } = BaseSpeed;
    [Export] public int MaxHp { get; set; } = MaxHealth;

    private int _health;

    public override void _Ready()
    {
        _health = MaxHp;
    }

    public void Move(Vector2 direction)
    {
        Velocity = direction * Speed;
        MoveAndSlide();
    }

    public int Heal(int amount)
    {
        _health = Mathf.Min(_health + amount, MaxHp);
        EmitSignal(SignalName.HealthChanged, _health);
        return _health;
    }
}
```

---

## 3. C# 스타일

- [ ] 노드 스크립트가 Godot 소스 생성기가 동작하도록 `partial class`를 쓴다
- [ ] 메서드와 프로퍼티가 `PascalCase`를; 지역 변수가 `camelCase`를 쓴다
- [ ] `[Export]` 프로퍼티가 `PascalCase`를 쓴다
- [ ] `[Signal]` 델리게이트가 `<EventName>EventHandler` 명명 패턴을 따른다
- [ ] `GetNode<T>()` 결과를 `_Ready()`에서 null 검사하거나 캐시하고 검증한다

```csharp
// GOOD
public partial class PlayerController : CharacterBody2D
{
    [Signal]
    public delegate void HealthChangedEventHandler(int newHealth);

    [Export] public float Speed { get; set; } = 200f;
    [Export] public int MaxHealth { get; set; } = 100;

    private int _health;
    private AnimationPlayer _animationPlayer = null!;

    public override void _Ready()
    {
        _animationPlayer = GetNode<AnimationPlayer>("AnimationPlayer");
        // Validate at startup rather than silently failing later
        if (_animationPlayer is null)
            GD.PushError("AnimationPlayer node not found on PlayerController");

        _health = MaxHealth;
    }

    public void TakeDamage(int amount)
    {
        _health = Mathf.Max(_health - amount, 0);
        EmitSignal(SignalName.HealthChanged, _health);
    }
}
```

---

## 4. 성능

- [ ] `get_node()` / `$NodePath`를 `_process()`나 `_physics_process()` 안에서 절대 부르지 않는다 — 항상 `@onready`로 캐시
- [ ] `load()`를 핫 패스에서 부르지 않는다 — 컴파일 타임 로딩엔 `preload()`를 쓰거나 결과를 캐시
- [ ] 노드가 프레임별 갱신이 필요 없으면 `_process()`를 비활성화한다 (`set_process(false)`)
- [ ] `_process()`나 타이트 루프 안 비교에는 `StringName`(또는 `&"string"` 리터럴)을 쓴다

### 안티패턴 — `_process()` 안의 캐시 안 된 노드 조회

```gdscript
# BAD: get_node() traverses the tree every frame
func _process(delta: float) -> void:
    get_node("HUD/HealthBar").value = health
    get_node("HUD/Label").text = str(health)
```

```csharp
// BAD: GetNode() traverses the tree every frame
public override void _Process(double delta)
{
    GetNode<ProgressBar>("HUD/HealthBar").Value = _health;
    GetNode<Label>("HUD/Label").Text = _health.ToString();
}
```

### 해결 — `@onready`로 캐시

```gdscript
# GOOD: resolved once at scene load
@onready var _health_bar: ProgressBar = $HUD/HealthBar
@onready var _health_label: Label = $HUD/Label

func _process(delta: float) -> void:
    _health_bar.value = health
    _health_label.text = str(health)
```

```csharp
// GOOD: resolved once in _Ready()
private ProgressBar _healthBar = null!;
private Label _healthLabel = null!;

public override void _Ready()
{
    _healthBar = GetNode<ProgressBar>("HUD/HealthBar");
    _healthLabel = GetNode<Label>("HUD/Label");
}

public override void _Process(double delta)
{
    _healthBar.Value = _health;
    _healthLabel.Text = _health.ToString();
}
```

### 핫 패스의 StringName

```gdscript
# BAD: new String allocation compared each frame
if animation_name == "run":
    pass

# GOOD: StringName literal, no allocation
if animation_name == &"run":
    pass
```

```csharp
// BAD: allocates a new StringName each frame
if (animationName == "run") { }

// GOOD: cache StringName as a static field
private static readonly StringName RunAnim = new("run");

public override void _Process(double delta)
{
    if (animationName == RunAnim) { }
}
```

---

## 5. 입력 처리

- [ ] 모든 액션이 하드코딩된 키 상수가 아니라 Input Map 이름(Project > Project Settings > Input Map)을 쓴다
- [ ] UI 컨트롤이 이벤트를 먼저 소비하도록 `_input()`보다 `_unhandled_input()`을 선호한다
- [ ] 연속 이동이 `_physics_process()` 안의 `Input.get_vector()` / `Input.is_action_pressed()`로 구동된다
- [ ] 개별 일회성 액션(점프, 발사)이 `_unhandled_input()`에서 처리된다

```gdscript
# Continuous movement — physics process
func _physics_process(delta: float) -> void:
    var direction: Vector2 = Input.get_vector(
        &"ui_left", &"ui_right", &"ui_up", &"ui_down"
    )
    velocity = direction * speed
    move_and_slide()

# Discrete action — unhandled input
func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed(&"jump"):
        _jump()
```

```csharp
// Continuous movement — physics process
public override void _PhysicsProcess(double delta)
{
    Vector2 direction = Input.GetVector(
        "ui_left", "ui_right", "ui_up", "ui_down"
    );
    Velocity = direction * Speed;
    MoveAndSlide();
}

// Discrete action — unhandled input
public override void _UnhandledInput(InputEvent @event)
{
    if (@event.IsActionPressed("jump"))
    {
        Jump();
    }
}
```

---

## 6. 시그널 & 통신

- [ ] 시그널이 트리 **위로** 이동한다(자식이 emit, 부모/조상이 연결); 메서드 호출은 **아래로** 간다(부모가 자식 메서드 호출)
- [ ] 연결이 `_ready()`에서 이뤄지거나 에디터에서 배선된다 — `_process()`나 일회성 콜백에서가 아니다
- [ ] 노드 간 순환 시그널 의존이 없다
- [ ] 시그널 이름이 무슨 일이 일어났는지 서술하는 **과거 시제**를 쓴다

```gdscript
# Good signal names
signal health_changed(new_health: int)   # past tense
signal enemy_died()                       # past tense
signal item_collected(item: ItemData)     # past tense

# Bad signal names (present/imperative tense)
# signal update_health(value: int)
# signal die()
# signal collect_item(item: ItemData)
```

```csharp
// Good signal names — past tense, EventHandler suffix
[Signal]
public delegate void HealthChangedEventHandler(int newHealth);
[Signal]
public delegate void EnemyDiedEventHandler();
[Signal]
public delegate void ItemCollectedEventHandler(ItemData item);

// Bad signal names (present/imperative tense)
// public delegate void UpdateHealthEventHandler(int value);
// public delegate void DieEventHandler();
// public delegate void CollectItemEventHandler(ItemData item);
```

```gdscript
# Parent connects to child signal in _ready()
func _ready() -> void:
    $Enemy.enemy_died.connect(_on_enemy_died)
    $Player.health_changed.connect(_on_player_health_changed)
```

```csharp
// Parent connects to child signal in _Ready()
public override void _Ready()
{
    GetNode<Enemy>("Enemy").EnemyDied += OnEnemyDied;
    GetNode<Player>("Player").HealthChanged += OnPlayerHealthChanged;
}
```

---

## 7. 리소스 관리

- [ ] 편집 시점에 알려진 리소스(씬, 텍스처, 오디오)에는 `preload()`를; 런타임에 해석되는 경로에는 `load()`를 쓴다
- [ ] 런타임에 로드되는 크거나 레벨 특정 리소스는 프레임 정체를 피하려 `ResourceLoader.load_threaded_request()`를 쓴다
- [ ] 동적으로 인스턴스화된 노드는 use-after-free 크래시를 피하려 `free()`가 아니라 `queue_free()`로 해제한다

```gdscript
# Compile-time — path is validated by the editor
const BULLET_SCENE: PackedScene = preload("res://scenes/bullet.tscn")

# Runtime — path comes from data
func _load_level(path: String) -> void:
    ResourceLoader.load_threaded_request(path)

func _check_load(path: String) -> void:
    if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
        var scene: PackedScene = ResourceLoader.load_threaded_get(path)
        get_tree().change_scene_to_packed(scene)

# Cleanup
func _on_enemy_died() -> void:
    queue_free()   # safe — deferred until end of frame
```

```csharp
// Compile-time equivalent — load once in a static field or _Ready()
private static readonly PackedScene BulletScene =
    GD.Load<PackedScene>("res://scenes/bullet.tscn");

// Runtime — path comes from data
private void LoadLevel(string path)
{
    ResourceLoader.LoadThreadedRequest(path);
}

private void CheckLoad(string path)
{
    if (ResourceLoader.LoadThreadedGetStatus(path) == ResourceLoader.ThreadLoadStatus.Loaded)
    {
        var scene = ResourceLoader.LoadThreadedGet(path) as PackedScene;
        GetTree().ChangeSceneToPacked(scene);
    }
}

// Cleanup
private void OnEnemyDied()
{
    QueueFree(); // safe — deferred until end of frame
}
```

---

## 8. 오류 유발 패턴

| 패턴 | 문제 | 해결 |
|---|---|---|
| `queue_free()` 후 `await get_tree().create_timer(t).timeout` | 해제된 노드에서 타이머 시그널이 발화해 에러 발생 | `await` 후 `is_instance_valid(self)` 검사, 또는 자동 정지하는 `create_tween()` 사용 |
| `$A/B/C/D/E` 같은 취약한 노드 경로 | 씬 트리 재구성 시 조용히 깨짐 | 직속 자식 + 시그널로 리팩터, 또는 `NodePath` export |
| `call_deferred()`를 어디서나 사용 | defer는 크로스 프레임 안전에 적합하지, 일반 해결책이 아니다; 남용은 진짜 설계 문제를 가린다 | 물리/메인 스레드 경계를 넘거나 호출 순환을 끊을 때만 defer |
| `_physics_process()` 안에서 `set_physics_process(true)` 호출 | 프레임마다 중복 호출; CPU 낭비 | 실제로 처리를 켜고/끄고 싶은 지점에서 한 번만 호출 |
| `CharacterBody2D`에 `position`을 직접 설정 | 충돌 우회; 바디를 순간이동시켜 터널링 유발 가능 | `velocity`로 `move_and_slide()` 사용; 의도적 순간이동에만 `position`/`global_position` 설정 |

---

## 9. 리뷰 출력 형식

리뷰를 전달할 때 이 템플릿을 써라:

```
## Code Review — <FileName or Feature>

### Critical
Issues that will cause bugs, crashes, or significant performance problems.

- [ ] <node/line> — <issue> — **Suggested fix:** <fix>

### Improvements
Code quality, style, or maintainability concerns that should be addressed.

- [ ] <node/line> — <issue> — **Suggested fix:** <fix>

### Positive
What the code does well — reinforce good patterns.

- <observation>

---
Reviewed against: Godot 4.3+ best practices
```

### 예시

```
## Code Review — PlayerController.gd

### Critical
- [ ] _process() line 42 — `get_node("HUD/HealthBar")` called every frame — **Suggested fix:** Cache with `@onready var _health_bar: ProgressBar = $HUD/HealthBar`
- [ ] take_damage() line 67 — no type hints on parameter or return — **Suggested fix:** `func take_damage(amount: int) -> void:`

### Improvements
- [ ] Line 12 — signal `updateHealth` should be past tense — **Suggested fix:** Rename to `health_changed`
- [ ] Line 8 — `var speed = 200` missing type hint — **Suggested fix:** `var speed: float = 200.0`

### Positive
- Signals are declared at the top of the file
- Constants correctly use SCREAMING_SNAKE_CASE
- `queue_free()` used correctly for cleanup

---
Reviewed against: Godot 4.3+ best practices
```
