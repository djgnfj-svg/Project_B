extends Node
# Audio 오토로드 (rules §1) — EventBus 구독 → SFX 재생 + 전체 볼륨 조절.
# 🔴 웹 autoplay 함정 (rules §5): 첫 사용자 입력 전엔 브라우저가 무음 — SFX는 전투(입력 이후)라
#   자연 회피된다. BGM을 붙이면 그때 첫 입력 이후 시작하도록 게이트할 것.
# 볼륨/뮤트는 user://settings.cfg에 저장(웹 = IndexedDB) — 새로고침해도 유지.
# ⚠ 오토로드 본체라 EventBus 전역 식별자 런타임 접근 OK (헤드리스 -s 대상 아님, rules §5).
# 연출/볼륨 기본값은 스크립트 const (rules §0 예외).

const SETTINGS_PATH := "user://settings.cfg"
const SFX_DIR := "res://assets/audio/sfx/"
const POOL_SIZE := 8         # 동시 재생 채널(라운드로빈)
const DEFAULT_MASTER := 0.55  # 초기 마스터 볼륨(선형 0~1) — 사용자 요청으로 낮춤(2026-07-23)

# 상황 키 → sfx 파일명(assets/audio/sfx/<id>.wav). 파일 없으면 조용히 스킵.
const SFX := {
	"swing": "swing",
	"swing_heavy": "swing_heavy",  # 무거운 대검 스윙(EquipDef.swing_sfx)
	"thud": "thud",                # 대검 적중 묵직한 쿵(EquipDef.hit_sfx)
	"hit": "hit",
	"hurt": "hurt",
	"roll": "roll",
	"enemy_death": "enemy_death",
	"player_death": "player_death",
	"drop": "drop",              # 드랍 등장(item_dropped)
	"pickup_item": "pickup_item",  # 재료/도면 픽업(item_picked)
	"pickup_gold": "pickup_gold",  # 골드 픽업(item_picked kind=gold)
	"blueprint": "blueprint",    # 도면 신규 언락 팡파레(blueprint_unlocked)
}

var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var _streams: Dictionary = {}  # id -> AudioStream
var _master_linear: float = DEFAULT_MASTER
var _muted: bool = false


func _ready() -> void:
	for _i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = &"Master"
		add_child(p)
		_players.append(p)
	_load_streams()
	_load_settings()
	_apply_volume()
	EventBus.combat_impact.connect(_on_impact)
	EventBus.player_swing.connect(func(_pos: Vector2, sfx: String) -> void: play(sfx))  # 무기별 휘두름음
	EventBus.weapon_impact.connect(func(_pos: Vector2, sfx: String, _shake: float) -> void: play(sfx))  # 무기 고유 타격음(비면 무음)
	EventBus.player_roll.connect(func(_pos: Vector2) -> void: play("roll"))
	EventBus.entity_died.connect(func(kind: String, _pos: Vector2) -> void:
		play("enemy_death" if kind == "enemy" else "player_death"))
	# 드랍 손맛 SFX (표시 전용 훅, 네트워크 0 — 각 클라 로컬 재생). 도면은 팡파레가 픽업음을 대신한다.
	EventBus.item_dropped.connect(func(_kind: String, _rarity: int, _pos: Vector2) -> void: play("drop"))
	EventBus.item_picked.connect(_on_item_picked)
	EventBus.blueprint_unlocked.connect(func(_rid: String) -> void: play("blueprint"))


func _load_streams() -> void:
	for key: String in SFX.values():
		var path := SFX_DIR + key + ".wav"
		if ResourceLoader.exists(path):
			_streams[key] = load(path)


# SFX 재생 — 라운드로빈 풀에서 다음 채널로. 없는 id는 무시(파일 아직 없을 때 안전).
func play(id: String) -> void:
	var stream: Variant = _streams.get(id)
	if stream == null:
		return
	var p := _players[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = stream as AudioStream
	p.play()


func _on_impact(kind: String, _pos: Vector2, _amount: int) -> void:
	play("hit" if kind == "enemy" else "hurt")


# 픽업 SFX — 골드는 코인, 도면은 blueprint_unlocked 팡파레가 담당(무음), 그 외 일반 픽업
func _on_item_picked(kind: String, _rarity: int, _pos: Vector2) -> void:
	match kind:
		"gold":
			play("pickup_gold")
		"blueprint":
			pass  # 도면 신규 언락은 blueprint_unlocked 팡파레(중복 재생 방지). 이미 보유분은 무음
		_:
			play("pickup_item")


# --- 볼륨 API (설정 UI가 호출) ---

func set_master_volume(linear: float) -> void:
	_master_linear = clampf(linear, 0.0, 1.0)
	_apply_volume()
	_save_settings()


func master_volume() -> float:
	return _master_linear


func set_muted(m: bool) -> void:
	_muted = m
	_apply_volume()
	_save_settings()


func is_muted() -> bool:
	return _muted


func _apply_volume() -> void:
	var bus := AudioServer.get_bus_index(&"Master")
	AudioServer.set_bus_mute(bus, _muted)
	# 선형 0~1 → dB. 0은 -inf라 하한을 둔다(무음은 뮤트로 처리).
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(_master_linear, 0.0001)))


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		_master_linear = clampf(float(cfg.get_value("audio", "master", DEFAULT_MASTER)), 0.0, 1.0)
		_muted = bool(cfg.get_value("audio", "muted", false))


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # 기존 값 병합(다른 섹션 보존)
	cfg.set_value("audio", "master", _master_linear)
	cfg.set_value("audio", "muted", _muted)
	cfg.save(SETTINGS_PATH)
