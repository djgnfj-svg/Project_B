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
const NavGrid := preload("res://src/enemies/nav_grid.gd")
const TelegraphFx := preload("res://src/feel/telegraph_fx.gd")
const MobStrikeFx := preload("res://src/feel/mob_strike_fx.gd")

# 연출값 (rules §0 예외)
const REMOTE_LERP_SPEED := 12.0
# attack 애니 선행 재생(초) — 예비 프레임(f6, 120ms)이 끝나는 순간 = 텔레그래프 만료 = mob_strike.
# frames.tres의 attack 첫 프레임 duration과 미러 (rules §3 "보이는 휘두름 = 맞는 타이밍").
const ATTACK_ANIM_LEAD_S := 0.12
const REMOTE_MOVE_EPS := 1.0      # 게스트 표시: 목표점과 이만큼 이상 벌어져 있으면 walk
# 추격 이탈 거리 = aggro_range × 이 배수. ⚠ 씬 스왑 프레임엔 이전 씬 플레이어가 "player" 그룹에
# 아직 남아 있어(queue_free는 프레임 끝) 게이트 앞 좌표로 유령 어그로가 잡힌다 — CHASE에 이탈
# 조건이 없으면 그 한 프레임이 영구 추격으로 굳는다 (챕터1 실기에서 발견, 간헐 레이스)
const LEASH_MULT := 1.5
# 🔴 지형 레이어(1 = world) 마스크 — rules §5 배정표가 단일 소스. `player.ENEMY_BODY_MASK`와 같은 관용구.
#   사선(LOS) 질의·길찾기 굽기 전용: 몸(2·3)·픽업(6)은 마스크에 없어 자기 자신·플레이어를 안 맞는다.
const WORLD_MASK := 1 << 0
# --- 길찾기 (호스트 전용 · 표시·네트워크와 무관 — 설계 근거·실측은 nav_grid.gd 머리말) ---
# 🔴 **직진이 통하면 길찾기를 안 쓴다.** 사선이 뚫려 있으면 예전 그대로 직진하고, 막혔을 때만
#   A* 경로를 탄다 — 열린 벌판(대부분의 프레임)에서 비용이 사실상 0이고, 도입 전 움직임이
#   **그 경우에 한해 완전 항등**이라 회귀 표면이 「막혔을 때」로 좁혀진다.
const NAV_LOS_INTERVAL_S := 0.2      # 사선 재확인 주기(초) — 매 프레임 레이캐스트를 피한다
const NAV_REPATH_S := 0.6            # 경로 재계산 주기(초). 매 프레임 굽지 않는다
const NAV_GOAL_MOVE_PX := 40.0       # 목표가 이만큼 움직이면 주기를 안 기다리고 다시 낸다
const NAV_WAYPOINT_REACH_PX := 10.0  # 웨이포인트 도달 판정 반경
# 갇힘 감지 — 사선은 **선**이라 몸 굵기를 모른다(뚫려 보이는데 모서리에 걸려 못 가는 경우).
const NAV_STUCK_WINDOW_S := 0.45
const NAV_STUCK_MIN_PX := 6.0
# 물러나다 벽에 몰린 원거리 몹이 CHASE↔BACKOFF를 매 프레임 오가지 않게 후퇴를 잠그는 시간(초).
const NAV_BACKOFF_BLOCK_S := 1.5
# 발사 원점 여유(px) — 화살이 몸 안에서 태어나지 않게. 🔴 상수를 크기로 쓰지 않는다:
#   실제 오프셋은 `body_radius + strike_radius + 이 값`이라 몹이 커지든 화살이 굵어지든 자동 추종한다.
const MUZZLE_PAD := 4.0
# 활 당기는 애니 배율의 하한 — 조준 창이 아주 길어도 애니가 사실상 정지해 보이지 않게(연출 안전판).
const MIN_ANIM_SPEED_SCALE := 0.05
# 접지 그림자 (사용자 요청 2026-07-26: "그림자가 잘 붙게해주면 됨" — 잔몹엔 아예 없었다).
# 🔴 텍스처 크기 미러 상수를 새로 만들지 않는다 — shadow.png·몹 시트를 다시 그려도 자동으로 맞게
#   런타임에 읽는다("텍스처를 고치면 상수도 고쳐야 하는" 함정을 안 늘린다 — 예고 장판의
#   `TELEGRAPH_TEX_SIZE`가 정확히 그 함정이었고 2026-08-02에 셰이더 전환으로 없앴다).
const SHADOW_WIDTH_MULT := 2.3   # 그림자 폭 = def.body_radius × 이 배수 (몸보다 살짝 넓어야 접지로 읽힌다)
const SHADOW_ALPHA := 0.5
const SHADOW_FOOT_INSET := 2.0   # 스프라이트 하단에서 이만큼 올려 둔다(발이 그림자를 밟고 선 모습)
# --- 예고 장판 (2026-08-02: 텍스처 → **보스와 같은 셰이더**) ---
#
# 왜 옮겼나: 옛 방식은 `telegraph.png`(정적인 원)를 스케일한 것뿐이라 **차오름이 없었다** —
#   "언제 때리는지"가 화면에서 안 읽혔다(사용자 신고). 셰이더로 오면 차오름·선단 파면·마지막
#   번쩍이 공짜로 따라오고, 덤으로 `TELEGRAPH_TEX_SIZE`(= telegraph.png 지름 32.0) **미러가 사라진다**
#   (그 PNG를 다시 그리면 반경이 조용히 갈라지던 자리다 — blast.png `TEX_RADIUS`와 같은 부류).
#
# 🔴 아래 상수에 **각·반지름이 없다 — 그게 설계다.** 표시 반경은 언제나 `def.strike_radius`
#   (= `CombatMath.is_strike_hit`의 판정 반경, §3) 하나에서 오고, 여기 있는 것은 전부
#   **시간·두께·색**이다. 예고를 "조금 더 크게" 만들려고 여기 숫자를 늘리지 마라 — 그 순간
#   "보이는 곳 ≠ 맞는 곳"이 된다. 범위를 바꾸려면 `data/enemies/*.tres` = 밸런스 변경이다.
#
# 색 선정 근거(시인성): 바닥이 **흙 갈색 · 잔디 초록 · 물 파랑** 셋이라 단색으로는 한 배경에서
#   반드시 묻힌다. 그래서 세 축을 겹쳐 쌓았다 — ⑴ 대각 해칭의 **어두운 줄**(밝은 바닥용 대비)
#   ⑵ 밝은 **황금 테두리**(어두운 바닥·물용 대비, 세 바닥 어디에도 없는 색상) ⑶ 차오름/번쩍의
#   **명도 변화**(색맹·저대비 모니터에서도 읽힌다). 전부 연출값 → docs/TUNING.md 대상.
# ⚠ 잔몹 반경은 22~28px로 보스(range 130 등)보다 훨씬 작다 — 그래서 알파를 보스보다 올리고
#   테두리·선단을 **반경 대비 두껍게** 잡았다(보스 값을 그대로 베끼면 작아서 안 보인다).
const TELEGRAPH_AA_PX := 1.0            # 경계 소프트 폭(월드 px) — 🔴 **바깥으로만** 퍼진다(= 항상 과예고)
const TELEGRAPH_QUAD_MARGIN_PX := 1.0   # 쿼드 여유 — 화면 픽셀 중심이 쿼드 밖으로 나가는 것 방지
const TELEGRAPH_BORDER_PX := 2.5        # 테두리 두께(경계 안쪽) — 반경 22에서 11%라 작아도 읽힌다
const TELEGRAPH_FILL := Color(0.847, 0.176, 0.141, 0.40)
const TELEGRAPH_BORDER := Color(1.000, 0.827, 0.353, 0.90)   # 황금 테두리 = 주 시인성 레버
const TELEGRAPH_STRIPE_DARK := Color(0.212, 0.043, 0.055, 0.52)
const TELEGRAPH_FILL_FADE := 0.20
const TELEGRAPH_PULSE_AMP := 0.12
const TELEGRAPH_PULSE_HZ := 2.6         # 보스(2.2)보다 조금 빠르게 — 잔몹 예고가 더 짧다
const TELEGRAPH_STRIPE_PERIOD := 9.0    # 반경 22 → 지름 44에 약 5줄
const TELEGRAPH_STRIPE_SPEED := 0.8
const TELEGRAPH_STRIPE_DUTY := 0.55
const TELEGRAPH_CHARGE := Color(1.000, 0.404, 0.129, 0.72)   # 다 찬 구역 — 더 뜨겁게
const TELEGRAPH_LEAD_PX := 4.0          # 차오름 선단 두께(보스 7.0을 반경비로 줄인 값)
const TELEGRAPH_FLASH := Color(1.000, 0.949, 0.784, 0.94)    # 마지막 순간 번쩍
const TELEGRAPH_FLASH_START := 0.82     # 이 진행도부터 번쩍이 올라온다

# --- 타격 순간 내지르기 (2026-08-02) ---
# 예고가 다 찬 그 프레임에 몸이 앞으로 툭 나간다 — 충격파(MobStrikeFx)와 같이 "지금 때렸다"를 읽힌다.
# 🔴 채널은 `_sprite.offset` **하나뿐**이고 손맛 계층 넷과 안 겹친다:
#   위치 = `Flinch`(sprite.position) · 스케일 = `HitStop` · 머티리얼 = `HitFlash` ·
#   speed_scale = `_apply_anim_scale`. 🔴 **몸(CharacterBody2D) 좌표는 절대 건드리지 마라** —
#   그건 판정 좌표라 `G_MOB_POS`·길찾기·`is_strike_hit`로 새어 나간다(표시가 판정을 움직인다).
const LUNGE_PX := 3.0     # 내지르는 거리(스프라이트 로컬 px — `sprite_scale`이 곱해져 화면엔 조금 더 크다)
const LUNGE_OUT := 0.05   # 나가는 시간
const LUNGE_BACK := 0.13  # 돌아오는 시간

# 돌진 먼지 — 발밑에서 뒤로 튀는 흙(연출값, rules §0 파티클 예외). 🔴 흙바닥보다 **어둡게**(진한 흙 갈색)
#   — 바닥이 밝은 사질이라 어두운 흙덩이가 대비로 읽힌다. 알파 페이드(color_ramp)로 옅게 사라진다.
const DUST_COLOR := Color(0.376, 0.267, 0.161)

# 원거리 조준선 — 연출값 (rules §0 예외)
const AIM_LINE_WIDTH := 1.0
const AIM_LINE_COLOR := Color(0.749, 0.247, 0.180, 0.5)  # #bf3f2e — 40색 팔레트의 경고 붉은
const AIM_ALPHA_START := 0.22    # 조준 시작 — 옅게
const AIM_ALPHA_END := 0.85      # 발사 직전 — 진하게(임박도)

# ⚠ CHARGE_DASH는 **끝에 붙였다** — 앞에 끼우면 기존 값의 정수가 밀린다(직렬화는 안 하지만 습관).
enum State { IDLE, CHASE, WINDUP, RECOVER, BACKOFF, CHARGE_DASH }

# --- 돌진 (2026-08-03, 들소 ox) — 보스 돌진의 **단순화판**(순간이동·왕복·회전 스윕 없음, 1회 직진) ---
# 색·타이밍은 연출값(rules §0 예외). 레인 예고는 근접 예고 셰이더를 캡슐 모드로 재사용한다.
const CHARGE_LANE_FILL := Color(0.847, 0.176, 0.141, 0.34)
const CHARGE_LANE_BORDER := Color(1.000, 0.827, 0.353, 0.90)   # 근접 예고와 같은 황금 테두리(시인성 규약 공유)
const CHARGE_LANE_STRIPE := Color(0.212, 0.043, 0.055, 0.52)
# 돌진 선택 정렬 문턱 — 플레이어가 대략 정면(±이 각, rad)일 때만 돌진한다(옆·뒤로는 안 돌진).
# ⚠ 예고를 보고 옆으로 피하는 것이 기믹이라(GDD §5) 너무 넓으면 회피가 불가능해진다.
const CHARGE_ALIGN_HALF_ANGLE := 0.52   # ≈ 30°
# 돌진을 **고려**하는 거리대(px) — 너무 붙으면(근접 사거리 안) 근접이 낫고, 너무 멀면 도달 전에 피한다.
const CHARGE_MIN_DIST := 40.0
const CHARGE_MAX_DIST := 300.0
# 준비동작(발 구르기) — 예고 전반부에 뒤로 살짝 빼며 힘을 모은다(새 시트 없이 `_sprite.offset`).
# 🔴 채널 = `_sprite.offset` **하나뿐** — 타격 순간 내지르기(`_lunge`)와 같은 채널이라 시간이 안 겹친다
#   (준비는 WINDUP, 내지르기는 근접 STRIKE — 돌진엔 `_lunge`가 없다). Flinch(position)·HitStop(scale)·
#   HitFlash(material)·anim_scale(speed) 넷과는 채널이 다르다.
const CHARGE_PREP_BACK_PX := 3.0    # 뒤로 빼는 거리(스프라이트 로컬 px)
const CHARGE_PREP_HZ := 8.0         # 발 구르기 진동수(Hz) — 후반부 떨림
const CHARGE_PREP_SHAKE_PX := 1.0   # 떨림 진폭(px)
const CHARGE_PREP_TINT := Color(1.0, 0.72, 0.62)  # 힘 모으는 붉은 기(연출) — 예고 후반부로 갈수록 짙어진다

@export var eid: String = ""
@export var def: EnemyDef

var _state: State = State.IDLE
var _state_left: float = 0.0
var _prev_hp: int = 0  # combat_impact 감소량 계산용
var _strike_center: Vector2 = Vector2.ZERO
# --- 돌진 (호스트 전용 AI 상태) ---
var _can_charge: bool = false           # def에서 유도(_ready) — CombatMath.mob_can_charge 단일 소스
var _is_charging: bool = false          # 이번 WINDUP이 돌진 예고인가(근접 예고와 갈래를 가른다)
var _charge_cd_left: float = 0.0        # 다음 "돌진 선택"까지 남은 쿨다운(호스트 전용). 🔴 재돌진 없음 — 1회뿐
var _charge_dir: Vector2 = Vector2.RIGHT   # 이번 돌진 방향(WINDUP 진입에 고정 — 조준 후 안 따라간다)
var _charge_start: Vector2 = Vector2.ZERO  # 돌진 시작 좌표 — 이동 거리(travel_max) 판정 기준
var _charge_end: Vector2 = Vector2.ZERO    # 돌진 끝점(= start + dir*travel) — 게스트 레인의 방향 소스(mob_telegraph center)
var _charge_seq: int = 0                # 돌진 회차 id(단조 증가) — CombatAuthority가 스윕 dedup 키로 쓴다(돌진당 1회)
var _charge_show_left: float = 0.0      # 🔴 게스트 전용 — 돌진 클립 표시 잔여 시간(레인 예고 만료에서 심는다).
#   호스트의 CHARGE_DASH 상태는 네트워크로 안 온다(신규 필드 0). 게스트는 돌진 예고(레인)가 끝나는
#   순간 = 발사로 인지해 이 창 동안 charge 클립을 재생한다 — 표시 전용, 판정·이동은 G_MOB_POS가 몬다.
var _dust: CPUParticles2D = null        # 돌진 먼지 이미터(지연 생성 — 처음 켜질 때 만든다. 안 돌진하는 몹엔 안 생김)
# 게스트: 이번 예고가 돌진 레인인가 + 레인 방향(호스트는 AI가 직접 심는다). show_telegraph가 def로 유도.
var _lane_visible: bool = false
var _lane_dir: Vector2 = Vector2.RIGHT
var _prep_phase: float = 0.0            # 준비동작 진행도(0→1) — 예고 후반부로 갈수록 떨림·틴트가 짙어진다
var _telegraph_is_lane: bool = false   # 현재 예고가 캡슐(돌진 레인)인가 — _reassert가 원/레인을 안 섞게
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
# 🔴 길찾기 격자는 **씬 전체가 하나를 공유한다** — 칸당 3840회 물리 질의를 몹마다 반복하면
#   4~6마리 × 3~4ms(웹)가 그대로 히치가 된다. 무효화는 열쇠로 한다: 바닥 TileMapLayer의
#   instance id가 바뀌면(= 다른 씬) 통째로 다시 굽는다. `main._swap`이 `add_child`라
#   `current_scene`은 계속 main이므로 **그것을 열쇠로 쓰면 스테이지가 바뀌어도 옛 격자가 남는다.**
static var _nav_shared: NavGrid = null
static var _nav_key: int = 0

var _nav_layer: TileMapLayer = null   # 이 몹이 찾은 바닥 레이어(없으면 길찾기 자체가 꺼진다)
var _nav_resolved: bool = false
var _path := PackedVector2Array()
var _path_i: int = 0
var _path_goal := Vector2.ZERO
var _repath_left: float = 0.0
var _los_left: float = 0.0
var _los_clear: bool = true           # 초기값 true = 도입 전(직진)과 같은 첫 프레임
var _stuck_ref := Vector2.ZERO
var _stuck_left: float = 0.0
var _backoff_block_left: float = 0.0
# --- 넉백 (2026-08-02) ---
# 층② 밀림은 **호스트 권한**이다 — 게스트는 기존 `G_MOB_POS`(10Hz + lerp)로 "목표점이 뒤로 갔다"로만
#   받는다(신규 메시지·필드 0개). 층①(흠칫)은 표시라 양쪽 클라에서 각자 로컬로 돈다.
# 🔴 `_knock_show_px`는 **호스트에만 선다**(권한 경로가 심는다) — 게스트는 -1로 남아
#   `Flinch`가 옛 고정값으로 떨어진다 = 게스트 화면은 도입 전과 항등. 세기는 때린 무기에서 오는데
#   게스트는 그 무기를 모르고, 알려면 `combat_impact`에 필드를 실어야 한다(= 새 표면).
var _knock_dir := Vector2.ZERO
var _knock_left: float = 0.0
var _knock_speed: float = 0.0
var _knock_show_px: float = -1.0   # 다음 `_on_hp_changed`가 소비할 층① 세기. -1 = 미상(항등 폴백)
# 🔴 예고 장판의 **월드 좌표**를 따로 들고 매 프레임 재주장한다 — `$Telegraph`는 이 몸의 **자식**이라
#   한 번만 심으면 **부모가 움직인 만큼 끌려간다**(보스가 2026-07-27 netreview에서 밟은 그 자리).
#   ⚠ 도입 전에도 **게스트에서는 이미 어긋나고 있었다**(매 프레임 lerp로 몸이 움직인다). 넉백은
#     호스트에서도 그 경로를 연다(WINDUP 중에 밀린다) — 타격점 `_strike_center`는 고정인데 표시만
#     따라가면 「보이는 예고 ≠ 맞는 자리」다(§3).
var _telegraph_center := Vector2.ZERO
# 🔴 이번 예고의 **총 길이** = 차오름(progress)의 분모. `show_telegraph`가 확정한 `dur` 그 자체다 —
#   식을 여기서 다시 쓰지 마라(보스 `_telegraph_total_s` 판례: "예고는 끝났는데 차오름은 70%"처럼
#   표시끼리 갈라진다). 호스트는 지연 보상분이 더해진 값, 게스트는 자기 `def.telegraph_s`이므로
#   **각 클라가 자기 창으로 리졸브**해도 "다 찼다 = 지금 맞는다"가 양쪽에서 동시에 성립한다(§3).
var _telegraph_total_s: float = 0.0
# 매 프레임 progress를 심을 대상(캐시 — 재조회 비용 제거). 반경이 고정이라 `_ready`에서 한 번 세운다.
var _telegraph_mat: ShaderMaterial = null

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


# 예고 장판의 기하·색을 **한 번** 심는다 (2026-08-02: 텍스처 → 셰이더).
#
# 🔴 표시 반경 = `def.strike_radius` = **판정 반경**(`CombatMath.is_strike_hit`) — 한 값에서만 온다(§3).
#   셰이더가 그리는 도형이 `length(p) <= radius_px`라 판정식 그 자체다(보스 판례와 같은 근거:
#   각·반지름이 텍스처 픽셀에 박혀 있으면 데이터를 튜닝하는 순간 에러 없이 갈라진다).
#
# ⚠ 보스처럼 예고마다 uniform을 전량 재설정하지 않는 이유: 잔몹은 패턴이 하나뿐이라 **반경이 절대
#   안 변한다**(보스 Telegraph 노드는 원/콘/캡슐을 오가며 재사용돼 낡은 값 잔류 경로가 있다).
#   🔴 다만 회차마다 바뀌는 `progress`만은 예외라 `show_telegraph`가 **매번 0으로 되심는다** —
#   안 심으면 다음 예고가 **이전 회차의 다 찬 상태로 시작**한다(에러 없음, 임박 신호만 거짓).
#   ⚠ 나중에 잔몹에 두 번째 패턴(반경이 다른 공격)이 생기면 이 함수를 `show_telegraph`로 옮기고
#     보스처럼 전량 재설정해라 — 안 그러면 두 번째 패턴이 첫 패턴의 반경으로 그려진다.
#
# 🔴 **머티리얼을 안 뗀다 — `hit_flash`의 "끝나면 material = null" 규율(rules §5)의 명시적 예외다.**
#   그 규율의 근거는 *"평상시에도 그려지는 스프라이트에 셰이더가 남으면 웹 Compatibility에서
#   amount=0이 항등이 아닐 수 있다"*인데, 이 노드는 예고 밖에서 `visible = false`라 **아예 안 그려진다**
#   (항등을 물을 off 상태가 없다). 반대로 떼면 남는 것이 흰 쿼드라 `visible`이 한 프레임이라도
#   살아 있으면 **거대한 흰 사각**이 뜬다 — 붙여 두는 쪽이 안전한 방향이다. 판단 기준은
#   "효과가 끝났는가"가 아니라 **"평상시에도 렌더되는가"**이고, 보스 텔레그래프가 같은 판례다.
func _setup_telegraph() -> void:
	if def == null:
		return
	_telegraph_mat = TelegraphFx.apply_circle(
		_telegraph, def.strike_radius, TELEGRAPH_AA_PX, TELEGRAPH_QUAD_MARGIN_PX)
	_apply_telegraph_style()  # 연출값(색·두께·주기) — show_lane과 공유(사본 방지)


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("mob")
	_remote_target = global_position
	_telegraph.visible = false
	# 근접/원거리 판별은 def 값에서 유도한다 (rules §3 단일 소스) — 배우·트립와이어가 같은 함수를 지난다.
	_is_ranged = CombatMath.is_ranged_enemy(def)
	# 돌진 판별도 값에서 유도한다 (rules §3 단일 소스). 원거리와 배타는 아니지만 ox는 근접+돌진이다.
	_can_charge = CombatMath.mob_can_charge(def)
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
		# 스프라이트 배율 — 시트 재작화 없이 덩치만 키운다 (2026-08-01). 기본 1.0 = 항등.
		# 🔴 **판정은 아래 `body_radius`가 그대로 정한다** — 데이터에서 둘을 같이 올려야 "맞는 곳 =
		#   보이는 곳"이 유지된다(그 경고는 `EnemyDef.sprite_scale` 필드 주석이 정본).
		# 🔴 **`HitStop.punch`보다 먼저 세팅돼야 한다** — punch가 첫 호출 때 현재 `scale`을
		#   `hs_base_scale` meta에 저장해 복원 기준으로 삼기 때문이다(rules §2). setup 시점이라 안전하다.
		if def.sprite_scale > 0.0:
			_sprite.scale = Vector2.ONE * def.sprite_scale
		# 몸 판정 반경 = def.body_radius — ⚠ shape 리소스는 씬 인스턴스 간 공유라 직접 만지면
		# 같은 tscn의 다른 개체까지 바뀐다 → 복제 후 적용 (조용히 깨지는 함정)
		var shape := _collision.shape.duplicate() as CircleShape2D
		if shape != null:
			shape.radius = def.body_radius
			_collision.shape = shape
		_health.setup(def.max_hp, def.respawns, def.respawn_delay)
		_prev_hp = def.max_hp
		_setup_telegraph()
		_fit_shadow()
	_health.hp_changed.connect(_on_hp_changed)
	# 권한 경로(호스트 apply_damage)에서만 발화 — CombatAuthority가 ehp 브로드캐스트 + 클리어 판정.
	# 이 연결이 없으면 게스트 화면에 시체가 남고 클리어가 영영 안 뜬다 (enemy.gd 글루와 동일 규약).
	_health.hp_confirmed.connect(func(hp: int) -> void: EventBus.enemy_hp_confirmed.emit(eid, hp))
	_play(&"idle")


func _on_hp_changed(hp: int, dropped: bool) -> void:
	var dead := hp <= 0
	_collision.set_deferred("disabled", dead)
	# 🔴 **실데미지 우선, hp 감소량은 폴백**(2026-08-01). `hp = maxi(0, hp - dmg)`라 감소량은
	#   **오버킬이 잘려** 막타가 실제보다 작게 떴다(5 남은 적을 10으로 때리면 "5"). `last_damage`
	#   0 = 미상(confirm_hp 등 데미지 개념이 없는 경로) → 옛 계산으로 떨어진다 = 항등.
	# 🔴 **`_prev_hp` 갱신은 `if dropped` **밖**이다** (netreview M-3). 안에 두면 허수아비가
	#   `confirm_hp(max_hp)`로 부활할 때(dropped=false) `_prev_hp`가 0에 굳고, 다음 타격의 폴백이
	#   음수 → `maxi(…,0)` → **숫자가 아예 안 뜬다.** `player.gd`의 같은 글루가 원래 이 형태다.
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
	if dead:
		_telegraph.visible = false
		_hide_aim_line()   # 죽으면 조준선도 즉시 거둔다 — 남으면 시체가 조준 중인 것처럼 보인다
		_knock_left = 0.0  # 시체는 안 밀린다 — 밀리던 중에 죽어도 그 프레임에 멎는다
		_knock_show_px = -1.0
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


# --- 넉백 (2026-08-02) ---
#
# 🔴 **층①(흠칫 표시)의 단일 진입점.** 세기·방향을 호스트 권한 경로가 심어 뒀으면 그것을 쓰고,
#   없으면(게스트 수신 표시·넉백 없는 경로) 옛 추측으로 떨어진다 = **도입 전과 완전 항등**.
#   ⚠ 옛 추측(`nearest_pos`)은 *가장 가까운 플레이어* 반대로 미는 것이라 2인에서 파트너가 더
#     가까우면 엉뚱한 쪽으로 흠칫한다 — 그래서 **아는 경우에는 반드시 실제 넉백 방향을 쓴다.**
# 🔴 **「아는 경우」는 호스트뿐이다 — 게스트 화면에선 이 폴백이 상시다**(netreview m-2).
#   `_knock_show_px`를 심는 것은 `apply_knockback`이고 그것은 **호스트 권한 경로에서만** 불린다.
#   게스트는 `G_MOB_POS`로 위치만 받으므로 영원히 `-1` → 위 추측으로 떨어진다. 즉 **같은 피격에
#   두 화면이 서로 다른 방향으로 흠칫할 수 있다**(파트너가 때린 사람보다 적에게 가까울 때).
#   ⚠ **이것을 고치려고 방향을 `combat_impact`에 싣지 마라** — 그 순간 표시 전용 훅이 네트워크
#   필드를 갖게 되고, 손맛 계층의 "네트워크 메시지 0개" 규약(rules §2)이 깨진다. 표시 오차를
#   수용하는 쪽이 옳다. 층②(몸 밀림)는 호스트 권한이라 **양쪽 화면에서 정확히 같다.**
func _play_flinch() -> void:
	# 🔴 방향과 세기를 **함께** 소비한다 — `_knock_show_px < 0`이면 이번 피격에 권한 경로가 아무것도
	#   안 심은 것이므로 `_knock_dir`(직전 타격의 방향)은 **낡았다.** 둘을 따로 판단하면 밀리지 않은
	#   피격이 한 타 전 방향으로 흠칫한다(2인에서만·간헐이라 원인이 화면에 안 드러난다).
	var dir := _knock_dir if _knock_show_px >= 0.0 else Vector2.ZERO
	if dir.length_squared() <= 0.000001:
		var opp := Flinch.nearest_pos(global_position, get_tree().get_nodes_in_group("player"))
		dir = global_position - opp
	Flinch.play(_sprite, dir, _knock_show_px)
	_knock_show_px = -1.0   # 1회 소비 — 다음 피격이 이전 무기의 세기를 물려받지 않게


# 🔴 **배우가 자기 상태를 안다** — 적용 지점(CombatAuthority)은 이 술어 하나만 본다.
#   잔몹은 항상 밀린다(보스만 돌진·결박·그로기에서 false). `_apply_anim_scale` 관용구와 같다.
func can_knock() -> bool:
	return true


# 🔴 **호스트 권한 경로 전용 진입점** — 데미지 확정 **직전**에 불린다(그래야 바로 뒤에 오는
#   `_on_hp_changed`가 층① 세기를 소비할 수 있다). `push_px` = 적 저항까지 반영된 몸 밀림 거리,
#   `show_px` = 저항 전 표시 세기(둘 다 `CombatMath`가 유일한 소스 — 여기서 다시 계산하지 마라).
func apply_knockback(dir: Vector2, push_px: float, show_px: float) -> void:
	if not dir.is_finite() or dir.length_squared() <= 0.000001:
		return
	# 🔴 **사망은 층①보다 먼저 거른다**(netreview m-3). 아래 `_knock_show_px`는 `hp_changed` →
	#   `_on_hp_changed`가 **소비할 때 비워지는** 값이라, 죽은 적에 들어온 확정(같은 스윙의 두 번째
	#   타격 · `invincible` 랩)은 심기만 하고 소비가 안 돼 **다음 피격까지 남는다.** 현 잔몹은 부활을
	#   안 해 무해하지만, `respawns = true` 적이 이 배우로 만들어지는 순간(rules §2 허수아비 게이트가
	#   이미 그 방향을 열어 뒀다) **부활 후 첫 흠칫이 한 타 전 세기·방향으로** 재생된다.
	# ⚠ **`push_px <= 0`과 같은 가드에 묶지 마라** — 그쪽은 정상 경로다(무기 미상이면 넉백이 0이지만
	#   층①은 살아야 한다, `KNOCK_DASH_RATIO` 주석 참조). 묶으면 무장 해제에서 흠칫이 통째로 사라진다.
	if _health.is_dead():
		return
	_knock_dir = dir.normalized()
	if is_finite(show_px) and show_px > 0.0:
		_knock_show_px = show_px
	if not is_finite(push_px) or push_px <= 0.0:
		return
	_knock_speed = CombatMath.knock_speed_px_s(push_px)
	_knock_left = CombatMath.knock_time_s(push_px)
	# 🔴 **경로 무효화 한 줄**(설계 A-11) — `_path_i`는 전진만 하므로 뒤로 밀린 몹이 이미 지난
	#   웨이포인트로 되돌아가려 하고, 장애물 반대편으로 밀렸다면 경로가 통째로 틀린다.
	#   ⚠ `_los_clear = false`로 **강제하지 마라** — 그러면 열린 벌판에서도 매 타격마다 A*를 굽는다.
	#     경로만 비우고 판단은 기존 0.2s 주기에 맡긴다.
	_path.resize(0)
	# 갇힘 감지 보정 — 넉백 변위를 "내가 걸었다"로 세면 실제로는 갇혔는데 안 갇힌 것으로 읽힌다.
	_stuck_ref = global_position


# 🔴 **AI 이동을 「대체」한다 — 합산 금지**(설계 A-9). 추격 전진이 넉백을 부분 상쇄하면 거리가
#   데이터와 갈라지고 화면에 이유가 안 드러난다(`player._local_move`의 대시 규칙과 같은 부호).
# 🔴 **`global_position +=` 금지 — `velocity` + `move_and_slide()`여야 한다.** 직접 대입은 충돌
#   해결을 건너뛰어 물·낭떠러지 **안으로 순간이동**시킨다(스테이지 바닥이 layer 1 콜리전을 쥔다).
#   이 한 줄 덕에 지형 차단이 **게임 코드 변경 0**으로 따라온다.
# ⚠ 상태 타이머는 여기서 **아무것도 건드리지 않는다** — 스턴락 금지(A-10). 접는 것은 자기 이동뿐이라
#   WINDUP은 정시에 STRIKE하고 「예고를 보고 구른다」가 그대로 산다. 무료 인터럽트 0.
func _tick_knock(delta: float) -> void:
	if _knock_left <= 0.0:
		return
	if not can_knock() or _health.is_dead():
		_knock_left = 0.0
		velocity = Vector2.ZERO
		return
	_knock_left -= delta
	velocity = _knock_dir * _knock_speed
	move_and_slide()
	if _knock_left <= 0.0:
		velocity = Vector2.ZERO


func _physics_process(delta: float) -> void:
	if _telegraph_left > 0.0:
		var before := _telegraph_left
		_telegraph_left -= delta
		if _is_ranged:
			_update_aim_line()
		# 예비 프레임 길이만큼 앞당겨 재생 → "내려침" 프레임이 텔레그래프 만료(=strike)와 겹친다
		# ⚠ 원거리는 이 규약을 안 쓴다 — 당기는 모션 전체가 조준 창을 채우도록 `_start_draw_anim`이
		#   `speed_scale`을 유도한다(고정 lead는 RTT 가변인 조준 창에 못 맞춘다).
		# ⚠ 돌진 레인(캡슐)일 땐 근접 attack(들이받기 내려침)을 재생하지 마라 — 그 모션은 그 자리
		#   한 방용이다. 돌진은 준비동작(_tick_charge_prep) 뒤 _play_charge_clip이 몬다.
		elif not _telegraph_is_lane and before > ATTACK_ANIM_LEAD_S \
				and _telegraph_left <= ATTACK_ANIM_LEAD_S:
			_play(&"attack")
		# 차오름(임박도) — 🔴 **`TIME`이 아니라 자기 예고 창에서 유도한다**(보스 판례 · §3 지연 보상).
		#   호스트 창은 `strike_delay_s`만큼 길어 남은 시간이 클라마다 다르다. TIME으로 만들면
		#   게스트가 **틀린 임박 신호**를 읽고, 그건 지연 보상이 없애려던 손해 그 자체다.
		# ⚠ 판정 형태는 안 건드린다 — 셰이더는 이 값으로 **색만** 바꾼다(반경은 그대로).
		if not _is_ranged and _telegraph_total_s > 0.0:
			var prog := 1.0 - _telegraph_left / _telegraph_total_s
			TelegraphFx.set_progress(_telegraph_mat, prog)
			# 소 준비동작 — 레인(돌진 예고)일 때만. 뒤로 살짝 빼며 후반부에 발 구르기 떨림 + 붉은 기.
			#   호스트/게스트 둘 다 _lane_visible이 서서 양쪽 화면에서 같이 보인다(offset은 표시 채널).
			if _lane_visible:
				_tick_charge_prep(prog)
		if _telegraph_left <= 0.0:
			# 🔴 **타격 순간 FX는 여기서 난다 — `EventBus.mob_strike`가 아니다.** 그 시그널은
			#   **호스트 전용 emit**이라(event_bus.gd) 매달면 게스트 화면엔 아무것도 안 뜬다.
			#   각 클라의 예고 카운트다운이 0이 되는 순간이 그 화면의 "지금 맞는다"이고, 호스트가
			#   지연 보상으로 타격을 늦춰 둔 덕에 그 순간이 실제 확정과 정렬된다(§3).
			#   ⇒ 표시 전용 · **네트워크 메시지 0개**(rules §2 손맛 계층).
			# ⚠ `visible` 게이트 = 사망 취소분이다. `_on_hp_changed`가 죽을 때 예고를 끄므로
			#   시체가 안 하는 타격의 충격파가 남지 않는다(호스트도 그때 STRIKE를 안 낸다 — 사망이
			#   `_state`를 IDLE로 돌린다). ⚠ `_telegraph.visible = false`보다 **먼저** 봐야 한다.
			# 돌진 레인은 충격파를 안 낸다 — 그건 원형 근접 타격의 지금 왔다다. 돌진의 지금 왔다는
			#   레인이 사라지고 몸이 튀어나가는 것이다(호스트 _enter_charge_dash가 그 프레임에 발사).
			if not _is_ranged and not _telegraph_is_lane and _telegraph.visible:
				_play_strike_fx()
			# 게스트: 방금 끝난 예고가 돌진 레인이면 이어지는 돌진(몸이 튀는 창) 동안 charge 클립을
			#   재생하도록 표시 타이머를 심는다. 창 길이 = 호스트 _enter_charge_dash의 dash 창과 같은
			#   식(travel_max / charge_speed + 0.4 여유)이라 def 하나로 양쪽이 맞는다. 호스트는 이 값을
			#   안 쓴다(_state == CHARGE_DASH로 이미 안다) — `not Net.is_host()` 게이트가 그것을 못 박는다.
			if _telegraph_is_lane and _can_charge and not Net.is_host():
				_charge_show_left = def.charge_travel_max / maxf(def.charge_speed, 1.0) + 0.4
			_telegraph.visible = false
			_lane_visible = false
			_sprite.offset = Vector2.ZERO   # 준비동작 offset 정리(레인 끝 = 발사) — 안 하면 어긋난 채 굳는다
			_sprite.modulate = Color.WHITE
			_hide_aim_line()
	_shadow.visible = not _health.is_dead()  # 시체·부활 대기 중엔 그림자도 없앤다(플레이어 고스트와 같은 규칙)
	if _health.is_dead() or def == null:
		return
	if Net.is_host():
		_host_ai(delta)
		_tick_knock(delta)   # 🔴 AI **뒤** — 넉백이 그 프레임의 이동을 대체한다(합산 금지, A-9)
		# ⚠ **넉백 중은 걷는 것이 아니다**(netreview m-4). 이 판정은 `_tick_knock` **뒤**라 그 프레임의
		#   `velocity`가 넉백 속도로 채워져 있는데, `_face()`는 넉백 분기 밖이라 몹이 플레이어를 본 채
		#   뒤로 밀린다 = **뒤로 미끄러지는 걷기**. 호스트 화면에서만 보인다(게스트는 `_remote_target`
		#   거리로 따로 판정한다) — 즉 두 화면이 서로 다르게 보이는 자리이기도 하다.
		# 🔴 돌진 중엔 이동 애니를 덮지 않는다 — `_enter_charge_dash`가 켠 charge 클립(loop)이 애니를
		#   소유한다. CHARGE_DASH는 CHASE/BACKOFF가 아니라 walking=false라, 여기서 _update_move_anim을
		#   부르면 매 물리 프레임 idle로 덮여 돌진 클립이 화면에 한 프레임도 못 산다(2026-08-03 실기 확인).
		#   attack(one-shot)이 _update_move_anim 안에서 예외인 것과 같은 부류 — 그쪽은 애니 이름으로,
		#   여기는 상태로 가른다(돌진 클립은 loop라 "재생 중" 가드만으론 idle 복귀를 못 막는다).
		if _state != State.CHARGE_DASH:
			var walking := (_state == State.CHASE or _state == State.BACKOFF) \
				and _knock_left <= 0.0 \
				and velocity.length_squared() > 0.0
			_update_move_anim(walking)
	else:
		var moving := global_position.distance_to(_remote_target) > REMOTE_MOVE_EPS
		global_position = global_position.lerp(_remote_target, minf(1.0, REMOTE_LERP_SPEED * delta))
		_sprite.flip_h = _remote_flip
		# 🔴 게스트 돌진 표시 — 예고 만료에서 심은 창 동안 charge 클립을 이어 재생한다(호스트의
		#   상태 기반 처방에 대응하는 게스트판). ⚠ `_play(&"charge")` — **force_restart 없이** 부른다.
		#   `_play_charge_clip`은 force_restart=true라 매 프레임 부르면 프레임0에 얼어붙는다(돌진 발사
		#   1회용). charge 애니가 없는 개체는 창만 흐르고 아래 이동 애니로 떨어진다(현행 유지).
		if _charge_show_left > 0.0:
			_charge_show_left -= delta
		if _charge_show_left > 0.0 and _has_anim(&"charge"):
			_play(&"charge")
		else:
			_update_move_anim(moving)
	# 🔴 돌진 먼지 — 발밑에서 모래가 뒤로 튄다. 켜는 게이트는 charge 클립과 **동일**하다(호스트=CHARGE_DASH,
	#   게스트=표시 창)라 그림과 먼지가 항상 함께 산다. 방향은 진행 반대(호스트 _charge_dir · 게스트 _lane_dir).
	#   표시 전용 · 각 클라 로컬 · 네트워크 0(drop_fx 규약과 동형).
	var dashing := (_state == State.CHARGE_DASH) if Net.is_host() else (_charge_show_left > 0.0)
	_update_dust(dashing, (-_charge_dir) if Net.is_host() else (-_lane_dir))
	# 🔴 **맨 끝에서 배속을 재주장한다** — 소유자가 매 프레임 자기 의도를 다시 심는 관용구
	#   (rules §2 · boss._apply_anim_scale). 이 프레임에 무엇이 speed_scale을 건드렸든 여기가 마지막이다.
	_apply_anim_scale()
	# 🔴 **몸이 움직인 뒤에** 예고를 제자리에 다시 못 박는다 — 순서가 계약이다(boss와 같은 관용구·
	#   같은 근거, rules §3). 위쪽에서 부르면 그 프레임의 이동(넉백 move_and_slide · 게스트 lerp)이
	#   뒤따라와 한 프레임씩 밀린다.
	_reassert_telegraph_pos()


func _host_ai(delta: float) -> void:
	_state_left -= delta
	_backoff_block_left -= delta
	_charge_cd_left -= delta   # 다음 돌진 선택까지의 최소 간격 (재돌진 없음 — 한 번 쓰면 이만큼 근접만)
	# 갇힘 감지는 **실제로 걷는 상태에서만** 의미가 있다 — 예고(WINDUP)로 서 있는 0.6~1.1s를
	# "안 움직였다"로 읽으면 매 공격마다 헛되이 경로를 다시 낸다.
	# ⚠ **넉백 중도 "자기 이동이 아니다"** (2026-08-02) — 넉백 변위(최대 12px)가
	#   `NAV_STUCK_MIN_PX`(6)를 넘으므로, 안 빼면 **벽에 걸려 못 가는 몹이 맞을 때마다 "걸었다"로
	#   읽혀** 경로 전환이 영영 안 걸린다(에러 없이 그 자리에서 걷는 애니만 돈다).
	if (_state != State.CHASE and _state != State.BACKOFF) or _knock_left > 0.0:
		_stuck_left = NAV_STUCK_WINDOW_S
		_stuck_ref = global_position
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
			# ⚠ `_backoff_block_left` — 벽에 몰려 못 물러난 직후에는 후퇴를 잠근다. 없으면
			#   BACKOFF(갇힘 → CHASE) ↔ CHASE(가까움 → BACKOFF)를 매 프레임 오가며 영영 못 쏜다.
			if _is_ranged and def.keep_dist > 0.0 and dist < def.keep_dist \
				and _backoff_block_left <= 0.0:
				_state = State.BACKOFF
				return
			# 🔴 원거리는 **사선(LOS)이 뚫려 있어야** 쏜다 (설계 ⑹ 층①, 2026-08-01).
			#   스테이지 바닥이 TileMapLayer + physics layer 1이 되면서 물·낭떠러지가 실물 벽이 됐다.
			#   이 게이트가 없으면 물 건너 궁수가 일방적으로 쏘는데, 전사만 남은 지금 플레이어에게
			#   답이 없다. 막혀 있으면 WINDUP에 안 들어가고 계속 추격 = **몹이 물을 돌아온다.**
			#   ⚠ 층②(화살 자체의 지형 차단)는 arrow.gd·combat_authority가 따로 진다 — 이건 "결정",
			#     저건 "결과"라 둘 다 필요하다(발사 후 표적이 엄폐물 뒤로 들어가는 경우).
			# 🔴 돌진 선택 — 근접 사거리보다 **먼저** 본다(근접이 닿는 거리면 돌진 대신 그냥 때린다).
			#   조건 전부는 `_should_charge`가 본다(쿨다운·거리대·정렬·사선). 하나라도 어긋나면 평소대로
			#   추격/근접으로 떨어진다(도입 전과 항등). 🔴 **재돌진 없음** — 쓰면 쿨다운을 재장전한다.
			if _can_charge and _charge_cd_left <= 0.0 and dist > def.attack_range \
					and _should_charge(anchor, dist):
				_enter_charge_windup(anchor)
				return
			if dist <= def.attack_range and (not _is_ranged or _has_line_of_sight(anchor)):
				# 타격점 고정 — 예고를 보고 빠져나갈 수 있어야 한다 (GDD §5 기믹 원칙)
				_strike_center = anchor
				_is_charging = false   # 명시: 이 WINDUP은 근접/원거리다(돌진 아님) — WINDUP 종료 분기가 갈린다
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
			# 🔴 길찾기에 맡기는 것은 **방향뿐이다 — 속력은 여전히 `def.move_speed`다.**
			#   이속을 건드리면 `CombatMath.MOB_LAG_SLACK_SPEED`(90)에서 유도한 각 슬랙이
			#   과소평가되어 창의 팁 타격이 게스트에서 조용히 거부된다(rules §3 「대상 좌표 각 슬랙」).
			# 🔴 **넉백 중엔 자기 이동을 접는다 — 대체이지 합산이 아니다**(A-9). 여기서 `_chase_dir`가
			#   아예 안 불리므로 경로 계산 비용도 0이다(A-11). 상태 타이머는 위에서 이미 흘렀다.
			if _knock_left > 0.0:
				velocity = Vector2.ZERO
			else:
				velocity = _chase_dir(anchor, delta) * def.move_speed
				move_and_slide()
			_face(anchor)
			_tick_stuck(delta, false)
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
			if _knock_left > 0.0:
				velocity = Vector2.ZERO   # 넉백이 후퇴를 대체한다 (CHASE와 같은 규칙)
			else:
				velocity = (global_position - bpos).normalized() * def.move_speed
				move_and_slide()
			_face(bpos)  # 물러나면서도 플레이어를 본다(조준 자세 유지 — 뒷모습으로 걷지 않는다)
			# 물러날 곳이 없으면(벽·물가) 그 자리에서 갈리는 대신 추격으로 돌아가 그냥 쏜다.
			_tick_stuck(delta, true)
		State.WINDUP:
			# 돌진 예고가 다 차면 근접 타격(mob_strike)이 아니라 직진으로 넘어간다(재돌진 없음).
			#   근접 예고는 그 자리 한 방, 돌진 예고는 이동 스윕 — WINDUP 진입 시 `_is_charging`이 갈랐다.
			velocity = Vector2.ZERO  # 예고 중엔 제자리(준비동작은 스프라이트 offset — 판정 좌표 불변)
			if _state_left <= 0.0:
				if _is_charging:
					_enter_charge_dash()   # 자기 상태(CHARGE_DASH)·타이머를 직접 세운다 — 아래 RECOVER 안 탄다
				else:
					if _is_ranged:
						_fire_arrow()  # 실제 투사체 — 등록·판정은 CombatAuthority(호스트)
					else:
						EventBus.mob_strike.emit(eid, _strike_center, -1)  # 판정·확정은 CombatAuthority (-1 = 단발, dedup 없음)
					# 🔴 근접·원거리 둘 다 RECOVER로 — 원거리가 이 전이를 놓치면 WINDUP에 갇혀 매 프레임 재발사한다.
					_state = State.RECOVER
					_state_left = def.attack_cooldown_s
		# 돌진(1회 직진) — 보스 CHARGE_DASH의 단순화판. `_charge_start`로부터의 이동 거리로
		#   종료를 판정한다(travel_max 도달 또는 타임아웃). 매 프레임 mob_strike를 `_charge_seq`와
		#   함께 emit → CombatAuthority가 돌진당 1회 dedup(이동 히트박스라 프레임 dedup으론 매 프레임
		#   데미지). 지형에 막히면 move_and_slide가 이동을 멈춰 이동 거리가 안 늘고, 그러면
		#   타임아웃(_state_left)이 종료를 대신 진다 — 벽에 낀 채 영원히 안 끝나지 않게 하는 안전판.
		State.CHARGE_DASH:
			var traveled := _charge_start.distance_to(global_position)
			if traveled >= def.charge_travel_max or _state_left <= 0.0:
				_end_charge()
			else:
				velocity = _charge_dir * def.charge_speed
				move_and_slide()
				# 판정·표시가 같은 반경을 지난다(§3) — 스윕 원 중심 = 몸의 현재 위치.
				#   호스트가 이 좌표에서 판정하고 게스트는 G_MOB_POS로 이 좌표를 따라온다.
				EventBus.mob_strike.emit(eid, global_position, _charge_seq)
		State.RECOVER:
			if _state_left <= 0.0:
				_state = State.CHASE



# --- 돌진 (호스트 전용 AI — 보스 돌진의 단순화판: 순간이동·왕복·회전 스윕 없음, 1회 직진) ---

# 돌진할 만한가 — 거리대·정렬·사선을 한 곳에서 본다(호출부가 쿨다운·can_charge는 이미 걸렀다).
#   대략 정면(±CHARGE_ALIGN_HALF_ANGLE)일 때만 돌진한다 — 옆·뒤로 돌진하면 예고를 보고 옆으로
#   피하는 기믹(GDD §5)이 무너진다. 사선이 막혀 있으면(물·낭떠러지 건너) 돌진해도 벽에 박으니 뺀다.
func _should_charge(anchor: Vector2, dist: float) -> bool:
	if dist < CHARGE_MIN_DIST or dist > CHARGE_MAX_DIST:
		return false
	var to_p := _dir_to(anchor)
	# 현재 바라보는 방향(flip_h로 좌우만 안다)과의 정렬 — 몹은 상하 조준이 없으니 좌우 반평면으로 근사.
	#   더 정확히: 플레이어가 좌/우 어느 쪽인지와 몹 facing이 같은 쪽인지. 정면이 아니면 먼저 돌아본다
	#   (이 프레임은 CHASE로 떨어져 _face가 돌리고, 다음 판단에서 정렬되면 돌진).
	var facing := -1.0 if _sprite.flip_h else 1.0
	if signf(to_p.x) != facing and absf(to_p.x) > 0.2:
		return false
	return _has_line_of_sight(anchor)


# 돌진 예고 진입(호스트). 방향·시작·끝점을 고정하고 레인 예고를 띄운다. 🔴 재돌진 없음 — 쿨다운은
#   _end_charge에서 재장전한다(여기서 하면 예고 중 취소돼도 쿨다운이 도는 비대칭이 생긴다).
func _enter_charge_windup(anchor: Vector2) -> void:
	_is_charging = true
	_charge_dir = _dir_to(anchor)
	_charge_start = global_position
	_charge_end = _charge_start + _charge_dir * def.charge_travel_max
	_face(anchor)
	_state = State.WINDUP
	velocity = Vector2.ZERO
	# 지연 보상(§3) — 근접 예고와 같은 규약: 게스트 화면 예고가 편도 지연만큼 늦게 뜨므로 그만큼
	#   돌진 발사도 늦춘다(호스트가 자기 예고를 늘려 "보이는 예고 = 맞는 타이밍" 유지).
	var telegraph_total := def.charge_telegraph_s + CombatMath.strike_delay_s(Net.max_remote_one_way_ms())
	_state_left = telegraph_total
	_prep_phase = 0.0
	# 호스트 레인 표시 — 시작→끝점. 게스트는 아래 mob_telegraph(endpoint)로 방향을 유도한다.
	show_lane(_charge_start, _charge_end, telegraph_total)
	# 🔴 center = **끝점**을 실어 보낸다(신규 필드 0). 게스트가 `_is_charge_telegraph`로 근접(가까운
	#   center)과 갈라, 끝점 방향으로 레인을 그린다. 근접은 여전히 strike_center(가까움)를 싣는다.
	EventBus.mob_telegraph.emit(eid, _charge_end)


# 돌진 발사(호스트). WINDUP 종료에서 불린다 — 회차 갱신 후 CHARGE_DASH로. 재돌진 없음.
func _enter_charge_dash() -> void:
	_charge_seq += 1                       # 스윕 dedup 회차(돌진당 1회) — CombatAuthority._mob_sweep_seq와 짝
	# 🔴 _charge_start를 여기서 덮지 않는다 — 그려진 레인(windup start→endpoint)을 돌진이 그대로 따른다.
	#   WINDUP 중 넉백으로 몸이 밀렸어도 판정 기준을 그린 레인에 맞춰 「보이는 곳 = 맞는 곳」을 지킨다.
	_state = State.CHARGE_DASH
	# 타임아웃 상한 = 이동시간 + 여유(지형에 막혀 거리가 안 늘 때 종료를 대신 지는 안전판).
	_state_left = def.charge_travel_max / maxf(def.charge_speed, 1.0) + 0.4
	# 레인은 발사 순간 꺼진다(_physics_process가 windup 끝에 visible=false) — 돌진의 「지금 왔다」는
	#   레인이 사라지고 몸이 튀어나가는 것이다. offset은 그 블록이 이미 0으로 되돌렸다(이중 안전).
	_sprite.offset = Vector2.ZERO
	_sprite.modulate = Color.WHITE
	_face(_charge_end)
	# 스프라이트 스왑 훅 — 전용 ox_dash 시트가 붙으면 여기서 돌진 클립으로 갈린다(지금은 walk 폴백).
	_play_charge_clip()


# 돌진 종료(호스트). travel_max 도달·타임아웃에서. 🔴 여기서 쿨다운을 재장전한다(재돌진 없음).
func _end_charge() -> void:
	_is_charging = false
	_charge_cd_left = def.charge_cooldown_s
	velocity = Vector2.ZERO
	_telegraph.visible = false
	_sprite.offset = Vector2.ZERO
	_sprite.modulate = Color.WHITE
	_state = State.RECOVER
	_state_left = def.attack_cooldown_s


# 돌진 애니 클립 — 전용 시트(ox_dash)가 붙으면 여기서 스왑한다. 지금은 결합 없이 walk 폴백만.
#   🔴 시트 스왑 훅을 최소로 남긴다(리드가 나중에 붙인다) — `_play_alt_clip`이 있으면 그것을,
#   없으면 walk로 떨어진다(고속 이동 + 먼지·속도선 FX는 기존 재사용, 별도 에셋 불필요).
func _play_charge_clip() -> void:
	if _has_anim(&"charge"):
		_play(&"charge", true)
	else:
		_play(&"walk")


# 돌진 먼지 이미터 — 켤 때 처음 생성한다(안 돌진하는 몹엔 노드가 안 붙는다). 발밑(그림자 지점)에서
#   모래가 진행 반대+살짝 위로 튀고 중력에 떨어진다. 🔴 웹 Compatibility 안전 = CPUParticles2D
#   (GPU 파티클 회피 — drop_fx 규약). 표시 전용·각 클라 로컬. z는 상대 -1(뒤로 튄 먼지 = 소 뒤).
func _update_dust(active: bool, back_dir: Vector2) -> void:
	if _dust == null:
		if not active:
			return
		_dust = CPUParticles2D.new()
		_dust.one_shot = false            # 돌진 내내 흐르는 트레일(일회 버스트 아님)
		_dust.emitting = false
		_dust.amount = 52                      # 훨씬 풍성하게 — 돌진 내내 흙이 뭉텅뭉텅 튄다
		_dust.lifetime = 0.55
		_dust.initial_velocity_min = 25.0
		_dust.initial_velocity_max = 120.0     # 속도 폭을 넓혀 가까운 흙덩이 + 멀리 튄 알갱이가 섞인다
		_dust.spread = 60.0
		_dust.gravity = Vector2(0.0, 280.0)    # 튄 뒤 바닥으로 떨어진다
		_dust.scale_amount_min = 1.5
		_dust.scale_amount_max = 4.5           # 큰 흙덩이 ~ 작은 알갱이
		_dust.color = DUST_COLOR
		# 알파 페이드 — 튄 흙이 옅어지며 사라진다(팝 없이). 최종색 = color × ramp.
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
		ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		_dust.color_ramp = ramp
		_dust.z_as_relative = true
		_dust.z_index = -1
		_dust.position = _shadow.position     # 발밑 = 그림자와 같은 지점
		add_child(_dust)
	_dust.emitting = active
	if active and back_dir.length_squared() > 0.0001:
		# 진행 반대 방향에 상향 성분을 섞는다 — 뒤로+위로 튄 뒤 중력에 떨어진다.
		_dust.direction = (back_dir.normalized() + Vector2.UP * 0.7).normalized()


# 소 준비동작(발 구르기) — 돌진 예고 동안 뒤로 살짝 빼며 후반부에 떨림 + 붉은 기. 새 시트 불필요.
# 🔴 채널은 `_sprite.offset`(위치)·`_sprite.modulate`(색) 둘뿐이고 손맛 계층과 안 겹친다:
#   Flinch(position)·HitStop(scale)·HitFlash(material)·anim_scale(speed)와 채널이 다르다.
#   🔴 몸(CharacterBody2D) 좌표·scale은 절대 안 건드린다 — 그건 판정·그림자·길찾기로 새어 나간다.
# ⚠ 방향은 `_lane_dir` **반대**(뒤로 뺀다) — 호스트/게스트 둘 다 show_lane에서 이 값을 세웠다.
func _tick_charge_prep(progress: float) -> void:
	var p := clampf(progress, 0.0, 1.0)
	# 뒤로 빼기: 예고 내내 서서히 뒤로(=힘 모으기). 후반부에 발 구르기 떨림을 얹는다.
	var back := -_lane_dir * (CHARGE_PREP_BACK_PX * p)
	var shake := 0.0
	if p > 0.5:
		# 후반부에만 떨림 — sin이라 좌우로 자잘하게. TIME이 아니라 progress에서 위상을 만든다
		#   (예고 창 길이가 클라마다 달라 TIME은 위상이 갈라진다 — 근접 차오름과 같은 부호).
		shake = sin(p * CHARGE_PREP_HZ * TAU) * CHARGE_PREP_SHAKE_PX * ((p - 0.5) * 2.0)
	_sprite.offset = back + Vector2(shake, 0.0)
	# 붉은 기가 후반부로 갈수록 짙어진다(힘이 모인다) — modulate라 hit_flash material과 채널이 다르다.
	_sprite.modulate = Color.WHITE.lerp(CHARGE_PREP_TINT, p)


# --- 길찾기 (호스트 전용) ---
#
# 🔴 **네트워크 메시지가 0개다.** 여기서 나오는 것은 이번 프레임의 이동 **방향**뿐이고, 그 결과는
#   지금처럼 `G_MOB_POS`(10Hz 좌표)로만 게스트에 간다 — 경로도, 목표도, 격자도 전송하지 않는다.
#   그래서 새 kind·채널 분류·신뢰 경계가 하나도 늘지 않는다(rules §1 "AI는 호스트에서만 돈다").
#
# 규칙은 두 줄이다:
#   ⑴ 사선이 뚫려 있으면 **예전 그대로 직진**한다 — 열린 벌판(대부분의 프레임)에서 비용 ≈ 0이고
#      도입 전 움직임과 그 경우에 한해 **완전 항등**이다.
#   ⑵ 막혔을 때만 A* 경로를 낸다. 경로가 안 나오면(격자 없음·도달 불가) 역시 직진으로 떨어진다 —
#      즉 **어떤 실패도 "예전 동작"으로만 떨어진다.**
func _chase_dir(anchor: Vector2, delta: float) -> Vector2:
	var to_target := anchor - global_position
	var direct := to_target.normalized() if to_target.length() > 0.001 else Vector2.RIGHT
	_los_left -= delta
	if _los_left <= 0.0:
		_los_left = NAV_LOS_INTERVAL_S
		_los_clear = _has_line_of_sight(anchor)
	if _los_clear:
		_path.resize(0)
		return direct
	var nav := _nav()
	if nav == null:
		return direct   # 바닥 TileMapLayer가 없는 씬(보스방·시험장) = 도입 전과 완전 항등
	_repath_left -= delta
	if _path.is_empty() or _repath_left <= 0.0 \
			or anchor.distance_to(_path_goal) > NAV_GOAL_MOVE_PX:
		_repath_left = NAV_REPATH_S
		_path_goal = anchor
		# ⚠ `direct_space_state`는 물리 프레임 안에서만 유효하다 — 보관하지 않고 그때그때 넘긴다.
		#   (`_host_ai`는 `_physics_process`에서만 불린다.)
		_path = nav.find_path(global_position, anchor, def.body_radius,
			get_world_2d().direct_space_state, WORLD_MASK)
		_path_i = 0
	while _path_i < _path.size() \
			and global_position.distance_to(_path[_path_i]) <= NAV_WAYPOINT_REACH_PX:
		_path_i += 1
	if _path_i >= _path.size():
		_path.resize(0)
		return direct
	var seg := _path[_path_i] - global_position
	return seg.normalized() if seg.length() > 0.001 else direct


# 갇힘 감지 — 사선(LOS)은 **선**이라 몸 굵기를 모른다. 뚫려 보이는데 모서리에 몸이 걸려 못 가는
# 경우가 있고, 그때 화면에는 이유가 안 드러난다(제자리에서 걷는 애니만 돈다).
#   추격 중이면 → "직진은 실제로 안 통한다"로 보고 경로 추종으로 넘긴다.
#   후퇴 중이면 → 물러날 곳이 없는 것이므로 추격으로 돌려 그냥 쏘게 한다(잠시 후퇴 잠금).
func _tick_stuck(delta: float, backing_off: bool) -> void:
	_stuck_left -= delta
	if _stuck_left > 0.0:
		return
	_stuck_left = NAV_STUCK_WINDOW_S
	var moved := global_position.distance_to(_stuck_ref)
	_stuck_ref = global_position
	if moved >= NAV_STUCK_MIN_PX:
		return
	if backing_off:
		_backoff_block_left = NAV_BACKOFF_BLOCK_S
		velocity = Vector2.ZERO
		_state = State.CHASE
		return
	_los_clear = false
	_los_left = NAV_LOS_INTERVAL_S   # 다음 재확인까지 이 판단을 유지한다
	_path.resize(0)


# 씬이 공유하는 길찾기 격자. 바닥 TileMapLayer를 못 찾으면 null = 길찾기 비활성(기존 동작).
# 🔴 굽기는 **첫 "막힘"에서 지연 실행**된다 — `_ready`에서 구우면 물리 서버가 아직 그 프레임의
#   바디를 동기화하지 않아 **전부 통행 가능한 격자**가 조용히 만들어진다(에러 0).
func _nav() -> NavGrid:
	if not _nav_resolved:
		_nav_resolved = true
		_nav_layer = _find_ground_layer()
	if _nav_layer == null or _nav_layer.tile_set == null:
		return null
	var key := int(_nav_layer.get_instance_id())
	if _nav_shared != null and _nav_key == key:
		return _nav_shared
	var used := _nav_layer.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return null
	var ts := _nav_layer.tile_set.tile_size
	var area := Rect2(_nav_layer.global_position + Vector2(used.position * ts),
		Vector2(used.size * ts))
	var ng := NavGrid.new()
	ng.setup(area, NavGrid.DEFAULT_CELL)
	_nav_shared = ng
	_nav_key = key
	return ng


# 바닥 레이어 찾기 — 하드코딩 경로 대신 **형제/조상의 자식 중 TileMapLayer**를 훑는다.
# 잔몹은 스테이지 루트의 직계 자식이라(gen_stage.py) 첫 홉에서 잡힌다. 씬 파일을 안 고치는 것이
# 이 방식의 값이다 — `stage_1.tscn`/`stage_2.tscn`은 생성물이라 손으로 고치면 재생성 때 날아간다.
func _find_ground_layer() -> TileMapLayer:
	var n := get_parent()
	var hops := 0
	while n != null and hops < 3:
		for c: Node in n.get_children():
			var t := c as TileMapLayer
			if t != null and t.tile_set != null:
				return t
		n = n.get_parent()
		hops += 1
	return null


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
	# 🔴 게스트 돌진 판별 — center가 **끝점**(멀다)이면 레인, strike_center(가깝다)면 근접 원.
	#   근접 타격점은 attack_range 안이고 돌진 끝점은 travel_max(먼)이라 거리 하나로 갈린다 —
	#   **신규 필드 0개**(설계: 기존 경로에 데이터로 얹기). 호스트는 이 경로를 안 지난다(_enter_charge_windup이
	#   show_lane을 직접 부르고 _is_charging으로 이미 안다) — 여기 판별은 게스트 전용이다.
	if _can_charge and not Net.is_host() \
			and global_position.distance_to(center) > def.attack_range + def.strike_radius:
		_face(center)                            # 돌진 방향을 본다(자세) — show_lane이 _lane_dir도 세운다
		show_lane(global_position, center, dur)  # 게스트: 몸 현재 위치(≈windup pos) → 끝점
		return
	_telegraph_is_lane = false
	_telegraph_center = center
	_refit_circle_telegraph()  # 직전이 레인(캡슐)이었을 수 있으니 원 형태로 되심는다(노드 재사용)
	_telegraph.global_position = center
	_telegraph.visible = true
	_telegraph_left = dur
	# 차오름 분모 = 표시 지속과 **문자 그대로 같은 값**이라 "다 찼다 = 사라진다 = 맞는다"가 세 축에서
	# 동시에 성립한다(보스 `_telegraph_duration` 판례, §3). 식을 다시 쓰면 표시끼리 갈라진다.
	_telegraph_total_s = dur
	# 🔴 0으로 되심는 것이 계약이다 — Telegraph 노드는 공격마다 재사용되므로 안 심으면 다음 예고가
	#   **이전 회차의 다 찬 상태로 시작**한다(에러 없음, 임박 신호만 거짓).
	TelegraphFx.set_progress(_telegraph_mat, 0.0)


# 돌진 레인 예고(캡슐) — 호스트/게스트 공용. 시작→끝점 선분을 스윕 반경으로 부풀린 띠를 그린다.
#   🔴 반경 = `CombatMath.mob_charge_sweep_radius`(= 호스트 스윕 판정 반경) 그대로 = "맞는 곳 = 보이는 곳"(§3).
#   노드 원점 = 선분 중점, rotation = 방향. 차오름은 근접과 같은 카운트다운(_telegraph_left)이 민다.
func show_lane(start: Vector2, end: Vector2, dur: float) -> void:
	if def == null:
		return
	var seg := end - start
	var half_len := seg.length() * 0.5
	var angle := seg.angle() if seg.length() > 0.001 else 0.0
	var radius := CombatMath.mob_charge_sweep_radius(def)
	_lane_dir = _dir_to(end)
	_lane_visible = true
	_telegraph_is_lane = true
	_telegraph_center = start + seg * 0.5   # 캡슐 원점 = 중점 (_reassert가 여기에 못 박는다)
	_telegraph_mat = TelegraphFx.apply_capsule(
		_telegraph, radius, half_len, angle, TELEGRAPH_AA_PX, TELEGRAPH_QUAD_MARGIN_PX)
	# 색·테두리는 근접 예고와 톤을 맞춘다(같은 셰이더라 유니폼 이름이 같다).
	_telegraph_mat.set_shader_parameter(&"border_px", TELEGRAPH_BORDER_PX)
	_telegraph_mat.set_shader_parameter(&"fill_color", CHARGE_LANE_FILL)
	_telegraph_mat.set_shader_parameter(&"border_color", CHARGE_LANE_BORDER)
	_telegraph_mat.set_shader_parameter(&"stripe_dark", CHARGE_LANE_STRIPE)
	_telegraph_mat.set_shader_parameter(&"fill_fade", TELEGRAPH_FILL_FADE)
	_telegraph_mat.set_shader_parameter(&"pulse_amp", TELEGRAPH_PULSE_AMP)
	_telegraph_mat.set_shader_parameter(&"pulse_hz", TELEGRAPH_PULSE_HZ)
	_telegraph_mat.set_shader_parameter(&"stripe_period", TELEGRAPH_STRIPE_PERIOD)
	_telegraph_mat.set_shader_parameter(&"stripe_speed", TELEGRAPH_STRIPE_SPEED)
	_telegraph_mat.set_shader_parameter(&"duty", TELEGRAPH_STRIPE_DUTY)
	_telegraph_mat.set_shader_parameter(&"charge_color", TELEGRAPH_CHARGE)
	_telegraph_mat.set_shader_parameter(&"lead_px", TELEGRAPH_LEAD_PX)
	_telegraph_mat.set_shader_parameter(&"flash_color", TELEGRAPH_FLASH)
	_telegraph_mat.set_shader_parameter(&"flash_start", TELEGRAPH_FLASH_START)
	_telegraph.global_position = _telegraph_center
	_telegraph.visible = true
	_telegraph_left = dur
	_telegraph_total_s = dur
	TelegraphFx.set_progress(_telegraph_mat, 0.0)


# 근접 예고를 원 모드로 되돌린다 — 같은 Telegraph 노드가 직전에 레인(캡슐)이었을 수 있으므로
#   반경·형태를 매번 다시 심는다(안 하면 근접 예고가 이전 레인의 캡슐로 그려진다 — 노드 재사용 함정).
func _refit_circle_telegraph() -> void:
	_lane_visible = false
	_telegraph_mat = TelegraphFx.apply_circle(
		_telegraph, def.strike_radius, TELEGRAPH_AA_PX, TELEGRAPH_QUAD_MARGIN_PX)
	_apply_telegraph_style()


# 예고 셰이더의 연출값(색·두께·주기)을 심는다 — _setup_telegraph와 show_lane이 공유(사본 방지).
func _apply_telegraph_style() -> void:
	_telegraph_mat.set_shader_parameter(&"border_px", TELEGRAPH_BORDER_PX)
	_telegraph_mat.set_shader_parameter(&"fill_color", TELEGRAPH_FILL)
	_telegraph_mat.set_shader_parameter(&"border_color", TELEGRAPH_BORDER)
	_telegraph_mat.set_shader_parameter(&"stripe_dark", TELEGRAPH_STRIPE_DARK)
	_telegraph_mat.set_shader_parameter(&"fill_fade", TELEGRAPH_FILL_FADE)
	_telegraph_mat.set_shader_parameter(&"pulse_amp", TELEGRAPH_PULSE_AMP)
	_telegraph_mat.set_shader_parameter(&"pulse_hz", TELEGRAPH_PULSE_HZ)
	_telegraph_mat.set_shader_parameter(&"stripe_period", TELEGRAPH_STRIPE_PERIOD)
	_telegraph_mat.set_shader_parameter(&"stripe_speed", TELEGRAPH_STRIPE_SPEED)
	_telegraph_mat.set_shader_parameter(&"duty", TELEGRAPH_STRIPE_DUTY)
	_telegraph_mat.set_shader_parameter(&"charge_color", TELEGRAPH_CHARGE)
	_telegraph_mat.set_shader_parameter(&"lead_px", TELEGRAPH_LEAD_PX)
	_telegraph_mat.set_shader_parameter(&"flash_color", TELEGRAPH_FLASH)
	_telegraph_mat.set_shader_parameter(&"flash_start", TELEGRAPH_FLASH_START)


# 🔴 예고는 **뜬 자리에 못 박혀 있어야 한다** — `$Telegraph`가 이 몸의 자식이라 몸이 움직이면
#   끌려간다. 타격점(`_strike_center`)은 WINDUP 진입에 고정되므로, 표시만 따라가면 「보이는 예고 ≠
#   맞는 자리」가 되고 그 어긋남이 **회피를 결정하는 바로 그 구간**에 생긴다(rules §3, 보스 판례).
#   ⚠ 호출 위치가 계약이다 — `_physics_process` **맨 끝**(이동 뒤). 앞에서 부르면 한 프레임씩 밀린다.
func _reassert_telegraph_pos() -> void:
	if _telegraph.visible:
		_telegraph.global_position = _telegraph_center


# --- 타격 순간 (2026-08-02) — "언제 때리는지"의 나머지 절반 ---
#
# 예고가 차오르는 것이 「곧 온다」라면, 여기가 「지금 왔다」다. 도입 전에는 예고 원이 그냥 **사라지기만**
# 해서 타격 프레임이 화면에서 아무 신호도 안 냈다(사용자 신고).
#
# 🔴 **표시 전용이다.** 판정·데미지 확정은 `EventBus.mob_strike` → `CombatAuthority`가 **따로** 하고
#   여기서는 아무 상태도 안 건드린다(rules §2: 판정 코드에 연출을 섞지 마라 — 그 반대편도 같다).
# 🔴 좌표는 `_telegraph_center`(= WINDUP에 고정된 타격점)다. `global_position`을 쓰면 넉백·추격으로
#   몸이 움직인 만큼 어긋나 「보이는 충격 ≠ 맞은 자리」가 된다 — `_reassert_telegraph_pos`가 예고에
#   대해 막고 있는 것과 **정확히 같은 함정**이다.
# 🔴 반경은 `def.strike_radius` 그대로 넘긴다 — 충격파를 "조금 더 크게" 만들지 마라(§3).
func _play_strike_fx() -> void:
	if def == null:
		return
	# 스테이지 루트에 붙인다 — 몹의 자식이면 충격파가 몸을 따라 끌려가고, 몹이 그 프레임에 죽으면
	# 같이 사라진다(런타임 add_child라 `_ready` "Parent node is busy" 함정과 무관, rules §5).
	MobStrikeFx.burst(get_parent(), _telegraph_center, def.strike_radius)
	_lunge(_telegraph_center)


# 타격 순간 몸이 앞으로 툭 내지른다 — 충격파와 함께 "이 몹이 때렸다"를 개체 단위로 읽힌다.
# 🔴 채널 = `_sprite.offset` **하나뿐**이고 손맛 계층 넷과 안 겹친다(선언부 `LUNGE_PX` 주석이 정본).
#   🔴 몸(CharacterBody2D) 좌표는 절대 안 건드린다 — 그건 판정 좌표다.
# ⚠ 직전 트윈을 죽이고 offset을 0으로 되돌린 뒤 시작한다(`Flinch`와 같은 관용구) — 안 그러면
#   연타 시 이전 트윈의 복귀 구간이 겹쳐 스프라이트가 **어긋난 offset에 굳는다**(에러 없음).
func _lunge(target: Vector2) -> void:
	var d := target - global_position
	if d.length() < 0.01:
		return
	var prev: Variant = _sprite.get_meta(&"lunge_tween", null)
	if prev is Tween and (prev as Tween).is_valid():
		(prev as Tween).kill()
	_sprite.offset = Vector2.ZERO
	var tw := _sprite.create_tween()
	_sprite.set_meta(&"lunge_tween", tw)
	tw.tween_property(_sprite, "offset", d.normalized() * LUNGE_PX, LUNGE_OUT) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_sprite, "offset", Vector2.ZERO, LUNGE_BACK) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


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
