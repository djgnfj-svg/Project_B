extends StaticBody2D
# 적 베이스 — HP·피격·사망/재생성. HP·부활 확정은 호스트만 한다 (rules §1·§3):
# 호스트 = take_hit()/부활 타이머 경로 → enemy_hp_confirmed emit → stage가 브로드캐스트.
# 게스트 = set_hp_display() 수신 반영만 (자가 부활 금지 — 탭 백그라운드로 타이머가 멎으면 영구 드리프트).

const HIT_FLASH_TIME := 0.12  # 연출값 (rules §0 예외)
const HIT_FLASH_COLOR := Color(1.0, 0.4, 0.4)

@export var def: EnemyDef
@export var eid: String = ""  # 방 내 적 식별자 — 씬에 배치된 적은 양쪽이 같은 eid를 가진다

var hp: int = 0

var _flash_left: float = 0.0
var _respawn_left: float = 0.0  # 호스트만 설정한다

@onready var _sprite: Sprite2D = $Sprite
@onready var _collision: CollisionShape2D = $Collision


func _ready() -> void:
	assert(def != null, "enemy: def(EnemyDef) 미배정 — %s" % get_path())
	hp = def.max_hp
	add_to_group("enemy")


func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_sprite.modulate = Color.WHITE
	if _respawn_left > 0.0:
		_respawn_left -= delta
		if _respawn_left <= 0.0:
			_revive()


# 호스트 전용 — 데미지 확정. HP 변화는 enemy_hp_confirmed로 알린다 (stage가 브로드캐스트).
func take_hit(dmg: int) -> void:
	if hp <= 0:
		return
	hp = maxi(0, hp - dmg)
	_apply_hp_visuals(true)
	EventBus.enemy_hp_confirmed.emit(eid, hp)


# 게스트 전용 — 호스트가 확정한 HP 반영. 부활 타이머는 돌리지 않는다.
func set_hp_display(new_hp: int) -> void:
	var dropped := new_hp < hp
	hp = new_hp
	if dropped:
		_apply_hp_visuals(false)
	elif hp > 0:
		_revive_visual()


func _apply_hp_visuals(is_authority: bool) -> void:
	if hp <= 0:
		visible = false
		_collision.set_deferred("disabled", true)
		if is_authority and def.respawns:
			_respawn_left = def.respawn_delay  # 부활 확정도 호스트만 (rules §1)
	else:
		_sprite.modulate = HIT_FLASH_COLOR
		_flash_left = HIT_FLASH_TIME


# 호스트 타이머 경로 — 부활 확정 + 브로드캐스트
func _revive() -> void:
	hp = def.max_hp
	_revive_visual()
	EventBus.enemy_hp_confirmed.emit(eid, hp)


func _revive_visual() -> void:
	visible = true
	_sprite.modulate = Color.WHITE
	_collision.set_deferred("disabled", false)
