---
name: projectb-verify
description: Project_B(2D Godot) 프로젝트의 검증 규율. Godot 헤드리스 테스트를 돌리거나, 손댄 코드가 실제로 도는지 확인하거나, "테스트는 그린인데 게임이 안 된다"를 만났을 때 반드시 이 스킬을 읽어라. 헤드리스가 못 잡는 것(클릭 도달·렌더·시간 경과)·`-s` 스크립트의 침묵 통과·뮤테이션으로 검출력 증명·`push_input`으로 실게임 확인·전체 테스트 스위트 명령을 담는다. 초록불을 근거로 쓰기 전에 이 스킬을 먼저 본다.
---

# Project_B 검증 규율

이 규율의 한 문장 = **"테스트가 그린이다"는 "동작한다"가 아니다.** 헤드리스 테스트는 로직 계약은 잘 잡지만 클릭 도달·렌더·시간 경과는 구조적으로 못 잡는다. 초록불을 "동작 확인"의 근거로 쓰기 전에 아래를 통과했는지 봐라.

## 0. 원칙 한 줄

> **사용자가 "안 된다"고 하면 초록불보다 사용자가 옳다.** 검증이 어떤 계층을 건너뛰었을 가능성을 먼저 의심해라 (특히 발사·클릭 같은 입력 경로는 Control 계층을 우회한 검증이 흔히 거짓 초록불을 낸다).

## 1. 전체 테스트 스위트 (반드시 Bash에서)

PowerShell은 자식 프로세스 stdout을 안 보여준다 — **테스트는 Bash 툴로 돌려라.** 실행 파일은 프로젝트 루트의 `Godot_v4.7.1-stable_win64.exe`다.

```bash
# CombatMath 단위 (사거리·쿨다운·구르기·잔몹 타격 반경·부채꼴·화살 발사율/원점/명중반경/사거리 clamp + 차지 발사(레벨 clamp·홀드→레벨·위력/반경 배율·폭발 판정·차지 시간 검증·탄속 clamp·터널링 불변식) + 장비 스탯 total_stats/equip_stat_at_level/upgraded_stats/upgrade_cost·calc_damage 보너스 + **성장축 5스탯**(level_stats 메인/서브 합산·clamp_level_stats 경계·confirm_damage 곱 순서·반올림 1회·치명 경계·leech_gain 오버킬·haste_scale/effective_cooldown + 검증 3함수 haste 버전·**스윙 창 계약 데이터 전수**·SAME_SWING 퇴화 트립와이어·effective_move_speed·level_for_exp/exp_progress) + **하위 직업 특성**(effective_attack_range 항등/+30%/상한 clamp/음수/INF · 기하 3함수가 같은 확장 사거리에서 파생되는지 = "맞는 곳=보이는 곳" · 적 body_radius 조합 · **특성 카탈로그 clamp_trait(s)** 상한/음수/INF/모르는 키/빠진 키 · **구르기 파생** effective_roll_cooldown·effective_roll_speed와 is_roll_grant_ok의 특성 게이트 · trait_text 부호 · **외삽 상한 불변식에 roll_dist 포함**) — 신뢰 경계·§3 계약)
./Godot_v4.7.1-stable_win64.exe --headless --path . -s res://tests/test_combat_math_auto.gd

# GameState 리졸버·인벤/제작/강화/저장 (직업·챕터·재료·장비·레시피 스캔 allowlist + 조작 id 거부 + 제작/강화 전이 + to/from_save_dict 라운드트립·조작 세이브 폐기 + 진행 좌표·HP 이월 + **성장축**(하위 직업 allowlist·계열 공용 풀 add_exp·해금 전이·메인 전환 마을 전용·타 계열 격리·저장 라운드트립·구 세이브 폴백·과대 EXP 만레벨 clamp) + **자리별 특성 리졸브**(traits_of — 메인/서브가 서로 다른 특성을 켜는지 · 계열 불일치/모르는 id/경로 조작 폐기 · 공유는 계열 무관 통과하되 **메인 자리에선 구조적으로 꺼짐**(합성 SubJobDef로 가드를 직접 겨눈다 — 데이터만으로는 검출력 0이었다) · 슬롯 초과분·메인/서브 중복 id 폐기 · 같은 축 합산 후 상한 clamp) + **장착 슬롯**(메인/서브 교체·미보유/중복 거부·메인 전환 시 자리 맞바꿈·장착 기준 5스탯) + 🔴 **슬롯 기준 총 화력 예산 트립와이어**(max_level_stats ≤ GDD §6 목표 — 새 하위 직업이 상위 3위에 들면 빨개진다) + **직업 귀속 뒤처리**(직업 전환 시 남의 무기 해제·가방 잔존·빈 슬롯을 보유분으로 채움 · **범용 장비는 유지**(합성 EquipDef로 겨눔 — 데이터만으론 검출력 0) · **세이브 로드는 비파괴**(로드 시점 직업은 항상 기본값) · apply_job_loadout 경계 · 판 도중 재검증 무시) — 네트워크/저장 신뢰 경계)
#   ⚠ 로그의 `ERROR: [GameState] 판 도중 직업 귀속 재검증 시도` 2줄은 **의도된 것**(가드를 직접 겨누는 케이스)
./Godot_v4.7.1-stable_win64.exe --headless --path . -s res://tests/test_game_state_auto.gd

# HealthComponent (HP·부활 타이머 권한/표시 경로 격리 — 게스트 자가 부활 금지)
./Godot_v4.7.1-stable_win64.exe --headless --path . -s res://tests/test_health_component_auto.gd

# 전송 계층 계약 (P2P 직결, 2026-07-26) — 소켓 없이 상수/스키마만 본다.
#   fast(유실 허용) 채널 분류 = {G_POS, G_MOB_POS} 정확 일치 + **사건 kind 22종 제외 단정**(하나라도 끼면 빨개진다)
#   + ping/pong이 fast에 없음(측정 채널 = 예고 채널, §3) + **G_* kind 값 유일성 전수**(rules §5 "nping" 사고 자동 방지)
#   + keepalive 주기 부등식(서버 IDLE_LIMIT_MS/SEEN_WRITE_MS의 JS 미러 — 릴레이 유휴 절단 방지) + 워치독/채널 id 정합
# ⚠ 이 테스트는 **협상·폴백·지연을 검증하지 않는다** — WebRTC는 웹 전용이라 네이티브에서 코드가 한 줄도 안 돈다(§2).
./Godot_v4.7.1-stable_win64.exe --headless --path . -s res://tests/test_net_transport_auto.gd

# SaveManager 커밋/롤백 (스테이지 클리어=commit·전멸=reload 롤백 → 클리어분 생존·전멸분 소실·무파일 첫 판 전멸 + **EXP/레벨도 같은 롤백 규칙**·`SAVE_VERSION == 1` 트립와이어 — GDD §11·§6 저장 계약)
#   ⚠ save_path를 임시 경로로 격리해 실제 user://save.json을 안 건드린다. GameState는 game_state_override로 주입(트리 밖 -s, rules §5)
./Godot_v4.7.1-stable_win64.exe --headless --path . -s res://tests/test_save_manager_auto.gd

# 배경 드레싱 (바닥 변주·디테일 스캐터·흔들리는 폴리지 — 2026-07-26). 표시 전용인데 테스트가 있는 이유 =
#   결함이 **에러를 안 낸다**: 폴리지 회전 피벗이 밑동이 아니면 풀이 공중에서 빙빙 돌고(아트가 텍스처를
#   다시 그릴 때마다 재발 가능), 배치가 비결정적이면 호스트·게스트가 다른 지면을 보고, 제외 영역이 안
#   먹으면 스폰 지점에 덤불이 돋아 시야를 가린다. 충돌 경계(layer=0 = 어떤 판정에도 안 잡힌다)도 여기서 고정.
#   ⚠ `_ready`는 **다음 프레임에 돈다** — add_child 직후 자식을 세면 항상 0이다(작성 중 실제로 겪음, `await process_frame`).
./Godot_v4.7.1-stable_win64.exe --headless --path . -s res://tests/test_stage_dressing_auto.gd

# 멀티 방 왕복 (릴레이+호스트+게스트 3프로세스 — 방 생성→참가→ping/pong 왕복 검증)
CODEFILE="<임시경로>/room_code.txt"; rm -f "$CODEFILE"
./Godot_v4.7.1-stable_win64.exe --headless --path . -s res://server/relay/relay_server.gd -- --port=9081 > relay.log 2>&1 &
RELAY_PID=$!
./Godot_v4.7.1-stable_win64.exe --headless --path . -s res://tests/test_net_room_auto.gd -- role=guest "codefile=$CODEFILE" url=ws://localhost:9081 > guest.log 2>&1 &
GUEST_PID=$!
./Godot_v4.7.1-stable_win64.exe --headless --path . -s res://tests/test_net_room_auto.gd -- role=host "codefile=$CODEFILE" url=ws://localhost:9081 > host.log 2>&1
wait $GUEST_PID; kill $RELAY_PID
# 판정: host/guest 로그 둘 다 "TEST_OK" + exit 0. "SCRIPT ERROR"도 같이 grep해라 (§3).
```

새 테스트를 추가하면 위 목록과 `CLAUDE.md`의 「검증 명령」 절을 **동시에** 갱신해라.

**진단 도구(스위트 아님) — 릴레이 왕복 지연 계측 `tests/measure_latency.gd`:** "렉이 있다·게스트만 맞는다" 류 신고가 오면 추측하지 말고 먼저 재라. 게임과 같은 홉(클라A→릴레이→클라B→릴레이→클라A)을 왕복해 RTT 분포 + 그 지연이 깎아먹는 **회피 창 예산**까지 환산해 찍는다. `_auto`가 아니라 스위트에 안 들어간다(외부 네트워크 의존).

```bash
CF=/tmp/lat_code.txt; rm -f $CF
./Godot_v4.7.1-stable_win64.exe --headless --path . -s res://tests/measure_latency.gd -- role=host codefile=$CF url=wss://relay.jachana.com count=40 gap_ms=100 &
HP=$!; sleep 2
./Godot_v4.7.1-stable_win64.exe --headless --path . -s res://tests/measure_latency.gd -- role=guest codefile=$CF url=wss://relay.jachana.com > /dev/null 2>&1 &
wait $HP   # 출력: LATENCY_OK rtt_ms min/p50/p95/max/mean + [budget] 회피 창 환산
```
- `url=ws://localhost:9080`으로 로컬 릴레이를 겨누면 **코드 자체의 오버헤드 하한**(실측 14ms)이 나온다 — 배포 릴레이 값에서 이걸 빼면 순수 네트워크분이다.
- ⚠ **한 번 재고 결론 내지 마라.** 릴레이 왕복은 시점에 따라 140~215ms를 오간다. 변경의 효과를 보려면 **같은 시간대에 A/B를 번갈아** 재라 — 순차 전후 비교는 경로 변동을 개선으로 착각하게 만든다(실제로 겪음, rules §5 DO 배치 항목).

⚠ **이 목록이 정본과 갈라지면**, 이 스킬을 읽은 에이전트가 "전 스위트를 돌렸다"고 믿으면서 절반만 돌린다. 새 테스트를 더하면 목록도 갱신해라 — **목록에서 빠진 테스트는 낡아 죽는다**(문법이 바뀌어도 아무도 안 돌려서 조용히 깨진 채 방치된다).

⚠ **세이브를 건드리는 테스트 주의.** `SaveManager`가 부팅 시 저장을 살리는 구조라면, 저장 관련 시그널을 쏘는 테스트는 실제 `user://save`를 덮어쓴다. 테스트 끝의 정리는 지울 뿐 복구가 아니다 — 플레이하던 세이브가 있으면 날아간다. 새 시그널을 쏘는 테스트를 더할 땐 SaveManager가 물려 있는지 먼저 확인해라.

## 2. 헤드리스가 못 잡는 것 (실게임으로만 확인된다)

### 2-0. 🔴 P2P 직결은 헤드리스가 **한 줄도 안 돈다** (2026-07-26)
`Net._p2p_available()`이 `OS.has_feature("web")`로 막혀 있어 네이티브 `-s` 경로는 릴레이만 탄다. 즉 **스위트 6종 전부 그린이어도 P2P에 대해서는 아무것도 검증되지 않았다** — 회귀 0의 증거일 뿐이다(그게 이 게이트의 목적이기도 하다). 아래는 웹 2클라 실기로만 확인된다:
- **HUD 방 코드 줄에 "직결"이 뜨는가** — 릴레이 폴백도 조용히 잘 돌기 때문에 **핑 숫자만으론 못 읽는다.** 이 표시가 곧 P2P 성공 여부의 유일한 창구다.
- 핑이 실제로 떨어지는가 — ⚠ **한 번 재고 결론 내지 마라**(§1 경고). 릴레이 왕복 자체가 140~215ms를 오간다.
- 🔴 **3분 이상 방을 유지**해 안 끊기는지 (릴레이 유휴 스윕 × 직결 무트래픽, rules §5). **로컬 릴레이엔 유휴 스윕이 없어 `dev_local.sh`로는 영원히 재현 안 된다 — 반드시 배포본에서 4분 이상.**
- 게스트 Wi-Fi를 껐다 켜면 몇 초 안에 릴레이로 복귀하는가(무수신 워치독).
- 손실이 있는 회선(테더링)에서 예고 타이밍 — 깨끗한 랜에선 안 드러난다.

### 2-1. "클릭이 닿는다" — `push_input` + 실게임
🔴🔴 **헤드리스는 마우스가 Control에 닿는지 모른다.** 화면을 덮는 Control(배경 ColorRect·패널 루트·오버레이)의 `mouse_filter`가 기본값 **STOP**이면 그 아래 클릭을 다 먹어 발사·상호작용이 통째로 죽는데, 에러도 경고도 없고 헤드리스 스위트는 그린이다. 렌더가 없어 히트 테스트가 실게임과 달라서, `push_input` 테스트조차 헤드리스에선 그냥 통과한다.

- **화면을 덮는 Control을 새로 깔았으면 `mouse_filter = 2`(IGNORE)를 적었는지 확인하고, 에디터로 띄운 실제 게임에 `viewport.push_input(InputEventMouseButton)`을 밀어 0회→1회를 확인해라.** 액션(InputMap) 주입은 이 버그를 못 잡는다 — Control 히트 테스트를 우회하기 때문.
- 이건 특정 씬만의 얘기가 아니다 — **새 씬·새 오버레이를 만들 때마다 되살아난다.**

### 2-2. "보인다" — MCP 스샷
헤드리스는 "노드가 존재"만 확인하고 "보인다"는 못 본다(z_index·visible·modulate·레이아웃 오류로 안 보여도 통과). **렌더·레이아웃을 건드렸으면 에디터로 띄워 MCP 스샷으로 확인해라.**

### 2-3. 소리가 난다 — 버스 라우팅
헤드리스는 오디오 드라이버가 없어 소리가 실제로 나는지 못 잡는다. `playing==true`·버스 라우팅은 에디터 실게임 exec로 확인.

### 2-4. 시간이 흐른다 — 쿨다운/자원 소모
연사 차단은 실제 발사 경로(`fire()`)를 거쳐야, 시간당 자원 감소는 시간이 실제로 흘러야 드러난다. 테스트가 이를 우회하면 검출력 0 → 실게임 입력·경과로 확인.

## 2-5. 🔴 남의 커밋을 당겨온 뒤 (머지·pull) — "리소스가 실제로 로드되나"

2인 협업이라 **상대 환경에만 존재하는 것**이 머지로 들어온다. 상대는 자기 PC에서 정상이라 이걸 못 보고, **테스트 스위트도 못 잡는다**(스위트는 리소스를 전수 로드하지 않는다). 머지 후 반드시:

- 🔴 **`--export-release`의 `exit 0`을 근거로 쓰지 마라.** 리소스 임포트 실패는 **로그의 ERROR 줄에만** 남고 익스포트는 성공한다(2026-07-26 실제로 통과했다). 익스포트를 돌렸으면 **출력에서 `ERROR`를 grep해라** — 특히 `Failed loading resource` / `referenced non-existent resource`.
- **바뀐 데이터 리소스를 직접 로드해 봐라.** `ResourceLoader.load("res://data/…")`가 null이면 그 def를 쓰는 씬이 통째로 안 뜬다:
  ```gdscript
  # -s 임시 스모크 — 오토로드 없이 돈다
  var d := ResourceLoader.load("res://data/enemies/<새로 온 것>.tres")
  print("LOAD: %s" % ("실패" if d == null else "OK"))
  ```
- 🔴 **익스포트/임포트를 돌린 뒤 `git diff -- '*.import'`를 확인해라.** 임포트가 실패하면 Godot이 그 `.import` 사이드카를 **`valid=false`로 덮어써** 워킹 트리를 오염시킨다 — 상대가 커밋한 **정상 임포트 기록(`path=`·`dest_files`)이 지워진다.** 그걸 모르고 커밋하면 남의 환경에서 멀쩡했던 에셋까지 깨뜨린다(2026-07-26 실제로 `boss_wraith.aseprite.import`가 이렇게 바뀌어 `git checkout`으로 되돌렸다). **내 환경에서 임포트 못 하는 에셋이 있는 채로 빌드했다면 이 확인은 필수다.**
- **상대가 남긴 인수인계·주의목록 파일을 먼저 읽어라**(`b_hyoung/` 등). 임시 축소·미배선 실험물·되돌려야 할 것이 적혀 있다 — 실제로 챕터 칸 수 축소·죽은 보스 템플릿이 그렇게 걸러졌다.
- **양쪽이 겹쳐 건드린 파일**을 확인해라: `comm -12 <(git diff --name-only $BASE origin/master|sort) <(git diff --name-only $BASE HEAD|sort)`. 자동 머지가 됐다고 **의미가 맞는 건 아니다** — 특히 새 네트워크 kind 이름 충돌(§5)·같은 함수의 다른 개정.

## 3. `-s` 스크립트의 침묵 통과

🔴 **`-s` SceneTree 테스트는 런타임 에러가 나도 "OK"를 찍을 수 있다.** 리팩터로 옮겨간 내부 필드를 더듬다 에러로 함수가 **중단**되면, 그 뒤 검증이 안 돌아도 `failures=0`이라 통과로 보인다.

- **grep을 `_OK`만 하지 말고 `SCRIPT ERROR`도 같이 봐라.**
- `_check`가 **실패할 때만 출력**하면 침묵이 곧 통과다 — 함수가 죽어도 조용하다. 성공도 한 줄 찍게 해라.
- **테스트는 공개 API로만 검증해라.** 내부 필드(`_밑줄`)는 리팩터 때 옮겨 다니는 물건이라 계약이 아니다.

## 4. 초록불을 근거로 쓰지 마라 — 뮤테이션으로 검출력 증명

🔴🔴 **고친 코드를 일부러 되돌려 정확히 몇 개가 실패하는지 확인한다.** 규칙을 바꿨으면 규칙을 어긴 입력을 넣어 테스트가 **빨개지는지** 봐라. 안 빨개지면 그 테스트는 그 규칙을 검증하지 않는다(그린이지만 아무것도 안 지키는 테스트다).

## 5. balance 수치를 런타임에 흔들어 검증할 수 없다

🔴 GDScript는 static 함수 안의 `const`로 잡힌 리소스 프로퍼티를 **컴파일 타임에 굳힌다**. 테스트에서 리소스 값을 바꿔도 static 경로는 옛 값을 돌려줄 수 있다(게임엔 무해하지만 테스트는 조용히 거짓 통과). 대신 **두 함수/경로의 경계가 어긋나지 않는지 전 구간을 훑는** 방식으로 검증하고, 그 검증도 뮤테이션으로 검출력을 확인해라.

## 6. 손맛·채점 수치는 헤드리스로 못 검증한다

테스트가 가이드 좌표를 그대로 찍으면 이탈이 0이라 판정 반경을 뭘로 바꾸든 항상 만점이다 — 그린 게 아니라 아무것도 안 잰 것이다. 손맛(이동·판정 반경·기준선·드롭률 체감·피격 손맛 수치)은 **사용자가 마우스로 직접 해 봐야** 정해진다. 리드의 시뮬레이션도 시뮬레이션이다.

## 검증 체크리스트 (손댄 것에 해당하는 줄만)

- [ ] 관련 테스트를 Bash로 돌렸다 — `_OK`와 **`SCRIPT ERROR` 둘 다** grep
- [ ] 규칙/버그 수정이면 **뮤테이션으로 검출력** 확인 (되돌려 빨개지나)
- [ ] 화면 덮는 Control을 깔았으면 `mouse_filter=2` + **실게임 `push_input` 클릭 도달** 확인
- [ ] 렌더/레이아웃을 건드렸으면 **MCP 스샷** 확인
- [ ] 소리/오디오면 실게임 `playing==true` 확인
- [ ] 손맛/채점 수치면 **사용자에게 직접 해 보라고** 넘긴다 (헤드리스로 결론 내지 않는다)
- [ ] 새 테스트를 더했으면 이 스킬 §1의 스위트 목록 + CLAUDE.md도 갱신
- [ ] 🔴 **에셋·데이터를 손댔거나 남의 커밋을 머지했으면** §2-5 — 익스포트 출력에서 `ERROR` grep + 바뀐 `.tres` 직접 로드 (exit 0은 근거가 아니다)
- [ ] 🔴 테스트가 딕셔너리를 **직접 인덱싱**하지 않는지 — `dict["key"]`는 그 키를 만드는 코드를 지우는 뮤테이션에서 SCRIPT ERROR로 테스트를 죽여 **검출력을 0으로 위장**한다(2026-07-25 실제로 겪음). `dict.get("key", 폴백)`으로 읽어라
