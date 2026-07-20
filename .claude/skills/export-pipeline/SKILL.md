---
name: export-pipeline
description: Godot 게임을 익스포트하고 배포할 때 사용한다 — 익스포트 프리셋, 플랫폼 설정, GitHub Actions로 CI/CD
---

# Godot 4.3+ 익스포트 파이프라인

모든 예제는 Godot 4.3+ 대상이며 폐기된(deprecated) API를 쓰지 않는다. GDScript를 먼저 보이고, 해당하는 경우 C#이 뒤따른다.

> **관련 스킬:** CI/CD 테스트 통합은 **godot-testing**, 익스포트 전 성능 점검은 **godot-optimization**, 플랫폼별 해상도 설정은 **responsive-ui**, Android/iOS 익스포트 세부는 **mobile-development**.

---

## 1. 익스포트 프리셋

### 에디터에서 프리셋 만들기

**Project → Export**를 열고 **Add…**를 눌러 대상 플랫폼을 고른다. 각 프리셋은 `export_presets.cfg`의 항목 하나에 대응한다. 같은 플랫폼에 여러 프리셋을 만들 수 있다(예: Windows용 디버그 빌드와 릴리스 빌드).

플랫폼마다 한 번씩 해 둬야 하는 준비:
- **Export Templates**를 **Editor → Export Templates**로 내려받아야 한다.
- 플랫폼별 툴체인(Android SDK, Xcode 등)은 별도로 설치해야 한다.

### export_presets.cfg

Godot은 `export_presets.cfg`를 프로젝트 루트에 쓴다. 이 파일은 커밋하라 — 안전하며 비밀 값을 담지 않는다. 비밀 값(코드사이닝 비밀번호, 키스토어 비밀번호)은 **절대** 커밋하지 마라. 대신 환경 변수를 써라.

프리셋 구조 예시(Windows 릴리스):

```ini
[preset.0]

name="Windows Desktop"
platform="Windows Desktop"
runnable=true
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path="build/windows/MyGame.exe"
encryption_include_filters=""
encryption_exclude_filters=""
encrypt_pck=false
encrypt_directory=false

[preset.0.options]

custom_template/debug=""
custom_template/release=""
debug/export_console_wrapper=1
binary_format/embed_pck=true
texture_format/s3tc_bptc=true
texture_format/etc2_astc=false
binary_format/architecture="x86_64"
codesign/enable=false
codesign/identity=""
codesign/password=""
codesign/timestamp=true
codesign/timestamp_server_url=""
codesign/digest_algorithm=1
codesign/description=""
codesign/custom_options=PackedStringArray()
application/icon=""
application/console_wrapper_icon=""
application/icon_interpolation=4
application/file_version=""
application/product_version=""
application/company_name=""
application/product_name=""
application/file_description=""
application/copyright=""
application/trademarks=""
application/export_angle=0
application/export_d3d12=0
application/d3d12_agility_sdk_multiarch=true
ssh_remote_deploy/enabled=false
ssh_remote_deploy/host="user@host_ip"
ssh_remote_deploy/port="22"
ssh_remote_deploy/extra_args_ssh=""
ssh_remote_deploy/extra_args_scp=""
ssh_remote_deploy/run_script="#!/usr/bin/env bash\nexport DISPLAY=:0\n\"{temp_dir}/{exe_name}\" {cmd_args}"
ssh_remote_deploy/cleanup_script="#!/usr/bin/env bash\nkill $(pgrep -x -f \"{temp_dir}/{exe_name} {cmd_args}\")\nrm -rf \"{temp_dir}\""
```

> Godot은 에디터를 저장할 때마다 `export_presets.cfg`를 다시 생성한다. 에디터가 열려 있는 동안 이 파일을 손으로 편집하지 마라.

> ⚠️ **Godot 4.7에서 변경:** "runnable" 플래그가 익스포트 프리셋 밖으로 옮겨졌다 — `runnable=`(위 예시에 4.3~4.6용으로 보임)은 더 이상 `export_presets.cfg`의 프리셋별 프로퍼티가 아니다. 이제 에디터가 어느 프리셋이 runnable인지 별도로 추적한다. 4.7 에디터에서 저장한 뒤 파일에서 이 줄이 사라져도 놀라지 마라. [GH-114930](https://github.com/godotengine/godot/pull/114930) 참조.

> **Godot 4.7+:** 희소 PCK 익스포트(패치 팩)는 파일 인덱스 암호화를 지원해, 기존 `encrypt_pck` / `encrypt_directory` 프리셋 옵션을 보완한다. ([GH-113920](https://github.com/godotengine/godot/pull/113920))

---

## 2. 플랫폼별 설정

| 플랫폼  | 핵심 설정 / 고려 사항                                                                                                      |
|-----------|--------------------------------------------------------------------------------------------------------------------------------------------------|
| **Windows** | `application/icon`(.ico 파일)을 설정한다. 코드사이닝에는 `.pfx` 인증서가 필요하다. `codesign/enable=true`로 두고 `codesign/identity` + `codesign/password`를 환경 변수로 공급한다. 코드사이닝을 안 하면 Windows SmartScreen이 사용자에게 경고를 띄운다. |
| **Linux**   | 코드사이닝이 필요 없다. 익스포트 후 바이너리에 `chmod +x MyGame.x86_64`를 실행한다. 배포는 tarball이나 AppImage로 한다. |
| **macOS**   | Gatekeeper가 경고 없이 실행을 허용하려면 노터라이제이션(notarization)이 필요하다. `codesign/enable=true`와 `notarization/enable=true`로 둔다. `codesign/identity`(Apple Developer ID)를 제공한다. `Info.plist` 항목(번들 ID, 버전, 표시 이름, 개인정보 사용 설명)은 프리셋의 `application/*` 옵션 아래에서 설정한다. 노터라이제이션은 익스포트 후 `xcrun notarytool`로 한다. |
| **Web**     | 멀티스레딩에 `SharedArrayBuffer`가 필요하다 — 웹 서버가 `Cross-Origin-Opener-Policy: same-origin`과 `Cross-Origin-Embedder-Policy: require-corp` 헤더를 보내야 한다. 서버를 설정할 수 없다면 스레드를 끈다(`rendering/threads/thread_model=0`). 익스포트 결과물은 `.html` + `.js` + `.wasm` + `.pck` 번들이다. |
| **Android** | 릴리스 서명에 키스토어가 필요하다. `keystore/release`를 `.keystore` 경로로 두고 `keystore/release_user` + `keystore/release_password`를 환경 변수로 공급한다. 권한은 프리셋의 `permissions/*` 아래에서 선언한다. `package/unique_name`을 역-DNS 문자열(예: `com.studio.mygame`)로 설정한다. |
| **iOS**     | 유효한 Apple 프로비저닝 프로파일(`.mobileprovision`)이 필요하다. `application/bundle_identifier`, `codesign/identity`, `application/provisioning_profile`을 설정한다. 배포용 빌드에는 App Store 배포 인증서가 필요하다. |

---

## 3. CLI에서 익스포트

GUI를 열지 않고 익스포트하려면 Godot을 헤드리스 모드로 실행한다. 이것이 CI/CD의 표준 방식이다.

### 릴리스 익스포트

```bash
godot --headless --export-release "Windows Desktop" build/windows/MyGame.exe
```

### 디버그 익스포트

```bash
godot --headless --export-debug "Windows Desktop" build/windows/MyGame.exe
```

### .pck만 익스포트 (실행 파일 없음)

고정된 엔진 바이너리와 함께 갱신된 게임 데이터만 배포하고 싶을 때(예: DLC나 패치 배포) `--export-pack`을 쓴다:

```bash
godot --headless --export-pack "Windows Desktop" build/windows/MyGame.pck
```

> **Godot 4.7+:** Android용 패치 PCK를 익스포트할 때 APK나 AAB를 베이스 팩으로 제공할 수 있어, PCK 패치 워크플로를 Android 빌드로 확장한다. ([GH-116553](https://github.com/godotengine/godot/pull/116553))

### 메모리 내 데이터 패킹 (Godot 4.7+)

`PCKPacker.add_file_from_buffer(target_path, data, encrypt = false)`는 `PackedByteArray`를 PCK로 곧장 패킹한다 — 디스크에 임시 파일이 생기지 않는다 — 빌드 스크립트에서 패치 콘텐츠를 생성할 때 편리하다:

```gdscript
var build_info: String = "v" + ProjectSettings.get_setting("application/config/version", "dev")
var packer := PCKPacker.new()
packer.pck_start("user://patch_1.pck")
packer.add_file_from_buffer("res://data/build_info.txt", build_info.to_utf8_buffer())
packer.flush()
```

```csharp
string buildInfo = "v" + ProjectSettings.GetSetting("application/config/version", "dev").AsString();
var packer = new PckPacker();
packer.PckStart("user://patch_1.pck");
packer.AddFileFromBuffer("res://data/build_info.txt", buildInfo.ToUtf8Buffer());
packer.Flush();
```

### 핵심 CLI 플래그

| 플래그 | 용도 |
|------|---------|
| `--headless` | 디스플레이 서버 없음; 서버/CI 환경에 필수 |
| `--export-release "Preset Name" path` | 릴리스 템플릿으로 익스포트 |
| `--export-debug "Preset Name" path` | 디버그 템플릿으로 익스포트 |
| `--export-pack "Preset Name" path` | .pck 리소스 팩만 익스포트 |
| `--quit-after N` | N 밀리초 후 종료(익스포트에는 거의 필요 없음) |

> CLI 플래그의 프리셋 이름은 `export_presets.cfg`의 `name=`과 대소문자·공백까지 정확히 일치해야 한다.

---

## 4. GitHub Actions로 CI/CD

푸시와 태그 릴리스마다 Windows, Linux, Web 아티팩트를 빌드하는 GitHub Actions 매트릭스 안에서 `godot --headless --export-release`를 실행한다. [`chickensoft-games/setup-godot@v2`](https://github.com/chickensoft-games/setup-godot)로 엔진 + 익스포트 템플릿을 설치한다(C# 프로젝트는 `use-dotnet: true`로 설정). 익스포트 전에 `git describe`로 버전을 주입해 바이너리의 `application/config/version`이 올바르게 되도록 한다.

---

## 5. 버전 관리

### 런타임에 버전 읽기

버전 문자열을 **Project → Project Settings → Application → Config → Version**에 저장한다. 그러면 어디서든 읽을 수 있다:

```gdscript
# version_label.gd
extends Label

func _ready() -> void:
    text = "v" + ProjectSettings.get_setting("application/config/version", "dev")
```

```csharp
// VersionLabel.cs
using Godot;

public partial class VersionLabel : Label
{
    public override void _Ready()
    {
        Text = "v" + ProjectSettings.GetSetting("application/config/version", "dev").AsString();
    }
}
```

### Git 태그에서 자동 버전 관리

릴리스 커밋에 태그를 달고, 익스포트 시점에 버전을 주입한다. 위 CI 워크플로는 `sed`로 이걸 하지만, 엔진 안에 두는 편을 선호한다면 익스포트 전 GDScript 툴(EditorScript)을 실행할 수도 있다:

```gdscript
# tools/inject_version.gd  — run with: godot --headless --script tools/inject_version.gd
@tool
extends EditorScript

func _run() -> void:
    var git_output: Array = []
    var exit_code := OS.execute("git", ["describe", "--tags", "--always", "--dirty"], git_output)
    if exit_code != 0:
        push_error("inject_version: git describe failed")
        return

    var version: String = (git_output[0] as String).strip_edges()
    ProjectSettings.set_setting("application/config/version", version)
    var err := ProjectSettings.save()
    if err != OK:
        push_error("inject_version: failed to save project.godot — error %d" % err)
    else:
        print("inject_version: set version to '%s'" % version)
```

익스포트 단계 전에 CI 단계의 일부로 실행한다:

```bash
godot --headless --script tools/inject_version.gd
godot --headless --export-release "Windows Desktop" build/windows/MyGame.exe
```

### 버전 태그 규칙

[Semantic Versioning](https://semver.org/) 태그를 써라: `v1.2.3`. 그러면 `git describe`가 태그 이후 커밋에 대해 `v1.2.3-4-gabcdef`를 만들어, 완전히 추적 가능한 빌드를 준다.

---

## 6. 배포: itch.io와 Steam

**itch.io**는 [Butler](https://itch.io/docs/butler/) CLI를 쓴다: `butler push build/windows/ my-studio/my-game:windows --userversion "$VERSION"`. 채널 이름은 규칙을 따른다(`windows`, `linux`, `macos`, `web`, `android`). CI에서는 [`Ayowel/butler-to-itch@v1`](https://github.com/Ayowel/butler-to-itch) 액션이 모든 아티팩트를 한 번에 푸시한다. API 키는 `BUTLER_API_KEY` 시크릿으로 저장하라.

**Steam**은 세 가지가 필요하다: Steamworks SDK(재배포 불가, 공개 저장소에 두지 마라), 엔진 바인딩용 [GodotSteam](https://godotsteam.com/) 애드온, 그리고 `steamcmd +run_app_build app_build.vdf`로 구동하는 데포(depot) 설정. Steam 통합은 익스포트 파이프라인 자체의 바깥이다.

---

## 7. Shader Baker (Godot 4.5+)

Godot 4.5는 **Shader Baker**를 도입했다. 대상 플랫폼용으로 셰이더를 미리 컴파일하는 익스포트 시점 도구다. 이게 없으면 셰이더가 처음 사용될 때 런타임에 컴파일돼, 새 머티리얼이 게임 내에서 처음 렌더링될 때 눈에 띄는 끊김(hitch)이 생긴다. Shader Baker는 그 작업을 익스포트 시점에 처리해 이 스터터를 없앤다.

### 활성화

**Project → Export**에서 프리셋을 열고 **Shader Baker** 섹션을 찾는다. 활성화하고 필요에 따라 대상 백엔드(Vulkan, D3D12, Metal, GLES3)를 설정한다.

> Shader Baker는 익스포트 빌드 시간을 늘리지만 게임 다운로드 크기나 런타임 메모리에는 영향이 없다. 미리 컴파일된 캐시는 `.pck` 파일에 임베드된다.

### 플랫폼별 효과

| 플랫폼 | 백엔드 | 이점 |
|----------|---------|---------|
| macOS / Apple Silicon | Metal | 복잡한 셰이더 그래프에서 로드 시간 최대 20배 감소 |
| Windows | D3D12 | D3D12 파이프라인 상태 컴파일 정체를 없앤다 |
| Mobile (Android/iOS) | GLES3 | 중급 하드웨어에서 첫 렌더가 빨라진다 |
| Linux / Windows | Vulkan | 중간 정도 개선; Vulkan 캐시는 드라이버마다 다르다 |

### CI 워크플로 참고

Shader Baker는 에디터 GUI나 CLI(`--export-release`)로 익스포트할 때 자동으로 실행된다. CI에 추가 단계가 필요 없다 — 별도의 CLI 플래그가 아니라 프리셋 설정으로 제어된다.

```bash
# Shader Baker runs as part of normal export (no extra flag needed).
godot --headless --export-release "Windows Desktop" build/windows/MyGame.exe
```

---

## 8. Windows 익스포트 — 네이티브 리소스 편집 (Godot 4.5+)

Godot 4.5 이전에는 Windows에서 `.exe` 메타데이터(버전 정보, 아이콘, 저작권, 회사명)를 수정하려면 외부 `rcedit` 도구가 필요했다. Godot 4.5는 이 전부를 익스포트 시점에 네이티브로 처리한다 — `rcedit` 다운로드나 설정이 필요 없다.

### 네이티브로 편집되는 것

| 익스포트 프리셋 필드 | .exe에 대한 효과 |
|---------------------|---------------|
| `application/file_version` | Properties → Details에 표시되는 파일 버전 |
| `application/product_version` | 제품 버전 |
| `application/company_name` | 회사명 |
| `application/product_name` | 제품명 |
| `application/file_description` | 설명 |
| `application/copyright` | 법적 저작권 |
| `application/icon` | 실행 파일 아이콘으로 임베드되는 `.ico` 파일 |

### 설정

1. **Project → Export** → Windows Desktop 프리셋을 연다.
2. 프리셋 옵션의 **Application** 아래 `application/*` 필드를 채운다.
3. 평소대로 익스포트한다 — Godot이 메타데이터를 `.exe`에 직접 쓴다.

> **CI에서 rcedit 제거:** 이전에 CI에서 `rcedit`을 다운로드해 익스포트 후 단계로 호출했다면, 그 단계를 없앨 수 있다. 익스포트 프리셋의 필드가 Godot 4.5+에서 그것을 완전히 대체한다.

---

## 9. 체크리스트

- [ ] 대상 Godot 버전용 익스포트 템플릿을 내려받았다 (Editor → Export Templates)
- [ ] `export_presets.cfg`를 버전 관리에 커밋했다
- [ ] 비밀 값(키스토어 비밀번호, 코드사이닝 비밀번호, API 키)을 파일이 아니라 환경 변수나 CI 시크릿에 저장했다
- [ ] 각 프리셋의 `name=`이 CLI `--export-release` 인자와 정확히 일치하는 고유 값이다
- [ ] 익스포트 명령 실행 전에 출력 디렉터리를 만들었다 (`mkdir -p`)
- [ ] 익스포트 후 Linux 바이너리를 실행 가능하게 표시했다 (`chmod +x`)
- [ ] project.godot의 `application/config/version`을 익스포트 시점에 git 태그에서 채웠다
- [ ] Web 익스포트: 스레드가 켜져 있으면 호스팅 서버가 `COOP` + `COEP` 헤더를 보낸다
- [ ] Android 릴리스 프리셋이 디버그 키스토어가 아니라 서명된 키스토어를 쓴다
- [ ] 배포용 macOS 빌드를 코드사이닝하고 노터라이즈했다
- [ ] CI에서 아티팩트를 플랫폼별로 업로드해 개별 플랫폼 빌드를 내려받을 수 있다
- [ ] itch.io 채널이 이름 규칙을 따른다 (windows, linux, macos, web, android)
- [ ] Butler API 키를 하드코딩하지 않고 CI 시크릿으로 저장했다
- [ ] Steam 데포 설정을 공개 저장소 밖에 뒀다
- [ ] macOS, D3D12, 모바일 대상용으로 익스포트 프리셋에서 Shader Baker를 활성화했다 (Godot 4.5+)
- [ ] Windows `.exe` 메타데이터(버전, 아이콘, 회사명)를 익스포트 프리셋에서 설정했다 — rcedit 더 이상 불필요 (Godot 4.5+)
