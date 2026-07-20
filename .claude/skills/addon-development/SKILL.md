---
name: addon-development
description: Godot 에디터 플러그인을 만들 때 사용한다 — EditorPlugin, @tool 스크립트, 커스텀 인스펙터, 도크 패널
---

# Godot 4.3+의 애드온 개발

에디터 플러그인은 Godot 에디터 자체를 확장한다: 커스텀 노드 타입, 인스펙터 패널, 도크 위젯, 3D 기즈모, 툴바 버튼. 모든 예제는 Godot 4.3+를 대상으로 하며 폐기된 API를 쓰지 않는다.

> **관련 스킬:** 커스텀 Resource 에디터는 **resource-pattern**, 에디터 패널 UI는 **godot-ui**, C# 플러그인 개발은 **csharp-godot**을 참고하라.

---

## 1. 플러그인 구조

모든 플러그인은 프로젝트 루트의 `addons/` 안에 있다. Godot은 `plugin.cfg` 파일을 스캔해 플러그인을 발견한다.

```
res://
└── addons/
    └── my_plugin/
        ├── plugin.cfg          # required — plugin metadata
        ├── plugin.gd           # main EditorPlugin script (named in plugin.cfg)
        ├── my_inspector.gd     # optional — EditorInspectorPlugin
        ├── my_dock.tscn        # optional — dock panel scene
        └── icons/
            └── my_node.svg     # optional — custom node icons
```

`plugin.cfg`는 평범한 INI 파일이다. Godot은 `addons/`를 스캔할 때 이를 읽는다. `script` 키는 플러그인 폴더 기준 상대 경로로 메인 플러그인 스크립트를 가리켜야 한다.

플러그인 활성화: **Project → Project Settings → Plugins** → 플러그인 이름 옆 체크박스를 체크한다.

---

## 2. @tool 어노테이션

`@tool`은 GDScript(또는 그 C# 등가물)를 런타임뿐 아니라 에디터 프로세스 안에서도 실행되게 한다. 이것이 없으면 스크립트는 게임이 실행 중일 때만 돌아간다.

### GDScript

```gdscript
@tool
extends Sprite2D

# Engine.is_editor_hint() is true when running inside the editor,
# false during a running game. Use it to guard editor-only logic.
func _process(delta: float) -> void:
    if Engine.is_editor_hint():
        # This block runs in the editor viewport — safe to call editor APIs.
        update_configuration_warnings()
    else:
        # Normal game logic here.
        pass


# _get_configuration_warnings() returns an array of strings shown as
# yellow warning icons on the node in the Scene panel.
func _get_configuration_warnings() -> PackedStringArray:
    var warnings := PackedStringArray()
    if texture == null:
        warnings.append("Texture is not set. Assign a Texture2D in the Inspector.")
    return warnings
```

### C#

```csharp
#if TOOLS
using Godot;

[Tool]
public partial class MyToolSprite : Sprite2D
{
    public override void _Process(double delta)
    {
        if (Engine.IsEditorHint())
        {
            // Editor-only logic — safe to call editor APIs here.
            UpdateConfigurationWarnings();
        }
        else
        {
            // Normal game logic.
        }
    }

    public override string[] _GetConfigurationWarnings()
    {
        if (Texture == null)
            return new[] { "Texture is not set. Assign a Texture2D in the Inspector." };
        return System.Array.Empty<string>();
    }
}
#endif
```

> C# tool 스크립트는 `#if TOOLS` / `#endif`로 감싸 익스포트 빌드에 클래스가 포함되지 않게 하라. GDScript `@tool` 스크립트는 익스포트에서 자동으로 제외된다.

**핵심 규칙:**
- 에디터 접근이 필요한 모든 스크립트 맨 위에 `@tool` / `[Tool]`을 붙인다.
- 씬이 완전히 로드되기 전에 처리가 시작돼 에디터가 크래시하는 것을 막으려면 런타임 전용 코드를 항상 `Engine.is_editor_hint()`로 가드한다.
- 경고 상태에 영향을 줄 수 있는 속성이 바뀔 때마다 `update_configuration_warnings()`를 호출한다.

---

## 3. EditorPlugin 기반

메인 플러그인 스크립트는 `EditorPlugin`을 상속한다. Godot은 플러그인이 활성화될 때 `_enter_tree()`를, 비활성화되거나 프로젝트가 닫힐 때 `_exit_tree()`를 호출한다. **`_enter_tree()`에서 추가한 모든 것은 `_exit_tree()`에서 제거해야 한다.**

### GDScript

```gdscript
# plugin.gd
@tool
extends EditorPlugin


func _enter_tree() -> void:
    # Register a custom node type. The editor shows MyNode in the
    # "Add Node" dialog under the chosen base class, with a custom icon.
    add_custom_type(
        "MyNode",                              # name shown in editor
        "Node2D",                              # base class to extend
        preload("res://addons/my_plugin/my_node.gd"),
        preload("res://addons/my_plugin/icons/my_node.svg")
    )

    # Add a menu item to the Project menu (top toolbar).
    add_tool_menu_item("My Plugin Action", _on_tool_menu_item)


func _exit_tree() -> void:
    remove_custom_type("MyNode")
    remove_tool_menu_item("My Plugin Action")


func _on_tool_menu_item() -> void:
    print("My Plugin Action triggered")
```

### C#

```csharp
// Plugin.cs
#if TOOLS
using Godot;

[Tool]
public partial class MyPlugin : EditorPlugin
{
    public override void _EnterTree()
    {
        AddCustomType(
            "MyNode",
            "Node2D",
            GD.Load<Script>("res://addons/my_plugin/MyNode.cs"),
            GD.Load<Texture2D>("res://addons/my_plugin/icons/my_node.svg")
        );

        AddToolMenuItem("My Plugin Action", new Callable(this, MethodName.OnToolMenuAction));
    }

    public override void _ExitTree()
    {
        RemoveCustomType("MyNode");
        RemoveToolMenuItem("My Plugin Action");
    }

    private void OnToolMenuAction()
    {
        GD.Print("My Plugin Action triggered");
    }
}
#endif
```

**add_custom_type 파라미터:**

| 파라미터 | 설명 |
|---|---|
| `name` | Add Node 대화창에 표시되는 이름 |
| `base` | Godot 베이스 클래스의 문자열 이름 |
| `script` | GDScript / C# 스크립트 리소스 |
| `icon` | `Texture2D`, 보통 16×16 SVG |

**add_tool_menu_item**은 상단 메뉴 바의 **Project** 아래에 항목을 추가한다. 인자를 받지 않는 `Callable`을 전달한다.

### 저장 안 된 상태 & 스크립트 에디터 제어 (Godot 4.7+)

Godot 4.7은 빌드/익스포트 도구화에 유용한 파일 관리 API를 추가한다 — 액션을 실행하기 전에 저장되지 않은 작업을 확인하거나, 외부 도구가 변경한 스크립트를 새로 고친다.

```gdscript
func _run_pre_build_check() -> void:
    var unsaved_scenes := EditorInterface.get_unsaved_scenes()  # PackedStringArray of scene paths
    var script_editor := EditorInterface.get_script_editor()
    var unsaved_files := script_editor.get_unsaved_files()      # PackedStringArray of script paths
    if not unsaved_scenes.is_empty() or not unsaved_files.is_empty():
        push_warning("Unsaved work detected — save before building.")

    script_editor.save_all_scripts()   # saves every open script
    script_editor.reload_open_files()  # re-read files changed outside the editor
    # Closes the tab, discarding unsaved changes; OK or ERR_FILE_NOT_FOUND.
    var err := script_editor.close_file("res://addons/my_plugin/generated.gd")
```

```csharp
#if TOOLS
private void RunPreBuildCheck()
{
    string[] unsavedScenes = EditorInterface.Singleton.GetUnsavedScenes();
    var scriptEditor = EditorInterface.Singleton.GetScriptEditor();
    string[] unsavedFiles = scriptEditor.GetUnsavedFiles();
    if (unsavedScenes.Length > 0 || unsavedFiles.Length > 0)
        GD.PushWarning("Unsaved work detected — save before building.");

    scriptEditor.SaveAllScripts();
    scriptEditor.ReloadOpenFiles();
    Error err = scriptEditor.CloseFile("res://addons/my_plugin/Generated.cs");
}
#endif
```

---

## 4. 커스텀 인스펙터 플러그인

특정 타입의 exported 속성에 커스텀 위젯을 두고 싶다면 메인 `EditorPlugin`에서 `EditorInspectorPlugin`을 등록한다. 인스펙터 플러그인은 참여를 선택하는 `_can_handle`과 커스텀 위젯을 주입하는 `_parse_property`(또는 `_parse_begin`)를 재정의한다. 실제 UI를 위해 `EditorProperty` 서브클래스와 짝지어라.

> **Godot 4.7+:** 정적 `EditorInspector.create_default_inspector(filter_line_edit: LineEdit = null)`는 에디터의 Inspector 도크와 같은 구성의 인스펙터를 반환해 플러그인 UI에 바로 임베드할 수 있다 — 실시간 속성 필터링을 위해 `LineEdit`을 전달한다. 또한 `EditorContextMenuPlugin`이 `ContextMenuSlot`에 `CONTEXT_SLOT_INSPECTOR_PROPERTY`를 얻어, 컨텍스트 메뉴 플러그인이 인스펙터 속성 우클릭 메뉴를 확장할 수 있다: `_popup_menu()`는 `[object ID, property name]`을 받고 옵션 콜백은 `EditorProperty`를 직접 받는다.

---

## 5. 커스텀 도크 패널

`EditorPlugin._enter_tree`에서 `add_control_to_dock(slot, control)`을 호출해 에디터에 커스텀 도크를 추가한다. `_exit_tree`에서 컨트롤을 해제한다. 프로젝트 전역 도구 UI(레벨 브라우저, 에셋 요약, 빌드 대시보드)에 유용하다.

---

## 6. 커스텀 Resource 에디터

`EditorResourcePicker`는 속성을 특정 Resource 서브클래스로 제한하고 툴팁과 베이스 타입 필터를 제공한다. `EditorResourcePreviewGenerator`는 FileSystem 도크와 인스펙터에서 리소스의 커스텀 썸네일을 제공한다.

---

## 7. 기즈모

`EditorNode3DGizmoPlugin`은 에디터에서 3D 노드용 시각 핸들을 추가한다 — 와이어프레임 도형, 드래그 가능한 핸들, 회전 링. `_init`(머티리얼), `_get_gizmo_name`, `_has_gizmo`, `_redraw`(선/핸들 그리기), 인터랙티브 편집용 `_get_handle_value` / `_set_handle` / `_commit_handle`을 구현한다.

> **Godot 4.7+:** `_can_commit_handle_on_click() -> bool`(재정의하지 않으면 `false` 반환)을 재정의하면 최종 핸들 위치가 초기 위치와 같을 때에도 — 즉 평범한 클릭에서도 — 핸들 액션을 커밋한다.

---

## 8. 플러그인 테스트

### 에디터에서 플러그인 리로드

Godot을 재시작하지 않고 플러그인 코드를 리로드하는 가장 빠른 방법:

1. **Project → Project Settings → Plugins** → 플러그인 체크 해제 → 다시 체크.
2. 또는 **Editor → Execute Script**나 에디터 콘솔에서 다음을 실행:

```gdscript
var plugin_name := "my_plugin"
ProjectSettings.set_setting("editor_plugins/enabled", [])
ProjectSettings.save()
# Re-enable via the Plugins dialog.
```

더 빠른 반복을 위해 플러그인 스크립트를 저장하면 — Godot은 `@tool` 스크립트를 자동으로 핫 리로드한다. 복잡한 변경(새 클래스 등록, 도크 변경)은 완전한 비활성화/활성화 사이클이 필요하다.

### print로 디버깅

`print()`와 `push_error()` / `push_warning()`은 Godot **Output** 패널로, 그리고 Godot을 터미널에서 실행했을 때는 OS 콘솔로 출력된다.

```gdscript
func _enter_tree() -> void:
    print("[my_plugin] _enter_tree called")   # Output panel
    push_warning("[my_plugin] something unexpected")
    push_error("[my_plugin] something failed")  # also shown as red in Output
```

```csharp
// C# equivalent — same Output panel, same OS console.
#if TOOLS
public override void _EnterTree()
{
    GD.Print("[my_plugin] _EnterTree called");      // Output panel
    GD.PushWarning("[my_plugin] something unexpected");
    GD.PushError("[my_plugin] something failed");   // also shown as red in Output
}
#endif
```

> **C# 플러그인 리로드 주의:** GDScript과 달리 C# 플러그인은 재컴파일이 필요하다. C# 플러그인 소스를 편집한 뒤에는 재활성화하기 전에 에디터가 어셈블리를 다시 빌드해야 한다. 플러그인이 `Could not find type "Plugin"`으로 로드에 실패하면 C# 프로젝트 컴파일이 실패한 것이다 — 에디터 하단의 **MSBuild Panel**에서 컴파일 오류를 확인하라. `[Tool]` 스크립트에서 프로그램적으로 플러그인을 리로드하는 방법:

```csharp
#if TOOLS
[Tool]
public partial class PluginReloader : EditorScript
{
    public override void _Run()
    {
        var pluginName = "my_plugin";
        // Disable then re-enable to force a clean reload cycle.
        EditorInterface.Singleton.SetPluginEnabled(pluginName, false);
        EditorInterface.Singleton.SetPluginEnabled(pluginName, true);
        GD.Print($"Plugin {pluginName} reloaded.");
    }
}
#endif
```

Windows에서 OS 콘솔을 보이며 실행하려면:

```
godot.exe --editor --path /path/to/project
```

### 플러그인 수명 주기 함정

| 상황 | 무슨 일이 일어나나 | 해결 |
|---|---|---|
| 플러그인은 활성이지만 `_enter_tree`가 크래시 | 플러그인이 활성이지만 망가진 상태로 남음; 에디터가 불안정할 수 있음 | 비활성화, 수정, 재활성화 |
| `_exit_tree`에서 도크 제거를 잊음 | 비활성화 후에도 고아 도크가 살아남음; 다음 활성화 때 도크 중복 | `_exit_tree`에서 항상 null 체크 후 `queue_free()` |
| 제거 후에도 커스텀 타입이 목록에 남음 | 프로젝트의 `plugin_types` 캐시에 낡은 엔트리 | `remove_custom_type` 후 에디터를 한 번 재시작 |
| `@tool` 스크립트가 속성 설정 시 크래시 | 에디터가 오류를 보이지만 스크립트가 갱신을 멈춤 | `if Engine.is_editor_hint()`로 가드하고 입력을 검증 |
| C# 플러그인 컴파일 안 됨 | 플러그인 전체가 조용히 로드 실패 | **Mono → Build Project** 출력을 확인하고 C# 오류부터 수정 |
| `add_inspector_plugin`을 두 번 호출 | 인스펙터 플러그인이 속성마다 두 번 발동 | 추적하고 `add_inspector_plugin` 전에 null 체크로 가드 |

---

## 9. plugin.cfg 형식

`plugin.cfg`는 플러그인 폴더 루트에 놓인 평범한 INI 파일이다. `[plugin]` 섹션의 모든 필드는 `dependencies`와 `installs`를 제외하고 필수다.

```ini
[plugin]

name="My Plugin"
description="Adds MyNode, a custom inspector, and a dock panel to the editor."
author="Your Name"
version="1.0.0"
script="plugin.gd"
```

**필드 레퍼런스:**

| 키 | 타입 | 설명 |
|---|---|---|
| `name` | String | Project Settings → Plugins에 표시되는 이름 |
| `description` | String | Plugins 패널에 표시되는 짧은 요약 |
| `author` | String | 작성자 이름 또는 조직 |
| `version` | String | 시맨틱 버전 문자열 (예: `"1.2.0"`) |
| `script` | String | 메인 `EditorPlugin` 스크립트 경로, **플러그인 폴더 기준 상대 경로** |

**모든 선택 필드를 포함한 완전한 예제:**

```ini
[plugin]

name="My Plugin"
description="Adds MyNode, a custom inspector, and a dock panel to the editor."
author="Your Name"
version="1.0.0"
script="plugin.gd"
```

> Godot 4.x `plugin.cfg`에는 다른 표준 키가 없다. 의존성 관리는 외부에서(예: Asset Library나 수동 설치 안내로) 처리된다.

---

## 10. 체크리스트

- [ ] `addons/<plugin_name>/plugin.cfg`가 `name`, `description`, `author`, `version`, `script`와 함께 존재한다
- [ ] 메인 스크립트가 `EditorPlugin`을 상속하고 `@tool`(GDScript) 또는 `#if TOOLS` 안의 `[Tool]`(C#)로 장식돼 있다
- [ ] `_enter_tree()`에서 등록한 모든 것이 `_exit_tree()`에서 해제된다
- [ ] 커스텀 노드 타입은 일치하는 아이콘 SVG와 함께 `add_custom_type` / `remove_custom_type`을 쓴다
- [ ] `@tool` 스크립트는 에디터 전용 코드를 `Engine.is_editor_hint()`로 가드한다
- [ ] 노드가 잘못 구성됐을 때 `_get_configuration_warnings()`가 비어 있지 않은 배열을 반환한다
- [ ] 인스펙터 플러그인은 의도치 않은 타입을 처리하지 않도록 `_can_handle`을 구현한다
- [ ] `_parse_property`는 커스텀 에디터가 필요한 속성에만 `true`를 반환한다
- [ ] 도크 씬은 기본 도크 폭에서도 쓸 수 있도록 `Custom Minimum Size`가 설정돼 있다
- [ ] 도크 `Control`은 `_exit_tree()`에서 `queue_free()`로 해제된다
- [ ] `EditorResourcePreviewGenerator`는 `EditorInterface.get_resource_previewer()`를 통해 추가·제거 둘 다 된다
- [ ] 기즈모 플러그인은 핸들 드래그가 undo 가능하도록 `get_undo_redo()`와 함께 `_commit_handle`을 구현한다
- [ ] 구조적 변경마다 완전한 비활성화/활성화 사이클로 플러그인을 테스트했다
- [ ] 모든 `_enter_tree` 설정 경로에서 조용한 실패 대신 `push_error()`를 쓴다
- [ ] C# 플러그인 스크립트를 `#if TOOLS` / `#endif`로 감쌌다
