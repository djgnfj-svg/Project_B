---
name: assets-pipeline
description: 에셋을 임포트하고 관리할 때 사용한다 — 이미지 압축, 3D 씬 임포트, 오디오 포맷, 리소스 포맷, 임포트 구성
---

# Godot 4.3+의 에셋 파이프라인

모든 예제는 Godot 4.3+를 대상으로 하며 폐기된 API를 쓰지 않는다. GDScript를 먼저 보이고, 그다음 C#을 보인다.

> **관련 스킬:** 오디오 재생과 버스 아키텍처는 **audio-system**, 3D 머티리얼과 조명은 **3d-essentials**, 2D 렌더링과 스프라이트는 **2d-essentials**, 임포트된 애니메이션은 **animation-system**, 에셋 관련 성능은 **godot-optimization**, 스레드 리소스 로딩은 **multithreading**을 참고하라.

---

## 1. 임포트가 동작하는 방식

### 임포트 시스템

`res://`에 파일을 추가하면 Godot이 타입에 따라 자동 임포트한다. 임포트 설정은 원본 옆의 `.import` 사이드카 파일에 저장된다.

```
project/
├── textures/
│   ├── player.png           ← original file (committed to VCS)
│   └── player.png.import    ← import settings (committed to VCS)
└── .godot/
    └── imported/            ← compiled cache (NOT committed — .gitignore it)
```

### 핵심 규칙

- **`.godot/imported/`의 파일을 절대 수정하지 마라** — 원본에서 재생성된다
- **`.import` 파일을 버전 관리에 커밋하라** — 설정을 저장한다
- 설정 변경 후 **재임포트**하라: 파일 선택 → Import 도크 → **Reimport** 클릭
- `.gitignore`에 `.godot/`를 넣어야 한다

### 임포트 설정 변경

1. **FileSystem** 도크에서 파일을 선택한다
2. **Import** 도크를 연다(기본적으로 Scene 도크 옆)
3. 설정을 변경한다
4. **Reimport**(또는 일괄 변경은 **Reimport All**)를 클릭한다

> 임포트 설정은 3D 씬의 경우 **Advanced Import Settings**로도 설정할 수 있다(`.glb`/`.gltf` 파일 더블클릭).

---

## 2. 이미지 임포트

### 압축 모드

| 모드           | 품질   | VRAM     | 파일 크기 | 용도                         |
|----------------|-----------|----------|-----------|----------------------------------|
| **Lossless**   | 완벽   | 높음     | 큼     | 픽셀 아트, UI 요소           |
| **Lossy**      | 좋음      | 높음     | 작음     | 큰 사진, 배경        |
| **VRAM Compressed** | 감소 | 낮음   | 작음     | 3D 텍스처, 큰 2D 스프라이트    |
| **VRAM Uncompressed** | 완벽 | 높음 | 큼    | VRAM 압축 아티팩트가 용납 안 될 때 |
| **Basis Universal** | 감소 | 낮음  | 아주 작음 | 크로스 플랫폼, 여러 GPU 포맷 |

### 언제 무엇을 쓰나

```
Pixel art / UI icons       → Lossless (no artifacts, crisp pixels)
2D game sprites            → Lossless (small sprites) or VRAM Compressed (large sprites)
3D textures (albedo, normal) → VRAM Compressed (saves GPU memory)
Large backgrounds          → Lossy or VRAM Compressed
Mobile targets             → VRAM Compressed (essential for memory)
```

### 핵심 임포트 설정

| 설정            | 설명                                   | 기본값     |
|--------------------|-----------------------------------------------|-------------|
| **Compress > Mode** | 압축 알고리즘(위 표 참고)      | VRAM Compressed |
| **Mipmaps > Generate** | 거리 렌더링용 밉맵 생성   | Off         |
| **Process > Fix Alpha Border** | 투명 스프라이트의 어두운 외곽선 방지 | On    |
| **Process > Premult Alpha** | 알파 프리멀티플라이(어두운 헤일로 방지)   | Off         |
| **Flags > Filter** | 이중선형 필터링(부드러움) 대 최근접(선명) | Linear    |
| **Flags > Repeat** | 텍스처 타일링 활성화                        | Disabled    |

### 픽셀 아트 설정

선명한 픽셀 아트를 위해 프로젝트 전역으로 다음을 설정한다:

**Project Settings > Rendering > Textures > Canvas Textures > Default Texture Filter** → `Nearest`

또는 Import 도크에서 이미지별로: **Filter** → `Nearest`

### 밉맵 활성화

밉맵은 각도나 먼 거리에서 보는 텍스처의 반짝임(shimmering)을 막는다. 3D 텍스처에는 필수, 2D에는 선택.

- **3D 텍스처:** 항상 밉맵 활성화(Import 도크 → Mipmaps → Generate → On)
- **2D 스프라이트:** 보통 끔(Camera2D 줌을 쓰지 않는 한)
- **UI 텍스처:** 끔(고정 스케일로 렌더링)

> **Godot 4.7+:** DDS 임포트가 R8과 R8G8 텍스처 포맷을 지원한다. ([GH-116307](https://github.com/godotengine/godot/pull/116307))

---

## 3. 3D 씬 임포트

### 지원 포맷

| 포맷    | 확장자    | 권장                              |
|-----------|-------------|----------------------------------------------|
| **glTF**  | `.gltf`, `.glb` | **권장** — 개방 표준, 최고 지원 |
| **Blend** | `.blend`    | 직접 Blender 임포트(Blender 설치 필요) |
| **FBX**   | `.fbx`      | 레거시 파이프라인에 적합                    |
| **Collada** | `.dae`    | 옛 포맷, 가능하면 glTF 사용           |
| **OBJ**   | `.obj`      | 정적 메시만 — 애니메이션/리그 없음      |

> **glTF가 권장 포맷이다.** Godot 지원이 가장 좋고, 개방 표준이며, 머티리얼·애니메이션·리그를 정확히 보존한다.

### 노드 네이밍 규약

Godot은 3D 모델 오브젝트 이름의 **접미사**에 따라 적절한 노드 타입을 자동 생성한다:

| 접미사                | 생성되는 노드            | 예시 이름               |
|-----------------------|---------------------------|----------------------------|
| `-col`                | StaticBody3D + collision  | `Wall-col`                 |
| `-convcol`            | ConvexPolygonShape3D      | `Rock-convcol`             |
| `-rigid`              | RigidBody3D               | `Barrel-rigid`             |
| `-navmesh`            | NavigationRegion3D        | `Floor-navmesh`            |
| `-occluder`           | OccluderInstance3D        | `BigWall-occluder`         |

```
In Blender:                  In Godot (after import):
Wall-col                  →  StaticBody3D
├── Wall (mesh)           →    ├── MeshInstance3D
                          →    └── CollisionShape3D (auto-generated)
```

### Import 도크 설정

임포트된 `.glb`/`.gltf`를 FileSystem에서 선택한 뒤, Import 도크에서:

| 설정                    | 설명                                      |
|----------------------------|--------------------------------------------------|
| **Root Type**              | 루트 노드 타입 오버라이드(Node3D, RigidBody3D 등) |
| **Root Name**              | 루트 노드의 커스텀 이름                    |
| **Meshes > Generate LOD**  | LOD 레벨 자동 생성(기본 켜짐)         |
| **Meshes > Light Baking**  | 라이트맵 베이킹용 Static 또는 Dynamic            |
| **Animation > Import**     | 애니메이션 임포트 활성/비활성                 |
| **Animation > FPS**        | 이 프레임레이트로 애니메이션 베이크                 |

> **Godot 4.7+:** Import 도크의 임포트 타입 옵션이 3D 씬 파일을 전체 씬 대신 단일 `Mesh` 리소스나 `MeshLibrary`(GridMap용)로도 임포트할 수 있다 — 3D 저작 도구에서 별도 익스포트 단계가 필요 없다. ([GH-107856](https://github.com/godotengine/godot/pull/107856))

> ⚠️ **Godot 4.7에서 변경됨:** `EditorSceneFormatImporter`의 `IMPORT_SCENE`, `IMPORT_ANIMATION`, `IMPORT_FAIL_ON_MISSING_DEPENDENCIES`, `IMPORT_GENERATE_TANGENT_ARRAYS`, `IMPORT_USE_NAMED_SKIN_BINDS`, `IMPORT_DISCARD_MESHES_AND_MATERIALS`, `IMPORT_FORCE_DISABLE_MESH_COMPRESSION` 상수가 새 `ImportFlags` enum(비트필드)으로 이동했다. GDScript는 호환되며, 옛 클래스 레벨 상수를 참조하던 C# 임포터 플러그인은 enum 멤버로 전환해야 한다. [4.7 마이그레이션 가이드](https://docs.godotengine.org/en/latest/tutorials/migrating/upgrading_to_godot_4.7.html)를 참고하라.

### 런타임 씬 로딩

컴파일 타임에 알려진 경로에는 `preload()`를, 데이터 주도 경로에는 `load()`를 쓴다.

### 런타임 glTF 임포트 플래그 (Godot 4.7+)

`GLTFDocument`가 `ImportFlags` 비트필드를 노출한다 — `IMPORT_FLAG_GENERATE_TANGENT_ARRAYS`(8), `IMPORT_FLAG_USE_NAMED_SKIN_BINDS`(16), `IMPORT_FLAG_DISCARD_MESHES_AND_MATERIALS`(32), `IMPORT_FLAG_FORCE_DISABLE_MESH_COMPRESSION`(64) — 이는 `append_from_file()`, `append_from_buffer()`, `append_from_scene()`의 `flags: int = 0` 파라미터가 받는다:

```gdscript
var doc := GLTFDocument.new()
var state := GLTFState.new()
doc.append_from_file("user://mods/enemy.glb", state,
        GLTFDocument.IMPORT_FLAG_GENERATE_TANGENT_ARRAYS | GLTFDocument.IMPORT_FLAG_USE_NAMED_SKIN_BINDS)
add_child(doc.generate_scene(state))
```

```csharp
var doc = new GltfDocument();
var state = new GltfState();
doc.AppendFromFile("user://mods/enemy.glb", state,
    (uint)(GltfDocument.ImportFlags.GenerateTangentArrays | GltfDocument.ImportFlags.UseNamedSkinBinds));
AddChild(doc.GenerateScene(state));
```

---

## 4. 애니메이션 임포트

### 애니메이션 분리

3D 파일이 여러 애니메이션이 담긴 단일 타임라인을 포함하면, **Advanced Import Settings**에서 분리한다:

1. `.glb` 파일을 더블클릭해 Advanced Import Settings를 연다
2. **Animations** 탭으로 간다
3. **start frame**과 **end frame**으로 애니메이션 클립을 추가한다
4. 클립별 **loop mode**를 설정한다(None, Linear, Ping-Pong)

### 애니메이션 리타게팅

스켈레톤이 다른 캐릭터끼리 애니메이션을 공유:

1. 소스(애니메이션)와 타깃(캐릭터) 모델을 둘 다 임포트한다
2. 타깃 모델에서 **Advanced Import Settings**를 연다
3. **Skeleton3D > Retarget** 설정으로 간다
4. 소스 본을 타깃 본에 매핑한다
5. 표준 휴머노이드 매핑에는 `SkeletonProfile` 리소스를 쓴다

### 애니메이션 임포트 설정

| 설정               | 설명                              |
|-----------------------|------------------------------------------|
| **Import**            | 애니메이션 임포트 활성/비활성          |
| **FPS**               | 베이크 프레임레이트(30이 표준)          |
| **Trimming**          | 시작/끝의 빈 프레임 제거         |
| **Remove Immutable Tracks** | 변하지 않는 트랙 제거  |

---

## 5. 오디오 임포트

> 심화 오디오 재생, 버스 설정, 음악 관리는 **audio-system** 스킬을 참고하라.

### 포맷 권장

| 포맷 | 임포트 형태       | 용도                   | 핵심 설정            |
|--------|-----------------|---------------------------|-------------------------|
| WAV    | AudioStreamWAV  | 짧은 SFX                 | Loop Mode, Mix Rate     |
| OGG    | AudioStreamOggVorbis | 음악, 긴 SFX      | Loop, Loop Offset       |
| MP3    | AudioStreamMP3  | 음악(대안)          | Loop, BPM               |

### 핵심 임포트 설정

| 설정       | 설명                                    | 언제 쓰나             |
|---------------|------------------------------------------------|-------------------------|
| **Loop**      | 루프 재생 활성화                        | 음악, 앰비언트 루프    |
| **Loop Offset** | 루프 재시작 시작 위치             | 루프 시 인트로 회피     |
| **Force Mono** | 스테레오를 모노로 변환                        | 3D 위치 오디오     |
| **BPM**       | 분당 비트                               | 리듬 게임            |
| **Beat Count** | 트랙의 총 비트 수                      | 리듬 동기            |

> **임포트 팁:** 짧은 SFX에는 WAV를 써라(디코드 지연 0). 음악에는 OGG를 써라(작은 파일, 좋은 품질). AudioStreamPlayer3D와 함께 쓰는 오디오는 **Force Mono**를 켜라 — 스테레오는 공간화가 제대로 안 된다.

---

## 6. 리소스 포맷

### .tres 대 .res

| 포맷 | 타입       | 읽기 가능 | 용도                              |
|--------|------------|----------|--------------------------------------|
| `.tres` | 텍스트      | 예      | 손으로 편집하거나 diff하는 리소스   |
| `.res`  | 바이너리    | 아니오   | 큰 리소스, 더 빠른 로딩      |

```gdscript
# Save as text resource
ResourceSaver.save(my_resource, "res://data/item.tres")

# Save as binary resource
ResourceSaver.save(my_resource, "res://data/item.res")

# Load (either format)
var resource: Resource = load("res://data/item.tres")
```

```csharp
ResourceSaver.Save(myResource, "res://data/item.tres");
ResourceSaver.Save(myResource, "res://data/item.res");
var resource = GD.Load<Resource>("res://data/item.tres");
```

### 언제 무엇을 쓰나

- **`.tres`** — 직접 만들고 편집하는 커스텀 리소스(아이템 데이터, 설정, 스킬 정의). 버전 관리에 친화적.
- **`.res`** — 생성되거나 큰 바이너리 데이터(베이크된 라이트맵, 내비게이션 메시, 큰 메시). 로드가 빠름.
- **`.tscn`** — 텍스트 씬 파일(씬에는 항상 텍스트를 써라 — VCS에서 diff 가능)
- **`.scn`** — 바이너리 씬 파일(드묾 — 로드 시간이 중요한 아주 큰 씬에만)

### 스레드 리소스 로딩

`ResourceLoader.load_threaded_request()` / `load_threaded_get_status()` / `load_threaded_get()` 패턴으로 게임을 멈추지 않고 큰 리소스를 로드한다.

---

## 7. 흔한 함정

| 증상                               | 원인                                       | 해결                                                               |
|---------------------------------------|----------------------------------------------|--------------------------------------------------------------------|
| 텍스처가 흐릿하게 보임                  | 픽셀 아트에 Filter가 Linear로 설정됨        | Project Settings에서 Default Texture Filter를 Nearest로 설정          |
| 투명 스프라이트에 어두운 외곽선  | 임포트 시 알파 보더 미수정             | Import 도크에서 "Fix Alpha Border" 활성화                           |
| 3D 모델에 충돌이 없음            | 소스 모델에 네이밍 접미사 없음               | Blender에서 메시 이름에 `-col` 접미사를 추가하거나 수동 추가       |
| 임포트된 애니메이션이 없음           | Import 도크에서 "Import Animation" 비활성   | Animation > Import 활성화 후 재임포트                             |
| 모바일에서 텍스처 VRAM이 너무 높음       | 큰 텍스처에 Lossless 압축 사용 | 256px 초과 텍스처는 VRAM Compressed로 전환                    |
| 3D 텍스처가 먼 거리에서 반짝임       | 밉맵 미생성                        | Import 도크에서 Mipmaps > Generate 활성화                           |
| 오디오가 루프 지점에서 팝/클릭      | 루프 오프셋이 잘못 설정됨                | Import 도크에서 Loop Offset 조정; 오디오 에디터에서 페이드 추가       |
| 씬 파일이 엄청 큼                | `.tscn` 대신 바이너리 `.scn` 사용       | 씬을 VCS용 `.tscn`(텍스트)로 저장; 필요할 때만 `.scn` 사용  |
| 리클론 후 임포트 설정 손실    | `.import` 파일이 VCS에 커밋 안 됨       | 항상 `.import` 파일을 커밋; `.godot/`만 .gitignore에 넣음  |
| 스레드 로드가 게임을 멈춤            | `load()`로 매 프레임 상태 확인       | `ResourceLoader.load_threaded_request/get_status` 패턴 사용      |

> ⚠️ **Godot 4.7에서 변경됨:** 폰트 임포트의 `hinting` 기본값이 `1`(Light)에서 `3`(Light (Except Pixel Fonts))로 바뀌었다 — 픽셀 스타일 폰트가 임포트 시 힌팅을 자동 비활성화하므로 업그레이드 후 렌더링이 바뀔 수 있다. 4.6 모습을 유지하려면 폰트별로 Import 도크에서 `hinting`을 다시 `1`(Light)로 설정하라. [4.7 마이그레이션 가이드](https://docs.godotengine.org/en/latest/tutorials/migrating/upgrading_to_godot_4.7.html)를 참고하라.

---

## 8. 구현 체크리스트

- [ ] `.gitignore`가 `.godot/`는 제외하지만 `.import` 파일은 제외하지 않는다
- [ ] 픽셀 아트 프로젝트는 Project Settings에서 Default Texture Filter를 `Nearest`로 설정한다
- [ ] 3D 텍스처는 밉맵이 켜져 있다(Import 도크 → Mipmaps → Generate)
- [ ] 큰 텍스처는 VRAM Compressed를 쓴다(특히 모바일 타깃)
- [ ] 3D 모델은 기본 임포트 포맷으로 glTF(`.glb` 또는 `.gltf`)를 쓴다
- [ ] 충돌 셰이프는 3D 저작 도구에서 네이밍 접미사(`-col`, `-convcol`)를 쓴다
- [ ] 애니메이션은 Advanced Import Settings에서 개별 클립으로 분리돼 있다
- [ ] 오디오 SFX는 WAV를, 음악은 OGG Vorbis를 쓴다
- [ ] 3D 위치 오디오 파일은 모노로 임포트된다(Force Mono 활성화)
- [ ] 커스텀 데이터 리소스는 버전 관리 diff 가능성을 위해 `.tres`(텍스트)를 쓴다
- [ ] 크거나 런타임 로드되는 리소스는 `ResourceLoader.load_threaded_request()`를 쓴다
- [ ] 씬 파일은 버전 관리를 위해 `.tscn`(텍스트 포맷)을 쓴다
