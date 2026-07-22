extends StaticBody2D
# 적 베이스 글루 — HP·피격·부활 로직은 Health 자식 컴포넌트(src/combat/health_component.gd)가 쥔다.
# 이 스크립트는 비주얼(플래시·숨김·충돌 토글)과 EventBus 브로드캐스트 배선만 한다.
# 권한 규율(rules §1·§3): 확정은 호스트만 — CombatAuthority가 Health.apply_damage/confirm_hp를 부르고,
# 게스트는 Health.set_hp_display 반영만. 이 글루는 경로 구분 없이 hp_changed(dropped)로 비주얼만 반영.

const HealthComponent := preload("res://src/combat/health_component.gd")

const HIT_FLASH_TIME := 0.12  # 연출값 (rules §0 예외)
const HIT_FLASH_COLOR := Color(1.0, 0.4, 0.4)

@export var def: EnemyDef
@export var eid: String = ""  # 방 내 적 식별자 — 씬에 배치된 적은 양쪽이 같은 eid를 가진다

var hp: int:  # 읽기 전용 미러 — debug_bridge pb_dump가 duck-typing(get("hp"))으로 읽는다
	get:
		return _health.hp if _health != null else 0

var _flash_left: float = 0.0

@onready var _sprite: Sprite2D = $Sprite
@onready var _collision: CollisionShape2D = $Collision
@onready var _health: HealthComponent = $Health as HealthComponent


func _ready() -> void:
	assert(def != null, "enemy: def(EnemyDef) 미배정 — %s" % get_path())
	assert(_health != null, "enemy: Health 자식 노드 없음 — %s" % get_path())
	_health.setup(def.max_hp, def.respawns, def.respawn_delay)
	_health.hp_changed.connect(_on_hp_changed)
	_health.hp_confirmed.connect(_on_hp_confirmed)
	add_to_group("enemy")


func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_sprite.modulate = Color.WHITE


func _on_hp_changed(new_hp: int, dropped: bool) -> void:
	if dropped:
		if new_hp <= 0:
			visible = false
			_collision.set_deferred("disabled", true)
		else:
			_sprite.modulate = HIT_FLASH_COLOR
			_flash_left = HIT_FLASH_TIME
	elif new_hp > 0:
		visible = true
		_sprite.modulate = Color.WHITE
		_collision.set_deferred("disabled", false)


# 권한 경로(apply_damage/confirm_hp)에서만 도착 — stage(CombatAuthority)가 브로드캐스트한다
func _on_hp_confirmed(new_hp: int) -> void:
	EventBus.enemy_hp_confirmed.emit(eid, new_hp)
