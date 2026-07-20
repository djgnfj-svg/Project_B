---
name: godot-optimization
description: Godot 게임을 최적화할 때 사용한다 — 프로파일러, 드로우콜, 물리 튜닝, 메모리 관리, 흔한 병목
---

# Godot 최적화

이 스킬은 GDScript와 C# 양쪽의 Godot 4.3+ 프로젝트를 위한 성능 최적화를 다룬다. 내장 프로파일러, 드로우콜 감소, 물리 튜닝, GDScript 성능 패턴, 메모리 관리, 오브젝트 풀링, 그리고 흔한 병목 참조 표를 다룬다.

> **관련 스킬:** 체계적 디버깅과 프로파일링은 **godot-debugging**, 성능 리뷰 체크리스트는 **godot-code-review**, 릴리스 빌드 최적화는 **export-pipeline**, 충돌 셰이프·레이어·물리 바디 타입은 **physics-system**, 2D 메시 최적화·파티클 성능·드로우 순서 튜닝은 **2d-essentials**, 메인 스레드 밖으로 작업 옮기기는 **multithreading**, 모바일 성능 예산은 **mobile-development**.

---

## 1. 프로파일러 사용

### 프레임 타임 예산

60 fps에서는 프레임 전체(업데이트, 물리, 렌더링)가 **16.6 ms** 안에 끝나야 한다. 30 fps에서는 예산이 33.3 ms다. 그 예산의 대부분을 소비하는 단일 시스템이 병목이다.

| 목표 FPS | 프레임 예산 |
|---|---|
| 120 | 8.3 ms |
| 60 | 16.6 ms |
| 30 | 33.3 ms |

### 프로파일러 출력 읽기

**Debugger > Profiler**를 열고 **Start**를 누른 뒤, 측정하려는 시나리오를 플레이하고 **Stop**을 누른다.

- **Frame Time** — 그 프레임의 총 실측 시간(밀리초).
- **Self** — 호출된 함수를 *제외한* 그 함수 내부 시간. 이것이 주된 핫스팟 지표다. Self time이 높은 함수는 직접 비싼 작업을 하고 있다.
- **Total** — 모든 호출된 함수를 포함한 시간. 비싼 서브트리를 식별하는 데 유용하다.
- **Calls** — 프레임당 호출 수. 프레임당 수천 번 호출되는 함수는(호출당은 싸도) 프레임을 지배할 수 있다.
- 함수 이름을 클릭하면 스크립트 에디터의 소스로 점프한다.

```gdscript
# Manual micro-benchmark for a specific block
var start := Time.get_ticks_usec()
_run_expensive_operation()
var elapsed := Time.get_ticks_usec() - start
print("_run_expensive_operation: %d µs" % elapsed)
```

**C#:**

```csharp
// Manual micro-benchmark using Stopwatch (high-resolution timer)
using System.Diagnostics;

var sw = Stopwatch.StartNew();
RunExpensiveOperation();
sw.Stop();
GD.Print($"RunExpensiveOperation: {sw.Elapsed.TotalMilliseconds:F3} ms");

// Alternative using Godot's built-in timer (microsecond precision)
long start = (long)Time.GetTicksUsec();
RunExpensiveOperation();
long elapsed = (long)Time.GetTicksUsec() - start;
GD.Print($"RunExpensiveOperation: {elapsed} µs");
```

### Monitors 탭

**Debugger > Monitors**는 게임이 도는 동안 실시간 엔진 지표를 보여 준다. 모니터 이름을 클릭하면 라이브 그래프가 열린다. 지켜볼 핵심 모니터:

| 모니터 | 무엇을 지켜보나 |
|---|---|
| `Time > FPS` | 목표 미만 — 프레임 예산 초과 |
| `Time > Process` | 높음 — `_process()` 콜백이 비쌈 |
| `Time > Physics Process` | 높음 — `_physics_process()`나 물리 시뮬이 비쌈 |
| `Render > Total Draw Calls` | ~500(모바일)이나 ~2 000(데스크톱) 초과 — 배칭 필요 |
| `Render > Video RAM` | 꾸준히 증가 — 해제 안 된 텍스처나 메시(메모리 누수) |
| `Object > Object Count` | 씬 리로드에 걸쳐 증가 — 노드가 해제 안 됨 |
| `Physics 3D > Active Bodies` | 단순한 씬에서 큰 수 — 바디가 잠들지 않음 |

```gdscript
# Query any monitor at runtime from code
var fps := Performance.get_monitor(Performance.TIME_FPS)
var draw_calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
var video_ram := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
print("FPS: %d | Draw calls: %d | VRAM: %.1f MB" % [fps, draw_calls, video_ram / 1_048_576.0])
```

**C#:**

```csharp
// Query any monitor at runtime from code
double fps = Performance.GetMonitor(Performance.Monitor.TimeFps);
double drawCalls = Performance.GetMonitor(Performance.Monitor.RenderTotalDrawCallsInFrame);
double videoRam = Performance.GetMonitor(Performance.Monitor.RenderVideoMemUsed);
GD.Print($"FPS: {fps:F0} | Draw calls: {drawCalls:F0} | VRAM: {videoRam / 1_048_576.0:F1} MB");
```

---

## 2. 드로우콜 최적화

이웃과 배칭될 수 없는 개별 메시, 스프라이트, 캔버스 아이템 하나하나가 드로우콜 하나를 든다. 드로우콜을 줄이는 것은, 특히 모바일에서, 가장 레버리지가 큰 최적화 중 하나다 — 텍스처를 공유하는 2D 그룹을 `CanvasGroup`으로 감싸고, 고유 머티리얼 수를 낮게 유지하고, 스프라이트를 아틀라스하고, 화면 밖 작업을 컬링하라.

---

## 3. 물리 최적화

물리 튜닝은 브로드페이즈 작업을 최소화하고 움직이는 바디에 메시 콜라이더를 피하는 데 달려 있다. 충돌 마스크를 각 바디가 실제로 필요한 레이어로만 잘라내고, 움직이는 것에서는 `ConcavePolygonShape3D`를 프리미티브로 교체하고, 겹침 감지에는 프레임별 레이캐스트보다 `Area2D/3D`를 선호하라.

---

## 4. GDScript 성능

핫 패스 GDScript 이득은 프레임별 할당 제거, `String` 대신 `StringName` 비교, 타입 배열 / `PackedArray` 사용, 클래스 스코프에서 리소스 `preload`에서 나온다. 같은 할당 규율이 C#에도 적용된다(타입 `Array[T]` 자리에 `List<T>`, `static readonly StringName` 필드).

---

## 5. 메모리 관리

씬 리로드에 걸쳐 `Performance.MEMORY_STATIC`과 `OBJECT_COUNT`를 지켜보라 — 꾸준한 증가는 누수된 참조를 뜻한다. 경로로 로드된 리소스는 캐시되고 공유된다; 인스턴스별 변경이 필요하면 `.duplicate()`를 부르라. 노드는 항상 `queue_free()`를 선호하라; 자신이 emit한 시그널 안의 `free()`는 크래시한다.

---

## 6. 흔한 병목

| 문제 | 진단 도구 | 해결 |
|---|---|---|
| 드로우콜 과다 | Debugger > Monitors `Render > Total Draw Calls`; Viewport > Debug > Draw Calls 오버레이 | 2D 배칭에 `CanvasGroup` 사용; 3D는 메시 병합; 텍스처 아틀라스 사용; 고유 머티리얼 감소 |
| `_process`의 무거운 GDScript | Profiler > Self 열 상단에 스크립트 함수 표시 | 로직을 `_physics_process`(덜 자주 실행)로 옮기기, 쿼리 캐시, 프레임별 할당 회피, 타이트 루프엔 C# 고려 |
| 과도한 시그널 연결 | Profiler가 시그널 디스패치 오버헤드 표시; `get_signal_connection_list()` 수동 감사 | 중복 연결 제거; 고빈도 데이터엔 프레임별 시그널보다 폴링 선호; fire-and-forget엔 `CONNECT_ONE_SHOT` 사용 |
| 최적화 안 된 TileMap | Profiler가 `TileMap._process`나 높은 드로우콜 수 표시 | 더 적은 레이어로 분할; 레이어당 단일 아틀라스 텍스처 사용; 필요 없으면 `use_parent_material` 비활성화; 레거시 TileMap 대신 `TileMapLayer`(Godot 4.3+) 사용 |
| 큰 비압축 텍스처 | Monitors `Render > Video RAM`이 높음; Import 도크에서 텍스처 설정 확인 | Import 도크에서 텍스처 압축(VRAM Compressed) 활성화; 밉맵 사용; 가까이서 안 보는 에셋은 해상도 절반 |
| 활성 물리 바디 과다 | Monitors `Physics 3D > Active Bodies`가 높음; Profiler에서 느린 `_physics_process` | `RigidBody3D`에 sleeping 활성화(`can_sleep = true`); 물리 틱 레이트 낮추기; 먼 바디를 가짜 애니메이션으로 교체; 레이어/마스크로 충돌 검사 좁히기 |
| 핫 패스의 문자열 연산 | Profiler가 `String` 할당 함수 표시; 높은 GC 압박 | `String` 비교를 `StringName`(`&"..."`)으로 교체; `_process`에서 `String` 포매팅 회피; 문자열을 한 번 만들어 캐시 |
| 핫 패스의 `instantiate()` | Profiler가 높은 Self time의 `PackedScene.instantiate` 표시 | 오브젝트 풀링 구현; 시작 시 씬 preload; 게임플레이 중이 아니라 로딩 화면 중 스폰 |

---

## 7. 최상위 안티패턴

- **`_process`에서 할당** — 프레임마다 새 Array, Dictionary, String, Vector 생성자. 컨테이너를 캐시하고 필드를 제자리에서 변경하라.
- **움직이는 바디의 메시 콜라이더** — `CharacterBody3D`나 `RigidBody3D`의 `ConcavePolygonShape3D`. 대신 캡슐, 박스, 컨벡스 헐을 써라.
- **인스턴스별 고유 머티리얼** — `_ready()`의 `material_override = SomeMaterial.new()`는 배칭을 깨뜨린다. 머티리얼 하나를 공유하고 셰이더 파라미터로 변주하라.
- **핫 패스의 `load()`** — `_process`나 `_physics_process`에서 `load("res://...")` 호출. 클래스 스코프에서 `const X := preload(...)`를 써라.
- **단명 오브젝트에 `instantiate()` + `queue_free()`** — 총알, 히트 이펙트, 파티클. 풀링하라.

---

## 8. 체크리스트

출시 전이나 성능 불만을 조사할 때 이 목록을 훑어라.

**프로파일러**
- [ ] 가장 부하가 큰 게임플레이 시나리오 중에 프로파일러를 실행했다.
- [ ] 어떤 단일 함수의 Self time도 프레임 예산의 30%를 넘지 않음을 확인했다.
- [ ] 총 프레임 타임이 예산(60 fps에서 16.6 ms) 아래에 머묾을 확인했다.

**드로우콜**
- [ ] 드로우콜 수가 목표 안에 있다(모바일 ≤500, 데스크톱 ≤2 000).
- [ ] 텍스처를 공유하는 2D 스프라이트 그룹이 `CanvasGroup`으로 감싸여 있다.
- [ ] 가능한 곳에서 텍스처가 아틀라스 패킹돼 있다; 중복 머티리얼이 제거됐다.
- [ ] 화면 밖 노드가 `VisibleOnScreenNotifier2D/3D`로 처리를 멈춘다.
- [ ] 3D 메시가 임포트 설정이나 수동 스와프 로직으로 LOD가 활성화돼 있다.

**물리**
- [ ] 충돌 레이어와 마스크가 최소다 — 어떤 바디도 필요 없는 레이어를 검사하지 않는다.
- [ ] 어떤 움직이는 바디도 `ConcavePolygonShape`를 쓰지 않는다 — 캡슐, 박스, 컨벡스로 교체.
- [ ] 물리 틱 레이트가 게임 유형에 적절하다(턴제나 탑다운엔 30 Hz도 괜찮을 수 있음).
- [ ] 프레임별 레이캐스트 대신 겹침 감지에 `Area2D/3D`를 쓴다.
- [ ] 해당하는 곳에서 `RigidBody3D` 노드가 `can_sleep = true`를 갖는다.

**GDScript**
- [ ] `_process`나 `_physics_process` 안에서 어떤 `Array`, `Dictionary`, `String`도 할당되지 않는다.
- [ ] 모든 핫 패스 문자열 비교가 `StringName`(`&"..."`)을 쓴다.
- [ ] 핫 패스의 모든 배열이 타입 지정돼 있다(`Array[T]`나 `PackedArray`).
- [ ] 핫 패스의 모든 함수 파라미터와 반환 타입이 정적으로 타입 지정돼 있다.
- [ ] 모든 씬과 리소스 참조가 프레임별 `load`가 아니라 클래스 스코프의 `preload`를 쓴다.

**메모리**
- [ ] `Performance.get_monitor(Performance.MEMORY_STATIC)`가 씬 리로드 사이에 안정적이다.
- [ ] 인스턴스별 변경이 필요한 리소스가 `.duplicate()`돼 있다.
- [ ] 동기적 해체가 명시적으로 필요하지 않은 한 모든 노드 제거가 `queue_free()`를 쓴다.

**오브젝트 풀링**
- [ ] 총알, 히트 이펙트, 파티클, 그 밖에 자주 스폰되는 오브젝트가 풀을 쓴다.
- [ ] 풀 초기 크기가 정상 게임플레이 중 런타임 증가를 피할 만큼 크다.
- [ ] 풀링된 오브젝트가 재활성화 시 모든 상태를 초기화한다(위치, 속도, 시그널).
