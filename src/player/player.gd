extends CharacterBody2D
# 플레이어 배우 — 로컬(입력 구동) / 원격(수신 보간) 겸용.
# 자기 위치·공격 입력은 자기가 소유하고, 데미지 확정은 호스트가 한다 (rules §1·§3).
# 조작(GDD §5 v1.5): WASD 이동, 마우스 조준(2방향 플립), 좌클릭 공격, Shift 구르기.

const NetSchema := preload("res://src/core/net_schema.gd")
const HealthComponent := preload("res://src/combat/health_component.gd")
const HitStop := preload("res://src/feel/hit_stop.gd")
const HitFlash := preload("res://src/feel/hit_flash.gd")
const Flinch := preload("res://src/feel/flinch.gd")
const AfterImage := preload("res://src/feel/afterimage.gd")
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
const GHOST_ALPHA := 0.4
const ATTACK_FX_DELAY := 0.07        # 예비동작이 끝나고 스윕이 시작될 때 궤적을 표시
const ATTACK_FX_TIME := 0.18         # 궤적 잔상 페이드 시간
const SWOOSH_TEX_RADIUS := 46.0      # swoosh_arc.png의 호 바깥 반지름(px) — FX 스케일 기준 (텍스처와 미러)
# 검기 파형 (검성 메인 특성, GDD v1.9) — **표시 전용**. 평타 스윙과 같은 프레임에 태어나 앞으로 뻗는다.
# 🔴 파형은 판정을 만들지 않는다 — 판정은 확장된 사거리를 쓴 원형 질의 하나뿐이고, 파형은 그 사거리가
#   왜 늘었는지를 눈에 보여주는 것이다(GDD §6: 파형 자체 데미지 없음). 그래서 도달 거리를 연출값으로
#   따로 두지 않고 **항상 기하(attack_center_offset+attack_radius)에서 파생**한다 — 여기 값을 키워
#   더 멀리 보이게 만들면 "보이는 곳 ≠ 맞는 곳"이 된다.
const WAVE_FX_TIME := 0.22           # 파형이 뻗어 사라지기까지 (연출값 — 사용자 실기 튜닝, §0 예외)
const WAVE_TEX_HALF_H := 12.0        # sword_wave.png 세로 반높이(px) — 판정 반경 정합 스케일 기준 (텍스처와 미러)
const WAVE_START_RATIO := 0.55       # 파형이 태어나는 지점 = 기본 사거리 도달점 × 이 비율 (스윙 궤적 안에서 출발)
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

# --- 4방향(4분면) 표시 (사용자 확정 2026-07-26) ---
# 애니 이름 규칙 = "<base>_e" / "_s" / "_n" — **서쪽은 동쪽 프레임을 flip_h**로 쓴다(픽셀아트 표준:
# 좌우가 대칭이라 장수를 반으로 줄인다). SpriteFrames에 방향 애니가 **없으면 기존 2방향으로 폴백**하므로,
# 4방향 시트가 아직 없는 지금도 동작이 완전히 그대로다 — 아트가 나오면 PNG/.tres 교체만으로 켜진다.
# 🔴 방향의 단일 소스는 **조준각(_aim_angle)** 이다: 로컬은 마우스, 원격은 G_POS "a"라 **네트워크 필드 0개**로
#   원격도 같은 방향을 얻는다. flip_h를 여기 말고 다른 곳에서 대입하면 프레임마다 서로 덮어써 깜빡인다.
const DIR_SUFFIX: Array[String] = ["e", "s", "w", "n"]  # _facing_index 순서와 미러
# --- 대쉬 손맛 (구르기 = 잔상 대쉬, 사용자 확정 2026-07-26 "연출만") ---
# 🔴 i-frame·쿨다운·거리는 **그대로다** — CombatMath.ROLL_TIME_S/effective_roll_*(§3 단일 소스,
#   호스트 검증과 같은 값)를 건드리지 않는다. 바뀐 것은 화면에 보이는 것뿐(잔상·먼지·카메라 킥).
const DASH_KICK := 2.2          # 대쉬 시작 시 진행 방향 카메라 반동
const DASH_END_KICK := 1.1      # 대쉬가 끝나며 멈출 때의 되튐(반대 방향)
# --- 무기 스탠스 (사용자 지적: "검도 idle이 있는건지 캐릭터에 붙어있음") ---
# 평상시 무기가 조준각에 못 박혀 있으면 몸에 용접된 것처럼 보인다 → 살짝 내려 들고 호흡하듯 흔든다.
# 전부 표시 전용이다 — 발사 원점(_aim_dir)·판정 기하는 sway를 **안 본다**(§3 "맞는 곳 = 보이는 곳"의
# 기준은 조준각이지 흔들린 각이 아니다). 스윙·차지·반동 중엔 sway를 끈다(모션끼리 섞이면 지저분해진다).
const STANCE_DROP := 0.20       # 평상시 무기를 내려 드는 각(rad)
const IDLE_SWAY_AMP := 0.055    # 정지 중 호흡 흔들림 진폭(rad)
const IDLE_SWAY_SPEED := 2.6
const RUN_SWAY_AMP := 0.15      # 이동 중 흔들림 — 걸음에 맞춰 크게
const RUN_SWAY_SPEED := 7.5
const STANCE_LERP := 9.0        # 스탠스↔조준 전환 부드러움
# --- 평타 콤보 (연출 전용, 사용자 확정 2026-07-26) ---
# 🔴 **데미지·쿨다운·스윙 창은 콤보와 무관하다** — 3타째가 더 아프면 GDD §6 화력 예산 변경이라
#   planner 승인이 필요하다(그래서 안 했다). 바뀌는 건 휘두르는 궤적의 방향/크기뿐이다.
# ⚠ _swing_time을 콤보로 늘리지 마라: 스윙 창 < attack_cooldown 미러 계약(§3)이 깨지면 원격
#   창-잠금 가드가 정당한 연속 공격의 연출을 삼킨다.
const COMBO_MAX := 3            # 콤보 길이(0→1→2→0)
const COMBO_WINDOW := 0.55      # 스윙 창이 끝난 뒤 이 시간 안에 다시 치면 다음 타로 이어진다(s)
const COMBO_FINISH_ARC := 1.25  # 마무리 타의 호 배율 — 크게 휘둘러 "끝났다"가 읽히게
const COMBO_FINISH_LUNGE := 1.7 # 마무리 타의 내지르기 배율
const COMBO_FINISH_KICK := 2.6  # 마무리 타의 카메라 반동
const HIT_KICK := 1.7           # 근접 적중 시 때린 방향 반동 — 셰이크(무작위)와 달리 "밀어냈다"가 읽힌다
const SHOOT_KICK := 1.5         # 발사 시 **반대** 방향 반동 (총·활의 반동)

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
# 하위 직업 특성 {reach, roll_cd, roll_dist, campfire_heal, kill_move, drop_find} (GDD v2.0 §5,
# G_STATS "ms"/"ss" 공지 → 각 클라가 자기 data/subjobs에서 리졸브한 값).
# 🔴 5스탯과 분리: 레벨로 자라지 않고 **낀 자리에 따라** 켜지므로 level_stats에 섞으면 서브 가중·레벨 곱이 붙는다.
var traits: Dictionary = {}
var _kill_move_left: float = 0.0  # 「광란」(kill_move) 남은 지속 — 로컬 연출/이동 전용(네트워크 0)

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
var _pos_seq: int = 0                   # 내 G_POS 송신 시퀀스(단조 증가) — 수신부 순서 뒤바뀜 폐기의 근거
var _last_pos_seq: int = 0              # 이 원격 피어에게서 받은 마지막 시퀀스 — 이보다 낮으면 옛 패킷
var _send_accum: float = 0.0
var _attack_cd_left: float = 0.0
var _roll_time_left: float = 0.0
var _roll_cd_left: float = 0.0
var _roll_dir: Vector2 = Vector2.RIGHT
var _fx_left: float = 0.0
var _fx_delay_left: float = 0.0
# 검기 파형 진행 상태 (표시 전용) — 방향·출발/도착 거리를 스윙 시점에 굳혀 두고 선형 보간한다.
var _wave_left: float = 0.0
var _wave_dir: Vector2 = Vector2.RIGHT
var _wave_from: float = 0.0
var _wave_to: float = 0.0
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
var _afterimage_left: float = 0.0   # 다음 잔상까지 남은 시간(s) — 대쉬 중에만 돈다
var _was_dashing: bool = false      # 직전 프레임 대쉬 여부 — 종료 순간(되튐 킥)을 잡는 엣지 감지
var _stance_sway: float = 0.0       # 현재 적용 중인 무기 스탠스 각(rad) — 목표로 부드럽게 따라간다
var _sway_phase: float = 0.0        # 흔들림 위상 — delta로 누적(Time 전역 대신, 일시정지·씬 전환에 안전)
var _combo_index: int = 0           # 근접 스윙 콤보 타수(0..COMBO_MAX-1) — 표시 전용
var _combo_left: float = 0.0        # 근접 콤보가 이어지는 남은 시간(s)
# 원거리(shoot/charge) 평타 콤보 — 궁수 "평·평·쭉". 🔴 **근접 콤보와 상태를 공유하지 않는다**:
#   근접은 궤적만 정하는 표시값이지만 이쪽은 사거리·데미지를 바꿔 신뢰 경계가 걸려 있고, 규칙도
#   호스트와 미러여야 한다(CombatMath.advance_combo). 섞으면 근접 손맛 튜닝이 원거리 판정을 움직인다.
# ⚠ 창 판정은 카운트다운 타이머가 아니라 **타임스탬프 간격**이다 — 호스트가 수신 시각으로 같은
#   산술을 하므로(양쪽이 같은 함수를 지나려면) 클라도 같은 형태로 재야 한다.
var _shot_combo_index: int = 0
var _last_shot_msec: int = -1000000000
var _swing_from: float = 0.0        # 이번 스윙의 시작 각 오프셋(rad) — 콤보 타수에 따라 방향이 뒤집힌다
var _swing_to: float = 0.0          # 이번 스윙의 끝 각 오프셋(rad)
var _swing_lunge_mult: float = 1.0  # 이번 스윙의 내지르기 배율(마무리 타만 크게)
var _swamp_factors: Array[float] = []  # 현재 겹친 늪들의 이동 배율 (SwampZone enter/exit로 추가·제거). 걷기 속도에 min 적용, 구르기 예외

var _prev_hp: int = 0  # 피격 손맛(combat_impact 감소량) 계산용 — hp_changed 표시 경로 추적

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _attack_fx: Sprite2D = $AttackFx
@onready var _wave_fx: Sprite2D = $WaveFx  # 검기 파형(메인 특성) — 표시 전용
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
	# 「광란」(kill_move) 트리거 — 적 사망 표시 훅에 매단다(손맛 계층 규약: 이미 모든 클라에서
	# 1회씩 발화하는 훅을 재사용 → **네트워크 메시지 0개**). 원격 인스턴스는 자기 좌표를 수신으로
	# 받으므로 버프를 굴릴 필요가 없다 — 대신 clamp는 _max_move_speed가 항상 관대하게 잡는다.
	EventBus.entity_died.connect(_on_entity_died)


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


# 하위 직업 특성 반영 (GDD v2.0 §5).
# 로컬 = GameState.active_traits() · 원격 = 그 피어가 공지한 하위 직업 id들을 리졸브한 값
# (둘 다 peer_sync가 넣는다 — 로컬은 _peer_stats에 항목이 없으므로 GameState에서 직접).
# 🔴 **호스트는 판정에 쓸 특성을 항상 "공격자 아바타"에서 읽는다**(combat_authority) — 이 인스턴스가
#   그 단일 소스다. peer_sync._peer_stats에는 로컬 항목이 영원히 없어서(Net 루프백 없음) 그쪽을
#   읽으면 "내 것만 안 먹힌다"가 된다 — 2026-07-25 공속 Critical과 같은 함정.
# 🔴 reach 하나가 **판정 기하·스워시 크기·파형 연출을 동시에** 움직인다(§3 사거리 계약).
#   한쪽만 받으면 "맞는 곳 ≠ 보이는 곳"이 되고, 그건 에러 없이 손맛으로만 드러난다.
# 여기서 한 번 더 clamp한다(수신부 clamp와 이중) — set_level_stats와 같은 규약.
func set_traits(t: Dictionary) -> void:
	traits = CombatMath.clamp_traits(t)


# 이 아바타의 특성값 — 모르는 키/미설정은 0(항등).
func trait_value(key: String) -> float:
	return float(traits.get(key, 0.0))


# 「광란」(kill_move) — 적이 쓰러지면 잠깐 빨라진다. **로컬 아바타만** 굴린다(원격은 좌표를 수신으로 받는다).
# 🔴 협동이라 **누가 막타를 냈는지 묻지 않는다** — EXP 전원 동일 지급과 같은 철학이고, 막타는 호스트만
#   아는 정보라 게스트에게 알리려면 새 메시지가 필요하다(그만한 값이 안 나온다).
func _on_entity_died(kind: String, _world_pos: Vector2) -> void:
	if not is_local or kind != "enemy":
		return
	if trait_value("kill_move") > 0.0:
		_kill_move_left = CombatMath.KILL_MOVE_TIME_S


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
	# 「광란」(kill_move) — 적을 처치한 뒤 잠깐 빨라진다. 5스탯 move와 **같은 축이라 더해서** 넘긴다:
	# 그러면 원격 변위 clamp·외삽 상한도 자동으로 같은 값을 보고(_roll_speed 경유), 빨라진 정당
	# 이동이 깎이지 않는다(§3 이동속도 계약). 상한은 effective_move_speed 안의 clamp_move가 건다.
	var m := float(level_stats.get("move", 0.0))
	if _kill_move_left > 0.0:
		m += trait_value("kill_move")
	return CombatMath.effective_move_speed(job.move_speed, m)


# 🔴 **clamp 전용 상한** — kill_move를 타이머와 무관하게 **항상** 포함한다.
#   버프 창은 각 클라의 로컬 타이머라 호스트의 원격 인스턴스와 몇십 ms 어긋날 수 있는데,
#   clamp가 그 순간 좁으면 빨라진 정당 이동이 깎여 외삽이 과소평가되고 "피했는데 맞았다"가
#   부분 재발한다(§3). clamp는 상한이므로 관대한 쪽으로 틀리는 것이 안전한 방향이다.
func _max_move_speed() -> float:
	if job == null:
		return 0.0
	return CombatMath.effective_move_speed(
		job.move_speed, float(level_stats.get("move", 0.0)) + trait_value("kill_move"))


# 이 아바타의 구르기 속도 — 로컬 이동용(현재 버프 상태 반영).
func _roll_speed() -> float:
	return CombatMath.effective_roll_speed(_move_speed(), trait_value("roll_dist"))


# 원격 속도/변위 clamp용 구르기 상한 — 위와 같은 유도식에 관대한 이동 상한을 넣는다(§3).
func _max_roll_speed() -> float:
	return CombatMath.effective_roll_speed(_max_move_speed(), trait_value("roll_dist"))


# 구르기 쿨 남은 비율 0.0~1.0 (1 = 방금 굴러 꽉 참, 0 = 지금 구를 수 있음). **HUD 표시 전용 읽기 접근자**
# — 상태를 바꾸지 않는다. (특성 축 절반이 구르기에 걸리는데 남은 쿨이 안 보이면 −%가 체감되지 않는다, GDD v2.0)
# 🔴 분모는 상수 ROLL_COOLDOWN_S가 아니라 **현재 특성이 반영된 유효 쿨**이다 — 상수로 나누면
#   roll_cd 특성이 켜졌을 때 바가 끝까지 안 차 "감소가 안 걸린 것처럼" 보인다(§3 단일 소스와 같은 이유).
func roll_cooldown_ratio() -> float:
	if _roll_cd_left <= 0.0:
		return 0.0
	var total := CombatMath.effective_roll_cooldown(trait_value("roll_cd"))
	if total <= 0.0:
		return 0.0
	return clampf(_roll_cd_left / total, 0.0, 1.0)


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
	# 무기가 바뀌면 콤보도 처음부터 — 리듬은 무기가 정하므로 옛 무기의 타수를 이어받으면 새 무기의
	# 배율 배열에 엉뚱한 칸이 걸린다(호스트는 자기 간격으로 세니 표시만 어긋난다).
	_shot_combo_index = 0
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
		_wave_fx.visible = false
		_wave_left = 0.0      # 날아가던 검기 파형도 정리 (스워시와 같은 이유)
		_roll_time_left = 0.0
		_remote_roll_left = 0.0
		_was_dashing = false     # 사망으로 끊긴 대쉬가 되튐 킥을 남기지 않게(엣지 감지 리셋)
		_combo_left = 0.0        # 부활 후 첫 스윙이 죽기 전 콤보를 이어받지 않게
		_combo_index = 0
		_shot_combo_index = 0    # 원거리 콤보도 같이 — 부활 첫 발이 죽기 전 마무리 타를 이어받지 않게
		# ⚠ _last_shot_msec은 안 건드린다: 호스트도 자기 기록을 사망으로 지우지 않으므로(발사율 게이트가
		#   그대로 살아 있다) 여기서 지우면 부활 직후 클라만 "간격 충분"으로 보고 타수가 어긋난다.
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
		# ⚠ flip_h는 여기서 안 건드린다 — 방향/뒤집기의 단일 소스는 _play_dir_anim이다(폴백 경로가
		#   원격일 때 _remote_flip을 읽는다). 두 곳에서 대입하면 프레임마다 서로 덮어쓴다.
	# 🔴 조준각 갱신이 **맨 앞**이다 — 방향 애니(_update_anim)와 무기 표시(_update_weapon)가 둘 다
	#   _aim_angle에서 파생하므로, 뒤에서 갱신하면 몸 방향만 한 프레임 늦게 돌아 무기와 어긋난다.
	_update_aim(delta)
	_update_anim()
	_update_weapon(delta)
	_update_charge_orb(delta)
	_update_dash_fx(delta)
	_update_dust()


# 이동/구르기 중 발밑 먼지 (로컬=속도, 원격=수신 이동). 사망 시 정지.
func _update_dust() -> void:
	var moving := velocity.length() > 8.0 if is_local else _remote_moving
	_dust.emitting = _alive and moving


# 대쉬(구르기) 잔상 — 지나온 자리에 현재 프레임을 떼어 놓는다. 로컬·원격 모두 자기 화면에서 재생하므로
# **네트워크 메시지 0개**다(rules §2 손맛 계층 규약: 이미 각 클라에 있는 상태에서 파생한다).
# 대쉬 창은 로컬 _roll_time_left / 원격 _remote_roll_left — i-frame 판정과는 무관한 표시 창이다.
func _update_dash_fx(delta: float) -> void:
	var dashing := _alive and (_roll_time_left > 0.0 or _remote_roll_left > 0.0)
	if dashing:
		_afterimage_left -= delta
		if _afterimage_left <= 0.0:
			_afterimage_left = AfterImage.SPAWN_INTERVAL
			AfterImage.spawn(_sprite, self)
	elif _was_dashing:
		# 멈추는 순간의 되튐 — 진행 방향 반대로 짧게 밀어 "급정거"가 읽히게 (로컬 카메라만)
		if is_local:
			EventBus.camera_kick.emit(-_roll_dir, DASH_END_KICK)
		_afterimage_left = 0.0
	_was_dashing = dashing


# 대쉬 시작 연출 — 로컬(입력)·원격(G_ROLL 수신) 공용. 잔상 첫 장 + 먼지 버스트 + 진행 방향 카메라 반동.
func _dash_burst(dir: Vector2) -> void:
	AfterImage.spawn(_sprite, self)  # 출발 프레임을 즉시 한 장 — 첫 간격을 기다리면 시작이 밋밋하다
	_afterimage_left = AfterImage.SPAWN_INTERVAL
	_was_dashing = true
	if _dust != null:
		_dust.restart()  # 튀어나가는 순간 발밑에서 확 터지게(이후는 _update_dust가 이어 뿜는다)
		_dust.emitting = true
	if is_local:
		EventBus.camera_kick.emit(dir, DASH_KICK)


func _tick_timers(delta: float) -> void:
	_attack_cd_left = maxf(0.0, _attack_cd_left - delta)
	_roll_cd_left = maxf(0.0, _roll_cd_left - delta)
	_remote_roll_left = maxf(0.0, _remote_roll_left - delta)
	_attack_anim_left = maxf(0.0, _attack_anim_left - delta)
	_recoil_left = maxf(0.0, _recoil_left - delta)
	_kill_move_left = maxf(0.0, _kill_move_left - delta)
	_orb_pop_left = maxf(0.0, _orb_pop_left - delta)
	_combo_left = maxf(0.0, _combo_left - delta)
	if _fx_delay_left > 0.0:
		_fx_delay_left -= delta
		if _fx_delay_left <= 0.0:
			# 궤적 표시 — 플레이어 중심 회전, 크기는 판정 기하(§3 단일 소스)에서 파생해 "맞는 곳=보이는 곳" 유지
			# 🔴 reach 특성을 여기에도 넘긴다 — 판정만 넓히면 늘어난 사거리가 화면에 안 보인다.
			var rb := trait_value("reach")
			var reach := CombatMath.attack_center_offset(_fx_dir, job, rb).length() \
				+ CombatMath.attack_radius(job, rb)
			_attack_fx.rotation = _fx_dir.angle()
			_attack_fx.position = Vector2.ZERO
			_attack_fx.scale = Vector2.ONE * (reach / _swoosh_radius)  # 무기별 궤적 반지름 정합(§3)
			_attack_fx.modulate = _fx_color(1.0)
			_attack_fx.visible = true
			_fx_left = ATTACK_FX_TIME
			if rb > 0.0:
				_start_wave(reach)  # 검기 파형 — 늘어난 사거리 끝(reach)까지 나아간다
	_tick_wave(delta)  # 파형 진행은 딜레이 블록 **밖** — 안에 두면 예약 창에서만 움직이다 얼어붙는다
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
	_play_dir_anim(next)


# 조준각 → 4분면 인덱스 (0=동 1=남 2=서 3=북). Godot는 y+가 아래라 남쪽이 +PI/2다.
# 경계에서 깜빡이지 않게 각을 45° 돌린 뒤 90°로 나눈다(각 사분면의 중앙이 정면이 된다).
func _facing_index(angle: float) -> int:
	if not is_finite(angle):
		return 0
	return int(wrapf(angle + PI / 4.0, 0.0, TAU) / (PI / 2.0)) % 4


# 방향 애니 재생 + flip_h 대입의 **단일 소스**. 4방향 시트가 있으면 그걸, 없으면 기존 2방향으로 폴백한다.
# 🔴 flip_h를 여기 밖에서 대입하지 마라 — 매 프레임 이 함수가 다시 쓰기 때문에 다른 대입은
#   한 프레임만 반영됐다 사라져 "가끔 방향이 튄다"로만 보인다(원인이 화면에 안 드러난다).
func _play_dir_anim(base: StringName) -> void:
	var frames := _sprite.sprite_frames
	if frames == null:
		return
	var idx := _facing_index(_aim_angle)
	# 서(2)는 동(0) 프레임을 뒤집어 쓴다 — 시트 장수를 반으로.
	var dir_flip := idx == 2
	var want := StringName(String(base) + "_" + DIR_SUFFIX[0 if dir_flip else idx])
	if frames.has_animation(want):
		_sprite.flip_h = dir_flip
		if _sprite.animation != want:
			_sprite.play(want)
		return
	# --- 폴백: 4방향 시트가 아직 없다 → 도입 전과 **완전히 같은 동작** ---
	# 기존 규칙은 "왼쪽 반평면이면 뒤집기"였다(4분면 서쪽보다 넓다) — 좁히면 좌상/좌하 조준에서
	# 캐릭터가 오른쪽을 본 채 왼쪽을 때리는 것처럼 보인다.
	_sprite.flip_h = (absf(wrapf(_aim_angle, -PI, PI)) > PI / 2.0) if is_local else _remote_flip
	if frames.has_animation(base) and _sprite.animation != base:
		_sprite.play(base)


# 몸통 공격 애니 보유 여부 — 현재 어느 직업도 없어(공격 연출은 무기 스윙 = _update_weapon 담당) 항상 false다.
# 4방향 시트가 attack_e/_n/_s를 들고 오면 자동으로 켜진다.
# 몸통 attack 애니를 되살리면 애니 길이 ↔ _swing_time 미러(rules §3)도 같이 되살릴 것.
func _has_attack_anim() -> bool:
	var f := _sprite.sprite_frames
	return f != null and (f.has_animation(&"attack") or f.has_animation(&"attack_e"))


# 조준각 갱신 — 몸 방향(4분면 애니·flip)과 무기 표시가 **둘 다** 여기서 파생하는 단일 소스.
# 무기 유무와 무관하게 돈다: 무장 해제 상태에서도 "a"를 실제 값으로 송신해야 무기를 드는 순간
# 원격 표시가 바로 맞고(리뷰 Minor), 몸이 향하는 쪽도 무장 여부와 무관해야 한다.
func _update_aim(delta: float) -> void:
	if is_local:
		_aim_angle = _aim_dir().angle()
	else:
		_aim_angle = lerp_angle(_aim_angle, _remote_aim, minf(1.0, WEAPON_AIM_LERP * delta))


# 무기 표시 — 조준 방향으로 내밀고, 공격 창 동안 호를 그리며 스윙 (전부 표시 전용, 판정은 별개).
func _update_weapon(delta: float) -> void:
	if _weapon.texture == null:
		return
	# 스윙 3박자: 예비(뒤로 젖힘) → 가속 스윕(+내지르기) → 복귀
	var swing_off := 0.0
	var lunge := 0.0
	var swinging := _attack_anim_left > 0.0
	# 발사 반동(shoot 무기) — 활을 뒤로 당겼다 복귀. shoot는 _attack_anim_left를 안 켜므로 스윙과 상호 배타.
	if _recoil_left > 0.0:
		lunge = -RECOIL_DIST * (_recoil_left / RECOIL_TIME)
	if swinging:
		var t := 1.0 - _attack_anim_left / _swing_time  # 무기별 스윙 창으로 정규화
		# 시작/끝 각은 콤보 타수가 정한다(_begin_swing) — 홀수 타는 반대로 휘둘러 좌우가 번갈아 보인다.
		if t < 0.28:
			swing_off = _swing_from * (t / 0.28)
		elif t < 0.75:
			var u := (t - 0.28) / 0.47
			u = u * u * (3.0 - 2.0 * u)  # smoothstep — 스윕에 가속감
			swing_off = lerpf(_swing_from, _swing_to, u)
			lunge = _swing_lunge * _swing_lunge_mult * sin(u * PI)
		else:
			swing_off = _swing_to * (1.0 - (t - 0.75) / 0.25)
	# 좌향 조준 시 뒤집기 — 안 하면 검이 거꾸로(날이 아래) 보인다. 기준은 조준각(스윙 중 깜빡임 방지)
	_weapon.flip_v = absf(wrapf(_aim_angle, -PI, PI)) > PI / 2.0
	# 평상시 스탠스 — 무기를 살짝 내려 들고 호흡/걸음에 맞춰 흔든다. 표시 전용이라 발사 원점·판정
	# 기하는 이 각을 보지 않는다(그쪽은 _aim_dir). 뒤집힌 쪽에선 부호를 반대로 줘야 양쪽 다 "내려 든" 모습.
	_tick_stance(delta, swinging)
	var ang := _aim_angle + swing_off + _stance_sway * (-1.0 if _weapon.flip_v else 1.0)
	_weapon_pivot.rotation = ang
	_weapon.position = -_weapon_grip + Vector2(_hold_dist + lunge, 0.0)
	# 위쪽 조준 = 몸 뒤(0), 아래 = 몸 앞(2) — 몸(Sprite z=1) 기준 상대 배치.
	# ⚠ 음수 z_index는 배경 타일 밑으로 꺼져 무기가 통째로 사라진다 (실기에서 확인) — 전부 0 이상 유지
	_weapon_pivot.z_index = 0 if sin(ang) < 0.0 else 2
	_weapon_pivot.visible = _alive and _roll_time_left <= 0.0 and _remote_roll_left <= 0.0


# 무기 스탠스 각 갱신 — 평상시엔 내려 들고 흔들리게, 모션 중(스윙·발사 반동·차지)엔 0으로 되돌린다.
# 목표로 lerp하므로 모션이 시작/끝날 때 각이 튀지 않는다. 로컬·원격 모두 자기 상태에서 파생(네트워크 0).
func _tick_stance(delta: float, swinging: bool) -> void:
	var charging := _charging if is_local else _remote_charge >= 0
	var target := 0.0
	if not swinging and _recoil_left <= 0.0 and not charging:
		var moving := (velocity.length_squared() > 1.0) if is_local else _remote_moving
		var amp := RUN_SWAY_AMP if moving else IDLE_SWAY_AMP
		_sway_phase = fmod(_sway_phase + delta * (RUN_SWAY_SPEED if moving else IDLE_SWAY_SPEED), TAU)
		target = STANCE_DROP + sin(_sway_phase) * amp
	_stance_sway = lerpf(_stance_sway, target, minf(1.0, STANCE_LERP * delta))


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
			return  # 뒤집기는 _play_dir_anim이 조준각에서 파생한다(단일 소스)
	if _roll_time_left > 0.0:
		_roll_time_left -= delta
		velocity = _roll_dir * _roll_speed()  # 구르기는 늪 슬로우 예외(이속·roll_dist가 거리를 늘린다, GDD §6)
	else:
		# 걷기만 늪 배율 적용. 기 모으는 중(charge 무기)이면 추가로 느려진다 — 모으는 대가(사용자 확정)
		var charge_mult := CHARGE_MOVE_MULT if _charging else 1.0
		velocity = dir * _move_speed() * _swamp_mult() * charge_mult
		if _alive and Input.is_action_just_pressed("roll") and _roll_cd_left <= 0.0:
			_roll_dir = dir if dir != Vector2.ZERO else _aim_dir()
			_roll_time_left = CombatMath.ROLL_TIME_S
			# 🔴 로컬 쿨과 호스트 그랜트 검증(is_roll_grant_ok)이 **같은 함수**를 지난다(§3) —
			#   사본을 만들면 "굴러지는데 무적이 안 걸리는" 상태가 되고 화면에 이유가 안 드러난다.
			_roll_cd_left = CombatMath.effective_roll_cooldown(trait_value("roll_cd"))
			EventBus.player_roll.emit(global_position)  # 구르기 SFX (로컬)
			_dash_burst(_roll_dir)  # 잔상 첫 장·먼지 버스트·진행 방향 카메라 반동 (표시 전용)
			# 구르기 선언 — 호스트가 쿨다운 검증 후 i-frame 창 부여 (방향은 연출용)
			Net.send_game({NetSchema.KEY_KIND: NetSchema.G_ROLL, "dx": _roll_dir.x, "dy": _roll_dir.y})
	move_and_slide()
	# 뒤집기는 _play_dir_anim이 조준각에서 파생한다(단일 소스) — 여기서 대입하면 서로 덮어쓴다


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
		var dir := _aim_dir()
		# 모션 타입 분기 (§2 게이트): shoot = 원거리 발사(화살), charge = 위에서 처리, 그 외 = 근접 호 스윙.
		if motion == "shoot":
			# 🔴 쿨다운을 콤보가 정한다 — 다음 타에 뜸이 붙어 있으면 그만큼 길어진다("평·평·쭉").
			_attack_cd_left = _advance_shot_combo()
			_fire_projectile(dir, 0)
		else:
			_attack_cd_left = CombatMath.effective_cooldown(job, _haste())
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
	# 차지도 shoot과 **같은 콤보 경로**를 지난다 — 지팡이는 combo_* 배열이 비어 있어 결과가
	# effective_cooldown과 완전 항등이다(법사 동작 무변경). 갈래를 만들지 않으려는 것: 리듬 있는
	# 차지 무기가 생기면 .tres 한 장으로 떨어진다(rules §4).
	_attack_cd_left = _advance_shot_combo()
	_fire_projectile(_aim_dir(), level)


func _cancel_charge() -> void:
	_charging = false
	_charge_held = 0.0
	_charge_level = 0


# 원거리 평타 콤보 전진 — 이번 발사의 타수(_shot_combo_index)를 굳히고, **다음 타의 뜸까지 포함한**
# 쿨다운(s)을 돌려준다. 🔴 전진 규칙은 CombatMath.advance_combo 단일 소스이고 **호스트도 같은 함수**를
# 자기 수신 간격으로 돌린다(§3) — 여기에 사본 조건문을 두면 "내 화면은 3타인데 판정은 평타"가 된다.
# 🔴 뜸을 **다음 발사의 쿨다운에 미리 실어 두는 것**이 "3타 직전에 살짝 뜸"의 구현이다.
#   ⚠ **활은 클릭 1회 = 1발이다** — 발사 입력은 `_unhandled_input`의 `is_action_pressed`(엣지 트리거,
#   echo 없음)라 홀드 연사가 안 된다. 폴링(`Input.is_action_pressed`)은 `_tick_charge`(차지 전용)에만 있다.
#   그래서 뜸은 "버튼을 눌러 두면 알아서 나오는 리듬"이 아니라 **다음 클릭을 그만큼 늦게 받는 것**이다.
# 🔴 이 사실이 호스트 게이트 두 개에 서로 다르게 걸린다 (2026-07-27 netreview M3):
#   **하한(너무 빠름)** — 안전하다. `_attack_cd_left`가 뜸만큼 입력을 막으므로 정직한 클릭은 구조적으로
#     인정 하한보다 빠를 수 없다.
#   🔴 **상한(너무 쉼)** — 그 보호를 **못 받는다.** 사람이 언제 다시 클릭할지는 아무것도 강제하지 않는다.
#     조준하거나 굴렀다가 쏘면 창을 넘겨 콤보가 리셋된다 = "쭉"이 안 나온다. 그래서 창(COMBO_GRACE_S)은
#     전사 근접 콤보와 같은 총 0.95s로 맞춰 두었다 — 좁히면 리듬 자체가 실기에서 사라진다.
func _advance_shot_combo() -> float:
	var now := Time.get_ticks_msec()
	var haste := _haste()
	_shot_combo_index = CombatMath.advance_combo(_shot_combo_index,
		float(now - _last_shot_msec) / 1000.0, job, _weapon_override, haste)
	_last_shot_msec = now
	var nxt := (_shot_combo_index + 1) % CombatMath.combo_len(_weapon_override)
	return CombatMath.combo_gap_s(job, _weapon_override, nxt, haste)


# 이번 스윙의 궤적을 콤보 타수로 결정한다 — **연출 전용**이다(데미지·쿨다운·스윙 창은 안 바뀐다).
# 0타 = 우→좌 · 1타 = 좌→우(되돌려 베기) · 2타(마무리) = 같은 방향으로 더 크게 + 깊이 내지른다.
# 로컬(입력)과 원격(G_ATK "cb") 공용이라 양쪽 화면이 같은 궤적을 그린다.
func _begin_swing(combo: int) -> void:
	_combo_index = clampi(combo, 0, COMBO_MAX - 1)
	var arc := _swing_arc
	_swing_lunge_mult = 1.0
	if _combo_index == COMBO_MAX - 1:
		arc *= COMBO_FINISH_ARC
		_swing_lunge_mult = COMBO_FINISH_LUNGE
	# 홀수 타만 반대로 — 매번 같은 방향으로 휘두르면 팔이 순간이동해 되돌아온 것처럼 보인다.
	_swing_from = arc if _combo_index == 1 else -arc
	_swing_to = -arc if _combo_index == 1 else arc
	# 🔴 스윙 창은 콤보와 무관하게 _swing_time 그대로 — §3 미러(swing_time < attack_cooldown) 보존.
	_attack_anim_left = _swing_time


# 근접 호 스윙 — 로컬 원형 질의 판정(즉시, 프레임 지연 없음). 확정은 호스트(attack_hit → CombatAuthority).
func _swing_attack(dir: Vector2) -> void:
	# 콤보 이어가기: 직전 스윙 뒤 COMBO_WINDOW 안이면 다음 타, 아니면 처음부터.
	_begin_swing((_combo_index + 1) % COMBO_MAX if _combo_left > 0.0 else 0)
	_combo_left = _swing_time + COMBO_WINDOW
	_show_attack_fx(dir)
	EventBus.player_swing.emit(global_position, _swing_sfx)  # 스윙 SFX (로컬 — 무기별 휘두름음)
	if _combo_index == COMBO_MAX - 1:
		EventBus.camera_kick.emit(dir, COMBO_FINISH_KICK)  # 마무리 타는 헛쳐도 묵직하게
	# "cb" = 콤보 타수(표시 전용). 수신 측이 clamp하므로 조작해도 궤적만 달라진다 — 판정·데미지 무관.
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_ATK, "dx": dir.x, "dy": dir.y, "cb": _combo_index})
	# 판정: 조준 방향 원형 질의 (Area 노드 대신 즉시 질의 — 프레임 지연 없음)
	# 기하는 CombatMath 단일 소스 — FX 위치(_show_attack_fx)와 같은 함수라 어긋나지 않는다
	# reach 특성(검기 파형) — 판정도 FX도 같은 값을 받는다(§3 사거리 계약)
	var center := global_position + CombatMath.attack_center_offset(dir, job, trait_value("reach"))
	var shape := CircleShape2D.new()
	shape.radius = CombatMath.attack_radius(job, trait_value("reach"))
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
		EventBus.camera_kick.emit(dir, HIT_KICK)  # 때린 방향으로 밀림 — 셰이크와 다른 축(방향이 읽힌다)


# 원거리 발사(shoot = 활 · charge = 지팡이) — 표시 투사체 스폰(로컬)·G_SHOOT 송신(원격 표시)·(호스트) 권한 투사체 등록.
# 명중·폭발 판정과 데미지는 호스트 CombatAuthority가 투사체를 추적해 확정한다 (근접의 로컬 원형 질의 대신). 여기선 판정 없음.
# charge = 차지 레벨(0~3, 비차지 무기는 0) — 호스트가 clamp + 차지 시간 재검증(§3 신뢰 경계).
func _fire_projectile(dir: Vector2, charge: int) -> void:
	var origin := global_position + dir * MUZZLE_OFFSET
	_shot_seq += 1
	var aid := str(Net.my_id) + ":" + str(_shot_seq)
	_recoil_left = RECOIL_TIME  # 활 반동/지팡이 반동 연출
	# 발사는 **쏜 반대쪽**으로 카메라를 민다(근접 타격과 반대 부호) — 밀려나는 반동이 읽히게.
	# 차지 무기는 모은 단계만큼 더 세게(0단계도 최소 1배는 나가게 +1).
	# 마무리 타는 더 묵직하게 — 배율을 새 상수로 만들지 않고 **그 타의 데미지 배율을 그대로** 반동에
	# 쓴다(연출과 위력이 한 데이터에서 온다. 3타를 2.5배로 조이면 반동도 같이 따라온다).
	var combo_kick := CombatMath.combo_damage_mult_at(_weapon_override, _shot_combo_index)
	EventBus.camera_kick.emit(-dir, SHOOT_KICK * combo_kick
		* (1.0 + 0.45 * float(clampi(charge, 0, CombatMath.MAX_CHARGE_LEVEL))))
	# player_shoot: ArrowField가 표시 투사체 스폰 + (호스트 자신이면) CombatAuthority가 권한 투사체 등록
	EventBus.player_shoot.emit(Net.my_id, origin, dir, aid, _arrow_range, _weapon_id, charge,
		_shot_combo_index)
	EventBus.player_swing.emit(global_position, _swing_sfx)  # 발사 SFX (swing_sfx 재활용 = 시위·발사음)
	# "cb" = 콤보 타수. 🔴 G_ATK의 "cb"와 달리 **판정에 영향을 주는 값**이라 호스트가 그대로 믿지 않는다 —
	#   자기 수신 간격으로 직접 세고 이 주장은 상한으로만 쓴다(CombatMath.authoritative_combo, §3).
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_SHOOT, "ox": origin.x, "oy": origin.y,
		"dx": dir.x, "dy": dir.y, "aid": aid, "r": _arrow_range,
		"w": _weapon_id, "c": charge, "cb": _shot_combo_index})


func _aim_dir() -> Vector2:
	var d := get_global_mouse_position() - global_position
	return d.normalized() if d.length() > 0.001 else Vector2.RIGHT


# 궤적 예약 — 스윕 타이밍(_tick_timers의 딜레이 만료)에 맞춰 표시된다
func _show_attack_fx(dir: Vector2) -> void:
	_fx_dir = dir
	_fx_delay_left = ATTACK_FX_DELAY


# 검기 파형 발진 (메인 특성 보유자만) — 스윙 궤적 안에서 태어나 확장 사거리 끝(tip)까지 나아간다.
# tip은 호출부가 그 프레임 스워시에 쓴 것과 **같은 기하 계산 결과**다 — 그래서 파형이 멈추는 곳이
# 곧 판정이 닿는 곳이다(§3). 로컬·원격 모두 이 경로를 지난다(원격은 그 피어가 공지한 특성으로).
func _start_wave(tip: float) -> void:
	if job == null:
		return
	# 출발점은 **특성 없는 기본 사거리** 기준 — 파형이 "기본 도달점 밖으로 더 나아가는" 것으로 읽히게.
	var base_tip := CombatMath.attack_center_offset(_fx_dir, job).length() + CombatMath.attack_radius(job)
	_wave_dir = _fx_dir
	_wave_from = base_tip * WAVE_START_RATIO
	_wave_to = tip
	_wave_left = WAVE_FX_TIME
	_wave_fx.rotation = _fx_dir.angle()
	# 파형 두께 = 판정 반경 — 스워시와 같은 이유로 텍스처 실측(WAVE_TEX_HALF_H)에 맞춘다
	_wave_fx.scale = Vector2.ONE * (CombatMath.attack_radius(job, trait_value("reach")) / WAVE_TEX_HALF_H)
	_wave_fx.position = _wave_dir * _wave_from
	_wave_fx.modulate = _fx_color(1.0)
	_wave_fx.visible = true


# 파형 진행 — 앞으로 밀며 페이드. 무기 틴트(_fx_color)를 그대로 쓴다(§4: 중립 텍스처 + swing_color).
func _tick_wave(delta: float) -> void:
	if _wave_left <= 0.0:
		return
	_wave_left -= delta
	var t := 1.0 - clampf(_wave_left / WAVE_FX_TIME, 0.0, 1.0)
	_wave_fx.position = _wave_dir * lerpf(_wave_from, _wave_to, t)
	_wave_fx.modulate = _fx_color(1.0 - t * t)  # 끝에서 빠르게 흩어진다
	if _wave_left <= 0.0:
		_wave_fx.visible = false


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


# 원격 플레이어의 공격 연출 (stage가 G_ATK 수신 시 호출) — 표시 전용, 판정 아님.
# combo = G_ATK "cb"(그 피어의 콤보 타수) — 궤적만 정하므로 조작돼도 화면이 달라질 뿐이다(clamp는 _begin_swing).
func play_attack_fx(dir: Vector2, combo: int = 0) -> void:
	if not _alive or not _is_armed():
		return  # 사망자·무장 해제 피어의 G_ATK로 FX가 뜨는 것 차단 (그 피어 무기 = set_weapon_visual 반영)
	_show_attack_fx(dir)
	# 조준각을 즉시 그 방향으로 당긴다 — 다음 G_POS를 기다리면 스윙이 옛 방향으로 한 박자 나간다.
	# (뒤집기는 _play_dir_anim이 이 각에서 파생한다 — flip_h를 여기서 대입하면 서로 덮어쓴다)
	if is_finite(dir.x) and is_finite(dir.y) and dir.length_squared() > 0.000001:
		_remote_aim = dir.angle()
		_remote_flip = dir.x < 0.0  # 4방향 시트가 없을 때의 폴백 경로가 읽는 값
	if _attack_anim_left <= 0.0:
		# 애니 창만 재수신 무시(FX·방향은 매번 적용) — G_ATK 스팸으로 애니를 영구 attack으로
		# 잠그는 그리핑 차단 (정직한 공격은 쿨다운 0.4s > 창(≤0.25~0.34)이라 안 걸린다)
		EventBus.player_swing.emit(global_position, _swing_sfx)  # 스윙 SFX (원격 — 무기별, 스팸 게이트 안)
		_begin_swing(combo)  # 원격도 그 피어의 무기 스윙 창 + 같은 콤보 궤적


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
		_remote_flip = dir.x < 0.0  # 4방향 시트가 없을 때의 폴백 경로가 읽는 값
	if is_finite(dir.x) and is_finite(dir.y):
		_roll_dir = dir  # 대쉬 종료 되튐 방향 — 원격은 카메라가 없으니 잔상·먼지에만 쓰인다
	_dash_burst(dir)  # 원격도 같은 대쉬 연출(잔상·먼지). 카메라 킥은 _dash_burst 안에서 로컬만


func _send_pos(delta: float) -> void:
	_send_accum += delta
	if _send_accum >= 1.0 / POS_SEND_RATE:
		_send_accum = 0.0
		_pos_seq += 1
		Net.send_game({
			NetSchema.KEY_KIND: NetSchema.G_POS,
			# 송신 시퀀스 — P2P fast 채널이 unordered라 순서 뒤바뀜을 수신부가 걸러야 한다 (§3, CombatMath.is_pos_seq_fresh).
			"n": _pos_seq,
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
		vel: Vector2 = Vector2.ZERO, seq: int = 0) -> void:
	# 🔴 순서 뒤바뀜 폐기 — **속도·조준각·차지까지 포함해 통째로** 버린다(맨 앞에서 return).
	#   옛 패킷의 vel만 새겨도 외삽이 과거 속도로 돌아가 방어자 우대가 무력화된다 (§3).
	if not CombatMath.is_pos_seq_fresh(seq, _last_pos_seq):
		return
	if seq > 0:
		_last_pos_seq = seq
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
		var max_speed := _max_roll_speed()  # 🔴 이속·kill_move·roll_dist 반영 — 안 하면 지연 보상이 부분 퇴행한다(§3)
		_remote_vel = vel.limit_length(max_speed)
	else:
		_remote_vel = Vector2.ZERO
	if not (is_finite(pos.x) and is_finite(pos.y)):
		return  # 무효 좌표는 통째로 무시 — 이전 앵커 유지
	var now := Time.get_ticks_msec()
	if _last_remote_msec >= 0:
		var dt := maxf(float(now - _last_remote_msec) / 1000.0, 1.0 / POS_SEND_RATE)
		var max_disp := _max_roll_speed() * REMOTE_MAX_SPEED_MULT * dt  # 속도 상한과 같은 유도식(갈라지면 한쪽만 튜닝된다)
		var delta := pos - _remote_target
		if delta.length() > max_disp:
			pos = _remote_target + delta.normalized() * max_disp
	_last_remote_msec = now
	_remote_target = pos
	_remote_flip = flip
