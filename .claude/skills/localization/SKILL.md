---
name: localization
description: 현지화(i18n/l10n)를 구현할 때 사용 — TranslationServer, CSV/PO 번역 파일, 로케일 전환, RTL 지원, Godot 4.3+의 복수형 처리
---

# Godot 4.3+의 현지화

모든 예제는 폐기된 API 없이 Godot 4.3+를 대상으로 한다. GDScript를 먼저, 그다음 C#을 보여준다.

> **관련 스킬:** Control 노드와 테마 관리는 **godot-ui**, 언어 설정 영속화는 **save-load**, 로케일별 레이아웃 조정은 **responsive-ui**를 보라.

---

## 1. 핵심 개념

### Godot 현지화가 동작하는 방식

1. **모든 사용자 대면 문자열을** `tr()`로 감싼다 — Godot의 번역 함수
2. 키를 번역 문자열에 매핑하는 **번역 파일을 만든다**(CSV 또는 PO)
3. 번역 파일을 **`Translation` 리소스로 임포트한다**
4. `TranslationServer.set_locale()`로 **런타임에 로케일을 전환한다**

`text`, `tooltip_text`, `placeholder_text` 프로퍼티를 가진 모든 `Control` 노드는 값이 번역 키와 일치하면 자동으로 번역된다.

### 번역 키 전략

| 전략 | 예시 키 | 장점 | 단점 |
|----------|-------------|------|------|
| 시맨틱 키 | `MENU_START_GAME` | 의도가 명확, 찾기 쉬움 | 기본 언어 폴백 필요 |
| 영어를 키로 | `Start Game` | 코드가 읽기 쉬움, 영어용 매핑 파일 불필요 | 영어 텍스트가 바뀌면 키가 깨짐 |

> **권장:** 프로덕션 프로젝트에는 시맨틱 키(`MENU_START_GAME`)를 써라. 영어를 키로 쓰는 방식은 프로토타입이나 1인 프로젝트에만 써라.

---

## 2. 번역 파일

### CSV 형식

가장 단순한 형식. 첫 열이 키, 이어지는 열이 로케일 코드다.

```csv
keys,en,cs,de,ja
MENU_START,Start Game,Začít hru,Spiel starten,ゲームスタート
MENU_OPTIONS,Options,Nastavení,Optionen,オプション
MENU_QUIT,Quit,Ukončit,Beenden,終了
PLAYER_HEALTH,Health: %d,Zdraví: %d,Gesundheit: %d,体力: %d
ITEM_COLLECTED,%s collected!,%s sebráno!,%s gesammelt!,%sを入手！
```

프로젝트에 `translations.csv`로 저장하라. Godot가 임포트 시 형식을 자동 감지한다.

**임포트 설정**(Import 도크):
- **Delimiter**: Comma(기본) 또는 Tab
- **Translations** 섹션: 개별 로케일 활성화/비활성화

### PO 형식 (Gettext)

업계 표준 형식. 전문 번역 팀과 Poedit, Weblate, Crowdin 같은 도구에 더 적합하다.

**POT 템플릿 생성**(`messages.pot`):

```
msgid "MENU_START"
msgstr ""

msgid "MENU_OPTIONS"
msgstr ""

msgid "MENU_QUIT"
msgstr ""

msgid "PLAYER_HEALTH"
msgstr ""
```

**로케일 파일 생성**(예: 체코어용 `cs.po`):

```
msgid "MENU_START"
msgstr "Začít hru"

msgid "MENU_OPTIONS"
msgstr "Nastavení"

msgid "MENU_QUIT"
msgstr "Ukončit"

msgid "PLAYER_HEALTH"
msgstr "Zdraví: %d"
```

### 번역 등록하기

**Project Settings → Localization → Translations → Add...** → `.csv` 또는 `.po` 파일을 선택.

또는 런타임에 등록:

```gdscript
var translation := load("res://translations/cs.po") as Translation
TranslationServer.add_translation(translation)
```

```csharp
var translation = GD.Load<Translation>("res://translations/cs.po");
TranslationServer.AddTranslation(translation);
```

> ⚠️ **Godot 4.7에서 변경:** `OptimizedTranslation.generate()`가 이제 성공을 보고하려고 `bool`을 반환한다(이전엔 `void`). GDScript 호환이며 C# 소스 호환이지만 C#에는 바이너리 비호환 — 그것을 호출하는 사전 컴파일 플러그인을 재컴파일하라. [4.7 마이그레이션 가이드](https://docs.godotengine.org/en/latest/tutorials/migrating/upgrading_to_godot_4.7.html)를 보라.

### POT 생성 훅 (Godot 4.7+)

커스텀 `EditorTranslationParserPlugin`이 `_customize_strings()` 가상 메서드를 오버라이드할 수 있다 — POT 생성 중 모든 파일이 파싱된 뒤 한 번 호출됨 — 추출된 문자열 최종 목록에서 항목을 더하거나 뺀다:

```gdscript
@tool
extends EditorTranslationParserPlugin

func _customize_strings(strings: Array[PackedStringArray]) -> Array[PackedStringArray]:
    strings.append(PackedStringArray(["Test 1", "context", "test 1 plurals", "test 1 comment"]))
    # Drop internal strings that begin with "$".
    return strings.filter(func(s): return not s[0].begins_with("$"))
```

```csharp
#if TOOLS
using System.Linq;
using Godot;

public partial class CommentAwareParser : EditorTranslationParserPlugin
{
    public override Godot.Collections.Array<string[]> _CustomizeStrings(Godot.Collections.Array<string[]> strings)
    {
        strings.Add(new[] { "Test 1", "context", "test 1 plurals", "test 1 comment" });
        // Drop internal strings that begin with "$".
        return new Godot.Collections.Array<string[]>(strings.Where(s => !s[0].StartsWith("$")));
    }
}
#endif
```

> **Godot 4.7+:** POT 생성기가 `Control.accessibility_name`과 `accessibility_description`도 추출하므로, 접근성 문자열을 수동으로 나열하지 않아도 번역 가능해진다. ([GH-117134](https://github.com/godotengine/godot/pull/117134))

---

## 3. 코드에서 tr() 쓰기

### GDScript

```gdscript
# Basic translation
var label_text: String = tr("MENU_START")  # "Start Game" or translated equivalent

# With format arguments
var health_text: String = tr("PLAYER_HEALTH") % current_health
# "Health: 85" or "Zdraví: 85"

# With string arguments
var collected_text: String = tr("ITEM_COLLECTED") % item_name
# "Sword collected!" or "Meč sebráno!"

# Pluralization (Godot 4.x)
var count := 5
var msg: String = tr_n("ONE_ENEMY", "MANY_ENEMIES", count)
# Requires PO files with plural forms
```

### C#

```csharp
string labelText = Tr("MENU_START");
string healthText = string.Format(Tr("PLAYER_HEALTH"), currentHealth);

// Pluralization
string msg = TrN("ONE_ENEMY", "MANY_ENEMIES", count);
```

### 자동 Control 번역

`Label`, `Button`, `RichTextLabel` 등 Control 노드는 `text` 프로퍼티가 번역 키와 일치하면 자동으로 번역한다. 텍스트를 키로 설정하라:

```
Button.text = "MENU_START"   → displays "Start Game" (en) or "Začít hru" (cs)
```

> **팁:** 특정 Control에 자동 번역을 원하지 않으면 그 `auto_translate_mode`를 `DISABLED`로 설정하라.

> **Godot 4.7+:** `Control.translation_context: StringName`은 컨트롤별 번역 컨텍스트를 설정한다 — 컨트롤의 표시 텍스트를 번역할 때와 번역 템플릿을 생성할 때 쓰이며, `tr()`의 컨텍스트 인자에 해당하는 프로퍼티다(C#: `TranslationContext`). ([GH-115340](https://github.com/godotengine/godot/pull/115340))

---

## 4. 런타임에 로케일 전환

### GDScript

```gdscript
# Switch language
func set_language(locale_code: String) -> void:
    TranslationServer.set_locale(locale_code)
    # All Control nodes with translation keys update automatically

# Get current locale
var current: String = TranslationServer.get_locale()  # e.g. "en", "cs", "de"

# Get available locales
var locales: PackedStringArray = TranslationServer.get_loaded_locales()
```

### C#

```csharp
public void SetLanguage(string localeCode)
{
    TranslationServer.SetLocale(localeCode);
}

string current = TranslationServer.GetLocale();
```

### 언어 선택 메뉴

```gdscript
extends Control

@onready var language_button: OptionButton = %LanguageButton

var _locales: Array[Dictionary] = [
    {"code": "en", "name": "English"},
    {"code": "cs", "name": "Čeština"},
    {"code": "de", "name": "Deutsch"},
    {"code": "ja", "name": "日本語"},
]

func _ready() -> void:
    for locale in _locales:
        language_button.add_item(locale["name"])

    # Set current selection
    var current_locale: String = TranslationServer.get_locale()
    for i in _locales.size():
        if _locales[i]["code"] == current_locale:
            language_button.selected = i
            break

    language_button.item_selected.connect(_on_language_selected)

func _on_language_selected(index: int) -> void:
    TranslationServer.set_locale(_locales[index]["code"])
    # Save preference — SettingsManager is a user-created autoload (see save-load skill)
    SettingsManager.set_setting("general", "locale", _locales[index]["code"])
```

---

## 5. 오른쪽에서 왼쪽으로(RTL) 지원

아랍어, 히브리어, 페르시아어 및 기타 RTL 언어를 위한 것.

### RTL 활성화

```gdscript
# On any Control node
control.layout_direction = Control.LAYOUT_DIRECTION_RTL

# Or set globally in Project Settings:
# Internationalization → Rendering → Text Direction → RTL
```

### 컨트롤별 설정

| 프로퍼티 | 목적 |
|----------|---------|
| `layout_direction` | `LTR`, `RTL`, `LOCALE`(현재 로케일에서 자동), `INHERITED` |
| `text_direction` | Label/RichTextLabel에서: 텍스트 방향 오버라이드 |
| `structured_text_type` | 완전히 뒤집으면 안 되는 특수 구조(URL, 파일 경로, 이메일) 처리 |

### 혼합 방향을 위한 RichTextLabel BBCode

```gdscript
# Force LTR for a number or URL inside RTL text
rich_text.text = "النتيجة: [ltr]100/200[/ltr]"
```

### C# 대응

```csharp
// LocaleAwarePanel.cs — flip layout direction whenever the locale changes.
using Godot;

public partial class LocaleAwarePanel : Control
{
    public override void _Ready()
    {
        ApplyLayoutForLocale();
        TranslationServer.Singleton.LocaleChanged += ApplyLayoutForLocale;
    }

    public override void _ExitTree()
    {
        // TranslationServer outlives every scene — without this unsubscribe,
        // each panel instance leaks a delegate reference for the lifetime of the process.
        TranslationServer.Singleton.LocaleChanged -= ApplyLayoutForLocale;
    }

    private void ApplyLayoutForLocale()
    {
        string locale = TranslationServer.Singleton.GetLocale();
        bool isRtl = TextServerManager.GetPrimaryInterface().IsLocaleRightToLeft(locale);
        LayoutDirection = isRtl
            ? Control.LayoutDirectionEnum.Rtl
            : Control.LayoutDirectionEnum.Ltr;
    }
}

// RichTextLabel mixed-direction example — same BBCode as GDScript, just assigned in C#.
public partial class ScoreLabel : RichTextLabel
{
    public void SetArabicScore(int score, int max)
    {
        BbcodeEnabled = true;
        Text = $"النتيجة: [ltr]{score}/{max}[/ltr]";
    }
}
```

### 폰트 요구사항

RTL 문자는 해당 유니코드 범위를 지원하는 폰트가 필요하다. Godot의 기본 폰트는 아랍어/히브리어를 커버하지 않는다. Noto Sans Arabic 같은 폰트를 임포트해 Theme으로 할당하라.

---

## 6. 로케일 인식 서식

### 숫자

```gdscript
# Format numbers with locale-appropriate separators
var formatted: String = "%d" % 1234567
# Always outputs "1234567" — GDScript doesn't locale-format numbers

# For locale-aware number formatting, use a helper:
func format_number(value: int) -> String:
    var s := str(value)
    var result := ""
    var count := 0
    for i in range(s.length() - 1, -1, -1):
        if count > 0 and count % 3 == 0:
            result = "," + result  # or "." for European locales
        result = s[i] + result
        count += 1
    return result
```

### 날짜와 시간

Godot는 내장 로케일 인식 날짜 서식을 제공하지 않는다. `Time.get_datetime_dict_from_system()`을 쓰고 로케일별로 수동 서식화하라.

### C#

```csharp
using Godot;
using System.Globalization;

public partial class LocaleFormatter : Node
{
    public string FormatNumber(double value)
    {
        var culture = CultureInfo.GetCultureInfo(TranslationServer.GetLocale().Replace("_", "-"));
        return value.ToString("N", culture);
    }

    // FormatCurrency and FormatDate follow the same pattern — same culture lookup,
    // ToString("C", culture) and ToString("d", culture) respectively.
}
```

---

## 7. 프로젝트 조직

### 권장 파일 구조

```
res://
├── translations/
│   ├── game.csv           # Main game translations
│   ├── ui.csv             # UI-specific translations
│   └── items.csv          # Item names and descriptions
├── fonts/
│   ├── default_font.ttf   # Latin, Cyrillic
│   └── cjk_font.ttf       # Chinese, Japanese, Korean
└── themes/
    └── default_theme.tres  # Font assignments per locale if needed
```

### 번역 키 규약

```
# Category_Context_Description
MENU_MAIN_START          # Main menu, start button
MENU_MAIN_QUIT           # Main menu, quit button
HUD_HEALTH_LABEL         # In-game HUD, health label
DIALOGUE_NPC_GREETING    # NPC dialogue, greeting line
ITEM_SWORD_NAME          # Inventory item name
ITEM_SWORD_DESC          # Inventory item description
```

---

## 8. 흔한 함정

| 증상 | 원인 | 해결 |
|---------|-------|-----|
| 텍스트 대신 번역 키가 보임 | Project Settings에 번역 파일이 등록 안 됨 | Project Settings → Localization → Translations에 추가 |
| 로케일 전환 시 텍스트가 갱신 안 됨 | `tr()` 대신 문자열 리터럴 사용 | 모든 사용자 대면 문자열을 `tr()`로 감쌈 |
| 씬 전환 후 라벨에 키가 보임 | 번역 리소스가 아직 로드 안 됨 | 번역을 (런타임이 아닌) Project Settings에 등록 |
| RTL 텍스트가 LTR로 렌더됨 | `layout_direction` 미설정 | 루트 Control에 `RTL` 또는 `LOCALE`로 설정 |
| 폰트가 문자를 표시 안 함 | 폰트에 유니코드 범위 누락 | 대상 문자를 커버하는 폰트 임포트(Noto Sans 권장) |
| CSV로 복수형이 동작 안 함 | CSV가 복수형을 지원 안 함 | 복잡한 복수 규칙 언어에는 PO 형식 사용 |
| 번역의 `%s`가 리터럴 `%s`로 보임 | `tr()` 결과를 서식화하지 않고 키로 사용 | `tr("KEY" % value)`가 아닌 `tr("KEY") % value` 사용 |

---

## 9. 에디터 로케일 미리보기 (Godot 4.5+)

Godot 4.5는 에디터에 실시간 로케일 미리보기를 추가한다. 게임을 실행하지 않고도 UI가 구성된 임의의 로케일에서 어떻게 보이는지 — 번역 텍스트, RTL 레이아웃, 폰트 변경 — 볼 수 있다.

### 사용 방법

1. **Project → Project Settings → Internationalization**을 연다.
2. **Preview Language** 드롭다운을 찾는다.
3. 등록된 번역 목록에서 로케일을 선택한다(예: `ja`, `cs`, `ar`).
4. 에디터 뷰포트가 선택한 로케일을 반영해 즉시 갱신된다.

### 이점

- Play 모드에 들어가지 않고 긴 번역 텍스트로 인한 레이아웃 문제를 식별.
- 아랍어, 히브리어, 페르시아어의 RTL 레이아웃 방향을 확인.
- 텍스트 프로퍼티를 가진 모든 Control 노드가 `tr()` 키로 제대로 감싸졌는지 확인(번역 안 된 키는 비영어 미리보기에서 그대로 나타난다).
- 더 빠른 번역 QA — 에디터에서 바로 반복.

> **Preview Language** 드롭다운에서 빈 항목이나 `en`을 선택해 기본 로케일로 초기화하라. 미리보기는 에디터에서만 적용되며 익스포트 빌드에는 영향을 주지 않는다.

---

## 10. CSV 복수형 및 컨텍스트 지원 (Godot 4.6+)

Godot 4.6은 CSV 번역 형식에 세 개의 선택적 헤더 열 — `?context`, `?plural`, `?pluralrule` — 을 확장해, 컨텍스트 명확화와 단순한 one/other 복수형(이전엔 PO 전용)을 CSV에 가져온다. 복수형이 셋 이상인 언어(러시아어, 폴란드어, 아랍어)에는 완전한 `msgstr[n]` 복수 배열이 있는 PO 형식을 계속 써라.

---

## 11. 구현 체크리스트

- [ ] 모든 사용자 대면 문자열이 `tr()`을 씀(또는 Control 노드에 번역 키로 설정됨)
- [ ] 번역 파일(CSV 또는 PO)이 Project Settings → Localization → Translations에 등록됨
- [ ] `TranslationServer.set_locale()`로 런타임에 언어 전환 가능
- [ ] 언어 설정이 저장되고 게임 실행 시 복원됨
- [ ] 폰트가 모든 대상 언어 문자 집합(라틴, CJK, 아랍어 등)을 커버함
- [ ] RTL 언어가 루트 UI 컨테이너에 `layout_direction`을 `RTL` 또는 `LOCALE`로 설정함
- [ ] 서식 문자열(`%s`, `%d`)이 `tr()` 앞이 아니라 뒤에 적용됨
- [ ] 번역 키가 일관된 명명 규약을 따름
- [ ] UI 레이아웃이 언어별 더 길고/짧은 텍스트에 적응함(하드코딩된 너비 없음)
- [ ] 복잡한 복수 규칙 언어에 PO 형식이 쓰임
- [ ] 테스트 실행 대신 번역 QA에 에디터 로케일 미리보기(Project Settings → Internationalization → Preview Language)를 씀 (Godot 4.5+)
- [ ] 같은 키가 다른 UI 컨텍스트에서 다른 의미일 때 CSV `?context` 열을 씀 (Godot 4.6+)
- [ ] CSV 워크플로에서 단순 one/other 복수형에 CSV `?plural` / `?pluralrule` 열을 씀; 복수형이 3개 이상인 언어에는 PO 형식을 씀 (Godot 4.6+)
