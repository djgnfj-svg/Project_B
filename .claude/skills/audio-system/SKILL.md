---
name: audio-system
description: 오디오를 구현할 때 사용한다 — 오디오 버스, AudioStreamPlayer, 공간 오디오, 음악 관리, SFX 풀링, 동적 믹싱
---

# Godot 4.3+의 오디오 시스템

모든 예제는 Godot 4.3+를 대상으로 하며 폐기된 API를 쓰지 않는다. GDScript를 먼저 보이고, 그다음 C#을 보인다.

> **관련 스킬:** 결합 없는 오디오 트리거는 **event-bus**, 오디오 설정 저장은 **save-load**, 오디오 데이터 컨테이너는 **resource-pattern**을 참고하라.

---

## 1. 핵심 개념

### 오디오 노드 타입

| 노드                   | 차원 | 용도                                       |
|------------------------|------------|-----------------------------------------------|
| `AudioStreamPlayer`    | 비위치 | 음악, UI 사운드, 전역 SFX              |
| `AudioStreamPlayer2D`  | 2D 위치  | 발소리, 총성, 환경음  |
| `AudioStreamPlayer3D`  | 3D 위치  | 2D와 같지만 3D 공간에서                |

### 오디오 버스 아키텍처

Godot은 모든 오디오를 **버스**(믹싱 콘솔처럼)를 통해 라우팅한다.

```
Master (always exists)
├── Music          → volume, effects for background music
├── SFX            → volume, effects for sound effects
│   ├── Footsteps  → sub-bus for fine-tuning
│   └── Weapons    → sub-bus for fine-tuning
└── UI             → volume for menu sounds
```

**설정:** 하단 패널 → Audio 탭 → 버스 추가, 이름 설정, 출력 라우팅.

모든 AudioStreamPlayer에는 `bus` 속성이 있다 — 타깃 버스 이름(예: `"SFX"`, `"Music"`)으로 설정한다.

---

## 2. 기본 오디오 재생

### GDScript

```gdscript
extends Node2D

@onready var sfx_player: AudioStreamPlayer2D = $AudioStreamPlayer2D
@onready var music_player: AudioStreamPlayer = $MusicPlayer

func _ready() -> void:
    # Play background music (looping is set on the AudioStream resource)
    music_player.play()

func play_jump_sound() -> void:
    sfx_player.stream = preload("res://audio/sfx/jump.wav")
    sfx_player.play()
```

### C#

```csharp
using Godot;

public partial class AudioExample : Node2D
{
    private AudioStreamPlayer2D _sfxPlayer;
    private AudioStreamPlayer _musicPlayer;

    public override void _Ready()
    {
        _sfxPlayer = GetNode<AudioStreamPlayer2D>("AudioStreamPlayer2D");
        _musicPlayer = GetNode<AudioStreamPlayer>("MusicPlayer");
        _musicPlayer.Play();
    }

    public void PlayJumpSound()
    {
        _sfxPlayer.Stream = GD.Load<AudioStream>("res://audio/sfx/jump.wav");
        _sfxPlayer.Play();
    }
}
```

### 루프 오디오

루프는 플레이어 노드가 아니라 **AudioStream 리소스**에 구성한다:

- **WAV:** Import 탭 → Loop Mode → Forward(또는 Ping-Pong)
- **OGG:** Import 탭 → Loop → On, Loop Offset 설정
- **MP3:** Import 탭 → Loop → On

> 음악에는 항상 OGG Vorbis를 써라(작은 파일, 좋은 품질). 짧은 SFX에는 WAV를 써라(디코딩 지연 없음). SFX에는 MP3를 피해라 — 시작에 무음을 추가한다.

---

## 3. 오디오 버스 관리

### 코드에서 볼륨 설정

Godot은 볼륨에 **데시벨(dB)**을 쓴다. 슬라이더에는 선형-dB 변환이 필요하다.

#### GDScript

```gdscript
# Get bus index by name
var bus_index: int = AudioServer.get_bus_index("SFX")

# Set volume in dB directly
AudioServer.set_bus_volume_db(bus_index, -6.0)  # -6 dB = ~50% perceived volume

# Convert linear (0.0–1.0) to dB — use for UI sliders
func set_bus_volume_linear(bus_name: String, linear: float) -> void:
    var index := AudioServer.get_bus_index(bus_name)
    AudioServer.set_bus_volume_db(index, linear_to_db(linear))

# Mute / unmute a bus
AudioServer.set_bus_mute(bus_index, true)

# Read current volume as linear (for displaying on a slider)
func get_bus_volume_linear(bus_name: String) -> float:
    var index := AudioServer.get_bus_index(bus_name)
    return db_to_linear(AudioServer.get_bus_volume_db(index))
```

#### C#

```csharp
int busIndex = AudioServer.GetBusIndex("SFX");

// Set volume in dB
AudioServer.SetBusVolumeDb(busIndex, -6.0f);

// Linear to dB conversion for UI sliders
public void SetBusVolumeLinear(string busName, float linear)
{
    int index = AudioServer.GetBusIndex(busName);
    AudioServer.SetBusVolumeDb(index, Mathf.LinearToDb(linear));
}

// Mute / unmute
AudioServer.SetBusMute(busIndex, true);

// Read current volume as linear
public float GetBusVolumeLinear(string busName)
{
    int index = AudioServer.GetBusIndex(busName);
    return Mathf.DbToLinear(AudioServer.GetBusVolumeDb(index));
}
```

### 오디오 버스 이펙트

Audio 패널(하단 도크)에서 버스에 이펙트를 추가한다. 흔한 이펙트:

| 이펙트          | 용도                                     |
|-----------------|---------------------------------------------|
| `Reverb`        | 동굴, 성당, 욕실 앰비언스           |
| `Delay`         | 에코 효과                                 |
| `Compressor`    | 큰/작은 소리 정규화(마스터 버스)     |
| `Limiter`       | 마스터 버스에서 클리핑 방지            |
| `LowPassFilter` | 먹먹한 소리(물속, 벽 뒤)    |
| `HighPassFilter` | 가늘고 얇은 소리(라디오, 전화)             |
| `Chorus`        | 소리를 두껍게                               |
| `Distortion`    | 거칠고 오버드라이브된 효과                     |
| `EQ`            | 주파수 대역 미세 조정                    |

### 동적 이펙트 토글

```gdscript
# Enable/disable an effect on a bus at runtime
var bus_index := AudioServer.get_bus_index("SFX")
var effect_index := 0  # First effect on the bus
AudioServer.set_bus_effect_enabled(bus_index, effect_index, true)

# Apply low-pass filter for "underwater" feel
func set_underwater(enabled: bool) -> void:
    var index := AudioServer.get_bus_index("SFX")
    # Assumes a LowPassFilter is the first effect on the SFX bus
    AudioServer.set_bus_effect_enabled(index, 0, enabled)
```

---

## 4. 공간 오디오 (2D & 3D)

### AudioStreamPlayer2D

가장 가까운 `AudioListener2D`(리스너가 없으면 Camera2D)까지의 거리에 따라 볼륨과 패닝을 자동 조정한다.

```
Enemy (CharacterBody2D)
├── Sprite2D
└── AudioStreamPlayer2D   ← positioned at enemy's location
    bus = "SFX"
    max_distance = 1000.0
    attenuation = 1.0
```

핵심 속성:

| 속성        | 설명                                   | 기본값  |
|-----------------|-----------------------------------------------|----------|
| `max_distance`  | 이 거리를 넘으면 소리가 무음          | 2000.0   |
| `attenuation`   | 볼륨 감쇠 곡선(1.0 = 선형, 클수록 급격) | 1.0 |
| `max_polyphony` | 이 플레이어의 최대 동시 인스턴스      | 1        |
| `panning_strength` | 소리가 좌/우로 얼마나 패닝되는지          | 1.0      |

### AudioStreamPlayer3D

같은 개념이지만 3D에서. `AudioListener3D`(또는 Camera3D)와 함께 동작한다.

핵심 추가 속성:

| 속성            | 설명                                 |
|---------------------|---------------------------------------------|
| `unit_size`         | 볼륨이 0 dB인 거리            |
| `max_db`            | 최대 볼륨 상한                          |
| `attenuation_model` | Inverse, InverseSquare, Logarithmic, Disabled |
| `doppler_tracking`  | 이동하는 소스에 도플러 효과 활성화    |

### AudioListener

```gdscript
# Make a specific camera the audio listener
# 2D: add AudioListener2D as child of Camera2D, call make_current()
# 3D: add AudioListener3D as child of Camera3D, call make_current()

# By default, the current Camera2D/3D acts as the listener.
# Only add an explicit AudioListener if you need a different listening position.
```

```csharp
// 2D spatial player
public partial class Footsteps : AudioStreamPlayer2D
{
    public override void _Ready()
    {
        Bus = "SFX";
        MaxDistance = 1000.0f;     // Pixels at which volume reaches zero
        Attenuation = 1.0f;         // Linear falloff (higher = sharper)
        MaxPolyphony = 4;           // Allow overlapping footstep sounds
    }

    public void PlayStep() => Play();
}

// 3D spatial player
public partial class EngineHum : AudioStreamPlayer3D
{
    public override void _Ready()
    {
        Bus = "SFX";
        UnitSize = 4.0f;            // Meters at which volume is 0 dB
        MaxDistance = 50.0f;
        AttenuationModel = AttenuationModelEnum.InverseDistance;
    }
}

// Custom listener — overrides the default Camera2D / Camera3D listener.
public partial class FollowCamListener : AudioListener3D
{
    public override void _Ready() => MakeCurrent();
}
```

> ⚠️ **Godot 4.7에서 변경됨:** `AudioStreamPlayer2D`/`AudioStreamPlayer3D`의 기본 `area_mask`가 `1`에서 `0`(비활성화)으로 바뀌었다 — `Area2D`/`Area3D`의 `audio_bus_override` 기능(예: 물속 버스)이 기본값으로 둔 플레이어에 대해 동작을 멈춘다. 복원하려면 `area_mask`를 다시 레이어 1로 설정하라; 레이어 1이 아닌 다른 값으로 명시적으로 설정된 마스크는 계속 동작한다. (마이그레이션 가이드는 "AudioStreamPlayer"라고 하지만 `area_mask`는 2D/3D 변형에만 존재한다.) [4.7 마이그레이션 가이드](https://docs.godotengine.org/en/latest/tutorials/migrating/upgrading_to_godot_4.7.html)를 참고하라.

---

## 5. 음악 매니저 (오토로드)

두 `AudioStreamPlayer` 노드를 관리하고 그 volume_db를 트윈하는 싱글턴 오토로드로 배경 트랙 간 크로스페이드를 한다. 설정 메뉴가 음악을 따로 조정할 수 있도록 `Music` 오디오 버스를 배선한다.

---

## 6. SFX 풀

고정된 `AudioStreamPlayer` 노드 풀을 미리 인스턴스화한다 — `play_sfx(stream)`이 다음 빈 플레이어를 찾아 재생한다. 고빈도 효과(총성, 발소리, 타격)에서 매 발 인스턴싱 churn을 피한다.

---

## 7. 오디오 설정 통합

설정 메뉴의 HSlider를 `AudioServer.set_bus_volume_db(bus_idx, linear_to_db(value))`로 버스 볼륨에 배선한다. `ConfigFile`로 저장한다. `linear_to_db` / `db_to_linear` 헬퍼를 써라 — 절대 손으로 로그를 계산하지 마라.

---

## 8. 인터랙티브 & 적응형 음악 (Godot 4.3+)

적응형 음악을 위한 세 스트림 타입: `AudioStreamPlaylist`(순차 또는 셔플 트랙), `AudioStreamSynchronized`(여러 스템을 동기 재생 — 전투 강도를 위한 수직 레이어링), `AudioStreamInteractive`(트리거에 따른 클립 전이 — 상태 주도 음악). Godot 4.4+는 런타임 WAV 로딩을 위한 `AudioStreamWAV.load_from_file()`을 추가한다.

> **Godot 4.7+:** `AudioStreamInteractive`가 이제 스크립트에 `TRANSITION_TO_TIME_PREVIOUS_POSITION`(`TransitionToTime` enum)을 노출한다 — 해당 클립에서 이전 전이가 있었다면 목적지 클립이 마지막 재생 위치에서 재개되고, 아니면 처음부터 재생된다. 멈춘 곳에서 이어지는 탐험 ↔ 전투 음악에 이상적이다.

---

## 9. 오디오 임포트 모범 사례

| 포맷    | 용도        | 파일 크기 | 디코드 지연 | 루프 지원  |
|-----------|----------------|-----------|----------------|---------------|
| **WAV**   | 짧은 SFX      | 큼     | 없음(PCM)     | 임포트로    |
| **OGG**   | 음악, 긴 SFX| 작음     | 최소        | 임포트로    |
| **MP3**   | 음악(대안)| 작음    | 패딩 있음  | 임포트로    |

### 임포트 설정

Import 도크에서(오디오 파일 선택):

- **Loop:** 음악과 앰비언트 루프에 활성화
- **BPM / Beat Count / Bar Beats:** 리듬 동기 게임에 설정
- **Force Mono:** 3D 위치 오디오에 활성화(스테레오는 공간화가 잘 안 됨)

> **팁:** SFX는 44.1kHz의 16비트 WAV로 유지하라. Godot은 WAV를 PCK에 무압축으로 저장하므로 디코드 오버헤드 없이 즉시 재생된다. 음악은 품질 6–8의 OGG Vorbis가 좋은 균형이다.

---

## 11. 흔한 함정

| 증상                            | 원인                                          | 해결                                                               |
|------------------------------------|-------------------------------------------------|-------------------------------------------------------------------|
| 소리가 안 남                 | 플레이어가 씬 트리에 없음                    | `play()` 전에 AudioStreamPlayer를 `add_child()` 했는지 확인  |
| 소리는 재생되나 안 들림     | 잘못된 버스 이름 또는 버스 음소거                  | `bus` 속성이 버스 이름과 정확히 일치하는지 확인(대소문자 구분)   |
| 씬 전환 시 음악 재시작     | 플레이어가 오토로드가 아니라 씬의 일부    | 음악 플레이어를 오토로드로 이동(MusicManager)                   |
| 위치 오디오에 패닝이 없음    | 씬에 AudioListener나 Camera 없음         | AudioListener2D/3D를 추가하거나 Camera가 current인지 확인           |
| 소리가 딸깍거리거나 팝       | 오디오 파일에 페이드인/페이드아웃 없음              | 오디오 에디터에서 WAV 시작/끝에 짧은 페이드(2–5ms) 추가      |
| 한 번에 너무 많은 소리 재생    | 폴리포니 제한 없음                              | 플레이어에 `max_polyphony`를 설정하거나 SFX 풀 사용                 |
| 볼륨 슬라이더가 비선형처럼 느껴짐     | 선형 변환 없이 dB를 직접 사용  | 슬라이더 값에 `linear_to_db()` / `db_to_linear()` 사용        |
| 3D 오디오가 모노/평면처럼 들림          | 스테레오 소스 파일                              | 3D 공간화를 위해 모노로 임포트(Import 탭의 Force Mono)   |
| MP3가 시작에 무음이 있음           | MP3 포맷이 인코더 패딩을 추가                 | 타이밍이 중요한 SFX에는 WAV, 음악에는 OGG 사용                   |

---

## 12. 구현 체크리스트

- [ ] 오디오 버스가 설정돼 있다: Master, Music, SFX(최소)
- [ ] 모든 AudioStreamPlayer 노드에 올바른 `bus` 속성이 할당돼 있다
- [ ] 음악은 OGG Vorbis 포맷을, 짧은 SFX는 WAV를 쓴다
- [ ] 음악 플레이어가 오토로드에 있다(씬 전환에도 살아남음)
- [ ] 부드러운 전환을 위해 음악 크로스페이드가 구현돼 있다
- [ ] AudioStreamPlayer 노드를 동적으로 만드는 대신 SFX 풀을 쓴다
- [ ] 볼륨 슬라이더가 `linear_to_db()` / `db_to_linear()` 변환을 쓴다
- [ ] 0에 가까운 슬라이더 값은 버스를 음소거한다(`linear_to_db(0.0)` = `-inf`를 피함)
- [ ] 3D 오디오 소스가 제대로 된 공간화를 위해 모노 오디오 파일을 쓴다
- [ ] 오디오 설정이 게임 실행 시 저장·복원된다(ConfigFile 등)
- [ ] 루프가 코드가 아니라 AudioStream 리소스에 구성돼 있다
- [ ] 인터랙티브/적응형 음악이 수동 트랙 전환 코드 대신 `AudioStreamPlaylist`, `AudioStreamSynchronized`, `AudioStreamInteractive`(Godot 4.3+)를 쓴다
