---
name: dialogue-system
description: 대화를 구현할 때 쓴다 — 분기 대화·조건을 위한 데이터 구조와 UI 표현
---

# Godot 4.3+ 대화 시스템

모든 예제는 Godot 4.3+를 대상으로 하며 폐기된 API를 쓰지 않는다. GDScript를 먼저, 이어서 C#을 보인다.

> **관련 스킬:** 대화 데이터를 Resource로 다루는 것은 **resource-pattern**, Control 노드 레이아웃은 **godot-ui**, 대화 흐름 관리는 **state-machine**, 대화 상태 저장은 **save-load**.

---

## 1. 아키텍처 개요

```
┌─────────────────────────────────────────────────────────┐
│                        UI Layer                         │
│   DialogueUI (Control)                                  │
│     ├─ Label (speaker_name)                             │
│     ├─ TextureRect (portrait)                           │
│     ├─ RichTextLabel (dialogue_text, typewriter effect) │
│     └─ VBoxContainer (choice_container)                 │
│           └─ Button × N (choice buttons)                │
│                                                         │
│   Connects to: line_displayed, choice_presented signals │
└───────────────────────┬─────────────────────────────────┘
                        │ drives UI via signals
┌───────────────────────▼─────────────────────────────────┐
│              DialogueManager (Autoload / Node)           │
│   start_dialogue(dialogue_data)                         │
│   advance()  → next line or end                         │
│   choose(choice_index)                                  │
│   current_line: DialogueLine (read-only)                │
│                                                         │
│   signals: dialogue_started                             │
│             line_displayed(line)                        │
│             choice_presented(choices)                   │
│             dialogue_ended                              │
└───────────────────────┬─────────────────────────────────┘
                        │ reads
┌───────────────────────▼─────────────────────────────────┐
│                   Data Layer (Resources)                 │
│   DialogueData (Resource)                               │
│     lines: Dictionary  ← id → DialogueLine              │
│     start_line_id: String                               │
│                                                         │
│   DialogueLine (Resource)                               │
│     speaker, text, choices, next_line_id, condition     │
└─────────────────────────────────────────────────────────┘
```

---

## 2. DialogueLine 리소스

`DialogueLine`은 대화 한 박자의 모든 데이터를 담는다. choices가 `Array[Dictionary]`이므로 각 항목이 별도 클래스 없이 `text`, `next_line_id`, 선택적 `condition`을 실을 수 있다.

### GDScript

```gdscript
# dialogue_line.gd
class_name DialogueLine
extends Resource

## Display name shown in the UI speaker box.
@export var speaker: String = ""

## The body text. Supports BBCode and variable placeholders: {player_name}.
@export_multiline var text: String = ""

## When non-empty, overrides next_line_id. Each Dictionary must have:
##   "text"        : String   — label on the choice button
##   "next_line_id": String   — line to jump to when chosen
##   "condition"   : String   — (optional) expression; omit or "" to always show
@export var choices: Array = []

## ID of the next DialogueLine. Ignored when choices is non-empty.
@export var next_line_id: String = ""

## Optional condition expression evaluated before displaying this line.
## If the expression returns false the manager skips to next_line_id.
## Example: "GameState.has_item('key')"
@export var condition: String = ""
```

### C#

```csharp
// DialogueLine.cs
using Godot;
using Godot.Collections;

[GlobalClass]
public partial class DialogueLine : Resource
{
    /// <summary>Display name shown in the speaker box.</summary>
    [Export] public string Speaker     { get; set; } = "";

    /// <summary>Body text. Supports BBCode and {variable} placeholders.</summary>
    [Export(PropertyHint.MultilineText)]
    public string Text                 { get; set; } = "";

    /// <summary>
    /// When non-empty, overrides NextLineId. Each Dictionary entry must contain:
    ///   "text"         : string  — choice button label
    ///   "next_line_id" : string  — line to jump to
    ///   "condition"    : string  — (optional) expression; omit or "" to always show
    /// </summary>
    [Export] public Array Choices      { get; set; } = new();

    /// <summary>ID of the next DialogueLine. Ignored when Choices is non-empty.</summary>
    [Export] public string NextLineId  { get; set; } = "";

    /// <summary>
    /// Optional condition expression. Evaluated before displaying this line.
    /// Example: "GameState.HasItem(\"key\")"
    /// </summary>
    [Export] public string Condition   { get; set; } = "";
}
```

---

## 3. DialogueData 리소스

`DialogueData`는 모든 line을 문자열 ID로 키를 매긴 딕셔너리로 담는 컨테이너 Resource다. `.tres` 파일로 만들면 Inspector에서 NPC에 할당할 수 있다.

### GDScript

```gdscript
# dialogue_data.gd
class_name DialogueData
extends Resource

## Dictionary mapping line ID strings to DialogueLine resources.
## Example: { "intro": <DialogueLine>, "ask_quest": <DialogueLine> }
@export var lines: Dictionary = {}

## ID of the first line to display when dialogue starts.
@export var start_line_id: String = ""


## Convenience accessor — returns null for unknown IDs.
func get_line(id: String) -> DialogueLine:
    return lines.get(id, null)
```

### C#

```csharp
// DialogueData.cs
using Godot;
using Godot.Collections;

[GlobalClass]
public partial class DialogueData : Resource
{
    /// <summary>Maps line ID strings to DialogueLine resources.</summary>
    [Export] public Dictionary Lines        { get; set; } = new();

    /// <summary>ID of the first line to display when dialogue starts.</summary>
    [Export] public string StartLineId      { get; set; } = "";

    /// <summary>Returns the DialogueLine for id, or null if not found.</summary>
    public DialogueLine GetLine(string id)
    {
        if (Lines.ContainsKey(id))
            return Lines[id].As<DialogueLine>();
        return null;
    }
}
```

> `lines`는 문자열 키와 `DialogueLine` 리소스 값의 Dictionary 항목을 추가해 Inspector에서 채우거나, JSON에서 프로그래밍으로 로드하라(7절 참고).

---

## 4. DialogueManager

싱글톤 오토로드가 활성 `DialogueData`를 소유하고 현재 line ID를 추적한다. `start(data)`가 데이터를 설정하고 첫 line을 emit하며; `advance(choice_index)`가 앞으로 나아간다. 세 시그널을 연결한다: `line_changed(line)`, `choices_presented(choices)`, `dialogue_ended()`.

---

## 5. 분기와 조건

선택지는 `DialogueLine.choices`(Dictionary의 Array)에 있다. 각 선택지는 `text`, `next_line_id`, 선택적 `condition`을 갖는다. 조건은 `Expression` 클래스로 평가되는 GDScript 표현식이며 — 프로젝트 상태(예: `GameState`)를 담은 컨텍스트 객체를 넘겨받는다.

---

## 6. 대화 UI

line 본문용 `RichTextLabel`(BBCode 활성화), 화자 이름용 `Label`, 선택 버튼용 `VBoxContainer`를 갖춘 `CanvasLayer`. 타자기 효과는 `Tween`으로 구동되는 `RichTextLabel.visible_characters`로 구현한다. UI는 `DialogueManager` 시그널을 구독한다.

---

## 7. 외부 포맷

디자이너 친화적 편집을 위해 JSON에서 대화를 로드하라 — 로드 시 JSON 키를 `DialogueLine` 속성에 매핑한다. 또는 노드 그래프 에디터를 위해 **Dialogic** 애드온을 통합하라(커뮤니티 표준).

---

## 8. 변수 보간

대화 텍스트는 `{player_name}` 스타일의 플레이스홀더를 지원한다. 작은 템플릿러로 해석하라: `text.format(vars)`(GDScript) 또는 이름 태그 전처리와 함께 `string.Format`(C#).

---

## 9. 구현 체크리스트

- [ ] `DialogueLine`과 `DialogueData`가 `Resource`를 확장하고 Inspector 통합을 위해 `[GlobalClass]`(C#)를 지님
- [ ] `DialogueManager`가 Autoload로 등록되어 모든 씬이 단일 인스턴스를 공유
- [ ] `start_dialogue()`가 접근 전에 `dialogue_data`가 non-null임을 assert
- [ ] `advance()`가 선택 대기 중 호출되는 것을 방어
- [ ] `choose()`가 원시 `choices` 배열이 아니라 필터링된 visible-choices 목록에서 동작
- [ ] 조건 문자열이 안정적인 오토로드 메서드 이름만 참조 — 씬 로컬 노드 참조 회피
- [ ] `_evaluate_condition()`이 메서드 호출 해석을 위해 알려진 base 인스턴스(`GameState`)를 `Expression.execute()`에 넘김
- [ ] 타자기 타이머가 BBCode 호환을 위해 프레임별 문자열 슬라이싱이 아니라 `visible_characters`를 사용
- [ ] 타자기 도중 `ui_accept`를 누르면 전체 텍스트가 드러나고; 두 번째 누름은 line을 진행
- [ ] 선택 버튼이 새로 만들기 전에 해제됨(`queue_free`) — 낡은 자식을 절대 누적하지 않음
- [ ] JSON 로더가 파일 열기와 파싱 단계를 따로 검증하고, 각 실패에 명확한 에러 메시지를 emit
- [ ] 변수 보간이 시그널 핸들러에 흩어지지 않고 단일 `_interpolate()` 헬퍼에 집중됨
- [ ] `next_line_id = ""`가 대화 종료를 뜻함 — 빈 문자열 외 매직 센티널 문자열 없음
- [ ] 모든 `push_error()` 메시지가 로그 추적을 쉽게 하도록 클래스명과 메서드를 포함
