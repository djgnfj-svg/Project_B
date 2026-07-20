---
name: responsive-ui
description: 여러 해상도를 다룰 때 사용한다 — 스트레치 모드, 종횡비, DPI 스케일링, 모바일/데스크톱 대응
---

# Godot 4.3+의 반응형 UI

모든 예제는 Godot 4.3+를 대상으로 하며 폐기된 API를 쓰지 않는다. GDScript를 먼저, 그다음 C#을 보여준다.

> **관련 스킬:** Control 노드 레이아웃과 테마는 **godot-ui**, 플랫폼별 익스포트 설정은 **export-pipeline**, 초기 프로젝트 해상도 설정은 **godot-project-setup**, 터치 대 데스크톱 입력 대응은 **input-handling**, 로케일별 레이아웃 조정은 **localization**, 세이프 에어리어와 노치 처리는 **mobile-development**를 참고하라.

---

## 1. 해상도 관련 프로젝트 설정

기본 해상도와 스트레치 동작은 `Project > Project Settings > Display > Window`에서 설정한다.

핵심 설정과 그 `.godot/project.godot` 키:

| 설정 | project.godot 키 | 권장 값 |
|---|---|---|
| 뷰포트 너비 | `window/size/viewport_width` | `1920` (또는 기준 설계 너비) |
| 뷰포트 높이 | `window/size/viewport_height` | `1080` (또는 기준 설계 높이) |
| 스트레치 모드 | `window/stretch/mode` | `canvas_items` (대부분의 게임) |
| 스트레치 종횡비 | `window/stretch/aspect` | `expand` (화면 채움) 또는 `keep` (레터박스) |
| 스케일 팩터 | `window/stretch/scale` | `1` (픽셀 아트 정수 스케일링을 위해 조정) |

> **Godot 4.7+:** Godot 4.7에서 **새로 생성된** 프로젝트는 이미 `display/window/stretch/mode`가 `canvas_items`로, `display/window/stretch/aspect`가 `expand`로 기본 설정된다(이전에는 `disabled` / `keep`) — 위 권장값이 이제 기본값이다. 이전 버전에서 생성된 프로젝트는 그대로다(프로퍼티 기본값이 여전히 `disabled`), 그러니 업그레이드 시 둘 다 명시적으로 설정하라. [4.7 마이그레이션 가이드](https://docs.godotengine.org/en/latest/tutorials/migrating/upgrading_to_godot_4.7.html)를 보라.

런타임에서도 설정할 수 있다:

**GDScript:**

```gdscript
# Read current viewport size
var viewport_size: Vector2 = get_viewport().get_visible_rect().size

# Change stretch mode at runtime
ProjectSettings.set_setting("display/window/stretch/mode", "canvas_items")
```

**C#:**

```csharp
// Read current viewport size
Vector2I viewportSize = GetViewport().GetVisibleRect().Size;

// Change a project setting at runtime (takes effect next frame)
ProjectSettings.SetSetting("display/window/stretch/mode", "canvas_items");
```

---

## 2. 스트레치 모드 비교

| 모드 | `project.godot` 값 | 렌더링 | 적합한 용도 |
|---|---|---|---|
| `canvas_items` | `"canvas_items"` | 뷰포트가 설계 해상도로 렌더된 뒤 업스케일 — UI와 2D 노드가 부드럽게 스케일됨 | 대부분의 2D 및 UI 중심 게임 |
| `viewport` | `"viewport"` | 전체 뷰포트가 설계 해상도로 렌더된 뒤 늘어남; 서브픽셀 블렌딩 없음 | 픽셀 퍼펙트 출력이 필요한 픽셀 아트 게임 |
| `disabled` | `"disabled"` | 자동 스케일링 없음; 모든 Control 노드가 자체 레이아웃을 처리해야 함 | 복잡한 커스텀 스케일링, Control HUD가 있는 3D 게임 |

**각각을 언제 고르나:**

- **`canvas_items`** — 기본 권장. 어떤 해상도에서도 부드러운 스케일링. `Control` 노드와 앵커로 만든 UI가 자연스럽게 반응한다. `content_scale_factor`와 결합하면 고DPI에서 텍스트와 아이콘이 선명하게 유지된다.
- **`viewport`** — 렌더링을 설계 해상도로 고정한다. 정수 스케일링과 최근접 이웃 필터링을 결합하면 고전적인 픽셀 퍼펙트 룩을 준다. 의도적으로 큼직한 픽셀을 원하는 게 아니라면 고DPI 디스플레이에서는 피하라.
- **`disabled`** — 완전한 수동 제어가 필요할 때 쓴다. 예: Godot가 스케일하지 않고 UI가 세이프 에어리어나 특이한 종횡비에 대응해야 하는 3D 게임.

---

## 3. 종횡비 처리

`Project > Project Settings > Display > Window > Stretch > Aspect` 또는 `window/stretch/aspect` 키로 설정한다.

| 모드 | 시각적 결과 | 언제 쓰나 |
|---|---|---|
| `keep` | 레터박스(상하 검은 띠) 또는 필러박스(좌우 띠) — 설계 사각형이 정확히 보존됨 | 잘려선 안 되는 고정 레이아웃 게임(예: 점수형 아케이드, 퍼즐) |
| `expand` | 화면이 완전히 채워짐; 더 넓거나 높은 디스플레이에서 보이는 게임 영역이 커짐 | 액션 게임, 플랫포머 — 더 넓은 플레이 영역이 문제가 아니라 이득 |
| `keep_width` | 너비 고정; 높은 화면에서 높이가 확장됨(모바일 세로) | 수평 정렬이 엄격한 세로 모바일 게임 |
| `keep_height` | 높이 고정; 넓은 화면에서 너비가 확장됨(가로) | 수직 정렬이 엄격한 가로 게임(예: 횡스크롤 HUD) |

**적응형 UI를 곁들인 `expand`**가 데스크톱과 모바일 둘 다 노리는 게임에 가장 다재다능한 선택이다. HUD 요소를 화면 가장자리에 앵커해 확장된 가시 영역을 따라가게 하라.

---

## 4. 픽셀 아트 설정

선명한 픽셀 아트 게임을 위해: `Project Settings → Display → Window → Stretch → Mode = viewport`, 기준 해상도는 네이티브 픽셀 크기(예: 320×180), 에디터 미리보기용 `Window Size Override = 4×`. 서브픽셀 블러를 피하려면 정수 스케일링을 써라.
---

## 5. DPI 스케일링

레티나 / 고DPI 디스플레이를 위해: `content_scale_factor`를 설정해 전체 UI를 비례해서 스케일하라. 기기별 적응형 스케일링을 위해 런타임에 `DisplayServer.screen_get_dpi()`를 조회하라.
---

## 6. 모바일 고려사항

모바일 고유 관심사 네 가지: **터치 입력**(탭, 스와이프, 멀티터치), **세이프 에어리어 인셋**(노치 / 다이내믹 아일랜드 회피), **방향 잠금**(세로/가로 고정), **가상 키보드**(UI를 가리지 않도록 표시/숨김 처리).
---

## 7. 적응형 레이아웃

앵커 프리셋 + Container 노드가 대부분의 일을 한다. `size_flags_horizontal`/`vertical`(`FILL`, `EXPAND`, `SHRINK_CENTER`, `SHRINK_END`)로 자식이 컨테이너 공간을 어떻게 차지할지 제어하라. `get_viewport().size_changed`로 런타임 해상도 변경을 감지하라.
---

## 8. 여러 해상도 테스트

### 에디터 미리보기 크기

에디터 뷰포트에서 **Editor > Editor Settings > Run > Window Placement**로 게임을 특정 크기로 시작하거나, 2D 에디터 툴바의 뷰포트 크기 선택기를 쓴다.

에디터에서 미리보려면 **Project > Project Settings > Display > Window > Size > Test Width/Height** 아래에 흔한 테스트 크기를 추가하라.

### `--resolution` CLI 플래그

커맨드 라인에서 오버라이드 해상도로 실행:

```bash
# Windows
godot.exe --path "C:/projects/mygame" --resolution 1280x720

# Linux / macOS
godot --path /projects/mygame --resolution 1280x720

# Run an exported binary at a specific size
./mygame.x86_64 --resolution 375x812
```

### 흔한 테스트 해상도

| 해상도 | 종횡비 | 흔한 용도 |
|---|---|---|
| `1920×1080` | 16:9 | 표준 1080p 데스크톱 / TV |
| `2560×1440` | 16:9 | 1440p 고DPI 데스크톱 |
| `1280×720` | 16:9 | 저사양 데스크톱 / 최소 타깃 |
| `640×360` | 16:9 | 픽셀 아트 기준 해상도(320×180의 2×) |
| `2732×2048` | 4:3 | iPad Pro — 비16:9 종횡비 테스트 |
| `390×844` | ~19.5:9 | iPhone 14 세로 |
| `844×390` | ~19.5:9 | iPhone 14 가로 |
| `1080×2400` | 20:9 | Android 긴 세로 |
| `360×800` | ~20:9 | Android 저사양 세로 |

> **전략:** 항상 기준 설계 해상도, 16:9보다 한 단계 넓은 것(예: 21:9 울트라와이드), 그리고 한 단계 높은 것(예: 모바일 세로)에서 테스트하라. 이 세 경우가 가장 많은 레이아웃 버그를 잡는다.

---

## 9. 체크리스트

- [ ] 기준 뷰포트 크기(`viewport_width` / `viewport_height`)가 에디터의 설계 캔버스와 일치한다
- [ ] 스트레치 모드를 의도적으로 골랐다: 대부분 `canvas_items`, 픽셀 아트는 `viewport`
- [ ] 종횡비 모드를 골랐다: 고정 레이아웃 콘텐츠가 `keep`을 요구하지 않는 한 `expand`
- [ ] 픽셀 아트 게임은 `viewport` 스트레치 + `Nearest` 텍스처 필터 + 정수 `content_scale_factor`를 쓴다
- [ ] 모든 HUD `Control` 노드가 고정 `position` 값이 아니라 가장 가까운 가장자리에 앵커돼 있다
- [ ] 버튼과 인터랙티브 요소에 `custom_minimum_size`를 설정해 탭 타깃 크기 아래로 무너지지 않게 한다(모바일 최소 44×44 px 권장)
- [ ] 공간을 채워야 하는 요소에 `size_flags_horizontal` / `size_flags_vertical`을 `SIZE_EXPAND_FILL`로 설정한다
- [ ] 레이아웃이 창 크기 변경에 반응해야 하는 곳에 `get_viewport().size_changed` 시그널이 연결돼 있다
- [ ] 세이프 에어리어 인셋을 `DisplayServer.get_display_safe_area()`에서 읽어 루트 `MarginContainer`에 적용한다
- [ ] 고DPI / 레티나 디스플레이를 위해 시작 시 `DisplayServer.screen_get_dpi()` 기반으로 `content_scale_factor`를 설정한다
- [ ] 터치 입력을 마우스 이벤트만이 아니라 `InputEventScreenTouch` / `InputEventScreenDrag`로 처리한다
- [ ] 방향을 올바른 모드(`SCREEN_LANDSCAPE` / `SCREEN_PORTRAIT`)로 잠그거나, 회전이 의도된 곳은 `SCREEN_SENSOR`로 둔다
- [ ] 가상 키보드 높이를 표시 후 조회해 모바일에서 UI 콘텐츠를 위로 밀 때 쓴다
- [ ] 최소한 설계 해상도, 하나의 울트라와이드(21:9), 하나의 모바일 세로 해상도에서 테스트했다
- [ ] CI나 플레이테스트 스크립트에서 `--resolution` 플래그로 다중 해상도 스모크 테스트를 자동화한다
