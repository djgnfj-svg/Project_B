---
name: tween-animation
description: 트윈을 구현할 때 사용한다 — 프로퍼티 애니메이션, 메서드 트위닝, 체이닝, 병렬 시퀀스, 이징, 흔한 UI/게임플레이 모션 레시피
---

# Godot 4.3+의 트윈

모든 예제는 Godot 4.3+를 대상으로 하며 폐기된 API를 쓰지 않는다. GDScript를 먼저, 그다음 C#을 보여준다.

> **관련 스킬:** AnimationPlayer/AnimationTree(키프레임 기반)는 **animation-system**, UI 전이는 **godot-ui**, 셰이더 파라미터 트위닝은 **shader-basics**, 카메라 흔들림과 전이는 **camera-system**, 이징 곡선과 보간 수학은 **math-essentials**, 코드 구동 VFX 타이밍과 시퀀싱은 **particles-vfx**를 참고하라.

---

## 1. 핵심 개념

### 트윈 대 AnimationPlayer

| 기능         | 트윈(코드 구동)                        | AnimationPlayer(데이터 구동)              |
|-----------------|--------------------------------------------|--------------------------------------------|
| 설정           | 코드만 — 에디터 불필요               | 키프레임이 있는 애니메이션 패널             |
| 적합한 용도        | 절차적 모션, UI 전이, VFX     | 복잡한 멀티트랙, 아티스트 구동 클립   |
| 재사용성     | 사용마다 재생성 — 가벼움            | 리소스로 저장, 씬 간 재사용 가능 |
| 블렌딩        | 없음 — 프로퍼티당 한 번에 트윈 하나      | 있음 — AnimationTree가 블렌딩 지원 |
| 메서드 호출    | 어느 지점에서든 `tween_callback()`         | 키프레임된 시점에 Call Method 트랙       |

**경험칙:** 일회성 절차적 애니메이션(페이드 인, 바운스, 슬라이드)에는 트윈을 써라. 반복되는 아티스트 조율 애니메이션(걷기 사이클, 공격 시퀀스)에는 AnimationPlayer를 써라.

### 트윈 만들기

트윈은 어떤 `Node`에서든 생성되고 그 노드에 자동 바인딩된다. 노드가 해제되면 트윈이 자동으로 멈춘다.

```gdscript
# Creates a tween bound to this node
var tween := create_tween()
tween.tween_property(self, "position", Vector2(400, 300), 1.0)
```

```csharp
var tween = CreateTween();
tween.TweenProperty(this, "position", new Vector2(400, 300), 1.0f);
```

> **중요:** `create_tween()` 호출마다 새 트윈을 만든다. 같은 프로퍼티의 이전 트윈은 자동으로 죽지 **않는다** — 서로 경쟁한다. 충돌을 원치 않으면 같은 프로퍼티에 새 트윈을 만들기 전에 오래된 트윈을 죽여라.

---

## 2. Tweener 타입

### tween_property() — 어떤 프로퍼티든 애니메이트

```gdscript
var tween := create_tween()
# Animate position over 0.5 seconds
tween.tween_property($Sprite2D, "position", Vector2(200, 100), 0.5)
# Animate modulate alpha (fade out)
tween.tween_property($Sprite2D, "modulate:a", 0.0, 0.3)
```

```csharp
var tween = CreateTween();
tween.TweenProperty(GetNode("Sprite2D"), "position", new Vector2(200, 100), 0.5);
tween.TweenProperty(GetNode("Sprite2D"), "modulate:a", 0.0f, 0.3);
```

**하위 프로퍼티 접근:** `:`을 써서 개별 컴포넌트를 타깃한다 — `"position:x"`, `"modulate:a"`, `"scale:y"`.

### tween_callback() — 시퀀스의 한 지점에서 메서드 호출

```gdscript
var tween := create_tween()
tween.tween_property(self, "position", Vector2.ZERO, 0.5)
tween.tween_callback(func(): print("Arrived!"))
tween.tween_callback(queue_free)
```

```csharp
var tween = CreateTween();
tween.TweenProperty(this, "position", Vector2.Zero, 0.5f);
tween.TweenCallback(Callable.From(() => GD.Print("Arrived!")));
tween.TweenCallback(Callable.From(QueueFree));
```

### tween_interval() — 스텝 사이 대기/지연

```gdscript
var tween := create_tween()
tween.tween_property(self, "modulate:a", 0.0, 0.3)  # fade out
tween.tween_interval(1.0)                             # wait 1 second
tween.tween_property(self, "modulate:a", 1.0, 0.3)  # fade back in
```

```csharp
var tween = CreateTween();
tween.TweenProperty(this, "modulate:a", 0.0f, 0.3);
tween.TweenInterval(1.0f);
tween.TweenProperty(this, "modulate:a", 1.0f, 0.3);
```

### tween_method() — 보간된 값으로 커스텀 메서드 애니메이트

```gdscript
# Animate a method that receives interpolated float values
func _ready() -> void:
    var tween := create_tween()
    tween.tween_method(_set_health_bar, 100.0, 0.0, 2.0)

func _set_health_bar(value: float) -> void:
    $HealthBar.value = value
    $HealthLabel.text = "%d%%" % int(value)
```

```csharp
public override void _Ready()
{
    var tween = CreateTween();
    tween.TweenMethod(Callable.From<float>(SetHealthBar), 100.0f, 0.0f, 2.0f);
}

private void SetHealthBar(float value)
{
    GetNode<ProgressBar>("HealthBar").Value = value;
    GetNode<Label>("HealthLabel").Text = $"{(int)value}%";
}
```

---

## 3. 시퀀싱 — 체인 대 병렬

### 순차 (기본)

기본적으로 tweener는 **순차적으로** 돈다 — 각각이 이전 것이 끝나기를 기다린다.

```gdscript
var tween := create_tween()
tween.tween_property(self, "position:x", 300.0, 0.5)   # Step 1
tween.tween_property(self, "position:y", 200.0, 0.5)   # Step 2 (after Step 1)
tween.tween_property(self, "rotation", PI, 0.3)         # Step 3 (after Step 2)
```

### 병렬 — tweener를 동시에 돌리기

#### 방법 1: `set_parallel(true)` — 모든 tweener가 한 번에 돎

```gdscript
var tween := create_tween().set_parallel(true)
tween.tween_property(self, "position", Vector2(300, 200), 0.5)
tween.tween_property(self, "rotation", PI, 0.5)
tween.tween_property(self, "modulate:a", 0.5, 0.5)
```

```csharp
var tween = CreateTween().SetParallel(true);
tween.TweenProperty(this, "position", new Vector2(300, 200), 0.5f);
tween.TweenProperty(this, "rotation", Mathf.Pi, 0.5f);
tween.TweenProperty(this, "modulate:a", 0.5f, 0.5f);
```

#### 방법 2: `chain()` — 트윈 중간에 순차로 되돌리기

```gdscript
var tween := create_tween().set_parallel(true)
# These two run at the same time
tween.tween_property(self, "position", Vector2(300, 200), 0.5)
tween.tween_property(self, "scale", Vector2(2, 2), 0.5)
# Switch back to sequential for the next step
tween.chain().tween_property(self, "modulate:a", 0.0, 0.3)
tween.tween_callback(queue_free)
```

```csharp
var tween = CreateTween().SetParallel(true);
tween.TweenProperty(this, "position", new Vector2(300, 200), 0.5f);
tween.TweenProperty(this, "scale", new Vector2(2, 2), 0.5f);
tween.Chain().TweenProperty(this, "modulate:a", 0.0f, 0.3f);
tween.TweenCallback(Callable.From(QueueFree));
```

#### 방법 3: `parallel()` — 다음 tweener를 이전 것과 병렬로

```gdscript
var tween := create_tween()
tween.tween_property(self, "position", Vector2(300, 200), 0.5)
# This runs at the same time as position, not after
tween.parallel().tween_property(self, "rotation", PI, 0.5)
# This runs after both finish (back to sequential)
tween.tween_callback(func(): print("done"))
```

---

## 4. 이징 & 전이

### 이징 설정

```gdscript
var tween := create_tween()
# Set defaults for the entire tween
tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
tween.tween_property(self, "position", Vector2(400, 300), 0.6)
```

```csharp
var tween = CreateTween();
tween.SetTrans(Tween.TransitionType.Cubic).SetEase(Tween.EaseType.Out);
tween.TweenProperty(this, "position", new Vector2(400, 300), 0.6f);
```

### Tweener별 오버라이드

```gdscript
var tween := create_tween()
# This tweener uses bounce, overriding the tween default
tween.tween_property(self, "position:y", 0.0, 0.5) \
    .set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
```

```csharp
var tween = CreateTween();
tween.TweenProperty(this, "position:y", 0.0f, 0.5f)
    .SetTrans(Tween.TransitionType.Bounce)
    .SetEase(Tween.EaseType.Out);
```

### 전이 타입

| 전이       | 성격                              | 흔한 용도                          |
|------------------|----------------------------------------|-------------------------------------|
| `TRANS_LINEAR`   | 일정한 속도                         | 진행 바, 타이머               |
| `TRANS_SINE`     | 부드러운 가속                    | 미묘한 UI 애니메이션               |
| `TRANS_QUAD`     | 적당한 곡선                         | 일반적인 이동                    |
| `TRANS_CUBIC`    | 매끄러운 곡선                           | 대부분의 UI 전이                 |
| `TRANS_QUART`    | 강한 곡선                            | 극적인 등장                  |
| `TRANS_QUINT`    | 매우 강한 곡선                      | 강조 효과                    |
| `TRANS_EXPO`     | 지수 — 급격한 시작/정지         | 위치로 스냅                    |
| `TRANS_CIRC`     | 원형 — 매끄러운 감속         | 자연스러운 모션                    |
| `TRANS_BACK`     | 타깃을 살짝 넘어감              | 통통 튀는 UI 버튼                   |
| `TRANS_ELASTIC`  | 스프링 진동                     | 장난스러운/카툰 효과             |
| `TRANS_BOUNCE`   | 끝에서 튕김                     | 떨어지는 오브젝트, 착지           |

### 이즈 타입

| 이즈          | 동작                                |
|---------------|-----------------------------------------|
| `EASE_IN`     | 느린 시작, 빠른 끝                    |
| `EASE_OUT`    | 빠른 시작, 느린 끝(가장 자연스러움)     |
| `EASE_IN_OUT` | 양 끝이 느림                       |
| `EASE_OUT_IN` | 양 끝이 빠름(드물게 씀)         |

> **가장 흔한 조합:** 자연스러운 UI 전이에는 `TRANS_CUBIC` + `EASE_OUT`. 장난스러운 바운스-인 효과에는 `TRANS_BACK` + `EASE_OUT`.

---

## 5. PropertyTweener 수정자

각 `tween_property()` 호출은 수정자를 체인할 수 있는 `PropertyTweener`를 반환한다: 커스텀 시작값은 `.from(value)`, 현재 값을 캡처하려면 `.from_current()`, (교체가 아니라) 더하려면 `.as_relative()`, 이 tweener의 시작을 지연하려면 `.set_delay(seconds)`.
---

## 6. 루핑과 시그널

`tween.set_loops(N)`은 N번 반복한다(`0` = 무한). 시그널: `finished`(트윈 전체 완료), `step_finished(idx)`(한 스텝 완료), `loop_finished(loop_count)`(한 사이클 완료).
---

## 7. 트윈 생명주기

트윈은 호스트 SceneTree가 소유한다. 스태킹을 피하려면 새 것을 시작하기 전에 `tween.kill()`로 도는 트윈을 죽여라. 런타임 제어에는 `set_pause_mode`, `set_speed_scale`, `set_ignore_time_scale`을 쓴다.
### has_tweeners() (Godot 4.7+)

`Tween.has_tweeners()`(const)는 트윈에 `Tweener`가 하나라도 추가됐고 트윈이 유효하면 `true`를 반환한다 — tweener가 동적으로 추가되어 트윈이 빈 채로 끝날 수 있을 때 유용하다. 시작 전에 빈 트윈을 죽이면 에러를 막는다.

```gdscript
var tween := create_tween()
_add_intro_steps(tween)  # may append zero tweeners
if not tween.has_tweeners():
    tween.kill()
```

```csharp
var tween = CreateTween();
AddIntroSteps(tween); // may append zero tweeners
if (!tween.HasTweeners())
    tween.Kill();
```

---

## 8. 흔한 레시피

대부분의 프로젝트가 필요로 하는 패턴: 페이드 인/아웃, UI 패널 슬라이드 인/아웃, 버튼 누름 바운스, 피해 숫자 팝업, 맥동/호흡 효과, 화면 흔들림, 셰이더 파라미터 애니메이션.
---

## 9. 흔한 함정

| 증상                             | 원인                                            | 해결                                                                |
|-------------------------------------|---------------------------------------------------|--------------------------------------------------------------------|
| 트윈이 튀거나 지터링               | 같은 프로퍼티에서 여러 트윈이 경쟁    | 새 것을 만들기 전에 오래된 트윈을 죽여라                       |
| 트윈이 아무것도 안 함                  | 트윈이 끝나기 전에 노드가 해제됨              | `is_valid()`를 확인하거나 `await` 대신 `tween_callback`을 써라      |
| 일시정지 중 트윈이 돎             | 기본 pause 모드가 기대와 안 맞음      | 일시정지 무시 트윈에는 `set_pause_mode(TWEEN_PAUSE_PROCESS)`를 설정하라  |
| `from()` 값이 무시됨              | `set_parallel()`이 순서를 바꾼 뒤 호출됨    | Tween이 아니라 PropertyTweener에서 직접 `from()`을 호출하라    |
| 트윈이 매끄럽게 루프 안 됨         | 이음매 없는 루프에 끝값이 시작값과 안 맞음   | 회전에는 `as_relative()`를 쓰거나 시작/끝값을 맞춰라        |
| 상대 트윈이 루프마다 drift함     | `as_relative()`가 루프마다 누적됨               | 루핑에는 절대값을; 상대값은 일회성 이동에         |
| 콜백이 잘못된 시점에 발동         | 콜백이 병렬 섹션에 추가됨                | 콜백 전에 `chain()`으로 순차로 되돌려라     |
| 트윈 프로퍼티 경로를 못 찾음       | 오타나 잘못된 경로 형식                       | `"property:component"`를 써라 — 예: `"position:x"`, `"modulate:a"` |
| 트윈이 기대보다 빠르거나 느림   | `Engine.time_scale`이 트윈에 영향                 | 슬로모 중 UI 트윈에는 `set_ignore_time_scale()`을 써라         |

---

## 10. 구현 체크리스트

- [ ] 같은 프로퍼티에 새 트윈을 만들기 전에 오래된 트윈을 죽인다
- [ ] 나중에 죽여야 하는 트윈 참조는 변수에 저장한다
- [ ] 이징을 설정한다(기본 `TRANS_LINEAR`가 아니라 자연스러운 모션에는 `TRANS_CUBIC` + `EASE_OUT`)
- [ ] 여러 프로퍼티를 동시에 애니메이트해야 할 때 `set_parallel(true)`를 쓴다
- [ ] 병렬 섹션 뒤 순차로 되돌리려고 `chain()`을 쓴다
- [ ] 시작값이 중요할 때(끝값만이 아니라) `from()`이나 `from_current()`를 쓴다
- [ ] 절대 타깃을 계산하는 대신 점진적 이동에는 `as_relative()`를 쓴다
- [ ] 루핑 트윈은 수동 재생성이 아니라 `set_loops()`를 쓴다
- [ ] 일시정지 중 돌아야 하는 트윈은 `set_pause_mode(TWEEN_PAUSE_PROCESS)`를 쓴다
- [ ] fire-and-forget 시퀀스(피해 숫자, 파티클)의 끝에 `tween_callback(queue_free)`를 쓴다
