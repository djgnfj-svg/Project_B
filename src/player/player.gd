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
# 위치 송신 빈도(Hz). 이 값이 곧 **호스트가 게스트 위치를 모르고 있는 평균 시간**(1/2주기)이라
# 지연 보상의 바닥이 된다 — 15Hz면 평균 33ms가 판정에서 그냥 손실이었다(2026-07-24 계측).
# 30Hz로 올려 17ms로 줄인다. 2인 기준 피어당 ~3.5KB/s라 릴레이 부담은 무시 가능.
const POS_SEND_RATE := 30.0
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
# 발사(shoot 무기 = 궁수 활) — 표시 연출값(§0 예외, 사용자 튜닝). 화살 속도/사거리는 CombatMath(결정론 공용).
const MUZZLE_OFFSET := 26.0          # 발사 원점 = 몸 중심 → 조준 방향 이만큼 앞. 화살 길이 18(반9)+몸 반경 16 → 26이면 화살 뒤끝(17)이 몸 밖 (겹침 방지). SHOT_ORIGIN_TOL이 이 값+지연을 수용
const RECOIL_DIST := 4.0             # 발사 시 활을 뒤로 당기는 거리(px) — 반동 손맛
const RECOIL_TIME := 0.14            # 반동 복귀 시간(s)
# 차지 발사(charge 무기 = 법사 지팡이) — 표시 연출값(§0 예외, 사용자 튜닝).
# 단계 수·위력/반경 배율은 CombatMath.CHARGE_*(§3 단일 소스), 단계 시간은 무기별(EquipDef.charge_step_time).
const CHARGE_MOVE_MULT := 0.5        # 기 모으는 동안 걷기 속도 배율 (모으는 대가 — 구르기로 취소 가능)
const ORB_LERP := 14.0               # 차지 오브 크기 보간 속도
const ORB_POP := 0.55                # 단계 상승 순간 확대 비율
const ORB_POP_TIME := 0.16           # 그 팝이 가라앉는 시간(s)
const REMOTE_CHARGE_SFX_MIN_MS := 250  # 원격 차지음 최소 간격 — G_POS "c"를 0↔2로 진동시켜 소리를 도배하는 그리핑 차단 (play_roll_fx 창-잠금 미러). 정직한 단계 상승은 350ms 간격이라 안 걸린다

@export var job: JobDef

var peer_id: int = 0
var is_local: bool = false
var scene_id: String = ""  # 소속 씬 (net_schema SCENE_*) — G_POS에 실어 다른 씬 피어의 유령 스폰 방지
var seated: bool = false  # 모닥불 앉기 (campfire 씬이 켠다) — 이동·구르기·공격 입력이 들어오면 스스로 풀린다. 공지(G_SIT)는 campfire가 상태 변화를 보고 송신
var equip_atk_bonus: int = 0  # 착용 장비 공격 보너스 (G_STATS 공지/수신) — 호스트가 calc_damage에 더한다
var equip_hp_bonus: int = 0   # 착용 장비 체력 보너스 — max_hp = job.max_hp + 이 값 (set_max_hp로 이월 HP 보존)
# 직업 레벨 5스탯 {crit, crit_dmg, haste, move, leech} (G_STATS "lv" 공지/수신, 성장축 GDD v1.8).
# 호스트가 치명 굴림·피흡 적립·공속 검증에 **자기가 clamp한 이 값**을 읽는다 (combat_authority).
# 장비 스탯(위 2개)과 **분리돼 있다** — 축 경계(GDD §6 🔒): 레벨은 공격력·체력을 건드리지 않는다.
var level_stats: Dictionary = {}

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
var _swing_time_base: float = ATTACK_ANIM_TIME  # 무기가 준 원본 스윙 창 — _swing_time은 여기에 haste 배율을 곱해 파생한다
var _swing_lunge: float = LUNGE_DIST
var _hold_dist: float = HOLD_DIST       # 몸 중심 → 무기 그립 거리 (무기별 = EquipDef.weapon_hold_dist, 대검 8·활 20)
var _arrow_range: float = 360.0         # shoot/charge 무기 투사체 사거리 (무기별 = EquipDef.arrow_range) — 발사 시 G_SHOOT로 전송
var _weapon_id: String = ""             # 착용 무기 id — G_SHOOT "w"(수신 측이 탄 겉모습/속도/폭발 반경을 allowlist 리졸브)
var _charge_step_time: float = 0.0      # charge 무기: 한 단계 모으는 시간(s). 0 = 차지 무기 아님
var _charge_step_time_base: float = 0.0  # 무기가 준 원본 단계 시간 — _charge_step_time은 haste 배율을 곱해 파생
var _charge_sfx: String = "charge_step"  # 단계 상승 효과음 id (무기별 = EquipDef.charge_sfx)

var _remote_target: Vector2 = Vector2.ZERO
var _remote_flip: bool = false
var _remote_vel: Vector2 = Vector2.ZERO  # G_POS "vx/vy" — 호스트 지연 보상 외삽의 입력 (§3). 수신 시 이동 상한으로 clamp
var _send_accum: float = 0.0
var _attack_cd_left: float = 0.0
var _roll_time_left: float = 0.0
var _roll_cd_left: float = 0.0
var _roll_dir: Vector2 = Vector2.RIGHT
var _fx_left: float = 0.0
var _fx_delay_left: float = 0.0
var _fx_dir: Vector2 = Vector2.RIGHT
var _attack_queued: bool = false
var _shot_seq: int = 0          # 로컬 발사 카운터 — 투사체 고유 id "my_id:seq" 생성 (shoot/charge 무기)
var _recoil_left: float = 0.0   # 발사 반동 잔여(s) — _update_weapon이 활을 뒤로 당김 (로컬·원격 공용 연출)
# 차지(charge 무기) — 로컬은 입력에서, 원격은 G_POS "c"에서. 레벨 자체는 표시용이고 실제 발사 레벨은 호스트가 재검증(§3).
var _charging: bool = false
var _charge_held: float = 0.0     # 누른 시간(s) — 레벨 = CombatMath.charge_level_for(held, step)
var _charge_level: int = 0
var _remote_charge: int = -1      # 원격 피어의 차지 레벨(-1 = 차지 중 아님) — G_POS "c" 디코드(표시 전용)
var _orb_pop_left: float = 0.0    # 단계 상승 팝 잔여(s)
var _remote_charge_sfx_msec: int = -1000000000  # 원격 차지음 스팸 게이트 앵커
var _last_remote_msec: int = -1
var _alive: bool = true
var bound: bool = false  # 코옵 속박(소울 케이지) — CoopAuthority가 켠다/끈다 (움직임 봉인)
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
@onready var _charge_orb: Sprite2D = $ChargeOrb


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
	# @onready 자식에 의존하는 무기 표시값(차지 오브 텍스처) 재적용 — set_weapon_visual이 _ready 전에
	# 불리는 경로가 생겨도 오브가 조용히 무텍스처로 남지 않게 (현 호출 경로는 전부 ready 이후, 심층 방어)
	_apply_weapon_feel(_weapon_override)


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


# 직업 레벨 5스탯 반영 — 로컬은 GameState.current_level_stats(), 원격은 G_STATS "lv" 수신(peer_sync가 부른다).
# 🔴 여기서 한 번 더 clamp한다(수신부 clamp와 이중): 이 인스턴스의 값이 곧 호스트 판정 입력이라
#   경로 어디서든 오염값이 새어들면 안 된다. 하드 상한(CombatMath.LEVEL_STAT_MAX)은 항상 적용된다.
func set_level_stats(stats: Dictionary) -> void:
	level_stats = CombatMath.clamp_level_stats(stats)
	_refresh_growth_derived()


# 레벨 스탯에서 파생되는 표시/이동 값을 다시 계산한다. 입력이 둘(레벨 스탯 변동·무기 교체)이라
# 반드시 한 함수로 모은다 — 한쪽에서만 갱신하면 무기를 바꾼 뒤 공속이 사라지는 식으로 조용히 갈라진다.
# 🔴 스윙 창·차지 스텝에 쿨다운과 **같은 배율**(haste_scale)을 곱하는 것이 §3 계약이다:
#   그래야 swing_time < attack_cooldown 부등식이 haste 어디서나 보존되고, 원격 창-잠금 가드가
#   빨라진 피어의 정당한 연속 공격 연출을 삼키지 않는다(원격 인스턴스도 그 피어의 haste로 파생된다).
func _refresh_growth_derived() -> void:
	var k := CombatMath.haste_scale(_haste())
	_swing_time = _swing_time_base * k
	_charge_step_time = CombatMath.effective_charge_step(_charge_step_time_base, _haste())


# 이 아바타의 공속 보너스 (로컬 = 내 레벨, 원격 = 그 피어가 공지한 값 — 둘 다 clamp된 값이다)
func _haste() -> float:
	return float(level_stats.get("haste", 0.0))


# 이 아바타의 실효 이동속도 — 로컬 이동과 **원격 위치 clamp가 같은 값을 써야 한다**(§3).
# 원격 clamp만 기본 이속으로 남기면 빨라진 정당 이동이 깎여 외삽이 과소평가되고,
# 2026-07-24에 고친 "피했는데 맞았다"가 빠른 피어에게 재발한다.
func _move_speed() -> float:
	if job == null:
		return 0.0
	return CombatMath.effective_move_speed(job.move_speed, float(level_stats.get("move", 0.0)))


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
	_weapon.position = -grip + Vector2(_hold_dist, 0.0)
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
	_swing_time_base = equip.swing_time if equip != null else ATTACK_ANIM_TIME
	_swing_lunge = equip.swing_lunge if equip != null else LUNGE_DIST
	_hold_dist = equip.weapon_hold_dist if equip != null else HOLD_DIST  # 큰 무기(활)는 멀리 잡아 몸과 안 겹침
	_arrow_range = equip.arrow_range if equip != null else CombatMath.DEFAULT_ARROW_RANGE  # shoot/charge 사거리
	_weapon_id = equip.id if equip != null else ""  # G_SHOOT "w" — 수신 측 탄 겉모습/속도/폭발 반경 리졸브 키
	# 차지(charge 무기) — 무기가 바뀌면 모으던 것도 취소한다(무장 해제·교체 중 유령 오브 방지)
	var is_charge := equip != null and equip.motion_type == "charge"
	_charge_step_time_base = equip.charge_step_time if is_charge else 0.0
	_charge_sfx = equip.charge_sfx if (is_charge and not equip.charge_sfx.is_empty()) else "charge_step"
	_refresh_growth_derived()  # 무기 교체도 파생 입력 — 새 base에 현재 haste를 다시 곱한다
	if is_node_ready():
		# 차지 오브 = 그 무기의 투사체 텍스처(표시 전용) — 모으는 탄과 날아가는 탄이 같은 그림.
		# ⚠ 틴트 없음(항등 흰색): 탄 텍스처는 이미 제 색을 갖고 있어 swing_color를 곱하면 탁해진다.
		#   swing_color는 **중립(흰색) 폭발 텍스처를 원소색으로 물들이는 용도**다 (불=주황, 이후 얼음=파랑).
		_charge_orb.texture = equip.projectile_texture if is_charge else null
		_charge_orb.modulate = Color(1, 1, 1, 1)
	if not is_charge:
		_cancel_charge()


# 궤적 페이드 색 — 무기 틴트 rgb 유지, 알파만 페이드로 구동
func _fx_color(alpha: float) -> Color:
	return Color(_swing_color.r, _swing_color.g, _swing_color.b, alpha * _swing_color.a)


func is_alive() -> bool:
	return _alive


# 무장 상태 — 착용 무기 텍스처가 있으면 무장(공격 가능). 미착용이면 공격·궤적 없음.
func _is_armed() -> bool:
	return _weapon.texture != null


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
	# 적은 치명타를 굴리지 않는다(GDD 범위) → 플레이어 피격은 항상 crit=false (php에 "cr"이 없는 이유와 짝)
	EventBus.combat_impact.emit("player", global_position, amount, false)
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
		_cancel_charge()         # 모으던 차지도 소멸 — 고스트가 기를 모으고 있지 않게
		_remote_charge = -1      # 원격 아바타의 차지 오브도 즉시 정리(사망 시 마지막 c가 남아 떠 있지 않게)
		_charge_orb.visible = false
		if is_local:
			_sprite.modulate.a = GHOST_ALPHA
		else:
			_sprite.visible = false


func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	if is_local:
		_local_move(delta)
		_local_combat(delta)
		_send_pos(delta)
	else:
		_remote_moving = global_position.distance_to(_remote_target) > 1.0
		global_position = global_position.lerp(_remote_target, minf(1.0, REMOTE_LERP_SPEED * delta))
		_sprite.flip_h = _remote_flip
	_update_anim()
	_update_weapon(delta)
	_update_charge_orb(delta)
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
	_recoil_left = maxf(0.0, _recoil_left - delta)
	_orb_pop_left = maxf(0.0, _orb_pop_left - delta)
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
	# 발사 반동(shoot 무기) — 활을 뒤로 당겼다 복귀. shoot는 _attack_anim_left를 안 켜므로 스윙과 상호 배타.
	if _recoil_left > 0.0:
		lunge = -RECOIL_DIST * (_recoil_left / RECOIL_TIME)
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
	_weapon.position = -_weapon_grip + Vector2(_hold_dist + lunge, 0.0)
	# 좌향 조준 시 뒤집기 — 안 하면 검이 거꾸로(날이 아래) 보인다. 기준은 조준각(스윙 중 깜빡임 방지)
	_weapon.flip_v = absf(wrapf(_aim_angle, -PI, PI)) > PI / 2.0
	# 위쪽 조준 = 몸 뒤(0), 아래 = 몸 앞(2) — 몸(Sprite z=1) 기준 상대 배치.
	# ⚠ 음수 z_index는 배경 타일 밑으로 꺼져 무기가 통째로 사라진다 (실기에서 확인) — 전부 0 이상 유지
	_weapon_pivot.z_index = 0 if sin(ang) < 0.0 else 2
	_weapon_pivot.visible = _alive and _roll_time_left <= 0.0 and _remote_roll_left <= 0.0


# 차지 오브 표시 — 지팡이 끝(= 발사 원점)에서 단계별로 커지는 마법구. 전부 표시 전용(판정 무관).
# 로컬은 내 차지 상태, 원격은 G_POS "c"(차지 중이면 레벨+1, 아니면 0으로 인코딩)에서 온다.
# 사망·구르기·무장 해제·비차지 무기면 숨긴다(유령 오브 방지).
func _update_charge_orb(delta: float) -> void:
	var lv := -1
	if is_local:
		if _charging:
			lv = _charge_level
	else:
		lv = _remote_charge
	if lv < 0 or not _alive or _charge_orb.texture == null \
			or _roll_time_left > 0.0 or _remote_roll_left > 0.0:
		_charge_orb.visible = false
		_charge_orb.scale = Vector2.ONE * 0.1  # 다음 차지는 다시 작게 시작 (자라나는 느낌)
		return
	_charge_orb.visible = true
	_charge_orb.position = Vector2(MUZZLE_OFFSET, 0.0).rotated(_aim_angle)
	var pop := 1.0 + ORB_POP * (_orb_pop_left / ORB_POP_TIME)  # 단계 상승 순간 부풀었다 가라앉음
	var target := CombatMath.CHARGE_ORB_SCALE[CombatMath.clamp_charge_level(lv)] * pop
	_charge_orb.scale = _charge_orb.scale.lerp(Vector2.ONE * target, minf(1.0, ORB_LERP * delta))
	_charge_orb.rotation += 5.0 * delta  # 자전 — 에너지가 도는 느낌


func _local_move(delta: float) -> void:
	if bound:
		# 코옵 속박(소울 케이지) — 파트너가 구출할 때까지 움직임/구르기 불가 (표시 전용 상태, 판정은 호스트)
		velocity = Vector2.ZERO
		return
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
		velocity = _roll_dir * _move_speed() * ROLL_SPEED_MULT  # 구르기는 늪 슬로우 예외(이속 보너스로 거리도 늘어난다, GDD §6)
	else:
		# 걷기만 늪 배율 적용. 기 모으는 중(charge 무기)이면 추가로 느려진다 — 모으는 대가(사용자 확정)
		var charge_mult := CHARGE_MOVE_MULT if _charging else 1.0
		velocity = dir * _move_speed() * _swamp_mult() * charge_mult
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


# 현재 착용 무기의 공격 모션 (EquipDef.motion_type) — 미착용/미지정이면 "swing" 폴백. _do_attack 분기의 단일 소스.
func _weapon_motion() -> String:
	return _weapon_override.motion_type if _weapon_override != null else "swing"


func _local_combat(delta: float) -> void:
	var want := _attack_queued
	_attack_queued = false
	if not _alive:
		_cancel_charge()  # 사망 = 모으던 것 소멸 (고스트가 계속 모으지 않게)
		return
	# 무장 해제(무기 미착용) = 공격 불가 — 판정·궤적·소리 전부 안 나간다. 무기가 곧 공격 수단.
	var motion := _weapon_motion()
	if motion == "charge" and _is_armed():
		_tick_charge(delta, want)  # 누르고 있는 동안 모으고, 떼면 발사 (쿨다운 게이트는 안에서)
		return
	if want and _attack_cd_left <= 0.0 and _roll_time_left <= 0.0 and _is_armed():
		_attack_cd_left = CombatMath.effective_cooldown(job, _haste())
		var dir := _aim_dir()
		# 모션 타입 분기 (§2 게이트): shoot = 원거리 발사(화살), charge = 위에서 처리, 그 외 = 근접 호 스윙.
		if motion == "shoot":
			_fire_projectile(dir, 0)
		else:
			_swing_attack(dir)


# 차지 발사(charge 무기) — 누른 순간 모으기 시작, 단계는 홀드 시간에서 리졸브(CombatMath 단일 소스),
# 떼면 그 단계로 발사. 구르기·사망·무기 교체는 취소. 모으는 동안 이동은 CHARGE_MOVE_MULT로 느려진다.
# ⚠ 시작은 _unhandled_input(UI가 소비한 클릭은 안 옴)이지만 유지·해제는 폴링이다 —
#   UI 위에서 버튼을 떼도 발사가 되도록(안 그러면 영구 차지 상태로 잠긴다).
func _tick_charge(delta: float, want: bool) -> void:
	if _roll_time_left > 0.0:
		_cancel_charge()  # 구르기로 취소 (사용자 확정: 모으는 중 위험하면 굴러서 뺀다)
		return
	if not _charging:
		if want and _attack_cd_left <= 0.0:
			_charging = true
			_charge_held = 0.0
			_charge_level = 0
		return
	if Input.is_action_pressed("attack"):
		_charge_held += delta
		var lv := CombatMath.charge_level_for(_charge_held, _charge_step_time)
		if lv > _charge_level:
			_charge_level = lv
			_orb_pop_left = ORB_POP_TIME
			EventBus.player_swing.emit(global_position, _charge_sfx)  # 단계 상승 "딸깍" (로컬)
		return
	var level := _charge_level
	_cancel_charge()
	_attack_cd_left = CombatMath.effective_cooldown(job, _haste())
	_fire_projectile(_aim_dir(), level)


func _cancel_charge() -> void:
	_charging = false
	_charge_held = 0.0
	_charge_level = 0


# 근접 호 스윙 — 로컬 원형 질의 판정(즉시, 프레임 지연 없음). 확정은 호스트(attack_hit → CombatAuthority).
func _swing_attack(dir: Vector2) -> void:
	_attack_anim_left = _swing_time  # 무기별 스윙 창 (§3: < attack_cooldown)
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


# 원거리 발사(shoot = 활 · charge = 지팡이) — 표시 투사체 스폰(로컬)·G_SHOOT 송신(원격 표시)·(호스트) 권한 투사체 등록.
# 명중·폭발 판정과 데미지는 호스트 CombatAuthority가 투사체를 추적해 확정한다 (근접의 로컬 원형 질의 대신). 여기선 판정 없음.
# charge = 차지 레벨(0~3, 비차지 무기는 0) — 호스트가 clamp + 차지 시간 재검증(§3 신뢰 경계).
func _fire_projectile(dir: Vector2, charge: int) -> void:
	var origin := global_position + dir * MUZZLE_OFFSET
	_shot_seq += 1
	var aid := str(Net.my_id) + ":" + str(_shot_seq)
	_recoil_left = RECOIL_TIME  # 활 반동/지팡이 반동 연출
	# player_shoot: ArrowField가 표시 투사체 스폰 + (호스트 자신이면) CombatAuthority가 권한 투사체 등록
	EventBus.player_shoot.emit(Net.my_id, origin, dir, aid, _arrow_range, _weapon_id, charge)
	EventBus.player_swing.emit(global_position, _swing_sfx)  # 발사 SFX (swing_sfx 재활용 = 시위·발사음)
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_SHOOT, "ox": origin.x, "oy": origin.y,
		"dx": dir.x, "dy": dir.y, "aid": aid, "r": _arrow_range,
		"w": _weapon_id, "c": charge})


func _aim_dir() -> Vector2:
	var d := get_global_mouse_position() - global_position
	return d.normalized() if d.length() > 0.001 else Vector2.RIGHT


# 궤적 예약 — 스윕 타이밍(_tick_timers의 딜레이 만료)에 맞춰 표시된다
func _show_attack_fx(dir: Vector2) -> void:
	_fx_dir = dir
	_fx_delay_left = ATTACK_FX_DELAY


# 네트워크 검증용 좌표 — 원격은 lerp된 표시 좌표가 아니라 (클램프된) 최신 수신 좌표를 쓴다.
# 표시 보간 지연 때문에 호스트의 사거리 검증이 정당한 적중을 거부하는 문제 방지 (실기 진단에서 확인).
# ⚠ 이건 여전히 **과거** 좌표다(편도 지연 + 송신 주기만큼). 피격 판정처럼 "지금 어디 있나"가
#   중요한 곳은 net_anchor_lead()와 짝지어 쓴다 — CombatMath.is_strike_hit_lagged (§3 지연 보상).
func net_anchor() -> Vector2:
	return global_position if is_local else _remote_target


# 지연 보상용 추정 좌표 — 마지막 관측 속도로 외삽한 "지금쯤 여기 있을 것" 위치.
# 로컬 피어는 지연이 없으므로 net_anchor()와 같다(항등 폴백 — 호스트 자신은 보상 대상이 아니다).
# one_way_ms = 그 피어와의 편도 지연 (Net.one_way_ms). 판정은 반드시 net_anchor()와 **둘 다** 통과해야
# 확정된다 — 외삽 오차가 방어자에게 유리한 쪽으로만 떨어지게 하는 규약 (CombatMath 주석 참조).
func net_anchor_lead(one_way_ms: float) -> Vector2:
	if is_local:
		return global_position
	var lead_s := CombatMath.lag_lead_s(_last_remote_msec, Time.get_ticks_msec(), one_way_ms)
	return CombatMath.extrapolate(_remote_target, _remote_vel, lead_s)


# 원격 플레이어의 공격 연출 (stage가 G_ATK 수신 시 호출) — 표시 전용, 판정 아님
func play_attack_fx(dir: Vector2) -> void:
	if not _alive or not _is_armed():
		return  # 사망자·무장 해제 피어의 G_ATK로 FX가 뜨는 것 차단 (그 피어 무기 = set_weapon_visual 반영)
	_show_attack_fx(dir)
	_sprite.flip_h = dir.x < 0.0
	if _attack_anim_left <= 0.0:
		# 애니 창만 재수신 무시(FX·플립은 매번 적용) — G_ATK 스팸으로 애니를 영구 attack으로
		# 잠그는 그리핑 차단 (정직한 공격은 쿨다운 0.4s > 창(≤0.25~0.34)이라 안 걸린다)
		EventBus.player_swing.emit(global_position, _swing_sfx)  # 스윙 SFX (원격 — 무기별, 스팸 게이트 안)
		_attack_anim_left = _swing_time  # 원격도 그 피어의 무기 스윙 창(set_weapon_visual로 세팅됨)


# 원격 궁수의 발사 연출 (peer_sync가 G_SHOOT 수신 시 호출) — 활 반동만, 표시 전용. 화살 자체는 ArrowField가 스폰.
func play_shoot_fx() -> void:
	if not _alive or not _is_armed():
		return  # 사망자·무장 해제 피어의 G_SHOOT로 연출이 뜨는 것 차단
	_recoil_left = RECOIL_TIME
	EventBus.player_swing.emit(global_position, _swing_sfx)  # 발사 SFX (원격 — swing_sfx 재활용)


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
			# 차지 상태 — 0 = 안 모으는 중, 그 외 = 레벨+1 (0단계 차지와 비차지를 구분하려는 인코딩).
			# 표시 전용이다: 실제 발사 레벨은 G_SHOOT "c"를 호스트가 차지 시간으로 재검증한다 (§3).
			"c": (_charge_level + 1) if _charging else 0,
			# 현재 속도 — 호스트가 "지금 내가 어디 있는지"를 추정하는 재료 (지연 보상, §3).
			# 부풀려 보내도 수신부 clamp + 외삽 거리 상한 + "방어자 우대" 규약 때문에 회피가
			# 관대해질 뿐 남을 때릴 수는 없다 (판정은 여전히 호스트가 자기 계산으로 확정).
			"vx": snappedf(velocity.x, 0.1),
			"vy": snappedf(velocity.y, 0.1),
		})


# 원격 위치 반영 — 메시지 간 변위를 최대 이동 속도로 클램프한다.
# 호스트의 사거리 검증(§3)이 이 표시 좌표를 기준으로 하므로, 클램프 없이는 순간이동 스푸핑으로 검증이 무력화된다.
func apply_remote_pos(pos: Vector2, flip: bool, aim: float, charge_code: int = 0,
		vel: Vector2 = Vector2.ZERO) -> void:
	# Inf/NaN 주입 가드 — JSON은 1e999 같은 오버플로를 Inf로 파싱한다. lerp_angle(유한, INF)=NaN이
	# 한 발로 _aim_angle을 영구 오염시키고, pos 쪽은 net_anchor()를 타 호스트 판정까지 닿는다 (리뷰 Important).
	if is_finite(aim):
		_remote_aim = wrapf(aim, -PI, PI)
	# 원격 차지 표시 — 0 = 안 모으는 중, 그 외 = 레벨+1. clamp로 범위 밖 값은 무해화(표시 전용, 판정 아님).
	var new_charge := clampi(charge_code, 0, CombatMath.MAX_CHARGE_LEVEL + 1) - 1
	if new_charge > _remote_charge and new_charge > 0:
		_orb_pop_left = ORB_POP_TIME
		# 상대가 단계를 올리는 "딸깍". ⚠ "직전보다 높으면"만으로는 못 막는다 — c를 0↔2로 진동시키면
		# 매 G_POS(15Hz)마다 상승으로 보인다 → 최소 간격 게이트로 도배 차단 (play_roll_fx 창-잠금과 같은 이유).
		var now_sfx := Time.get_ticks_msec()
		if now_sfx - _remote_charge_sfx_msec >= REMOTE_CHARGE_SFX_MIN_MS:
			_remote_charge_sfx_msec = now_sfx
			EventBus.player_swing.emit(global_position, _charge_sfx)
	_remote_charge = new_charge
	# 속도 반영 — 위치와 같은 신뢰 규율(유한성 + 최고 이동속도 clamp). 외삽 입력이므로 여기서 상한을 건다.
	# ⚠ 무효값이면 0으로 떨어뜨린다(이전 속도 유지 금지) — 정지한 피어를 계속 미끄러뜨리면
	#   추정 좌표가 실제와 벌어져 "방어자 우대"가 과하게 관대해진다.
	if is_finite(vel.x) and is_finite(vel.y):
		var max_speed := _move_speed() * ROLL_SPEED_MULT  # 🔴 이속 보너스 반영 — 안 하면 지연 보상이 부분 퇴행한다(§3)
		_remote_vel = vel.limit_length(max_speed)
	else:
		_remote_vel = Vector2.ZERO
	if not (is_finite(pos.x) and is_finite(pos.y)):
		return  # 무효 좌표는 통째로 무시 — 이전 앵커 유지
	var now := Time.get_ticks_msec()
	if _last_remote_msec >= 0:
		var dt := maxf(float(now - _last_remote_msec) / 1000.0, 1.0 / POS_SEND_RATE)
		var max_disp := _move_speed() * ROLL_SPEED_MULT * REMOTE_MAX_SPEED_MULT * dt  # 속도 상한과 같은 유도식(갈라지면 한쪽만 튜닝된다)
		var delta := pos - _remote_target
		if delta.length() > max_disp:
			pos = _remote_target + delta.normalized() * max_disp
	_last_remote_msec = now
	_remote_target = pos
	_remote_flip = flip
