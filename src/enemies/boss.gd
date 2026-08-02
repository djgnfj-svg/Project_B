extends CharacterBody2D
# 보스 공용 — 잔몹 FSM(mob_melee)을 다패턴으로 확장. 어느 보스든 `BossDef`(patterns/frames)로 돌리는
# 데이터 주도 배우다(특정 몬스터 전용이 아니다 — 그래서 이름에 종을 박지 않는다).
# AI·판정 결정은 호스트만(rules §1·§3),
# 게스트는 mpos 수신 표시 + G_BOSS_ATK 텔레그래프 표시만. 판정·데미지 확정은 여기 없다 —
# WINDUP 만료(STRIKE) 시점을 EventBus.boss_strike로 알리면 CombatAuthority(호스트)가 확정한다.
# 수치는 전부 def(BossDef, .tres)가 쥔다 (rules §4 — "새 보스 = 파일 한 장"). 연출값만 const 예외.
# ⚠ 씬 전용 글루(오토로드 전역 식별자 사용) — -s 헤드리스 테스트에서 preload 금지 (rules §5).

const HealthComponent := preload("res://src/combat/health_component.gd")
const PlayerActor := preload("res://src/player/player.gd")
const HitStop := preload("res://src/feel/hit_stop.gd")
const HitFlash := preload("res://src/feel/hit_flash.gd")
const Flinch := preload("res://src/feel/flinch.gd")
const TELEGRAPH_SHADER := preload("res://assets/shaders/boss_telegraph.gdshader")

# 연출값 (rules §0 예외)
const REMOTE_LERP_SPEED := 12.0
const REMOTE_MOVE_EPS := 1.0      # 게스트 표시: 목표점과 이만큼 이상 벌어져 있으면 walk

# 텔레그래프 연출값 (rules §0 예외 — 사용자가 조인다, docs/TUNING.md 대상).
# 🔴 기하값(각·반지름)은 여기 없다 — 전부 BossPatternDef에서 파생한다. 여기 숫자를 늘려
# 예고를 "조금 더 크게" 만들지 마라: 그 순간 보이는 곳과 맞는 곳이 갈라진다(§3).
const TELEGRAPH_BORDER_PX := 3.0       # 테두리 두께(경계 안쪽)
# 🔴 경계 소프트 폭(월드 px) — **바깥으로만** 퍼진다. 셰이더가 알파 램프를 `smoothstep(-aa, 0, d)`로
# 잡아 판정 안(d ≥ 0)은 알파 1이고 밖으로만 이만큼 사라진다 = **틀리는 방향이 항상 과예고**.
# ⚠ 2026-08-02에 격자 스냅(`pixel_px` 2.0 + `edge_bias_px` 1.41)을 폐기하며 이 상수가 그 자리를
# 대신했다. 옛 여유는 "스냅이 표본점을 최대 셀 반대각선만큼 옮기니 그만큼 관대하게"라는 유도였는데,
# 스냅이 없으면 표본점이 진짜 그 자리라 여유 자체가 필요 없다(실측 과예고 2.83px → aa 1.0px, 그것도
# 반투명). 근거였던 "전 게임 16px 도트와 같은 계단"은 **16px 세대 기준**이고 지금은 32px + 줌 1.5다.
# ⚠ 안티에일리어싱에 `fwidth`/derivative를 쓰지 않는다(웹 Compatibility 안전 목록 밖, rules §5) —
# 셰이더가 월드 px 폭을 직접 받는 이유다.
const TELEGRAPH_AA_PX := 1.0
# 쿼드 여유(월드 px) — 화면 픽셀 중심이 쿼드 밖으로 나가 프래그먼트가 아예 안 도는 것을 막는다.
# 줌 1.5에서 화면 반픽셀 = 0.33 월드px이므로 1.0이면 넉넉하다.
const TELEGRAPH_QUAD_MARGIN_PX := 1.0
const TELEGRAPH_FILL := Color(0.910, 0.275, 0.110, 0.306)    # 옛 telegraph_cone.png 채움색 실측 미러
const TELEGRAPH_BORDER := Color(1.000, 0.604, 0.235, 0.729)  # 옛 telegraph_cone.png 테두리색 실측 미러
const TELEGRAPH_FILL_FADE := 0.25      # 바깥으로 갈수록 옅어지는 정도
const TELEGRAPH_PULSE_AMP := 0.10
const TELEGRAPH_PULSE_HZ := 2.2
# 차오름(임박도) 연출값 — "언제 터지는지가 눈에 보인다". 🔴 기하가 아니라 **색만** 바꾼다(§3).
const TELEGRAPH_CHARGE := Color(1.000, 0.451, 0.129, 0.620)  # 다 찬 구역(더 뜨겁고 진하게)
const TELEGRAPH_LEAD_PX := 7.0         # 차오름 선단(밝은 파면) 두께
const TELEGRAPH_FLASH := Color(1.000, 0.925, 0.722, 0.880)   # 마지막 순간 번쩍
const TELEGRAPH_FLASH_START := 0.86    # 이 진행도부터 번쩍이 올라온다

# 추격 이탈 = aggro_range × 이 배수. 씬 스왑 프레임 유령 어그로 방지 (mob_melee와 동일 규약, rules §5).
const LEASH_MULT := 1.5

# 공격 애니 이름(=BossPatternDef.id 관례). 이 애니가 도는 동안엔 walk/idle로 덮지 않는다.
const ATTACK_ANIMS: Array[StringName] = [&"swing", &"slam", &"spray", &"spin", &"charge_windup", &"charge_dash", &"charge_hit", &"charge_recover"]

# 공격 애니 speed_scale 하한 — 0/음수는 애니를 세우거나 거꾸로 돌린다. 히트스톱 정지(0.0) 판별과도 겹치지 않게.
const MIN_ANIM_SPEED_SCALE := 0.01

# 유령 생명감 연출 (rules §0 예외 — 사용자가 조인다). 🔴 손맛 계층과 채널이 안 겹치게 골랐다:
# 부유=offset.y(위치는 Flinch), 명멸=modulate.a(머티리얼은 HitFlash), 아우라=별도 자식 스프라이트.
# scale은 HitStop, speed_scale은 _apply_anim_scale이 쥐고 있어 건드리지 않는다.
const BOB_HZ := 0.7            # 부유 주기(Hz) — 아주 느긋하게
const BOB_AMP := 0.8           # 부유 진폭(px) — 위아래는 거의 안 느껴질 만큼만
const SWAY_HZ := 0.35         # 좌우 표류 주기(Hz) — 느리게 (부유와 다른 주기라 정처 없이 떠도는 느낌)
const SWAY_AMP := 1.0         # 좌우 표류 진폭(px)
# 노이즈 지터 — 손상된 데이터 프로세스가 지직거리는 흔들림(사인 드리프트에 얹음). 컨셉 = 데이터 망령.
const NOISE_AMP := 1.6        # 노이즈 흔들림 진폭(px)
const NOISE_SPEED := 1.2      # 노이즈 표본 이동 속도(클수록 빠른 지직임) — 느긋하게 꿈틀대게
const SHIMMER_HZ := 2.2        # 명멸 주기(Hz)
const SHIMMER_MIN_A := 0.84    # 명멸 최소 알파(1.0까지 왕복)
const AURA_HZ := 1.35          # 아우라 맥동 주기(Hz)
const AURA_BASE_SCALE := 1.15  # 아우라 기본 스케일(128px 방사 텍스처 기준)
const AURA_PULSE := 0.1        # 아우라 맥동 폭(스케일 배수)
const AURA_COLOR := Color(0.32, 0.8, 0.66, 0.42)  # 가산 청록 발광
# 망토 나부낌 — 스프라이트 skew(전단)를 이동 방향으로 기울인다(바람에 쓸리는 망토). 정지 땐 은은히 흔들림.
# skew는 손맛 채널과 안 겹친다(scale=HitStop·position=Flinch·material=HitFlash·offset=부유).
const CAPE_SKEW_MAX := 0.12     # 최대 기울기(rad, 약 7°) — 줄임
const CAPE_VEL_K := 0.0014      # 이동속도(px/s) → 기울기 계수
const CAPE_IDLE_AMP := 0.03     # 정지 시 흔들림 진폭(rad, 약 1.7°) — 줄임
const CAPE_IDLE_HZ := 0.28      # 정지 흔들림 주기 — 느리게
const CAPE_VEL_SMOOTH := 2.5    # 이동속도 저역통과 — 낮을수록 부드럽게(kiting 스터터 흡수)
# 카운터 반응 — 약점(카운터 가능) 동안 몸색 변화 + 성공 시 잠깐 꿇음. 표시 전용(보스가 자기 채널 소유).
const COUNTER_TINT := Color(1.5, 1.2, 0.55)  # 카운터 가능 시 몸색(밝은 앰버 — 약점 노출 신호)
const STAGGER_DUR := 0.4        # 카운터 성공 꿇음 지속(s)
const STAGGER_DROP := 9.0       # 꿇을 때 아래로 꺾이는 양(px, offset)
const STAGGER_LEAN := 0.22      # 꿇을 때 앞으로 숙이는 skew

enum State { IDLE, CHASE, WINDUP, RECOVER, CHARGE_DASH, CHARGE_HIT }

# 돌진(P3) 연출 상수 (rules §0 예외 — 손맛값, docs/TUNING.md 대상)
const CHARGE_HIT_DUR := 0.3       # 바위 충돌 리코일(튕김) 지속(s) — 짧게, 이후 그로기로
const CHARGE_RECOIL_SPEED := 180.0  # 바위 충돌 시 뒤로 튕기는 초기 속도(px/s)
const CHARGE_TIMEOUT_MARGIN := 0.4  # 돌진 타임아웃 = 이동시간 + 이 여유(벽에 낀 채 무한 돌진 방지)
const CHARGE_SPIN_TIME := 1.0       # 돌진+회전 총 지속(s). 이동은 앞부분(속도로 0.5s쯤 도달)
const WHIRL_OFFSET_Y := -13.0       # F7 회오리 시트(128px, 발밑 y96)를 방향 시트 발 높이에 맞추는 오프셋

@export var eid: String = ""
@export var def: BossDef

var _state: State = State.IDLE
var _state_left: float = 0.0
var _phase: int = 1                    # 페이즈(1→2). hp ≤ max_hp*phase2_hp_ratio 최초 도달 시 호스트가 2로.
var _prev_hp: int = 0                  # combat_impact 감소량 계산용
var _cur_pattern: BossPatternDef = null  # WINDUP 중 선택된 패턴
var debug_hold: bool = false  # 테스트 랩 — true면 자동 패턴 선택 안 함(버튼으로만 발동). TestMode 게이트, 외부 설정.
var _strike_center: Vector2 = Vector2.ZERO
var _strike_angle: float = 0.0
var _pattern_last_msec: Dictionary = {}  # pattern.id -> 마지막 발동 msec (호스트 전용 쿨다운 게이트)
var _swamp_seq: int = 0                # 늪 생성 로컬 id 시퀀스
var _rock_seq: int = 0                 # 낙석(P4) 바위 스폰 로컬 id 시퀀스 (_swamp_seq 미러 — 고유 rid 생성)
var _strike_centers: Array = []        # 물뿌리기 착탄점(Vector2) — 비었으면 단일 패턴(_strike_center)
var _max_hp: int = 0                   # party_scale 적용된 max_hp (페이즈2 임계·초기 hp 단일 소스)
var _p2_swamp_accum: float = 0.0       # 페이즈2 자동 늪 생성 카운트다운(호스트 전용)
var _remote_target: Vector2 = Vector2.ZERO
var _remote_flip: bool = false
var _telegraph_left: float = 0.0       # 표시용 자동 숨김 타이머(각 클라 로컬 리졸브)
# 🔴 이번 예고의 월드 중심 — **매 물리 프레임 재주장한다**(`_reassert_telegraph_pos`). `$Telegraph`가
# Boss의 자식이라 `global_position`을 한 번만 심으면 **부모가 움직인 만큼 예고가 따라 끌려간다.**
# 호스트는 WINDUP에서 정지(velocity = ZERO)라 안 드러나지만, **게스트는 매 프레임 원격 위치로 lerp**해
# 예고가 t=0에 정확한 자리에 찍혔다가 남은 1초 내내 9~14px 어긋난 채 있다(netreview 실측: 배포 13.8px ·
# P2P 9.1px · dev_local 8.7px). 셰이더가 세운 "틀리면 과예고 방향으로만"(예산 2.83px) 보장이 **노드
# 좌표계 바깥에서** 깨지는 자리다 — 밀리는 방향이 보스 진행 방향이라 **무예고 쪽으로도** 떨어진다.
var _telegraph_center: Vector2 = Vector2.ZERO
# 이번 예고를 띄워둘 시간(초) — 호스트는 지연 보상분이 더해진 값, 게스트는 pat.telegraph_s 그대로.
# WINDUP 진입/예고 수신 때 한 번 확정해 표시·타격이 같은 값을 쓰게 한다(중간에 RTT가 흔들려도 안 갈라지게).
var _telegraph_hold_s: float = 0.0
# 🔴 이번 예고의 **총 길이** = 차오름(progress)의 분모. `_telegraph_duration()` 한 곳에서만 온다 —
# 그 함수의 네 번째 파생값이고 새 계산이 아니다(§3: 표시 지속 · N개 원 타이머 · 애니 길이 · 차오름).
# 식을 여기서 다시 쓰면 "예고는 끝났는데 차오름은 70%"처럼 표시끼리 갈라진다.
var _telegraph_total_s: float = 0.0
var _telegraph_mat: ShaderMaterial = null  # 매 프레임 progress를 심을 대상(캐시 — 재조회 비용 제거)
var _move_hold: float = 0.0   # 이동 디바운스 — 잔멈춤에도 walk 애니가 프레임0으로 리셋 안 되게 (0이면 idle 복귀)
var _face_dir: String = "s"   # 8방향 바라보기 접미사(플레이어 방향) — 디렉셔널 애니(idle_<dir>/slam_<dir>) 선택용. 없으면 base 폴백.
var _anim_scale: float = 1.0           # 지금 애니에 걸려 있어야 할 speed_scale (공격 애니만 1.0이 아니다)
var _life_t: float = 0.0               # 생명감 연출 시간 누적(부유·명멸·아우라 위상)
var _prev_life_x: float = 0.0          # 망토 나부낌용 직전 x (이동량 = 위치 델타, 호스트/게스트 공통)
var _cape_vel: float = 0.0             # 저역통과된 수평 이동속도 (kiting 스터터 흡수 — 망토가 홱 안 꺾임)
var counter_ready: bool = false        # 약점 표식이 떠 있는 동안 true (외부=랩이 매 프레임 설정) → 몸색 변화
var speed_mult: float = 1.0            # 이동(접근) 속도 배수 — 외부(랩)가 설정, 기본 1이라 프로덕션 무영향
var groggy_left: float = 0.0           # 그로기(격파 당함) 남은 시간 — 눕고 무방비. 외부가 enter_groggy로 설정.
var _stagger_t: float = 0.0            # 카운터 성공 꿇음 타이머
var _aura: Sprite2D = null             # 보스 발밑 가산 발광(따라다님) — _ready에서 생성
var _noise: FastNoiseLite = null       # 지터용 연속 노이즈(1D 표본) — _ready에서 생성
var _charge_seq: int = 0               # 돌진(P3) 회차 id — 스윕 dedup 키(돌진당 +1, CombatAuthority._boss_sweep_seq와 짝)
var _charge_start: Vector2 = Vector2.ZERO  # 이번 돌진 시작 위치 — 이동거리(travel_max) 판정 기준
var _c1_frames: SpriteFrames = null    # C1 코옵 전용 클립 시트(roar/grab/groggy — mino_boss_c1) 지연 로드
var _spin_frames: SpriteFrames = null  # 돌진 회전 전용 풀캐릭터 시트(mino_spin_full) 지연 로드
var _whirl_frames: SpriteFrames = null # F7 제자리 회오리 전용 시트(mino_whirl, 128px + 황금 에너지) 지연 로드
var _hitfall_frames: SpriteFrames = null  # 바위 충돌·그로기 클립 시트(mino_hit_fall) 지연 로드
var _hitfall_active: bool = false          # 충돌/그로기 클립 재생 중 — 그로기 끝나면 end_c1_clip으로 복귀
var _spin_anim_active: bool = false        # 제자리 회오리(pat_spin=F7) 클립 재생 중 — RECOVER 끝에 방향 시트 복귀
var _c1_active: bool = false           # C1 클립 재생 중 — 생명감 눕기 포즈를 건너뛴다(클립이 곧 포즈)
var coop_locked: bool = false          # C1 결박 중 — 패턴 AI 정지(외부=coop_authority가 설정). 페이즈2 자동 늪도 멈춤(설계 §9)
# --- 넉백 (2026-08-02) — `mob_melee`와 **같은 계약·같은 함수**(사본이 아니라 같은 규칙이다) ---
# 🔵 보스는 사실상 안 밀린다 — 저항이 `body_radius`(63)에서 유도돼 0.036이라 최대 0.44px다.
#   **플래그 없이 데이터가 거른다**(설계 A-5). 그래도 상태 게이트(`can_knock`)는 필요하다:
#   돌진(P3)은 `_charge_start`로부터의 **이동 거리**로 종료를 판정하므로 1px여도 velocity를 덮으면
#   눈에 띄게 히치한다.
var _knock_dir := Vector2.ZERO
var _knock_left: float = 0.0
var _knock_speed: float = 0.0
var _knock_show_px: float = -1.0   # 층① 세기(호스트에만 선다 — 게스트는 -1 = 항등 폴백)

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _collision: CollisionShape2D = $Collision
@onready var _telegraph: Sprite2D = $Telegraph
@onready var _health: HealthComponent = $Health
# 접지 그림자 — 씬에 authoring된 위치·크기를 `sprite_scale`로 같이 키운다(없으면 발밑이 뜬다).
@onready var _shadow: Sprite2D = get_node_or_null("Shadow") as Sprite2D


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("mob")  # MobSync mpos 배치·G_BOSS_ATK 라우팅이 이 그룹으로 문다
	_remote_target = global_position
	# 🔴 예고가 끝나도 머티리얼을 떼지 않는다 — hit_flash의 "끝나면 material=null" 규율(§5)과 다른 판단이다.
	# 그 규율의 근거는 "평상시에도 그려지는 스프라이트에 셰이더가 남으면 웹 Compatibility에서 항등이
	# 아닐 수 있다"인데, 이 노드는 예고 밖에서 visible=false라 **아예 그려지지 않는다**(항등을 물을 상태가
	# 없다). 반대로 떼면 남는 것이 1×1 흰 쿼드라 혹시 visible이 살아 있는 순간엔 거대한 흰 사각이 뜬다 —
	# 붙여 두는 쪽이 안전한 방향이다. 대신 표시할 때마다 셰이더·uniform을 전부 다시 심어
	# (_apply_telegraph_geometry) 낡은 값이 남을 경로를 없앤다. N개 원은 노드째 free되므로 무관.
	_telegraph.visible = false
	if def != null:
		if def.frames != null:
			_sprite.sprite_frames = def.frames
		elif def.sprite != null:
			# 애니 없는 개체 폴백 — sprite 1장을 idle로 감싼다 (placeholder 호환)
			var sf := SpriteFrames.new()
			sf.rename_animation(&"default", &"idle")
			sf.add_frame(&"idle", def.sprite)
			_sprite.sprite_frames = sf
		# 스프라이트 배율 — 시트 재작화 없이 덩치만 키운다 (`mob_melee.gd`의 `sprite_scale` 관용구).
		# 🔴🔴 **잔몹처럼 `Vector2.ONE * sprite_scale`로 대입하지 마라 — 보스는 작아진다.**
		#   `boss.tscn`의 Sprite는 이미 `scale = (2, 2)`로 authoring돼 있다(64px 시트를 128px로).
		#   대입식을 그대로 베끼면 2.0 → 1.5가 되어 **키우려던 변경이 축소가 된다**(에러 없음).
		#   곱셈이면 기본값 1.0에서 **완전 항등**이라 배율을 안 적은 BossDef도 안 깨진다.
		# 🔴 **`body_radius`도 같이 올려야 한다** — 판정은 그쪽이 정한다(`EnemyDef.sprite_scale` 필드
		#   주석이 정본). 그림만 키우면 "몸통에 맞췄는데 안 맞는다"가 되고 화면에 이유가 안 드러난다.
		#   `tests/test_boss_data_auto.gd`의 「덩치 ↔ 판정 반경」 단정이 데이터 축에서 이걸 지킨다.
		# 🔴 **`HitStop.punch`보다 먼저여야 한다** — punch가 첫 호출 때 현재 `scale`을 `hs_base_scale`
		#   meta에 저장해 복원 기준으로 삼기 때문이다(rules §2). `_ready` 시점이라 안전하다.
		if def.sprite_scale > 0.0:
			_sprite.scale *= def.sprite_scale
			# 그림자는 스프라이트를 안 따라간다(별도 형제 노드) → 같은 배율로 위치·크기를 같이 민다.
			# 위치까지 곱하는 이유: authoring 값 y=42는 "그 배율에서의 발밑"이라 배율에 비례한다.
			# 안 밀면 보스가 커진 만큼 발이 그림자 아래로 내려가 **떠 보인다**.
			if _shadow != null:
				_shadow.position *= def.sprite_scale
				_shadow.scale *= def.sprite_scale
		# 몸 판정 반경 = def.body_radius — shape 리소스는 씬 인스턴스 간 공유라 복제 후 적용 (rules §5)
		var shape := _collision.shape.duplicate() as CircleShape2D
		if shape != null:
			shape.radius = def.body_radius
			_collision.shape = shape
		# 솔로 약화 — 인원 스케일(§3 party_scale). 호스트/게스트 같은 피어 수 → 동일 계산(표시 일치),
		# 정본 hp는 ehp라 무해. 페이즈2 임계도 이 스케일 max를 기준으로 삼는다.
		_max_hp = int(CombatMath.party_scale(float(def.max_hp), _party_size()))
		_health.setup(_max_hp, def.respawns, def.respawn_delay)
		_prev_hp = _max_hp
	_health.hp_changed.connect(_on_hp_changed)
	# 권한 경로(호스트 apply_damage)에서만 발화 — CombatAuthority가 ehp 브로드캐스트 + 클리어 판정.
	_health.hp_confirmed.connect(func(hp: int) -> void: EventBus.enemy_hp_confirmed.emit(eid, hp))
	# 물뿌리기 N개 원 텔레그래프 + 애니 = 이 구독이 그린다 (호스트/게스트 공용 단일 경로).
	EventBus.boss_spray.connect(_on_boss_spray)
	if def != null and def.ghostly:
		_setup_aura()   # 유령 보스만 발광 아우라 — 실체 보스(미노)는 아예 안 만든다
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 1.0   # 표본 좌표를 _life_t*NOISE_SPEED로 직접 굴리므로 여기선 항등에 가깝게
	_play(&"idle")


# 발밑 가산 발광 — 유령이 오염 에너지에 감싸인 느낌. 보스 자식이라 이동을 따라온다(코드 생성 = 씬 무변경).
func _setup_aura() -> void:
	_aura = Sprite2D.new()
	_aura.texture = _radial_tex()
	_aura.z_index = -3                       # 몸(0) 아래·바닥(-10) 위 — 보스를 감싸는 발광
	_aura.z_as_relative = false
	_aura.modulate = AURA_COLOR
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_aura.material = m
	_aura.scale = Vector2.ONE * AURA_BASE_SCALE
	add_child(_aura)


func _on_hp_changed(hp: int, dropped: bool) -> void:
	var dead := hp <= 0
	_collision.set_deferred("disabled", dead)
	# 🔴 실데미지 우선, hp 감소량은 폴백 — 오버킬 절삭 방지 (mob_melee와 같은 규약, 2026-08-01).
	#   `_prev_hp` 갱신이 `if dropped` 밖인 이유도 거기 주석이 정본이다(netreview M-3).
	var amount := _health.last_damage if _health.last_damage > 0 else _prev_hp - hp
	_prev_hp = hp
	if dropped:
		EventBus.combat_impact.emit("enemy", global_position, maxi(amount, 0), _health.last_crit)  # 손맛 공용 훅 (crit = 표시 강조)
		if dead:
			EventBus.entity_died.emit("enemy", global_position, def.respawns)  # 사망 SFX (+ 광란 제외 판단)
		else:
			HitStop.punch(_sprite)   # 맞은 대상만 정지+스케일 튕김
			HitFlash.flash(_sprite)  # 흰색 번쩍
			_play_flinch()
	else:
		_prev_hp = hp
	# 페이즈 전이 — 호스트만 확정(로컬 페이즈). 임계는 party_scale 적용된 _max_hp 기준(솔로 정합).
	if Net.is_host() and _phase < 2 and not dead and def != null \
			and hp <= int(_max_hp * def.phase2_hp_ratio):
		_phase = 2
		_p2_swamp_accum = _auto_swamp_interval()  # 즉시 늪 방지 — 첫 자동 늪은 한 간격 뒤
		EventBus.boss_phase_changed.emit(2)  # MobSync가 G_BOSS_PHASE 중계·HUD가 배너 (표시 큐)
	if dead:
		_telegraph.visible = false
		_telegraph_left = 0.0
		_knock_left = 0.0      # 시체는 안 밀린다 (mob_melee와 같은 규약)
		_knock_show_px = -1.0
		velocity = Vector2.ZERO
		_state = State.IDLE
		if _has_anim(&"death"):
			visible = true
			_play(&"death")  # 시체 남김(loop=false 전제) — 없으면 숨김
		else:
			visible = false
	else:
		visible = true
		# 공격 애니가 도는 중이 아니면 idle 복귀 (피격 흠칫과 겹치지 않게)
		if not _is_attack_anim_playing():
			_play(&"idle")


func _physics_process(delta: float) -> void:
	if _telegraph_left > 0.0:
		_telegraph_left -= delta
		if _telegraph_left <= 0.0:
			_telegraph.visible = false
		_update_telegraph_progress()
	_apply_anim_scale()
	_update_life_feel(delta)
	if _health.is_dead() or def == null:
		_reassert_telegraph_pos()
		return
	var raw_moving := false
	if Net.is_host():
		_host_ai(delta)
		_tick_knock(delta)   # 🔴 AI **뒤** — 넉백이 그 프레임의 이동을 대체한다(합산 금지, A-9)
		raw_moving = _state == State.CHASE and velocity.length_squared() > 0.0
	else:
		raw_moving = global_position.distance_to(_remote_target) > REMOTE_MOVE_EPS
		global_position = global_position.lerp(_remote_target, minf(1.0, REMOTE_LERP_SPEED * delta))
		_sprite.flip_h = _remote_flip
	# 디바운스: 움직이면 즉시 walk, 멈춰도 0.25초는 유지 → 잔멈춤에 walk가 리셋되지 않는다.
	_move_hold = 0.25 if raw_moving else maxf(0.0, _move_hold - delta)
	_update_move_anim(_move_hold > 0.0)
	# 🔴 **몸이 움직인 뒤에** 예고를 제자리에 다시 못 박는다 — 순서가 계약이다. 위쪽(타이머 감산 자리)에서
	# 부르면 그 프레임의 이동(_host_ai의 move_and_slide · 게스트 lerp)이 뒤따라와 한 프레임씩 밀린다.
	# `_apply_anim_scale()`이 speed_scale을 매 프레임 재주장하는 것과 같은 관용구다(rules §2 손맛 계층 —
	# "소유자가 자기 의도를 재주장한다"). 대안이던 `top_level = true`는 드로우 순서까지 바꿔 z 층
	# (바닥 -10 < 예고 -1 < 몸 0)을 눈으로 재확인해야 하므로 고르지 않았다.
	_reassert_telegraph_pos()


# 유령 생명감 — 부유(offset.y)·명멸(modulate.a)·아우라 맥동. 표시 전용, 호스트/게스트 공통(로컬 위상).
# 🔴 손맛 채널과 안 겹친다(선언부 주석): 위치=Flinch·스케일=HitStop·머티리얼=HitFlash·speed=애니.
# 죽으면 정지하고 값을 원상 복구해 시체가 명멸/부유하지 않게 한다.
func _update_life_feel(delta: float) -> void:
	if _health.is_dead():
		_sprite.offset = Vector2.ZERO
		_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
		_sprite.skew = 0.0
		_stagger_t = 0.0
		if _aura != null:
			_aura.visible = false
		return
	# 그로기(격파) — 옆으로 눕고(회전) 바닥으로 내려앉아 무방비. 흔들림·아우라 정지.
	if groggy_left > 0.0:
		groggy_left -= delta
		if _c1_active:
			return   # C1 groggy 클립이 포즈를 맡음 — 회전/오프셋 안 건드린다
		_sprite.rotation = lerp_angle(_sprite.rotation, 1.43, minf(1.0, delta * 9.0))  # ~82° 눕기
		_sprite.offset = Vector2(0.0, 16.0)
		_sprite.skew = 0.0
		_sprite.modulate = Color(0.7, 0.72, 0.82, 0.9)   # 흐릿(무력)
		if _aura != null:
			_aura.visible = false
		return
	# 그로기 끝 — hit_fall 클립(충돌/눕기)이 재생 중이었으면 방향 시트로 복귀.
	# CHARGE_HIT(충돌 리코일 0.3s) 동안엔 아직 그로기 전이라 안 끝낸다(상태로 가드).
	if _hitfall_active and _state != State.CHARGE_HIT:
		_hitfall_active = false
		end_c1_clip()
	# 그로기 끝 — 회전 원위치로 복구
	if not is_zero_approx(_sprite.rotation):
		_sprite.rotation = lerp_angle(_sprite.rotation, 0.0, minf(1.0, delta * 9.0))
	# 클립(회전/충돌/회오리) 재생 중엔 클립이 곧 포즈 — 생명감 드리프트(offset·skew)를 건너뛴다(회오리 오프셋 유지).
	if _c1_active:
		return
	_life_t += delta
	# 사인 드리프트(정처 없이) + 노이즈 지터(지직거림). 노이즈는 x/y 표본 좌표를 멀리 떨어뜨려 상관 제거.
	var nx := _noise.get_noise_1d(_life_t * NOISE_SPEED) if _noise != null else 0.0
	var ny := _noise.get_noise_1d(_life_t * NOISE_SPEED + 1000.0) if _noise != null else 0.0
	if def != null and def.ghostly:
		_sprite.offset.x = sin(_life_t * TAU * SWAY_HZ) * SWAY_AMP + nx * NOISE_AMP
		_sprite.offset.y = sin(_life_t * TAU * BOB_HZ) * BOB_AMP + ny * NOISE_AMP
	else:
		_sprite.offset = Vector2.ZERO   # 실체 보스는 부유 없음 (땅에 붙어 있음)
	# 망토 나부낌 — 이동 방향으로 기운다(위치 델타 = 호스트/게스트 공통) + 정지 시 은은한 흔들림.
	# 🔴 순간속도를 그대로 쓰면 kiting(다가갔다 멈춤)에 망토가 툭툭 끊긴다 → 저역통과로 부드럽게.
	var mv := (global_position.x - _prev_life_x) / maxf(delta, 0.0001)
	_prev_life_x = global_position.x
	_cape_vel = lerpf(_cape_vel, mv, minf(1.0, delta * CAPE_VEL_SMOOTH))
	var target_skew := clampf(-_cape_vel * CAPE_VEL_K, -CAPE_SKEW_MAX, CAPE_SKEW_MAX)
	target_skew += sin(_life_t * TAU * CAPE_IDLE_HZ) * CAPE_IDLE_AMP
	_sprite.skew = lerpf(_sprite.skew, target_skew, minf(1.0, delta * 4.0))
	# 카운터 성공 꿇음 — 잠깐 아래로 꺾이고 앞으로 숙인다(offset·skew에 덧댐). rise-fall 엔벨로프.
	if _stagger_t > 0.0:
		_stagger_t -= delta
		var sk := sin((1.0 - clampf(_stagger_t / STAGGER_DUR, 0.0, 1.0)) * PI)
		_sprite.offset.y += sk * STAGGER_DROP
		_sprite.skew += sk * STAGGER_LEAN
	# 명멸(알파) + 카운터 가능 시 몸색이 앰버로 맥동(약점 노출 신호). modulate는 HitFlash(material)와 안 겹침.
	var shimmer_a := 1.0   # 실체 보스는 명멸 없음(불투명). 유령만 알파 맥동.
	if def != null and def.ghostly:
		shimmer_a = SHIMMER_MIN_A + (1.0 - SHIMMER_MIN_A) * (0.5 + 0.5 * sin(_life_t * TAU * SHIMMER_HZ))
	if counter_ready:
		var cp := 0.55 + 0.45 * sin(_life_t * TAU * 3.2)
		_sprite.modulate = Color(lerpf(1.0, COUNTER_TINT.r, cp), lerpf(1.0, COUNTER_TINT.g, cp), lerpf(1.0, COUNTER_TINT.b, cp), shimmer_a)
	else:
		_sprite.modulate = Color(1.0, 1.0, 1.0, shimmer_a)
	if _aura != null:
		_aura.visible = true
		_aura.scale = Vector2.ONE * (AURA_BASE_SCALE * (1.0 + AURA_PULSE * sin(_life_t * TAU * AURA_HZ)))
		# 카운터 가능 시 아우라(청록)를 죽여 몸색(앰버) 변화가 드러나게
		_aura.modulate.a = AURA_COLOR.a * (0.3 if counter_ready else 1.0)


# --- 넉백 (2026-08-02) — 계약·주석 정본은 `mob_melee.gd`의 같은 세 함수다 ---
#
# 🔴 **손맛 채널 넷과 안 겹친다**(선언부 주석): 위치=Flinch(스프라이트 로컬) · 스케일=HitStop ·
#   머티리얼=HitFlash · offset/skew=생명감·`counter_stagger`. 층②는 **몸 월드 좌표**라 다섯 번째
#   축이고, 넷 중 어느 것도 안 건드린다.
func _play_flinch() -> void:
	# 방향·세기 동시 소비 — 근거는 `mob_melee._play_flinch` 주석이 정본이다(낡은 방향 차단).
	var dir := _knock_dir if _knock_show_px >= 0.0 else Vector2.ZERO
	if dir.length_squared() <= 0.000001:
		var opp := Flinch.nearest_pos(global_position, get_tree().get_nodes_in_group("player"))
		dir = global_position - opp
	Flinch.play(_sprite, dir, _knock_show_px)
	_knock_show_px = -1.0


# 🔴 **배우가 자기 상태를 안다 — 적용 지점은 이 술어 하나만 본다**(설계 A-12).
#   ⑴ 돌진(CHARGE_DASH)은 `_charge_start`로부터의 **이동 거리**로 종료를 판정하고 매 프레임 스윕을
#      발화한다 — velocity를 덮으면 돌진이 히치하고 스윕 좌표가 어긋난다.
#   ⑵ CHARGE_HIT는 리코일(뒤로 튕김) 감쇠 그 자체가 이동이다.
#   ⑶ `coop_locked`(C1 결박)·`groggy_left`(그로기)는 **AI가 몸을 정지시킨 상태**다 — 여기서 밀면
#      "결박당한 채 미끄러진다"가 된다.
func can_knock() -> bool:
	return not coop_locked and groggy_left <= 0.0 \
		and _state != State.CHARGE_DASH and _state != State.CHARGE_HIT


func apply_knockback(dir: Vector2, push_px: float, show_px: float) -> void:
	if not dir.is_finite() or dir.length_squared() <= 0.000001:
		return
	# 🔴 **사망을 층①보다 먼저 거른다** — `mob_melee.apply_knockback`과 같은 이유·같은 순서
	#   (netreview m-3). `_knock_show_px`는 소비될 때 비워지는 값이라, 죽은 뒤 들어온 확정이
	#   심기만 하고 남으면 다음 피격이 **한 타 전 세기**로 흠칫한다. 보스는 부활하지 않지만
	#   두 배우가 같은 관용구를 갖는 편이 싸다(한쪽만 고치면 다음 사람이 어느 쪽이 옳은지 모른다).
	# ⚠ `push_px <= 0`과 묶지 마라 — 무기 미상은 정상 경로이고 층①은 살아야 한다.
	if _health.is_dead():
		return
	_knock_dir = dir.normalized()
	if is_finite(show_px) and show_px > 0.0:
		_knock_show_px = show_px
	if not is_finite(push_px) or push_px <= 0.0:
		return
	_knock_speed = CombatMath.knock_speed_px_s(push_px)
	_knock_left = CombatMath.knock_time_s(push_px)


func _tick_knock(delta: float) -> void:
	if _knock_left <= 0.0:
		return
	# 🔴 적용 후에 돌진·결박·그로기에 **들어간** 경우까지 막는다 — 게이트가 적용 시점에만 있으면
	#   그 0.05~0.13s 창에서 돌진 velocity를 덮는다(WINDUP → CHARGE_DASH가 그 창 안에 들어온다).
	if not can_knock() or _health.is_dead():
		_knock_left = 0.0
		velocity = Vector2.ZERO
		return
	_knock_left -= delta
	velocity = _knock_dir * _knock_speed
	move_and_slide()
	if _knock_left <= 0.0:
		velocity = Vector2.ZERO


# 카운터 성공 시 외부(랩)가 호출 — 잠깐 꿇는다(_update_life_feel이 offset·skew로 연출). 표시 전용.
func counter_stagger() -> void:
	_stagger_t = STAGGER_DUR


# 격파(활성 룬 파훼) 시 외부(랩)가 호출 — dur초 동안 누워서 무방비(그로기). _update_life_feel이 누운 포즈.
func enter_groggy(dur: float) -> void:
	groggy_left = maxf(groggy_left, dur)


# 전용 시트 클립 임시 재생 — 방향 시트를 잠시 다른 시트로 갈고 end_c1_clip에서 원복.
# _c1_active면 생명감 눕기 포즈를 건너뛰고 이동애니 덮기도 막는다(클립이 곧 포즈). C1 클립·돌진 회전이 공용.
func _play_alt_clip(frames: SpriteFrames, clip: StringName) -> void:
	if frames == null or not frames.has_animation(clip):
		return
	_c1_active = true
	_sprite.rotation = 0.0
	_sprite.offset = Vector2.ZERO
	_anim_scale = 1.0
	if _sprite.sprite_frames != frames:
		_sprite.sprite_frames = frames
	_sprite.play(clip)
	_sprite.speed_scale = 1.0


# C1 코옵 — 미노 전용 클립(roar/grab/groggy, mino_boss_c1 시트). coop_authority가 STELE 중 구동.
func play_c1_clip(clip: StringName) -> void:
	if _c1_frames == null:
		_c1_frames = load("res://assets/sprites/enemies/mino_boss_c1_frames.tres") as SpriteFrames
	_play_alt_clip(_c1_frames, clip)


# 돌진 회전 — 풀캐릭터 회전 시트(mino_spin_full)로 몸통을 통째 갈아끼운다. clip = spin_prep/spin/spin_end.
func play_spin_clip(clip: StringName = &"spin") -> void:
	if _spin_frames == null:
		_spin_frames = load("res://assets/sprites/fx/mino_spin_full_frames.tres") as SpriteFrames
	_play_alt_clip(_spin_frames, clip)


# 바위 충돌·그로기 — 풀캐릭터 hit_fall 시트로 몸통 스왑. clip = hit(충돌 1프레임)/groggy(눕기 루프).
func play_hitfall_clip(clip: StringName) -> void:
	if _hitfall_frames == null:
		_hitfall_frames = load("res://assets/sprites/fx/mino_hit_fall_frames.tres") as SpriteFrames
	_play_alt_clip(_hitfall_frames, clip)
	_hitfall_active = true


# F7 제자리 회오리 — 128px 황금 에너지 시트(mino_whirl). 프레임이 커서 발밑을 오프셋으로 맞춘다.
func play_whirl_clip(clip: StringName) -> void:
	if _whirl_frames == null:
		_whirl_frames = load("res://assets/sprites/fx/mino_whirl_frames.tres") as SpriteFrames
	_play_alt_clip(_whirl_frames, clip)
	_sprite.offset = Vector2(0, WHIRL_OFFSET_Y)


# 돌진 회전 시작 — 풀캐릭터 회전 시트(mino_spin_full)의 spin 클립(루프)로 몸통을 통째 갈아끼운다.
func _start_spin_axe() -> void:
	play_spin_clip(&"spin")


# 돌진 회전 종료 — 방향 시트로 복귀(end_c1_clip이 def.frames 원복 + idle 재생).
func _stop_spin_axe() -> void:
	end_c1_clip()


func end_c1_clip() -> void:
	if not _c1_active:
		return
	_c1_active = false
	_sprite.offset = Vector2.ZERO           # 회오리 발밑 오프셋 원복
	if def != null and def.frames != null:
		_sprite.sprite_frames = def.frames   # 방향 시트 복구
	_play(&"idle", 1.0, true)


# 아우라용 방사 그라디언트(흰→투명) — 가산 블렌드로 발광. 정적 1회 생성(공유).
static var _radial: GradientTexture2D = null


static func _radial_tex() -> GradientTexture2D:
	if _radial == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 128
		t.height = 128
		_radial = t
	return _radial


func _host_ai(delta: float) -> void:
	_state_left -= delta
	# C1 결박 중 — 패턴 AI·이동·자동 늪 전부 정지(c1 클립이 몸을 몬다, 설계 §9). 예고/돌진 서브상태 진행 중이면 먼저 정리 안 함(그런 상태에서 STELE가 겹치지 않게 coop 쪽이 보장).
	if coop_locked:
		velocity = Vector2.ZERO
		return
	# 페이즈2 = 안 때려도 바닥 잠식. 상태 무관하게 주기적으로 늪 생성(솔로면 간격↑, _auto_swamp_interval).
	if _phase == 2:
		_p2_swamp_accum -= delta
		if _p2_swamp_accum <= 0.0:
			_p2_swamp_accum = _auto_swamp_interval()
			_spawn_auto_swamp()
	# 테스트 랩 — debug_hold면 제자리 정지(관찰용). 강제 발동 패턴(WINDUP/RECOVER/돌진 서브상태)은 그대로 진행.
	if debug_hold and _state != State.WINDUP and _state != State.RECOVER \
			and _state != State.CHARGE_DASH and _state != State.CHARGE_HIT:
		velocity = Vector2.ZERO
		return
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
			_face_dir = _dir_suffix(anchor - global_position)
			var dist := global_position.distance_to(anchor)
			if dist > def.aggro_range * LEASH_MULT:
				velocity = Vector2.ZERO
				_state = State.IDLE  # 리시 초과 — 유령 어그로·무한 카이팅 해제
				return
			var pat := _select_pattern(dist)
			if pat != null:
				_begin_windup(pat, anchor)
				return
			# 쓸 패턴 없음 → 이동 (net_anchor 기준, rules §3).
			# keep_distance>0 = 카이팅: 너무 가까우면 물러나고, 유지 거리면 멈추고, 멀면 접근.
			var dir := Vector2.ZERO
			if def.keep_distance > 0.0:
				if dist < def.keep_distance - 12.0:
					dir = (global_position - anchor).normalized()   # 물러남
				elif dist > def.keep_distance + 40.0:
					dir = (anchor - global_position).normalized()   # 접근
			else:
				dir = (anchor - global_position).normalized()       # 추격(기본)
			# 🔴 넉백 중엔 자기 이동을 접는다 — 대체이지 합산이 아니다(A-9). 상태 타이머는 위에서
			#   이미 흘렀으므로 **스턴락이 아니다**(A-10 — 접는 것은 자기 이동뿐이다).
			if _knock_left > 0.0:
				velocity = Vector2.ZERO
			else:
				velocity = dir * def.move_speed * speed_mult
				if dir != Vector2.ZERO:
					move_and_slide()
					_sprite.flip_h = false
		State.WINDUP:
			velocity = Vector2.ZERO   # 공격 애니 중엔 이동 정지 (패턴 애니 하면서 안 움직인다)
			if _state_left <= 0.0:
				# 🔴 돌진은 기본 STRIKE 경로를 안 탄다 — 이동·스윕·분기가 있어 돌진 서브상태로 넘어간다(§3-1).
				if _cur_pattern != null and _cur_pattern.is_charge:
					_enter_charge_dash()
				else:
					_fire_strike()
					if _spin_anim_active:
						play_whirl_clip(&"whirl_burst")  # 느린 회전 끝 → 황금 대폭발→감속→후딜(F7).
					_state = State.RECOVER
					# 회복은 짧게(recover_s) — 재사용 쿨다운(cooldown_s)은 _pattern_last_msec가 따로 막는다.
					# 둘을 분리하지 않으면 슬램 후 쿨다운(4s)만큼 멈춰 서 "빈틈"이 생긴다.
					_state_left = _cur_pattern.recover_s if _cur_pattern != null else 0.5
		State.CHARGE_DASH:
			# 돌진(앞부분 이동) + 회전(총 CHARGE_SPIN_TIME, 2바퀴). 이동거리 도달하면 제자리 회전 지속.
			# 바위에 박으면 HIT(그로기·회전 멈춤), 아니면 회전 끝나고 RECOVER.
			var traveled := _charge_start.distance_to(global_position)
			if traveled < _cur_pattern.charge_travel_max:
				velocity = Vector2.RIGHT.rotated(_strike_angle) * _cur_pattern.charge_speed * speed_mult
			else:
				velocity = Vector2.ZERO   # 도달 — 제자리에서 회전만
			move_and_slide()
			if Net.is_host():
				EventBus.boss_sweep.emit(global_position, _strike_angle, _cur_pattern, _charge_seq)
			var rock: Node = _dash_rock_collision()
			if rock != null:
				_enter_charge_hit(rock)              # 🪨 바위 박음 → 회전 멈춤 + 그로기 처벌창
			elif _state_left <= 0.0:
				velocity = Vector2.ZERO               # 회전 끝 → 후딜
				_stop_spin_axe()                      # 풍차 도끼 숨김
				_state = State.RECOVER
				_state_left = _cur_pattern.recover_s
		State.CHARGE_HIT:
			# 리코일(뒤로 튕김) 감쇠 → 끝나면 그로기(무방비 처벌창). 눕는 포즈는 _update_life_feel이 처리.
			velocity = velocity.lerp(Vector2.ZERO, minf(1.0, delta * 8.0))
			move_and_slide()
			if _state_left <= 0.0:
				enter_groggy(_cur_pattern.groggy_s)
				play_hitfall_clip(&"groggy")          # 눕기 그로기 루프(별 뜨고 무방비)
				_state = State.RECOVER
				_state_left = _cur_pattern.groggy_s
		State.RECOVER:
			velocity = Vector2.ZERO   # 후딜에도 정지 유지 (스윙 마무리 프레임 동안 안 미끄러진다)
			if _state_left <= 0.0:
				if _spin_anim_active:
					_spin_anim_active = false
					end_c1_clip()      # F7 제자리 회오리 끝 → 방향 시트 복귀
				_state = State.CHASE


# 패턴 선택기 — (a) min_phase ≤ 현재 페이즈 (b) 대상 거리 ∈ [use_min_dist, use_max_dist]
# (c) 쿨다운 경과, 를 만족하는 후보 중 **priority 높은 것** 우선(거리별 역할 분리 — 가까이=평타·중간=슬램·
# 멀리=물뿌리기). 동률이면 range 작은 것. 결정적 선택 — 랜덤 없음.
func _select_pattern(dist: float) -> BossPatternDef:
	if debug_hold:
		return null  # 테스트 랩 — 자동 발동 금지 (패턴 버튼으로만)
	var now := Time.get_ticks_msec()
	var best: BossPatternDef = null
	for p: BossPatternDef in def.patterns:
		if p == null or p.min_phase > _phase:
			continue
		if dist < p.use_min_dist or dist > p.use_max_dist:
			continue
		var last := int(_pattern_last_msec.get(p.id, -1000000000))
		if now - last < int(p.cooldown_s * 1000.0):
			continue
		if best == null or p.priority > best.priority \
				or (p.priority == best.priority and p.range < best.range):
			best = p
	return best


# 테스트 랩 전용 — 특정 패턴 id를 즉시 강제 발동(쿨다운·거리·debug_hold 무시). 호스트만.
# 실제 실행 경로(_begin_windup)를 그대로 타므로 예고·타격·FX가 진짜와 동일하다.
func debug_force_pattern(pid: String) -> void:
	if not Net.is_host() or _health.is_dead():
		return
	var t := _nearest_alive_player()
	var anchor := t.net_anchor() if t != null else global_position + Vector2(0, 80)
	_face_dir = _dir_suffix(anchor - global_position)   # 강제 발동도 플레이어 바라보게
	for p: BossPatternDef in def.patterns:
		if p != null and p.id == pid:
			_telegraph_left = 0.0
			_begin_windup(p, anchor)
			return


# WINDUP 진입 — 판정 중심/각 확정 + 텔레그래프 표시 + 호스트 예고 브로드캐스트.
func _begin_windup(pat: BossPatternDef, anchor: Vector2) -> void:
	_cur_pattern = pat
	_state = State.WINDUP
	# 지연 보상(§3, 잔몹 mob_melee와 같은 규약): 예고가 게스트 화면에 뜨기까지 편도 지연만큼 늦으므로
	# 타격도 그만큼 늦춘다 → 게스트도 온전한 telegraph_s를 갖는다. 이 경로는 호스트 전용(보스 AI).
	_telegraph_hold_s = pat.telegraph_s + CombatMath.strike_delay_s(Net.max_remote_one_way_ms())
	_state_left = _telegraph_hold_s
	velocity = Vector2.ZERO
	_strike_angle = (anchor - global_position).angle()  # 대상 방향
	_strike_centers = []
	_sprite.flip_h = false   # 8/4방향 시트는 방향이 구워져 있음(미러 포함) — flip 미사용(디렉셔널 애니가 처리)
	if pat.burst_count > 1:
		# 물뿌리기 — N개 원 착탄. 호스트가 착탄점 확정 → boss_spray로 게스트 표시 중계(G_BOSS_SPRAY).
		# 개수는 솔로면 party_scale로 감소. 애니·N개 원 텔레그래프는 _on_boss_spray가 그린다(호스트/게스트 공용).
		var count := maxi(1, int(CombatMath.party_scale(float(pat.burst_count), _party_size())))
		_strike_centers = _scatter_centers(anchor, pat.burst_spread, count)
		_telegraph.visible = false  # 단일 텔레그래프 숨김 — 렌더러가 N개 원을 대신 그린다
		_telegraph_left = 0.0
		if Net.is_host():
			EventBus.boss_spray.emit(eid, pat.id, _strike_centers, _strike_angle)
		return
	if pat.shape == "cone" or pat.center_self:
		# 부채꼴 apex = 보스 위치 · 도끼 회전(center_self) 원 중심 = 보스 자신(전방위 근접)
		_strike_center = global_position
	else:
		# 원: 대상 net_anchor 고정 — 예고를 보고 빠져나갈 수 있게 (GDD §5 기믹 원칙)
		_strike_center = anchor
	_show_telegraph_visual(pat, _strike_center, _strike_angle)
	if pat.is_charge:
		# 돌진 예비 자세 — 회전 시트(mino_spin_full)의 spin_prep(도끼 치켜듦→웅크림)을 예고 동안 재생.
		# 예고(좁은 cone)는 "경로 예고(긁힘 선)"로 이미 _show_telegraph_visual이 그렸다.
		play_spin_clip(&"spin_prep")
	elif pat.id == "spin":
		# F7 제자리 회오리 — 예고 동안 황금 링이 천천히 여러 바퀴(whirl_spin 루프 6fps). 타격 순간 폭발(STRIKE 분기).
		play_whirl_clip(&"whirl_spin")
		_spin_anim_active = true
	else:
		_play_attack_anim(pat)  # 공격 애니(swing/slam) — 예고 길이에 맞춰 재생 속도를 늘린다
	if Net.is_host():
		# MobSync가 G_BOSS_ATK로 브로드캐스트 → 게스트 표시. 판정은 절대 여기서 안 한다.
		EventBus.boss_telegraph.emit(eid, pat.id, _strike_center, _strike_angle)


# STRIKE 순간 — 호스트만 판정 요청/늪 생성. 판정은 CombatAuthority(boss_strike 구독).
func _fire_strike() -> void:
	if not Net.is_host() or _cur_pattern == null:
		return
	_pattern_last_msec[_cur_pattern.id] = Time.get_ticks_msec()  # 쿨다운 게이트(호스트 전용)
	if not _strike_centers.is_empty():
		# 물뿌리기 — 착탄점마다 원 판정(기존 boss_strike 재사용, is_strike_hit N회). 겹침 중복 데미지는
		# CombatAuthority가 같은 STRIKE(물리 프레임)에서 플레이어당 1회로 dedup (rules §3 판정은 호스트).
		for c: Variant in _strike_centers:
			EventBus.boss_strike.emit(c as Vector2, 0.0, _cur_pattern)
	else:
		EventBus.boss_strike.emit(_strike_center, _strike_angle, _cur_pattern)
	if _cur_pattern.creates_swamp:
		_swamp_seq += 1
		var sid := "%s:swamp:%d" % [eid, _swamp_seq]
		# 호스트는 자기 G_SWAMP를 릴레이로 못 받으므로 로컬 스폰 (drop_spawn_local 미러).
		# 구독자 = SwampField. 튜플 = [sid, x, y, r, ttl, slow] (net_schema G_SWAMP "sw" 미러).
		EventBus.swamp_spawn_local.emit(
			[[sid, _strike_center.x, _strike_center.y,
			def.swamp_radius, def.swamp_ttl, def.swamp_slow_factor]])
	# 낙석(P4) — 착탄점마다 바위 지형이 남는다(돌진 유도). RockField가 로컬 스폰 + G_ROCK 브로드캐스트(늪 미러).
	# 데미지는 위 boss_strike가 이미 냈다 — 바위는 판정 없는 지형일 뿐. 착탄점 = _strike_centers(spray N점).
	if _cur_pattern.leaves_rock and not _strike_centers.is_empty():
		var rocks: Array = []
		for c: Variant in _strike_centers:
			_rock_seq += 1
			var cv := c as Vector2
			rocks.append(["%s:rock:%d" % [eid, _rock_seq], cv.x, cv.y,
				_cur_pattern.rock_radius, _cur_pattern.rock_ttl])
		EventBus.rock_spawn_local.emit(rocks)


# --- 돌진(P3) 서브상태 진입/충돌 (minotaur_patterns.md §3-1) ---

# 돌진 진입 — WINDUP 종료 후 호출. 예고를 끄고 고정 방향(_strike_angle, WINDUP에서 대상 방향으로 확정)으로 질주.
func _enter_charge_dash() -> void:
	_telegraph.visible = false
	_telegraph_left = 0.0
	_charge_seq += 1                       # 스윕 dedup 회차 갱신 (CombatAuthority._boss_sweep_seq와 짝 — 돌진당 1회)
	_charge_start = global_position
	_state_left = CHARGE_SPIN_TIME         # 돌진+회전 총 지속(이동은 앞부분, 도달 후 제자리 회전). _host_ai가 감산.
	_state = State.CHARGE_DASH
	_start_spin_axe()                      # 회전 시트(mino_spin_full) spin 클립으로 몸통 통째 스왑


# 바위 충돌 — 리코일로 뒤로 튕기고 CHARGE_HIT 진입. 바위가 shatter를 구현했으면 부순다(P4 오브젝트 계약).
func _enter_charge_hit(rock: Node) -> void:
	_state = State.CHARGE_HIT
	_state_left = CHARGE_HIT_DUR
	play_hitfall_clip(&"hit")              # 🔴 바위 박음 = 회전 중단 + 충돌 프레임(이후 groggy 눕기 클립)
	var away := global_position - (rock as Node2D).global_position
	var dir := away.normalized() if away.length_squared() > 1.0 else -Vector2.RIGHT.rotated(_strike_angle)
	velocity = dir * CHARGE_RECOIL_SPEED
	if rock.has_method("shatter"):
		rock.call("shatter")               # 바위 산산조각 (없으면 그냥 남는다 — 헤드리스 디버그 바위엔 없음)


# 돌진 중 슬라이드 충돌에서 "boss_rock" 그룹만 골라 반환. 벽(아레나 경계)은 무시 → 헛참으로 처리. 없으면 null.
func _dash_rock_collision() -> Node:
	for i in get_slide_collision_count():
		var c: Object = get_slide_collision(i).get_collider()
		if c is Node and (c as Node).is_in_group("boss_rock"):
			return c as Node
	return null


# 나 포함 파티 인원 — 호스트/게스트 동일 계산(peer_ids는 자기 제외라 +1). party_scale 표시 일치의 근거.
func _party_size() -> int:
	return Net.peer_ids.size() + 1


# 페이즈2 자동 늪 간격 — 솔로면 덜 자주(간격↑). party_scale(1,solo)=solo_factor<1 → 나눠서 간격을 늘린다.
func _auto_swamp_interval() -> float:
	return def.swamp_auto_interval_p2 / CombatMath.party_scale(1.0, _party_size())


# 페이즈2 자동 늪(호스트 전용) — 안 때려도 바닥 잠식. 위치 = 랜덤 생존 플레이어 근처(없으면 보스 주변).
# swamp_spawn_local = 슬램과 동일 경로(SwampField 로컬 스폰 + G_SWAMP 브로드캐스트, sid 시퀀스 재사용).
func _spawn_auto_swamp() -> void:
	var target := _nearest_alive_player()
	var center := target.net_anchor() if target != null else global_position
	center += Vector2(randf_range(-24.0, 24.0), randf_range(-24.0, 24.0))
	_swamp_seq += 1
	var sid := "%s:swamp:%d" % [eid, _swamp_seq]
	EventBus.swamp_spawn_local.emit(
		[[sid, center.x, center.y, def.swamp_radius, def.swamp_ttl, def.swamp_slow_factor]])


# 물뿌리기 착탄점 산개(호스트 확정) — 대상 주변 spread 반경 원판 안 N개. 첫 발은 대상 위(확실한 압박),
# 나머지는 균일 랜덤 분포. 씬 전용 글루라 randf 무관(-s 아님) — 호스트가 계산해 boss_spray로 그대로 중계.
func _scatter_centers(anchor: Vector2, spread: float, count: int) -> Array:
	var centers: Array = []
	for i in count:
		if i == 0:
			centers.append(anchor)
			continue
		var ang := randf() * TAU
		var dist := sqrt(randf()) * spread  # sqrt = 균일 원판 분포 (중심 몰림 방지)
		centers.append(anchor + Vector2(cos(ang), sin(ang)) * dist)
	return centers


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


# --- MobSync용 API (호스트 송신 배치 / 게스트 수신 반영) — mob_melee와 동일 규약 ---

func get_sync_state() -> Array:
	return [eid, global_position.x, global_position.y, _sprite.flip_h]


func apply_remote_pos(pos: Vector2, flip: bool) -> void:
	_remote_target = pos
	_remote_flip = flip


# --- 게스트 표시 API (G_BOSS_ATK 수신 → MobSync가 호출). 판정은 절대 없다(mob_melee matk 표시 미러). ---

func show_boss_telegraph(pattern_id: String, center: Vector2, angle: float) -> void:
	var pat := _resolve_pattern(pattern_id)
	if pat == null:
		return  # 모르는 패턴 id = 무시
	_show_telegraph_visual(pat, center, angle)
	_play_attack_anim(pat)  # 공격 애니 재생 (게스트는 자기 pat.telegraph_s 길이에 맞춘다)


# 물뿌리기 N개 원 텔레그래프 + 애니 (표시 전용, 판정 절대 없음 — 그건 CombatAuthority). 호스트/게스트 공용:
# 호스트=_begin_windup의 boss_spray emit, 게스트=MobSync가 G_BOSS_SPRAY 수신 후 emit. 각자 로컬 렌더.
func _on_boss_spray(spray_eid: String, pattern_id: String, centers: Array, _angle: float) -> void:
	if spray_eid != eid:
		return  # 다른 보스(다중 보스 확장 대비) — 무시
	var pat := _resolve_pattern(pattern_id)
	if pat == null:
		return  # 모르는 패턴 id
	_play_attack_anim(pat)  # 물뿌리기 애니
	for c: Variant in centers:
		_spawn_spray_circle(pat, c as Vector2)


# 착탄점 하나에 원형 텔레그래프 스프라이트 스폰 후 telegraph_s 뒤 자동 free. 단일 Telegraph 노드로는
# N개를 못 그리므로 착탄점마다 별도 스프라이트 (기하는 _apply_telegraph_geometry 공용 — 단일 원과 같은 식).
func _spawn_spray_circle(pat: BossPatternDef, center: Vector2) -> void:
	var spr := Sprite2D.new()
	spr.z_index = -1  # 바닥(-10) 위, 몸/무기(0+) 아래 — 가려지지 않게 (rules §5)
	_apply_telegraph_geometry(spr, pat, 0.0)
	get_parent().add_child(spr)  # 스테이지 Node2D 자식 (런타임 add_child — _ready 함정 무관, rules §5)
	spr.global_position = center
	# 표시 지속 = 호스트는 지연 보상분 포함(_begin_windup 확정), 게스트는 자기 telegraph_s (단일 원과 같은 규약)
	var dur := _telegraph_duration(pat)
	get_tree().create_timer(dur).timeout.connect(
		func() -> void:
			if is_instance_valid(spr):
				spr.queue_free())
	# 차오름 — 🔴 **분모가 위 자동 free 타이머와 문자 그대로 같은 값**이라 "다 찼다 = 사라진다 =
	# 맞는다"가 세 축에서 동시에 성립한다(§3 `_telegraph_duration` 파생값). 단일 원은
	# `_telegraph_left`를 매 프레임 감산해 만들지만 N개 원은 노드가 여럿이라 각자 트윈으로 돈다 —
	# 시간 소스는 둘 다 벽시계이고 분모가 같으므로 갈라질 축이 없다.
	# ⚠ 트윈을 `spr`에 묶어 두면 스프라이트가 free될 때 같이 죽는다(고아 트윈 없음).
	var spray_mat := spr.material as ShaderMaterial
	if spray_mat != null and dur > 0.0:
		spr.create_tween().tween_method(
			func(v: float) -> void: spray_mat.set_shader_parameter(&"progress", v),
			0.0, 1.0, dur)


func _resolve_pattern(pattern_id: String) -> BossPatternDef:
	if def == null:
		return null
	for p: BossPatternDef in def.patterns:
		if p != null and p.id == pattern_id:
			return p
	return null


# 이번 회차의 예고 지속(초) — 단일 소스. 호스트는 _begin_windup이 지연 보상분을 더해 확정하고
# (_telegraph_hold_s), 게스트는 그 값이 0이라 자기 pat.telegraph_s를 쓴다(§3 지연 보상).
# 🔴 예고 표시 지속(단일/N개 원)과 공격 애니 길이가 **전부 이 함수에서 파생돼야** 예고와 동작이
# 같은 순간에 끝난다 — 식을 복제하면 다음 튜닝에서 표시와 모션이 갈라진다.
func _telegraph_duration(pat: BossPatternDef) -> float:
	return _telegraph_hold_s if _telegraph_hold_s > 0.0 else pat.telegraph_s


# 예고를 월드에 못 박는다 — "예고는 뜬 자리에 그대로 있다"가 회피의 전제다(§3 "맞는 곳=보이는 곳"이
# 시간축으로 확장된 것). 🔴 **`_physics_process`의 맨 끝에서만 불러라** (호출부 주석 참조).
# ⚠ 물뿌리기 N개 원은 이 함수와 무관하다 — 스테이지 자식으로 스폰돼 애초에 보스를 안 따라간다.
func _reassert_telegraph_pos() -> void:
	if _telegraph_left > 0.0:
		_telegraph.global_position = _telegraph_center


# 차오름(임박도)을 셰이더에 심는다 — "언제 터지는지가 눈에 보인다".
# 🔴 **분모는 `_telegraph_duration()`이 확정한 `_telegraph_total_s` 하나다** (§3). 각 클라가 **자기**
#   예고 창으로 리졸브한 값이라(호스트 = 지연 보상분 포함 · 게스트 = 자기 telegraph_s) 지연이 있어도
#   양쪽 화면에서 "다 찼다 = 지금 맞는다"가 동시에 성립한다.
# 🔴 **`TIME`에서 유도하지 마라** — 예고 창 길이가 클라마다 달라 게스트가 틀린 임박 신호를 읽는다
#   (셰이더 `progress` 주석이 정본, netreview 2026-07-27 계약).
# ⚠ 판정 형태는 안 건드린다 — 셰이더는 이 값으로 **색만** 바꾼다(부채꼴/원은 range·half_angle 그대로).
func _update_telegraph_progress() -> void:
	if _telegraph_mat == null or _telegraph_total_s <= 0.0:
		return
	_telegraph_mat.set_shader_parameter(
		&"progress", clampf(1.0 - _telegraph_left / _telegraph_total_s, 0.0, 1.0))


# 예고 스프라이트의 쿼드 소스 — 1×1 흰 텍스처 한 장을 모든 예고가 공유한다(단일 콘/원 + N개 원).
# 🔴 기하를 셰이더가 그리므로 텍스처는 "크기"만 준다. 1×1이면 **scale이 곧 월드 한 변**이라
# 텍스처 해상도·종횡비가 판정 정합에 끼어들 여지가 아예 없다 — 옛 결함(텍스처에 각이 박혀 데이터와
# 갈라짐)의 근본 원인 제거다. 셰이더가 이 텍스처를 곱하므로 흰색 = 정확한 항등이다.
# ⚠ **무늬를 얹으려면 코드 변경이 선행된다** — 갈아끼울 데이터 자리는 없다(`telegraph_tex` 필드는
# 2026-07-27에 제거됐다). 아트가 **정사각 풀블리드(알파 1)** 패턴을 주면 이 함수를 그 텍스처
# preload로 바꾸거나 새 필드를 판다. 🔴 **형태를 그린 텍스처는 안 된다** — 알파가 셰이더 형태를
# 다시 잘라 정합이 깨진다(그게 방금 없앤 결함이다). 형태는 언제나 코드가 정한다.
static var _quad_tex: ImageTexture = null


static func _telegraph_quad_tex() -> ImageTexture:
	if _quad_tex == null:
		# 🔴 2×2(1×1 아님) — 1×1은 centered 오프셋이 -0.5px 서브픽셀이라, 거대 scale(~226)을 곱하면
		#   그 반올림 오차가 half-quad(~113px)만큼 통째로 어긋난다(콘 apex가 회전 방향으로 -123px 튐,
		#   실측 2026-07-31). 2×2면 centered 오프셋 = -1px 정수라 scale과 정확히 맞물려 중심에 앉는다.
		#   UV는 텍스처 크기와 무관하게 0..1이라 셰이더 p=(UV-0.5)*quad_px는 그대로다(scale만 절반).
		var img := Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_quad_tex = ImageTexture.create_from_image(img)
	return _quad_tex


# 🔴 판정 기하를 화면으로 넘기는 **유일한 지점** — "맞는 곳 = 보이는 곳" (§3).
#   원(circle)   = 중심 기준 반지름 pat.range           ≡ CombatMath.is_strike_hit
#   부채꼴(cone) = apex 기준 반지름 pat.range ∩ 전체각 2*pat.half_angle ≡ CombatMath.is_hit_in_cone
# 규약: 노드 원점 = 원 중심 / apex, 노드 회전 = facing, **균일** scale = quad/2(2×2 쿼드 → 월드 한 변 quad).
#   ⚠ 텍스처는 **2×2**다(1×1 아님) — 1×1 centered 오프셋 -0.5px가 거대 scale에 곱해져 half-quad 어긋난다.
#   셰이더는 로컬 프레임(facing = +x = 각 0)에서 판정식을 그대로 계산한다. 회전+균일스케일은
#   닮음변환이라 각·거리비가 보존된다 — 세로만 늘리는 비균일 스케일은 정원을 타원으로 만들어
#   다시 어긋나므로 절대 넣지 마라(rules §3 콘 계약이 두 번 기각한 우회로).
# ⚠ 모든 uniform을 매번 심는다(기본값 의존 금지) — Telegraph 노드는 재사용돼 콘/원을 오가므로
#   한 번이라도 안 심으면 이전 패턴의 각·반지름이 남는다.
func _apply_telegraph_geometry(spr: Sprite2D, pat: BossPatternDef, angle: float) -> void:
	var is_cone := pat.shape == "cone"
	var radius := maxf(pat.range, 0.0)
	spr.texture = _telegraph_quad_tex()
	spr.centered = true
	spr.offset = Vector2.ZERO
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.rotation = angle if is_cone else 0.0  # 원은 회전 불변 — 회전을 넣어도 그림이 같다
	# 쿼드 한 변 = (반지름 + 소프트 폭 + 화면픽셀 마진)의 2배.
	# 🔴 딱 지름으로 두면 원호의 상하좌우 끝에서 화면 픽셀 중심이 쿼드 밖으로 나가 그 픽셀이 아예
	#   안 그려진다(= 판정 안인데 무예고). 여유는 표시용일 뿐 판정 기하가 아니다 — 셰이더는
	#   radius_px로만 안팎을 가른다.
	# ⚠ **유도식을 격자 스냅 폐기에 맞춰 다시 세웠다**(2026-08-02): 옛 여유 `pixel_px + edge_bias_px`
	#   (= 2.0 + 1.41)는 격자 셀 크기와 그 반대각선에서 나온 값이라 격자가 없어지면 근거가 없다.
	#   새 항 둘은 각각 ⑴ 알파 램프가 바깥으로 퍼지는 폭(`aa_px`) ⑵ 프래그먼트가 픽셀 **중심**에서만
	#   생기는 데서 오는 화면 반픽셀(줌 1.5에서 0.33 월드px)이고, 후자를 1.0으로 넉넉히 잡았다.
	var quad := 2.0 * (radius + TELEGRAPH_AA_PX + TELEGRAPH_QUAD_MARGIN_PX)
	# 텍스처가 2×2라 월드 한 변 = 2*scale → scale = quad/2. quad_px(월드 span)은 quad 그대로 넘긴다.
	spr.scale = Vector2.ONE * (quad * 0.5)
	var mat := spr.material as ShaderMaterial
	if mat == null or mat.shader != TELEGRAPH_SHADER:
		mat = ShaderMaterial.new()
		mat.shader = TELEGRAPH_SHADER
		spr.material = mat
	mat.set_shader_parameter(&"quad_px", quad)
	mat.set_shader_parameter(&"radius_px", radius)
	# 원 = 각 제한 없음. PI를 넘기면 셰이더가 각 검사를 통째로 건너뛴다(is_strike_hit와 항등).
	mat.set_shader_parameter(&"half_angle", pat.half_angle if is_cone else PI)
	mat.set_shader_parameter(&"aa_px", TELEGRAPH_AA_PX)
	mat.set_shader_parameter(&"border_px", TELEGRAPH_BORDER_PX)
	mat.set_shader_parameter(&"fill_color", TELEGRAPH_FILL)
	mat.set_shader_parameter(&"border_color", TELEGRAPH_BORDER)
	mat.set_shader_parameter(&"fill_fade", TELEGRAPH_FILL_FADE)
	mat.set_shader_parameter(&"pulse_amp", TELEGRAPH_PULSE_AMP)
	mat.set_shader_parameter(&"pulse_hz", TELEGRAPH_PULSE_HZ)
	# 차오름 — 🔴 여기서 **0으로 되심는 것이 계약의 일부다**. Telegraph 노드는 재사용되므로 안 심으면
	# 다음 예고가 **이전 회차의 다 찬 상태로 시작**한다(에러 없음, 임박 신호만 거짓).
	mat.set_shader_parameter(&"progress", 0.0)
	mat.set_shader_parameter(&"charge_color", TELEGRAPH_CHARGE)
	mat.set_shader_parameter(&"lead_px", TELEGRAPH_LEAD_PX)
	mat.set_shader_parameter(&"flash_color", TELEGRAPH_FLASH)
	mat.set_shader_parameter(&"flash_start", TELEGRAPH_FLASH_START)


# 텔레그래프 표시 — 판정 기하(range·half_angle·angle)를 셰이더에 그대로 넘긴다. "맞는 곳=보이는 곳" (§3).
# 🔴 **표시를 건너뛰는 분기는 없다.** 옛 `telegraph_tex == null` 게이트("아트 대기 = 표시 생략, 판정은
# 정상 진행")는 2026-07-27에 필드째 제거했다 — 셰이더가 텍스처 없이 그리게 된 뒤로 그 게이트는
# "데이터 한 칸을 비우면 예고가 통째로 안 보이는데 판정은 난다"(= 무예고 피격 100%)로만 남았다.
# 이 전환이 없애려던 결함 클래스 그 자체라 게이트를 두는 것이 곧 위험이었다.
func _show_telegraph_visual(pat: BossPatternDef, center: Vector2, angle: float) -> void:
	if def != null and not def.show_telegraph:
		_telegraph.visible = false   # 예고 원 숨김 (윈드업 타이밍은 _state_left가 따로 잡음)
		return
	_apply_telegraph_geometry(_telegraph, pat, angle)
	_telegraph_center = center     # 매 프레임 재주장할 목표 (부모에 끌려가지 않게 — 선언부 주석)
	_telegraph.global_position = center
	_telegraph.visible = true
	# 호스트는 지연 보상분이 더해진 시간(_begin_windup에서 확정), 게스트는 자기 telegraph_s.
	# 게스트가 편도 지연만큼 늦게 시작하고 호스트가 그만큼 늦게 때리므로 양쪽 예고가 같은 순간에 끝난다.
	_telegraph_total_s = _telegraph_duration(pat)   # 차오름 분모 = 표시 지속과 **같은 값**(§3)
	_telegraph_left = _telegraph_total_s
	_telegraph_mat = _telegraph.material as ShaderMaterial


# --- 애니 표시 경로 (호스트/게스트 공용 — 판정과 무관) ---

# 애니 재생. 🔴 speed_scale은 **노드 전역**이라 공격 애니에서 늘려둔 배율이 idle/walk/death에 남으면
# 다음 애니가 느려진 채 굳는다(에러 없음). 진입 경로가 여럿(_ready·_on_hp_changed 2곳·_begin_windup·
# show_boss_telegraph·_on_boss_spray·_update_move_anim)이라 호출부마다 손으로 맞추면 다음 사람이
# 빠뜨리므로, **복귀를 이 한 곳으로 모은다** — 기본 인자 1.0이 곧 복귀다(공격 애니만 값을 넘긴다).
#
# 🔴 force_restart = "같은 애니여도 처음부터". 평소 가드(`animation != anim`)는 매 프레임 오는
# _play(&"idle")이 애니를 리스타트하지 않게 막는 것인데, **공격 애니에는 그 가드가 독이다**:
# animation이 이미 그 패턴 이름으로 남아 있으면 재생이 시작되지 않아 예고 내내 이전 스윙의 마지막
# 프레임으로 얼어 있는다(에러 없음). 시트에 walk가 없는 보스에서 실제로 도달 가능하다 —
# 공격 애니가 예고를 꽉 채우게 된 뒤로는 중간에 idle/walk가 끼어들어 이름을 갈아주는 것에
# 기댈 수 없다(RECOVER의 idle·CHASE의 walk 둘뿐이고, walk가 없는 시트는 early return한다).
# 4방향(대각선만) 접미사 — 부호로 se/sw/nw/ne. 가로선(dy=0)은 '앞(아래)'으로 편향해서
# 서/동쪽 플레이어에 등(NW/NE) 대신 앞(SW/SE)을 보게 한다. 뒤 대각선은 플레이어가 위에 있을 때만.
func _dir_suffix(v: Vector2) -> String:
	if v.length_squared() < 1.0:
		return _face_dir
	# 8방향 — 부채꼴(연속 각)과 스프라이트 방향을 맞추려 45° 구간으로 스냅(4대각선만 쓰면 정동/정서에서
	# 크게 어긋난다). Godot 각: 0=E, +y=아래(S). 시트에 idle/slam _e/se/s/sw/w/nw/n/ne 8종 모두 있다.
	var idx := int(round(v.angle() / (PI / 4.0))) % 8
	if idx < 0:
		idx += 8
	return ["e", "se", "s", "sw", "w", "nw", "n", "ne"][idx]


# idle/slam/swing/spray는 방향별 변형(_<dir>)이 있으면 그걸로, 없으면 base 그대로 (단방향 보스 폴백).
func _resolve_dir_anim(anim: StringName) -> StringName:
	var s := String(anim)
	if s == "idle" or s == "slam" or s == "swing" or s == "spray" or s == "spin":
		var d := StringName(s + "_" + _face_dir)
		if _has_anim(d):
			return d
		if s == "swing" or s == "spray" or s == "spin":   # 방향 전용 공격 애니가 없으면 slam_<dir> 재사용(오픈소스 플레이스홀더, 나중 API로 교체)
			var sd := StringName("slam_" + _face_dir)
			if _has_anim(sd):
				return sd
	elif s == "walk":
		var wd := StringName("walk_" + _face_dir)   # 방향 walk 있으면 그걸로
		if _has_anim(wd):
			return wd
		var idle_d := StringName("idle_" + _face_dir)   # 없으면 방향 idle(플레이어 바라보기) — 이동 중에도 안 등짐
		if _has_anim(idle_d):
			return idle_d
	return anim


func _play(anim: StringName, speed_scale: float = 1.0, force_restart: bool = false) -> void:
	anim = _resolve_dir_anim(anim)
	if not _has_anim(anim):
		return  # 없는 애니는 갈아타지 않으므로 배율도 그대로 둔다(현재 애니의 배율이 계속 맞다)
	_anim_scale = maxf(speed_scale, MIN_ANIM_SPEED_SCALE)
	if force_restart or _sprite.animation != anim:
		_sprite.play(anim)
	if force_restart:
		# 🔴 play()에만 기대지 않는다: 4.7 실측으로 play()는 **끝나 멈춘** 같은 애니를 프레임 0으로
		# 되돌리지만, **재생 중인** 같은 애니는 이어서 돈다(그러면 그 회차만 애니가 일찍 끝난다).
		# 지금은 패턴 cooldown_s가 그 경우를 막고 있을 뿐이라 데이터에 기댄 안전이다 — 명시로 못 박는다.
		_sprite.set_frame_and_progress(0, 0.0)
	_apply_anim_scale()


# 원하는 배율을 스프라이트에 심는다 — 유일한 speed_scale 대입 지점.
# ⚠ 히트스톱(src/feel/hit_stop.gd)이 맞은 스프라이트의 speed_scale을 55ms간 0으로 세우고 **무조건
# 1.0으로** 되돌린다. 그래서 ⑴ 정지(0.0) 중에는 건드리지 않고(덮으면 히트스톱이 사라진다) ⑵ 매
# 물리 프레임 다시 심는다 — 예고 중 보스를 때리면(= 거의 항상) 늘려둔 배율이 1.0으로 날아가
# 공격 애니가 다시 일찍 끝나기 때문이다(에러 없음, 화면만 어긋난다).
# ⚠ **그래서 "애니 종료 = 타격 순간"은 근사만 성립한다** — 전투 중엔 히트스톱 정지분이 누적된다
# (피격 1회당 약 −44ms. 2인이 1.2s 예고 동안 6타면 약 0.26s 늦게 끝난다). 정지 자체가 "때린 맛"이라
# 의도된 것이고, 없애려면 매 프레임 `남은 애니분 / 남은 예고시간`으로 배율을 재유도해야 하는데
# 그러면 피격마다 배속이 눈에 띄게 튄다 — **수락한 부채다**(고치려 하지 마라, 리뷰 판단 2026-07-26).
func _apply_anim_scale() -> void:
	if _sprite.speed_scale <= 0.0:
		return
	if not is_equal_approx(_sprite.speed_scale, _anim_scale):
		_sprite.speed_scale = _anim_scale


# 공격 애니 재생 — 총 재생 길이를 그 회차 예고 길이(_telegraph_duration)에 맞춘다.
# 🔴 데이터(.tres speed)로는 원리적으로 못 맞춘다: 호스트의 예고 길이는 지연 보상분
# (CombatMath.strike_delay_s)이 더해져 **RTT에 따라 가변**이라, 애니를 telegraph_s에 정확히 맞춰
# 놔도 호스트에선 그 차이만큼 계속 어긋난다. 그래서 매 회차 speed_scale로 늘린다.
# (§3 "애니 길이 ≈ telegraph_s" 미러 — 안 맞으면 보스가 휘두름을 마치고 idle 자세로 서 있다가 때린다.)
func _play_attack_anim(pat: BossPatternDef) -> void:
	var anim := StringName(pat.id)
	# force_restart = true — 같은 패턴이 연속으로 와도 반드시 처음부터 (위 _play 주석의 "얼음" 방지)
	_play(anim, _attack_speed_scale(anim, _telegraph_duration(pat)), true)


# 목표 길이에 맞춘 speed_scale = 기본 길이 / 목표 길이. 못 구하는 경우(애니 없음·프레임 0·speed 0·
# 목표 ≤ 0)는 1.0 = 항등 폴백(옛 동작).
func _attack_speed_scale(anim: StringName, target_s: float) -> float:
	var base := _anim_base_length(anim)
	if base <= 0.0 or target_s <= 0.0:
		return 1.0
	return base / target_s


# 애니 기본 재생 길이(초) = Σ프레임 duration / 애니 speed.
# ⚠ 프레임 수·speed를 코드에 박지 않는다 — sprite_frames에서 읽으므로 아트가 프레임을 늘리거나
# speed를 바꿔도 이 계산이 자동으로 따라간다. duration도 프레임별로 다를 수 있어 개수로 가정하지 않고 합산.
func _anim_base_length(anim: StringName) -> float:
	var sf := _sprite.sprite_frames
	if sf == null or not sf.has_animation(anim):
		return 0.0
	var speed := sf.get_animation_speed(anim)
	var count := sf.get_frame_count(anim)
	if speed <= 0.0 or count <= 0:
		return 0.0
	var total := 0.0
	for i in count:
		total += sf.get_frame_duration(anim, i)
	return total / speed


func _has_anim(anim: StringName) -> bool:
	return _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation(anim)


func _is_attack_anim_playing() -> bool:
	if not _sprite.is_playing():
		return false
	var s := String(_sprite.animation)
	for a: StringName in ATTACK_ANIMS:
		if s == String(a) or s.begins_with(String(a) + "_"):  # slam_e 등 방향 변형 포함
			return true
	return false


func _update_move_anim(moving: bool) -> void:
	# 공격 애니(one-shot)가 도는 동안은 덮지 않는다 — 끝나면 walk/idle로 복귀.
	# 돌진 서브상태도 자기 클립(placeholder walk)을 직접 모므로 이동 애니 중재가 덮지 않게 게이트.
	# C1 코옵 클립(roar/grab/groggy) 재생 중에도 덮지 않는다.
	if _c1_active or _is_attack_anim_playing() or _state == State.CHARGE_DASH or _state == State.CHARGE_HIT:
		return
	_play(&"walk" if moving else &"idle")
