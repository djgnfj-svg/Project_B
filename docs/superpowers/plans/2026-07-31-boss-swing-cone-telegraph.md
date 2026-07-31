# 미노 전방 후리기(cone) + 위험 줄무늬 예고 — 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 미노타우로스에 제자리 근접 기본기 `swing`(cone)을 추가하고, 그 예고를 기존 단색 부채꼴이 아니라 위험 줄무늬로 표시한다.

**Architecture:** 판정·FSM·애니는 **전부 기존 경로 재사용**(cone은 `CombatMath.is_hit_in_cone_lagged` + `CombatAuthority._on_boss_strike`의 `shape=="cone"` 분기 + `boss.gd`의 WINDUP→STRIKE→RECOVER + 이미 있는 `swing` 애니). 신규 코드는 **셰이더 채움색뿐** — `boss_telegraph.gdshader`에 `stripe_on` uniform을 더해 콘일 때만 대각 줄무늬로 칠한다. 부채꼴 **기하·마스크·테두리 로직은 불변**이라 "맞는 곳=보이는 곳" 계약이 자동 유지된다.

**Tech Stack:** Godot 4.7.1 · GDScript · `.tres` 리소스 · canvas_item 셰이더(Compatibility/GLES3) · 헤드리스 테스트(`scripts/run_tests.sh`).

**설계 근거:** `docs/superpowers/specs/2026-07-31-boss-swing-cone-telegraph-design.md` · 패턴 문서 `docs/boss_pattern/swing_cone.md`.

---

## 검증 규약 (모든 태스크 공통)

- 테스트 실행은 **Bash 툴**에서 `bash scripts/run_tests.sh [필터]` (PowerShell은 자식 stdout을 안 보여준다).
- 🔴 **판정 3조건 전부**: `exit 0` + 출력에 `TEST_OK` ≥ 1 + `SCRIPT ERROR` 0건. `TEST_OK`만 grep하면 침묵 통과를 놓친다.
- 🔴 **헤드리스 한계**: 셰이더 GLSL 컴파일·예고 렌더 모양·줄무늬 흐름·클릭 회피는 헤드리스가 **구조적으로 못 잡는다**. 그건 Task 6의 실기 목록(`docs/TUNING.md`)으로 넘긴다 — 이 계획의 자동 테스트는 **데이터 계약**과 **씬 글루 파스**까지만 보증한다.

---

## File Structure

| 파일 | 역할 | 태스크 |
|---|---|---|
| `data/enemies/wraith_boss.tres` | 미노 `BossDef` 정본 — cone 패턴 추가 + `keep_distance 0` | 1 |
| `tests/test_boss_data_auto.gd` | 보스 데이터 계약 — cone `half_angle` 단정 추가 | 2 |
| `assets/shaders/boss_telegraph.gdshader` | 예고 렌더 — `stripe_on` uniform + 줄무늬 채움 | 3 |
| `src/enemies/boss.gd` | 줄무늬 상수 + `_apply_telegraph_geometry`에서 uniform 심기 | 4 |
| `docs/TUNING.md` | 실기 확인 목록 §15 추가 | 5 |

---

## Task 1: 데이터 — `swing`(cone) 패턴 추가 + `keep_distance 0`

**Files:**
- Modify: `data/enemies/wraith_boss.tres` (헤더 `load_steps` · 새 sub_resource · `patterns` 배열 · `keep_distance`)

**배경:** 현재 미노는 `slam`(circle) 하나뿐이고 `keep_distance = 150`이라 후리기(사거리 120)가 안 닿는다. cone 패턴을 넣고 파고들게 한다. 수치는 전부 시작값(튜닝 대상). 🔴 `telegraph_s`는 **0.9**로 둔다 — `swing` 애니 기본 길이 = 9프레임/speed 7.5 = **1.2s**이고, Task 2의 계약 테스트가 `애니길이 / telegraph_s ≤ 1.5`를 요구한다. 0.8이면 비율이 정확히 1.5(경계)라 부동소수점에서 깨질 수 있다. 0.9면 1.333으로 안전하다.

- [ ] **Step 1: `load_steps` 1 증가**

파일 첫 줄:
```
[gd_resource type="Resource" script_class="BossDef" load_steps=16 format=3]
```
→ 로 교체:
```
[gd_resource type="Resource" script_class="BossDef" load_steps=17 format=3]
```

- [ ] **Step 2: cone sub_resource 추가**

기존 slam sub_resource 블록(아래) **바로 다음**, `[resource]` 줄 **앞**에 새 블록을 삽입한다.

기존(참고 — 이건 그대로 둔다. `id="pat_swing"`인데 안의 `id`는 `"slam"`이다):
```
[sub_resource type="Resource" id="pat_swing"]
script = ExtResource("2")
id = "slam"
shape = "circle"
telegraph_s = 1.2
damage = 12
range = 130.0
cooldown_s = 2.5
recover_s = 0.6
use_min_dist = 0.0
use_max_dist = 210.0
min_phase = 1
```

삽입할 새 블록:
```
[sub_resource type="Resource" id="pat_cone"]
script = ExtResource("2")
id = "swing"
shape = "cone"
telegraph_s = 0.9
damage = 10
range = 120.0
half_angle = 0.7
cooldown_s = 2.0
recover_s = 0.4
priority = 1
use_min_dist = 0.0
use_max_dist = 110.0
min_phase = 1
```

- [ ] **Step 3: `patterns` 배열에 cone 추가**

```
patterns = Array[BossPatternDef]([SubResource("pat_swing")])
```
→ 로 교체:
```
patterns = Array[BossPatternDef]([SubResource("pat_swing"), SubResource("pat_cone")])
```

- [ ] **Step 4: `keep_distance` 0으로**

```
keep_distance = 150.0
```
→ 로 교체:
```
keep_distance = 0.0
```

- [ ] **Step 5: 데이터 계약 테스트 실행 (파스 + 계약)**

Run: `bash scripts/run_tests.sh boss`
Expected: `exit 0` · 출력에 `TEST_OK boss_data` · `SCRIPT ERROR` 0. 새 콘 패턴이 `[미노타우로스] .../swing`로 뜨고 그 아래 `ok` 줄들(애니 존재·loop=false·range>0·애니길이≤telegraph_s×1.5)이 전부 통과해야 한다. `FAIL`이 뜨면 오타(특히 `telegraph_s`·프레임/speed) 점검.

- [ ] **Step 6: 커밋**

```bash
git add data/enemies/wraith_boss.tres
git commit -m "추가: 미노 전방 후리기(swing·cone) 패턴 + keep_distance 0"
```

---

## Task 2: 데이터 계약 강화 — cone `half_angle` 단정

**Files:**
- Modify: `tests/test_boss_data_auto.gd` (패턴 루프에 cone 전용 검사 추가)

**배경:** 현재 계약 테스트는 `half_angle`을 검사하지 않는다. cone은 `half_angle = 0`이면 판정이 사실상 없는데 예고는 apex 블롭으로 **보인다**(range=0과 같은 "보이는데 안 맞는" 방향의 유일한 이탈). 데이터로 못 들어오게 막는다.

- [ ] **Step 1: 실패를 먼저 만든다 — cone half_angle을 0으로 임시 변경**

`data/enemies/wraith_boss.tres`의 `pat_cone` 블록에서 `half_angle = 0.7` → `half_angle = 0.0`으로 임시 변경.

- [ ] **Step 2: 아직 단정이 없으니 통과함을 확인(= 구멍 실증)**

Run: `bash scripts/run_tests.sh boss`
Expected: **여전히 `TEST_OK boss_data`** (현재 테스트는 half_angle을 안 보므로 0.0도 통과 — 이게 메우려는 구멍이다).

- [ ] **Step 3: cone 단정 추가**

`tests/test_boss_data_auto.gd`의 `_check_boss` 안, `range > 0` 검사 블록 **다음**(아래 기존 코드):
```gdscript
		_check(p.range > 0.0,
			"%s: range > 0 (%.1f) — 0이면 예고만 보이고 판정이 없다"
			% [label, p.range])
```
바로 뒤에 삽입:
```gdscript
		# 부채꼴은 half_angle이 판정 반각이자 셰이더가 그리는 각. 0이면 판정 없는데 예고는
		# apex 블롭으로 보인다(range=0과 같은 "보이는데 안 맞는" 이탈). PI 이상이면 원과 구분 안 됨.
		if p.shape == "cone":
			_check(p.half_angle > 0.0 and p.half_angle < PI,
				"%s: cone half_angle ∈ (0, PI) (%.3f) — 0이면 판정 없는데 예고는 apex 블롭으로 보인다"
				% [label, p.half_angle])
```

- [ ] **Step 4: 이제 실패하는지 확인 (mutation 검출력 증명)**

Run: `bash scripts/run_tests.sh boss`
Expected: **`TEST_FAIL boss_data failures=1`** · `FAIL .../swing: cone half_angle ∈ (0, PI) (0.000) ...` 줄. `exit` 비0. (테스트가 진짜로 이 결함을 잡는다는 증명.)

- [ ] **Step 5: half_angle을 원복(0.7)**

`data/enemies/wraith_boss.tres`의 `pat_cone`에서 `half_angle = 0.0` → `half_angle = 0.7`.

- [ ] **Step 6: 그린 확인**

Run: `bash scripts/run_tests.sh boss`
Expected: `exit 0` · `TEST_OK boss_data` · `SCRIPT ERROR` 0.

- [ ] **Step 7: 커밋**

```bash
git add tests/test_boss_data_auto.gd
git commit -m "추가: 보스 데이터 계약 — cone half_angle ∈ (0, PI) 단정"
```

---

## Task 3: 셰이더 — `stripe_on` uniform + 위험 줄무늬 채움

**Files:**
- Modify: `assets/shaders/boss_telegraph.gdshader` (uniform 5개 추가 · fragment else-분기 교체)

**배경:** 🔴 **기하·마스크·테두리 판정(`d`, `d_arc`, `d_side`, `edge_bias` 분기)은 절대 손대지 않는다** — 그려지는 도형 = 판정 조건. 바꾸는 건 판정-안의 **채움색**뿐. `stripe_on` 기본값 0.0이라 이 태스크만으로는 화면이 그대로다(콘도 boss.gd가 uniform을 심기 전이라 기본 0). 즉 이 커밋은 **기존 예고를 하나도 안 바꾼다** — 스위치만 심는다.

- [ ] **Step 1: 줄무늬 uniform 5개 추가**

`pulse_hz` uniform 선언(아래) **다음 줄**에 삽입:
```glsl
uniform float pulse_hz = 2.2;        // 알파 맥동 주기(등속 — 위 주석)
```
삽입:
```glsl
// 위험 줄무늬(콘 예고 전용) — stripe_on=1일 때만 채움을 줄무늬로. 🔴 **등속 흐름만**: pulse와 같은
// 근거로 TIME에서 임박도(남은 시간)를 유도하면 게스트가 틀린 남은-시간을 읽는다(§3 지연 보상 계약).
// 격자 스냅점 q로 계산해 줄무늬가 16px 도트처럼 계단진다. 형태는 위에서 이미 갈렸다 — 여긴 색뿐이라
// "맞는 곳=보이는 곳"과 무관하다.
uniform float stripe_on = 0.0;        // 0=단색(원/슬램/물뿌리기 기존 그대로) · 1=줄무늬(콘)
uniform float stripe_period = 14.0;   // 줄 간격(월드 px)
uniform float stripe_speed = 0.6;     // 흐름 속도(등속)
uniform float duty = 0.55;            // 밝은 줄 비율(0~1)
uniform vec4 stripe_dark : source_color = vec4(0.35, 0.078, 0.020, 0.34);  // 어두운 줄
```

- [ ] **Step 2: fragment의 else-분기(채움)를 교체**

아래 기존 블록 전체:
```glsl
	} else {
		float t = clamp(r / max(radius_px, 0.0001), 0.0, 1.0);
		vec4 base = fill_color;
		base.a *= mix(1.0, 1.0 - fill_fade, t);
		if (d <= border_px) {
			base = border_color;                 // 경계 테두리 밴드(위 border_px 주석 — 안쪽만이 아니다)
		}
		// 텍스처는 "무늬"로만 곱한다 — 1×1 흰색이면 정확히 항등이다. 나중에 정사각 풀블리드(알파 1)
		// 패턴을 얹고 싶으면 `boss.gd`의 `_telegraph_quad_tex()`를 갈아야 한다(형태는 계속 셰이더가
		// 정한다 — ⚠ **형태를 그린 텍스처는 안 된다**. 알파가 셰이더 형태를 다시 잘라 정합이 깨진다).
		vec4 tex = texture(TEXTURE, UV);
		float pulse = 1.0 + pulse_amp * sin(TIME * pulse_hz * TAU);
		COLOR = vec4(base.rgb * tex.rgb, clamp(base.a * tex.a * pulse, 0.0, 1.0)) * mod_c;
	}
```
→ 로 교체:
```glsl
	} else {
		float t = clamp(r / max(radius_px, 0.0001), 0.0, 1.0);
		// 채움색만 정한다(안팎은 위에서 이미 갈림 → 계약 무관). stripe_on이면 대각 줄무늬, 아니면 단색.
		vec4 base;
		if (stripe_on > 0.5) {
			// q = 이미 격자 스냅된 점(위). 대각 좌표에 TIME 등속 흐름(임박도 아님 — uniform 주석).
			float sline = (q.x + q.y) / max(stripe_period, 0.0001) - TIME * stripe_speed;
			base = (fract(sline) < duty) ? fill_color : stripe_dark;
		} else {
			base = fill_color;
		}
		base.a *= mix(1.0, 1.0 - fill_fade, t);
		if (d <= border_px) {
			base = border_color;                 // 테두리는 줄무늬 위 — 판정 경계 가독성(위 border_px 주석)
		}
		// 텍스처는 "무늬"로만 곱한다 — 1×1 흰색이면 정확히 항등이다.
		vec4 tex = texture(TEXTURE, UV);
		float pulse = 1.0 + pulse_amp * sin(TIME * pulse_hz * TAU);
		COLOR = vec4(base.rgb * tex.rgb, clamp(base.a * tex.a * pulse, 0.0, 1.0)) * mod_c;
	}
```

- [ ] **Step 3: 웹 안전·계약 자가 점검 (읽기)**

확인(코드 리뷰, 실행 아님): 새 코드가 `floor`(via `fract`)·`TIME`·`mix`·`sin`만 쓰고 derivative(`fwidth`)·`discard`·screen texture가 **없다**(웹 Compatibility 안전). `stripe_on`이 `d`/`d_arc`/`d_side`/`edge_bias` 어디에도 안 들어간다(기하 불변). ✅ 둘 다 만족.

- [ ] **Step 4: 전체 스위트로 회귀 없음 확인**

Run: `bash scripts/run_tests.sh`
Expected: `exit 0` · `TEST_OK` 다수 · `SCRIPT ERROR` 0. (⚠ 셰이더 GLSL 컴파일은 헤드리스가 못 돈다 — 이 스텝은 "다른 것을 안 깼다"만 보증한다. 실제 렌더는 Task 6 실기.)

- [ ] **Step 5: 커밋**

```bash
git add assets/shaders/boss_telegraph.gdshader
git commit -m "추가: 예고 셰이더에 위험 줄무늬(stripe_on) — 콘 전용, 기하 불변"
```

---

## Task 4: boss.gd — 줄무늬 상수 + uniform 심기

**Files:**
- Modify: `src/enemies/boss.gd` (텔레그래프 상수 블록에 4개 추가 · `_apply_telegraph_geometry`에서 5개 심기)

**배경:** 셰이더 `stripe_*` uniform을 콘일 때만 켠다. 🔴 Telegraph 노드는 콘/원을 오가며 **재사용**되므로, `_apply_telegraph_geometry`의 규약("모든 uniform을 매번 심는다 — 안 심으면 이전 패턴 값이 남는다")대로 `stripe_on`도 **매번** 심어야 한다. 안 그러면 콘 뒤에 뜨는 원(슬램)에 `stripe_on=1`이 남아 원이 줄무늬로 나온다.

- [ ] **Step 1: 줄무늬 상수 추가**

`boss.gd`의 텔레그래프 연출 상수 블록에서 아래 줄(현재 파일에 존재):
```gdscript
const TELEGRAPH_PULSE_AMP := 0.10
const TELEGRAPH_PULSE_HZ := 2.2
```
바로 뒤에 삽입:
```gdscript
# 위험 줄무늬(콘 예고 전용, rules §0 예외 — 사용자가 조인다). 셰이더 stripe_* uniform과 미러.
# 🔴 등속만 — 임박도(남은 시간)를 여기서 만들지 마라(셰이더 주석·netreview 계약).
const TELEGRAPH_STRIPE_PERIOD := 14.0     # 줄 간격(월드 px)
const TELEGRAPH_STRIPE_SPEED := 0.6       # 흐름 속도(등속)
const TELEGRAPH_STRIPE_DUTY := 0.55       # 밝은 줄 비율
const TELEGRAPH_STRIPE_DARK := Color(0.35, 0.078, 0.020, 0.34)  # 어두운 줄
```

- [ ] **Step 2: `_apply_telegraph_geometry`에서 uniform 심기**

`_apply_telegraph_geometry` 함수 끝의 아래 줄(현재 파일에 존재):
```gdscript
	mat.set_shader_parameter(&"pulse_amp", TELEGRAPH_PULSE_AMP)
	mat.set_shader_parameter(&"pulse_hz", TELEGRAPH_PULSE_HZ)
```
바로 뒤에 삽입:
```gdscript
	# 위험 줄무늬 — 콘만 켠다(원/슬램/물뿌리기는 단색). 🔴 매번 심는다: 노드가 콘/원 재사용이라
	# 안 심으면 이전 콘의 stripe_on=1이 남아 원이 줄무늬로 나온다(위 함수 주석의 "매번 심는다" 규약).
	mat.set_shader_parameter(&"stripe_on", 1.0 if is_cone else 0.0)
	mat.set_shader_parameter(&"stripe_period", TELEGRAPH_STRIPE_PERIOD)
	mat.set_shader_parameter(&"stripe_speed", TELEGRAPH_STRIPE_SPEED)
	mat.set_shader_parameter(&"duty", TELEGRAPH_STRIPE_DUTY)
	mat.set_shader_parameter(&"stripe_dark", TELEGRAPH_STRIPE_DARK)
```

- [ ] **Step 3: 씬 글루 파스 체크 + 전체 스위트**

Run: `bash scripts/run_tests.sh`
Expected: `exit 0` · `SCRIPT ERROR` 0. 🔴 `run_tests.sh`는 스위트 전에 `boss.gd`를 **파스 체크**한다(문법 오류·없는 상수/함수 호출을 잡는다). `is_cone`은 같은 함수 위쪽에서 이미 선언돼 있고, 새 상수 4개는 Step 1에서 정의됐다 — 오타가 있으면 여기서 잡힌다.

- [ ] **Step 4: 커밋**

```bash
git add src/enemies/boss.gd
git commit -m "추가: boss.gd가 콘 예고에 줄무늬 uniform 심기 (매 프레임 재주장)"
```

---

## Task 5: TUNING.md — 실기 확인 목록 §15

**Files:**
- Modify: `docs/TUNING.md` (§14 뒤에 §15 추가)

**배경:** 헤드리스가 못 잡는 것(렌더·애니 도달·회피·역할 선택)을 실기 목록에 올린다. 🔴 지연 관련(줄무늬 등속의 클라 정합)은 `dev_local.sh`(13.8ms)로는 재현 안 되고 배포본이라야 한다.

- [ ] **Step 1: §15 블록 추가**

`docs/TUNING.md`의 §14 섹션 **끝**(다음 `## ` 헤더 앞 또는 파일 끝)에 삽입:
```markdown
## 15. 실기 확인 목록 — 미노 전방 후리기(cone) + 위험 줄무늬 예고 (2026-07-31, 전량 미확인)

> 헤드리스가 못 잡는 것만. 데이터 계약은 `test_boss_data_auto.gd`가 이미 그린. 도구 = `?host&debug=1` → **F1** → 미노 소환(또는 챕터1 보스방).

### A. 혼자 · 로컬(에디터/웹)에서 되는 것

| # | 무엇을 본다 | ❌ 실패 신호 |
|---|---|---|
| **A-1** 🔴 | **줄무늬 예고 실물(웹)** — 미노에 붙어 후리기를 유도한다. 🔴 에디터(네이티브 GL)에서만 컴파일 확인됨 — **웹 Compatibility가 첫 확인**이다 | 부채꼴에 대각 줄무늬가 **안 뜬다**(단색이면 stripe_on 미전달) · 줄무늬가 부채꼴 **밖으로 샌다**(테두리=판정 경계 육안 대조 — 새면 계약 위반) · 셰이더 컴파일 에러로 예고가 **안 보인다**(그러면 무예고 피격) |
| **A-2** | **역할 분리** — 붙으면 후리기(cone), 벌어지면 슬램(circle) | ≤110px에서 슬램만 나온다(priority 미반영) · 파고들지 않는다(keep_distance 0 미반영) |
| **A-3** | **회피** — 예고 뜨면 **부채꼴 밖(측면)**으로 스텝 | 옆으로 빠졌는데 맞는다(예고 각 ≠ 판정 각 — 셰이더 기하를 건드렸다는 신호) |
| **A-4** | **원/물뿌리기 회귀 없음** — 슬램·(있으면)물뿌리기 예고가 **여전히 단색** | 원/물뿌리기가 줄무늬로 나온다(stripe_on이 콘 뒤에 남음 — Task 4 "매번 심기" 회귀) |
| **A-5** | **애니 정합** — 도끼 임팩트 프레임 ↔ 예고 종료(판정 순간) | 도끼가 닿기 전/후에 데미지가 뜬다(슬램도 같은 구조라 신규 위험은 아님 — telegraph_s/애니 speed로 조인다) |

### B. 2인 + 배포본이라야 되는 것

🔴 **`dev_local.sh`(13.8ms)로는 재현 안 됨.** 반드시 `game.jachana.com`.

| # | 무엇을 본다 | ❌ 실패 신호 |
|---|---|---|
| **B-1** | **줄무늬 흐름 정합** — 호스트/게스트 화면에서 줄무늬가 **등속**으로 흐른다 | 게스트 화면에서 줄무늬가 타격 임박에 **빨라지거나 진해진다**(누군가 stripe_speed를 `_telegraph_left`로 유도 = 계약 위반 회귀) |
| **B-2** | **원격 콘 정합** — 게스트가 미노 후리기를 회피 | 게스트 예고 각/위치가 호스트와 어긋나 못 피한다 |

### C. 조일 노브 (실기 후)

- **줄 간격/속도/비율** → `src/enemies/boss.gd`의 `TELEGRAPH_STRIPE_PERIOD`·`TELEGRAPH_STRIPE_SPEED`·`TELEGRAPH_STRIPE_DUTY`·`TELEGRAPH_STRIPE_DARK`(셰이더 uniform과 미러 — 한쪽만 바꾸지 마라).
- **후리기 수치** → `data/enemies/wraith_boss.tres`의 `pat_cone`: `telegraph_s`(🔴 애니 1.2s 기준 ≥0.8 유지 — `test_boss_data_auto.gd` 1.5배 계약)·`range`·`half_angle`·`damage`·`cooldown_s`·`use_max_dist`·`priority`.
- 🔴 **`range`·`half_angle`는 판정이자 예고 기하다** — 조이면 예고와 판정이 **함께** 움직인다(그게 계약). 예고만/판정만 따로 바꾸는 자리는 없다.
```

- [ ] **Step 2: 문서 규율 체크**

Run: `bash scripts/check_harness.sh`
Expected: `exit 0` (소유권 표 링크·이력 길이 규율 통과). 실패하면 출력이 가리키는 항목 수정.

- [ ] **Step 3: 커밋**

```bash
git add docs/TUNING.md
git commit -m "문서: 미노 후리기+줄무늬 예고 실기 확인 목록 §15"
```

---

## Task 6: 최종 검증 + 실기 인계

**Files:** 없음 (검증만)

- [ ] **Step 1: 전체 스위트 최종**

Run: `bash scripts/run_tests.sh`
Expected: `exit 0` · `TEST_OK` 다수(포함 `TEST_OK boss_data`) · `SCRIPT ERROR` 0.

- [ ] **Step 2: 남은 것은 실기임을 명시**

자동 테스트는 데이터 계약 + 씬 글루 파스까지만 보증했다. 🔴 **셰이더 렌더·줄무늬·역할 선택·회피·2인 정합은 `docs/TUNING.md §15`의 A/B 목록으로 사람이 확인**해야 한다(헤드리스 구조적 한계). 리드에게 실기 확인을 요청한다.

- [ ] **Step 3: 리뷰 관문**

`boss.gd`·셰이더 변경은 **네트워크에 안 닿는다**(표시 전용 · 판정은 기존 경로 재사용). 따라서 `projectb-reviewer`(품질·계약·이식성)로 리뷰하되, 두 축을 명시적으로 보라고 지시: ⑴ "맞는 곳=보이는 곳"(셰이더 기하 불변) ⑵ TIME에서 임박도 유도 없음. netreview는 불요.

---

## Self-Review (작성자 점검 결과)

- **Spec 커버리지:** ① 패턴 데이터=Task1 · ② keep_distance=Task1 · ③ 줄무늬 예고=Task3+4 · 검증=Task2·6 · 리뷰 관문=Task6. 스펙의 "열린 물음"(줄무늬 색/속도 const vs 셰이더 기본값)은 **const로** 확정(Task4). 갭 없음.
- **플레이스홀더:** 없음 — 모든 스텝에 실제 코드/명령/기대 출력.
- **타입/이름 일관성:** uniform 이름(`stripe_on`·`stripe_period`·`stripe_speed`·`duty`·`stripe_dark`)이 셰이더(Task3)와 boss.gd `set_shader_parameter`(Task4)에서 **정확히 일치**. 상수(`TELEGRAPH_STRIPE_*`)는 Task4 Step1 정의 → Step2 사용. `is_cone`은 기존 함수 변수 재사용. SubResource id `pat_cone`는 Task1 Step2 정의 → Step3 참조.
- **알려진 경계값:** `telegraph_s 0.9` = 애니길이 1.2s / 0.9 = 1.333 ≤ 1.5(계약). 0.8(=1.5 경계)을 피한 이유를 Task1 배경에 명시.
