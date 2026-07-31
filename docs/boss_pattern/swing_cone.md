# P1 · 도끼 후려치기 (전방 후리기 / `swing` · cone)

> 작성 2026-07-31 · 브레인스토밍 산물. **작업용 설계 노트지 정본이 아니다** — 확정되면 수치는 `docs/TUNING.md`, 기획 내용은 `docs/GDD.md`(🔒 승인제)로 증류한다.
>
> 상위 문서 = `docs/boss_pattern/minotaur_patterns.md`(전체 로테이션, 이 패턴은 표의 **P1**). 구현 스펙 = `docs/superpowers/specs/2026-07-31-boss-swing-cone-telegraph-design.md`.

---

## 1. 컨셉 한 줄

**미노의 가장 기본이 되는 제자리 근접기.** 플레이어가 붙으면 정면으로 도끼를 크게 후려친다. 거리별 역할 분리에서 **근접 = 후리기 / 중거리 = 슬램(P2)**. "붙으면 위험, 예고 보고 옆으로 빠져라"를 가르치는 첫 상호작용.

- 형태 = `cone`(전방 부채꼴). 이동 없음 — 제자리 스윙(돌진 P3와 정반대: 여긴 안 움직인다).
- def 전환 전제: `keep_distance 150 → 0`(파고들어야 사거리 120이 닿는다).
- GDD §5 원칙: 텔레그래프(0.8s) ≥ 구르기(0.25s)보다 충분히 김 → 프레임 반응 요구 없음(웹 지연 공정성).

---

## 2. 동작 · 회피

### 동작
보스가 제자리에 서서 도끼를 옆으로 뺐다가 **정면 부채꼴로 후려친다.** 위협 = 부채꼴 안(사거리 120, 반각 ~40°) 하나. apex = 보스 위치.

### 회피 (공정성)
- **옆으로 비켜라 = 부채꼴 밖.** 예고가 정면 부채꼴이라, 옆이나 뒤로 빠지면 안전. 정면에서 물러나기(뒤로 구르기)보다 **측면 스텝**이 정답.
- 부채꼴 밖으로만 나가면 사거리 안이어도 안 맞음 → "각을 읽어라"가 학습 포인트.

---

## 3. 예고 = 위험 줄무늬 (만들 오브젝트)

🔴 **형태는 판정 그 자체다.** 부채꼴 기하(range·half_angle)는 `boss_telegraph.gdshader`가 판정 조건에서 **직접 그린다** → "맞는 곳 = 보이는 곳" 자동 보장. 형태·크기·테두리 로직은 **건드리지 않는다**(과거 텍스처로 각을 박았다가 19px 무예고 피격 사고).

### 바꾸는 것 = 내부 채움만
기존 단색 빨간 부채꼴 → **대각 위험 줄무늬**(공사장 경고 톤). 부채꼴 안을 흐르는 앰버 빗금.

- **어떻게:** 셰이더의 판정-안(`d >= -edge_bias_px`) 채움 색 계산만 교체. 이미 격자 스냅된 점 `q`로 대각 좌표 `s = (q.x + q.y)/stripe_period - TIME*stripe_speed`를 만들고 `fract(s) < duty`면 밝은 줄, 아니면 어두운 줄. `q`를 쓰므로 빗금도 **도트 블록으로 계단져** 16px 픽셀아트 톤 유지.
- **테두리 유지:** 밝은 테두리 밴드(`d <= border_px`)는 그대로 → 부채꼴 가장자리(=판정 경계) 가독성.
- 🔴 **흐름은 `TIME` 등속만.** 임박도(남은 시간)를 `TIME`에서 유도 금지 — 호스트 예고 창은 지연 보상분만큼 길어 남은 시간이 클라마다 다르다. 유도하면 게스트가 틀린 임박 신호를 읽는다(netreview 2026-07-27 계약). 기존 알파 맥동과 같은 무해 관용구.
- **웹 안전:** `floor`/`fract`/`TIME`/`length`/`sin`만. derivative·discard·screen texture 없음.

### 신규 uniform
| uniform | 뜻 | 비고 |
|---|---|---|
| `stripe_period` | 빗금 간격(월드 px) | 도트 격자와 어울리는 값 |
| `stripe_speed` | 흐름 속도 | 등속(위 계약) |
| `stripe_dark : source_color` | 어두운 줄 색 | 밝은 줄 = 기존 `fill_color` 재사용 |
| `duty` | 밝은 줄 비율 | 실기 튜닝 |

> 목업 4안 중 **B(위험 줄무늬)** 채택. 참고 = `.superpowers/brainstorm/.../telegraph-style.html`.

---

## 4. 상태 · 타이밍 (기존 FSM 재사용 — 신규 상태 없음)

돌진(P3)과 달리 **전용 상태머신이 필요 없다.** 기존 `boss.gd`의 WINDUP → STRIKE → RECOVER를 그대로 탄다.

| 단계 | 시간 | 무슨 일 |
|---|---|---|
| WINDUP | `telegraph_s 0.8` | 정지 + `swing` 애니 재생(예고 길이에 맞춰 speed_scale) + 부채꼴 줄무늬 예고 + 방향 고정 |
| STRIKE | 만료 순간 | `boss_strike` 1회 → `CombatAuthority`가 `is_hit_in_cone_lagged`로 판정(호스트) |
| RECOVER | `recover_s 0.4` | 짧은 후딜, 정지 유지 |

수치(시작값, 전부 튜닝 대상): `telegraph_s 0.8` · `damage 10` · `range 120` · `half_angle 0.7` · `cooldown_s 2.0` · `recover_s 0.4` · `priority 1` · `use_max_dist 130` · `min_phase 1`.

---

## 5. 만들어야 할 것

### 5-1. 아트 / 애니메이션 (`projectb-art`)
- 🔴 **`swing` 클립은 이미 완성돼 있다 — 새로 만들 애니 없음** (실측 2026-07-31, `mino_boss.png` 육안 확인). `mino_boss_frames.tres`:
  - `swing` = 아틀라스 프레임 **f9~f17 (9프레임)**, `loop=false`, `speed=7.5`. 64px 도끼 브루트가 도끼를 휘두르는 실제 애니.
  - 명목 길이 = 9/7.5 ≈ 1.2s. `boss.gd`가 WINDUP에서 `telegraph_s`(0.8s)에 맞춰 `speed_scale`로 **압축 재생**한다(제자리 슬램과 동일 경로).
  - ⚠ **플레이스홀더 경보(우리 패턴과 무관하지만 기록):** `spray` 클립이 `swing`과 **동일한 f9~f17을 재사용**한다. spray 전용 아트는 아직 없다. 후리기(swing)에는 영향 없음.
  - 재사용 자산(새로 안 그림): 히트스톱 · 히트플래시 · 궤적 리본(기존 칼 잔상) = feel 계층.
- **신규 오브젝트 없음** — 이 패턴은 지형/발사체를 안 만든다(예고는 셰이더가 그리는 표시 전용).
- ⚠ **손맛 실기 확인거리:** 판정은 WINDUP 만료(클립 끝) 시점에 확정된다. 9프레임 안에서 도끼가 실제로 "닿는" 임팩트 프레임이 클립 중간이면, 눈에 보이는 타격과 판정 순간이 어긋날 수 있다(슬램도 같은 구조라 신규 위험은 아님). 실기에서 임팩트 프레임 ↔ 예고 종료 정렬을 본다.

### 5-2. 데이터 리소스 (리드)
- `data/enemies/wraith_boss.tres`에 `BossPatternDef` 서브리소스 1장 추가 + `patterns` 배열에 삽입.
- ⚠ SubResource id 충돌 주의: 기존 `pat_swing`은 그 `id`가 헷갈리게도 `"slam"`이다. 새 것은 SubResource id `pat_cone`(안의 `id`만 `"swing"`).
- `keep_distance 0`으로 변경.

### 5-3. 코드 / 셰이더 (`projectb-dev`)
- **신규 상태머신 없음** — 기존 cone 경로 재사용.
- `boss_telegraph.gdshader` 내부 채움 → 줄무늬(위 §3). 신규 uniform 4개.
- (선택) `boss.gd`가 줄무늬 색/속도 uniform을 심을지, 셰이더 기본값으로 둘지 결정. 기하값이 아니므로 손맛 상수 예외 가능.
- ⚠ **네트워크 안 닿음**(표시 전용·판정은 기존 경로) → `projectb-reviewer`(품질·계약), netreview 불요.

---

## 6. 필요 애니메이션 정리

| 클립 | 아틀라스 프레임 | 프레임 수 | loop | speed | 상태 | 비고 |
|---|---|---|---|---|---|---|
| `swing` | f9~f17 | 9 | false | 7.5 | WINDUP 재생 | **이미 완성** · 예고 0.8s에 speed_scale 압축 |

> 실측(`mino_boss_frames.tres` · `mino_boss.png`, 2026-07-31). 이 패턴이 **새로 요구하는 클립은 없다.** 공통 클립: `idle`=f0 · `walk`=f1~f8 · `slam`(P2)=f18~f25 · `death`는 아직 시트에 **없음**(있으면 시체 남김, 없으면 사망 시 숨김 — 상위 문서 §6).

---

## 7. 열린 항목 (TBD)

- **수치 튜닝:** telegraph_s · range · half_angle · damage · cooldown_s · use_max_dist · priority → 실기(`docs/TUNING.md §13`).
- **줄무늬 파라미터:** stripe_period · stripe_speed · duty · stripe_dark 색 → 실기 튜닝.
- **줄무늬 색/속도** `boss.gd` const vs 셰이더 기본값 선택.
- **`swing` 애니 손맛** — 선딜/타격/후딜 프레임 타이밍이 예고 0.8s와 붙는지 실기 확인.
- **역할 경계** — `use_max_dist 130`이 슬램(210)과 겹치는 구간(≤130)에서 priority로 후리기가 이기는지 실기 확인.
