---
name: godot-testing
description: Godot 프로젝트 테스트를 작성할 때 사용 — GUT와 gdUnit4를 쓰는 TDD 워크플로, GDScript와 C# 모두 다룸
---

# Godot Testing

이 스킬은 GUT(Godot Unit Testing)와 gdUnit4를 써서 Godot 4.3+ 프로젝트를 위한 테스트 주도 개발(TDD)을 다룬다. 프레임워크 선택, 완전한 RED-GREEN-REFACTOR 예제, 테스트 구조, CI에서 테스트 실행, 흔한 테스트 패턴을 포함한다.

> **관련 스킬:** 리뷰 체크리스트는 **godot-code-review**, 테스트 친화적 아키텍처는 **dependency-injection**, CI/CD 테스트 자동화는 **export-pipeline**을 보라.

## 프레임워크 선택

| 기능                  | GUT                              | gdUnit4                           |
|-----------------------|----------------------------------|-----------------------------------|
| 언어                  | GDScript 우선, C# 제한적          | GDScript + C# (일급 지원)          |
| 설치                  | AssetLib 또는 git submodule       | AssetLib 또는 git submodule        |
| 에디터 통합           | 내장 GUT 패널                     | 내장 인스펙터 + 패널               |
| 모킹                  | `double()` / `stub()` API        | `mock()` / `spy()` API            |
| 씬 테스트             | `add_child_autofree()`           | `auto_free()` + scene runner       |
| CI 지원               | `gut_cmdln.gd` CLI 스크립트       | `gdunit4_runner` CLI 스크립트      |
| C# 지원               | 최소한 (GDScript 래퍼만)          | 네이티브 C# 단언 + 생명주기        |
| 성숙도                | 확립됨 (Godot 3 + 4)             | Godot 4 집중, 활발히 갱신됨        |
| 적합한 대상           | 순수 GDScript 프로젝트            | GDScript/C# 혼합 또는 C# 전용      |

**어림잡는 규칙:** GDScript 전용 프로젝트에는 GUT를 써라. C# 프로젝트거나 일급 C# 지원과 scene runner 유틸리티가 필요하면 gdUnit4를 써라.

---

## TDD 워크플로: RED-GREEN-REFACTOR

표준 테스트 주도 개발 사이클: 실패하는 테스트를 쓰고(RED), 통과할 최소한의 코드를 쓰고(GREEN), 테스트를 깨지 않고 리팩터한다. 각 단계에는 고유한 규율이 있다 — RED를 건너뛰지 마라(사소하게 통과하는 테스트를 쓰게 된다), REFACTOR도 건너뛰지 마라(기술 부채가 쌓인다).

---

## 테스트 디렉터리 구조

```
res://
├── src/
│   └── components/
│       ├── health_component.gd
│       └── HealthComponent.cs
└── tests/
    ├── unit/
    │   ├── test_health_component.gd      # GUT: test_ prefix required
    │   └── HealthComponentTest.cs        # gdUnit4 C#: [TestSuite] attribute
    ├── integration/
    │   ├── test_player_scene.gd
    │   └── PlayerSceneTest.cs
    └── gut_config.json                   # GUT configuration (optional)
```

### 명명 규약

| 프레임워크 | GDScript 파일       | C# 파일              | 테스트 메서드 접두/속성 |
|-----------|---------------------|----------------------|------------------------------|
| GUT       | `test_*.gd`         | 해당 없음             | `func test_*()`              |
| gdUnit4   | `test_*.gd`         | `*Test.cs`           | `func test_*()` / `[TestCase]` |

---

## 테스트 실행

두 프레임워크 모두 CLI 러너를 제공한다. **GUT:** `addons/gut/gut_cmdln.gd`를 `godot --headless --path . -s addons/gut/gut_cmdln.gd`로 호출한다. **gdUnit4:** `--add-gdunit-test-runner` 인자, 또는 에디터의 "GdUnit Tests" 도크로 실행한다. CI: Godot를 설치하고 스위트를 돌리며 실패 시 0이 아닌 코드로 종료하는, 태그 트리거 또는 PR 트리거 GitHub Action.

---

## 테스트 패턴

흔한 네 가지 패턴: **노드가 있는 씬**(`before_each`에서 `add_child`로 인스턴스화, `after_each`에서 해제), **시그널 테스트**(발신이 되는지, 연결 후 발신이 발화되는지 단언), **모킹/더블링**(gdUnit4 `Mock<T>` 또는 `@export` 주입으로 손수 만든 fake), **비동기**(테스트에서 yield·시그널·프레임을 await).

---

## 흔한 단언(Assertion)

### GUT 단언

| 단언                                         | 설명                               |
|----------------------------------------------|------------------------------------|
| `assert_eq(actual, expected)`                | 동등                               |
| `assert_ne(actual, expected)`                | 비동등                             |
| `assert_true(value)`                         | 참(truthy)                         |
| `assert_false(value)`                        | 거짓(falsy)                        |
| `assert_null(value)`                         | null임                             |
| `assert_not_null(value)`                     | null이 아님                        |
| `assert_gt(actual, expected)`                | 큼                                 |
| `assert_lt(actual, expected)`                | 작음                               |
| `assert_gte(actual, expected)`               | 크거나 같음                        |
| `assert_lte(actual, expected)`               | 작거나 같음                        |
| `assert_has(collection, item)`               | 컬렉션이 항목을 포함               |
| `assert_does_not_have(collection, item)`     | 컬렉션이 항목을 포함하지 않음      |
| `assert_string_contains(str, sub)`           | 문자열이 부분문자열을 포함         |
| `assert_almost_eq(actual, expected, margin)` | 마진 이내의 실수 동등              |
| `assert_signal_emitted(obj, signal_name)`    | 시그널이 발신됨                    |
| `assert_signal_not_emitted(obj, signal_name)`| 시그널이 발신되지 않음             |

### gdUnit4 단언 (GDScript + C#)

| GDScript                                           | C#                                              | 설명                            |
|----------------------------------------------------|-------------------------------------------------|---------------------------------|
| `assert_that(val).is_equal(exp)`                   | `AssertThat(val).IsEqual(exp)`                  | 동등                            |
| `assert_that(val).is_not_equal(exp)`               | `AssertThat(val).IsNotEqual(exp)`               | 비동등                          |
| `assert_that(val).is_true()`                       | `AssertThat(val).IsTrue()`                      | 참                              |
| `assert_that(val).is_false()`                      | `AssertThat(val).IsFalse()`                     | 거짓                            |
| `assert_that(val).is_null()`                       | `AssertThat(val).IsNull()`                      | null임                          |
| `assert_that(val).is_not_null()`                   | `AssertThat(val).IsNotNull()`                   | null이 아님                     |
| `assert_that(val).is_greater(exp)`                 | `AssertThat(val).IsGreater(exp)`                | 큼                              |
| `assert_that(val).is_less(exp)`                    | `AssertThat(val).IsLess(exp)`                   | 작음                            |
| `assert_that(val).is_between(min, max)`            | `AssertThat(val).IsBetween(min, max)`           | 범위 내 (포함)                  |
| `assert_that(arr).contains([a, b])`                | `AssertThat(arr).Contains(a, b)`                | 배열이 원소를 포함              |
| `assert_that(str).contains("sub")`                 | `AssertThat(str).Contains("sub")`               | 문자열이 부분문자열을 포함      |
| `assert_that(val).is_approximately(exp, margin)`   | `AssertThat(val).IsApproximately(exp, margin)`  | 마진 이내의 실수                |
| `assert_signal(mon).is_emitted("name")`            | `AssertSignal(mon).IsEmitted("name")`           | 시그널 발신됨                   |

---

## 테스트하지 말 것

실제 버그를 잡지 못하면서 노이즈만 더하는 것들은 테스트하지 마라:

- **Godot 엔진 내부** — `Node.add_child()`가 동작한다거나 `@export` 변수가 에디터에 나타난다고 단언하지 마라
- **비공개 구현 세부** — 공개 API를 통해 동작을 테스트하라. 리팩터가 비공개 상태만 다루는 테스트를 깨뜨린다면, 그 테스트가 잘못된 것이다
- **시각/렌더 출력** — 픽셀 단위 렌더 결과는 취약하다. 대신 시각을 구동하는 데이터를 테스트하라
- **마진 없는 타이밍 민감 실수** — 물리 값에는 `assert_almost_eq` / `IsApproximately`를 써라
- **내장을 감싸기만 하는 한 줄짜리** — 필드를 그대로 반환하는 프로퍼티 getter는 테스트가 필요 없다
- **가능한 모든 잘못된 입력** — 상상 가능한 모든 오용이 아니라, 문서화된 계약을 테스트하라

---

## 체크리스트

- [ ] 각 테스트 파일이 선택한 프레임워크의 명명 규약을 따른다 (`test_*.gd` / `*Test.cs`)
- [ ] 테스트가 올바른 기반 클래스를 상속한다 (`GutTest` / `GdUnit4.GdUnitTestSuite`)
- [ ] 씬 트리에 추가한 노드는 `add_child_autofree` 또는 `auto_free`를 쓴다 — 수동 `queue_free()`는 절대 안 됨
- [ ] 시그널을 트리거하는 동작 전에 시그널을 감시(watch)한다
- [ ] 모킹/더블은 테스트 대상 유닛이 아니라 외부 의존성에 쓴다
- [ ] 각 테스트가 정확히 하나의 동작을 다룬다 (테스트당 논리적 단언 하나)
- [ ] CI 워크플로가 매 push와 PR마다 테스트를 헤드리스로 돌린다
- [ ] 불안정한 비동기 테스트는 임의의 sleep 지속이 아니라 명시적 타임아웃을 쓴다
- [ ] 병합 전에 테스트가 통과한다 (RED는 능동적으로 구현하는 동안에만 허용됨)
