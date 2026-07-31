# 미노타우로스 보스 패턴 — 직렬 구축

> **한 작업 = 한 파일.** 끝나면 증류하고 `docs/plans/done/`으로 내린다.
> 설계 정본 = `docs/boss_pattern/`(minotaur_patterns.md = 마스터 P1~P5+돌진 · swing_cone.md = P1 · stele_bind_coop.md = C1).
> ⚠ 정체 전환(망령→미노)은 GDD §5·§11 승인 대기 — 이 문서·데이터는 그 전 단계(오픈소스 프로토타입)다.

---

## 왜

사용자 요청(2026-07-31, 자리 비움): `docs/boss_pattern/`의 패턴들을 **하나씩 직렬로** 구현·검증한다. 요구:
1. 한 패턴씩 만들고 **검증하고** 넘어간다(테스트가 최우선).
2. 애니·idle·오브젝트를 잘 잇고, **바라보는 방향이 의도와 맞는지** 확인.
3. **P 키로 패턴을 순차 순회**해 각 패턴을 조정·발동·테스트 가능하게.
4. **코옵(C1) 파훼는 혼자서도** 양 역할 테스트 가능하게(가짜 파트너).
5. 모든 패턴 후 **사람이 보기 좋은 정리**.
6. 🔴 **오픈소스로만** 만든다 — PixelLab API 금지(사용자가 나중에 API로 정밀화). [[prefer-opensource-before-pixellab]]

---

## 검증 하네스 (완료)

`_mapcheck/boss_debug.tscn` + `boss_debug.gd` — 릴레이/로비 없이 보스 패턴을 발동·조정·검증한다.
- **P** = 다음 패턴 순회 · **Space** = 선택 패턴 발동 · **R** = 재시작 · **H** = 패널 숨김.
- 좌하 패널 슬라이더로 선택 패턴 수치(telegraph_s·range·half_angle·damage·cooldown_s·recover_s) **실시간 조정**.
- `Net.my_id`를 호스트로 강제 → 보스 AI 경로가 돈다. `debug_hold`로 자동공격 정지(버튼으로만 발동).
- 플레이어 무적(보스는 공격하되 데미지 0). 강제 발동도 `_face_dir = _dir_suffix(anchor-pos)`로 **플레이어를 바라본다.**
- 자가 캡처: `-- swcap`(콘) / `-- swcap slam`(원) → 뷰포트 PNG 저장(P패널 자동 숨김 — 보스와 겹침).

---

## 진척 (직렬)

### ✅ P1 — 도끼 후려치기 (`swing` · cone) — **검증 완료**
- 데이터: `wraith_boss.tres` SubResource `pat_swing`(id `swing`, cone, telegraph 0.8, range 120, half_angle 0.7, dmg 10, cd 2.0, recover 0.4, priority 1, use_max_dist 130).
- **예고 = 위험 줄무늬**(swing_cone.md §3 B안): `boss_telegraph.gdshader` 채움을 대각 앰버 빗금으로. 신규 uniform 4개(`stripe_period·stripe_speed·stripe_dark·duty`), 흐름은 `TIME` 등속(임박도 유도 금지 계약 준수). 격자 스냅점 `q`로 도트 블록 계단. **네트워크 안 닿음**(표시 전용).
- 애니: 전용 `swing` 클립이 아직 없어 `slam_<dir>` **플레이스홀더** 재사용(`_resolve_dir_anim`의 swing→slam 폴백). 나중 API로 교체.
- 실기 캡처: apex가 보스에 붙고 부채꼴이 플레이어를 향함(`face=sw`), 빗금 렌더 정상.

### ✅ P2 — 내려찍기 (`slam` · circle) — **검증 완료**
- 데이터: SubResource `pat_slam`(id `slam`, circle, telegraph 1.0, range 110, dmg 14, cd 3.0, recover 0.6, priority 0, use_max_dist 210).
- 실기 캡처: 예고 원이 **플레이어 위에 정확히** 중심. 위험 줄무늬 공유(일관된 위험 신호 언어).

### 🔴 코어 버그 수정 (P1/P2 검증 중 발견) — **모든 보스에 영향**
- **텔레그래프 half-quad 어긋남 수정.** 1×1 쿼드 텍스처의 centered 오프셋(−0.5px 서브픽셀)이 거대 scale(~226)에 곱해져 예고가 회전 방향으로 ~123px 튀었다(콘 apex 좌상단, 원 우하단 — 회전별 반대 방향이 결정적 단서). **2×2 텍스처 + scale=quad/2**(정수 −1px centering)로 교체 → "맞는 곳 = 보이는 곳" 계약 복원. `boss.gd _apply_telegraph_geometry`/`_telegraph_quad_tex` + 셰이더 미러 주석 갱신.
- **`test_boss_data_auto.gd` 방향 인지화.** bare `idle`/`swing`/`slam` 애니를 요구하던 계약이 미노의 방향 애니(`idle_<dir>`·`slam_<dir>`)에서 3건 실패했다. `_resolve_dir_anim`을 미러(`swing→slam_<dir>`·`walk→idle_<dir>` 폴백 포함, 4방향 전수)해 실제 재생 경로를 검증하도록 갱신. **스위트 9/9 그린.**

---

### ✅ P3 — 돌진 + 휘두르기 (신규 상태머신) — **구현·검증 완료 (netreview 통과)**
minotaur_patterns.md §3-1 상태 전이표대로 배선.
- **스키마**(리드): `BossPatternDef`에 `is_charge`·`charge_speed`·`charge_sweep_radius`·`charge_travel_max`·`groggy_s` 추가.
- **상태머신**(`boss.gd`): `State.CHARGE_DASH`·`CHARGE_HIT` 신설. WINDUP 종료 시 `is_charge`면 `_fire_strike` 대신 `_enter_charge_dash`로 분기. DASH = 고정 방향 직진 + 매 프레임 스윕 emit + 바위 충돌 감지(`_dash_rock_collision`, 그룹 `boss_rock`). 바위 박음→CHARGE_HIT(리코일)→`enter_groggy(3s)`+RECOVER. 헛참(travel_max/타임아웃)→짧은 RECOVER. 애니는 placeholder(windup=slam·dash=walk, 전용 클립 나중 API).
- **네트워크**(`EventBus.boss_sweep` + `combat_authority._on_boss_sweep`): DASH 매 프레임 스윕 emit, **dash_seq로 돌진당 플레이어 1회 dedup**(프레임 dedup과 별개), 지연 보상은 boss_strike와 동일 축, i-frame 존중, peer_left 정리.
- **예고**: shape="cone"의 좁은 wedge(range=이동거리 260, half_angle=0.30)를 "경로 예고(긁힘 선)"로 재사용.
- **검증**: 자가 캡처(`-- swcap charge`)로 상태 궤적 확인 — WINDUP(1.1s)→CHARGE_DASH(x 760→565, ~245px/s)→바위 박음→CHARGE_HIT(리코일)→RECOVER+groggy(2.98→). 그로기 순간 PNG = 보스가 바위 옆에 눕는다. 스위트 9/9 그린.
- **netreview 결과(2026-07-31): Critical 0** (과거 3 Critical 방향 전부 회피 — 호스트 자기 포함·새 net kind 없음·권한/신뢰 경계 정상). **Important 2건**(둘 다 배포본 2클라 전용, `docs/TUNING.md §15` E-1·E-2에 등재):
  - E-1: 게스트가 스윕 위험(원 72px)을 예고(경로선 cone)로 다 못 봐 무예고 피격 가능 → half_angle 0.22→0.30로 1차 완화(경로선을 스윕 폭 쪽으로). 완전 해결은 게스트 스윕 링 표시(코드).
  - E-2: `is_strike_hit_lagged`(둘 다 맞아야)가 예고 없는 순간 판정에서 방어자 과우대 → 돌진이 거의 안 맞을 수 있음. 실기 반경 튜닝 필요.
- ⚠ **P4 바위가 아직 없어** 시그니처 분기(바위↔돌진 루프)는 하네스 디버그 바위로만 검증됨. 실제 P4 낙석 바위가 같은 `boss_rock` 그룹+layer 1을 재사용하면 자동으로 물린다.

### ✅ P4 — 낙석 (`spray` + 바위 오브젝트) — **구현·검증·netreview 완료**
`spray`(N점 산포 + N원 텔레그래프)는 boss.gd에 이미 있었음. 신규 = **착탄 후 남는 바위 지형**(P3 돌진이 박을) + 낙하 연출 + 네트워크 동기화. **SwampField를 1:1 미러**:
- **스키마** `BossPatternDef`: `leaves_rock`·`rock_radius`·`rock_ttl`. **네트워크**: `NetSchema.G_ROCK` + `EventBus.rock_spawn_local`. **오브젝트** `src/stage/boss_rock.gd`+`.tscn`(StaticBody2D, 그룹 `boss_rock`+layer 1, Sprite 2프레임, 낙하 연출, `shatter()`, ttl despawn). **매니저** `src/stage/rock_field.gd` → stage_boss.tscn RockField. **데이터** `pat_rockfall`. **아트** `boss_rock.png`(96×48, projectb-art) `--import` 완료.
- **검증**: `-- swcap rock` — 착탄 시 바위 3개(디버그1+낙석2) 스폰·지속, 캡처 확인. P3 돌진이 같은 그룹 박음 = 시그니처 루프 완성. 스위트 9/9.
- **netreview(2026-07-31): Critical 0 · Important 0 · Minor 1.** 미러 정확·불변식 4종 준수·위조 차단 확인. Minor = 미래 burst_count 크게 올리면 릴레이 상한(2048). ⚠ **shatter 미동기화**: 게스트 보스는 lerp라 `move_and_slide` 안 함 → 게스트에선 바위가 안 부서지고 ttl까지 남음(판정 없어 무해, 체감만). 수용 부채 — `docs/TUNING.md §15` E-4 등재. 신경 쓰이면 `G_ROCK_BREAK` 저빈도 kind 추가가 정공법.

### ✅ P5 — 도끼 회전 (`spin` · circle, center_self) — **구현·검증 완료**
신규 = `BossPatternDef.center_self`(circle 중심 = 대상 아닌 **보스 자신** = 전방위 근접). `_resolve_dir_anim`·ATTACK_ANIMS·테스트에 `spin` 추가(placeholder = slam_<dir>). 데이터 `pat_spin`(circle, range 95, min_phase 2).
- **검증**: `-- swcap spin` — 예고 원(위험 줄무늬)이 **보스 중심**에 렌더(플레이어 원 밖). 돌진 스윕(예고 없는 이동 히트박스)과 시각 구분됨. 스위트 9/9.

### ✅ C1 — 영혼 비석 결박 (코옵) — **메커니즘 구현·솔로 검증 완료 · 아트 오픈소스 완성**
CAGE 컨트롤러(`coop_authority.gd`)를 `MECH_STELE`로 확장(stele_bind_coop.md §6-4). GDD 충돌은 사용자("솔로 안 해도 돼")로 해소.
- **두 게이지 맞물림**: 비석 내구도(B가 타격 −6/타, A 버티면 자연회복 +10/s 정지) + A 저항(−6/s, 버티면 −3/s). 내구도 0 = 성공(보스 `enter_groggy(3s)` = 공동 딜) · 저항 0 = 실패(A HP −40%, 즉사 아님).
- **오브젝트**: 영혼 비석(soul_stele, hframes 5: idle→break) + 붉은 결박선(Line2D). 새 필드/상수/입력(A 연타·B 근접 타격)·저항 바 UI.
- **배선**: `stage_boss.tscn`에 CoopAuthority 노드(`stele_only=true` — 실보스는 STELE만, 다른 5 테스트 메커니즘 제외). 하네스에 TestMode+가짜 파트너(NPC 777) 솔로 테스트.
- **아트(오픈소스, PixelLab 미사용)**: soul_stele·thorn_ring·thorn_shard(projectb-art) + 미노 클립 roar/grab/groggy(`mino_boss_c1.png`, 기존 시트 재조합). 4장 전부 `--import` + 육안 검증 완료.
- **검증(두 역할 솔로 — 설계 "둘다 테스트해볼수있는 상황")**: 하네스에서 **C**=인간 B(비석 부수기)·**V**=인간 A(연타 버티기), NPC가 반대 역할 자동(A=자동 버티기·B=자동 파괴 2/s). `coop_authority.debug_force_stele(victim)`로 지정-victim 발동.
  - 인간 B(`-- swcap stele`): 내구도 94→0·저항 100→85·보스 groggy=2.87 ✓
  - 인간 A(`-- swcap stele va`): NPC-B 자동 파괴로 내구도 100→0·저항 100→75·보스 groggy=2.90 ✓
  - 중간 캡처에 비석·결박선·두 게이지 바·프롬프트·가시 링 렌더 확인. 스위트 9/9.
- ✅ **미노 클립 배선** — boss.gd `play_c1_clip`/`end_c1_clip`(STELE 동안만 `mino_boss_c1_frames.tres`로 시트 임시 교체, `_c1_active`가 눕기 포즈 억제). 발동=roar→0.5s 뒤 grab → 성공=groggy 클립(+3.2s 원복). 검증: 중간 캡처=grab · 성공 캡처=groggy 드로우 포즈.
- ✅ **① 보스 AI 락** — boss.gd `coop_locked`(STELE 중 `_host_ai` 정지 + 페이즈2 늪 정지, 설계 §9). `_apply_resolution`이 양쪽 해제(게스트 정지 버그 방지 — 락 설정은 `_begin`, 해제는 `_apply_resolution`으로 대칭).
- ✅ **② 실패 경로 검증** — `-- swcap stele fail`: 저항 9→0 순간 active→false, **groggy=0**(성공과 구분), 메테오/즉사 없음. A HP −40%.
- ✅ **③ 가시 링 hazard + 파편** — 2.5s마다 비석에서 붉은 가시 링 방출(예고 0.7s→버스트: B 반경 안+비구르기면 −8), 버스트 자리에 파편(3s, B 회수→다음 3타 강타 −18). 중간 캡처에 링 렌더 확인. 아트 = thorn_ring/thorn_shard.
- ✅ **④ 게스트 게이지 동기화(부분)** — `NetSchema.G_COOP_GAUGE`(호스트 ~6Hz 브로드캐스트 → 게스트 게이지 표시). 보스 클립·락은 `_begin`/`_apply_resolution`이 양쪽 실행. G_COOP_IN act(게스트 A연타/B타격 보고) 호스트 처리.
- ✅ **netreview 완료 + Critical 4 + Important 2 전부 수정** (2026-07-31):
  - **C1(게스트 STELE 입력 무시)**: `_on_net_msg` G_COOP_IN에 STELE `act` 라우팅 추가(`from_id==_victim`→mash·else→hit). **이전엔 게스트 A/B 입력이 통째로 드롭돼 2인 STELE 성립 불가**였다(호스트 화면에서만 동작 — 교과서적 결함). 이제 라우팅됨.
  - **C2(B 근접 무검증)**: 호스트가 hit 보고 시 `from_id.net_anchor().distance_to(_stele_pos) <= RESCUE_RADIUS` 재검증(게스트 클라 게이트 신뢰 안 함).
  - **C3(가시 링 무예고 피격)**: `NetSchema.G_THORN`(호스트→전원 링/파편 스폰 브로드캐스트, G_MOB_ATK 예고 규약 미러). 판정=호스트만(`_thorn_judge`), 표시=양쪽(`_spawn_thorn_visual`). 게스트가 링을 보고 피할 수 있다.
  - **C4(원격 구르기 i-frame)**: `_roll_grant_msec`(G_ROLL 수신 추적) + `_b_rolling`이 `CombatMath.is_iframe_active`로 원격 구르기 존중.
  - **Imp1(peer_left 보스 락 stuck)**: `_on_peer_left`가 STELE 활성 중 이탈 시 강제 종료(양쪽 보스 락 해제).
  - **Imp2(릴레이 로그)**: relay-worker `index.js`에 `cgauge` 로그 제외 추가(미러).
  - ⚠ **2인 경로는 코드 수정·솔로 회귀만 검증**(스위트 9/9, `-- swcap stele` 성공 유지) — **게스트 A/B 실제 성립·링 렌더·원격 회피는 배포본 2클라 실기 필요**(netreview: "호스트로만 테스트하면 C1이 절대 안 드러난다"). `docs/TUNING.md` 실기 목록 후보.
  - Minor(미수정): `_stele_input`이 KEY_J/SPACE도 소비 — B가 비석 근처서 공격/구르기 키가 삼켜지는지 실기 확인.

## 🔴 남은 것
- C1 follow-up 4종(위) — 특히 게스트 동기화(netreview)와 미노 클립 배선.

---

## 검증 (무엇을 테스트했나)

- `bash scripts/run_tests.sh` → **9/9 그린**(parse-glue 10파일 · boss_data가 방향 애니 + 돌진/낙석 파라미터 계약까지 검증).
- 자가 캡처 5회(`-- swcap` + slam/charge/rock/spin): P1 콘 apex·줄무늬 · P2 원 플레이어 중심 · P3 상태 궤적(WINDUP→DASH→바위 박음→그로기) · P4 바위 3개 스폰·지속 · P5 원 보스 중심. 전부 육안 확인.
- netreview 2건(P3 스윕·P4 G_ROCK): **Critical 0.** 실기 항목은 `docs/TUNING.md §15`.
- ⚠ **실기 미확인:** 웹 빌드·2인 지연·손맛은 `docs/TUNING.md §13·§15` 계열. 헤드리스가 못 잡는 축. **애니는 전부 placeholder**(slam/walk 재사용) — 전용 클립은 사용자 API 정밀화 대상.

## 미커밋
워킹 트리에 이번 변경 전부 미커밋(P1~P5 + 코어 텔레그래프 수정 + 바위 오브젝트/네트워크 + 아트 + docs). 사용자 = "다 만들고 커밋"(C1 포함 여부는 사용자 결정). 규약: 한국어 `동사: 내용`.
