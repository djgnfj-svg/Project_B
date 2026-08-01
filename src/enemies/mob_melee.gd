extends CharacterBody2D
# 잔몹 공용 배우 — AI는 호스트에서만 구동(rules §1 호스트 권한), 게스트는 mpos/matk 수신 표시만.
# 판정·데미지 확정은 여기 없다 — WINDUP/STRIKE 시점을 EventBus로 알리면 CombatAuthority(호스트)가 확정.
# 수치는 전부 def(.tres)가 쥔다 (rules §4 — 새 잔몹 = 파일 한 장).
#
# 🔴 **근접·원거리를 한 배우가 데이터로 갈라 돈다** (원거리 축 2026-08-01). 갈림 기준은
#   `CombatMath.is_ranged_enemy(def)`(= proj_speed > 0 and proj_range > 0) **하나뿐**이고, 별도 bool
#   플래그는 두지 않는다(두 번째 진실원이 되어 배우 분기와 트립와이어가 갈라진다).
#   선례 = `boss.gd`("어떤 BossDef든 돌리는 데이터 주도 공용 배우")와 `player.gd`의
#   `EquipDef.motion_type` 분기. 배우를 둘로 쪼개면 **배치 함정**이 생긴다 — 원거리 def를 근접
#   씬에 꽂으면 조용히 근접으로 돈다. 데이터가 정하면 그 경로가 원리적으로 없다.
#   ⚠ 파일명 `mob_melee`는 이제 오칭이다(개명하면 .tscn ext_resource·.uid 전수 수정이라 이득이 없다).
#
# 두 형태의 차이는 **사거리 안에서의 행동뿐**이다 — IDLE/CHASE/리시/어그로/HP/동기화는 전부 공유한다:
#   근접: WINDUP(장판 예고) → mob_strike → CombatAuthority가 원형 판정
#   원거리: WINDUP(활 당김) → mob_shoot(실제 투사체 발사) → CombatAuthority가 화살을 추적하며 판정
#           + BACKOFF(keep_dist 안으로 붙으면 물러난다)
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
# 🔴 지형 레이어(1 = world) 마스크 — rules §5 배정표가 단일 소스. `player.ENEMY_BODY_MASK`와 같은 관용구.
#   원거리 몹의 사선(LOS) 질의 전용: 몸(2·3)·픽업(6)은 마스크에 없어 자기 자신·플레이어를 안 맞는다.
const WORLD_MASK := 1 << 0
# 발사 원점 여유(px) — 화살이 몸 안에서 태어나지 않게. 🔴 상수를 크기로 쓰지 않는다:
#   실제 오프셋은 `body_radius + strike_radius + 이 값`이라 몹이 커지든 화살이 굵어지든 자동 추종한다.
const MUZZLE_PAD := 4.0
# 활 당기는 애니 배율의 하한 — 조준 창이 아주 길어도 애니가 사실상 정지해 보이지 않게(연출 안전판).
const MIN_ANIM_SPEED_SCALE := 0.05
# 접지 그림자 (사용자 요청 2026-07-26: "그림자가 잘 붙게해주면 됨" — 잔몹엔 아예 없었다).
# 🔴 텍스처 크기 미러 상수를 새로 만들지 않는다 — shadow.png·몹 시트를 다시 그려도 자동으로 맞게
#   런타임에 읽는다(TELEGRAPH_TEX_SIZE 같은 "텍스처를 고치면 상수도 고쳐야 하는" 함정을 안 늘린다).
const SHADOW_WIDTH_MULT := 2.3   # 그림자 폭 = def.body_radius × 이 배수 (몸보다 살짝 넓어야 접지로 읽힌다)
const SHADOW_ALPHA := 0.5
const SHADOW_FOOT_INSET := 2.0   # 스프라이트 하단에서 이만큼 올려 둔다(발이 그림자를 밟고 선 모습)
# 원거리 조준선 — 연출값 (rules §0 예외)
const AIM_LINE_WIDTH := 1.0
const AIM_LINE_COLOR := Color(0.749, 0.247, 0.180, 0.5)  # #bf3f2e — 40색 팔레트의 경고 붉은
const AIM_ALPHA_START := 0.22    # 조준 시작 — 옅게
const AIM_ALPHA_END := 0.85      # 발사 직전 — 진하게(임박도)

enum State { IDLE, CHASE, WINDUP, RECOVER, BACKOFF }

@export var eid: String = ""
@export var def: EnemyDef

var _state: State = State.IDLE
var _state_left: float = 0.0
var _prev_hp: int = 0  # combat_impact 감소량 계산용
var _strike_center: Vector2 = Vector2.ZERO
var _remote_target: Vector2 = Vector2.ZERO
var _remote_flip: bool = false
var _telegraph_left: float = 0.0
var _is_ranged: bool = false      # def에서 유도(_ready) — CombatMath.is_ranged_enemy 단일 소스
var _aim_dir: Vector2 = Vector2.RIGHT  # WINDUP 진입 시 고정한 발사 방향. 조준 후엔 안 따라간다 —
                                       # "예고를 보고 빠져나갈 수 있어야 한다"(GDD §5 기믹 원칙)
var _shot_seq: int = 0            # 호스트 발사 카운터 — 화살 고유 id "m:<eid>:<seq>" 생성
var _aim_target: Vector2 = Vector2.ZERO   # 조준선이 가리키는 착탄점(= _strike_center)
var _aim_line: Line2D = null              # 원거리 개체만 만든다(근접은 null)
var _aim_total: float = 0.0               # 이번 조준의 총 길이 — 선이 진해지는 진행도 분모
# 🔴 스프라이트 배속의 **유일한 대입 지점**이 쥐는 의도값 (boss._apply_anim_scale 관용구, rules §2).
#   HitStop.punch가 speed_scale을 무조건 1.0으로 리셋하므로 소유자가 매 프레임 재주장해야 한다.
var _anim_scale: float = 1.0

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _collision: CollisionShape2D = $Collision
@onready var _telegraph: Sprite2D = $Telegraph
@onready var _health: HealthComponent = $Health
@onready var _shadow: Sprite2D = $Shadow


# 접지 그림자를 이 개체 크기에 맞춘다 — 폭은 판정 몸 반경, 높이는 스프라이트 하단에서 파생.
# 둘 다 런타임에 읽으므로 몹이 16px든 48px든, 시트를 다시 그려도 따로 손댈 곳이 없다.
func _fit_shadow() -> void:
	var tex := _shadow.texture
	if tex == null or def == null:
		return
	var w := float(tex.get_width())
	if w > 0.0:
		_shadow.scale = Vector2.ONE * (def.body_radius * SHADOW_WIDTH_MULT / w)
	_shadow.modulate = Color(1.0, 1.0, 1.0, SHADOW_ALPHA)
	# 발밑 = 몸 스프라이트 하단(AnimatedSprite2D는 centered라 높이/2). 애니 이름은 idle을 우선하되,
	# 없는 개체(폴백 시트·다른 명명)를 위해 첫 애니로 떨어진다 — 못 찾으면 중앙(0)이라 무해하다.
	var sf := _sprite.sprite_frames
	if sf == null:
		return
	var anim: StringName = &"idle"
	if not sf.has_animation(anim):
		var names := sf.get_animation_names()
		if names.is_empty():
			return
		anim = StringName(names[0])
	if sf.get_frame_count(anim) <= 0:
		return
	var ft := sf.get_frame_texture(anim, 0)
	if ft != null:
		_shadow.position = Vector2(0.0, maxf(0.0, float(ft.get_height()) * 0.5 - SHADOW_FOOT_INSET))


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("mob")
	_remote_target = global_position
	_telegraph.visible = false
	# 근접/원거리 판별은 def 값에서 유도한다 (rules §3 단일 소스) — 배우·트립와이어가 같은 함수를 지난다.
	_is_ranged = CombatMath.is_ranged_enemy(def)
	if _is_ranged:
		_make_aim_line()
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
		_fit_shadow()
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
		EventBus.combat_impact.emit("enemy", global_position, maxi(amount, 0), _health.last_crit)  # 손맛 공용 훅 (crit = 표시 강조)
		if dead:
			EventBus.entity_died.emit("enemy", global_position, def.respawns)  # 사망 SFX (+ 광란 제외 판단)
		else:
			HitStop.punch(_sprite)   # 맞은 대상만 정지+스케일 튕김
			HitFlash.flash(_sprite)  # 흰색 번쩍
			var opp := Flinch.nearest_pos(global_position, get_tree().get_nodes_in_group("player"))
			Flinch.play(_sprite, global_position - opp)  # 플레이어 반대로 흠칫
	else:
		_prev_hp = hp
	if dead:
		_telegraph.visible = false
		_hide_aim_line()   # 죽으면 조준선도 즉시 거둔다 — 남으면 시체가 조준 중인 것처럼 보인다
		velocity = Vector2.ZERO
		_state = State.IDLE
		# 🔴 배속을 반드시 되돌린다 — 당기던 중에 죽으면 늘려 둔 배율(예: 0.28)이 그대로 **death
		#   애니에 걸려** 시체가 슬로모션으로 쓰러진다.
		# 🔴 **의도값만 고치면 안 되고 스프라이트에 직접 심어야 한다** — `_physics_process`가
		#   사망 시 `_apply_anim_scale()` **앞에서** early return하므로 재주장이 다시는 안 돌아,
		#   `_anim_scale`만 1.0으로 둬도 실제 speed_scale은 늘린 값 그대로 굳는다(에러 없음).
		_anim_scale = 1.0
		_sprite.speed_scale = 1.0
		# death 애니가 있으면 시체를 남긴다(loop=false — 마지막 프레임 홀드). 없으면 기존대로 숨김
		if _has_anim(&"death"):
			visible = true
			_play(&"death")
		else:
			visible = false
	else:
		visible = true
		# 🔴 **재생 중인 attack은 덮지 않는다** (원거리 축 2026-08-01). 원거리의 예고는 장판이 아니라
		#   **활 당기는 모션 그 자체**라, 여기서 idle로 갈아 버리면 「예고를 보고 피한다」가 통째로
		#   사라진다 — 그런데 조준 중에 맞는 것은 예외가 아니라 **상시**다(플레이어가 그 몹을 때리고
		#   있으니까). 근접도 같은 방향으로 옳다(예고 마지막 0.12s의 내려침이 피격 한 번에 지워지던 것).
		#   가드 형태는 _update_move_anim과 같다 — 사본이 아니라 같은 규칙이다.
		if not (_sprite.animation == &"attack" and _sprite.is_playing()):
			_play(&"idle")


func _physics_process(delta: float) -> void:
	if _telegraph_left > 0.0:
		var before := _telegraph_left
		_telegraph_left -= delta
		if _is_ranged:
			_update_aim_line()
		# 예비 프레임 길이만큼 앞당겨 재생 → "내려침" 프레임이 텔레그래프 만료(=strike)와 겹친다
		# ⚠ 원거리는 이 규약을 안 쓴다 — 당기는 모션 전체가 조준 창을 채우도록 `_start_draw_anim`이
		#   `speed_scale`을 유도한다(고정 lead는 RTT 가변인 조준 창에 못 맞춘다).
		elif before > ATTACK_ANIM_LEAD_S and _telegraph_left <= ATTACK_ANIM_LEAD_S:
			_play(&"attack")
		if _telegraph_left <= 0.0:
			_telegraph.visible = false
			_hide_aim_line()
	_shadow.visible = not _health.is_dead()  # 시체·부활 대기 중엔 그림자도 없앤다(플레이어 고스트와 같은 규칙)
	if _health.is_dead() or def == null:
		return
	if Net.is_host():
		_host_ai(delta)
		var walking := (_state == State.CHASE or _state == State.BACKOFF) \
			and velocity.length_squared() > 0.0
		_update_move_anim(walking)
	else:
		var moving := global_position.distance_to(_remote_target) > REMOTE_MOVE_EPS
		global_position = global_position.lerp(_remote_target, minf(1.0, REMOTE_LERP_SPEED * delta))
		_sprite.flip_h = _remote_flip
		_update_move_anim(moving)
	# 🔴 **맨 끝에서 배속을 재주장한다** — 소유자가 매 프레임 자기 의도를 다시 심는 관용구
	#   (rules §2 · boss._apply_anim_scale). 이 프레임에 무엇이 speed_scale을 건드렸든 여기가 마지막이다.
	_apply_anim_scale()


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
			var dist := global_position.distance_to(anchor)
			if dist > def.aggro_range * LEASH_MULT:
				velocity = Vector2.ZERO
				_state = State.IDLE  # 리시 초과 — 유령 어그로·무한 카이팅 추격 해제
				return
			# 🔴 원거리: 너무 붙으면 물러난다(카이팅). keep_dist = 0이면 이 분기가 통째로 꺼져
			#   제자리 사격(포탑형)이 된다 — 근접 개체는 _is_ranged가 false라 애초에 안 온다.
			if _is_ranged and def.keep_dist > 0.0 and dist < def.keep_dist:
				_state = State.BACKOFF
				return
			# 🔴 원거리는 **사선(LOS)이 뚫려 있어야** 쏜다 (설계 ⑹ 층①, 2026-08-01).
			#   스테이지 바닥이 TileMapLayer + physics layer 1이 되면서 물·낭떠러지가 실물 벽이 됐다.
			#   이 게이트가 없으면 물 건너 궁수가 일방적으로 쏘는데, 전사만 남은 지금 플레이어에게
			#   답이 없다. 막혀 있으면 WINDUP에 안 들어가고 계속 추격 = **몹이 물을 돌아온다.**
			#   ⚠ 층②(화살 자체의 지형 차단)는 arrow.gd·combat_authority가 따로 진다 — 이건 "결정",
			#     저건 "결과"라 둘 다 필요하다(발사 후 표적이 엄폐물 뒤로 들어가는 경우).
			if dist <= def.attack_range and (not _is_ranged or _has_line_of_sight(anchor)):
				# 타격점 고정 — 예고를 보고 빠져나갈 수 있어야 한다 (GDD §5 기믹 원칙)
				_strike_center = anchor
				_state = State.WINDUP
				# 지연 보상(§3): 예고가 게스트 화면에 뜨기까지 편도 지연만큼 늦는다 — 그만큼 타격도 늦춰야
				# 게스트도 온전한 telegraph_s를 갖는다. 솔로/로컬이면 0이라 기존 동작과 동일(항등).
				var telegraph_total := def.telegraph_s + CombatMath.strike_delay_s(Net.max_remote_one_way_ms())
				_state_left = telegraph_total
				velocity = Vector2.ZERO
				# 호스트 화면은 늘어난 시간만큼 예고를 띄운다 — "보이는 예고 = 맞는 타이밍" 유지.
				# 게스트는 인자 없이 자기 def.telegraph_s를 쓴다(늦게 받아 늦게 시작 → 같은 순간에 끝난다).
				# 🔴 원거리도 **같은 메시지(G_MOB_ATK)를 그대로 탄다** — show_telegraph가 자기 def를 보고
				#   장판 대신 활 당김으로 해석한다(신규 kind 0개, 설계 ⑶ "기존 경로에 데이터로 얹기").
				show_telegraph(_strike_center, telegraph_total)
				EventBus.mob_telegraph.emit(eid, _strike_center)
				return
			velocity = (anchor - global_position).normalized() * def.move_speed
			move_and_slide()
			_face(anchor)
		State.BACKOFF:
			# 원거리 전용 — 사거리를 되찾을 때까지 뒷걸음. 물러나는 중엔 쏘지 않는다(붙으면 사격이
			# 멎는다 = 근접 직업의 접근 보상). 리시를 넘어가면 추격 상태로 돌려 IDLE 판단에 맡긴다.
			var bt := _nearest_alive_player()
			if bt == null:
				velocity = Vector2.ZERO
				_state = State.IDLE
				return
			var bpos := bt.net_anchor()
			var bdist := global_position.distance_to(bpos)
			if bdist >= def.keep_dist or bdist > def.aggro_range * LEASH_MULT:
				velocity = Vector2.ZERO
				_state = State.CHASE
				return
			velocity = (global_position - bpos).normalized() * def.move_speed
			move_and_slide()
			_face(bpos)  # 물러나면서도 플레이어를 본다(조준 자세 유지 — 뒷모습으로 걷지 않는다)
		State.WINDUP:
			if _state_left <= 0.0:
				if _is_ranged:
					_fire_arrow()  # 실제 투사체 — 등록·판정은 CombatAuthority(호스트)
				else:
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


# 텔레그래프 표시 — 호스트는 AI가 직접(지연 보상분 포함한 duration을 넘긴다), 게스트는 matk 수신으로
# (인자 없이 = def.telegraph_s 로컬 리졸브. 편도 지연만큼 늦게 시작하지만 호스트가 그만큼 타격을
#  늦추므로 양쪽 예고가 같은 순간에 끝난다 — §3 지연 보상).
func show_telegraph(center: Vector2, duration: float = -1.0) -> void:
	var dur := duration if duration > 0.0 else (def.telegraph_s if def != null else 0.6)
	if _is_ranged:
		# 🔴 원거리의 예고는 장판이 아니라 **활 당기는 모션 그 자체**다. 같은 G_MOB_ATK를 각 클라가
		#   자기 def로 다르게 해석하는 것이라 **신규 kind가 0개**다(설계 ⑶ — 새 메시지를 만들기 전에
		#   기존 경로에 데이터로 얹을 수 있는지부터 본다).
		# ⚠ center에서 유도한 방향은 **자세(좌우 뒤집기)용 근사**다 — 실제 화살 방향은 G_MOB_SHOOT의
		#   dx/dy가 정확히 싣는다. 게스트의 global_position이 lerp로 조금 낡아도 자세만 어긋난다.
		_aim_dir = _dir_to(center)
		_face(center)
		_start_draw_anim(dur)
		# 조준선 — 근접의 예고 장판에 해당하는 "어디로 쏠지"의 표시. 같은 dur를 쓴다.
		_aim_target = center
		_aim_total = dur
		_telegraph_left = dur      # 근접과 같은 카운트다운을 재사용(만료 시 선을 끈다)
		return
	_telegraph.global_position = center
	_telegraph.visible = true
	_telegraph_left = dur


# 🔴 게스트 전용 진입점 — MobSync가 G_MOB_SHOOT 수신 시 부른다(`show_telegraph`의 미러).
#   호스트는 이 함수를 안 지나고 `_fire_arrow`가 같은 두 가지(놓는 프레임 + mob_shoot)를 한다.
#   양쪽 다 **로컬 EventBus.mob_shoot로 수렴**하므로 표시 경로(ArrowField)는 하나뿐이다.
func play_shoot(origin: Vector2, dir: Vector2, aid: String) -> void:
	# 🔴🔴 **사수 생존을 여기서 보지 마라 — "쏜 화살은 사수 사망과 무관하게 날아간다"가 계약이다**
	#   (리드 결정 2026-08-01, netreview 사망 레이스). 호스트는 `T_d`에 죽고 게스트는 `T_d + 편도`에
	#   죽는다(ehp 도착) — 발사가 그 창에 들어가면 **한쪽만** 화살을 낸다. `is_dead()` 가드를 두면
	#   그 창에서 **게스트만 표시 탄을 버리는데 호스트의 권한 화살은 계속 날아가** 데미지를 확정한다
	#   = "안 보이는데 맞는다"(§3 금지 방향). 화살은 발사 순간에만 사수가 살아 있으면 되고(그 판단은
	#   호스트 AI가 이미 했다) 그 뒤엔 제 수명을 산다 — 취소 메시지가 필요 없어지는 것이 이 계약의 값이다.
	if def == null:
		return
	_aim_dir = dir
	_face(global_position + dir)
	_enter_release_frame()
	EventBus.mob_shoot.emit(eid, origin, dir, aid, def)


# --- 원거리 발사 (호스트 전용 — 등록·판정은 CombatAuthority) ---

# 발사 원점 = 몸 중심에서 조준 방향으로 이만큼. 상수를 크기로 쓰지 않고 데이터에서 유도하므로
# 몹이 커지든(body_radius) 화살이 굵어지든(strike_radius) 따로 손댈 곳이 없다.
func _muzzle_offset() -> float:
	return def.body_radius + def.strike_radius + MUZZLE_PAD


func _fire_arrow() -> void:
	_shot_seq += 1
	# 🔴 **aid 네임스페이스 = "m:<eid>:<seq>"** — 플레이어는 "<peer_id>:<seq>"다(player._fire_projectile).
	#   G_SHOOT 수신부는 `aid.begins_with(str(from_id) + ":")`로 발신자를 검증하는데, 몹 화살은
	#   호스트(id 1)가 보내므로 접두사를 안 갈라 두면 호스트 플레이어 화살의 aid 공간과 겹친다
	#   (같은 aid = 남의 표시 탄을 조기 despawn시키는 코스메틱 그리핑, 2026-07-24 리뷰가 막은 그것).
	#   ⚠ 나중에 몹 화살에 같은 발신자 검증을 미러하려는 사람은 이 접두사를 **면제**해야 한다 —
	#     모르고 그대로 미러하면 정당한 몹 화살이 전부 조용히 거부된다.
	# 🔴 **aid 재사용 금지 — 유일성이 두 축의 곱으로 성립한다** (netreview ③, `G_EXP` dedup과 같은
	#   실패 모드다: 같은 aid가 두 번 나오면 수신 측에 화살이 2개 생기거나, 먼저 죽은 화살의 종료
	#   통지가 **나중 화살을 지운다**).
	#     ⑴ `eid`는 씬 안에서 유일하다(씬에 박아 둔 값 — 동적 스폰이 없다).
	#     ⑵ `_shot_seq`는 이 인스턴스에서 **단조 증가만 하고 절대 리셋되지 않는다.**
	#   씬 전환·방 재입장은 배우·ArrowField·CombatAuthority가 **통째로 새로 태어나므로** 옛 aid가
	#   살아남지 못한다(리셋이 공짜인 이유). 🔴 그래서 `_shot_seq`를 어디서든 0으로 되돌리거나
	#   같은 씬에 같은 `eid`를 두 번 놓으면 그 순간 이 불변식이 깨진다 — 둘 다 하지 마라.
	var aid := "m:" + eid + ":" + str(_shot_seq)
	var origin := global_position + _aim_dir * _muzzle_offset()
	_enter_release_frame()  # 놓는 프레임 = 탄 스폰 순간 (아래 함수 주석이 근거 정본)
	_hide_aim_line()        # 화살이 나갔으니 조준선은 끝 — 남으면 "아직 조준 중"으로 읽힌다
	EventBus.mob_shoot.emit(eid, origin, _aim_dir, aid, def)


# 사선(LOS) — 몹 중심에서 표적까지 지형(layer 1)이 막고 있는가. 호스트 전용(사격 결정용).
# 몸 레이어(2 player_body · 3 enemy_body)는 마스크에 없어 자기 자신도 플레이어도 안 맞는다.
func _has_line_of_sight(target: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(global_position, target, WORLD_MASK)
	q.collide_with_areas = false
	q.collide_with_bodies = true
	return space.intersect_ray(q).is_empty()


# --- 애니 표시 경로 (호스트/게스트 공용 — 판정과 무관) ---

# 🔴 활 당김 애니를 **조준 창 전체에 맞춰 늘린다** (원거리 축 2026-08-01).
#   고정 lead 상수(ATTACK_ANIM_LEAD_S 방식)로는 **원리적으로** 못 맞춘다: 호스트의 조준 창은
#   `telegraph_s + strike_delay_s(RTT)`라 **가변**이라서 어떤 상수를 골라도 지연 0에서만 맞는다.
#   보스가 `.tres` speed 미러를 폐기하고 speed_scale 유도로 간 것과 **같은 이유**(rules §3 2026-07-26).
#   늘리지 않으면 애니(0.375s)가 조준 창(0.9s)보다 짧아 놓는 프레임에서 얼어붙은 채 0.5s를 서 있다가
#   화살이 나간다 — *"활을 놓았는데 화살이 안 나감."* 에러 없음.
# --- 조준선 (원거리 전용, 표시 전용) ---
#
# 사용자 요청 2026-08-01: "화살 쏠 때 빨간색 직선으로 진행 방향 보여주고 쏴줘 — 일반적인 게임처럼".
# 근접의 예고 장판에 해당하는 "어디로 쏠지"의 표시다.
#
# 🔴 **끝점을 `_aim_dir`이 아니라 `center`(착탄점)로 잡는다.** 게스트의 `_aim_dir`은 자기
#   `global_position`(lerp라 조금 낡다)에서 center를 향해 유도한 **근사**라, 방향으로 길게 그으면
#   게스트에서만 각이 어긋나 「보이는 선 ≠ 날아오는 화살」이 된다. `center`는 G_MOB_ATK가 정확히
#   싣는 값이므로 그것을 끝점으로 쓰면 양쪽이 같은 곳을 가리킨다.
# 🔴 **조준 시작에 고정된다** — `_aim_dir`/`_aim_target` 둘 다 WINDUP 진입 때 정하고 그 뒤 안
#   따라간다. 매 프레임 재조준하면 선을 보고 피할 수 없어 예고의 의미가 사라진다(GDD §5 기믹 원칙).
func _make_aim_line() -> void:
	_aim_line = Line2D.new()
	_aim_line.width = AIM_LINE_WIDTH
	_aim_line.default_color = AIM_LINE_COLOR
	_aim_line.z_index = -1          # 잔몹 텔레그래프와 같은 층 — 몸·FX 아래, 바닥 위 (rules §5 z표)
	_aim_line.top_level = true      # 부모 flip_h를 안 따라간다(따라가면 선이 좌우로 뒤집힌다)
	_aim_line.visible = false
	add_child(_aim_line)


func _update_aim_line() -> void:
	if _aim_line == null:
		return
	# 🔴 사망 가드 — 이 함수는 `_physics_process`의 예고 카운트다운 블록에서 불리고, **그 블록은
	#   `is_dead()` 가드보다 앞에 있다**(죽어도 예고가 제 수명을 마치는 기존 동작). 가드가 없으면
	#   `_on_hp_changed`가 껐던 선을 다음 프레임에 다시 켜서 **시체가 계속 조준한다.**
	#   폐기된 「표시 전용 화살」 구현에서 "죽은 적이 화살을 쏜다"로 한 번 밟은 것과 같은 구조다.
	if _health.is_dead():
		_aim_line.visible = false
		return
	# top_level이라 좌표계가 전역이다. 시작점은 매 프레임 갱신한다 — 게스트에서 몸이 lerp로
	# 움직이는 동안 선이 몸에서 떨어져 보이지 않게.
	_aim_line.points = PackedVector2Array([global_position, _aim_target])
	# 조준이 찰수록 진해진다 — 임박도를 색이 아니라 알파로 읽게 한다(일반적인 조준 연출).
	var p := 1.0 - clampf(_telegraph_left / maxf(_aim_total, 0.001), 0.0, 1.0)
	var c := AIM_LINE_COLOR
	c.a = lerpf(AIM_ALPHA_START, AIM_ALPHA_END, p)
	_aim_line.default_color = c
	_aim_line.visible = true


func _hide_aim_line() -> void:
	if _aim_line != null:
		_aim_line.visible = false


func _start_draw_anim(aim_total: float) -> void:
	if not _has_anim(&"attack"):
		return
	var pre := _draw_pre_release_s()
	# 못 구하는 경우(1프레임 attack·speed 0·창 ≤ 0)는 1.0 = 항등 폴백 — boss._attack_speed_scale과 같은 규약.
	_anim_scale = 1.0 if (pre <= 0.0 or aim_total <= 0.0) \
		else maxf(pre / aim_total, MIN_ANIM_SPEED_SCALE)
	# 🔴 **force_restart** — `_play()`는 같은 애니를 리스타트하지 않고, `play()`도 **재생 중인** 같은
	#   애니는 이어서 돈다(boss.gd 4.7 실측). 없으면 두 번째 사격부터 당기는 모션이 통째로 안 나온다.
	_play(&"attack", true)
	_apply_anim_scale()


# 놓는 프레임(마지막) **직전까지의** 자연 재생 시간(초) — sprite_frames에서 읽으므로 아트가
# 프레임을 늘려도 자동 추종한다(미러 상수를 새로 만들지 않는다).
func _draw_pre_release_s() -> float:
	var sf := _sprite.sprite_frames
	if sf == null or not sf.has_animation(&"attack"):
		return 0.0
	var n := sf.get_frame_count(&"attack")
	var speed := sf.get_animation_speed(&"attack")
	if n <= 1 or speed <= 0.0:
		return 0.0
	var total := 0.0
	for i: int in range(n - 1):
		total += sf.get_frame_duration(&"attack", i)
	return total / speed


# 🔴 **"놓는 프레임 시작 = 탄 스폰"을 산술이 아니라 구조로 못 박는다.**
#   `_start_draw_anim`의 speed_scale 유도만으로도 이론상 맞지만 프레임 양자화·히트스톱 정지분이
#   누적되면 한두 프레임 어긋난다. 발사 시점에 **명시적으로** 마지막 프레임으로 점프시키면
#   호스트·게스트 어느 쪽에서도 어긋날 축이 남지 않는다(양쪽 다 이 함수를 지난다).
#   배속은 여기서 1.0으로 돌린다 — 늘린 것은 **당기는 구간**이고 놓는 동작까지 느리면 맥이 빠진다.
func _enter_release_frame() -> void:
	_anim_scale = 1.0
	_sprite.speed_scale = 1.0
	if not _has_anim(&"attack"):
		return
	var n := _sprite.sprite_frames.get_frame_count(&"attack")
	if n <= 0:
		return
	if _sprite.animation != &"attack":
		_sprite.play(&"attack")
	_sprite.set_frame_and_progress(n - 1, 0.0)


# 🔴 스프라이트 배속의 **유일한 대입 지점** — 소유자가 매 물리 프레임 자기 의도를 재주장한다
#   (rules §2 · boss._apply_anim_scale과 같은 관용구).
#   `HitStop.punch`가 `speed_scale`을 **무조건 1.0으로** 리셋하기 때문인데, 원거리 몹은
#   **당기는 중에 맞는 것이 상시**라(플레이어가 그 몹을 때리고 있다) 엣지 케이스가 아니다 —
#   재주장이 없으면 늘려 둔 당김이 피격 한 번에 원속도로 돌아가 놓는 프레임이 일찍 온다.
# 🔴 **0(정지) 중에는 건드리지 않는다 — 그게 히트스톱 본체다.** 덮으면 히트스톱이 사라진다.
#   ⚠ hit_stop 쪽을 meta 저장 방식으로 "고치지" 마라(rules §2가 명시적으로 금지) — 회차마다
#     배율이 달라지는 소유자에게는 첫 회차 값이 영구 base로 굳는다.
func _apply_anim_scale() -> void:
	if _sprite.speed_scale <= 0.0:
		return
	if not is_equal_approx(_sprite.speed_scale, _anim_scale):
		_sprite.speed_scale = _anim_scale


# 표적 쪽을 본다 — 좌우 뒤집기 단일 진입점(추격·후퇴·조준이 같은 규칙을 쓴다).
func _face(target: Vector2) -> void:
	if absf(target.x - global_position.x) > 0.001:
		_sprite.flip_h = target.x < global_position.x


func _dir_to(target: Vector2) -> Vector2:
	var d := target - global_position
	return d.normalized() if d.length() > 0.001 else Vector2.RIGHT


func _play(anim: StringName, force_restart: bool = false) -> void:
	if not _has_anim(anim):
		return
	if force_restart or _sprite.animation != anim:
		_sprite.play(anim)
	if force_restart:
		# play()는 **재생 중인** 같은 애니를 이어서 돌린다(boss.gd 실측) — 명시로 못 박는다.
		_sprite.set_frame_and_progress(0, 0.0)


func _has_anim(anim: StringName) -> bool:
	return _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation(anim)


func _update_move_anim(moving: bool) -> void:
	# attack(one-shot)이 도는 동안은 덮지 않는다 — 끝나면 walk/idle로 복귀
	if _sprite.animation == &"attack" and _sprite.is_playing():
		return
	_play(&"walk" if moving else &"idle")
