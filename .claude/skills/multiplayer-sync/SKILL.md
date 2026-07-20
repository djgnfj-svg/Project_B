---
name: multiplayer-sync
description: 멀티플레이어 상태를 동기화할 때 사용한다 — MultiplayerSynchronizer, 보간, 예측, 그리고 지연 보상(lag compensation)
---

# Godot 4.3+에서의 멀티플레이어 동기화

모든 예제는 Godot 4.3+를 대상으로 하며 폐기된 API를 쓰지 않는다. GDScript를 먼저 보이고, 그다음 C#을 보인다.

> **관련 스킬:** ENet 설정·RPC·권한 모델은 **multiplayer-basics**, 헤드리스 익스포트와 배포는 **dedicated-server**, 물리 보간과 RigidBody 동기화는 **physics-system**을 보라.

---

## 1. MultiplayerSynchronizer

`MultiplayerSynchronizer`는 네트워크 너머로 속성을 복제하는 Godot 내장 노드다. 상태를 공유하려는 노드의 자식으로 추가하라.

### 하는 일

- **권한(authority)** 피어에서 다른 모든 피어로, 구성된 간격마다 속성 값을 보낸다
- **델타 동기화**(변경된 값만)와 **전체 동기화**(매 틱 모든 값)를 둘 다 지원
- **가시성 필터(visibility filter)**로 어느 피어가 업데이트를 받을지 제어

### 에디터에서 복제 구성

1. 씬 트리에서 `MultiplayerSynchronizer` 노드를 선택한다.
2. 인스펙터에서 **Replication**을 열고 **Add Property**를 클릭한다.
3. 부모 노드 경로와 속성 이름(예: `position`, `velocity`)을 고른다.
4. 속성별로 **Sync**(매 간격 전송) 또는 **Spawn**(스폰 시에만 전송)을 설정한다.
5. **Replication Interval**(초)을 설정한다. `0`은 매 물리 프레임을 뜻한다.

### 핵심 속성

| Property | Description |
|---|---|
| `replication_interval` | 전체 동기화 업데이트 간격(초). `0` = 매 물리 프레임 |
| `delta_interval` | 델타 동기화 업데이트 간격(초). `0` = 비활성 |
| `public_visibility` | `true`면 업데이트가 모든 피어에 감 (기본값) |
| `visibility_filters` | `Callable` 배열; 각각 피어가 업데이트를 받아야 하면 `true` 반환 |

### 델타 vs 전체 동기화

| Mode | How It Works | Best For |
|---|---|---|
| **전체 동기화** | 구성된 모든 속성을 매 `replication_interval`마다 전송 | 단순 객체, 낮은 속성 수 |
| **델타 동기화** | 마지막 동기화 이후 변경된 속성만, 매 `delta_interval`마다 전송 | 속성은 많지만 드물게 바뀌는 객체 |

둘을 함께 써라: 주기적 전체 상태에는 `replication_interval`을, 빈번한 변경만-버스트에는 `delta_interval`을 설정한다.

### 가시성 필터 (GDScript)

```gdscript
# Only send updates to peers within 500 units of this object.
func _ready() -> void:
    $MultiplayerSynchronizer.add_visibility_filter(_is_peer_in_range)

func _is_peer_in_range(peer_id: int) -> bool:
    var peer_player := _get_player_node(peer_id)
    if peer_player == null:
        return false
    return global_position.distance_to(peer_player.global_position) <= 500.0
```

### 가시성 필터 (C#)

```csharp
// Only send updates to peers within 500 units of this object.
public override void _Ready()
{
    var sync = GetNode<MultiplayerSynchronizer>("MultiplayerSynchronizer");
    sync.AddVisibilityFilter(Callable.From<int>(IsPeerInRange));
}

private bool IsPeerInRange(int peerId)
{
    var peerPlayer = GetPlayerNode(peerId);
    if (peerPlayer is null)
        return false;
    return GlobalPosition.DistanceTo(peerPlayer.GlobalPosition) <= 500.0f;
}
```

---

## 2. 속성 동기화

### 무엇을 동기화하나

원격 피어에서 시각적 상태를 재구성하는 데 필요한 최소 상태만 동기화하라. 전형적인 속성:

| Property | Type | Notes |
|---|---|---|
| `position` | `Vector2` / `Vector3` | 핵심 트랜스폼 — 매 프레임 동기화하거나 보간을 써라 |
| `velocity` | `Vector2` / `Vector3` | 원격 예측이 위치 스냅보다 앞서 있게 도움 |
| `health` | `int` / `float` | 변경 시 안정적으로 동기화; 델타 동기화가 이상적 |
| `animation_state` | `String` / `int` | 변경 시 동기화; 대역폭 절약을 위해 enum int 사용 |
| `is_crouching` | `bool` | 변화가 적은 불리언; 델타 동기화나 변경 시 RPC |

### 동기화되는 플레이어 (GDScript)

```gdscript
# synced_player.gd
extends CharacterBody2D

## Sync interval in seconds — exposed so designers can tune per object type.
@export var sync_interval: float = 0.05  # 20 Hz

@export var speed: float = 200.0

# These properties are listed in the MultiplayerSynchronizer replication config.
var synced_position: Vector2 = Vector2.ZERO
var synced_velocity: Vector2 = Vector2.ZERO
var synced_health: int = 100
var synced_anim: int = 0  # 0 = idle, 1 = run, 2 = jump

@onready var _sync: MultiplayerSynchronizer = $MultiplayerSynchronizer


func _ready() -> void:
    _sync.replication_interval = sync_interval
    # Only the authority (owner) drives movement.
    set_physics_process(is_multiplayer_authority())


func _physics_process(_delta: float) -> void:
    # Authority: write canonical state so MultiplayerSynchronizer can replicate it.
    synced_position = global_position
    synced_velocity = velocity
    synced_anim     = _compute_anim_state()
```

### 동기화되는 플레이어 (C#)

```csharp
// SyncedPlayer.cs
using Godot;

public partial class SyncedPlayer : CharacterBody2D
{
    /// <summary>Sync interval in seconds. Exposed so designers can tune per object type.</summary>
    [Export] public float SyncInterval { get; set; } = 0.05f; // 20 Hz

    [Export] public float Speed { get; set; } = 200.0f;

    // These properties are listed in the MultiplayerSynchronizer replication config.
    public Vector2 SyncedPosition { get; set; } = Vector2.Zero;
    public Vector2 SyncedVelocity { get; set; } = Vector2.Zero;
    public int SyncedHealth { get; set; } = 100;
    public int SyncedAnim   { get; set; } = 0; // 0=idle, 1=run, 2=jump

    private MultiplayerSynchronizer _sync = null!;

    public override void _Ready()
    {
        _sync = GetNode<MultiplayerSynchronizer>("MultiplayerSynchronizer");
        _sync.ReplicationInterval = SyncInterval;
        SetPhysicsProcess(IsMultiplayerAuthority());
    }

    public override void _PhysicsProcess(double delta)
    {
        // Authority: write canonical state for replication.
        SyncedPosition = GlobalPosition;
        SyncedVelocity = Velocity;
        SyncedAnim     = ComputeAnimState();
    }

    private int ComputeAnimState()
    {
        if (!IsOnFloor()) return 2;
        return Velocity.Length() > 1f ? 1 : 0;
    }
}
```

---

## 3. 보간(Interpolation)

`MultiplayerSynchronizer`는 동기화 간격(예: 30 Hz)마다 목표 속성을 갱신하지만, 렌더링은 프레임 레이트(60+ Hz)로 돈다. 보간이 없으면 원격 플레이어가 스냅샷 사이를 순간이동하는 것처럼 보인다. 해법: 타임스탬프와 함께 위치 스냅샷을 저장하고, 작은 오프셋(보간 버퍼 ~100 ms)을 두어 최신 스냅샷을 향해 `_process`에서 lerp한다.
---

## 4. 클라이언트 측 예측

로컬 플레이어 반응성을 위해: 클라이언트에서 이동을 즉시 예측하고, 입력을 서버로 보내고, 서버 스냅샷이 도착하면 조정(reconcile)한다. 서버가 클라이언트 예측에서 임계값 이상 벗어나면 스냅하고, 아니면 100-200 ms에 걸쳐 보정을 부드럽게 lerp한다.
---

## 5. 지연 보상(Lag Compensation)

빠른 템포의 게임에서 히트스캔 무기용: 서버가 명중을 검증할 때, 월드 상태를 클라이언트의 관측 시점(`now - client_rtt/2 - interp_delay`)으로 되감고 그 과거 상태에 대해 명중을 테스트한다.
---

## 6. 상태 vs 입력 동기화

게임의 필요에 맞는 동기화 모델을 골라라:

| Factor | Sync State | Sync Inputs |
|---|---|---|
| **무엇을 보내나** | 현재 속성 값(위치, 체력 등) | 매 프레임 플레이어 입력 액션 |
| **누가 시뮬레이션하나** | 권한만; 나머지는 결과를 받음 | 모든 피어가 같은 시뮬레이션을 실행 |
| **결정론 필요 여부** | 아니오 | 예 — 모든 피어가 같은 입력에서 동일한 출력을 내야 함 |
| **대역폭** | 더 높음 — 매 간격 전체 상태 전송 | 더 낮음 — 프레임당 작은 입력 구조체 |
| **반응성** | 더 낮음 — 비권한 피어는 다음 동기화 틱을 기다림 | 더 높음 — 결정론적이면 로컬 예측이 사소함 |
| **복잡도** | 더 낮음 — 조정 루프 없음 | 더 높음 — 결정론적 물리, 고정소수점 수학, 또는 lockstep 필요 |
| **적합** | 액션 게임, 슈터, 대부분의 실시간 게임 | 격투 게임, RTS, 턴제, 시뮬레이션 게임 |
| **지연 보상 필요** | 예, 명중 판정에 | 대개 불필요 — 모든 피어가 동기화됨 |

**하이브리드 접근**(대부분의 실시간 게임): 로컬 플레이어 캐릭터는 입력 동기화(예측 가능), 다른 모든 객체와 게임 이벤트는 상태 동기화.

---

## 7. 대역폭 최적화

네 가지 지렛대: **변경된 속성만 동기화**(속성별 복제 구성 플래그), **float 양자화**(Vector3 성분을 float 대신 mm로 — 16비트는 바이트를 2× 절감), **거리 기반 동기화 속도**(먼 객체는 5 Hz, 가까운 객체는 30 Hz로 동기화), 그리고 **채널 선택**(반드시 도착해야 하는 상태 변경은 reliable, 곧 덮어써질 위치 스트림은 unreliable).
---

## 8. 구현 체크리스트

- [ ] `MultiplayerSynchronizer`가 복제하는 노드의 직계 자식이다
- [ ] **권한** 피어만 동기화 속성에 쓴다; 나머지는 읽기 전용
- [ ] `set_multiplayer_authority()`가 스폰 시점에 올바른 피어 ID로 호출된다
- [ ] `replication_interval`과 `delta_interval`이 객체의 갱신 속도에 맞게 튜닝됨
- [ ] 원격 플레이어 시각은 `_physics_process`가 아니라 `_process`에서 보간을 쓴다
- [ ] 보간이 이전·현재 상태를 저장하고 `Engine.get_physics_interpolation_fraction()`으로 블렌드한다
- [ ] 클라이언트 측 예측은 로컬 플레이어 자신의 캐릭터에만 적용된다
- [ ] 대기 입력 버퍼가 유계(최대 ~128틱)로 메모리 증가를 막는다
- [ ] 조정 임계값이 미세 보정으로 인한 지터를 막는다
- [ ] 위치와 속도는 `unreliable` RPC; 상태 변경은 `reliable`
- [ ] 위치 데이터를 네트워크로 보내기 전에 float 양자화를 적용한다
- [ ] 지연 보상 스냅샷 히스토리를 매 틱 유계 윈도우로 정리한다
- [ ] 서버가 모든 명중 판정을 검증한다; 클라이언트는 절대 자체 킬을 보고하지 않는다
- [ ] 거리 기반 동기화 속도가 먼 객체의 대역폭을 줄인다
