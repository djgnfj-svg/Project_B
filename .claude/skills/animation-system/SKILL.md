---
name: animation-system
description: 애니메이션을 구현할 때 사용한다 — AnimationPlayer, AnimationTree, 블렌드 트리, 상태 머신, 스프라이트 애니메이션, 코드 주도 애니메이션
---

# Godot 4.3+의 애니메이션 시스템

모든 예제는 Godot 4.3+를 대상으로 하며 폐기된 API를 쓰지 않는다. GDScript를 먼저 보이고, 그다음 C#을 보인다.

> **관련 스킬:** 게임플레이 상태 관리는 **state-machine**, 애니메이션을 구동하는 이동은 **player-controller**, 재사용 가능한 애니메이션 컴포넌트는 **component-system**, TileMap·시차 스크롤·2D 조명·캔버스 레이어 구성은 **2d-essentials**, AnimationTree와 3D 애니메이션 블렌딩은 **3d-essentials**, 셰이더 주도 히트 플래시·디졸브 효과는 **shader-basics**, 키프레임 애니메이션과 나란히 쓰는 코드 주도 모션은 **tween-animation**을 참고하라.

---

## 1. 핵심 개념

### AnimationPlayer 대 AnimationTree

| 노드              | 용도                                  | 복잡도 | 비고                                              |
|-------------------|------------------------------------------|------------|----------------------------------------------------|
| `AnimationPlayer` | 단순 재생, 원샷 효과        | 낮음        | 개별 클립을 직접 재생/정지/큐          |
| `AnimationTree`   | 블렌딩, 전이, 레이어드 애니메이션 | 중간-높음| 부드러운 전이를 위한 상태 머신과 블렌드 트리 |

**경험칙:** AnimationPlayer로 시작한다. 애니메이션 간 블렌딩(걷기/뛰기 블렌드, 방향 이동, 레이어드 상/하체)이 필요할 때 AnimationTree를 더한다.

### 애니메이션 워크플로

```
1. Create AnimationPlayer node       → holds all animation clips
2. Add tracks in the Animation panel → keyframe properties, methods, audio
3. (Optional) Add AnimationTree      → blend/transition logic
4. Trigger from code                 → play(), travel(), set parameters
```

---

## 2. AnimationPlayer 기초

### 씬 구조

```
Character (CharacterBody2D)
├── Sprite2D
└── AnimationPlayer
```

AnimationPlayer는 형제나 자식 노드의 **어떤 속성이든** 애니메이션할 수 있다: 스프라이트 프레임, modulate, 위치, 회전, 스케일, 가시성, 충돌 셰이프 disabled 상태, 메서드 호출(Call Method 트랙), 오디오 재생(Audio Playback 트랙).

### GDScript — 기본 재생

```gdscript
extends CharacterBody2D

@onready var anim_player: AnimationPlayer = $AnimationPlayer

func _physics_process(delta: float) -> void:
    var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

    if input_dir != Vector2.ZERO:
        velocity = input_dir * 200.0
        anim_player.play("walk")
    else:
        velocity = Vector2.ZERO
        anim_player.play("idle")

    move_and_slide()
```

### C# — 기본 재생

```csharp
using Godot;

public partial class Character : CharacterBody2D
{
    private AnimationPlayer _animPlayer;

    public override void _Ready()
    {
        _animPlayer = GetNode<AnimationPlayer>("AnimationPlayer");
    }

    public override void _PhysicsProcess(double delta)
    {
        Vector2 inputDir = Input.GetVector("ui_left", "ui_right", "ui_up", "ui_down");

        if (inputDir != Vector2.Zero)
        {
            Velocity = inputDir * 200.0f;
            _animPlayer.Play("walk");
        }
        else
        {
            Velocity = Vector2.Zero;
            _animPlayer.Play("idle");
        }

        MoveAndSlide();
    }
}
```

> 이미 재생 중인 애니메이션과 같은 이름으로 `play()`를 호출하면 아무 일도 없다(재시작 안 됨). 매 프레임 호출해도 안전하다.

### 재생 제어

```gdscript
anim_player.play("attack")
anim_player.play_backwards("attack")
anim_player.queue("idle")            # play after current
anim_player.stop()
anim_player.pause()
anim_player.play()                   # resume from paused position
anim_player.speed_scale = 2.0
anim_player.seek(0.5)
```

```csharp
_animPlayer.Play("attack");
_animPlayer.PlayBackwards("attack");
_animPlayer.Queue("idle");
_animPlayer.Stop();
_animPlayer.Pause();
_animPlayer.Play();
_animPlayer.SpeedScale = 2.0;
_animPlayer.Seek(0.5);
```

---

## 3. 애니메이션 시그널

```gdscript
func _ready() -> void:
    anim_player.animation_finished.connect(_on_animation_finished)

func _on_animation_finished(anim_name: StringName) -> void:
    match anim_name:
        "attack":
            anim_player.play("idle")
        "death":
            queue_free()
```

```csharp
public override void _Ready()
{
    _animPlayer = GetNode<AnimationPlayer>("AnimationPlayer");
    _animPlayer.AnimationFinished += OnAnimationFinished;
}

private void OnAnimationFinished(StringName animName)
{
    if (animName == "attack")
        _animPlayer.Play("idle");
    else if (animName == "death")
        QueueFree();
}
```

### 메서드 호출 트랙

정확한 애니메이션 프레임에 게임 로직을 트리거하려면 **Call Method** 트랙을 추가한다(5번째 프레임에 투사체 스폰, 임팩트 프레임에 SFX 재생, 휘두르는 동안 히트박스 활성화). Animation 패널에서: Add Track → Call Method Track → 타깃 노드 선택 → 키프레임 추가 → 메서드 이름과 인자 설정.

```gdscript
func spawn_projectile() -> void:
    var bullet := preload("res://scenes/bullet.tscn").instantiate()
    get_parent().add_child(bullet)
    bullet.global_position = $Muzzle.global_position

func enable_hitbox() -> void:
    $HitboxArea/CollisionShape2D.disabled = false
```

---

## 4. 스프라이트 프레임 애니메이션

2D 캐릭터 애니메이션에는 두 접근법이 있다: `AnimatedSprite2D`(빠름, 프레임만)와 `AnimationPlayer + Sprite2D`(전체 속성 애니메이션). 단순한 캐릭터에는 AnimatedSprite2D를, 히트박스·파티클·사운드나 다른 속성도 동기화해 애니메이션할 때는 AnimationPlayer를 골라라.
### 핑퐁 재생 (Godot 4.7+)

`SpriteFrames`가 `LoopMode` enum을 얻는다 — `LOOP_NONE = 0`, `LOOP_LINEAR = 1`, `LOOP_PINGPONG = 2` — 애니메이션마다 `set_animation_loop_mode(anim, loop_mode)`로 설정하고 `get_animation_loop_mode(anim)`으로 읽는다. 예전의 bool `set_animation_loop()` / `get_animation_loop()`은 폐기됐다. 핑퐁은 애니메이션이 끝이나 시작에 도달할 때마다 방향을 번갈아 바꾸며, `AnimatedSprite2D`와 `AnimatedSprite3D` 둘 다에서 동작한다.

```gdscript
var frames: SpriteFrames = $AnimatedSprite2D.sprite_frames
frames.set_animation_loop_mode(&"sway", SpriteFrames.LOOP_PINGPONG)
```

```csharp
var frames = GetNode<AnimatedSprite2D>("AnimatedSprite2D").SpriteFrames;
frames.SetAnimationLoopMode("sway", SpriteFrames.LoopMode.Pingpong);
```

---

## 5. AnimationTree — 정석적 상태 머신

### 씬 구조

```
Character (CharacterBody2D)
├── Sprite2D
├── AnimationPlayer        ← holds all clips
└── AnimationTree          ← controls blending/transitions
    (tree_root = AnimationNodeStateMachine or AnimationNodeBlendTree)
```

**설정:** AnimationTree를 AnimationPlayer의 형제로 추가한다. `anim_player`가 AnimationPlayer를 가리키게 설정한다. `active = true`로 설정한다. 루트를 고른다: **AnimationNodeStateMachine**(전이가 있는 이산 상태) 또는 **AnimationNodeBlendTree**(연속 블렌딩).

### 상태 머신 재생

정석 패턴: `anim_tree["parameters/playback"]`에서 `AnimationNodeStateMachinePlayback`을 캐시하고, 게임플레이 코드에서 `travel("state")`를 호출하며(`travel()`은 부드럽게 전이하고 `start()`는 즉시 전환), `get_current_node()`로 활성 상태를 조회한다.
### 블렌드 트리 — BlendSpace1D / BlendSpace2D

연속 블렌딩용이다(속도 파라미터로 걷기↔뛰기; 2D 벡터로 4/8방향 이동). 루트를 **AnimationNodeBlendTree**로 설정하고, **BlendSpace1D**나 **BlendSpace2D**를 추가하며, 애니메이션을 방위 위치에 배치한다(예: walk @ 0.0, run @ 1.0; idle_down @ (0,1), idle_right @ (1,0)). 매 프레임 블렌드를 구동한다:

```gdscript
# 1D — speed blend
var blend_amount := inverse_lerp(walk_speed, run_speed, velocity.length())
anim_tree["parameters/BlendSpace1D/blend_position"] = blend_amount

# 2D — direction blend
anim_tree["parameters/BlendSpace2D/blend_position"] = input_dir
```

```csharp
_animTree.Set("parameters/BlendSpace1D/blend_position", blendAmount);
_animTree.Set("parameters/BlendSpace2D/blend_position", inputDir);
```

### 이름 붙은 블렌드 포인트 (Godot 4.7+)

`AnimationNodeBlendSpace1D/2D.add_blend_point()`가 선택적 `name: StringName = &""` 파라미터를 얻고, 블렌드 포인트 이름/인덱스를 에디터에서 설정·표시할 수 있다. 이름을 명시적으로 전달하는 것이 권장된다(빈 이름은 폐기 예정) — `find_blend_point_by_name()`으로 포인트를 조회한다.

```gdscript
blend_space.add_blend_point(walk_node, 0.0, -1, &"walk")
blend_space.add_blend_point(run_node, 1.0, -1, &"run")
var run_index := blend_space.find_blend_point_by_name(&"run")
```

```csharp
blendSpace.AddBlendPoint(walkNode, 0.0f, -1, "walk");
blendSpace.AddBlendPoint(runNode, 1.0f, -1, "run");
int runIndex = blendSpace.FindBlendPointByName("run");
```

> ⚠️ **Godot 4.7에서 변경됨:** `AnimationNodeBlendSpace1D/2D`가 bool `sync` 속성(이제 폐기됨)을 `sync_mode` `SyncMode` enum으로 대체한다: `SYNC_MODE_NONE = 0`(기본 — 비활성 애니메이션이 정지됨), `SYNC_MODE_INDEPENDENT = 1`(예전 `sync = true` 동작), `SYNC_MODE_CYCLIC_MUTABLE = 2`(블렌드 가중치로 사이클 길이 동적 계산), `SYNC_MODE_CYCLIC_CONSTANT = 3`(`cyclic_length`초마다 한 사이클 — 반드시 > 0). 4.6에서 올바르게 블렌딩되던 AnimationTree가 전이를 제대로 못 하게 되면, 각 블렌드 스페이스에 `sync_mode`를 설정하라. [4.7 마이그레이션 가이드](https://docs.godotengine.org/en/latest/tutorials/migrating/upgrading_to_godot_4.7.html)를 참고하라.

---

## 6. 스켈레톤 수정자 (3D, 4.4+)

### LookAtModifier3D (Godot 4.4+)

본(bone)을 절차적으로 회전시켜 월드 공간 타깃을 바라보게 한다. 추가 애니메이션 클립 없이 머리 추적과 눈맞춤에 이상적이다.

> ⚠️ **Godot 4.7에서 변경됨:** `LookAtModifier3D.relative`가 이제 기본값 `false`다(이전엔 `true`) — 회전이 기본적으로 현재 포즈가 아니라 rest 포즈 기준으로 적용된다. 4.6 동작을 복원하려면 `relative = true`로 설정하라. [4.7 마이그레이션 가이드](https://docs.godotengine.org/en/latest/tutorials/migrating/upgrading_to_godot_4.7.html)를 참고하라.

### BoneConstraint3D (Godot 4.5+)

`AimModifier3D`, `CopyTransformModifier3D`, `ConvertTransformModifier3D`는 월드 공간이 아니라 **본 상대(bone-relative)**로 동작한다 — aim/소스 타깃이 같은 스켈레톤의 본일 때 쓴다(미러링, 보조 리그 바인딩, 본-투-본 조준).
### SpringBoneSimulator3D (Godot 4.4+)

본에 스프링 물리를 시뮬레이션한다 — 머리카락, 망토, 꼬리, 더듬이가 절차적으로 튀고 흔들린다. `Skeleton3D`의 자식으로 추가하고, 인스펙터에서 스프링 체인(root bone, end bone, stiffness, damping, gravity, drag)을 구성한다.
### 애니메이션 마커 (Godot 4.4+)

마커는 애니메이션 클립 안의 이름 붙은 지점/구역을 정의한다 — 클립을 쪼개지 않고 부분 구역 루프, 섹션 기반 재생, 오디오 동기 이벤트에 쓴다. 타임라인 우클릭 → **Add Marker** → 이름 지정(예: `hit_frame`, `loop_start`). 코드에서 `anim_player.current_animation_position`을 읽어 마커 시간과 비교하거나, 동기화를 위해 마커를 AudioStreamInteractive에 넘긴다.

### 애니메이션 리타게팅 (Godot 4.3+)

Godot 4.3은 `.glb`/`.gltf` 임포트 중 `SkeletonProfile`(예: `SkeletonProfileHumanoid`)로 한 스켈레톤의 애니메이션을 다른 스켈레톤으로 리타게팅한다. 그러면 애니메이션이 일반 프로파일 본 이름을 타깃으로 하므로, 일치하는 어떤 스켈레톤이든 그것을 재생할 수 있다.

---

## 7. IKModifier3D — 솔버 비교 (Godot 4.6+)

Godot 4.6은 스켈레탈 IK 솔버의 베이스 클래스인 `IKModifier3D`를 추가하며, 가장 흔한 알고리즘을 다루는 여덟 개의 서브클래스가 있다. 이들은 `Skeleton3D`의 `SkeletonModifier3D` 자식으로, 다른 수정자(예: `LookAtModifier3D`)와 나란히 동작한다.

체인에 맞는 가장 저렴한 솔버를 골라라: 정확히 두 개의 본으로 된 팔다리(흔한 휴머노이드 경우)에는 `TwoBoneIK3D`, 두 개가 아닌 짧은 체인에는 `CCDIK3D`, 길거나 가변 길이 체인에는 `FABRIK3D`, 리그 정확도가 CPU 비용보다 더 중요할 때만 `JacobianIK3D`.

---

## 8. 흔한 레시피

게임플레이 맛이 나는 두 애니메이션 레시피: 히트 플래시 modulate 트윈과 AnimationPlayer의 Call Method 트랙을 쓴 버퍼드 공격 콤보.

---

## 9. 흔한 함정

증상 → 원인 → 해결 빠른 표로, 블렌딩 대신 애니메이션이 튀는 것, 비활성 AnimationTree, `travel()`이 전이하지 않음, 잘못된 트랙 노드 경로, 조용한 Call Method 트랙, 죽은 블렌드 파라미터, 매 프레임 `play()` 리셋을 다룬다.

---

## 10. 구현 체크리스트

- [ ] AnimationPlayer가 애니메이션되는 노드의 직속 자식이다(더 깊이 중첩되지 않음)
- [ ] 모든 애니메이션 트랙 노드 경로가 유효하다(씬 재구성 후 깨진 참조 없음)
- [ ] AnimationTree `active`가 `true`로 설정되고 `anim_player`가 올바른 AnimationPlayer를 가리킨다
- [ ] 상태 머신 전이에 적절한 페이드 시간이 있다(반응성 있는 게임플레이는 0.1–0.2초)
- [ ] 루프 애니메이션(idle, walk, run)은 Animation 패널에서 루프 모드가 **Loop**로 설정돼 있다
- [ ] 원샷 애니메이션(attack, jump, death)은 루프 모드가 **None**으로 설정돼 있다
- [ ] Call Method 트랙이 게임플레이 이벤트에 쓰인다(히트박스 활성/비활성, 투사체 스폰, SFX 재생)
- [ ] 블렌드 파라미터가 상태 변경 때뿐 아니라 매 프레임 게임플레이 코드에서 설정된다
- [ ] 후속 로직이 필요한 원샷 애니메이션에 `animation_finished` 시그널이 연결돼 있다
- [ ] 머리/눈 추적이 수동 본 회전 대신 `LookAtModifier3D`를 쓴다(Godot 4.4+)
- [ ] 머리카락, 망토, 꼬리가 커스텀 물리 스크립트 대신 `SpringBoneSimulator3D`를 쓴다(Godot 4.4+)
- [ ] 공유 애니메이션 라이브러리가 `SkeletonProfileHumanoid`로 리타게팅을 쓴다(Godot 4.3+)
- [ ] 본-투-본 aim/copy 제약이 수동 본 트랜스폼 코드 대신 `AimModifier3D` / `CopyTransformModifier3D`를 쓴다(Godot 4.5+)
- [ ] 팔/다리 IK가 커스텀 IK 스크립트가 아니라 `IKModifier3D` 서브클래스(두 본 팔다리는 `TwoBoneIK3D`, 긴 체인은 `FABRIK3D`)를 쓴다(Godot 4.6+)
