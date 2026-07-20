---
name: save-load
description: 저장/불러오기 시스템을 구현할 때 사용한다 — ConfigFile, JSON, Resource 직렬화, 세이브 게임 아키텍처
---

# Godot 4.3+의 저장 / 불러오기 시스템

데이터 타입에 맞는 직렬화 전략을 골라라. 모든 예제는 Godot 4.3+를 대상으로 하며 폐기된 API를 쓰지 않는다.

> **관련 스킬:** 커스텀 Resource 데이터 컨테이너는 **resource-pattern**, 인벤토리 직렬화 패턴은 **inventory-system**, SaveManager 오토로드 설정은 **godot-project-setup**을 참고하라.

---

## 1. 전략 비교

| 전략              | 적합한 용도                      | 가독성   | 에디터 지원    | 비고                              |
|-------------------|---------------------------------|----------|----------------|------------------------------------|
| ConfigFile        | 설정, 단순 키-값 데이터         | 예       | 아니오         | 내장 INI 스타일, 추가 의존성 없음  |
| JSON              | 게임 세이브, 유연한 구조        | 예       | 아니오         | 크로스 플랫폼, 버전 마이그레이션 가능 |
| Resource .tres    | 에디터 통합 데이터              | 예       | 예             | **안전하지 않음 — 신뢰할 수 없는 파일은 절대 로드하지 마라** |
| Resource .res     | 빠른 바이너리 데이터            | 아니오   | 예             | **안전하지 않음 — 신뢰할 수 없는 파일은 절대 로드하지 마라** |

> **보안 경고:** `.tres` 또는 `.res` 파일을 로드하면 리소스에 내장된 임의의 GDScript가 실행된다. 신뢰할 수 없는 출처(사용자 업로드 파일, 다운로드한 모드)의 Resource 파일은 절대 로드하지 마라. 사용자 생성 세이브 데이터에는 ConfigFile이나 JSON을 써라.

---

## 2. ConfigFile — 설정

`ConfigFile`은 INI 스타일 섹션을 쓴다 — 오디오 / 비디오 / 컨트롤 설정(작고, 디자이너가 디버그하기 쉬운 데이터)에 이상적이다. `set_value(section, key, value)` 후 `save(path)`를 쓰고, `load(path)`와 `get_value(section, key, default)`로 불러온다.
---

## 3. JSON — 게임 세이브

`JSON.stringify(dict)`로 직렬화하고, `JSON.parse_string(text)`로 역직렬화한다. `FileAccess`를 통해 읽고 쓴다. 사람이 읽을 수 있는 파일을 원하는 게임 세이브에 가장 좋다. 모든 게임플레이 상태(플레이어 위치, 인벤토리, 월드 플래그)를 담은 Dictionary를 만들어 직렬화하고 `user://save_<slot>.json`에 쓴다.
> ⚠️ **Godot 4.7에서 변경됨:** `JSON.stringify(data, indent = "", sort_keys = true, full_precision = false)`는 이제 `indent`가 전달돼도 빈 `Dictionary`를 `{}`로 간결하게 직렬화한다([GH-115883](https://github.com/godotengine/godot/pull/115883)). indent로 작성한 세이브 파일은 업그레이드 후 빈 딕셔너리 필드의 포맷이 바뀐다 — 세이브 출력을 바이트 단위로 diff하거나 해시하는 것은 새 형태를 견뎌야 한다. 파싱은 영향받지 않는다.

---

## 4. 세이브 아키텍처 패턴

더 큰 게임에서는 각 영속 노드에 `SaveableComponent`를 붙인다. 각 컴포넌트는 `save_callable`과 `load_callable`을 선언한다. 세이브 매니저는 ID로 컴포넌트들을 순회하며 각각의 save callable을 호출해 마스터 Dictionary를 만든다.
---

## 5. 세이브 파일 위치

`user://`는 프로젝트 폴더 바깥의 플랫폼별 쓰기 가능 디렉터리로 해석된다.

| 플랫폼 | 경로                                                                          |
|----------|-------------------------------------------------------------------------------|
| Windows  | `%APPDATA%\Godot\app_userdata\<project-name>\`                                |
| macOS    | `~/Library/Application Support/Godot/app_userdata/<project-name>/`           |
| Linux    | `~/.local/share/godot/app_userdata/<project-name>/`                          |

> 세이브 데이터에는 항상 `user://`를 쓰고 `res://`는 절대 쓰지 마라. `res://` 경로는 익스포트된 빌드에서 읽기 전용이다.

---

## 6. 버전 마이그레이션

세이브 파일은 그것을 작성한 스키마보다 오래 살아남는다. 저장하는 Dictionary 맨 위에 항상 `"version": <int>`를 포함하라. 불러올 때 버전에 따라 분기해 오래된 세이브를 점진적으로 앞으로 마이그레이션하라(`v1 → v2 → v3 → current`). 오래된 세이브를 절대 깨뜨리지 마라 — 항상 마이그레이션하라.
---

## 7. 구현 체크리스트

- [ ] 설정에는 ConfigFile, 게임 세이브에는 JSON을 쓴다(Resource가 아니라)
- [ ] 모든 세이브 파일에 `version` 정수 필드가 들어간다
- [ ] 세이브 경로는 `user://`를 쓰고 `res://`는 절대 안 쓴다
- [ ] 세이브를 쓰기 전에 `DirAccess.make_dir_recursive_absolute()`를 호출한다
- [ ] Vector2/Vector3는 별개의 `x`/`y`/`z` float으로 직렬화한다(JSON에는 Vector 타입이 없다)
- [ ] 모든 파일 작업이 반환 코드를 확인하고 실패 시 `push_error()`를 호출한다
- [ ] `_migrate()`가 0부터 현재까지 모든 버전을 처리하며 점진적으로 적용한다
- [ ] Resource 파일(.tres/.res)은 플레이어가 통제하는 세이브 데이터에 절대 쓰지 않는다
- [ ] UI 슬롯 관리를 위한 `get_save_slots()`와 `delete_save()` 헬퍼가 존재한다
- [ ] 세이브 가능 노드는 세션 간에 바뀌지 않는 안정적인 ID를 쓴다
