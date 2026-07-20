# Project_B

> **정본은 두 곳이다 — 역할이 다르다.**
> - **기획 정본 = `docs/GDD.md`** — 게임이 "무엇인가"(비전·핵심 루프·메커니즘·콘텐츠). 🔒 **수정 시 사용자 승인 필수** (`.claude/settings.json` 권한 규칙으로 잠김). 담당 = `projectb-planner`.
> - **구현 정본 = 이 문서(CLAUDE.md)** — 하네스·아키텍처·검증 규율. 스킬·에이전트와 충돌하면 여기가 이긴다.

- **정체:** 2D **웹 게임** (코드네임 Project_B) — Godot 4.7.1, **Web(HTML5/WASM) 익스포트 타깃**, 렌더러 Compatibility(웹 필수).
- 🔴 **네트워크 리뷰는 항상 필요하다.** 웹 게임이라 네트워크(WebSocket·RPC·동기화·권한·지연/재접속 처리)가 코어다. 네트워크에 닿는 코드는 예외 없이 `projectb-reviewer`의 네트워크 점검을 거친다 — 브라우저는 ENet(UDP)을 못 쓰므로 WebSocket 경로가 맞는지, 신뢰 경계·권한 검증이 있는지 매번 본다.
- **엔진 실행 파일:** 루트의 `Godot_v4.7.1-stable_win64.exe`.
- **상태:** 초기 단계 — 게임 설계·모듈·에셋 아직 미확정. 뼈대(하네스)만 구성됨. **게임 기획은 `docs/GDD.md`에서 `projectb-planner`와 함께 채운다.**

> **TODO(리드):** 게임 장르·핵심 루프가 GDD에서 정해지면 `projectb-rules`의 §1~§5(오토로드·모듈 지도·하드 계약·데이터 주도·함정)를 실제 내용으로 채운다.

## 하네스: Project_B (2D Godot)

**목표:** Project_B의 Godot 개발을 전문 에이전트 팀으로 나눠, 아키텍처 규칙·검증 규율을 일관되게 지키며 구현한다.

**트리거 규칙:**
- **코드를 쓰거나·읽거나·리뷰하거나·서브에이전트에 위임하기 전에 반드시 `projectb-rules` 스킬을 읽어라.** 아키텍처 규칙·모듈 지도·하드 계약·"조용히 깨지는 함정"이 여기 있다.
- **헤드리스 테스트를 돌리거나·"테스트는 그린인데 게임이 안 된다"를 만나면 `projectb-verify` 스킬을 읽어라.**
- 단순 질문은 스킬 없이 직접 응답 가능.

**에이전트 라우팅 (리드가 위임):**
- 기획/GDD = `projectb-planner` (게임을 무엇으로 만들지 정함 · GDD 수정은 승인제)
- 기획 검증 = `projectb-critic` (planner가 만든 기획의 정합성·모순·구멍을 적대적으로 뜯음 · GDD 수정 안 함)
- 구현 = `projectb-dev` · 설계/계획 = `projectb-architect` · 리뷰 = `projectb-reviewer`
- 아트(도트) = `projectb-art` · Control UI = `projectb-ui` · 애니 배선 = `projectb-animator`
- 2D 셰이더 = `projectb-shader` · 성능 진단 = `projectb-profiler` · 에디터 툴 = `projectb-tools`
- **리드가 직접 하는 것:** core 스키마 변경, `mcp__godot` 필요 작업, `--import`, git 커밋, 회귀 위험이 큰 tight 검증 루프.

**검증 명령 (정본):**
- 아직 테스트 없음. 첫 `tests/*_auto.gd`를 추가하면 여기와 `projectb-verify` §1을 **동시에** 갱신한다.
- 테스트는 **Bash 툴에서** `./Godot_v4.7.1-stable_win64.exe --headless --path . -s res://tests/<파일>` 로 돌린다(PowerShell은 자식 stdout을 안 보여준다).

**커밋 규약:**
- **메시지는 한국어로 쓴다.** (요약 줄 + 필요 시 본문. 트레일러 `Co-Authored-By`·`Claude-Session`은 형식이라 그대로 영어로 붙인다.)
- **요약 줄은 `동사: 내용` 형식.** 접두 동사는 아래 목록에서만 고른다:

  | 접두 | 쓰임 |
  |---|---|
  | `추가:` | 새 기능·파일·에이전트·스킬 |
  | `변경:` | 기존 동작·기획을 바꿈 (예: `변경: 성장 방식을 레벨업 → 장비 강화로`) |
  | `수정:` | 버그 고침 |
  | `삭제:` | 제거 |
  | `문서:` | 문서·주석만 손댐 |
  | `정리:` | 리팩터·포맷 (동작 변화 없음) |

- **한 커밋 = 한 논리 변경.** 성격이 다른 변경(예: 에이전트 추가 + 버그 수정 + 문서 정리)이 워킹 트리에 섞여 있으면 **한 번에 커밋하지 말고 먼저 물어라** — 어떻게 쪼갤지 사용자에게 확인받은 뒤 나눠 커밋한다. `git add -A`로 전부 쓸어담기 전에 `git status`로 무엇이 섞였는지 본다.

**변경 이력:**
| 날짜 | 변경 내용 | 대상 | 사유 |
|------|----------|------|------|
| 2026-07-21 | 탁본 하네스를 Project_B용으로 이식 (에이전트 9종 `takbon-*`→`projectb-*`, 스킬 `takbon-rules/verify`→`projectb-rules/verify` 재작성, Godot 4.6.1→4.7.1) | 전체 | 탁본 `.claude` 복사본을 신규 2D 프로젝트에 맞춰 일반화. 게임 고유 사실은 걷어내고 보편 규율만 유지 |
| 2026-07-21 | 기획 담당 `projectb-planner` + 진실원 문서 `docs/GDD.md` 신설, GDD 수정 승인 게이트(settings.json `permissions.ask`) 추가 | agents/projectb-planner.md · docs/GDD.md · .claude/settings.json | 하나의 진실원 기획 문서로 개발하고, 그 문서 수정은 사용자 승인을 받도록 |
| 2026-07-21 | 프로젝트 정체를 웹 게임(Web/HTML5 익스포트)으로 확정, 네트워크 리뷰 상시 필수 규칙 추가 | CLAUDE.md · projectb-rules · projectb-reviewer | 웹 게임이라 네트워크가 코어 — 리뷰에서 WebSocket·권한·검증을 매번 확인 |
| 2026-07-21 | "비주얼은 스프라이트 기본, 도형으로 때우지 마라" 규약 추가 | projectb-rules §0 · projectb-dev · projectb-reviewer | 임시라도 스프라이트(텍스처)로 만들어야 나중에 이미지 교체가 쉬움 |
| 2026-07-21 | 기획 검증 에이전트 `projectb-critic` + `projectb-plancheck` 스킬(7 정합성 렌즈) 신설 | agents/projectb-critic.md · skills/projectb-plancheck | planner가 만든 기획을 적대적으로 검증(생성-검증 짝). 모순·안 닫히는 루프·비현실적 범위를 잡되 GDD는 안 고침 — 수정은 planner 승인제로 |
| 2026-07-21 | 커밋 규약 신설 — 한국어 메시지, 요약 줄 `동사: 내용` 형식(추가/변경/수정/삭제/문서/정리), 한 커밋=한 논리 변경(섞이면 먼저 질문) | CLAUDE.md 커밋 규약 절 | 커밋 언어·형식·단위를 고정해 이력을 읽기 쉽게, 뒤섞인 커밋 방지 |
