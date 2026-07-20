---
name: multiplayer-basics
description: 멀티플레이어를 구현할 때 사용한다 — MultiplayerAPI, ENet/WebSocket 피어, RPC, 그리고 권한(authority) 모델
---

# Godot 4.3+에서의 멀티플레이어 기초

모든 예제는 Godot 4.3+를 대상으로 하며 폐기된 API를 쓰지 않는다. GDScript를 먼저 보이고, C#이 뒤따른다.

**관련 스킬:** 상태 동기화와 보간은 **multiplayer-sync**를 보라. 헤드리스 익스포트와 서버 배포는 **dedicated-server**를 보라.

---

## 1. 멀티플레이어 아키텍처

Godot은 `MultiplayerAPI` 위에 세워진 **클라이언트-서버 모델**을 쓴다. 한 피어가 서버 역할을 하고, 나머지 모두는 클라이언트다. 모든 피어는 네트워크 계층이 부여하는 고유 정수 ID를 갖는다:

| Peer ID | Role |
|---------|------|
| `1` | 서버 (항상) |
| `2`, `3`, … | 연결된 클라이언트 |

**멀티플레이어 권한(authority)**은 노드에 대한 소유권 개념이다. 권한을 가진 피어만이 입력을 읽고 그 노드의 상태를 구동해야 한다. 기본적으로 서버(피어 `1`)가 모든 노드의 권한이다. 소유권을 클라이언트로 넘기려면 `set_multiplayer_authority(peer_id)`를 호출하라.

```
Server (peer 1)
    ├── Owns game state by default
    ├── Spawns and validates objects
    └── Routes RPCs
Client (peer 2, 3, …)
    ├── Sends input to server via RPC
    └── Receives state updates from server
```

---

## 2. ENetMultiplayerPeer 설정하기

### GDScript

```gdscript
# network_manager.gd — add as autoload named NetworkManager
extends Node

const DEFAULT_PORT := 7777
const MAX_CLIENTS  := 16

var peer: ENetMultiplayerPeer


func host_game(port: int = DEFAULT_PORT) -> void:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		push_error("NetworkManager: create_server failed — error %d" % err)
		return
	multiplayer.multiplayer_peer = peer
	_connect_signals()
	print("NetworkManager: hosting on port %d" % port)


func join_game(address: String, port: int = DEFAULT_PORT) -> void:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		push_error("NetworkManager: create_client failed — error %d" % err)
		return
	multiplayer.multiplayer_peer = peer
	_connect_signals()
	print("NetworkManager: connecting to %s:%d" % [address, port])


func disconnect_from_game() -> void:
	if peer:
		peer.close()
	multiplayer.multiplayer_peer = null


func _connect_signals() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)


func _on_peer_connected(id: int) -> void:
	print("NetworkManager: peer connected — id %d" % id)


func _on_peer_disconnected(id: int) -> void:
	print("NetworkManager: peer disconnected — id %d" % id)


func _on_connected_to_server() -> void:
	print("NetworkManager: connected to server — my id is %d" % multiplayer.get_unique_id())


func _on_connection_failed() -> void:
	push_error("NetworkManager: connection failed")
```

**핵심 시그널 요약:**

| Signal | Fires on | When |
|--------|----------|------|
| `peer_connected` | 서버 + 클라이언트 | 새 피어가 연결을 마침 |
| `peer_disconnected` | 서버 + 클라이언트 | 피어가 끊기거나 타임아웃됨 |
| `connected_to_server` | 클라이언트만 | 이 클라이언트가 연결에 성공함 |
| `connection_failed` | 클라이언트만 | 이 클라이언트가 연결하지 못함 |

### C#

```csharp
// NetworkManager.cs — add as autoload named NetworkManager
using Godot;

public partial class NetworkManager : Node
{
    private const int DefaultPort  = 7777;
    private const int MaxClients   = 16;

    private ENetMultiplayerPeer _peer;

    public void HostGame(int port = DefaultPort)
    {
        _peer = new ENetMultiplayerPeer();
        var err = _peer.CreateServer(port, MaxClients);
        if (err != Error.Ok)
        {
            GD.PushError($"NetworkManager: CreateServer failed — error {err}");
            return;
        }
        Multiplayer.MultiplayerPeer = _peer;
        ConnectSignals();
        GD.Print($"NetworkManager: hosting on port {port}");
    }

    public void JoinGame(string address, int port = DefaultPort)
    {
        _peer = new ENetMultiplayerPeer();
        var err = _peer.CreateClient(address, port);
        if (err != Error.Ok)
        {
            GD.PushError($"NetworkManager: CreateClient failed — error {err}");
            return;
        }
        Multiplayer.MultiplayerPeer = _peer;
        ConnectSignals();
        GD.Print($"NetworkManager: connecting to {address}:{port}");
    }

    public void DisconnectFromGame()
    {
        _peer?.Close();
        Multiplayer.MultiplayerPeer = null;
    }

    private void ConnectSignals()
    {
        Multiplayer.PeerConnected      += OnPeerConnected;
        Multiplayer.PeerDisconnected   += OnPeerDisconnected;
        Multiplayer.ConnectedToServer  += OnConnectedToServer;
        Multiplayer.ConnectionFailed   += OnConnectionFailed;
    }

    private void OnPeerConnected(long id)
        => GD.Print($"NetworkManager: peer connected — id {id}");

    private void OnPeerDisconnected(long id)
        => GD.Print($"NetworkManager: peer disconnected — id {id}");

    private void OnConnectedToServer()
        => GD.Print($"NetworkManager: connected — my id is {Multiplayer.GetUniqueId()}");

    private void OnConnectionFailed()
        => GD.PushError("NetworkManager: connection failed");
}
```

---

## 3. RPC

`@rpc`(GDScript) / `[Rpc]`(C#)는 메서드를 네트워크 너머에서 호출 가능하게 표시한다. 모드와 전송 설정을 신중히 골라라 — 보안과 성능 둘 다에 영향을 준다.

### RPC 모드

| Mode | Who may call it | Executes on |
|------|-----------------|-------------|
| `"authority"` (기본값) | 권한 피어만 | 전송 대상 피어(들) |
| `"any_peer"` | 연결된 아무 피어나 | 전송 대상 피어(들) |

### 전송 모드

| Mode | Delivery | Order | Use For |
|------|----------|-------|---------|
| `"reliable"` | 보장됨 | 순서대로 | 채팅, 스폰 이벤트, 중요한 상태 |
| `"unreliable"` | 최선 노력 | 순서 없음 | 고빈도 위치 업데이트 |
| `"unreliable_ordered"` | 최선 노력 | 채널별 순서대로 | 부드러운 이동 스트림 |

### GDScript

```gdscript
# chat.gd
extends Node

# Any peer can call this; executed on the server only.
# The server then broadcasts to all peers.
@rpc("any_peer", "reliable")
func send_chat_message(text: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	_broadcast_chat.rpc(sender_id, text)


# Only the authority (server) can call this; runs on every peer.
@rpc("authority", "reliable", "call_local")
func _broadcast_chat(sender_id: int, text: String) -> void:
	print("[%d]: %s" % [sender_id, text])


# Client → server: request to spawn an object.
@rpc("any_peer", "reliable")
func request_spawn(scene_path: String, spawn_position: Vector2) -> void:
	if not multiplayer.is_server():
		return
	# Server validates and performs the actual spawn.
	var scene: PackedScene = load(scene_path)
	if scene == null:
		return
	var instance := scene.instantiate()
	instance.global_position = spawn_position
	get_tree().root.add_child(instance)


# High-frequency position sync — unreliable_ordered is acceptable here.
# transfer_channel separates this stream from other RPC traffic.
@rpc("authority", "unreliable_ordered", "call_local", 1)
func sync_position(pos: Vector2) -> void:
	global_position = pos
```

**특정 피어에게 보내기:**

```gdscript
# Send to everyone (including self if call_local is set):
send_chat_message.rpc("Hello!")

# Send to one specific peer:
send_chat_message.rpc_id(target_peer_id, "Hello!")
```

### C#

```csharp
// Chat.cs
using Godot;

public partial class Chat : Node
{
    // Any peer can call; executes on the server only.
    [Rpc(MultiplayerApi.RpcMode.AnyPeer, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
    public void SendChatMessage(string text)
    {
        if (!Multiplayer.IsServer()) return;
        int senderId = Multiplayer.GetRemoteSenderId();
        Rpc(MethodName.BroadcastChat, senderId, text);
    }

    // Authority only; runs on every peer including the caller.
    [Rpc(MultiplayerApi.RpcMode.Authority,
         CallLocal = true,
         TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
    private void BroadcastChat(int senderId, string text)
        => GD.Print($"[{senderId}]: {text}");

    // Client → server: request a spawn.
    [Rpc(MultiplayerApi.RpcMode.AnyPeer, TransferMode = MultiplayerPeer.TransferModeEnum.Reliable)]
    public void RequestSpawn(string scenePath, Vector2 spawnPosition)
    {
        if (!Multiplayer.IsServer()) return;
        var scene = GD.Load<PackedScene>(scenePath);
        if (scene == null) return;
        var instance = scene.Instantiate<Node2D>();
        instance.GlobalPosition = spawnPosition;
        GetTree().Root.AddChild(instance);
    }

    // High-frequency position sync.
    [Rpc(MultiplayerApi.RpcMode.Authority,
         CallLocal = true,
         TransferMode = MultiplayerPeer.TransferModeEnum.UnreliableOrdered,
         TransferChannel = 1)]
    public void SyncPosition(Vector2 pos)
        => GlobalPosition = pos;
}
```

**C#에서 특정 피어에게 보내기:**

```csharp
// Broadcast to all:
Rpc(MethodName.SendChatMessage, "Hello!");

// Send to one peer:
RpcId(targetPeerId, MethodName.SendChatMessage, "Hello!");
```

---

## 4. 권한(Authority) 모델

모든 노드는 정확히 하나의 권한 피어를 갖는다 — 그 노드의 상태 업데이트를 보내도록 허용된 피어다. 다른 피어들은 들어오는 상태를 읽기 전용으로 취급해야 한다.

### GDScript

```gdscript
# player.gd
extends CharacterBody2D

func _ready() -> void:
	# multiplayer.get_unique_id() returns this peer's ID.
	# The server assigns authority during spawn (see Section 6).
	pass


func _physics_process(delta: float) -> void:
	# Guard: only the authority peer reads input and moves.
	if not is_multiplayer_authority():
		return

	var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = direction * 200.0
	move_and_slide()

	# Broadcast position to all other peers.
	sync_position.rpc(global_position)


@rpc("authority", "unreliable_ordered", "call_local", 1)
func sync_position(pos: Vector2) -> void:
	if not is_multiplayer_authority():
		global_position = pos


# Check who owns this node at runtime:
func print_authority_info() -> void:
	print("My peer ID : %d" % multiplayer.get_unique_id())
	print("Authority  : %d" % get_multiplayer_authority())
	print("Am I auth? : %s" % str(is_multiplayer_authority()))
```

### C#

```csharp
// Player.cs
using Godot;

public partial class Player : CharacterBody2D
{
    public override void _PhysicsProcess(double delta)
    {
        // Guard: only the authority peer processes input.
        if (!IsMultiplayerAuthority()) return;

        var direction = Input.GetVector("ui_left", "ui_right", "ui_up", "ui_down");
        Velocity = direction * 200f;
        MoveAndSlide();

        Rpc(MethodName.SyncPosition, GlobalPosition);
    }

    [Rpc(MultiplayerApi.RpcMode.Authority,
         CallLocal = true,
         TransferMode = MultiplayerPeer.TransferModeEnum.UnreliableOrdered,
         TransferChannel = 1)]
    private void SyncPosition(Vector2 pos)
    {
        if (!IsMultiplayerAuthority())
            GlobalPosition = pos;
    }
}
```

**API 요약:**

| Method | Returns | Notes |
|--------|---------|-------|
| `multiplayer.get_unique_id()` | `int` | 이 피어의 ID |
| `get_multiplayer_authority()` | `int` | 이 노드를 소유한 피어의 ID |
| `is_multiplayer_authority()` | `bool` | 이 피어가 이 노드를 소유하면 true |
| `set_multiplayer_authority(id)` | `void` | 소유권 이전; 서버에서 호출 |

---

## 5. 네트워크 객체 스폰

`MultiplayerSpawner`를 써서 씬 인스턴스를 피어 전체에 복제한다. 서버가 스폰된 노드의 부모에 자식을 추가하면, 스포너가 그것을 동기화된 상태로 모든 피어에 미러링한다. 동적 스폰 경로는 `_spawnable_scenes`를 구성하고 서버에서만 `add_child(scene.instantiate())`를 호출하라.
---

## 6. 플레이어 합류 흐름

전체 로비 합류 생명주기: 피어 연결 → 서버가 슬롯 할당 → 로비 씬 로드 → 플레이어 노드 스폰 → 모든 클라이언트에 피어 목록 브로드캐스트 → "매치 시작" RPC 시 모든 피어를 게임플레이 씬으로 전환.
---

## 7. 연결 해제 처리

`multiplayer` API의 `peer_disconnected(id)`를 수신하라. 서버에서는: 끊긴 피어의 플레이어 노드를 해제하고 갱신된 피어 목록을 브로드캐스트한다. 클라이언트에서는: 서버 연결 해제를 감지하고 재접속 / 메인 메뉴 화면으로 라우팅한다.
---

## 8. 흔한 함정

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| 잘못된 권한에서 RPC 호출 | `rpc_id`가 조용히 무시됨; 메서드가 실행 안 됨 | 보내기 전에 `is_multiplayer_authority()`를 검사; `"any_peer"`는 의도한 곳에만 |
| 순서 없는 RPC로 인한 디싱크 | 위치가 지터/순간이동 | 스트림에는 `"unreliable_ordered"`; 중요한 상태 변경에는 `"reliable"` |
| `_process` vs `_physics_process`에서 입력 읽기 | 프레임 레이트가 다르면 이동 디싱크 | `CharacterBody2D`는 항상 `_physics_process`에서 이동; 동기화 RPC도 거기서 |
| 입력 전 `is_multiplayer_authority()` 미검사 | 모든 피어가 모든 플레이어를 조종 | 입력 처리 맨 위에 `if not is_multiplayer_authority(): return` 가드 추가 |
| `MultiplayerSpawner` 없이 스폰 | 서버엔 나타나고 클라이언트엔 없음 | 복제돼야 하는 서버의 모든 런타임 `add_child`는 `MultiplayerSpawner.spawn()`을 거쳐야 함 |
| 권한 RPC에 `call_local` 빠뜨림 | 서버 상태가 자기 노드와 어긋남 | 발신자도 로컬에서 RPC를 실행해야 하면 `"call_local"` 추가 |
| 피어 할당 전에 `rpc()` 사용 | 크래시 또는 조용한 실패 | 어떤 RPC 호출보다 먼저 `multiplayer.multiplayer_peer`를 할당 |
| 익스포트 빌드에서 `res://` 씬 미제거 | 클라이언트가 서버 전용 스크립트를 읽을 수 있음 | 민감한 서버 코드는 `export_exclude`나 PCK 암호화를 써라 |

---

## 9. 체크리스트

- [ ] `ENetMultiplayerPeer.create_server()` / `create_client()`가 `OK`를 반환한 뒤에 `multiplayer.multiplayer_peer`에 할당한다
- [ ] 네 개의 멀티플레이어 시그널을 모두 연결: `peer_connected`, `peer_disconnected`, `connected_to_server`, `connection_failed`
- [ ] 플레이어 입력을 읽는 모든 노드가 `if not is_multiplayer_authority(): return`으로 가드한다
- [ ] 입력 처리와 `sync_position` RPC 둘 다 `_process`가 아니라 `_physics_process`에 있다
- [ ] RPC 모드를 의도적으로 선택: `"any_peer"`는 클라이언트 → 서버 호출에만; `"authority"`는 서버 → 클라이언트
- [ ] unreliable RPC는 고빈도 업데이트(위치, 회전)에만 사용; 이벤트(스폰, 피해, 채팅)에는 reliable
- [ ] 첫 플레이어가 합류하기 전에 `MultiplayerSpawner`가 모든 스폰 가능 씬으로 구성됨
- [ ] 각 플레이어 노드가 스폰된 뒤 서버에서 `set_multiplayer_authority(peer_id)`를 호출
- [ ] `peer_disconnected` 핸들러가 플레이어 노드를 해제하고 추적 컬렉션에서 제거
- [ ] 클라이언트의 `server_disconnected` 핸들러가 메인 메뉴로 돌아가고 `multiplayer.multiplayer_peer`를 null로
- [ ] 연결 해제 콜백에서 저장된 노드 참조를 역참조하기 전에 `is_instance_valid()`를 검사
- [ ] `multiplayer.multiplayer_peer`가 할당되기 전에 `rpc()` 호출을 하지 않는다
