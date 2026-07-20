---
name: godot-ui
description: 사용자 인터페이스를 만들 때 사용 — Control 노드, 테마, 앵커, 컨테이너, 레이아웃 패턴
---

# Godot UI — Control 노드, 테마 & 레이아웃

모든 예제는 폐기된 API 없이 Godot 4.3+를 대상으로 한다. GDScript를 먼저, 그다음 C#을 보여준다.

> **관련 스킬:** 다해상도 스케일링은 **responsive-ui**, 인게임 HUD 패턴은 **hud-system**, 대사 UI 표현은 **dialogue-system**, UI 전환·애니메이션 효과는 **tween-animation**을 보라.

---

## 1. Control 노드 계층

### Control이 Node2D와 다른 점

`Control`은 모든 UI 노드의 기반 클래스다. 씬 트리에서 `Node2D`/`Node3D`와 별개의 가지에 살며, 근본적으로 다른 레이아웃 모델을 가진다.

| 기능 | `Node2D` | `Control` |
|---|---|---|
| 위치 모델 | 월드 공간 `position` (부모로부터 픽셀) | 부모 rect 기준 앵커 + 오프셋 |
| 크기 | 고유 크기 없음 | `size`, `minimum_size`, `custom_minimum_size` 가짐 |
| 테마 | 없음 | `Theme` 리소스를 상속·오버라이드 |
| 포커스 | 해당 없음 | 내장 포커스 시스템 (`focus_mode`, `grab_focus()`) |
| 마우스 이벤트 | `_input`으로 수동 처리 | `gui_input`, `mouse_entered`, `mouse_exited` |
| 레이아웃 헬퍼 | 없음 | `Container` 서브클래스가 자식을 자동 배치 |

### 기반 클래스로서의 Control

모든 UI 위젯(`Button`, `Label`, `LineEdit` 등)은 `Control`을 상속한다. `Control` 자체에 정의된 핵심 프로퍼티는:

- `anchor_left`, `anchor_top`, `anchor_right`, `anchor_bottom` — 부모 rect 기준 분수 값(0.0–1.0)
- `offset_left`, `offset_top`, `offset_right`, `offset_bottom` — 앵커가 해결된 뒤 적용되는 픽셀 오프셋
- `size_flags_horizontal`, `size_flags_vertical` — 노드가 `Container` 레이아웃에 참여하는 방식
- `theme` — `Theme` 리소스. `null`이면 노드가 트리를 거슬러 올라가 가장 가까운 조상의 것을 찾는다
- `focus_mode` — 노드가 키보드/게임패드 포커스를 받을 수 있는지 제어

UI 노드는 `CanvasLayer`(또는 씬 루트의 내장 캔버스 바로 아래)에 두어, 항상 3D/2D 월드 위에 렌더되고 `Camera` 변환의 영향을 받지 않도록 한다.

> ⚠️ **Godot 4.7에서 변경:** `Control.accessibility_live`의 타입이 `DisplayServer.AccessibilityLiveMode`에서 `AccessibilityServer.AccessibilityLiveMode`(`LIVE_OFF = 0` 기본, `LIVE_POLITE`, `LIVE_ASSERTIVE`)로 바뀌었다 — 접근성 enum/API가 새 `AccessibilityServer` 싱글턴으로 옮겨졌다. GDScript 호환. C# 바이너리/소스 호환성은 깨진다(새 enum에 맞춰 재빌드). [4.7 마이그레이션 가이드](https://docs.godotengine.org/en/latest/tutorials/migrating/upgrading_to_godot_4.7.html)를 보라.

---

## 2. 흔한 Container 노드

| Container | 목적 | 언제 쓰나 |
|---|---|---|
| `VBoxContainer` | 자식을 위에서 아래로 세로 쌓음 | 리스트, 옵션 행, 세로 메뉴 |
| `HBoxContainer` | 자식을 왼쪽에서 오른쪽으로 가로 쌓음 | 툴바, 스탯 행, 가로 내비 |
| `GridContainer` | 자식을 고정 열 그리드로 배열 | 인벤토리 그리드, 키 바인딩 표 |
| `MarginContainer` | 단일 자식 둘레에 패딩을 더함 | 여백을 주려고 임의의 노드를 감쌀 때 |
| `PanelContainer` | `StyleBox` 배경을 그린 뒤 자식을 배치 | 카드 UI, 대화 상자, HUD 패널 |
| `ScrollContainer` | 단일 자식을 스크롤 가능하게; 넘침을 클립 | 긴 리스트, 로그, 스크롤 설정 |
| `TabContainer` | 자식을 이름 붙은 탭으로 쌓아 한 번에 하나 표시 | 설정 화면, 다중 섹션 패널 |

**크기 조정 팁:**
- 가용 공간을 채워야 하는 자식에는 `size_flags_horizontal = SIZE_EXPAND_FILL`을 설정하라.
- 자식이 0으로 접히는 것을 막으려면 `custom_minimum_size`를 써라.
- `MarginContainer`는 테마 프로퍼티 `margin_*`에서 마진을 읽는다. 런타임에는 `add_theme_constant_override("margin_left", 16)`로 오버라이드하라.

> **Godot 4.7+:** `custom_maximum_size`(`Vector2(-1, -1)`)는 축별로 크기를 제한하며 `custom_minimum_size`보다 우선한다. `propagate_maximum_size`(기본 `false`)는 부모의 최대치가 그 Control 자식들을 제약하게 한다. `_get_maximum_size()` 가상 메서드는 코드로 최대치를 계산한다.

> ⚠️ **Godot 4.7에서 변경:** `TabContainer.all_tabs_in_front`는 폐기됐다 — 탭이 항상 앞에 있어 더는 아무것도 하지 않는다. 그것을 설정하는 코드를 제거하라. [GH-118623](https://github.com/godotengine/godot/pull/118623)를 보라.

---

## 3. 앵커 & 마진

### 앵커 프리셋이 동작하는 방식

앵커는 **부모** rect 위의 한 점을 분수로 표현한 것이다(0 = 위/왼쪽 가장자리, 1 = 아래/오른쪽 가장자리). Godot는 각 가장자리의 최종 픽셀 위치를 이렇게 해결한다:

```
final_left   = parent_width  * anchor_left   + offset_left
final_top    = parent_height * anchor_top    + offset_top
final_right  = parent_width  * anchor_right  + offset_right
final_bottom = parent_height * anchor_bottom + offset_bottom
```

에디터가 내장 프리셋을 노출한다:

| 프리셋 | 앵커 값 | 사용 사례 |
|---|---|---|
| Full Rect | L=0, T=0, R=1, B=1 | 오버레이 / 부모 채움 — 루트 UI에 가장 흔함 |
| Center | L=0.5, T=0.5, R=0.5, B=0.5 | 부모 중앙에 고정 크기 위젯 |
| Top Left | L=0, T=0, R=0, B=0 | 좌상단 모서리에 고정 크기 위젯 |
| Top Right | L=1, T=0, R=1, B=0 | 우상단 모서리에 고정 크기 위젯 |
| Bottom Center | L=0.5, T=1, R=0.5, B=1 | 하단 중앙에 앵커된 HUD 요소 |

### 코드로 앵커 설정하기

**GDScript:**

```gdscript
# Fill parent completely (equivalent to "Full Rect" preset)
$Panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

# Anchor to top-right corner, fixed 200x60 size
$HUDLabel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
$HUDLabel.size = Vector2(200.0, 60.0)
# Fine-tune with a 16 px margin from the right and top edges
$HUDLabel.offset_right  = -16.0
$HUDLabel.offset_top    =  16.0

# Custom responsive anchor: right half of screen, full height
$SidePanel.anchor_left   = 0.5
$SidePanel.anchor_top    = 0.0
$SidePanel.anchor_right  = 1.0
$SidePanel.anchor_bottom = 1.0
$SidePanel.offset_left   = 0.0
$SidePanel.offset_top    = 0.0
$SidePanel.offset_right  = 0.0
$SidePanel.offset_bottom = 0.0
```

**C#:**

```csharp
// Fill parent completely
GetNode<Control>("Panel").SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);

// Anchor to top-right corner
var label = GetNode<Control>("HUDLabel");
label.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.TopRight);
label.Size = new Vector2(200f, 60f);
label.OffsetRight = -16f;
label.OffsetTop   =  16f;

// Custom anchor: right half of screen
var panel = GetNode<Control>("SidePanel");
panel.AnchorLeft   = 0.5f;
panel.AnchorTop    = 0.0f;
panel.AnchorRight  = 1.0f;
panel.AnchorBottom = 1.0f;
panel.OffsetLeft   = 0f;
panel.OffsetTop    = 0f;
panel.OffsetRight  = 0f;
panel.OffsetBottom = 0f;
```

### 앵커 vs 오프셋

- **앵커**는 노드의 가장자리가 *부모의 어디를* 추적할지 정한다. 해상도 독립적이다.
- **오프셋**은 앵커 뒤에 더해지는 *고정 픽셀 값*이다. 부모에 따라 스케일되지 않는다.

완전 반응형 레이아웃을 위해서는 오프셋을 0으로 두고 앵커가 일하게 하라. 화장용 마진(예: 가장자리로부터 16 px 간격)에만 작은 고정 오프셋을 더하라.

---

## 4. 테마 시스템

`Theme` 리소스는 폰트·색·`StyleBox`를 한곳에 모은다. 루트에 적용하고 상속이 일하게 하라. 일회성 조정에만 `theme_override_*`를 써라. `StyleBoxFlat`이 대부분의 플랫 디자인 요구를 처리한다(`bg_color`, `border_color`, `corner_radius`, `border_width`). 텍스처 배경에는 `StyleBoxTexture`를 쓴다.

> **Godot 4.7+:** `GradientTexture2D`의 `Fill` enum에 `FILL_CONIC`이 추가됐다 — 색이 원뿔(각도) 패턴으로 보간된다. 셰이더 없이 방사형 진행/쿨다운 인디케이터를 만들 수 있다(C#: `FillEnum.Conic`).

---

## 5. 포커스 & 내비게이션

포커스 모드(`FOCUS_NONE`, `FOCUS_CLICK`, `FOCUS_ALL`)가 키보드/게임패드 내비게이션을 통제한다. `focus_neighbor_top` / `_bottom` / `_left` / `_right`로 내비게이션 사슬을 배선하거나, 자동 공간 감지에 의존하라. 메뉴가 열릴 때 첫 상호작용 요소에 `grab_focus()`를 호출하라.

---

## 6. 흔한 UI 패턴

정석 씬 셋: **메인 메뉴**(제목 + 버튼 목록이 담긴 중앙 VBoxContainer), **탭이 있는 설정 화면**(`TabContainer` + 카테고리별 자식 패널), **일시정지 메뉴 오버레이**(full-rect `ColorRect` 배경 + 중앙 옵션 패널, `get_tree().paused = true`로 일시정지).

> **Godot 4.7+:** `offset_transform_*` — 컨테이너 레이아웃을 절대 재트리거하지 않는 UI 손맛(흔들기/펄스)용 시각 전용 변환. `_get_cursor_shape(at_position)` 가상 메서드 — 위치별 커서 모양. `PopupMenu` 검색 바(`search_bar_enabled`, 기본 퍼지) 및 재정렬용 `set_item_index()`. `TextureRect` `STRETCH_TILE`이 이제 `AtlasTexture`를 타일링한다(0이 아닌 `margin`만 미지원).

> ⚠️ **Godot 4.7에서 변경:** `RichTextLabel.add_image()` / `update_image()`의 크기 지정이 재작업됐다 — `width`/`height`가 이제 `float`. `width_in_percent`/`height_in_percent` bool은 새 `ImageUnit` enum(`IMAGE_UNIT_PIXEL`, `IMAGE_UNIT_PERCENT`, `IMAGE_UNIT_EM` — em은 폰트 크기에 따라 스케일)을 받는 `width_unit`/`height_unit`이 된다. `ImageUpdateMask.UPDATE_WIDTH_IN_PERCENT`는 `UPDATE_WIDTH_UNIT`으로 개명돼, 옛 이름을 쓰는 GDScript를 깨뜨린다. [4.7 마이그레이션 가이드](https://docs.godotengine.org/en/latest/tutorials/migrating/upgrading_to_godot_4.7.html)를 보라.

---

## 7. 시그널

클릭은 `Button.pressed`, 노드의 원시 이벤트는 `Control.gui_input`, 호버는 `Control.mouse_entered` / `mouse_exited`. `_ready()`에서 또는 인스펙터의 Node 패널로 연결하라.

---

## 8. FoldableContainer (Godot 4.5+)

`FoldableContainer`는 Godot 4.5에 도입된 새 내장 `Container` 노드다. 토글 헤더가 있는 아코디언식 접이 섹션을 제공해, `Button`을 수동으로 배선해 자식 `VBoxContainer`를 보이고/숨기는 상용구를 없앤다.

### 기본 사용

```gdscript
# In a script that builds UI dynamically:
func _ready() -> void:
    var foldable := FoldableContainer.new()
    foldable.title = "Advanced Settings"
    foldable.folded = false  # start expanded

    var label := Label.new()
    label.text = "This content can be collapsed."
    foldable.add_child(label)

    var slider := HSlider.new()
    slider.min_value = 0.0
    slider.max_value = 1.0
    slider.value = 0.5
    foldable.add_child(slider)

    add_child(foldable)

# Listen for toggle events:
func _ready() -> void:
    var foldable := $FoldableContainer
    foldable.folding_changed.connect(_on_section_toggled)

func _on_section_toggled(is_folded: bool) -> void:
    print("Section is now: ", "folded" if is_folded else "expanded")
```

```csharp
public override void _Ready()
{
    var foldable = new FoldableContainer
    {
        Title = "Advanced Settings",
        Folded = false
    };

    var label = new Label { Text = "This content can be collapsed." };
    foldable.AddChild(label);

    var slider = new HSlider { MinValue = 0.0, MaxValue = 1.0, Value = 0.5 };
    foldable.AddChild(slider);

    AddChild(foldable);

    // Listen for toggle:
    foldable.FoldingChanged += OnSectionToggled;
}

private void OnSectionToggled(bool isFolded)
{
    GD.Print("Section is now: ", isFolded ? "folded" : "expanded");
}
```

### 핵심 프로퍼티

| 프로퍼티 | 타입 | 목적 |
|----------|------|---------|
| `title` | `String` | 토글 헤더에 보이는 텍스트 |
| `folded` | `bool` | `true` = 내용 숨김, `false` = 내용 보임 |
| `title_alignment` | `HorizontalAlignment` | 헤더 안에서 제목 텍스트 정렬 |

### 시그널

| 시그널 | 시그니처 | 언제 발신 |
|--------|-----------|--------------|
| `folding_changed` | `(folded: bool)` | 접힘 상태가 토글될 때마다 발신 |

> **상용구를 대체함:** Godot 4.5 이전에는 아코디언 섹션에 `Button` + `VBoxContainer` + 시그널 연결이 필요했다. `FoldableContainer`가 이 모두를 한 노드로 처리한다.

---

## 9. 겹친 Label 효과 (Godot 4.5+)

Godot 4.5에서 `Label`과 `RichTextLabel`은 여러 레이어의 텍스트 효과를 동시에 지원한다 — 예를 들어 서로 다른 두께·색의 외곽선 효과를 두 겹 쌓거나, 그림자와 글로우를 결합할 수 있다. 이전에는 다중 외곽선 레이어를 만들려면 Label 노드를 복제해 수동으로 겹쳐야 했다.

```gdscript
# In the inspector: Label → Theme Overrides → Constants
# Add multiple outline layers by stacking VisualShaderNodeTextureParameter entries
# in the Theme, or configure via add_theme_* overrides at runtime.

# Example: thick outer outline + thin inner outline via theme overrides
func apply_stacked_outlines(label: Label) -> void:
    # Outer outline — wide, dark
    label.add_theme_constant_override("outline_size", 6)
    label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))

    # Shadow (counts as a second layered effect)
    label.add_theme_constant_override("shadow_offset_x", 2)
    label.add_theme_constant_override("shadow_offset_y", 2)
    label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.5))
```

```csharp
public void ApplyStackedOutlines(Label label)
{
    // Outer outline — wide, dark
    label.AddThemeConstantOverride("outline_size", 6);
    label.AddThemeColorOverride("font_outline_color", new Color(0f, 0f, 0f, 0.9f));

    // Shadow (second layered effect)
    label.AddThemeConstantOverride("shadow_offset_x", 2);
    label.AddThemeConstantOverride("shadow_offset_y", 2);
    label.AddThemeColorOverride("font_shadow_color", new Color(0f, 0f, 0f, 0.5f));
}
```

`RichTextLabel`의 경우, BBCode를 테마 오버라이드와 조합해 겹친 효과를 적용할 수도 있다:

```gdscript
# RichTextLabel with multiple outline-style effects via BBCode + theme
$RichTextLabel.text = "[outline size=4 color=#000000]Level Up![/outline]"
# Additional layers are set via theme overrides on the node as above.
```

> **에디터 워크플로:** 겹친 효과는 **Theme Editor → Label → Constants**로, 또는 Font 리소스에 여러 `FontFile`식 외곽선 패스를 추가해 가장 쉽게 구성한다. 위의 런타임 API(`add_theme_*_override`)는 동적 시나리오에 동작한다.

---

## 10. 체크리스트

- [ ] 루트 UI `Control`이 앵커 프리셋 **Full Rect**(또는 레이아웃에 맞는 프리셋)를 가진다
- [ ] 모든 상호작용 위젯(`Button`, `LineEdit`, `Slider`)이 `focus_mode = FOCUS_ALL`을 가진다
- [ ] 장식 노드(`Label`, `TextureRect`)가 `focus_mode = FOCUS_NONE`을 가진다
- [ ] 비선형 레이아웃에서 게임패드 내비가 올바로 순환하도록 focus neighbour가 배선됐다
- [ ] 각 화면의 `_ready()`에서 첫 상호작용 위젯에 `grab_focus()`가 호출된다
- [ ] 일시정지 메뉴 루트 `Control`이 `process_mode = PROCESS_MODE_ALWAYS`를 가진다
- [ ] 화면 루트에 `Theme` 리소스 하나가 할당됨 — 모든 자식에 복제되지 않음
- [ ] 단순 단색 패널에는 이미지 에셋 대신 `StyleBoxFlat`을 씀
- [ ] 노드별 오버라이드에는 새 `Theme` 전체를 할당하는 대신 `add_theme_*_override()`를 씀
- [ ] 레이아웃에 수동 `position` 값 대신 컨테이너(`VBoxContainer`, `HBoxContainer` 등)를 씀
- [ ] 0으로 접히면 안 되는 위젯에 `custom_minimum_size`가 설정됨
- [ ] 슬라이더·볼륨 코드가 오디오 버스에 매핑한 원시 선형 값이 아니라 `linear_to_db` / `db_to_linear`를 씀
- [ ] 시그널이 `_ready()`에서(또는 에디터로) 연결됨; `_process`에서 UI 상태를 폴링하지 않음
- [ ] `TabContainer`의 탭 순서가 논리적 읽기/내비 순서와 일치함
- [ ] 아코디언식 접이 패널이 수동 Button + VBoxContainer 배선 대신 `FoldableContainer`를 씀 (Godot 4.5+)
- [ ] `Label`/`RichTextLabel`의 다중 외곽선/그림자 레이어가 복제 노드 대신 겹친 테마 오버라이드를 씀 (Godot 4.5+)
