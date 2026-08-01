# 마을 숲 아트 — 전량 재생산 (PixelLab + Aseprite)

> 착수 = 다음 세션. 계획 작성 = 2026-07-31.
> 선행 작업(마을 백지화 + 첫 TileMapLayer)은 끝났다 — `docs/CHANGELOG.md` 2026-07-31 항목.

## 왜

마을을 숲으로 백지화했지만 **바닥만 있다.** 나무·풀이 0개고, 기능 표지 3개는 버려진 옛 마을 아트(모루·대장간 문·훈련소 간판)를 임시로 꽂아 둔 상태다.

그리고 첫 타일셋이 실기에서 **"자글자글"** 하다는 신고를 받았다(사용자, 07-31). 원인은 둘이다:

1. **32×32 타일에 디테일 과다.** 캐릭터가 32px인데 타일 한 칸에 잔디 날·조약돌·꽃이 전부 박혀 있다. PixelLab 생성 시 `detail`/`shading`을 지정하지 않아 기본값(중간)으로 뽑혔다.
2. **팔레트가 안 묶여 있다.** 자동 생성물은 장마다 색을 제각각 쓴다. 이 프로젝트는 원래 **20색 이하**를 지향했다(팔레트 실측 기록: 126/142장이 20색 이하였고 `boss_arena` 한 장만 예외였다).

🔴 **웹 검색으로 확인한 핵심 원칙(자글자글의 정답):** *"모든 디테일을 렌더하지 말고, 단순한 텍스처로 복잡함을 **암시**하라."* 그리고 *"제한된 팔레트 + 미세한 명도 차"* 로 표면을 표현한다. 즉 잔디는 초록 3~4단계 명도로 충분하고, 날을 하나하나 그리면 그게 노이즈가 된다.

## 톤 (사용자 확정)

**밝고 아기자기.** 참조 = **세피리아(Sephiria)** — 팀 호레이(던그리드 개발사)의 탑다운 코옵 액션 로그라이트. 귀여운 픽셀 그래픽, 탑 꼭대기 마을이 허브. Project_B와 장르가 거의 겹친다(탑다운 · 코옵 · 마을 거점 · 픽셀아트).

## 무엇 (범위)

| # | 대상 | 규격 | 도구 |
|---|---|---|---|
| ① | 숲 바닥 타일셋 **재생성** | 32px · Wang 16타일 | `create_topdown_tileset` |
| ② | 기능 표지 3종 — 제작대 · 훈련소 · 게이트 | 아래 좌표·크기 절 참조 | `create_map_object` 또는 `create_1_direction_object` |
| ③ | 장식 — 나무 2~3종 · 덤불 · 풀 · 꽃 · 바위 | 32~64px | `create_1_direction_object` (후보 여러 장 → 골라 씀) |
| ④ | **팔레트 통일** — 전 에셋을 한 팔레트로 | ≤20색 목표 | Aseprite MCP |
| ⑤ | 씬 배치 + 스캐터 배선 | — | 리드 |

**비범위:** 스테이지·보스방 아트(마을만) · NPC(기능이 없다 — 넣으려면 기획부터) · GDD 변경 · 캐릭터/무기 스프라이트.

⚠ **기존 오브젝트는 전부 버린다** (사용자 확정 07-31). 지금 남아 있는 4장(`gate_48`·`anvil`·`craft_station`·`train_station`)도 **기능은 유지하되 이미지는 새로 뽑는다.**

## 어떻게

### 1) PixelLab 생성 파라미터 — 자글자글을 막는 설정

**바닥 타일셋:**
```
create_topdown_tileset(
  lower_description = "packed dirt path, smooth soil, few pebbles",
  upper_description = "soft green grass, gentle tufts",   # ← 꽃·잡초를 넣지 마라
  transition_description = "soft grass edge fading into dirt",
  tile_size = 32, view = "high top-down",
  detail = "low detail",          # 🔴 이게 핵심
  shading = "flat shading",       # 🔴 명도 단계를 줄인다
  outline = "selective outline",
)
```
- 🔴 **`detail = "low detail"` + `shading = "flat shading"` 이 두 개가 자글자글의 직접 처방이다.** 지금 것은 둘 다 미지정으로 뽑혔다.
- 🔴 **upper 설명에 꽃·이끼·야생화를 넣지 마라.** 지금 타일셋 설명이 `"lush green forest grass, vibrant moss and small forest wildflowers"` 였고, 그 단어들이 그대로 노이즈가 됐다. 꽃은 **바닥 타일이 아니라 별도 스캐터 오브젝트**로 뿌린다(그래야 밀도를 조절할 수 있다).

**오브젝트(표지·장식):**
```
create_map_object(
  description = "...", width = N, height = N,
  view = "high top-down",
  detail = "low detail", shading = "basic shading",
  outline = "single color outline",
)
```
- ⚠ **`create_map_object` 결과는 8시간 뒤 자동 삭제된다** — 받으면 곧바로 `assets/`에 저장해라.
- `create_1_direction_object`는 크기에 따라 후보를 **4/16/64장** 주고 `review` 상태로 둔다 → `get_object`로 눈으로 보고 `select_object_frames`로 고른다. **장식처럼 "여러 변주가 필요한 것"에 이쪽이 맞다.**
- 스타일을 묶으려면 `style_images`(≤256px base64)에 먼저 확정한 에셋을 넘긴다.

### 2) Aseprite 후처리 — 진짜 일은 여기다

자동 생성물이 "따로 노는" 것은 대부분 이 단계를 건너뛰어서다.

1. 가장 마음에 드는 에셋 1장에서 `extract_palette` → 그것을 **마스터 팔레트**로 삼는다(≤20색으로 손질).
2. 전 에셋에 `quantize_to_palette`로 그 팔레트를 강제한다.
3. `get_color_stats`로 장별 색 수를 실측해 남은 이상치를 잡는다.
4. 아웃라인 통일 — `outline_cel` / `outline_native`.

### 3) 배치 원칙 (검색으로 확인한 것)

- **바닥 경계가 읽혀야 한다** — 길·잔디가 명확히 구분되게. 경계가 흐리면 어디를 걷는지 모른다.
- **레이어 분리** — 장식이 이동 명료성을 해치면 장식을 조정한다(충돌은 장식과 별개로 둔다). 이 프로젝트는 이미 z 배치표로 이걸 강제한다(아래).
- **랜드마크 주변은 비운다** — 기능 3곳 근처에 장식을 밀집시키지 마라. 상호작용 영역(60×60)이 시각적으로 가려지면 "F가 안 먹는다"로 신고된다.
- **가장자리에 나무를 밀집**시켜 시선을 안쪽으로 모은다. 맵 경계(벽 충돌체)와 시각적 경계가 일치해야 "보이는데 못 간다"가 안 생긴다.
- **실루엣 일관성** — 같은 종류(나무끼리)는 비슷한 덩어리 실루엣을 유지한다.

### 4) 프로젝트 제약 — 반드시 지킬 것

- **규격:** 캐릭터 **32px** · 카메라 zoom **1.0** · 타일 **32×32**. 정본 = `projectb-art` 에이전트 파일(⚠ 그 안의 「16px 세대」 절은 옛 기록이니 거기서 수치를 가져오지 마라).
- **맵:** 960×576 = **30×18셀**. `village.gd`의 `MAP_RECT`와 미러 — 맵을 넓히면 그 상수도 같이 늘려야 카메라가 새 영역을 보여준다.
- **z 배치표** (rules §5 — 어기면 조용히 가려진다):

  | z | 층 |
  |---|---|
  | -10 | 바닥 타일(`TileMapLayer`) |
  | -9 | 바닥 디테일 스캐터(`ground_detail`) |
  | -3 | 흔들리는 폴리지(`foliage`) |
  | -2 | 접지 그림자 |
  | 0+ | 몸 · 무기 · FX |

- **에셋 경로:** `assets/sprites/village/…` · 타일셋 리소스 `assets/tilesets/…`
- 🔴 **`.aseprite`를 게임 리소스로 참조하지 마라** (rules §4·§5). 그 임포터는 Aseprite 실행 경로를 EditorSettings(로컬·커밋 불가)에서 읽어 **만든 사람 PC에서만 동작**한다 — 2026-07-26에 챕터1 보스전을 통째로 로드 실패시킨 사고의 원인이다. 게임은 `.png`/`.tres`만 본다.
- **스캐터는 이미 있다 — 새로 짜지 마라.** `src/stage/ground_detail.gd`·`foliage_field.gd`·`ground_variant.gd`가 `area`/`textures`/`count`/`rng_seed`/`exclude`를 받는다. 마을에 붙일 때 **텍스처만** 숲용으로 바꾸면 된다(`stage_1.tscn`이 사용 예시).

### 5) 기능 3곳 — 좌표·현재 크기

| 기능 | 노드 좌표 | 현재 표지 | 상호작용 영역 |
|---|---|---|---|
| 제작대 (제작/강화) | (138, 165) | `anvil.png` 28×22 | 60×60 |
| 훈련소 (하위 직업) | (700, 380) | `craft_station.png` 32×32 | 60×60 |
| 출발 게이트 | (882, 270) | `gate_48.png` 48×48 | 60×66 |
| (스폰) | (120, 285) | — | — |

- 발밑 원점 규약: `centered = false`, `offset = (-w/2, -h)`.
- ⚠ 훈련소는 `village.gd`의 `_apply_train_texture()`가 `res://assets/sprites/village/train_station.png`를 **런타임 로드**하고 offset을 자동 유도한다 — 그 경로에 새 PNG를 놓으면 씬을 안 고쳐도 바뀐다.
- ⚠ 크기를 키우면 상호작용 영역(`shape_craft`/`shape_train`/`shape_gate`)과 어긋나는지 본다. 표지가 영역보다 훨씬 크면 "그림 위에 섰는데 F가 안 뜬다"가 된다.

### 6) 타일셋 → Godot 변환

이미 만들어 둔 도구를 쓴다(재실행 가능):
```bash
./Godot_v4.7.1-stable_win64.exe --headless --path . -s res://scripts/gen_tileset.gd -- \
  --meta=res://assets/sprites/village/ground/forest_tiles_meta.json \
  --tex=res://assets/sprites/village/ground/forest_tiles.png \
  --out=res://assets/tilesets/forest_village.tres \
  --lower=흙길 --upper=숲잔디
```
- 🔴 **`mode = TERRAIN_MODE_MATCH_CORNERS(1)`이다.** PixelLab 공식 문서의 컨버터는 `0`(CORNERS_AND_SIDES)을 쓰는데, Wang 16타일 셋에는 코너 정보밖에 없어 **오토타일이 에러 없이 안 붙는다.** `gen_tileset.gd`가 이미 1로 쓴다 — 직접 .tres를 쓰지 말고 이 도구를 써라.
- 🔴 **시트 좌표는 메타데이터의 `bounding_box`에서만 유도한다.** `wang_N`의 N은 코너 비트값이고 `original_position`은 생성 격자 좌표다.
- 바닥 시드 레이아웃은 `scripts/gen_village_ground.gd` → `build/village_ground_data.txt`의 한 줄을 `village.tscn`의 Ground 블록에 붙인다(기존 `tile_map_data` 줄을 갈아끼운다).
- 다듬기는 에디터 **Terrains 탭 + Rect Tool(R)** — 코너 모드에서 Paint Tool(D)은 안 먹는다.

## 검증

- `bash scripts/run_tests.sh` — **판정 3조건 전부**: `exit 0` + `TEST_OK` ≥ 1 + `SCRIPT ERROR` 0.
- 🔴 **실기 확인이 필수다** — 헤드리스는 렌더·타일 이음새·색 조화를 구조적으로 못 잡는다(rules §5). 마을 씬 직접 실행:
  `./Godot_v4.7.1-stable_win64.exe --path . --resolution 1280x720 res://src/village/village.tscn`
- 리소스 무결성은 **`ResourceLoader.load`가 null이 아닌지 직접** 본다 — "익스포트 성공"을 근거로 쓰지 마라(rules §5).
- 팔레트 실측: Aseprite `get_color_stats`로 장별 색 수를 찍어 남긴다.

## 완료 조건

1. 마을을 걸었을 때 **자글거리지 않는다**(사용자 판단 — 중간에 두어 번 보여주고 방향을 받는다).
2. 바닥·나무·표지가 **한 팔레트**로 보인다.
3. 기능 3곳이 숲 안에서 **눈에 띈다**(랜드마크로 읽힌다).
4. 상호작용이 그대로 된다(F로 제작/훈련소/출발).
5. 스위트 그린 + 실기 확인.

## ⚠ 리드가 잡는 것

`--import` · git 커밋 · `mcp__godot` 에디터 제어(에디터 인스턴스가 하나뿐이다). `projectb-art`에 위임하면 PNG(+`_frames.tres` 제안)까지만 받는다.

⚠ **에디터 MCP 브리지가 다른 클라이언트에 물릴 수 있다** — 07-31에 `godot-mcp` node 프로세스가 4개 떠 있어 제어가 안 됐다. 안 붙으면 중복 프로세스부터 확인해라.
