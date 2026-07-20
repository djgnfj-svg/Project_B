---
name: dedicated-server
description: 전용 서버를 만들 때 쓴다 — 헤드리스 익스포트, 서버 아키텍처, 로비 관리, 배포
---

# Godot 4.3+ 전용 서버

모든 예제는 Godot 4.3+를 대상으로 하며 폐기된 API를 쓰지 않는다. GDScript를 먼저, 이어서 C#을 보인다.

**관련 스킬:** ENet 설정·RPC·권한 모델은 **multiplayer-basics**를 보라. 상태 동기화와 보간은 **multiplayer-sync**를 보라.

---

## 1. 헤드리스 익스포트

전용 서버는 디스플레이·GPU·오디오 장치 없이 돈다. Godot은 `--headless` 플래그와 전용 익스포트 프리셋을 통해 이를 지원한다.

### --headless 플래그

런타임에 디스플레이·오디오 드라이버를 억제하려면 커맨드 라인에 `--headless`를 넘겨라:

```
./my_game.x86_64 --headless
```

이는 `server` 플랫폼과 구별된다 — `--headless`는 어떤 익스포트 바이너리에서도 동작하는 런타임 플래그다. `server` 익스포트 템플릿은 바이너리에서 렌더링을 완전히 걷어내 크기를 줄인다.

### 서버 익스포트 프리셋

Godot 에디터에서 전용 **Linux/X11**(또는 **Linux Server**) 익스포트 프리셋을 만든다:

1. **Project → Export**를 연다.
2. **Linux/X11** 프리셋을 추가하고 `Linux Server`로 이름 짓는다.
3. **Options → Binary** 아래에서 **Export As Dedicated Server**(Godot 4.2+)를 활성화한다. 이는 렌더링과 오디오 코드를 뺀 서버 익스포트 템플릿을 사용한다.
4. **Resources** 아래에서 **Exclude** 목록으로 클라이언트 전용 에셋(셰이더, 고해상도 텍스처, 오디오 파일)을 서버 PCK에서 걷어낸다.

### Feature 태그

`OS.has_feature()`로 런타임에 서버 코드와 클라이언트 코드를 분기하라. 익스포트 프리셋(Project Settings → Export → Custom Features)에 커스텀 `server` feature를 정의하거나, 서버 템플릿이 자동으로 설정하는 내장 `dedicated_server` feature에 의존하라:

```gdscript
# boot.gd — autoload, runs before any scene loads
extends Node

func _ready() -> void:
    if OS.has_feature("dedicated_server") or DisplayServer.get_name() == "headless":
        # Disable rendering-dependent systems
        RenderingServer.set_render_loop_enabled(false)
        # Start server logic
        ServerBootstrap.start()
    else:
        # Start client logic
        ClientBootstrap.start()
```

```csharp
// Boot.cs — autoload, runs before any scene loads.
using Godot;

public partial class Boot : Node
{
    public override void _Ready()
    {
        if (OS.HasFeature("dedicated_server") || DisplayServer.GetName() == "headless")
        {
            // Disable the render loop. The window is invisible but the engine still ticks.
            RenderingServer.SetRenderLoopEnabled(false);
            ServerBootstrap.Start();
        }
        else
        {
            ClientBootstrap.Start();
        }
    }
}
```

> **참고:** 익스포트 프리셋 설정(커스텀 feature, exclude 목록, "Export As Dedicated Server" 플래그)은 언어와 무관하게 동일하다 — 프리셋 설정은 위 GDScript 절을 보라.

**Feature 태그 요약:**

| 태그 | 설정 주체 | 참고 |
|-----|--------|-------|
| `dedicated_server` | 서버 익스포트 템플릿 | 서버 바이너리를 감지하는 가장 확실한 방법 |
| `headless` | `--headless` CLI 플래그 | 런타임에 설정됨, 바이너리에 굳혀지지 않음 |
| 커스텀 `server` | 네 익스포트 프리셋의 Custom Features | 역할 간 바이너리를 공유할 때 유용 |

---

## 2. 서버 아키텍처

### 렌더링 없는 게임 루프

헤드리스 서버에서 `_process`와 `_physics_process`는 여전히 정상적으로 돈다 — 다만 아무것도 렌더되지 않는다. 결정론적·고정 레이트 업데이트를 위해 모든 서버 로직을 `_physics_process`에 두어라.

### GDScript

```gdscript
# server_main.gd — add as autoload named ServerMain
extends Node

## Physics frames per second — matches Project Settings → Physics → Common → Physics Ticks Per Second.
## Override via --tick-rate CLI argument (see Section 5).
var tick_rate: int = 60

## Current server tick counter.
var server_tick: int = 0


func _ready() -> void:
    # Guard: this node does nothing on the client.
    if not _is_server():
        set_process(false)
        set_physics_process(false)
        return

    Engine.physics_ticks_per_second = tick_rate
    print("[Server] Started — tick rate: %d Hz" % tick_rate)


func _physics_process(_delta: float) -> void:
    server_tick += 1
    _tick_game_logic()


func _tick_game_logic() -> void:
    # All authoritative game simulation goes here.
    # Never reference Camera, CanvasLayer, or any rendering node from this path.
    pass


## Returns true when this process is acting as the authoritative server.
func _is_server() -> bool:
    # Covers both: dedicated binary and hosted listen-server.
    return multiplayer.is_server()
```

### 클라이언트와 분리된 서버 전용 로직

서버 전용 노드를 전용 브랜치에 두고 클라이언트에서 건너뛰도록 씬을 구성하라:

```gdscript
# world.gd
extends Node

@onready var server_systems: Node = $ServerSystems   # physics, AI, scoring
@onready var client_systems: Node = $ClientSystems   # camera, HUD, audio


func _ready() -> void:
    # Disable server systems on clients and vice versa.
    server_systems.set_process_mode(
        PROCESS_MODE_ALWAYS if multiplayer.is_server() else PROCESS_MODE_DISABLED
    )
    client_systems.set_process_mode(
        PROCESS_MODE_DISABLED if multiplayer.is_server() else PROCESS_MODE_ALWAYS
    )
```

### Engine.is_editor_hint() + is_server 검사

에디터, 서버, 클라이언트에서 다르게 동작해야 하는 스크립트의 맨 위에 이 가드를 두어라:

```gdscript
func _ready() -> void:
    if Engine.is_editor_hint():
        return  # Skip all runtime setup in editor preview

    if multiplayer.is_server():
        _server_init()
    else:
        _client_init()


func _server_init() -> void:
    print("[Server] Initializing authoritative state")


func _client_init() -> void:
    print("[Client] Initializing local presentation layer")
```

### C#

```csharp
// ServerMain.cs — add as autoload named ServerMain
using Godot;

public partial class ServerMain : Node
{
    /// <summary>Physics ticks per second. Override via --tick-rate CLI argument.</summary>
    public int TickRate { get; set; } = 60;

    /// <summary>Current server tick counter.</summary>
    public int ServerTick { get; private set; }

    public override void _Ready()
    {
        if (!IsServer())
        {
            SetProcess(false);
            SetPhysicsProcess(false);
            return;
        }

        Engine.PhysicsTicksPerSecond = TickRate;
        GD.Print($"[Server] Started — tick rate: {TickRate} Hz");
    }

    public override void _PhysicsProcess(double delta)
    {
        ServerTick++;
        TickGameLogic();
    }

    private void TickGameLogic()
    {
        // All authoritative game simulation goes here.
    }

    private bool IsServer() => Multiplayer.IsServer();
}
```

```csharp
// World.cs
using Godot;

public partial class World : Node
{
    [Export] private Node _serverSystems = null!;
    [Export] private Node _clientSystems = null!;

    public override void _Ready()
    {
        if (Engine.IsEditorHint()) return;

        _serverSystems.ProcessMode = Multiplayer.IsServer()
            ? ProcessModeEnum.Always
            : ProcessModeEnum.Disabled;

        _clientSystems.ProcessMode = Multiplayer.IsServer()
            ? ProcessModeEnum.Disabled
            : ProcessModeEnum.Always;
    }
}
```

---

## 7. 체크리스트

- [ ] 익스포트 프리셋이 **server** 익스포트 템플릿을 사용(`dedicated_server` feature가 자동 설정됨)
- [ ] 클라이언트 전용 에셋(셰이더, 오디오, 고해상도 텍스처)이 서버 PCK에서 제외됨
- [ ] 부트 스크립트가 `OS.has_feature("dedicated_server")` 또는 `DisplayServer.get_name() == "headless"`로 서버 vs 클라이언트 시작을 분기
- [ ] 서버에서 어떤 렌더 작업도 막기 위해 `RenderingServer.set_render_loop_enabled(false)` 호출
- [ ] 서버 전용 노드는 클라이언트에서 `PROCESS_MODE_DISABLED`; 클라이언트 전용 노드는 서버에서 `PROCESS_MODE_DISABLED`
- [ ] 부작용이 있는 모든 스크립트의 `_ready()` 맨 위에 `Engine.is_editor_hint()` 가드
- [ ] `ServerConfig`가 다른 오토로드의 `_ready()` 전에 CLI 인자에서 `--port`, `--max-players`, `--tick-rate`를 파싱
- [ ] `server.cfg`가 없을 때 설정 파일 로딩이 우아하게 폴백
- [ ] 환경 변수(`SERVER_PORT`, `SERVER_MAX_PLAYERS`, `SERVER_TICK_RATE`)가 설정 파일 뒤·CLI 인자 앞에 적용됨
- [ ] 새 피어를 받기 전에 `LobbyManager.player_list` 크기를 `max_players`와 대조
- [ ] 로비가 가득 차면 닫기 전에 RPC로 피어를 킥
- [ ] `MatchState`가 `LOBBY`로 돌아갈 때 ready 상태를 리셋해 라운드마다 다시 확인하게 함
- [ ] `MatchManager`가 서버에서만 `_physics_process`를 실행(클라이언트에서는 `SetPhysicsProcess(false)`)
- [ ] 카운트다운·결과 타이머가 `Timer` 노드가 아니라 `_physics_process` delta로 구동됨(씬 의존성 회피)
- [ ] Dockerfile이 바이너리와 `.pck` 파일을 모두 이미지에 복사
- [ ] 첫 테스트 실행 전에 VPS 방화벽에서 UDP 포트를 개방
- [ ] systemd 서비스에 `Restart=on-failure`가 있어 서버가 크래시에서 자동 복구
- [ ] 로그가 systemd journal로 라우팅되어 `journalctl -u <service> -f`로 검사 가능

## 3. 로비 시스템

`peer_id`로 키를 매기는 플레이어별 상태 딕셔너리가 정석 패턴이다. 서버가 권위 있는 딕셔너리를 쥐고; 클라이언트는 RPC로 업데이트를 받는다. `--max-players` CLI 상한과 ready-toggle RPC를 구현해 모든 피어가 시작 전에 확인하게 하라.

---

## 4. 매치 흐름

로비 → 카운트다운 → 인게임 → 결과를 상태 기계로 구동하라. 서버가 권위를 가지며 — 클라이언트는 상태 변경 RPC만 받는다. 흔한 상태: `LOBBY`, `COUNTDOWN`, `IN_GAME`, `RESULTS`.

---

## 5. 서버 설정

`OS.get_cmdline_args()`에서 `--port`, `--max-players`, `--tick-rate`, `--log-level`의 CLI 플래그를 파싱하라. 첫 물리 프레임 *전에* `Engine.physics_ticks_per_second`를 미리 설정하고; 나머지를 읽고 쓰는 것은 단순한 `match` / `switch` 작업이다.

---

## 6. 배포

`Dockerfile`과 `systemd` 서비스 파일을 갖춘 Linux VPS가 표준 프로덕션 레이아웃이다. Dockerfile은 헤드리스 익스포트 템플릿, 익스포트된 PCK, .NET 런타임(C# 프로젝트용)을 묶는다. systemd는 자동 재시작, `journald`를 통한 로그 로테이션, 리소스 제한을 처리한다.

---

## 7. 체크리스트

- [ ] 헤드리스 익스포트 프리셋 생성 및 `dedicated_server` feature 태그 추가
- [ ] `OS.has_feature("dedicated_server")`가 true일 때 `RenderingServer.set_render_loop_enabled(false)`(및 오디오 버스 뮤트)
- [ ] 서버 측 오토로드가 시스템 초기화 전에 `multiplayer.is_server()`를 검사
- [ ] 시작 시 port·max-players·tick-rate·log-level용 CLI 인자 파싱
- [ ] 로비 상태는 서버에만 존재; 클라이언트는 RPC로 업데이트 수신
- [ ] 매치 흐름 상태 기계가 명시적 전이와 단일 진실원(서버)을 가짐
- [ ] 프로덕션 배포가 자동 재시작·로그 로테이션을 위해 systemd 또는 Docker 사용
- [ ] 프로덕션 프리셋에서 헤드리스 빌드가 **Export with Debug** 꺼진 채 익스포트됨
