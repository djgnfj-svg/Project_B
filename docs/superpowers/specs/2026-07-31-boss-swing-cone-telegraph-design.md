# 미노타우로스 「전방 후리기」 + 위험 줄무늬 예고 — 설계

- 날짜: 2026-07-31
- 대상 보스: 미노타우로스 (`data/enemies/wraith_boss.tres` = 현재 `BossDef` 정본)
- 상태: 설계 확정, 구현 대기

## 목표

미노에게 **가장 기본이 되는 제자리 근접 패턴** 하나를 준다. 지금 미노는 `slam`(원형 내려찍기) 하나뿐이라 거리별 역할이 없다. **전방 부채꼴 후리기(cone)** 를 근접 기본기로 넣어 "붙으면 후리기 / 벌어지면 슬램"으로 역할을 가른다. 동시에 이 후리기의 예고를 기존 단색 빨간 부채꼴이 아니라 **위험 줄무늬**로 색다르게 표시한다.

## 범위

- ✅ cone 패턴 `swing` 추가 (데이터).
- ✅ `keep_distance`를 0으로 (미노가 파고들어 후리기가 닿게).
- ✅ `boss_telegraph.gdshader` 내부 채움을 위험 줄무늬로 (셰이더).
- ❌ 돌진·이동 공격 (다른 세션에서 검토 — 신규 메커닉).
- ❌ 신규 스프라이트/애니 (미노에 `swing` 애니 이미 존재).
- ❌ 예고에 남은-시간(임박도) 싣기 (아래 계약상 별도 결정 — 이번엔 등속만).

## 이미 갖춰진 배선 (신규 코드 불필요)

- `CombatMath.is_hit_in_cone_lagged` — cone 판정 함수.
- `CombatAuthority._on_boss_strike` — `shape=="cone"` 분기 존재.
- `boss.gd._begin_windup` — `shape=="cone"`면 apex=보스 위치로 텔레그래프.
- `mino_boss_frames.tres` — `swing` 애니 존재 (`ATTACK_ANIMS`에 `swing` 포함).
- `boss_telegraph.gdshader` — 부채꼴 기하를 코드로 그림(마스크·테두리 완비).

## ① 패턴 데이터 — `swing` (cone)

`data/enemies/wraith_boss.tres`에 `BossPatternDef` sub_resource 한 장 추가하고 `patterns` 배열에 넣는다. 기존 `pat_swing`(=slam) sub_resource를 템플릿으로 미러.

⚠ **이름 충돌 주의**: 기존 sub_resource의 SubResource id는 헷갈리게도 `pat_swing`인데 그 `id`는 `"slam"`이다. 새 cone sub_resource의 SubResource id는 충돌을 피해 `pat_cone`(또는 `pat_swing_cone`)로 두고, 안의 `id`만 `"swing"`으로 한다.

| 필드 | 값 | 근거 |
|---|---|---|
| `id` | `"swing"` | 동명 애니 선택 키 (이미 존재) |
| `shape` | `"cone"` | 정면 부채꼴 |
| `telegraph_s` | `0.8` | 슬램(1.2)보다 빠른 기본기. 구르기(0.25)보다는 충분히 김 |
| `damage` | `10` | 기본기 — 슬램(12)보다 약간 낮게 |
| `range` | `120.0` | 부채꼴 사거리 |
| `half_angle` | `0.7` | 반각 ~40° |
| `cooldown_s` | `2.0` | 자주 나오는 기본기 |
| `recover_s` | `0.4` | 짧게 |
| `priority` | `1` | 근접에선 슬램(0)보다 우선 선택 |
| `use_min_dist` | `0.0` | |
| `use_max_dist` | `130.0` | 사거리 안일 때만 후보 |
| `min_phase` | `1` | 처음부터 개방 |

🔴 값은 전부 시작값 — 실기 후 사용자 튜닝 대상(`docs/TUNING.md`). `range`/`half_angle`는 판정=예고 기하이므로 조이면 둘 다 같이 움직인다(하드 계약).

## ② 거동 — `keep_distance = 0`

현재 미노 `keep_distance = 150` > 후리기 사거리(120)라 그대로면 후리기가 **영영 안 나온다**. 0으로 바꿔 순수 추격 → 얼굴로 파고들어 후리기. 카이팅 거동은 사라진다(의도된 트레이드오프 — "기본 근접 보스" 손맛).

## ③ 위험 줄무늬 예고 (`boss_telegraph.gdshader`)

🔴 **불변**: 부채꼴 **기하·마스크·테두리 판정 로직**(`d`, `d_arc`, `d_side`, `edge_bias` 분기)은 손대지 않는다. 그려지는 도형 = 판정 조건이라, 여길 바꾸면 "맞는 곳=보이는 곳"이 갈라진다(2026-07-26 19px 무예고 피격의 재발).

**바꾸는 것**: 판정 안(`d >= -edge_bias_px`)의 **채움 색 계산**만. 지금은 단색 `fill_color` + `fill_fade`. 이를 **대각 줄무늬**로 교체:

- 이미 격자 스냅된 점 `q`로 대각 좌표 `s = (q.x + q.y)/stripe_period - TIME*stripe_speed`를 만들고, `fract(s) < duty`면 밝은 줄, 아니면 어두운 줄. `q`를 쓰므로 줄무늬도 도트 블록으로 계단져 픽셀아트 톤 유지.
- **테두리 밴드(`d <= border_px`)는 그대로 밝게 유지** — 가장자리 가독성.
- 🔴 **흐름은 `TIME` 등속만.** 임박도(남은 시간)를 `TIME`에서 유도하지 않는다 — 호스트 예고 창은 지연 보상분만큼 길어 남은 시간이 클라마다 다르므로, `TIME` 유도는 게스트에게 틀린 임박 신호를 준다(netreview 2026-07-27 계약). 기존 알파 맥동과 같은 무해 관용구.
- 웹(Compatibility/GLES3) 안전 유지: `floor`/`fract`(=floor)/`TIME`/`length`/`sin`만. derivative·discard·screen texture 없음.

**신규 uniform**: `stripe_period`(줄 간격, 월드 px) · `stripe_speed`(흐름 속도) · `stripe_dark : source_color`(어두운 줄 색). 기본값은 유도식 주석 규율에 맞춰 에디터 프리뷰가 맞게. `boss.gd`가 런타임에 색/속도를 심을지, 셰이더 기본값으로 둘지는 구현 시 결정(기하값이 아니므로 손맛 상수 예외로 `boss.gd` const 가능).

⚠ **미러 주의**: 셰이더 좌표 규약은 `boss.gd._apply_telegraph_geometry`와 미러다. 줄무늬는 기하가 아니라 색이라 좌표 계약은 안 건드리지만, 새 uniform을 `boss.gd`가 심는다면 그 배선도 같이 본다.

## 검증

🔴 헤드리스가 **못 잡는 것**: 예고 렌더 모양·줄무늬 흐름·애니 도달·클릭 회피(구조적 한계, `projectb-verify`). 실기 목록에 올린다(`docs/TUNING.md §13`).

헤드리스로 **잡는 것**:
- 패턴 선택기 — 근접(≤130)에서 `swing`(priority 1)이 `slam`보다 우선 선택되는지, 130 밖에서 슬램으로 넘어가는지 (결정적 선택 로직, 단언 가능).
- cone 판정 기하 — `is_hit_in_cone` 회귀 (기존 `test_combat_math_auto.gd`에 이미 커버, 값만 확인).
- 씬 글루 파스 체크 — `boss.gd` 변경분(`keep_distance` 경로) 문법·함수 존재.

전량: `bash scripts/run_tests.sh` (Bash 툴). 판정 3조건(exit 0 + TEST_OK≥1 + SCRIPT ERROR 0).

실기(에디터+웹): 후리기 예고가 부채꼴에 줄무늬로 뜨는지 · 줄무늬가 판정 밖으로 새지 않는지(테두리=판정 경계 육안 대조) · 근접에서 후리기가 슬램 대신 나오는지 · `keep_distance=0`으로 파고드는 거동.

## 리뷰 관문

- `boss_telegraph.gdshader` + `boss.gd` 변경 → 네트워크에 닿지 않음(표시 전용, 판정은 기존 경로 재사용)이므로 `projectb-reviewer`(품질·계약·이식성). 단 셰이더 계약("맞는 곳=보이는 곳", TIME 임박 금지)이 핵심이라 리뷰에서 이 두 축을 명시적으로 본다.
- 데이터(.tres)만이면 리뷰 경량.

## 열린 물음 (구현 중 결정)

- 줄무늬 색/속도를 `boss.gd` const로 심을지 셰이더 기본값으로 둘지.
- `duty`(밝은 줄 비율) 기본값 — 실기 튜닝.
