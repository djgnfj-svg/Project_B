extends CharacterBody2D
# 근접 추격형 잔몹 — AI는 호스트에서만 구동(rules §1 호스트 권한), 게스트는 mpos/matk 수신 표시만.
# 판정·데미지 확정은 여기 없다 — WINDUP/STRIKE 시점을 EventBus로 알리면 CombatAuthority(호스트)가 확정.
# 수치는 전부 def(.tres)가 쥔다 (rules §4 — 새 근접형 = 파일 한 장).
# ⚠ 씬 전용 글루(오토로드 전역 식별자 사용) — -s 헤드리스 테스트에서 preload 금지 (rules §5).

const HealthComponent := preload("res://src/combat/health_component.gd")
const PlayerActor := preload("res://src/player/player.gd")
const HitStop := preload("res://src/feel/hit_stop.gd")
const HitFlash := preload("res://src/feel/hit_flash.gd")
const Flinch := preload("res://src/feel/flinch.gd")

# 연출값 (rules §0 예외)
const REMOTE_LERP_SPEED := 12.0
const TELEGRAPH_TEX_SIZE := 32.0  # telegraph.png 지름(px) — strike_radius 스케일 기준
# attack 애니 선행 재생(초) — 예비 프레임(f6, 120ms)이 끝나는 순간 = 텔레그래프 만료 = mob_strike.
# frames.tres의 attack 첫 프레임 duration과 미러 (rules §3 "보이는 휘두름 = 맞는 타이밍").
const ATTACK_ANIM_LEAD_S := 0.12
const REMOTE_MOVE_EPS := 1.0      # 게스트 표시: 목표점과 이만큼 이상 벌어져 있으면 walk
# 추격 이탈 거리 = aggro_range × 이 배수. ⚠ 씬 스왑 프레임엔 이전 씬 플레이어가 "player" 그룹에
# 아직 남아 있어(queue_free는 프레임 끝) 게이트 앞 좌표로 유령 어그로가 잡힌다 — CHASE에 이탈
# 조건이 없으면 그 한 프레임이 영구 추격으로 굳는다 (챕터1 실기에서 발견, 간헐 레이스)
const LEASH_MULT := 1.5

enum State { IDLE, CHASE, WINDUP, RECOVER }

@export var eid: String = ""
@export var def: EnemyDef

var _state: State = State.IDLE
var _state_left: float = 0.0
var _prev_hp: int = 0  # combat_impact 감소량 계산용
var _strike_center: Vector2 = Vector2.ZERO
var _remote_target: Vector2 = Vector2.ZERO
var _remote_flip: bool = false
var _telegraph_left: float = 0.0

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _collision: CollisionShape2D = $Collision
@onready var _telegraph: Sprite2D = $Telegraph
@onready var _health: HealthComponent = $Health


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("mob")
	_remote_target = global_position
	_telegraph.visible = false
	if def != null:
		if def.frames != null:
			_sprite.sprite_frames = def.frames
		elif def.sprite != null:
			# 애니 없는 개체 폴백 — sprite 1장을 idle로 감싼다 (EnemyDef.frames 주석과 미러)
			var sf := SpriteFrames.new()
			sf.rename_animation(&"default", &"idle")
			sf.add_frame(&"idle", def.sprite)
			_sprite.sprite_frames = sf
		# 몸 판정 반경 = def.body_radius — ⚠ shape 리소스는 씬 인스턴스 간 공유라 직접 만지면
		# 같은 tscn의 다른 개체까지 바뀐다 → 복제 후 적용 (조용히 깨지는 함정)
		var shape := _collision.shape.duplicate() as CircleShape2D
		if shape != null:
			shape.radius = def.body_radius
			_collision.shape = shape
		_health.setup(def.max_hp, def.respawns, def.respawn_delay)
		_prev_hp = def.max_hp
		# 텔레그래프 표시 반경 = 판정 반경(def.strike_radius) — "맞는 곳=보이는 곳" (rules §3)
		_telegraph.scale = Vector2.ONE * (def.strike_radius * 2.0 / TELEGRAPH_TEX_SIZE)
	_health.hp_changed.connect(_on_hp_changed)
	# 권한 경로(호스트 apply_damage)에서만 발화 — CombatAuthority가 ehp 브로드캐스트 + 클리어 판정.
	# 이 연결이 없으면 게스트 화면에 시체가 남고 클리어가 영영 안 뜬다 (enemy.gd 글루와 동일 규약).
	_health.hp_confirmed.connect(func(hp: int) -> void: EventBus.enemy_hp_confirmed.emit(eid, hp))
	_play(&"idle")


func _on_hp_changed(hp: int, dropped: bool) -> void:
	var dead := hp <= 0
	_collision.set_deferred("disabled", dead)
	if dropped:
		var amount := _prev_hp - hp
		_prev_hp = hp
		EventBus.combat_impact.emit("enemy", global_position, maxi(amount, 0))  # 손맛 공용 훅
		if dead:
			EventBus.entity_died.emit("enemy", global_position)  # 사망 SFX
		else:
			HitStop.punch(_sprite)   # 맞은 대상만 정지+스케일 튕김
			HitFlash.flash(_sprite)  # 흰색 번쩍
			var opp := Flinch.nearest_pos(global_position, get_tree().get_nodes_in_group("player"))
			Flinch.play(_sprite, global_position - opp)  # 플레이어 반대로 흠칫
	else:
		_prev_hp = hp
	if dead:
		_telegraph.visible = false
		velocity = Vector2.ZERO
		_state = State.IDLE
		# death 애니가 있으면 시체를 남긴다(loop=false — 마지막 프레임 홀드). 없으면 기존대로 숨김
		if _has_anim(&"death"):
			visible = true
			_play(&"death")
		else:
			visible = false
	else:
		visible = true
		_play(&"idle")


func _physics_process(delta: float) -> void:
	if _telegraph_left > 0.0:
		var before := _telegraph_left
		_telegraph_left -= delta
		# 예비 프레임 길이만큼 앞당겨 재생 → "내려침" 프레임이 텔레그래프 만료(=strike)와 겹친다
		if before > ATTACK_ANIM_LEAD_S and _telegraph_left <= ATTACK_ANIM_LEAD_S:
			_play(&"attack")
		if _telegraph_left <= 0.0:
			_telegraph.visible = false
	if _health.is_dead() or def == null:
		return
	if Net.is_host():
		_host_ai(delta)
		_update_move_anim(_state == State.CHASE and velocity.length_squared() > 0.0)
	else:
		var moving := global_position.distance_to(_remote_target) > REMOTE_MOVE_EPS
		global_position = global_position.lerp(_remote_target, minf(1.0, REMOTE_LERP_SPEED * delta))
		_sprite.flip_h = _remote_flip
		_update_move_anim(moving)


func _host_ai(delta: float) -> void:
	_state_left -= delta
	match _state:
		State.IDLE:
			var t := _nearest_alive_player()
			if t != null and global_position.distance_to(t.net_anchor()) <= def.aggro_range:
				_state = State.CHASE
		State.CHASE:
			var t := _nearest_alive_player()
			if t == null:
				velocity = Vector2.ZERO
				_state = State.IDLE
				return
			var anchor := t.net_anchor()
			if global_position.distance_to(anchor) > def.aggro_range * LEASH_MULT:
				velocity = Vector2.ZERO
				_state = State.IDLE  # 리시 초과 — 유령 어그로·무한 카이팅 추격 해제
				return
			if global_position.distance_to(anchor) <= def.attack_range:
				# 타격점 고정 — 예고를 보고 빠져나갈 수 있어야 한다 (GDD §5 기믹 원칙)
				_strike_center = anchor
				_state = State.WINDUP
				_state_left = def.telegraph_s
				velocity = Vector2.ZERO
				show_telegraph(_strike_center)
				EventBus.mob_telegraph.emit(eid, _strike_center)
				return
			velocity = (anchor - global_position).normalized() * def.move_speed
			move_and_slide()
			_sprite.flip_h = velocity.x < 0.0
		State.WINDUP:
			if _state_left <= 0.0:
				EventBus.mob_strike.emit(eid, _strike_center)  # 판정·확정은 CombatAuthority
				_state = State.RECOVER
				_state_left = def.attack_cooldown_s
		State.RECOVER:
			if _state_left <= 0.0:
				_state = State.CHASE


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


# --- MobSync용 API (호스트 송신 배치 / 게스트 수신 반영) ---

func get_sync_state() -> Array:
	return [eid, global_position.x, global_position.y, _sprite.flip_h]


func apply_remote_pos(pos: Vector2, flip: bool) -> void:
	_remote_target = pos
	_remote_flip = flip


# 텔레그래프 표시 — 호스트는 AI가 직접, 게스트는 matk 수신으로. 지속 = def.telegraph_s 로컬 리졸브
func show_telegraph(center: Vector2) -> void:
	_telegraph.global_position = center
	_telegraph.visible = true
	_telegraph_left = def.telegraph_s if def != null else 0.6


# --- 애니 표시 경로 (호스트/게스트 공용 — 판정과 무관) ---

func _play(anim: StringName) -> void:
	if _has_anim(anim) and _sprite.animation != anim:
		_sprite.play(anim)


func _has_anim(anim: StringName) -> bool:
	return _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation(anim)


func _update_move_anim(moving: bool) -> void:
	# attack(one-shot)이 도는 동안은 덮지 않는다 — 끝나면 walk/idle로 복귀
	if _sprite.animation == &"attack" and _sprite.is_playing():
		return
	_play(&"walk" if moving else &"idle")
