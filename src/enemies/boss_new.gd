extends CharacterBody2D
# ┌─────────────────────────────────────────────────────────────────────────┐
# │ 새 보스 골격 — 움직임을 직접 채워 넣는 실험용 보스.                        │
# │ 악어(boss_croc.gd)와 "같은 계약"만 지키면 게스트 화면에서 안 깨진다:      │
# │   · AI/판정은 호스트만 (Net.is_host()), 게스트는 mpos 수신 표시만          │
# │   · HP·피격·사망 = $Health(HealthComponent)                               │
# │   · MobSync가 get_sync_state()/apply_remote_pos()로 위치 동기화            │
# │ ⚠ 아래 "여기를 채우세요" 표시된 _host_ai() 안의 움직임만 자유. 나머지는     │
# │   계약이라 그대로 두는 게 안전하다 (지우면 조용히 깨짐, rules §1·§3·§5).   │
# └─────────────────────────────────────────────────────────────────────────┘
# ⚠ 씬 전용 글루(오토로드 전역 식별자 사용) — -s 헤드리스 테스트에서 preload 금지 (rules §5).

const HealthComponent := preload("res://src/combat/health_component.gd")
const PlayerActor := preload("res://src/player/player.gd")
const HitStop := preload("res://src/feel/hit_stop.gd")
const HitFlash := preload("res://src/feel/hit_flash.gd")
const Flinch := preload("res://src/feel/flinch.gd")

# 연출값 (rules §0 예외 — 눈으로 조인다)
const REMOTE_LERP_SPEED := 12.0
const REMOTE_MOVE_EPS := 1.0   # 게스트 표시: 목표점과 이만큼 이상 벌어져 있으면 walk 애니

@export var eid: String = ""
@export var def: BossDef        # 스탯·스프라이트·드랍은 데이터로 (악어와 같은 BossDef 스키마 재사용)

var _prev_hp: int = 0
var _max_hp: int = 0
var _remote_target: Vector2 = Vector2.ZERO
var _remote_flip: bool = false

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _collision: CollisionShape2D = $Collision
@onready var _health: HealthComponent = $Health


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("mob")   # MobSync mpos 배치가 이 그룹으로 문다 — 지우지 마라
	_remote_target = global_position
	if def != null:
		if def.frames != null:
			_sprite.sprite_frames = def.frames
		elif def.sprite != null:
			var sf := SpriteFrames.new()
			sf.rename_animation(&"default", &"idle")
			sf.add_frame(&"idle", def.sprite)
			_sprite.sprite_frames = sf
		# 몸 판정 반경 = def.body_radius (거대 보스 표면 사거리). shape는 인스턴스 공유라 복제 후 적용
		var shape := _collision.shape.duplicate() as CircleShape2D
		if shape != null:
			shape.radius = def.body_radius
			_collision.shape = shape
		_max_hp = int(CombatMath.party_scale(float(def.max_hp), _party_size()))
		_health.setup(_max_hp, def.respawns, def.respawn_delay)
		_prev_hp = _max_hp
	_health.hp_changed.connect(_on_hp_changed)
	# 권한 경로(호스트 apply_damage)에서만 발화 — CombatAuthority가 ehp 브로드캐스트 + 클리어 판정.
	# 이 연결이 없으면 게스트 화면에 시체가 남고 클리어가 영영 안 뜬다.
	_health.hp_confirmed.connect(func(hp: int) -> void: EventBus.enemy_hp_confirmed.emit(eid, hp))
	_play(&"idle")


func _on_hp_changed(hp: int, dropped: bool) -> void:
	# HP·피격·사망 손맛 — 악어와 동일 (표시 전용 훅, 지우지 마라)
	var dead := hp <= 0
	_collision.set_deferred("disabled", dead)
	if dropped:
		var amount := _prev_hp - hp
		_prev_hp = hp
		EventBus.combat_impact.emit("enemy", global_position, maxi(amount, 0))
		if dead:
			EventBus.entity_died.emit("enemy", global_position)
		else:
			HitStop.punch(_sprite)
			HitFlash.flash(_sprite)
			var opp := Flinch.nearest_pos(global_position, get_tree().get_nodes_in_group("player"))
			Flinch.play(_sprite, global_position - opp)
	else:
		_prev_hp = hp
	if dead:
		velocity = Vector2.ZERO
		if _has_anim(&"death"):
			visible = true
			_play(&"death")
		else:
			visible = false
	else:
		visible = true
		_play(&"idle")


func _physics_process(delta: float) -> void:
	if _health.is_dead() or def == null:
		return
	if Net.is_host():
		_host_ai(delta)        # ← 호스트만 움직임/공격 결정
	else:
		# 게스트 = 호스트가 보낸 위치로 부드럽게 따라가기만 (판정 없음)
		global_position = global_position.lerp(_remote_target, minf(1.0, REMOTE_LERP_SPEED * delta))
		_sprite.flip_h = _remote_flip
		_update_move_anim(global_position.distance_to(_remote_target) > REMOTE_MOVE_EPS)


# ╔═══════════════════════════════════════════════════════════════════════╗
# ║  여기를 채우세요 — 호스트 전용 움직임/행동. velocity를 정하고            ║
# ║  move_and_slide()를 부르면 몸이 움직인다. 아래는 "가장 가까운 플레이어  ║
# ║  를 향해 걸어가기"만 하는 최소 예시 — 원하는 대로 갈아엎으세요.         ║
# ║  · 대상 조준 좌표 = t.net_anchor() (표시 좌표 말고 이걸 써라, rules §3) ║
# ║  · 공격을 넣고 싶으면 EventBus.boss_strike.emit(...)로 호스트 확정 요청  ║
# ║    (판정은 CombatAuthority가 함 — 악어 _fire_strike 참고)               ║
# ╚═══════════════════════════════════════════════════════════════════════╝
func _host_ai(delta: float) -> void:
	var t := _nearest_alive_player()
	if t == null:
		velocity = Vector2.ZERO
		_update_move_anim(false)
		return

	# ── 예시 움직임: 플레이어를 향해 이동 (여기부터 자유롭게 바꾸세요) ──
	var target := t.net_anchor()
	var to_target := target - global_position
	if to_target.length() > 4.0:
		velocity = to_target.normalized() * def.move_speed
		move_and_slide()
		_sprite.flip_h = velocity.x < 0.0
		_update_move_anim(true)
	else:
		velocity = Vector2.ZERO
		_update_move_anim(false)
	# ── 예시 끝 ──


# --- 아래는 계약·헬퍼 (건드릴 필요 없음) ---

# 추격/조준 좌표는 표시 좌표가 아니라 net_anchor — 호스트 판정 기준과 일치 (rules §3)
func _nearest_alive_player() -> PlayerActor:
	var best: PlayerActor = null
	var best_dist := INF
	for node: Node in get_tree().get_nodes_in_group("player"):
		var p := node as PlayerActor
		if p == null or not p.is_alive():
			continue
		var d := global_position.distance_to(p.net_anchor())
		if d < best_dist:
			best_dist = d
			best = p
	return best


func _party_size() -> int:
	return Net.peer_ids.size() + 1   # 나 + 원격 피어 수 (악어와 동일)


# --- MobSync 동기화 API (호스트 송신 배치 / 게스트 수신 반영) — 지우지 마라 ---

func get_sync_state() -> Array:
	return [eid, global_position.x, global_position.y, _sprite.flip_h]


func apply_remote_pos(pos: Vector2, flip: bool) -> void:
	_remote_target = pos
	_remote_flip = flip


# --- 애니 표시 헬퍼 ---

func _play(anim: StringName) -> void:
	if _has_anim(anim) and _sprite.animation != anim:
		_sprite.play(anim)


func _has_anim(anim: StringName) -> bool:
	return _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation(anim)


func _update_move_anim(moving: bool) -> void:
	if _sprite.animation == &"death":
		return
	_play(&"walk" if moving and _has_anim(&"walk") else &"idle")
