---
name: multithreading
description: 메인 스레드 밖에서 작업을 실행할 때 사용한다 — WorkerThreadPool, Thread/Mutex/Semaphore, call_deferred, 스레드 안전한 씬 접근, 그리고 스레드 리소스 로딩
---

# 멀티스레딩

씬 트리를 손상시키지 않고 값비싼 작업을 메인 스레드 밖에서 실행한다. 짧은 병렬 작업에는 `WorkerThreadPool`을 우선하고, 장수 워커가 필요할 때만 `Thread`/`Mutex`/`Semaphore`를 꺼내라.

> **관련 스킬:** 스레딩 전 프로파일링은 **godot-optimization**, 에셋 임포트는 **assets-pipeline**, C# 세부는 **csharp-godot**, async/await 함정은 **gdscript-advanced**를 보라.

---

## 1. 스레딩 모델 & 안전 규칙

메인 스레드가 씬 트리를 소유한다 — **활성 씬 트리와 상호작용하는 것은 스레드 안전하지 않다.** 문서에 근거한 이 규칙들을 지켜라:

- **서버**(RenderingServer, PhysicsServer)는 **프로젝트 설정에서 활성화한 뒤에만** 스레드 안전하다(`Rendering > Driver > Thread Model = Separate`, `Physics > {2D,3D} > Run on Separate Thread`). 서버는 스레드 구동되는 수천 개의 인스턴스를 잘 처리한다.
- **NavigationServer2D/3D는 스레드 안전하고 스레드 친화적이다**(진짜 병렬 쿼리); `Navigation > Pathfinding > Max Threads`를 튜닝하라.
- **AStar2D/3D/Grid2D는 스레드 안전하지 않다** — 객체당 전용 스레드 하나만; 한 객체를 여러 스레드에서 공유하면 데이터가 손상된다.
- **GDScript `Array`/`Dictionary`:** 여러 스레드에서 기존 요소를 읽고/쓰는 건 괜찮다; **크기 변경(추가/제거)에는 `Mutex`가 필요하다.**
- **메인 스레드 밖에서 GPU 작업 금지**(텍스처 생성, 이미지 읽기/수정) — RenderingServer 동기화 지연을 유발한다.
- 스레드에서 **씬 청크를 트리 밖에서 만들고**, 메인 스레드에서 `add_child.call_deferred()`로 추가하라 — 단일 로더 스레드에서만(여러 스레드는 같은 캐시된 리소스를 건드릴 위험 → 크래시).

> **황금 규칙:** 씬 트리는 메인 스레드에서만 변경하라. 워커에서는 `call_deferred` / `set_deferred`로 결과를 넘겨라.

---

## 2. WorkerThreadPool (우선)

`WorkerThreadPool`은 시작 시 스레드를 할당하는 전역 싱글톤이다. 일반 작업(`add_task`)은 워커 하나에서 실행되고, **그룹 작업**(`add_group_task`)은 워커들에 분산되어 각 요소 인덱스마다 `Callable`을 반복 호출한다 — 많은 요소를 순회할 때 좋다. **모든 작업은 대기(wait)해야 한다**(`wait_for_task_completion` / `wait_for_group_task_completion`), 아니면 할당된 리소스가 새어 나간다. 값싼 작업을 분산하면 성능이 나빠질 수 있다 — 진짜 값비싼 작업에만 써라.

### GDScript

```gdscript
var enemies = [] # Filled with enemies elsewhere.

func process_enemy_ai(enemy_index):
    var processed_enemy = enemies[enemy_index]
    # Expensive per-enemy logic...

func _process(delta):
    var task_id = WorkerThreadPool.add_group_task(process_enemy_ai, enemies.size())
    # ... other main-thread work ...
    WorkerThreadPool.wait_for_group_task_completion(task_id)
    # Safe to read results now.
```

### C# 등가물

```csharp
private List<Node> _enemies = new(); // Filled with enemies elsewhere.

private void ProcessEnemyAI(int enemyIndex)
{
    Node processedEnemy = _enemies[enemyIndex];
    // Expensive per-enemy logic...
}

public override void _Process(double delta)
{
    long taskId = WorkerThreadPool.AddGroupTask(Callable.From<int>(ProcessEnemyAI), _enemies.Count);
    // ... other main-thread work ...
    WorkerThreadPool.WaitForGroupTaskCompletion(taskId);
    // Safe to read results now.
}
```

이는 멀티스레드 구간 동안 요소 개수가 일정하게 유지된다는 전제에 의존한다.

---

## 3. Thread / Mutex / Semaphore

실제 시그니처: `Thread.start(callable: Callable, priority := PRIORITY_NORMAL)`, `wait_to_finish()`(블록; free 전에 join), `is_alive()`. `Mutex`는 재진입 가능(`lock`/`unlock`/`try_lock`). `Semaphore`는 `wait()` / `post(count := 1)`을 노출한다.

### GDScript

정석적인 세마포어 생산자/소비자 + 깔끔한 종료 관용구:

```gdscript
var counter := 0
var mutex: Mutex
var semaphore: Semaphore
var thread: Thread
var exit_thread := false

func _ready():
    mutex = Mutex.new()
    semaphore = Semaphore.new()
    thread = Thread.new()
    thread.start(_thread_function)

func _thread_function():
    while true:
        semaphore.wait() # Block until there is work.

        mutex.lock()
        var should_exit = exit_thread
        mutex.unlock()
        if should_exit:
            break

        mutex.lock()
        counter += 1
        mutex.unlock()

func increment_counter():
    semaphore.post() # Wake the worker.

func _exit_tree():
    mutex.lock()
    exit_thread = true
    mutex.unlock()
    semaphore.post()        # Unblock so it can see exit_thread.
    thread.wait_to_finish() # Join.
```

### C# 등가물

`Godot.Mutex`/`Godot.Semaphore`도 존재하지만, C#에서는 `System.Threading`이 관용적이다:

```csharp
using Godot;
using System.Threading;

public partial class Worker : Node
{
    private int _counter;
    private readonly object _lock = new();
    private readonly SemaphoreSlim _semaphore = new(0);
    private Thread _thread;
    private volatile bool _exitThread;

    public override void _Ready()
    {
        _thread = new Thread(ThreadFunction) { IsBackground = true };
        _thread.Start();
    }

    private void ThreadFunction()
    {
        while (true)
        {
            _semaphore.Wait();           // Block until there is work.
            if (_exitThread) break;
            lock (_lock) { _counter++; }
        }
    }

    public void IncrementCounter() => _semaphore.Release(); // Wake the worker.

    public override void _ExitTree()
    {
        _exitThread = true;
        _semaphore.Release();            // Unblock so it can see _exitThread.
        _thread.Join();                  // Join.
    }
}
```

스레드 생성은 느리다(특히 Windows에서) — 무거운 작업 전에 미리 만들고, 필요 순간에 만들지 마라. 뮤텍스를 과도하게 잠그는 것도 비용이 크다.

---

## 4. 결과 넘기기: call_deferred / set_deferred

### GDScript

```gdscript
# Unsafe from a worker thread:
world.add_child(enemy)
# Safe:
world.add_child.call_deferred(enemy)
```

### C# 등가물

```csharp
// Unsafe from a worker thread:
world.AddChild(enemy);
// Safe — use the MethodName StringName constant, NOT "AddChild":
world.CallDeferred(Node.MethodName.AddChild, enemy);
```

C#에서 `CallDeferred("AddChild")`는 실패한다 — deferred/`Call`/`Connect` API는 Godot의 snake_case 이름을 쓴다. `Node.MethodName.*` 상수를 우선하라(함정과 할당을 둘 다 피한다).

---

## 5. 스레드 리소스 로딩

`ResourceLoader.load_threaded_request(path)`가 로드를 시작한다. 매 프레임 `load_threaded_get_status(path, progress)`를 폴링하고(`progress[0]`이 0–1 비율); `THREAD_LOAD_LOADED`에서 `load_threaded_get(path)`를 호출한다. **`load_threaded_get`은 로드가 끝나지 않았으면 `load()`처럼 블록한다** — 항상 먼저 폴링하라. 상태: `THREAD_LOAD_INVALID_RESOURCE` / `THREAD_LOAD_IN_PROGRESS` / `THREAD_LOAD_FAILED` / `THREAD_LOAD_LOADED`.

### GDScript

```gdscript
const SCENE_PATH := "res://enemy.tscn"
var _progress: Array = []

func _ready():
    ResourceLoader.load_threaded_request(SCENE_PATH)

func _process(_delta):
    var status := ResourceLoader.load_threaded_get_status(SCENE_PATH, _progress)
    match status:
        ResourceLoader.THREAD_LOAD_IN_PROGRESS:
            $ProgressBar.value = _progress[0] * 100.0
        ResourceLoader.THREAD_LOAD_LOADED:
            var scene: PackedScene = ResourceLoader.load_threaded_get(SCENE_PATH)
            add_child(scene.instantiate())
            set_process(false)
        ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
            push_error("Threaded load failed: %s" % SCENE_PATH)
            set_process(false)
```

### C# 등가물

```csharp
private const string ScenePath = "res://enemy.tscn";
private readonly Godot.Collections.Array _progress = new();

public override void _Ready() => ResourceLoader.LoadThreadedRequest(ScenePath);

public override void _Process(double delta)
{
    var status = ResourceLoader.LoadThreadedGetStatus(ScenePath, _progress);
    switch (status)
    {
        case ResourceLoader.ThreadLoadStatus.InProgress:
            GetNode<ProgressBar>("ProgressBar").Value = (double)_progress[0] * 100.0;
            break;
        case ResourceLoader.ThreadLoadStatus.Loaded:
            var scene = (PackedScene)ResourceLoader.LoadThreadedGet(ScenePath);
            AddChild(scene.Instantiate());
            SetProcess(false);
            break;
        case ResourceLoader.ThreadLoadStatus.Failed:
        case ResourceLoader.ThreadLoadStatus.InvalidResource:
            GD.PushError($"Threaded load failed: {ScenePath}");
            SetProcess(false);
            break;
    }
}
```

> **Godot 4.7+:** 4.7은 스레드 로드 정확성 수정을 여럿 실었다 — `load_threaded_get()` 데드락([GH-119757](https://github.com/godotengine/godot/pull/119757), [GH-120077](https://github.com/godotengine/godot/pull/120077)), `load_threaded_request()`의 경쟁 상태([GH-118824](https://github.com/godotengine/godot/pull/118824)), 그리고 `load_threaded_get()`이 반환한 리소스가 절대 언로드되지 않던 문제([GH-119394](https://github.com/godotengine/godot/pull/119394)). API 변경은 없다; 이전 버전에서 드문 스레드 로드 멈춤이나 누수에 대한 우회책을 들고 있다면, 유지하기 전에 4.7에서 재테스트하라. 위의 폴링-먼저 규칙은 여전히 적용된다.

---

## 6. C# 동시성: Task vs Godot 스레드

C#에서는 fire-and-forget CPU 작업에 `System.Threading.Tasks.Task.Run` / `async`-`await`를 우선하라; **백그라운드 스레드에서 Godot 객체를 건드리거나 `await ToSignal(...)`을 절대 하지 마라** — 결과는 `CallDeferred`로 마샬링해 돌려라. Godot의 풀과 엔진 통합을 원하면 `WorkerThreadPool`을, .NET 관용구를 원하면 `Task`를 써라. (GDScript 사용자: 위 절의 `WorkerThreadPool`이나 `Thread`를 써라.)

```csharp
public override void _Process(double delta)
{
    if (Input.IsActionJustPressed("compute"))
    {
        _ = System.Threading.Tasks.Task.Run(() =>
        {
            int result = ExpensiveComputation();   // Pure CPU work, no Godot objects.
            CallDeferred(MethodName.OnComputed, result); // Marshal back to main thread.
        });
    }
}

private void OnComputed(int result) => GD.Print($"Done: {result}");
```
---

## 구현 체크리스트

- [ ] 먼저 프로파일링 — 작업이 진짜 CPU-값비싼지 확인(**godot-optimization** 참고)
- [ ] 씬 트리 변경은 메인 스레드에서만(`call_deferred` / `set_deferred`)
- [ ] 모든 `WorkerThreadPool` 작업을 대기(`wait_for_*_completion`)
- [ ] 공유 상태는 `Mutex` / `lock`으로 보호; 컨테이너 크기 변경은 잠금
- [ ] 소유 노드가 free되기 전에 스레드를 join(`wait_to_finish` / `Join`)
- [ ] GPU 호출 없음, AStar 공유 없음, 스레드 간 같은 리소스 로드 없음
- [ ] 스레드 로드는 `load_threaded_get` 호출 전에 상태를 폴링
