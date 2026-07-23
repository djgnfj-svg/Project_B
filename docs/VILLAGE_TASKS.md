# 마을(E안) 제작 작업리스트 — 실행 전용

> **설계도 = `docs/mockups/village_mockup_e.html`** (렌더 스냅샷: `docs/mockups/_shot_e.png`).
> 이 파일은 마을 제작의 **실행 체크리스트**다 — 배치 하나가 끝날 때마다 상태를 갱신한다.
> 결정 배경·규칙은 `docs/WORKLIST.md`, 아키텍처는 `projectb-rules` 참조.

## 공통 규격

- 저장 (2026-07-23 재구성 — 폴더별 정리, 파일명의 `village_` 접두사 제거):
  - PNG = `assets/sprites/village/{ground,nature,buildings,props,npc}/` — ground 바닥·데칼 / nature 자연물 / buildings 건물 / props 소품 / npc NPC
  - 원본 = `assets/aseprite/village/` (NPC 원본은 `npc_` 접두사 유지)
  - `a/b/c` 접미사 = **변형(variant)** — 같은 스프라이트 반복 배치 금지 규칙용 실루엣 변형
- 바닥/타일 = 외곽선 없이 면. 오브젝트/자연물/NPC = 진한 외곽선 `#33372f`
- 배경 투명 (베이크드 바닥 제외) · 32px 그리드 정합
- 🔴 자연물은 변형 2~3종 필수 (배치 시 flip_h·스케일 지터는 씬에서)
- 검수: 확대본을 Read로 눈 확인 (projectb-art 규율)

## 공통 팔레트 (목업 PAL — 이 값에서 시작, 미세 조정 허용)

| 용도 | 색 |
|---|---|
| 잔디 | `#9cc36d` 기본 · `#88ab5a` 어둠 · `#b8d488` 밝은 얼룩 · `#6f9648` 풀포기 |
| 흙길 | `#cbb178` · `#b3985e` |
| 물 | `#4aa8d8` · `#7cc8e8` 반짝 · `#3a8cba` 깊음 · `#d8eef8` 포말 |
| 기슭 돌 | `#5c6a76` · `#78899a` 밝음 · `#4a5560` 어둠 |
| 나무 목재 | `#a87c4f` · `#c99b62` 밝음 · `#8a5f3a` 어둠 · 기둥 `#7a5535` |
| 잎 톤 3세트 | 기본 `#4e7c52/#639664/#7cae74` · 짙음 `#456f49/#578a5c/#6fa468` · 노란기 `#55804a/#6f9e59/#8cba68` |
| 벚꽃 | `#c9829e` · `#e8a8c0` · `#f5cddd` |
| 제작소 | 슬레이트 `#5a6270/#434a56/#707a88` · 벽 `#d9c091/#b89e6e` · 화덕 발광 `#f08030/#ffc860` |
| 강화소 | 벽 `#f2eee2/#d5cdbc` · 지붕 `#3f6fb5/#2d5490/#5b8fd0` · 유리 `#bfe4f5` · 액체 `#4aa8e8` · 브라스 `#c9973f` · 보일러 `#3a3f45` |
| 돌 | `#aeb6b8/#cfd6d6/#7e8688` |
| 외곽선 | `#33372f` · 피부 `#f2c793` |

## 배치 진행 상태

### 배치 A — 바닥 베이크 + 강 ✅ (2026-07-23 완료)
- [x] 잔디 타일 3변형 (`village_grass_a/b/c.png`, 32x32)
- [x] 흙길 데칼 2종 + 흙 얼룩 (`village_path_a/b.png` 48x36급, `village_dirt_spot.png`)
- [x] 밝은 풀 얼룩 데칼 2종 (`village_grasspatch_a/b.png` 64x48급)
- [x] **베이크드 바닥 1장** (`village_ground.png`, 640x384) — 강 북안 y≈294~314 사인 곡선, 다리 구간(x 278~304) 기슭 돌 갭, 강물 위 흙길 없음(다리 스프라이트가 덮음)
- [x] 바위 기슭 돌 단품 3변형 (`village_bankrock_a/b/c.png`)

### 배치 B — 자연물 ✅ (2026-07-23 완료)
- [x] 활엽수 3변형 (`village_tree_a/b/c.png` — a 둥근 대칭·b 옆퍼짐 비대칭·c 길쭉, 잎 톤 3세트 각각)
- [x] 침엽수 2변형 (`village_pine_a/b.png` — a 곧은 4단·b 기울고 불규칙)
- [x] 벚꽃나무 2변형 (`village_blossom_a/b.png`) + 꽃잎 데칼 (`village_petal.png` — 바닥 데칼라 외곽선 생략)
- [x] 덤불 2변형 (`village_bush_a/b.png`) + 자갈 2종 (`village_pebble_a/b.png`)

### 배치 C — 제작소 ✅ (2026-07-23 완료)
- [x] 본채 (`village_forge_house.png`, 96x88 — 슬레이트 지붕·돌 굴뚝·따뜻한 창·문)
- [x] 화덕 셰드 (`village_forge_shed.png`, 48x64 — 발광 화구 포함, 왼쪽 여백 0)
- [x] 연기 퍼프 3프레임 (`village_smoke.png` 72x24 가로 스트립, 외곽선 없음)
- [x] 모루+받침 (`village_anvil.png` 28x22) · 잉걸불 통 (`village_ember_barrel.png` 16x18) · 무기 진열대 (`village_weapon_rack.png` 32x24)

### 배치 D — 강화소 ✅ (2026-07-23 완료)
- [x] 본채 (`village_enhance_house.png`, 112x88 — 흰 벽·파란 기와 지붕·흰 박공 도머+창·파란 아치 문·노란 불빛 창 2)
- [x] 강화 실린더+보일러 (`village_enhance_machine.png`, 64x64 — 브라스 캡/꼭지/받침 + 유리 실린더 발광 액체·기포 + 검은 보일러 리벳·배기관·파란 게이지, 파이프 연결)
- [x] "준비중" 팻말 (`village_sign_wip.png`, 24x20 — 글자 6x9px, 자모 사이 공백 행으로 판독 확보)

### 배치 E — 창고·구조물 ✅ (2026-07-23 완료)
- [x] 대형 궤짝 (`village_chest_big.png`, 64x48) + 상자 3변형 (`village_crate_a/b/c.png`, 16px)
- [x] 나무다리 (`village_bridge.png`, 48x96 세로) + 낚시 데크 (`village_dock.png`, 32x56) + 통 (`village_barrel.png`, 14x16) + 양동이 (`village_bucket.png`, 10x10)
- [x] 텃밭 (`village_garden.png`, 64x44) + 돌계단 (`village_stairs.png`, 48x48)
- [x] 유적 담장 돌 3변형 (`village_ruin_a/b/c.png`, 16x12) + 우체통 (`village_postbox.png`, 10x16)

### 배치 F — NPC 7종 ✅ (2026-07-23 완료, 담당: projectb-art, 16x16 캐릭터 규격)
- [x] 촌장 (`npc/elder.png` 16x16 — 흰 수염·갈색 로브·지팡이 우측 파지)
- [x] 대장장이 (`npc/smith.png` 16x16 — 넓은 어깨·민소매·앞치마·바닥에 세운 슬레지해머)
- [x] 강화술사 (`npc/enchanter.png` 16x16 — 이마 고글 밴드(브라스+유리 렌즈)·파란 작업복·호리호리 실루엣)
- [x] 창고지기 상자 퍼리 (`npc/keeper.png` 16x16 — 상자 몸통·분홍 속귀·점눈·볼터치·짧은 발)
- [x] 낚시꾼 (`npc/fisher.png` 24x16 — 앉은 자세·밀짚모자·대각 낚싯대, 찌 `npc/bobber.png` 4x4)
- [x] 문지기 (`npc/guard.png` 16x20 — 회색 경갑·세로 창)
- [x] 토끼 (`npc/rabbit.png` 12x12 — 흰 몸·긴 귀·점눈·측면 꼬리 범프)

### 배치 G — Godot 배선 ✅ (2026-07-23 완료, 리드 직접)
- [x] village.tscn 재구성 — village_ground(z=-10) + 오브젝트 49노드 배치 + 기존 컴포넌트(PeerSync·SceneFlow·HUD·Gate) 유지, spawn_base (80,190)
- [x] 충돌: 강 좌/우(다리 구간 268~324 갭)·제작소·강화소·궤짝·텃밭·모닥불·경계 4벽 (StaticBody2D layer 1)
- [x] NPC 8종 배치 (표시 전용 Sprite2D)
- [x] 카메라 = `src/temp/camera_test.gd` (TEMP, 씬 미연결 — 폴더째 삭제 가능)
- [x] 검증: 헤드리스 4종 그린 + **에디터 실기(godot MCP 입력 주입)** — 걷기·강 충돌 차단·다리 건너기·게이트 F 출발(stage_idx -1→0) 전부 통과
- ⚠ 참고: 남쪽 둔치는 하단 벽(y358)으로 접근 차단 — 고정 카메라(640x360)에선 화면 밖 영역이라 의도. 카메라 도입 시 해제 검토

## 진행 로그

| 일시 | 배치 | 결과 |
|---|---|---|
| 2026-07-23 01:40 | A 바닥 | ✅ 12종 완료 (베이크드 바닥 640x384 + 타일·데칼·기슭돌). 검수 통과 — 강 곡선·길 흐름 목업 재현 |
| 2026-07-23 01:52 | C 제작소 | ✅ 6종 완료 (본채·화덕 셰드·연기 3프레임·모루·잉걸불 통·무기 진열대). 검수 통과 — 발광 화구·굴뚝·슬레이트로 "대장간" 판독. 무기 진열대는 v3에서 판벽 추가+도끼 가독성 수정 |
| 2026-07-23 | D 강화소 | ✅ 3종 완료 (본채 112x88·실린더+보일러 64x64·준비중 팻말 24x20). 검수 통과 — 제작소와 나란한 몬타주에서 흰벽+파란지붕 대비·실린더 발광으로 "강화소" 판독. 팻말은 v3에서 자모 사이 공백 행 추가로 "준비중" 판독 확보 (몬타주: `build/_review_batch_d_x2.png`) |
| 2026-07-23 | F NPC | ✅ 8파일 완료 (촌장·대장장이·강화술사·창고지기·낚시꾼+찌·문지기·토끼). 검수 2회전 — 워리어 16px 규격(큰 머리·점눈 6/9열·피부 `#f2c793`·명암 2단) 준수, 외곽선은 마을 규격 `#33372f`. v2에서 대장장이 망치 내부 3px 확대(검은 덩어리 오독)·토끼 꼬리 음영 추가. 원본 `assets/aseprite/npc_*.aseprite` (몬타주: `build/_review_batch_f_x6.png`, 워리어 나란히) |
| 2026-07-23 | E 창고·구조물 | ✅ 14종 완료 (궤짝 64x48·상자 3·다리 48x96·데크 32x56·통·양동이·텃밭 64x44·계단 48x48·유적 3·우체통). 검수 3회전 통과 — 궤짝은 아치 뚜껑+철 밴드 2+브라스 자물쇠로 "창고" 존재감, 다리는 물 60px 밴드 몬타주로 도하 길이 확인. v2에서 데크 세로판자(테이블 오독)→가로판자+말뚝 모서리 이동, 텃밭 관목 잎 캡+돔/쌍엽 2종화, 유적 c 묘비 오독→대각 파단면 (몬타주: `build/_review_batch_e_x3.png`) |
| 2026-07-23 02:30 | G 배선 | ✅ village.tscn 전면 재구성 + 실기 검증(에디터 MCP: 이동·강 충돌·다리 도하·게이트 F 출발) + 헤드리스 4종 그린 + **workers.dev 재배포 완료** (`https://projectb-game.youqlrqod.workers.dev`) |
