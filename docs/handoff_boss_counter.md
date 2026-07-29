# 보스 카운터 콘텐츠 — 인수인계 (다음 세션용)

> 작성 2026-07-29 · 브랜치 `feat/MonsterAnima` (origin 푸시됨) · 이 문서는 **WIP 곁문서**다(정본 아님).
> 정본은 `CLAUDE.md`(구현) / `docs/GDD.md`(기획). 여기는 "지금 뭐 하다 멈췄고, 다음에 뭘 이어받나"만 적는다.

---

## 0. 한 줄 요약
보스(몰락한 망령 = **Ghost Nos**)의 기존 공격 패턴 3종(swing/slam/spray)을 **전부 제거**하고,
**"돌진을 F로 받아치는 카운터 + 룬 자물쇠 격파 + 그로기"** 로 재구축 중. **전부 테스트 랩(`?test=1`) 프로토타입**이고
실게임(`stage_boss.tscn`)엔 아직 안 올렸다. **협동(2인) 배선이 핵심 미완.**

- **배포(실기 확인):** `https://projectb-game.youqlrqod.workers.dev/?test=1&host` — ⚠ 브라우저 **강력 새로고침(Ctrl+Shift+R)**.
  - ⚠ jachana.com 아님 — 이 머신 wrangler 로그인이 youqlrqod 계정이라 workers.dev 임시 주소로 나간다.
  - 커밋해도 서버 반영 안 됨 → `bash scripts/deploy_web.sh` 를 **따로** 돌려야 한다.

---

## 1. 먼저 읽을 것 (순서대로)
1. **`CLAUDE.md`** — 구현 정본. 매 세션 자동 로드되지만 카운터 관련은 아직 여기 안 적혀 있음(이 문서가 대신).
2. 스킬 **`projectb-rules`** — 🔴 코드 만지기 전 필수. 아키텍처 규칙·모듈 지도·하드 계약·"조용히 깨지는 함정".
3. 스킬 **`projectb-verify`** — 헤드리스 테스트·검증 규율(헤드리스가 못 잡는 것 = 실기 몫).
4. **`docs/CHANGELOG.md`** — 전체 변경 이력 전문.
5. (기획) **`docs/GDD.md`** — 🔴 **카운터/룬/협동은 아직 GDD에 없다**(브레인스토밍 단계). 코어 전투 설계라, 방향이 굳으면
   `projectb-critic`(점검) → 사용자 승인 → `projectb-gdd` 스킬(기록) 순으로 §에 넣어야 한다. 지금은 랩 실험 단계.

---

## 2. 카운터 메커니즘 현황 (구현된 플레이 흐름)

```
5초 대기 → 눈 반짝(예고) → 조준(보스가 플레이어를 바라봄) → 돌진(고정 방향 직선)
                                    │
                          ┌─ 앞에서 근접(마커 노랑 "지금!") F → 성공(클래시 + 보스 잠깐 꿇음)
                          ├─ 너무 일찍 F → 잠금(빨간 ✕, 이번 돌진 못 침)
                          └─ 못 치고 내 뒤를 지나감 → 실패(HP-1, 넉백X 위치고정, 보스 근처 텔포)

  ★ 룬 자물쇠 3개: 활성 1개만 색이 있는데 "시야 콘 안에 들어와야" 금색 "★격파★"로 드러남
                    (시야 밖/비활성 = 회색 "룬 N", 구분 불가) → 시야로 스캔해 찾는다
     활성 룬 위에서 성공 = 파훼 → 화려 FX(추가 스파크·큰 흔들림) + 보스 10초 그로기(눕고 "그로기중... N", 카운터 정지)
```

### 핵심 파일·심볼
- **`src/stage/test_lab.gd`** (랩 전용, TestMode 게이트 — 프로덕션 무접촉):
  - 상태머신: `_update_counter()` — 상태 `CS_IDLE / CS_GLINT / CS_AIM / CS_DASH`
  - 입력/판정: `_try_counter()`(F, 0.5s 쿨), `_player_in_active_rune()`, `_rune_in_vision()`
  - 연출: `_counter_strike()`(클래시=둘이 부딪힘→튕김), `_clash_impact()`(피해·꿇음·파훼분기·그로기발동), `_clash_fx()`, `_charge_hit()`(실패)
  - 룬: `_setup_runes()`, `_make_rune_lock()`, `_update_runes()`
  - 시야 콘: `_setup_vision()`/`_ensure_vision()`(자가복구), `VISION_HALF/LEN`
  - 튜닝 상수: `COUNTER_INTERVAL 5` · `COUNTER_GLINT 0.5` · `CHARGE_AIM 0.5` · `CHARGE_SPEED 1550`(x2.5) ·
    `PARRY_OPEN_RANGE 165` · `PARRY_WINDOW 0.28` · `RUNE_RADIUS 50` · `RUNE_POS`(보스방 3점) · `ARENA_SAFE`(맵 클램프)
- **`src/enemies/boss.gd`** (실게임 보스 — 표시 전용 훅, 기본값 프로덕션 무영향):
  - `counter_ready`(약점 뜬 동안 몸색 앰버) · `counter_stagger()`(짧은 꿇음) · `enter_groggy()`/`groggy_left`(격파 시 눕고 무방비) · `speed_mult`(접근속도 배수) · 유령 생명감(부유/명멸/아우라/망토 skew/노이즈)
- **`src/combat/health_component.gd`**: `force_damage_one`(정적, 랩 데미지 1 캡) · `apply_damage(dmg,crit,bypass_invincible)`(실패에 무적 뚫고 피해)
- **`src/player/player.gd`**: `roll_suppressed`(돌진 중 F=카운터가 구르기와 안 겹치게 — 🔴 **F가 `roll` 키에 매핑돼 있다**, project.godot)
- 데이터: `data/enemies/wraith_boss.tres` — `patterns = []`(비움) · 스프라이트 `boss_wraith.png`(2880×64, walk/idle 8프레임 보간됨)

---

## 3. 다음 작업 (우선순위)

1. 🔴 **협동(2인) 배선 — 핵심 미완.** 사용자 확정 설계 = **"P2만 룬을 찾을 수 있다"**(P2=스캐너, 시야로 룬을 드러냄 → 콜 / P1=격파, 그 룬 위에서 받아치기).
   - 지금은 **로컬 플레이어가 룬을 봄**(솔로 테스트용 임시). 진짜는 **P2 시야만 룬 색을 드러내고 P1은 회색만** 봐야 한다.
   - 🔴 **랩이 솔로 호스트용이라 2인이 붙으면 삐걱**한다 — 카운터 상태머신·보스 이동을 양쪽이 각자 돌린다(호스트 권한 정리 필요). 실 2인 테스트 전에 이걸 먼저 손봐야 함.
   - 선택지: (A) 솔로로 감각만 더 다듬기 (B) NPC(P2) 자동 스캔 시뮬 (C) 2인 실기 배선.
2. **`test_boss_data_auto` RED 해소.** 패턴 0개라 "패턴 ≥1" 트립와이어가 잡는다(의도된 WIP 상태). 카운터를 `BossPatternDef`로 편입할지, 별도 시스템으로 둘지 정하고 해소. **트립와이어는 유지**(가치 있음).
3. **랩 → 실 `stage_boss.tscn` 이식.** 카운터·룬·환경 연출·시야 콘·HP바 전부 랩 전용. 실게임에 올리려면 이식 + 호스트 권한 배선.
4. **튜닝(실기):** 돌진 속도 1550 · 창 0.28s · 그로기 10s · 룬 위치/개수 · 활성 룬을 매 라운드 바꿀지.
5. **그로기 딜타임 살리기:** 무방비 10초 동안 피해 증폭 등 보상 설계.

---

## 4. 함정 / 주의 (겪은 것들)
- 🔴 **F = `roll`(구르기) 키** (project.godot). 카운터가 F라 충돌 → `roll_suppressed`로 카운터 시퀀스+클래시 동안 구르기 억제. F 쿨 0.5s도 있음. 협동/이식 때 이 충돌 재발 주의.
- 🔴 **MCP 재실행 후 첫 `Net.host_room`이 "Net busy(state=3)"로 무시**돼 마을로 튀는 경우 있음 → `Main` 자식이 `Lobby`인지 확인 후 host. 마을로 갔으면 stop→run 다시.
- **`_boss`는 `Node` 타입**이라 `_boss.global_position`으로 `:=` 추론하면 파싱 에러("Cannot infer type") — 항상 `var x: Vector2 = ...` 명시. (이 세션에서 5번 걸림)
- **맵 밖 이탈:** 카운터/돌진/넉백은 tween으로 위치를 바꿔 벽 충돌을 우회한다 → 반드시 `_clamp_arena()`로 클램프.
- **데미지=1 · 플레이어 무적**은 랩 테스트 세팅(실패만 무적 뚫음). 실게임엔 안 감.
- **헤드리스는 GLSL·클릭·시간경과·클래시 전환(0.2~0.6s)을 못 잡는다** → 실기(배포본) 확인 몫. 상태값 읽기(`godot_exec`)로 로직만 검증.

---

## 5. 최근 커밋 (feat/MonsterAnima)
```
fae4660 추가: 룬 자물쇠 + 격파(파훼) + 보스 그로기 10초 (테스트 랩)
8b812d5 변경: 카운터 실패 처리 — 넉백 제거(위치 고정) + 보스 근처 텔포
0f06be5 수정: 카운터 F 연타 시 맵 밖으로 튀어나가던 것
1d947e4 추가: 보스 카운터/돌진 프로토타입 (테스트 랩) + 지원 훅
857ae69 변경: 보스 공격 패턴 전부 제거 — 카운터 중심으로 재구축 착수
```
