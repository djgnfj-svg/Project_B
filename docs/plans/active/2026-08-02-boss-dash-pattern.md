# 보스 페이즈2 — 좌우 횡단 돌진 (기존 P3 돌진의 **확장**)

> **설계만. 코드·씬·데이터 수정 0.**
> 🔴 **돌진은 이미 있다.** 이 문서는 **차이만** 적는다 — 상태기계·연속 판정·1회 히트 dedup·바위 처벌은 전부 구현돼 있고 건드리지 않는다.
> 기존 구현 이력 = `2026-07-31-minotaur-boss-patterns.md` §P3 · 마스터 = `docs/boss_pattern/minotaur_patterns.md` §3·§3-1.

---

## 0. 이미 있는 것 (실측 — 다시 만들지 않는다)

| 있는 것 | 위치 |
|---|---|
| `CHARGE_DASH`·`CHARGE_HIT` 서브상태 · WINDUP 만료 시 `is_charge` 분기 | `boss.gd:86, 533, 543-570, 696-716` |
| 연속 스윕 판정(**매 프레임** emit) | `boss.gd:553` → `EventBus.boss_sweep` → `combat_authority.gd:623` |
| **돌진 1회당 피어 1회 dedup** + i-frame 존중 + `peer_left` 정리 | `combat_authority.gd:29, 135, 630-639` |
| 지연 보상(`is_strike_hit_lagged`) | `combat_authority.gd:634` |
| 경로 예고 = `shape="cone"` 재사용 · 예고 못 박기 | `boss.gd:639-645, 858` |
| 바위 충돌 → 리코일 → 그로기 | `boss.gd:554, 707-716` · `boss_rock.gd`(layer 1, 그룹 `boss_rock`) |
| 회전 시트 스왑(`mino_spin_full`) | `boss.gd:414-418, 437-443` |
| 데이터 `pat_charge` | `wraith_boss.tres:95-113` (속도 500 · 스윕 72 · 이동 260 · 그로기 3s) |

**그래서 안 만드는 것:** 새 판정 함수 · 1회 히트 마킹 · 새 상태기계 골격 · dedup 설계. **「60번 맞는다」 문제는 이미 해결돼 있다.**

---

## 1. 사용자 요구 ↔ 현행의 차이 (이게 전부다)

| # | 요구 | 현행 | 델타 |
|---|---|---|---|
| ① | 아레나 **가장자리에서** 출발 | 보스가 선 자리에서 출발 | 새 서브상태 `CHARGE_APPROACH` 1개 |
| ② | **가로지른다**(768px 폭) | 260px | 🔴 **데이터만으로 안 된다** — 코드 상수가 막는다(§3) |
| ③ | **왕복 3회+ · 회차마다 빨라진다** | 1회 후 RECOVER | 필드 2 + 회차 카운터 1 + `_telegraph_duration` 확장 |
| ④ | 조준 = **호스트 고정** | `_nearest_alive_player()` | 필드 1(`target_mode`) + 선택 함수 1 |
| ⑤ | 카메라는 **시간 아닌 신호** | `WIDE_HOLD_S` 2.4s 고정 | 시그널 1 + 필드 1, `WIDE_PATTERNS` 상수 **삭제** |

---

## 2. ① 출발점 = 아레나 가장자리 — `CHARGE_APPROACH`

### 왜 새 상태가 필요한가
`_begin_windup`이 `_strike_angle = (anchor − global_position).angle()`과 `_strike_center = global_position`(cone apex)을 **보스의 현재 위치**로 확정한다(`boss.gd:626, 641`). 즉 **가장자리 이동은 WINDUP보다 먼저 끝나 있어야** 예고가 올바른 자리에서 뻗는다. WINDUP 안에 이동을 넣으면 예고 apex가 이동 전 좌표에 박힌다.

### 배선 (기존 심볼 그대로)
- `_host_ai`의 `State.CHASE`에서 `_select_pattern`이 이 패턴을 고르면 → `_begin_windup` 대신 `_enter_charge_approach(pat, target)`.
- 목표점 = `Vector2(가까운 쪽 끝 x, 대상 net_anchor().y)`. 도달하면 **`_begin_windup(pat, 반대편 끝 점)`을 그대로 부른다** — 🔴 인자만 바꾸면 `_strike_angle`이 정확히 `0`/`PI`가 되고 `_strike_center`가 출발단이 된다. **함수 무변경.**
- 끝 좌표 = 아레나에서 유도. 🔴 **`stage_boss.tscn`에 벽도 `map_rect`도 없다**(실측 — 아레나는 순수 스프라이트다) → 씬 루트가 `set_meta("arena_rect", Rect2(192, 116, 768, 416))` 한 줄 선언하고 보스가 조상 체인에서 찾는다(`camera_rig`의 `map_rect` 관용구 미러 — 복붙 배선 방지). 메타 없으면(하네스) 보스 `_ready` 위치 기준 폴백.
- 이동 거리 상한 = **아레나 반폭(384) + 세로 최대(208) ≈ 435px**. 가까운 쪽 끝을 고르므로 반대편까지 갈 일이 없다.
- 2회차부터는 이미 반대편 끝에 서 있으므로 **세로 이동만**(≤208px).

### 🔴 조용히 깨지는 곳 — 걷기 애니
```gdscript
# boss.gd:291 (현행)
raw_moving = _state == State.CHASE and velocity.length_squared() > 0.0
```
`CHARGE_APPROACH`가 여기 없으면 **보스가 idle 자세로 미끄러진다**(에러 없음 — `walk`가 없던 시절의 그 증상이 상태 하나에서만 재발한다). → `(_state == State.CHASE or _state == State.CHARGE_APPROACH)`.

⚠ **`_update_move_anim` 게이트(`:1107`)에는 넣지 마라 — 정반대다.** 거기 넣으면 walk가 막힌다. **두 곳의 부호가 반대**라는 것이 이 항목에서 가장 헷갈리는 지점이다.

⚠ `debug_hold` 게이트(`:489`)에는 **넣어야 한다** — 안 넣으면 테스트 하네스에서 접근 도중 얼어붙는다.

### 예고는 접근 중에 안 뜬다 (사용자 확정 = 2단계 아님)
위협이 없는 구간에 예고를 그리면 *"예고를 봐도 안 맞는 경우가 있다"*를 가르쳐 예고 언어 전체가 약해진다.
🔵 대신 **카메라가 접근 진입에서 이미 뒤로 빠진다**(§6) — 화면이 넓어지는 것 자체가 "뭔가 온다"는 1단계 신호이고, **예고 도형이 아니라서 규약을 안 깬다.**

---

## 3. ② 가로지르기 — 🔴 **데이터만으로는 안 된다**

### 막고 있는 것: `CHARGE_SPIN_TIME`
```gdscript
const CHARGE_SPIN_TIME := 1.0       # boss.gd:92
_state_left = CHARGE_SPIN_TIME      # boss.gd:701 — 돌진 총 지속
```
`charge_speed` 500에서 **1.0초 = 최대 500px**다. `charge_travel_max`를 642로 올려도 보스는 **500px에서 시간이 끝나 RECOVER로 빠진다** → 예고(cone `range` = 이동거리)는 끝까지 그려져 있는데 **보스가 아레나 중간에 멈춘다.** 표시 > 실제라 안전한 방향이지만 **패턴이 죽는다.**

### 처방 — 🔵 죽어 있던 상수를 되살린다
```gdscript
const CHARGE_TIMEOUT_MARGIN := 0.4  # boss.gd:91 — 🔴 선언만 되고 **아무도 안 쓴다**(전수 grep 확인)
#   주석: "돌진 타임아웃 = 이동시간 + 이 여유(벽에 낀 채 무한 돌진 방지)"
```
**의도는 이미 코드에 적혀 있고 구현만 상수로 굳어 있었다.** 그대로 되살린다:

```gdscript
_state_left = maxf(CHARGE_SPIN_TIME,
    _cur_pattern.charge_travel_max / maxf(_cur_pattern.charge_speed, 1.0) + CHARGE_TIMEOUT_MARGIN)
```
- **P3(현행 데이터): `max(1.0, 260/500 + 0.4 = 0.92) = 1.0` → 완전 항등** ✅
  🔴 **`maxf`를 빼고 순수 유도로 두면 P3가 1.0 → 0.92s로 조용히 짧아진다** — 그게 이 한 줄의 유일한 회귀 위험이다.
- 횡단(642px): `max(1.0, 1.684) = 1.684s` ✅
- `CHARGE_SPIN_TIME`의 남은 의미 = **회전 연출 최소 지속**(짧은 돌진이 반 바퀴만 돌고 끝나지 않게). 주석을 그렇게 고친다.

### 그 밖에 걸리는 것 — 확인 결과 **없다**
| 축 | 결과 |
|---|---|
| `LEASH_MULT` 리시 | CHASE에서만 검사 — 돌진과 무관 ✅ |
| `aggro_range` 600 | RECOVER → **CHASE 직접 대입**(`:577`)이라 IDLE 재진입 조건(≤600)을 안 거친다 ✅ |
| 벽 충돌 | 아레나에 StaticBody가 **없다**(실측) — 끝단에서 안 낀다 ✅ |
| `_dash_rock_collision` | 그대로 문다 → 🔴 **밸런스 결정 필요**(§10-5) |
| 회전 클립 | `spin`이 loop이라 길어져도 안 깨진다 ✅ |

### 🔴 그런데 경로 예고(cone)가 길이에 못 따라온다 — 실측 문제다

콘은 apex에서 폭 0으로 시작해 **끝으로 갈수록 넓어진다.** 스윕은 **폭이 일정한 원**이다. 260px에서는 우연히 맞았고 **642px에서는 안 맞는다**:

| | `range` | `half_angle` | 끝 반폭 = `range·tan(half)` | 스윕 반경 | 비 |
|---|---|---|---|---|---|
| P3 현행 | 260 | 0.30 | **80.4px** | 72 | **1.12배** ✅ 거의 정확 |
| 횡단(같은 각) | 642 | 0.30 | **198.6px** | 72 | **2.76배** — 아레나 세로 416 중 397px가 붉게 칠해진다 |
| 횡단(끝 기준 각) | 642 | 0.112 | 72 ✅ | 72 | 🔴 **중간 지점에서 57px 무예고** — 캐릭터 32px보다 넓다 = §3 금지 방향 |

**콘으로는 원리적으로 못 맞춘다** — 폭이 일정한 띠를 각으로 표현할 수 없다. 셋 중 하나를 골라야 한다:

- **A (권장) — `shape = "capsule"` 신설.** 셰이더 uniform **1개**, 표시 함수 1개. 표시 = 판정이 정확히 일치.
- **B — 끝 기준 각.** 🔴 「표시 < 판정」이라 §3 위반. **기각.**
- **C — 각 0.30 유지, 2.76배 과예고 수용.** 코드 변경 0이지만 아레나 세로의 95%가 위험구역으로 보여 **"못 피하는 패턴"으로 학습된다**(실제로는 피할 수 있는데). 회피 학습을 방해한다.

⚠ 리드의 *"스윕은 이동하는 원이라 띠 없이 성립한다"*는 **판정에 대해서는 맞다**(그래서 판정 함수는 안 만든다). **표시에 대해서만 성립하지 않고, 격차가 길이에 비례해 커진다.**

### A안 상세 (채택 시)

`src/core/combat_math.gd` — **표시 형태의 단일 소스**(판정은 여전히 이동 원):
```gdscript
static func capsule_depth(pt: Vector2, a: Vector2, b: Vector2, radius: float) -> float:
    var ab := b - a
    var l2 := ab.length_squared()
    var t := 0.0 if l2 < 0.000001 else clampf((pt - a).dot(ab) / l2, 0.0, 1.0)
    return radius - pt.distance_to(a + ab * t)
```
- `a == b`이면 `is_strike_hit`과 **완전 항등**.
- 🔵 **판정 ⊆ 표시가 기하 정리로 성립한다**: 프레임당 전진 `500/60 = 8.3px`, 가리비 깊이 = `72 − sqrt(72² − 4.17²)` = **0.12px**. 트립와이어가 검사한다.

`boss_telegraph.gdshader` — uniform **하나**(`half_len_px`), `d_arc` **한 줄** 교체:
```glsl
uniform float half_len_px = 0.0;   // 0 = 원/콘 = 현행과 완전 항등
...
float qx    = max(abs(p.x) - half_len_px, 0.0);
float d_lat = length(vec2(qx, p.y));
float d_arc = radius_px - d_lat;                 // t·차오름 좌표도 d_lat 기준으로
```
🔴 **항등 증명:** `half_len_px = 0` ⇒ `qx = |p.x|` ⇒ `length(vec2(|p.x|, p.y)) = sqrt(p.x² + p.y²) = length(p)`. `p.x²`는 부호 무관이라 **IEEE 비트 단위로 같다.** 원·콘은 한 픽셀도 안 바뀐다.
웹 안전: `max`·`abs`·`length`만 추가 — `fwidth`/derivative/screen texture/`discard` **없음**(§5).

🔴 **`_apply_telegraph_geometry`에서 `half_len_px`를 무조건 심어라**(캡슐 아니면 `0.0`). Telegraph 노드는 재사용되므로 **안 심으면 다음 원 예고가 캡슐로 그려진다**(에러 없음). 이 변경에서 가장 조용히 깨지는 한 줄이다. `spr.rotation`도 `is_cone or is_capsule`로 넓힌다(안 하면 오른→왼 회차에서 **차오름 방향만** 반대가 된다).

⚠ `quad_px`는 **정사각 유지**(`2*(half_len + radius + AA + MARGIN)`). 비용은 "전체화면 반투명 쿼드 한 장 × 1.7초"뿐이라 비균일 스케일 문을 열 이유가 없다. 🔵 다만 그 금지의 근거("정원이 타원")는 span을 둘 주면 **해소되는** 것이니, 나중에 프로파일러가 지목하면 **틀린 이유로 기각하지 마라.**

---

## 4. ③ 왕복 3회+ · 회차마다 빨라진다

### 4-1. 회차 카운터는 `dash_seq`가 아니다

`_charge_seq`는 **보스 생애 동안 단조 증가**하는 dedup 키다(`_boss_sweep_seq`와 짝). 회차 인덱스로 쓰면 두 번째 패턴이 idx 3부터 시작한다. → **`_charge_idx: int` 별도**(패턴 시작마다 0). `_charge_seq`의 **횡단마다 +1**은 그대로 유지 = 회차마다 플레이어가 다시 맞을 수 있다(설계 의도) ✅ **현행 `_enter_charge_dash`의 증가 한 줄이 이미 그 역할을 한다.**

### 4-2. 상태기계 — STRIKE를 여러 번 내지 않는다

이 패턴은 원래 `_fire_strike()`를 **안 탄다**(`is_charge` 분기). 따라서 왕복은 **서브상태 루프**다:

```
CHARGE_APPROACH → WINDUP → CHARGE_DASH ─┬─ (_charge_idx+1 < charge_repeat) → CHARGE_APPROACH
                                        └─ (마지막)                          → RECOVER → CHASE
```
현행 `CHARGE_DASH` 종료 분기(`boss.gd:557-561`)에 `if` 하나를 더하는 것이 전부다. 바위 충돌(`CHARGE_HIT` → 그로기)은 **루프를 끊는다**(그로기 = 처벌창인데 계속 돌진하면 처벌이 아니다).

### 4-3. 🔴 회차마다 예고 단축 — `_telegraph_duration`에 **인자를 넣지 않는다**

§3이 못 박은 단일 소스이고 소비처가 다섯이다(표시 지속 · N개 원 타이머 · 애니 길이 · 차오름 분모 · 카메라). 인자를 늘리면 다섯 호출부를 손으로 맞추게 된다.

**선례가 이미 있다**: `_telegraph_hold_s`가 정확히 그 방식이다 — 호스트가 `_begin_windup`에서 **한 번 확정**하고 함수는 그것을 읽는다. 회차 단축도 같은 자리에 곱해 넣는다:

```gdscript
# _begin_windup — 호스트
var t := pat.telegraph_s * CombatMath.charge_telegraph_scale(pat, _charge_idx)
_telegraph_hold_s = t + CombatMath.strike_delay_s(Net.max_remote_one_way_ms())

# _telegraph_duration — 게스트 갈래만 한 줄 확장 (호스트 갈래 무변경)
func _telegraph_duration(pat: BossPatternDef) -> float:
    if _telegraph_hold_s > 0.0:
        return _telegraph_hold_s
    return pat.telegraph_s * CombatMath.charge_telegraph_scale(pat, _charge_idx)
```
✅ **함수 시그니처 무변경 · 소비처 다섯이 자동으로 따라온다.**

🔴 **게스트가 `_charge_idx`를 모르면 3회차에서 호스트 0.6s vs 게스트 1.2s가 되어 「다 찼다 = 지금 맞는다」가 깨진다** — 게스트가 절반 시점에 이미 맞는다. §8의 `"i"` 필드가 그 때문에 필요하다.

배율은 `CombatMath`에 둔다 — 🔴 씬 글루(`boss.gd`)에 두면 `-s`가 preload를 못 해 **`data/enemies` 전수 트립와이어를 만들 수 없다**(§3 J-1·J-2):
```gdscript
# 회차 단축 하한. 🔴 근거 = ROLL_TIME_S(0.25s) — 예고가 구르기보다 짧으면
#   "예고를 읽고 구른다"(GDD §5 기믹 원칙)가 **원리적으로** 불가능해진다.
const CHARGE_TELEGRAPH_MIN := 0.35

static func charge_telegraph_scale(pat: BossPatternDef, idx: int) -> float:
    return maxf(1.0 - pat.charge_speedup * float(maxi(idx, 0)), CHARGE_TELEGRAPH_MIN)
```
- `charge_speedup = 0` ⇒ 항상 1.0 = **모든 기존 패턴과 완전 항등** ✅
- 큰 `idx`(버그·조작)는 하한으로 포화 = 안전 방향. 음수는 `maxi`가 0으로 누른다.
- 트립와이어: `pat.telegraph_s × CHARGE_TELEGRAPH_MIN ≥ ROLL_TIME_S × 1.5` 전수.

### 4-4. `strike_delay_s`는 **회차마다 다시 더해진다** (쌓이는 게 아니다)

각 회차가 독립된 WINDUP이므로 편도 지연이 회차마다 한 번씩 더해진다. 3회면 총 길이에 `3 × strike_delay`가 붙지만 **그건 누적 보상이 아니라 회차마다 새로 생기는 공정성 요구**다 — 게스트는 매 회차 온전한 예고 창을 가져야 한다. 최악(상한 200ms) 3회 = **+0.6s**, 총 길이 대비 6%라 수용.

### 4-5. 🔴 총 소요 시간 — **지루함 임계에 걸린다**

제안값(`telegraph_s` 1.2 · `charge_speedup` 0.25 · `charge_speed` 500 · 이동 642 · 접근 260px/s):

| 회차 | 접근 | 예고(배율) | 돌진 | 소계 |
|---|---|---|---|---|
| 1 | 1.67s(최악) | 1.20s (×1.00) | 1.68s | **4.55s** |
| 2 | 0.80s(세로만) | 0.90s (×0.75) | 1.68s | **3.38s** |
| 3 | 0.80s | 0.60s (×0.50) | 1.68s | **3.08s** |
| | | | RECOVER 0.5 | **합 11.5s** (지연 최악 +0.6 → **12.1s**) |

- 🔴 **12초는 길다.** 가장 큰 레버는 **접근(3.27s = 28%)** 이다 → `charge_approach_speed`를 400으로 올리면 2.1s로 줄어 **총 10.3s**.
- 🔵 **완화 요소**: 돌진 중에는 보스가 직선으로 예측 가능하게 움직여 **띠 밖에서 때릴 수 있다.** 진짜 딜 정지 구간은 접근 + 예고(약 4.8s)뿐이다.
- 🔴 그래도 `cooldown_s`를 크게 잡아라(**제안 14s**). 페이즈2 내내 이것만 나오면 안 된다.
- ⚠ **`charge_repeat = 3`을 확정하기 전에 실기가 필요하다** — 2가 맞을 수 있다(`.tres` 한 줄).

---

## 5. ④ 조준 = 호스트 고정 (`.tres` 한 줄로 뒤집히게)

```gdscript
# BossPatternDef
@export var target_mode: String = "nearest"   # "nearest"(현행 = 항등) | "host" | "alternate"
```
```gdscript
# boss.gd — 대상 선택 단일 소스. 🔴 폴백이 계약이다.
func _select_target(pat: BossPatternDef) -> PlayerActor:
    match pat.target_mode:
        "host":      return _alive_peer(NetSchema.HOST_ID)      # 없으면 아래 폴백
        "alternate": return _alive_other_than(_last_target_peer)
    return _nearest_alive_player()   # 기본 + 모든 폴백
```
- **결정적** — `HOST_ID`가 상수라 RNG가 없다. 🔴 **게스트는 대상 id를 알 필요조차 없다**: 조준 결과는 `_strike_center`/`_strike_angle`(= `G_BOSS_ATK`의 `x, y, a`)로 **이미 전부 표현된다.** `target_mode`를 무엇으로 바꿔도 **네트워크 표면 0**.
- 🔴 **폴백 없이 null을 돌리면 패턴이 조용히 안 나온다** — 호스트가 죽어 관전 중이면 대상이 없다. `nearest` 폴백이면 「호스트 사망 = 게스트가 표적」으로 자연스럽게 넘어간다. 모르는 문자열도 같은 폴백으로 떨어져 **데이터 오타가 패턴을 죽이지 않는다.**
- ⚠ **리드가 지적한 불균형은 실재한다** — 2인이면 게스트가 그 패턴 동안 완전히 안전해지고, 페이즈2 주력 패턴이 한 명만 위협한다. **이 필드의 존재 이유가 그것**이고 `target_mode = "alternate"` **한 줄**로 뒤집힌다. 실기에서 사용자가 고른다(`docs/TUNING.md` 등재).
- ⚠ 4인 확장 시 `"alternate"`는 라운드로빈으로 넓혀야 한다(값은 그대로, §2 게이트 등재).

---

## 6. ⑤ 카메라 — 시간이 아니라 신호

### 문제
`WIDE_HOLD_S = 2.4s` 고정인데 이 패턴은 **10~12초**이고 길이가 `charge_repeat`에 따라 가변이다. 상수로는 원리적으로 불가능하다.

### 제안 — 🔵 `WIDE_PATTERNS` 상수를 **삭제**한다
```gdscript
# core (리드): 표시 전용 로컬 시그널 — 중계 없음, 네트워크 0
signal boss_wide_view(active: bool)

# BossPatternDef: 어떤 패턴이 넓은 화면을 요구하는지 = **데이터**
@export var wide_view: bool = false
```
- `camera_rig`는 `boss_telegraph` 대신 **`boss_wide_view`만 구독**한다. `WIDE_PATTERNS`(패턴 id 하드코딩 미러)·`WIDE_HOLD_S`가 사라진다 → 🔵 **§2 「id 하드코딩 미러」가 하나 줄어든다.** `spin`은 `.tres`에 `wide_view = true` 한 줄 = 항등.
- **누가 emit하나 — 호스트·게스트 둘 다 로컬에서.**
  - `true`: **접근 진입**(`CHARGE_APPROACH`). 🔵 예고보다 먼저 빠지므로 접근이 읽힌다(§2).
  - `false`: 마지막 회차 돌진 종료(RECOVER 진입) · 보스 사망(`_on_hp_changed` dead 경로).
- **게스트는 상태기계를 안 돈다** → 게스트가 아는 것은 `show_boss_telegraph` 수신뿐이다:
  - `true`: 🔴 **`G_BOSS_ATK`의 `"i"`를 `−1`로 보내 「접근 시작」을 알린다.** 수신부는 `i < 0`이면 **예고 도형을 안 그리고** `boss_wide_view(true)`만 낸다. **신규 kind 0 · 신규 필드 0**(§8의 `"i"` 재사용). **도형이 없으므로 2단계 예고가 아니다.**
  - `false`: 마지막 회차(`i == pat.charge_repeat − 1`)의 예고를 받았으면, 보스가 **자기 로컬 타이머**(예고 + 돌진 — 둘 다 데이터 유도라 클라 공통)로 낸다. 🔴 **패턴 def를 가진 보스가 계산하고 카메라는 순수 신호 구독자로 남는다** — 그게 §2 손맛 계층 경계(`src/feel`은 EventBus 구독만)에 맞다.
- 🔴 **워치독 필수**: `false`가 유실될 수 있는 경로(보스 사망 레이스·씬 전환·재합류)를 위해 카메라에 **상한 타임아웃**(15s)을 남긴다. 없으면 **줌아웃 상태로 영영 남는다**(에러 없음). 기존 `WIDE_HOLD_S`를 그 역할로 재해석하면 상수 추가가 0이다.
- `ZOOM_WIDE = 0.8`은 그대로 맞다 — 보이는 영역 800×450 ⊃ 아레나 768×416. ⚠ 그 값이 아레나 크기의 **사람 미러**라는 것은 남는다(`camera_rig.gd:49-53`). `arena_rect` 메타의 세 번째 소비자가 생기면 그때 유도로 옮겨라(§2 「두 번째 사용처 전 공용화」).

---

## 7. 예고 표현 — 차오름 vs 깜빡임

### 권장: **차오름(길이 방향) 유지. 회차 구분은 색 + `pulse_hz`.**

**차오름을 고른 이유**
- 캡슐 띠는 폭 144px(반경 72)로 **캐릭터 32px의 4.5배**다 — "얇아서 채움이 안 보인다"는 우려는 실측상 해당 없다.
- 길이 방향 차오름은 **임박도 + 방향**을 동시에 싣는다(마스터 §3 「긁힘 선의 수직 = 회피 축」과 같은 언어).
- 🔵 **회차마다 빨라지는 것이 그대로 차오름 속도가 된다** — 예고 창이 짧아지므로 같은 거리를 더 빨리 흐른다. 사용자 요구("점점 빨라진다")가 **연출로 그대로 드러난다.** 별도 장치 불필요.

**회차 구분(같은 연출 3번 반복 문제) — 셰이더 분기 추가 0**
- `charge_color`·`border_color`를 회차마다 뜨겁게 심는다. 🔵 이미 **매번 심는 uniform**이라(`boss.gd:948`) 셰이더를 안 건드린다 — `boss.gd`에서 색만 `lerp`.
- `pulse_hz`를 회차별 **상수**로 올린다(1회 2.2 → 3회 3.4). ⚠ **등속을 유지한다.**

**깜빡임 매핑을 안 고른 이유**
`pulse_hz`를 `progress`에 매핑하면 셰이더 안에서 `sin(TIME × f(progress))`가 되어 **주파수가 변할 때마다 위상이 점프한다**(눈에 띄는 딸꾹질). 진폭(`pulse_amp`)만 `progress`에 매핑하는 것은 안전하지만 차오름보다 정보량이 적다(방향이 안 실린다).

🔴 **어느 쪽이든 입력은 `progress` uniform 하나다.** `TIME`에서 임박도를 유도하면 호스트 예고 창이 `strike_delay_s`만큼 길어 게스트가 **틀린 신호**를 읽는다(셰이더 52~57·74~76줄 주석이 정본, netreview 2026-07-27 계약).

---

## 8. 네트워크

| 축 | 결과 |
|---|---|
| 신규 kind | **0** |
| `G_BOSS_ATK` 신규 필드 | **`"i"` 1개** — 회차 인덱스. `−1` = 접근 시작(도형 없음) · 기본 `0` = **현행 항등** |
| EventBus | `boss_wide_view(active)` 신설(**로컬 전용·중계 없음**) · `boss_telegraph`에 `idx` 인자 추가(리드 core) |
| 채널 | `G_BOSS_ATK`는 **사건** = safe 유지. 한 통 유실 = **예고 없이 맞는다**. `RTC_FAST_KINDS`는 allowlist라 기본 safe ✅ |
| 크기 | 정수 한 칸 — 릴레이 2048 상한 무관 ✅ |

**신뢰 경계**
- `"i"`는 호스트 발신 전용이고 수신부가 이미 `from_id != NetSchema.HOST_ID`를 거부한다(`mob_sync.gd:142`).
- 값 검증은 **`charge_telegraph_scale`의 `maxi(idx, 0)` + 하한 포화**가 구조로 한다. 별도 clamp 불필요.
- 🔴 **`"i"`는 "수치"가 아니라 "인덱스"다** — 예고 길이 자체는 각 클라가 자기 `.tres`에서 리졸브한다. 특성 축이 id만 보내고 값은 로컬에서 푸는 것과 **같은 철학**(§3).

🔴 **netreview 필요: 예.** 신규 kind가 0이어도 회차 동기화·예고 창 정합·호스트 권한 경로에 닿는다.

---

## 9. §2 게이트 · 검증

### 9-1. 게이트

| 게이트 | 영향 | 처리 |
|---|---|---|
| **`ATTACK_ANIMS` 미러** | 횡단은 `play_spin_clip`(`spin_prep`/`spin`)을 쓰므로 **현행 P3와 같이 우연히 안전하다** — 클립 이름 `spin`이 마침 P5 패턴 id라 배열에 있다. ⚠ **P5를 지우면 P3·횡단 애니가 같이 조용히 깨진다**(`_on_hp_changed`가 `_is_attack_anim_playing()`만 보고 idle로 덮는다 — 돌진 중엔 반드시 맞는다) | 전수 트립와이어 신설(⑥) |
| **재합류 스냅샷** | **새 항목** — 재합류 피어는 진행 중인 횡단의 `"i"`를 놓쳐 **예고 없이 돌진만 본다** | 「진행 중인 charge(회차 idx · 남은 회차 · 중심·각)」 등재 요청 |
| **4인 파티** | `target_mode = "alternate"`가 2인 전제 | 게이트 목록 등재(지금 코드 변경 불필요) |
| 동적 스폰 · G_EXP · 릴레이 상한 | 무관 | — |

### 9-2. 헤드리스가 잡는 것

1. **★`charge_telegraph_scale`** — `charge_speedup = 0`에서 항상 1.0(전 패턴 항등) · 단조 감소 · 하한 포화 · 음수 idx 방어.
2. **★회피 가능성 전수** — `telegraph_s × CHARGE_TELEGRAPH_MIN ≥ ROLL_TIME_S × 1.5`.
3. 🔴 **★돌진 완주 불변식** — `charge_travel_max / charge_speed + CHARGE_TIMEOUT_MARGIN ≤ 돌진 지속`. **리드가 물은 "데이터만 늘리면 되는지"의 자동 답이다**: 옛 상수(1.0 고정)에서 `charge_travel_max`를 642로 올리면 **이 트립와이어가 빨개진다.** 가장 값어치 있는 항목.
4. **★`_state_left` 유도 항등** — P3 데이터에서 `maxf(...) == CHARGE_SPIN_TIME`.
5. **★캡슐**(A안 채택 시) — 독립 오라클(`Geometry2D.get_closest_point_to_segment`) 교차검증 · `a == b`에서 `is_strike_hit` 항등 · GLSL 수식을 GDScript로 옮겨 `d ≥ 0 ⟺ 캡슐 안` · 가리비 부등식(판정 ⊆ 표시).
   - ⚠ **증명하는 것은 "식이 같다"뿐** — GLSL 컴파일·uniform 배선은 실기 몫.
   - 🔵 오라클을 **엔진 함수로 쓰는 것**이 핵심이다 — 테스트가 코드를 미러하면 검출력이 0이다(§3 N-1).
6. **★`ATTACK_ANIMS` 커버리지 전수(신설)** — 모든 `BossDef`의 모든 패턴 id·클립이 접두 규칙으로 덮이는지. 🔵 §2 게이트 절반을 규율에서 구조로 옮긴다.
7. **★`target_mode` allowlist** — 모르는 값이 `nearest` 폴백으로 떨어지는지.

### 9-3. 🔴 실기 몫

- **GLSL 캡슐 분기 컴파일**(웹). 안 돌면 **예고만 사라지고 판정은 정상** = 최악의 방향.
- **원·콘 예고 항등 육안 확인** — swing·slam·spray·spin 네 패턴 캡처. `half_len_px` 미기입 경로가 하나라도 있으면 원이 캡슐로 그려진다.
- **접근 중 walk 애니**(`raw_moving` 수정 확인) — 안 고치면 idle로 미끄러진다.
- **카메라 on/off 신호 타이밍 + 워치독** — 줌아웃에 갇히는지.
- 🔴 **2클라 배포본: 회차별 예고 단축 정합** — 3회차에서 게스트가 늦게 반응하지 않는지. **`"i"` 필드의 존재 이유이고 `dev_local.sh` 13.8ms로는 재현 안 된다.**
- **12초 지루함 임계** — 사용자 판단(`charge_repeat` 2 vs 3).
- **보스 스프라이트가 아레나 밖으로 삐져나오는 정도** — 그려지는 폭 = 64 × 2(씬) × 1.5(`sprite_scale`) = **192px** vs 끝단 여유 `body_radius` 63.

### 9-4. `docs/TUNING.md` 등재

`charge_repeat`(3) · `charge_speedup`(0.25) · `charge_approach_speed`(260~400) · `charge_travel_max`(642) · `cooldown_s`(14) · `damage`(18) · `target_mode`(host ↔ alternate) · `CHARGE_TELEGRAPH_MIN`(0.35) · 바위 파괴 여부.

---

## 10. 단계 + 크기 · 위험

### 단계 (마감 8/10 — **총 ≈ 반나절~하루**)

| # | 무엇 | 크기 | 라이브 영향 |
|---|---|---|---|
| 1 | `CombatMath`: `charge_telegraph_scale` + 트립와이어 ①②③④⑦ | **S** | **없음(항등)** |
| 2 | `_state_left`를 `maxf` 유도로 + `CHARGE_TIMEOUT_MARGIN` 부활 | **XS** | **없음(P3 항등)** |
| 3 | 스키마 6필드 — 리드: `charge_repeat`·`charge_speedup`·`charge_approach_speed`·`target_mode`·`wide_view`(+A안이면 `shape="capsule"`) | **XS** | 없음 |
| 4 | `CHARGE_APPROACH` + `_select_target` + `arena_rect` 메타 + 🔴 `raw_moving`·`debug_hold` 게이트 | **M** | 신규 경로 |
| 5 | 왕복 루프(`_charge_idx`) + 예고 단축 + `G_BOSS_ATK "i"` + `boss_telegraph` 인자 | **M** ← netreview 핵심 | 신규 경로 |
| 6 | 캡슐 shape(A안) — 셰이더 uniform 1 + `capsule_depth` + 트립와이어 ⑤ | **S** | **없음(항등 증명)** |
| 7 | `boss_wide_view` 전환 + `WIDE_PATTERNS` 삭제 + 워치독 | **S** | spin 항등 |
| 8 | 데이터 `pat_cross` + `spin.wide_view = true` | **XS** | 신규 패턴 |
| 9 | 🔴 netreview + 실기(§9-3) | — | — |

🔵 **1·2·3·6은 라이브 동작을 한 픽셀도 안 바꾼다.** 위험은 4·5에 몰려 있고 그 앞에서 트립와이어가 깔린다.
⚠ **시간이 모자라면 6(캡슐)을 미루고 C안(과예고 수용)으로 나갈 수 있다** — 안전한 방향이라 회귀는 없고 학습성만 손해다. 5는 못 미룬다(게스트 정합).

### 위험 · 되돌리기 어려운 결정

1. 🔴 **`_state_left` 유도 교체가 P3 현행 동작에 닿는다.** `maxf(CHARGE_SPIN_TIME, ...)`가 항등의 전부다.
2. 🔴 **`_telegraph_duration` 게스트 갈래 확장이 모든 패턴에 닿는다.** `charge_speedup = 0`에서 배율 1.0 = 항등이 근거.
3. 🔴 **셰이더 `half_len_px`(A안)는 모든 보스 예고에 닿는다.** 항등 증명 + 트립와이어 + 4패턴 캡처를 **다 하기 전에 4단계로 넘어가지 마라.**
4. 🔴 **`half_len_px`를 조건부로 심는 실수** — 캡슐 뒤의 원 예고가 캡슐로 그려진다. 에러 없음.
5. 🔒 **밸런스: 횡단이 바위를 부수나?** (사용자 판단, 구현은 한 줄)
   - **부순다**: 페이즈2 escalation이 읽힌다("페이즈1에서 통하던 바위 유도가 안 통한다"). 대가 = 선분 위 바위가 사라져 P3 처벌 도구를 잃는다.
   - **안 부순다**: `boss_rock`이 layer 1이고 보스 mask가 1이라 **보스가 막혀 횡단이 중단된다.**
   - **현행 그대로(그로기)**: 횡단이 P3와 구분이 안 되고 왕복이 매번 끊긴다.
   - ⚠ 어느 쪽이든 게스트에서는 `shatter()`가 안 돌아 바위가 남는다(기존 부채 E-4). 판정이 없어 무해.
6. 🔴 **12초 패턴의 지루함**(§4-5). `charge_repeat` 3 확정 전 실기 필요.
7. 🔴 **A안을 안 하면 남는 부채**: 경로 예고가 스윕의 **2.76배 과예고**(아레나 세로의 95%). 안전한 방향이지만 "못 피하는 패턴"으로 학습된다.
8. **`target_mode = "host"` 기본은 2인에서 게스트를 완전히 안전하게 만든다**(§5). `.tres` 한 줄로 뒤집히게 설계했다는 것이 완화책 전부다.

---

## 11. §3 등록 요청 (리드 → `projectb-rules`)

1. 🔴 **회차 예고 배율 = `CombatMath.charge_telegraph_scale(pat, idx)`.** 호스트는 `_telegraph_hold_s`에 곱해 넣고 게스트는 `_telegraph_duration`이 직접 읽는다 — **양쪽이 같은 함수를 지나야** 「다 찼다 = 지금 맞는다」가 유지된다. 하한 `CHARGE_TELEGRAPH_MIN`의 근거는 `ROLL_TIME_S`다.
2. 🔴 **돌진 지속 = `maxf(CHARGE_SPIN_TIME, travel/speed + CHARGE_TIMEOUT_MARGIN)`.** 상수 고정이면 `charge_travel_max`를 늘려도 보스가 중간에 멈춘다(예고는 끝까지 그려진 채로).
3. 🔴 **대상 선택 = `boss._select_target(pat)` + `BossPatternDef.target_mode`.** 조준 결과는 `x/y/a`로만 나가므로 **모드를 바꿔도 네트워크 표면 0**. 폴백(`nearest`)이 계약이다.
4. **넓은 화면 = `BossPatternDef.wide_view` + `EventBus.boss_wide_view`.** 카메라의 패턴 id 하드코딩 미러를 없앤다. 워치독 타임아웃이 안전장치.
5. (A안 채택 시) **캡슐 예고 = `CombatMath.capsule_depth` + 셰이더 `half_len_px`.** 판정은 여전히 이동 원이고 캡슐은 그 합집합 — 「판정 ⊆ 표시」가 가리비 부등식(0.12px)으로 증명된다.

§2 갱신 둘: 「`ATTACK_ANIMS` 미러」에 **전수 트립와이어가 생겼다** + **P3가 `spin` 이름의 우연에 기대고 있었다**는 사실 · 「재합류 스냅샷」에 **진행 중인 charge 회차** 추가.
