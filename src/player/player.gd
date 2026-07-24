extends CharacterBody2D
# 플레이어 배우 — 로컬(입력 구동) / 원격(수신 보간) 겸용.
# 자기 위치·공격 입력은 자기가 소유하고, 데미지 확정은 호스트가 한다 (rules §1·§3).
# 조작(GDD §5 v1.5): WASD 이동, 마우스 조준(2방향 플립), 좌클릭 공격, Shift 구르기.

const NetSchema := preload("res://src/core/net_schema.gd")
const HealthComponent := preload("res://src/combat/health_component.gd")
const HitStop := preload("res://src/feel/hit_stop.gd")
const HitFlash := preload("res://src/feel/hit_flash.gd")
const Flinch := preload("res://src/feel/flinch.gd")
const DEFAULT_SWOOSH := preload("res://assets/sprites/fx/swoosh_arc.png")  # 무기가 궤적을 안 지정할 때 폴백

# 연출값 (rules §0 예외 — 사용자가 플레이하며 조인다)
# ⚠ 구르기 시간·쿨다운은 여기 없다 — CombatMath.ROLL_TIME_S/ROLL_COOLDOWN_S(§3 단일 소스,
#   호스트 i-frame 검증과 같은 값). 사본을 만들면 무적 창과 이동이 갈라진다.
const REMOTE_LERP_SPEED := 12.0
const POS_SEND_RATE := 15.0
const REMOTE_TINT := Color(1.0, 0.75, 0.75)
const ROLL_SPEED_MULT := 2.6
const GHOST_ALPHA := 0.4
const ATTACK_FX_DELAY := 0.07        # 예비동작이 끝나고 스윕이 시작될 때 궤적을 표시
const ATTACK_FX_TIME := 0.18         # 궤적 잔상 페이드 시간
const SWOOSH_TEX_RADIUS := 46.0      # swoosh_arc.png의 호 바깥 반지름(px) — FX 스케일 기준 (텍스처와 미러)
# ⚠ 미러(rules §3): 스윙 창은 모든 JobDef.attack_cooldown보다 짧아야 한다 (전사 0.4s) —
#   원격 창-잠금 가드(play_attack_fx)가 정당한 연속 공격의 스윙을 무시하지 않으려면.
#   이 3상수는 무장 해제/폴백 기본값이고, 무기별 실값은 EquipDef.swing_time/arc/lunge(→ _swing_*).
const ATTACK_ANIM_TIME := 0.25       # 스윙 창 기본값(폴백) — 무기별은 EquipDef.swing_time
const SWING_HALF_ARC := 1.9          # 스윙 호 반각(rad) 기본값(폴백) — 무기별은 EquipDef.swing_arc
const WEAPON_AIM_LERP := 18.0        # 원격 조준각 보간 속도
const HOLD_DIST := 8.0               # 몸 중심 → 그립 거리 (몸에 붙지 않게 떨어뜨려 든다)
const LUNGE_DIST := 5.0              # 스윕 중 앞으로 내지르는 거리
const REMOTE_MAX_SPEED_MULT := 1.5  # 원격 변위 클램프 여유 — 순간이동 스푸핑 완화 (rules §3)
const ENEMY_BODY_MASK := 1 << 2  # 물리 레이어 3 enemy_body — rules §5 배정표가 단일 소스

@export var job: JobDef

var peer_id: int = 0
var is_local: bool = false
var scene_id: String = ""  # 소속 씬 (net_schema SCENE_*) — G_POS에 실어 다른 씬 피어의 유령 스폰 방지
var seated: bool = false  # 모닥불 앉기 (campfire 씬이 켠다) — 이동·구르기·공격 입력이 들어오면 스스로 풀린다. 공지(G_SIT)는 campfire가 상태 변화를 보고 송신
var equip_atk_bonus: int = 0  # 착용 장비 공격 보너스 (G_STATS 공지/수신) — 호스트가 calc_damage에 더한다
var equip_hp_bonus: int = 0   # 착용 장비 체력 보너스 — max_hp = job.max_hp + 이 값 (set_max_hp로 이월 HP 보존)

# 무기 겉모습 — 착용 무기(EquipDef.weapon_texture)에서 그린다. 미착용이면 직업 기본 무기로 폴백.
# _weapon_grip은 _update_weapon이 매 프레임 참조 → 착용/직업에 따라 바뀌므로 멤버로 보관(job.weapon_grip 직참 금지).
var _weapon_grip: Vector2 = Vector2(4.0, 8.0)
var _weapon_override: EquipDef = null       # 마지막 착용 무기 — set_job 재호출(재공지/재합류) 시 겉모습 유지용 보관. null = 무장 해제

# 무기 손맛 — set_weapon_visual이 착용 무기(EquipDef)에서 세팅, 미착용/미지정이면 기본값 폴백. 전부 표시 전용(네트워크 0).
var _swoosh_radius: float = SWOOSH_TEX_RADIUS  # 현재 궤적 텍스처의 바깥 반지름 — FX 스케일 정합(§3)
var _swing_color: Color = Color(1, 1, 1, 1)    # 궤적 틴트(페이드 알파와 곱해 적용)
var _swing_sfx: String = "swing"               # 스윙(휘두름) 효과음 id
var _hit_sfx: String = ""                       # 적중 시 무기 고유 타격음 id (비면 무음)
var _hit_shake: float = 1.5                     # 적중 시 스크린셰이크 강도
# 스윙 모션(무기별) — 기본값 = 대검 기준(폴백). ⚠ _swing_time < job.attack_cooldown 유지 (rules §3)
var _swing_arc: float = SWING_HALF_ARC
var _swing_time: float = ATTACK_ANIM_TIME
var _swing_lunge: float = LUNGE_DIST

var _remote_target: Vector2 = Vector2.ZERO
var _remote_flip: bool = false
var _send_accum: float = 0.0
var _attack_cd_left: float = 0.0
var _roll_time_left: float = 0.0
var _roll_cd_left: float = 0.0
var _roll_dir: Vector2 = Vector2.RIGHT
var _fx_left: float = 0.0
var _fx_delay_left: float = 0.0
var _fx_dir: Vector2 = Vector2.RIGHT
var _attack_queued: bool = false
var _last_remote_msec: int = -1
var _alive: bool = true
var _saved_layer: int = 0
var _saved_mask: int = 0
var _remote_roll_left: float = 0.0  # 원격 구르기 연출 창 (G_ROLL 수신 — 표시 전용, 판정 아님)
var _attack_anim_left: float = 0.0  # 공격 스윙 창 — 로컬은 공격 발동, 원격은 G_ATK 수신 시 (표시 전용)
var _aim_angle: float = 0.0  # 무기 조준각 — 로컬은 마우스, 원격은 _remote_aim으로 보간
var _remote_aim: float = 0.0  # G_POS "a" 수신 목표각 (표시 전용, 판정 아님)
var _remote_moving: bool = false
var _swamp_factors: Array[float] = []  # 현재 겹친 늪들의 이동 배율 (SwampZone enter/exit로 추가·제거). 걷기 속도에 min 적용, 구르기 예외

var _prev_hp: int = 0  # 피격 손맛(combat_impact 감소량) 계산용 — hp_changed 표시 경로 추적

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _attack_fx: Sprite2D = $AttackFx
@onready var _health: HealthComponent = $Health
@onready var _weapon_pivot: Node2D = $WeaponPivot
@onready var _weapon: Sprite2D = $WeaponPivot/Weapon
@onready var _camera: Camera2D = $Camera
@onready var _shadow: Sprite2D = $Shadow
@onready var _dust: CPUParticles2D = $Dust


func _ready() -> void:
	add_to_group("player")
	_saved_layer = collision_layer
	_saved_mask = collision_mask
	# 권한 경로(호스트의 apply_damage/confirm_hp)에서만 발화 — 게스트 표시 경로는 confirm_hp_from_net이 별도 emit
	_health.hp_confirmed.connect(_on_hp_confirmed)
	# 표시 경로(모든 클라 — 호스트 apply_damage·게스트 set_hp_display 둘 다) — 피격 손맛 연출
	_health.hp_changed.connect(_on_hp_changed_feel)
	if job != null:
		_health.setup(job.max_hp)
		_prev_hp = job.max_hp


func setup(p_peer_id: int, p_is_local: bool, spawn_pos: Vector2, p_scene_id: String) -> void:
	peer_id = p_peer_id
	is_local = p_is_local
	scene_id = p_scene_id
	global_position = spawn_pos
	_remote_target = spawn_pos
	_camera.enabled = is_local  # 로컬 플레이어만 현재 카메라 (원격 인스턴스는 뷰포트 안 잡음)
	if not is_local:
		_sprite.modulate = REMOTE_TINT
	set_job(job)


# 직업 적용 — 애니 프레임까지 교체. 원격은 G_JOB 공지 수신 시 stage가 다시 부른다.
func set_job(j: JobDef) -> void:
	if j == null:
		return
	job = j
	if j.frames != null:
		_sprite.sprite_frames = j.frames
		_sprite.play("idle")
	# 무기 겉모습은 착용 무기(EquipDef)에서만 그린다(무기 = 장비). 직업 재공지/재합류로 set_job이
	# 다시 불려도 override(마지막 착용) 재적용해 겉모습 유지. 미착용이면 무장 해제(무기 미표시).
	set_weapon_visual(_weapon_override)
	if is_node_ready():
		# setup이 아니라 set_max_hp — 직업 재공지가 챕터 이월 HP(호스트 확정)를 풀피로 되돌리지 않게
		_health.set_max_hp(j.max_hp + equip_hp_bonus)  # 장비 체력 보너스 유지


# 장비 총 스탯 반영 — 로컬은 GameState.current_stats(), 원격은 G_STATS 수신(peer_sync가 부른다). max_hp 재계산.
func set_equip_stats(atk: int, hp: int) -> void:
	equip_atk_bonus = maxi(0, atk)
	equip_hp_bonus = maxi(0, hp)
	_apply_max_hp()


func _apply_max_hp() -> void:
	if job != null and is_node_ready():
		_health.set_max_hp(job.max_hp + equip_hp_bonus)


# 무기 겉모습 적용 — 착용 무기(equip)의 텍스처/그립, 없으면(null·텍스처 없음) 직업 기본 무기로 폴백.
# 로컬은 peer_sync가 GameState 착용 무기로, 원격은 G_STATS의 weapon id 리졸브로 부른다 (표시 전용, 판정 무관).
func set_weapon_visual(equip: EquipDef) -> void:
	_weapon_override = equip  # 재공지/재합류 대비 마지막 착용 무기 보관 (set_job이 재적용)
	var tex: Texture2D = null  # 미착용 = 무장 해제 (직업 폴백 없음 — 무기 = 장비)
	var grip := Vector2(4.0, 8.0)
	if equip != null and equip.weapon_texture != null:
		tex = equip.weapon_texture
		grip = equip.weapon_grip
	_weapon.texture = tex
	_weapon_grip = grip
	_weapon.position = -grip + Vector2(HOLD_DIST, 0.0)
	_weapon_pivot.visible = tex != null
	_apply_weapon_feel(equip)


# 무기 손맛(궤적 텍스처·반지름·색·SFX·타격 셰이크) 반영 — 착용 무기가 지정하면 그 값, 아니면 기본 swoosh.
# set_weapon_visual이 로컬·원격 모두 부르므로 무기 교체 시 손맛도 자동으로 갈린다 (표시 전용, 판정 무관).
func _apply_weapon_feel(equip: EquipDef) -> void:
	if equip != null and equip.swing_texture != null:
		_attack_fx.texture = equip.swing_texture
		_swoosh_radius = maxf(1.0, equip.swing_tex_radius)
		_swing_color = equip.swing_color
	else:
		_attack_fx.texture = DEFAULT_SWOOSH
		_swoosh_radius = SWOOSH_TEX_RADIUS
		_swing_color = Color(1, 1, 1, 1)
	_swing_sfx = equip.swing_sfx if equip != null and not equip.swing_sfx.is_empty() else "swing"
	_hit_sfx = equip.hit_sfx if equip != null else ""
	_hit_shake = equip.hit_shake if equip != null else 1.5
	# 스윙 모션 — 무기 지정값, 미착용이면 대검 기본. swing_time은 §3 미러(< attack_cooldown) 유지.
	_swing_arc = equip.swing_arc if equip != null else SWING_HALF_ARC
	_swing_time = equip.swing_time if equip != null else ATTACK_ANIM_TIME
	_swing_lunge = equip.swing_lunge if equip != null else LUNGE_DIST


# 궤적 페이드 색 — 무기 틴트 rgb 유지, 알파만 페이드로 구동
func _fx_color(alpha: float) -> Color:
	return Color(_swing_color.r, _swing_color.g, _swing_color.b, alpha * _swing_color.a)


func is_alive() -> bool:
	return _alive


# 호스트가 자기 로컬 플레이어의 i-frame을 직접 조회 (원격 피어는 G_ROLL 그랜트 창으로 판정)
func is_rolling() -> bool:
	return _roll_time_left > 0.0


# --- 늪 슬로우 (SwampZone이 로컬 플레이어 겹칠 때만 호출 — 네트워크 0, 이동은 각자 소유 rules §3) ---
# 여러 늪이 겹치면 가장 느린 배율(min)을 걷기 속도에 적용. exit는 factor를 받아 정확히 그 늪 항목만 제거
# (여러 늪 배율이 다를 때 min 재계산이 어긋나지 않게 — 현재는 def.swamp_slow_factor 하나라 전부 동일).
func enter_swamp(factor: float) -> void:
	_swamp_factors.append(factor)


func exit_swamp(factor: float) -> void:
	var idx := _swamp_factors.find(factor)
	if idx >= 0:
		_swamp_factors.remove_at(idx)


# 현재 유효 걷기 배율 — 겹친 늪 없으면 1.0, 있으면 가장 느린 값. 구르기엔 적용 안 한다(탈출 수단).
func _swamp_mult() -> float:
	var m := 1.0
	for f: float in _swamp_factors:
		m = minf(m, f)
	return m


# 게스트 수신 경로 — php 브로드캐스트 반영. 타이머 없는 표시 전용 (§3: 자기 HP도 이것만 믿는다)
func confirm_hp_from_net(p_hp: int) -> void:
	_health.set_hp_display(p_hp)
	GameState.record_party_hp(peer_id, p_hp)  # 챕터 스테이지 간 이월 기록 — 확정 경로만 쓴다
	EventBus.player_hp_confirmed.emit(peer_id, p_hp)
	_update_life_state(p_hp)


func _on_hp_confirmed(p_hp: int) -> void:
	GameState.record_party_hp(peer_id, p_hp)  # 챕터 스테이지 간 이월 기록 — 확정 경로만 쓴다
	EventBus.player_hp_confirmed.emit(peer_id, p_hp)
	_update_life_state(p_hp)


# 표시 경로(모든 클라) 피격 손맛 — 이 인스턴스(로컬·원격 무관)의 HP가 실제로 감소했을 때.
# combat_impact(카메라 셰이크·데미지 숫자·SFX 공용 훅) + 히트스톱(맞은 대상 스프라이트만).
# i-frame(구르기) 중엔 호스트가 데미지를 확정하지 않아 hp가 안 떨어진다 → 여기 안 온다(거짓 연출 없음).
func _on_hp_changed_feel(new_hp: int, dropped: bool) -> void:
	var amount := _prev_hp - new_hp
	_prev_hp = new_hp
	if not dropped or amount <= 0:
		return  # 회복·부활·최대치 조정은 손맛 대상 아님
	EventBus.combat_impact.emit("player", global_position, amount)
	if new_hp > 0:
		HitStop.punch(_sprite)
		HitFlash.flash(_sprite)  # 흰색 번쩍
		var opp := Flinch.nearest_pos(global_position, get_tree().get_nodes_in_group("enemy"))
		Flinch.play(_sprite, global_position - opp)  # 피격원 반대로 흠칫
	else:
		EventBus.screen_shake.emit(5.0)  # 사망은 강하게
		EventBus.entity_died.emit("player", global_position)


# 사망 = 관전 고스트 (GDD §5): 공격·구르기 차단, 이동은 자유(충돌 off), G_POS는 계속 송신
# (송신을 멈추면 부활 순간 원격 변위 클램프가 순간이동을 기어가는 걸로 만든다 — 앵커 연속성 유지)
func _update_life_state(p_hp: int) -> void:
	var now_alive := p_hp > 0
	if now_alive == _alive:
		return
	_alive = now_alive
	seated = false  # 사망/부활 어느 쪽이든 앉기 해제 — 시체가 앉아서 회복받는 상태 방지
	if _alive:
		collision_layer = _saved_layer
		collision_mask = _saved_mask
		_sprite.visible = true
		_sprite.modulate.a = 1.0
		_shadow.visible = true
	else:
		collision_layer = 0
		collision_mask = 0
		_shadow.visible = false  # 관전 고스트는 그림자 없음(떠 있는 느낌)
		_dust.emitting = false
		_attack_fx.visible = false
		_fx_delay_left = 0.0  # 예약된 궤적도 취소 — 시체에서 스워시가 뜨지 않게
		_roll_time_left = 0.0
		_remote_roll_left = 0.0
		_attack_anim_left = 0.0  # 사망 직전 발동한 공격 스윙이 고스트에 남지 않게
		if is_local:
			_sprite.modulate.a = GHOST_ALPHA
		else:
			_sprite.visible = false


func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	if is_local:
		_local_move(delta)
		_local_combat()
		_send_pos(delta)
	else:
		_remote_moving = global_position.distance_to(_remote_target) > 1.0
		global_position = global_position.lerp(_remote_target, minf(1.0, REMOTE_LERP_SPEED * delta))
		_sprite.flip_h = _remote_flip
	_update_anim()
	_update_weapon(delta)
	_update_dust()


# 이동/구르기 중 발밑 먼지 (로컬=속도, 원격=수신 이동). 사망 시 정지.
func _update_dust() -> void:
	var moving := velocity.length() > 8.0 if is_local else _remote_moving
	_dust.emitting = _alive and moving


func _tick_timers(delta: float) -> void:
	_attack_cd_left = maxf(0.0, _attack_cd_left - delta)
	_roll_cd_left = maxf(0.0, _roll_cd_left - delta)
	_remote_roll_left = maxf(0.0, _remote_roll_left - delta)
	_attack_anim_left = maxf(0.0, _attack_anim_left - delta)
	if _fx_delay_left > 0.0:
		_fx_delay_left -= delta
		if _fx_delay_left <= 0.0:
			# 궤적 표시 — 플레이어 중심 회전, 크기는 판정 기하(§3 단일 소스)에서 파생해 "맞는 곳=보이는 곳" 유지
			var reach := CombatMath.attack_center_offset(_fx_dir, job).length() + CombatMath.attack_radius(job)
			_attack_fx.rotation = _fx_dir.angle()
			_attack_fx.position = Vector2.ZERO
			_attack_fx.scale = Vector2.ONE * (reach / _swoosh_radius)  # 무기별 궤적 반지름 정합(§3)
			_attack_fx.modulate = _fx_color(1.0)
			_attack_fx.visible = true
			_fx_left = ATTACK_FX_TIME
	if _fx_left > 0.0:
		_fx_left -= delta
		_attack_fx.modulate = _fx_color(clampf(_fx_left / ATTACK_FX_TIME, 0.0, 1.0))
		if _fx_left <= 0.0:
			_attack_fx.visible = false


# 애니 상태: roll > attack > run > idle. 로컬은 자기 상태, 원격은 수신 신호(G_POS 변위·G_ROLL/G_ATK 창)로 판단.
func _update_anim() -> void:
	var next: StringName = &"idle"
	if _roll_time_left > 0.0 or _remote_roll_left > 0.0:
		next = &"roll"
	elif _attack_anim_left > 0.0 and _has_attack_anim():
		next = &"attack"
	elif (is_local and velocity.length_squared() > 1.0) or (not is_local and _remote_moving):
		next = &"run"
	if _sprite.animation != next:
		_sprite.play(next)


# 현재 미사용(어느 직업도 frames에 attack 없음) — 공격 연출은 무기 스윙(_update_weapon)이 담당.
# 몸통 attack 애니를 되살리면 애니 길이 ↔ ATTACK_ANIM_TIME 미러(rules §3)도 같이 되살릴 것.
func _has_attack_anim() -> bool:
	return _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation(&"attack")


# 무기 표시 — 조준 방향으로 내밀고, 공격 창 동안 호를 그리며 스윙 (전부 표시 전용, 판정은 별개).
func _update_weapon(delta: float) -> void:
	# 조준각은 무기 유무와 무관하게 갱신 — 무기 없는 직업도 "a"를 실제 값으로 송신해야
	# 나중에 활/지팡이 텍스처가 붙는 순간 원격 표시가 바로 맞는다 (리뷰 Minor)
	if is_local:
		_aim_angle = _aim_dir().angle()
	else:
		_aim_angle = lerp_angle(_aim_angle, _remote_aim, minf(1.0, WEAPON_AIM_LERP * delta))
	if _weapon.texture == null:
		return
	# 스윙 3박자: 예비(뒤로 젖힘) → 가속 스윕(+내지르기) → 복귀
	var swing_off := 0.0
	var lunge := 0.0
	if _attack_anim_left > 0.0:
		var t := 1.0 - _attack_anim_left / _swing_time  # 무기별 스윙 창으로 정규화
		if t < 0.28:
			swing_off = -_swing_arc * (t / 0.28)
		elif t < 0.75:
			var u := (t - 0.28) / 0.47
			u = u * u * (3.0 - 2.0 * u)  # smoothstep — 스윕에 가속감
			swing_off = lerpf(-_swing_arc, _swing_arc, u)
			lunge = _swing_lunge * sin(u * PI)
		else:
			swing_off = _swing_arc * (1.0 - (t - 0.75) / 0.25)
	var ang := _aim_angle + swing_off
	_weapon_pivot.rotation = ang
	_weapon.position = -_weapon_grip + Vector2(HOLD_DIST + lunge, 0.0)
	# 좌향 조준 시 뒤집기 — 안 하면 검이 거꾸로(날이 아래) 보인다. 기준은 조준각(스윙 중 깜빡임 방지)
	_weapon.flip_v = absf(wrapf(_aim_angle, -PI, PI)) > PI / 2.0
	# 위쪽 조준 = 몸 뒤(0), 아래 = 몸 앞(2) — 몸(Sprite z=1) 기준 상대 배치.
	# ⚠ 음수 z_index는 배경 타일 밑으로 꺼져 무기가 통째로 사라진다 (실기에서 확인) — 전부 0 이상 유지
	_weapon_pivot.z_index = 0 if sin(ang) < 0.0 else 2
	_weapon_pivot.visible = _alive and _roll_time_left <= 0.0 and _remote_roll_left <= 0.0


func _local_move(delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if seated:
		# 앉는 동안 무방비·정지 (GDD §5 모닥불) — 몸을 움직이려는 입력이 오면 스스로 일어난다
		if dir != Vector2.ZERO or Input.is_action_just_pressed("roll") or _attack_queued:
			seated = false
		else:
			velocity = Vector2.ZERO
			_sprite.flip_h = get_global_mouse_position().x < global_position.x
			return
	if _roll_time_left > 0.0:
		_roll_time_left -= delta
		velocity = _roll_dir * job.move_speed * ROLL_SPEED_MULT  # 구르기는 늪 슬로우 예외 — 늪 탈출 수단
	else:
		velocity = dir * job.move_speed * _swamp_mult()  # 걷기만 늪 배율 적용
		if _alive and Input.is_action_just_pressed("roll") and _roll_cd_left <= 0.0:
			_roll_dir = dir if dir != Vector2.ZERO else _aim_dir()
			_roll_time_left = CombatMath.ROLL_TIME_S
			_roll_cd_left = CombatMath.ROLL_COOLDOWN_S
			EventBus.player_roll.emit(global_position)  # 구르기 SFX (로컬)
			# 구르기 선언 — 호스트가 쿨다운 검증 후 i-frame 창 부여 (방향은 연출용)
			Net.send_game({NetSchema.KEY_KIND: NetSchema.G_ROLL, "dx": _roll_dir.x, "dy": _roll_dir.y})
	move_and_slide()
	_sprite.flip_h = get_global_mouse_position().x < global_position.x


# 공격은 폴링이 아니라 _unhandled_input — UI(Control)가 소비한 클릭은 여기 안 온다 (mouse_filter 존중)
func _unhandled_input(event: InputEvent) -> void:
	if is_local and event.is_action_pressed("attack"):
		_attack_queued = true


func _local_combat() -> void:
	var want := _attack_queued
	_attack_queued = false
	if not _alive:
		return
	if want and _attack_cd_left <= 0.0 and _roll_time_left <= 0.0:
		_attack_cd_left = job.attack_cooldown
		_attack_anim_left = _swing_time  # 무기별 스윙 창 (§3: < attack_cooldown)
		var dir := _aim_dir()
		_show_attack_fx(dir)
		EventBus.player_swing.emit(global_position, _swing_sfx)  # 스윙 SFX (로컬 — 무기별 휘두름음)
		Net.send_game({NetSchema.KEY_KIND: NetSchema.G_ATK, "dx": dir.x, "dy": dir.y})
		# 판정: 조준 방향 원형 질의 (Area 노드 대신 즉시 질의 — 프레임 지연 없음)
		# 기하는 CombatMath 단일 소스 — FX 위치(_show_attack_fx)와 같은 함수라 어긋나지 않는다
		var center := global_position + CombatMath.attack_center_offset(dir, job)
		var shape := CircleShape2D.new()
		shape.radius = CombatMath.attack_radius(job)
		var params := PhysicsShapeQueryParameters2D.new()
		params.shape = shape
		params.transform = Transform2D(0.0, center)
		params.collision_mask = ENEMY_BODY_MASK
		params.collide_with_bodies = true
		var hits := get_world_2d().direct_space_state.intersect_shape(params, 8)
		var connected := false
		for hit: Dictionary in hits:
			var body := hit.get("collider") as Node
			if body != null and body.is_in_group("enemy"):
				EventBus.attack_hit.emit(body, job)
				connected = true
		if connected:
			# 공격자 로컬 예측 타격 손맛 — 무기별 셰이크/타격음(호스트 확정 전 즉발, 표시 전용). 스윙당 1회.
			EventBus.weapon_impact.emit(center, _hit_sfx, _hit_shake)


func _aim_dir() -> Vector2:
	var d := get_global_mouse_position() - global_position
	return d.normalized() if d.length() > 0.001 else Vector2.RIGHT


# 궤적 예약 — 스윕 타이밍(_tick_timers의 딜레이 만료)에 맞춰 표시된다
func _show_attack_fx(dir: Vector2) -> void:
	_fx_dir = dir
	_fx_delay_left = ATTACK_FX_DELAY


# 네트워크 검증용 좌표 — 원격은 lerp된 표시 좌표가 아니라 (클램프된) 최신 수신 좌표를 쓴다.
# 표시 보간 지연 때문에 호스트의 사거리 검증이 정당한 적중을 거부하는 문제 방지 (실기 진단에서 확인).
func net_anchor() -> Vector2:
	return global_position if is_local else _remote_target


# 원격 플레이어의 공격 연출 (stage가 G_ATK 수신 시 호출) — 표시 전용, 판정 아님
func play_attack_fx(dir: Vector2) -> void:
	if not _alive:
		return  # 사망자(조작 클라)의 G_ATK로 시체 위치에 FX가 뜨는 그리핑 차단
	_show_attack_fx(dir)
	_sprite.flip_h = dir.x < 0.0
	if _attack_anim_left <= 0.0:
		# 애니 창만 재수신 무시(FX·플립은 매번 적용) — G_ATK 스팸으로 애니를 영구 attack으로
		# 잠그는 그리핑 차단 (정직한 공격은 쿨다운 0.4s > 창(≤0.25~0.34)이라 안 걸린다)
		EventBus.player_swing.emit(global_position, _swing_sfx)  # 스윙 SFX (원격 — 무기별, 스팸 게이트 안)
		_attack_anim_left = _swing_time  # 원격도 그 피어의 무기 스윙 창(set_weapon_visual로 세팅됨)


# 원격 플레이어의 구르기 연출 (peer_sync가 G_ROLL 수신 시 호출) — 표시 전용.
# i-frame 판정은 호스트 그랜트 창(CombatAuthority)이 별도로 한다 (§3) — 이 창은 애니만 돌린다.
func play_roll_fx(dir: Vector2) -> void:
	if _remote_roll_left > 0.0:
		return  # 창 중 재수신 무시 — G_ROLL 스팸으로 애니를 영구 roll로 잠그는 그리핑 차단 (정직한 구르기는 쿨다운 0.8s > 창 0.25s라 안 걸린다)
	_remote_roll_left = CombatMath.ROLL_TIME_S
	EventBus.player_roll.emit(global_position)  # 구르기 SFX (원격 — 스팸 게이트 뒤)
	if absf(dir.x) > 0.001:
		_remote_flip = dir.x < 0.0


func _send_pos(delta: float) -> void:
	_send_accum += delta
	if _send_accum >= 1.0 / POS_SEND_RATE:
		_send_accum = 0.0
		Net.send_game({
			NetSchema.KEY_KIND: NetSchema.G_POS,
			"s": scene_id,
			"x": global_position.x,
			"y": global_position.y,
			"f": _sprite.flip_h,
			"a": snappedf(_aim_angle, 0.01),  # 조준각 — 원격 무기 표시 전용 (판정 아님)
		})


# 원격 위치 반영 — 메시지 간 변위를 최대 이동 속도로 클램프한다.
# 호스트의 사거리 검증(§3)이 이 표시 좌표를 기준으로 하므로, 클램프 없이는 순간이동 스푸핑으로 검증이 무력화된다.
func apply_remote_pos(pos: Vector2, flip: bool, aim: float) -> void:
	# Inf/NaN 주입 가드 — JSON은 1e999 같은 오버플로를 Inf로 파싱한다. lerp_angle(유한, INF)=NaN이
	# 한 발로 _aim_angle을 영구 오염시키고, pos 쪽은 net_anchor()를 타 호스트 판정까지 닿는다 (리뷰 Important).
	if is_finite(aim):
		_remote_aim = wrapf(aim, -PI, PI)
	if not (is_finite(pos.x) and is_finite(pos.y)):
		return  # 무효 좌표는 통째로 무시 — 이전 앵커 유지
	var now := Time.get_ticks_msec()
	if _last_remote_msec >= 0:
		var dt := maxf(float(now - _last_remote_msec) / 1000.0, 1.0 / POS_SEND_RATE)
		var max_disp := job.move_speed * ROLL_SPEED_MULT * REMOTE_MAX_SPEED_MULT * dt
		var delta := pos - _remote_target
		if delta.length() > max_disp:
			pos = _remote_target + delta.normalized() * max_disp
	_last_remote_msec = now
	_remote_target = pos
	_remote_flip = flip
