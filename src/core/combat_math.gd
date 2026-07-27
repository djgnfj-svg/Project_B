class_name CombatMath
extends RefCounted
# 전투 수치 계산 — 단일 소스 (projectb-rules §3 하드 계약).
# UI 표시·실전투(호스트 확정)가 전부 이 함수만 부른다. 다른 곳에서 같은 계산을 만들면 갈라진다.


# 최종 데미지. bonus_attack = 착용 장비 공격 합(total_stats.attack). 미착용=0 → 기존 동작과 동일(항등 폴백).
static func calc_damage(job: JobDef, bonus_attack: int = 0) -> int:
	return job.attack_damage + bonus_attack


# --- 메인 전용 특성: 검기 파형(평타 사거리) — 단일 소스 (§3) ---
# GDD §5·§6 v1.9: **메인** 하위 직업의 특성만 발동한다(서브는 5스탯만 합산된다).
# 🔴 레벨로 자라지 않는 켜짐/꺼짐 값이라 LEVEL_STAT_KEYS 루프에 **얹지 않는다** — 얹으면 서브 가중(×0.4)이
#   곱해져 "메인 전용"이 조용히 깨지고, 레벨 곱까지 타 예산 밖 스탯이 레벨 스탯 상한 검증에 섞인다.
# 🔴 아래 사거리 3함수(is_hit_in_reach·attack_center_offset·attack_radius)는 **전부 이 함수를 지난다.**
#   haste_scale과 같은 이유다 — 배율 함수를 공유하는 것 자체가 "맞는 곳 = 보이는 곳" 계약의 증명이고,
#   한 곳이라도 job.attack_range를 직접 읽으면 파형이 판정과 표시 중 한쪽에만 걸린다.
const MAX_REACH_BONUS := 0.5  # 하드 상한 +50% (GDD §6) — 근접이 원거리가 되는 것 + 공지 스푸핑 차단


# --- 하위 직업 특성 카탈로그 (GDD v2.0 §6) — 단일 소스 (§3) ---
# 🔴 특성 = **(효과 키, 값)** 이다. 키마다 적용 지점이 **1곳**뿐이고, 새 하위 직업이 기존 키를
#   재사용하면 순수 데이터 한 장이다(rules §4). 키를 늘릴 때만 코드가 늘어난다.
# 와이어/데이터 공용 키 = 아래 문자열 **그대로**(SubJobDef.main/sub_trait_key · clamp 키).
#   LEVEL_STAT_KEYS와 같은 관용구 — 별도 매핑 표를 만들면 그게 두 번째 진실원이 되어 갈라진다.
# 🔒 여기 들어올 수 있는 것 = **합계 데미지에 곱해지지 않는 축**뿐이다(GDD §6 예산).
#   공격력·체력(장비 축)·공속·치명(5스탯 축)을 키로 추가하는 변경은 기획 변경이 선행 조건이다.
const TRAIT_KEYS: Array[String] = ["reach", "roll_cd", "roll_dist", "campfire_heal", "kill_move", "drop_find", "proj_range"]

# 키별 **하드 상한** — 같은 키를 메인·서브가 같이 밀면 합산된 뒤 여기서 잘린다.
# 🔴 상한을 두는 이유는 키마다 다르다(GDD §6에 근거를 남겼다):
#   reach — 무한이면 근접이 원거리가 되어 "직업 = 플레이 방식의 변환"이 무너진다(전사 42 → 63).
#   roll_cd — 🔴 **가장 인색하게 잡는다.** i-frame 창 0.37s(ROLL_TIME_S + GRACE) / 쿨 0.8s이라
#     **정직한 플레이의 무적 시간이 이미 46%**다. −30%면 0.56s 쿨 = 66%, −40%면 0.48s = 77%로
#     사실상 상시 무적이 되어 §5 "패턴을 읽고 구른다"가 "계속 구른다"가 된다.
#     ⚠ **호스트 게이트 기준으로는 더 높다** — `is_roll_grant_ok`가 지터 여유로 ×0.9를 곱하므로
#     연타하는 클라의 상한은 특성 0에서 370/720 = **51%**, −30%에서 370/504 = **73%**다.
#     (그 여유는 지연 환경에서 정당한 구르기를 거부하지 않기 위한 것 — 협동 2인이라 수용한다.
#      이 축을 더 열 때는 66%가 아니라 **73% 쪽 숫자**를 기준으로 봐라.)
#   나머지 — 자원·회복·기동이라 상한은 "데이터 실수와 공지 스푸핑 차단"이 목적이다.
const TRAIT_MAX: Dictionary = {
	"reach": MAX_REACH_BONUS,  # 평타 사거리 증가율
	"roll_cd": 0.3,            # 구르기 쿨다운 **감소**율 (0.3 = −30%)
	"roll_dist": 0.3,          # 구르기 거리 증가율 — 🔴 원격 변위 clamp도 같이 유도한다(§3 이동속도 계약)
	"campfire_heal": 0.6,      # 모닥불 회복 속도 증가율
	# 🔴 kill_move는 5스탯 `move`와 **같은 축이라 더해진 뒤 함께** LEVEL_STAT_MAX["move"](0.3)에서 잘린다
	#   (`player._move_speed`). 그래서 상한을 그 여유 안쪽으로 좁게 잡는다 — 넓게 잡으면 이속을 키운
	#   플레이어에게서 「광란」이 조용히 사라진다(표시는 +15%인데 실제 0). 이 부등식은
	#   test_game_state_auto의 트립와이어가 지킨다: 데이터 최대 move + 이 값 ≤ LEVEL_STAT_MAX["move"].
	#   ⚠ 별도 축으로 분리하고 싶으면 LAG_MAX_LEAD_DIST를 함께 재유도해야 한다(115 → ~150).
	"kill_move": 0.15,         # 적 처치 후 일시 이동속도 증가율
	"drop_find": 0.3,          # 골드·재료 드랍량 증가율
	# 투사체 사거리 증가율 — 근접 reach의 원거리 대칭(reach는 근접 3함수 전용이라 활·지팡이엔 안 걸린다).
	# 🔴 **상한 근거는 `MAX_ARROW_RANGE`(480)다** — 데이터상 최장 원거리 무기 iron_staff(arrow_range 260)가
	#   260 × 1.5 = 390 < 480이라 정당한 무기가 `clamp_arrow_range`에서 **조용히 절삭되지 않는다**.
	#   ⚠ 화면 해상도(640×360)에서 유도하지 마라 — GDD §9에서 아직 TBD라, 미확정 값이 판정 기하의 근거로
	#   승격된다. `test_combat_math_auto`가 이 부등식을 원거리 무기 전수로 지킨다(넘으면 빨개진다).
	# ⚠ 값이 MAX_REACH_BONUS와 같지만 **별칭으로 묶지 않는다** — 근거가 다른 축이라(근접은 "직업 = 플레이
	#   방식" 경계, 여기는 절삭 여유) 별칭으로 두면 한쪽 튜닝이 다른 쪽을 조용히 움직인다.
	"proj_range": 0.5,
}

const KILL_MOVE_TIME_S := 3.0  # 처치 후 이속 버프 지속(연출/손맛값 — §0 예외, 사용자가 조인다)


# 🔴 비율 보너스를 **정수 수량**에 적용하는 단일 소스 — 소수 잔량을 누적해 1 이상일 때만 올린다.
#   피흡(`combat_authority._leech_frac`)과 **같은 관용구**이고, 같은 이유로 필요하다:
#   드랍 수량이 1~2라 `round(1 × 1.15) = 1`이 되어 **+15%가 정확히 0**이 된다(리뷰 C1에서 실측).
#   반올림/절삭 어느 쪽도 작은 수량에서 비율을 죽인다 — 기댓값을 보존하려면 잔량을 들고 가야 한다.
# carry는 호출부(호스트)가 보관한다 — CombatMath는 상태를 안 쥔다(테스트 결정론).
static func accrue_bonus(base_qty: int, rate: float, carry: float) -> Dictionary:
	var c := carry if (is_finite(carry) and carry > 0.0) else 0.0
	if base_qty <= 0 or not is_finite(rate) or rate <= 0.0:
		return {"qty": base_qty, "carry": c}
	var total := c + float(base_qty) * rate
	var whole := int(floor(total))
	return {"qty": base_qty + whole, "carry": total - float(whole)}


# 특성 한 칸 clamp — 유한성 가드 먼저(JSON 1e999 → INF, clamp_level_stat과 같은 철학).
# 음수는 0 — 디버프 주입 차단. **모르는 키는 0**(TRAIT_MAX에 없으면 상한 0이라 자동 폐기).
static func clamp_trait(key: String, value: float) -> float:
	if not is_finite(value):
		return 0.0
	return clampf(value, 0.0, float(TRAIT_MAX.get(key, 0.0)))


# 특성 묶음 clamp — 🔴 **payload가 아니라 TRAIT_KEYS를 순회한다**(clamp_level_stats 관용구):
# 모르는 키는 자동 폐기되고, 빠진 키는 0.0으로 채워져 하류가 항등 폴백을 얻는다.
static func clamp_traits(traits: Dictionary) -> Dictionary:
	var out := {}
	for key: String in TRAIT_KEYS:
		out[key] = clamp_trait(key, float(traits.get(key, 0.0)))
	return out


# 빈 특성(전부 0) — 특성 없음/미공지 경로의 항등 폴백.
static func empty_traits() -> Dictionary:
	var out := {}
	for key: String in TRAIT_KEYS:
		out[key] = 0.0
	return out


# 🔴 UI 문구는 **여기서 파생**한다 — 훈련소 패널이 특성 설명을 하드코딩하면 값과 문구가 갈라져
#   "표시는 +30%인데 실제는 +10%"가 된다(rules §2 게이트가 요구한 것). 이름만 데이터(SubJobDef).
const TRAIT_LABEL: Dictionary = {
	"reach": "평타 사거리",
	"roll_cd": "구르기 쿨다운",
	"roll_dist": "구르기 거리",
	"campfire_heal": "모닥불 회복 속도",
	"kill_move": "처치 후 이동속도",
	"drop_find": "골드·재료 드랍",
	"proj_range": "투사체 사거리",  # 근접 "평타 사거리"(reach)와 문구로도 구분된다 — 두 축이 서로 안 걸린다
}
# 값이 클수록 "줄어드는" 축 — 부호를 뒤집어 표기한다(쿨다운 −15%).
const TRAIT_REDUCTION: Array[String] = ["roll_cd"]


static func trait_text(key: String, value: float) -> String:
	if key.is_empty() or not TRAIT_LABEL.has(key):
		return ""
	var v := clamp_trait(key, value)
	var sign_s := "−" if key in TRAIT_REDUCTION else "+"
	return "%s %s%d%%" % [str(TRAIT_LABEL[key]), sign_s, int(round(v * 100.0))]


# 유한성 가드 먼저(JSON 1e999 → INF, clamp_level_stat과 같은 철학). 음수는 0 — 사거리 디버프 주입 차단.
# 🔴 상한은 TRAIT_MAX["reach"] 하나에서 온다 — 사본을 만들면 특성 상한과 사거리 상한이 갈라진다.
static func clamp_reach(reach: float) -> float:
	return clamp_trait("reach", reach)


# reach = 그 피어가 공지한 메인 하위 직업에서 **호스트가 로컬 리졸브한** 특성값(peer_sync.peer_reach_bonus).
# 0 = 항등 = 특성 없음/도입 전과 완전히 동일.
static func effective_attack_range(job: JobDef, reach: float = 0.0) -> float:
	return job.attack_range * (1.0 + clamp_reach(reach))


# 호스트의 적중 요청 검증 — 공격자 위치 기준 사거리 내인가 (지연 감안 여유 배율).
# enemy_radius = 적 몸 반경 — 중심거리에서 빼 준다. 거대 보스(radius ~48)는 중심이 멀어
# "붙어도 사거리 밖"이 되므로 몸통 표면까지로 판정한다 (기본 0 = 기존 잔몹 동작 불변).
static func is_hit_in_reach(attacker_pos: Vector2, enemy_pos: Vector2, job: JobDef,
		enemy_radius: float = 0.0, reach: float = 0.0) -> bool:
	return attacker_pos.distance_to(enemy_pos) - enemy_radius <= effective_attack_range(job, reach) * 2.0


# 히트 기하 — 단일 소스 (§3). 실제 판정(원형 질의)과 공격 FX 위치가 같은 함수를 부른다.
# 한쪽만 조이면 "맞는 곳"과 "보이는 곳"이 어긋난다 — 손맛 튜닝은 반드시 여기서.
const ATTACK_CENTER_SCALE := 0.6  # 공격 중심까지의 거리 = range * 이 값
const ATTACK_RADIUS_SCALE := 0.5  # 판정 반경 = range * 이 값


static func attack_center_offset(dir: Vector2, job: JobDef, reach: float = 0.0) -> Vector2:
	return dir * (effective_attack_range(job, reach) * ATTACK_CENTER_SCALE)


static func attack_radius(job: JobDef, reach: float = 0.0) -> float:
	return effective_attack_range(job, reach) * ATTACK_RADIUS_SCALE


# 한 스윙이 여러 적을 치는 것은 허용하되(SAME_SWING_MS 안), 스윙 간격은 쿨다운(지터 여유 0.9배)을 강제.
# 앵커(last_confirm_msec)는 새 스윙에서만 갱신해야 한다 — 매 확정마다 갱신하면 창이 미끄러져 연사 스팸이 뚫린다.
const SAME_SWING_MS := 50
# 🔴 호스트 간격 게이트의 **지터 여유** — 요구 간격을 이 배율만큼 깎아 정직한 발사가 네트워크 지터로
#   거부되지 않게 한다. 근접 쿨다운·발사율·차지 시간·콤보 전진 **네 곳이 같은 값을 쓴다**: 여유를
#   따로 두면 한쪽만 조였을 때 "어떤 공격은 관대하고 어떤 공격은 오탐 거부"가 되고, 그건 화면에
#   "가끔 공격이 씹힌다"로만 보인다. 조일 땐 여기 한 곳.
const FIRE_RATE_SLACK := 0.9


# haste = 그 피어가 공지한(그리고 호스트가 clamp한) 공격속도 보너스 — 0 = 항등(성장축 도입 전과 동일).
static func is_hit_cooldown_ok(last_confirm_msec: int, now_msec: int, job: JobDef, haste: float = 0.0) -> bool:
	var dt := now_msec - last_confirm_msec
	return dt <= SAME_SWING_MS or dt >= int(effective_cooldown(job, haste) * FIRE_RATE_SLACK * 1000.0)


# 구르기 타이밍 — 단일 소스 (§3). 로컬 이동(player)과 호스트 i-frame 검증이 같은 값을 읽는다.
# player.gd에 사본을 남기면 첫 손맛 튜닝에서 구르기 거리와 무적 창이 갈라진다.
# ⚠ 애니 미러: assets/sprites/player/*_frames.tres의 roll(4프레임/speed 16 = 0.25s)이 이 값과 맞물린다.
#   ROLL_TIME_S를 바꾸면 3개 .tres의 roll speed도 같이 조정할 것 (애니가 짧으면 마지막 프레임에 얼어붙는다).
const ROLL_TIME_S := 0.25
const ROLL_COOLDOWN_S := 0.8
const ROLL_IFRAME_GRACE_MS := 120  # 지연 여유 — 사거리 검증 2.0배 완충과 같은 철학
# 구르기 이동 배율 — 로컬 이동·원격 변위 clamp·LAG_MAX_LEAD_DIST 유도가 **전부 이 상수 하나**를 읽는다.
# (player.gd에 있던 것을 v2.0에서 여기로 이사: roll_dist 특성이 붙으면서 세 곳의 유도가 갈라질 자리가 됐다.)
const ROLL_SPEED_MULT := 2.6


# 유효 구르기 쿨다운 — roll_cd 특성(0.15 = −15%)만큼 짧아진다. 0 = 항등(특성 도입 전과 동일).
# 🔴 로컬 쿨(player)과 호스트 그랜트 검증이 **같은 함수**를 지난다 — 사본을 만들면 게스트가
#   "내 화면에선 굴러지는데 무적이 안 걸리는" 상태가 되고, 그건 화면에 이유가 안 드러난다.
static func effective_roll_cooldown(roll_cd: float = 0.0) -> float:
	return ROLL_COOLDOWN_S * (1.0 - clamp_trait("roll_cd", roll_cd))


# 유효 구르기 속도 — roll_dist 특성만큼 빨라진다(= ROLL_TIME_S가 고정이므로 곧 거리 증가).
# 🔴 로컬 이동·원격 변위 clamp가 같은 유도식을 쓴다(§3 이동속도 계약과 같은 이유) —
#   원격 clamp만 기본값으로 남기면 정당하게 길어진 구르기가 깎여 외삽이 과소평가되고,
#   2026-07-24에 고친 "피했는데 맞았다"가 roll_dist 보유자에게 부분 재발한다.
static func effective_roll_speed(base_move_speed: float, roll_dist: float = 0.0) -> float:
	return base_move_speed * ROLL_SPEED_MULT * (1.0 + clamp_trait("roll_dist", roll_dist))


# 호스트의 구르기 그랜트 검증 — 쿨다운(지터 여유 0.9배) 강제. 스팸해도 정직한 구르기 이상의 무적을 못 얻는다.
# roll_cd = 그 피어가 공지한 하위 직업에서 **호스트가 로컬 리졸브한** 특성값(peer_sync.peer_traits).
static func is_roll_grant_ok(last_grant_msec: int, now_msec: int, roll_cd: float = 0.0) -> bool:
	return now_msec - last_grant_msec >= int(effective_roll_cooldown(roll_cd) * 0.9 * 1000.0)


# 그랜트된 i-frame 창이 현재 유효한가 (호스트가 데미지 확정 직전에 조회).
static func is_iframe_active(grant_msec: int, now_msec: int) -> bool:
	return now_msec - grant_msec <= int(ROLL_TIME_S * 1000.0) + ROLL_IFRAME_GRACE_MS


# 투사체(궁수 화살) 단일 소스 (§3, 2026-07-24). 화살은 결정론적 직선 등속 —
# 각 클라 표시 화살과 호스트 권한 화살이 같은 속도/사거리 상수를 읽어야 위치가 일치한다("맞는 곳=보이는 곳").
# 속도·사거리·굵기는 손맛/도달 튜닝값(§0 예외 — 사용자가 조인다). 무기별로 갈라야 하면 나중에 EquipDef로 이관.
const ARROW_SPEED := 420.0        # 화살 이동 속도(px/s) — 표시·호스트 공용(결정론 필수)
const DEFAULT_ARROW_RANGE := 360.0  # 무기 미지정 시 사거리 폴백(px). 무기별 실값 = EquipDef.arrow_range
const MAX_ARROW_RANGE := 480.0    # 사거리 상한 — 호스트가 게스트 전송값을 이 이상으로 못 쓰게 clamp(§3 신뢰 경계). ⚠ 정당 무기도 이 이상은 조용히 잘림 — 신규 활 EquipDef.arrow_range는 이 값 이하 유지
const MIN_ARROW_RANGE := 40.0     # 사거리 하한 — 0/음수 전송으로 화살이 즉시 소멸하는 것 방지
const ARROW_HIT_RADIUS := 6.0     # 화살 굵기(px) — 명중 반경 = ARROW_HIT_RADIUS + 적 body_radius
# ⚠ 터널링 불변식(§5): 프레임당 전진(ARROW_SPEED/60 ≈ 7px) < 최소 명중 지름(2×(ARROW_HIT_RADIUS+min body_radius)).
#   EnemyDef.body_radius 기본 6 → 최소 지름 24px ≫ 7px라 프레임 사이 관통 없음. ARROW_SPEED를 크게 올리거나
#   body_radius 0인 적을 넣으면 이 부등식이 깨진다 — 그땐 스텝을 세그먼트로 쪼개 질의할 것.
const SHOT_ORIGIN_TOL := 44.0     # 발사 원점 허용 오차(px) — 발사자 net_anchor에서 이보다 멀면 스푸핑으로 거부.
# MUZZLE_OFFSET(26, 화살이 몸 밖에서 나가게) + 발사~마지막 수신 좌표 사이 이동·지연 여유(~18px). ⚠ 수용된 한계
#   (G_ROLL 그랜트 창과 같은 성격): 조작 클라가 원점을 적 쪽으로 최대 ~18px 당기는 미세 이득은 막지 않는다(2인 협동 실익 낮음).


# 전송받은 사거리를 안전 범위로 clamp — 호스트가 게스트 G_SHOOT의 "r"에 적용(스푸핑 상한, §3 신뢰 경계). G_STATS clamp 미러.
# ⚠ NaN 가드 먼저: clampf(NAN,…)는 NaN을 그대로 반환 → life=NaN → 수명 만료 안 되는 무한 화살(누수). dir is_finite 가드와 대칭.
static func clamp_arrow_range(arrow_range: float) -> float:
	if not is_finite(arrow_range):
		return DEFAULT_ARROW_RANGE
	return clampf(arrow_range, MIN_ARROW_RANGE, MAX_ARROW_RANGE)


# 화살 수명(s) = 사거리/속도. 사거리는 무기별(EquipDef.arrow_range) — 표시·권한이 같은 값을 받아 결정론 유지("맞는 곳=보이는 곳").
static func arrow_lifetime_s(arrow_range: float = DEFAULT_ARROW_RANGE) -> float:
	return clamp_arrow_range(arrow_range) / ARROW_SPEED


# 투사체 속도 clamp — 무기별 탄속(EquipDef.projectile_speed, 0 = 기본 화살 속도)의 유일한 진입점.
# ⚠ 터널링 불변식(위): 상한을 올리면 프레임당 전진 > 최소 명중 지름이 될 수 있다 — MAX는 그 여유 안에서 고른 값.
const MIN_PROJECTILE_SPEED := 60.0
const MAX_PROJECTILE_SPEED := 600.0


static func clamp_projectile_speed(speed: float) -> float:
	if not is_finite(speed) or speed <= 0.0:
		return ARROW_SPEED  # 미지정(0)·오염값 = 기본 화살 속도
	return clampf(speed, MIN_PROJECTILE_SPEED, MAX_PROJECTILE_SPEED)


# 🔴 그 무기가 **탄을 쏠 수 있는가** — 호스트의 G_SHOOT 신뢰 경계 (2026-07-27 netreview M4).
#   `EquipDef.motion_type`의 발사형 판정을 여기 한 곳에 모은다: `player._local_combat`의 모션 분기와
#   호스트의 발사 수락이 같은 기준을 써야 "로컬은 못 쏘는데 호스트는 받아준다"가 안 생긴다.
# ⚠ **null은 false다** — 다만 호출부는 null을 **거부하지 않는다.** null = "G_STATS 미도착" 정상 창이고,
#   그 창의 폴백(기본 화살)은 의도된 동작이다. 거부 대상은 **리졸브에 성공했는데 발사형이 아닌** 무기다.
# 🔴 왜 필요한가: `EquipDef.arrow_range` 기본값이 DEFAULT_ARROW_RANGE(360)이고 근접 무기 `.tres`엔
#   그 필드가 아예 없다 — 즉 대검을 공지한 채 G_SHOOT을 쏘면 호스트가 **360px 권한 화살**을 등록하고
#   전사 공격력으로 확정한다. 활 사거리를 150으로 내린 뒤로는 그 사칭 화살이 궁수의 정당한
#   마무리 타(300/306px)보다도 **멀리** 나간다.
static func is_projectile_weapon(equip: EquipDef) -> bool:
	return equip != null and (equip.motion_type == "shoot" or equip.motion_type == "charge")


# 유효 투사체 사거리 — proj_range 특성 + 콤보 타별 배율만큼 길어진다. 둘 다 기본값(0 / 1.0)이면
# **도입 전과 완전 항등**이다.
# 🔴 근접의 effective_attack_range와 같은 자리다: 표시(ArrowField)와 판정(CombatAuthority)이 **같은
#   함수**를 지나야 "맞는 곳 = 보이는 곳"이 유지된다. 유일한 호출부는 GameState.projectile_params
#   하나이고(사거리를 거기서만 리졸브한다), 사본을 만들면 표시 탄과 권한 탄의 수명이 갈라진다.
# 🔴 결과는 그대로 projectile_lifetime_s → clamp_arrow_range(MAX_ARROW_RANGE)를 지난다 — **순서를
#   바꿔 clamp를 우회하지 마라**(심층 방어: 데이터가 커져도 상한 밖으로는 못 나간다). 비유한 base도
#   여기서 판단하지 않고 그 clamp가 DEFAULT로 떨어뜨린다(판단 지점을 늘리지 않는다).
# proj_range = 그 피어가 공지한 하위 직업에서 **각 클라가 로컬 리졸브한** 특성값(player.trait_value).
# combo_mult = 그 타의 사거리 배율(combo_range_mult_at) — **호스트가 센 타수**로 리졸브한다(아래 콤보 절).
static func effective_projectile_range(base_range: float, proj_range: float = 0.0,
		combo_mult: float = 1.0) -> float:
	return base_range * (1.0 + clamp_trait("proj_range", proj_range)) * clamp_combo_mult(combo_mult)


# --- 평타 콤보 (궁수 "평·평·쭉") 단일 소스 (§3, 2026-07-27) ---
#
# 🔴 **리듬은 무기가 정한다** — 값은 전부 `EquipDef.combo_*`(장비 축)에서 온다. 특성 축에 두면
#   GDD §6 🔒("특성은 합계 데미지에 곱해지지 않는 축만")을 어긴다. 여기 함수들은 그 데이터를 읽는
#   **유일한 창구**다: 로컬 입력(player)·표시(arrow_field)·호스트 판정(combat_authority)이 전부
#   이 함수만 지나야 "맞는 곳 = 보이는 곳"과 "클라 리듬 = 호스트가 인정하는 리듬"이 함께 유지된다.
# 🔴 **네트워크로 오가는 것은 타수(정수) 하나뿐**이다(G_SHOOT "cb") — 배율·뜸은 각자 로컬 .tres에서
#   리졸브한다. 차지 레벨(G_SHOOT "c")과 정확히 같은 철학이다: 수치를 전송하면 그게 곧 스푸핑 표면.
const MAX_COMBO_LEN := 8        # 콤보 길이 상한 — 데이터 실수(거대 배열)가 인덱스 산술을 오염시키지 않게
const MAX_COMBO_MULT := 4.0     # 타별 배율 하드 상한 — 데이터 오타(100.0)가 100배 데미지가 되지 않게
# 그 타를 치고 다음 타로 **이어지는** 여유(s). 이보다 더 쉬면 콤보가 처음으로 돌아간다.
# 🔴 유도 = **전사 근접 콤보와 같은 총 창**(2026-07-27 netreview M3). 전사는 쿨다운 0.4 +
#   `player.COMBO_WINDOW` 0.55 = **0.95s** 안에 다시 치면 이어진다. 궁수도 0.15 + 0.8 = **0.95s**.
#   🔴 첫 값(0.45)은 총 0.60s라 훨씬 좁았고, **활은 홀드 연사가 아니라 클릭 1회 = 1발**이라
#   조준하거나 굴렀다가 다시 쏘는 흔한 페이스(0.7s+)에서 콤보가 매번 리셋돼 **"쭉"이 영영 안 나왔다.**
#   두 무기의 창이 갈라질 이유가 없다 — 리듬 느낌은 뜸(`combo_delay`)이 만들지 창이 만들지 않는다.
# ⚠ 손맛값(§0 예외 — 사용자가 조인다)이지만 **호스트 판정에도 쓰인다**(로컬·호스트가 같은 창을 봐야
#   타수가 안 갈라진다). 그래서 player.gd의 근접 COMBO_WINDOW와 달리 여기 산다.
const COMBO_GRACE_S := 0.8


# 그 무기의 콤보 길이 — 세 배열 중 **가장 긴 것**. 전부 비면 1(= 콤보 없음, 항등).
# 한 축만 채워도 되게 max를 쓴다(길이를 손으로 맞추게 하면 다음 사람이 반드시 어긋나게 적는다).
static func combo_len(equip: EquipDef) -> int:
	if equip == null:
		return 1
	var n := maxi(equip.combo_range_mult.size(),
		maxi(equip.combo_damage_mult.size(), equip.combo_delay.size()))
	return clampi(n, 1, MAX_COMBO_LEN)


static func clamp_combo_index(index: int, equip: EquipDef) -> int:
	return clampi(index, 0, combo_len(equip) - 1)


# 배율 clamp — 비유한/0 이하는 **1.0(항등)** 으로 떨어뜨린다. "데이터가 비었다"와 "데이터가 깨졌다"를
# 같은 안전값으로 모으는 것이 규약이다(clamp_projectile_speed와 같은 관용구).
static func clamp_combo_mult(mult: float) -> float:
	if not is_finite(mult) or mult <= 0.0:
		return 1.0
	return minf(mult, MAX_COMBO_MULT)


static func combo_range_mult_at(equip: EquipDef, index: int) -> float:
	return _combo_arr_at(equip.combo_range_mult if equip != null else PackedFloat32Array(), index)


static func combo_damage_mult_at(equip: EquipDef, index: int) -> float:
	return _combo_arr_at(equip.combo_damage_mult if equip != null else PackedFloat32Array(), index)


static func _combo_arr_at(arr: PackedFloat32Array, index: int) -> float:
	if index < 0 or index >= arr.size():
		return 1.0  # 배열이 짧으면(한 축만 채운 무기) 그 타는 항등
	return clamp_combo_mult(arr[index])


# 그 타 **직전**의 추가 뜸(s). 배열 밖·비유한·음수는 0(뜸 없음).
# ⚠ 상한은 COMBO_GRACE_S가 아니라 창 유도식(combo_window_s)이 흡수한다 — 뜸이 길어지면 창도 같이 길어진다.
static func combo_delay_at(equip: EquipDef, index: int) -> float:
	if equip == null or index < 0 or index >= equip.combo_delay.size():
		return 0.0
	var d := equip.combo_delay[index]
	if not is_finite(d) or d <= 0.0:
		return 0.0
	return d


# 🔴 그 타를 치기 위한 **최소 간격**(s) = 직업 쿨다운 + 그 타의 뜸, 둘 다 haste로 짧아진다.
#   뜸에도 haste_scale을 곱하는 이유는 쿨다운·스윙 창·차지 스텝과 같다(§3 haste 계약) — 안 곱하면
#   공속을 올릴수록 리듬이 뜸에 지배돼 궁수에게 공속이 무가치해진다.
# 로컬(player가 _attack_cd_left에 심는 값)과 호스트 판정(advance_combo)이 **같은 함수**를 지난다.
static func combo_gap_s(job: JobDef, equip: EquipDef, index: int, haste: float = 0.0) -> float:
	return (job.attack_cooldown + combo_delay_at(equip, index)) * haste_scale(haste)


# 콤보가 이어지는 창(s) — 이보다 더 쉬면 처음(0타)으로 돌아간다.
# 🔴 **gap에서 유도한다(독립 상수 금지)** — `window = gap + GRACE > gap > min_gap`이 항상 성립해야
#   "너무 빨라서 리셋"과 "너무 쉬어서 리셋" 두 조건이 겹치지 않는다. 겹치면 어떤 데이터에서는
#   정직한 발사가 **어느 쪽으로도 콤보를 못 잇는** 죽은 구간이 생긴다(에러 없이 3타가 영영 안 나온다).
static func combo_window_s(job: JobDef, equip: EquipDef, index: int, haste: float = 0.0) -> float:
	return combo_gap_s(job, equip, index, haste) + COMBO_GRACE_S


# 🔴 호스트가 그 타를 **인정하는 최소 간격**(s) — `combo_gap_s`(클라가 실제로 내는 간격)보다 관대하다.
#
# 왜 따로 있나: 호스트가 재는 것은 **자기 수신 시각의 차**이지 상대가 쏜 시각의 차가 아니다.
#   연속 두 G_SHOOT의 편도 지연이 다르면(앞 패킷이 더 늦게 도착하면) 측정 간격이 **실제보다 짧아** 보이고,
#   그러면 뜸을 정직하게 낸 궁수가 마무리 타를 못 받는다 — 발사가 사라지는 것보단 낫지만
#   "가끔 강화살이 안 나온다"가 되고 원인이 화면에 안 드러난다. 관대한 쪽으로 틀리는 것이 안전한 방향이다.
#
# 🔴 유도식 (독립 상수를 두지 않는다 — 전부 기존 값에서 나온다):
#     min_gap(i) = (attack_cooldown × FIRE_RATE_SLACK + max(0, delay_i − LAG_MAX_ONE_WAY_MS)) × haste_scale
#   ⑴ **기본 쿨다운분은 기존 관용구 그대로**(×FIRE_RATE_SLACK) — `is_fire_rate_ok`가 이미 그 값으로
#      게이트하고 있으므로, 여기서 더 조이면 그 게이트를 통과한 발사를 두 번째 잣대로 다시 재는 셈이 된다.
#   ⑵ **뜸(추가분)에서는 `LAG_MAX_ONE_WAY_MS`(200ms)를 통째로 깎는다.** 그 상수가 이 프로젝트가
#      선언한 "편도 지연 인정 상한"이고, 측정 간격이 실제보다 짧아질 수 있는 양의 상한이 바로
#      앞 패킷의 편도 지연이다(= 최악 200ms). 즉 **전송이 삼킬 수 있다고 우리가 이미 인정한 만큼**을
#      정직한 플레이어에게 돌려준다. 이보다 좁게 잡을 근거가 이 코드베이스 안에 없다.
#   ⚠ **delay ≤ LAG_MAX_ONE_WAY_MS면 뜸분이 0이 되어 게이트가 `is_fire_rate_ok`와 같아진다** — 즉
#      "전송 불확실성보다 작은 뜸은 호스트가 검증할 수 없다"를 그대로 인정하는 것이다(있는 척하지 않는다).
#      그 무기는 마무리 타를 사실상 공짜로 준다 → `test_combat_math_auto`가 **무기별로** 그 상태를
#      단정해 빨개진다("최속 스팸이 마무리 타에 도달"). 조용한 절벽을 시끄럽게 만든 것이다.
#
# ⚠ 이 게이트는 **리듬 확인이지 치트 방지 원장이 아니다.** 조작 클라는 여기까지만 앞당길 수 있고
#   (현 데이터에서 마무리 타 0.40s → 0.185s), 그 상한은 여전히 `is_fire_rate_ok`가 잡는다.
#   협동 2인·PvP 없음이라 수용한다(rules §2 4인/PvP 게이트에서 재검토).
static func combo_min_gap_s(job: JobDef, equip: EquipDef, index: int, haste: float = 0.0) -> float:
	var extra := maxf(0.0, combo_delay_at(equip, index) - LAG_MAX_ONE_WAY_MS / 1000.0)
	return (job.attack_cooldown * FIRE_RATE_SLACK + extra) * haste_scale(haste)


# 🔴 다음 콤보 타수 — 로컬(player)과 호스트 판정(combat_authority)이 **같은 함수**를 지난다(§3).
#   elapsed_s = 직전 발사로부터의 경과. 클라는 자기 발사 시각, 호스트는 자기 수신 시각으로 잰다.
# 규칙은 셋뿐이다:
#   ⑴ 콤보 없는 무기(길이 1) → 항상 0 (법사 지팡이 = 도입 전과 항등)
#   ⑵ 너무 **쉬었으면**(> window) 처음부터 — 리듬이 끊긴 것
#   ⑶ 🔴 너무 **빨랐으면**(< combo_min_gap_s) 처음부터 — **뜸을 내지 않은 자는 다음 타를 못 얻는다**
#      ⚠ 기준이 `combo_gap_s`가 아니라 **`combo_min_gap_s`**(관대한 하한)인 것이 핵심이다 —
#        호스트는 자기 수신 간격으로 재므로 지터가 정직한 간격을 짧아 보이게 만들 수 있다(그 함수 주석).
# 🔴 ⑶이 "발사 거부"가 아니라 "리셋"인 것이 계약의 핵심이다. 거부로 만들면 호스트/클라의 타수가
#   창 경계 지터로 한 번 어긋났을 때 **정당한 발사가 통째로 사라진다**(화살이 안 생기고 이유가 화면에
#   안 드러난다 — 이 프로젝트가 반복해 겪은 "조용히 깨진다" 부류). 리셋이면 최악이 "이번 타는 평타"다.
#   그러면서 방어력은 더 세다: 쿨다운만 지키며 스팸하는 조작 클라는 index가 0↔1만 오가 **마무리 타에
#   영영 도달하지 못한다**(뜸이 곧 마무리 타의 대가라는 설계 그대로).
static func advance_combo(prev_index: int, elapsed_s: float, job: JobDef, equip: EquipDef,
		haste: float = 0.0) -> int:
	var n := combo_len(equip)
	if n <= 1 or job == null:
		return 0
	if not is_finite(elapsed_s):
		return 0
	var nxt := (clampi(prev_index, 0, n - 1) + 1) % n
	if elapsed_s < combo_min_gap_s(job, equip, nxt, haste) \
			or elapsed_s > combo_window_s(job, equip, nxt, haste):
		return 0
	return nxt


# 🔴 **판정에 쓰는 콤보 타수 = 이 함수 하나**(호스트 전용, §3 신뢰 경계).
#   claimed = G_SHOOT "cb"(발신자 주장, 표시용) · prev_index = 호스트가 그 피어에게 마지막으로 인정한 타수.
# 🔴 호스트는 주장을 **믿지 않고 직접 센다** — 안 그러면 클라가 매 발사에 "나 마무리 타야"라고 주장해
#   항상 강화살(사거리 2배·데미지 2.5배)을 얻는다. 근접 콤보(G_ATK "cb")가 궤적만 정해 조작돼도 화면만
#   달라졌던 것과 **성격이 다르다** — 여기 타수는 사거리·데미지를 바꾸므로 신뢰 경계가 새로 생긴다.
# 🔴 주장을 **상한으로만** 쓴다(min): 호스트가 센 값보다 크게는 못 가고, 작게 주장하면 자기 손해다.
#
# 🔴 **규약 — "화면에 없는데 맞는" 방향은 구조적으로 불가능해야 한다** (2026-07-27 리드 승격).
#   표시(ArrowField)는 발신자 주장 타수를 그대로 그리므로 `min` 덕에 **판정 ≤ 표시**가 항상 성립한다.
#   min이 없으면 창 경계 지터에서 **화면엔 짧은 화살인데 판정은 300px 밖 적을 죽이는** 방향이 열린다.
#   있으면 갈라짐은 항상 "그려졌는데 안 맞는다"(빗나감으로 읽히는 쪽)로만 떨어진다.
#   같은 규약의 다른 구현이 이미 둘 있다 — 보스 텔레그래프는 경계 여유를 격자에서 유도해 **틀리면 반드시
#   과예고 방향**으로 고정했고(rules §3), `projectile_params`의 `w`(무기 사칭)는 사칭자 화면에만
#   폭발을 그린다. **새 표시/판정 쌍을 만들 때 이 부등호의 방향부터 정해라.**
static func authoritative_combo(claimed: int, prev_index: int, elapsed_s: float,
		job: JobDef, equip: EquipDef, haste: float = 0.0) -> int:
	var counted := advance_combo(prev_index, elapsed_s, job, equip, haste)
	return mini(clamp_combo_index(claimed, equip), counted)


# 투사체 수명(s) = clamp(사거리)/clamp(속도). arrow_lifetime_s의 일반화 —
# 무기별 탄속이 갈리는 charge 무기(느린 마법탄)도 표시·권한이 같은 값을 리졸브해 결정론 유지.
static func projectile_lifetime_s(travel_range: float, speed: float) -> float:
	return clamp_arrow_range(travel_range) / clamp_projectile_speed(speed)


# --- 차지 발사(법사 지팡이) 단일 소스 (§3, 2026-07-24) ---
# 마우스를 눌러 모은 단계(0~MAX)만큼 위력·폭발 반경이 커진다. 단계 배율은 여기 공용 상수 —
# 네트워크로는 "레벨(정수)"만 오가고(G_SHOOT "c"), 실제 수치는 각 클라·호스트가 이 표에서 리졸브한다.
# (배율 자체를 전송하면 스푸핑 표면이 된다 — 궁수 r clamp 철학과 동일.)
const MAX_CHARGE_LEVEL := 3
const CHARGE_DAMAGE_MULT: Array[float] = [1.0, 1.7, 2.5, 3.4]   # 레벨별 데미지 배율 (0 = 탭 발사)
const CHARGE_RADIUS_MULT: Array[float] = [1.0, 1.45, 1.9, 2.4]  # 레벨별 폭발 반경 배율
const CHARGE_ORB_SCALE: Array[float] = [0.6, 0.85, 1.1, 1.4]    # 레벨별 탄/차지 오브 표시 스케일 (표시 전용 — 반경 미러 아님)
const MAX_BLAST_RADIUS := 140.0  # 폭발 반경 상한 — 게스트 주장 무기(w)가 어떤 값이든 이 이상으로는 안 터진다(§3 신뢰 경계)


static func clamp_charge_level(level: int) -> int:
	return clampi(level, 0, MAX_CHARGE_LEVEL)


# 홀드 시간 → 차지 레벨. step_time이 0/음수/비유한이면 차지 불가(레벨 0) — 데이터 오염 가드.
static func charge_level_for(held_s: float, step_time: float) -> int:
	if not (is_finite(held_s) and is_finite(step_time)) or step_time <= 0.0 or held_s <= 0.0:
		return 0
	return clamp_charge_level(int(held_s / step_time))


# 차지 데미지 = 기본 데미지(calc_damage) × 레벨 배율. UI 표시와 호스트 확정이 같은 함수.
static func charge_damage(base_damage: int, level: int) -> int:
	return int(round(float(base_damage) * CHARGE_DAMAGE_MULT[clamp_charge_level(level)]))


# 폭발 반경 = 무기 기준 반경 × 레벨 배율 (상한 clamp). 호스트 판정 반경 = 표시 FX 스케일 기준 —
# 한쪽만 고치면 "맞는 곳"과 "보이는 곳"이 어긋난다 (§3, is_strike_hit·telegraph와 같은 철학).
static func charge_blast_radius(base_radius: float, level: int) -> float:
	if not is_finite(base_radius) or base_radius <= 0.0:
		return 0.0  # 폭발 없는 무기(일반 화살) — 단일 명중
	return minf(base_radius * CHARGE_RADIUS_MULT[clamp_charge_level(level)], MAX_BLAST_RADIUS)


# 폭발 명중 판정 — 폭발 중심에서 반경 안의 적/대상 전부. is_strike_hit 재사용(같은 거리 질의, 단일 소스).
static func is_blast_hit(target_pos: Vector2, blast_center: Vector2, radius: float, target_radius: float = 0.0) -> bool:
	return is_strike_hit(target_pos, blast_center, radius + target_radius)


# 호스트의 차지 레벨 검증 — 주장한 레벨만큼 실제로 모을 시간이 있었는가 (마지막 발사 이후 경과 기준).
# 연사하며 항상 c=MAX를 주장하는 스푸핑을 막는다 (is_fire_rate_ok의 차지 버전 — 지터 여유 0.9배 동일).
# ⚠ 첫 발사(last_shot 미기록)는 통과 — 입장 후 충분히 모을 시간이 있었다고 본다.
static func is_charge_time_ok(last_shot_msec: int, now_msec: int, level: int, step_time: float,
		haste: float = 0.0) -> bool:
	var lv := clamp_charge_level(level)
	if lv <= 0:
		return true
	if not is_finite(step_time) or step_time <= 0.0:
		return false  # 차지 못 하는 무기인데 레벨을 주장 = 거부
	# 차지 단계 시간도 공속으로 짧아진다(사용자 확정 2026-07-25) — 안 그러면 리듬이 차지에 지배되는
	# 법사에게 공속이 무가치해진다. 검증도 같은 배율을 써야 빨라진 정당 차지가 거부되지 않는다.
	var step := effective_charge_step(step_time, haste)
	return now_msec - last_shot_msec >= int(float(lv) * step * FIRE_RATE_SLACK * 1000.0)


# 화살 명중 판정 — 호스트만. 화살 현재 위치와 적 중심 거리 <= 화살굵기+적반경.
# is_strike_hit 재사용(같은 거리 질의) — 물리 레이어 대신 매 프레임 거리 질의라 물리 레이어 함정(§5) 회피 + 단위 테스트 가능.
static func is_arrow_hit(arrow_pos: Vector2, enemy_pos: Vector2, enemy_radius: float = 0.0) -> bool:
	return is_strike_hit(arrow_pos, enemy_pos, ARROW_HIT_RADIUS + enemy_radius)


# 호스트의 발사 쿨다운 검증 — 발사 간격은 공격자 job 쿨다운(지터 여유 0.9배) 강제. 스팸해도 정직한 발사율 이상 못 얻는다.
# 근접의 is_hit_cooldown_ok와 달리 SAME_SWING 다중타격 허용이 없다 — 화살 하나=한 발이라 매 발사 독립 게이트.
static func is_fire_rate_ok(last_shot_msec: int, now_msec: int, job: JobDef, haste: float = 0.0) -> bool:
	return now_msec - last_shot_msec >= int(effective_cooldown(job, haste) * FIRE_RATE_SLACK * 1000.0)


# 호스트의 발사 원점 검증 — 원점이 발사자 net_anchor 근처인가 (순간이동 원점 스푸핑 완화, §3 신뢰 경계).
static func is_shot_origin_ok(shooter_anchor: Vector2, origin: Vector2) -> bool:
	return shooter_anchor.distance_to(origin) <= SHOT_ORIGIN_TOL


# 잔몹 타격 판정 — 단일 소스 (§3). 호스트 판정과 텔레그래프 표시가 같은 반경(def.strike_radius)을 읽는다.
static func is_strike_hit(player_pos: Vector2, strike_center: Vector2, strike_radius: float) -> bool:
	return player_pos.distance_to(strike_center) <= strike_radius


# 부채꼴 판정 — 단일 소스 (§3, 보스전 2026-07-23). 보스 평타/전방 분사 등 전방 원뿔형 공격.
# apex = 부채꼴 꼭짓점(보스 중심), facing = 향한 각(rad), half_angle = 반각(rad), radius = 사거리.
# 판정 각/반경 = 텔레그래프 표시(부채꼴 텍스처 스케일·회전)와 같은 값 — "맞는 곳=보이는 곳".
static func is_hit_in_cone(pt: Vector2, apex: Vector2, facing: float, half_angle: float, radius: float) -> bool:
	var to_pt := pt - apex
	var dist := to_pt.length()
	if dist > radius:
		return false
	if dist < 0.01:
		return true  # 꼭짓점 위 = 안쪽 (각 계산 무의미)
	return absf(angle_difference(facing, to_pt.angle())) <= half_angle


# --- 지연 보상 (2026-07-24) — 단일 소스 (§3). "피했는데 맞았다"를 없애는 계약. ---
#
# 문제: 호스트 권한 모델에서 게스트만 구조적으로 손해본다 (실측 2026-07-24, RTT 83~207ms).
#   ⑴ 호스트가 예고를 띄운 순간 → 게스트 화면에 뜨기까지 **편도 지연**만큼 늦다.
#   ⑵ 호스트가 타격을 판정할 때 아는 게스트 좌표는 **편도 지연 + 송신 주기**만큼 과거다.
#   합쳐서 게스트의 실효 회피 창 = telegraph_s − (왕복 + 송신주기). RTT 207ms일 때 0.6s → 0.36s(40% 손실).
#   호스트는 둘 다 0이라 손실이 없다 — 그래서 "호스트는 괜찮은데 게스트만 맞는" 비대칭이 생긴다.
#
# 해법 두 축 (둘 다 호스트에서만 계산 — 게스트 코드에 상태 확정은 없다, §1):
#   ⓐ **STRIKE 지연**(`strike_delay_s`): 예고 타격 시각을 원격 피어 편도 지연만큼 늦춘다 → ⑴ 상쇄.
#      게스트는 자기 화면 기준 온전한 telegraph_s를 갖고, 호스트는 예고가 그만큼 길어져 공평해진다.
#   ⓑ **위치 외삽 + 방어자 우대**(`lag_lead_s`·`extrapolate`·`is_strike_hit_lagged`): 판정 시 게스트의
#      "지금" 위치를 마지막 관측 속도로 추정하고, **낡은 좌표와 추정 좌표가 둘 다 맞아야** 확정 → ⑵ 상쇄.
#
# 🔴 왜 "둘 다"인가 (핵심 설계): 외삽은 방향 전환 순간에 틀린다 — 한쪽만 믿으면 새 오탐이 생긴다.
#   둘 다 요구하면 오차가 **항상 방어자에게 유리한 쪽**으로만 떨어진다:
#     빠져나가는 중 → 추정 좌표가 밖 → 안 맞음 (게스트 화면과 일치 = 고치려던 그 버그)
#     들어오는 중   → 낡은 좌표가 밖 → 안 맞음 (관대 — 협동 게임이라 무해)
#     계속 안       → 둘 다 안 → 맞음 (정상)
#   PvP가 생기면 이 관대함이 표면이 된다 → rules §2 4인/PvP 게이트에서 재검토.
const LAG_MAX_ONE_WAY_MS := 200.0   # 편도 지연 인정 상한 — 조작 피어가 큰 RTT를 주장해 보스 예고를
                                    # 무한 지연시키거나 외삽을 뻥튀기하는 것 차단 (신뢰 경계 §3)
const LAG_MAX_LEAD_DIST := 115.0    # 외삽 거리 상한(px) — 지연 스파이크 한 번이 판정을 화면 밖으로 날리지 않게.
# 🔴 유도식(조립축 2026-07-26 재산정): 최고 이속 × 최대 구르기 배율 × 최대 lead
#   = (110 × (1+LEVEL_STAT_MAX["move"]=0.3)) × (2.6 × (1+TRAIT_MAX["roll_dist"]=0.3))
#     × (LAG_MAX_ONE_WAY_MS 0.2s + 송신주기 1/30s) ≈ 113px → 115.
#   ⚠ **roll_dist 특성이 구르기 배율을 키우므로 여기가 같이 커진다** — 안 키우면 정당하게 길어진
#   구르기가 외삽에서 과소평가돼 "피했는데 맞았다"가 부분 재발한다(아래 ⚠와 같은 실패 모드).
#   ⚠ 상한을 무한정 키울 수도 없다 — 두 목적이 충돌한다(스파이크 억제는 작기를, 정당 외삽 커버는 크기를 요구).
#   그래서 이속 하드 상한을 0.3으로 조여 균형을 잡았다.
#   ⚠ 이 값이 실제 최대 외삽보다 **작으면** 추정 좌표가 예고 안에 남아 "둘 다 맞아야 확정" 규약이
#   맞는 쪽으로 기운다 → 빠르게 빠져나가는 피어가 다시 맞는다(2026-07-24에 고친 버그의 부분 퇴행).
#   이속 상한(LEVEL_STAT_MAX["move"])·구르기 거리 상한(TRAIT_MAX["roll_dist"])·직업 move_speed 중
#   무엇을 올리든 여기도 재유도해라 —
#   test_combat_math_auto의 데이터 전수 불변식이 그때 빨개진다.

# 편도 지연 = RTT의 절반. 음수·NaN·스파이크를 상한으로 눌러 판정에 쓸 수 있는 값으로 정규화한다.
static func clamp_one_way_ms(one_way_ms: float) -> float:
	if not is_finite(one_way_ms):
		return 0.0
	return clampf(one_way_ms, 0.0, LAG_MAX_ONE_WAY_MS)


# 예고 타격을 늦출 시간(초) — 원격 피어 중 **최대** 편도 지연. 가장 느린 피어도 온전한 예고 창을 갖는다.
# 솔로/호스트뿐이면 0 = 기존 동작과 완전히 동일(항등 폴백).
static func strike_delay_s(max_one_way_ms: float) -> float:
	return clamp_one_way_ms(max_one_way_ms) / 1000.0


# 외삽 시간(초) — 마지막 위치 패킷이 담은 시점부터 "지금"까지.
#   (패킷 수신 후 흐른 시간) + (그 패킷이 날아오는 데 걸린 편도 지연)
# 로컬 피어(지연 0·수신 기록 없음)는 0을 넘겨 항등이 되게 한다.
static func lag_lead_s(last_recv_msec: int, now_msec: int, one_way_ms: float) -> float:
	if last_recv_msec < 0:
		return 0.0
	var since_ms := float(maxi(now_msec - last_recv_msec, 0))
	return (since_ms + clamp_one_way_ms(one_way_ms)) / 1000.0


# 위치 패킷 신선도 — 순서가 뒤바뀐 G_POS를 폐기해 판정 앵커가 과거로 되돌아가는 것을 막는다.
# 🔴 **왜 필요한가 (P2P 직결 도입, 2026-07-26):** fast 데이터 채널은 unordered(유실 허용)라 위치 패킷이
#   뒤바뀌어 도착할 수 있다. 릴레이(TCP)에선 구조적으로 불가능했던 상황이다. 뒤늦게 도착한 옛 패킷을
#   적용하면 `_remote_target`과 `_remote_vel`이 **함께** 한 틱 과거로 돌아가는데, 그러면
#   `net_anchor()`(낡은 좌표)와 `net_anchor_lead()`(추정 좌표)가 **같은 방향으로** 틀려
#   "둘 다 맞아야 확정"인 방어자 우대 규약(is_strike_hit_lagged)이 무력화된다 — 규약은 두 좌표가
#   **서로 다른 방향**으로 틀릴 때만 방어자를 보호하기 때문이다. 결과는 "빠져나왔는데 맞았다"의 부분 재발.
# ⚠ 변위 clamp(player.apply_remote_pos)는 이걸 못 막는다 — 되돌아가는 거리가 한 송신 간격분(~4px)이라
#   상한(~13px) 안에 들어와 그냥 통과한다. 그래서 순서를 **명시적으로** 봐야 한다.
# seq <= 0 = 시퀀스 미부착(릴레이 경로·구버전) → 항등 폴백으로 전부 통과시킨다.
static func is_pos_seq_fresh(seq: int, last_seq: int) -> bool:
	if seq <= 0:
		return true
	return seq > last_seq


# 마지막 관측 속도로 추정한 "지금" 위치. 거리 상한(LAG_MAX_LEAD_DIST)으로 폭주를 막는다.
static func extrapolate(pos: Vector2, vel: Vector2, lead_s: float) -> Vector2:
	if not (is_finite(vel.x) and is_finite(vel.y)) or lead_s <= 0.0:
		return pos
	var offset := vel * lead_s
	if offset.length() > LAG_MAX_LEAD_DIST:
		offset = offset.normalized() * LAG_MAX_LEAD_DIST
	return pos + offset


# 지연 보상 원형 타격 판정 — 낡은 좌표와 추정 좌표가 **둘 다** 안일 때만 맞은 것 (방어자 우대, 위 설명).
# lead_pos == anchor(로컬 피어·속도 0)면 is_strike_hit과 완전히 같다 — 항등 폴백.
static func is_strike_hit_lagged(anchor: Vector2, lead_pos: Vector2,
		strike_center: Vector2, strike_radius: float) -> bool:
	return is_strike_hit(anchor, strike_center, strike_radius) \
		and is_strike_hit(lead_pos, strike_center, strike_radius)


# 지연 보상 부채꼴 판정 — 원형과 같은 규약(둘 다 안일 때만). 보스 평타 등 cone 패턴용.
static func is_hit_in_cone_lagged(anchor: Vector2, lead_pos: Vector2, apex: Vector2,
		facing: float, half_angle: float, radius: float) -> bool:
	return is_hit_in_cone(anchor, apex, facing, half_angle, radius) \
		and is_hit_in_cone(lead_pos, apex, facing, half_angle, radius)


# 인원 스케일링 — 솔로 시 보스 약화 (§3 예약 → 구현, GDD §11·§5 확정). party_size>=2 → base(항등),
# 1(솔로) → base*solo_factor. max_hp·물 착탄 수·늪 자동 생성 빈도에 곱한다. 호스트가 계산(게스트도
# 같은 피어 수로 동일 계산 → 표시 일치). solo_factor·적용 대상 수치는 사용자 실기 튜닝.
static func party_scale(base: float, party_size: int, solo_factor: float = 0.6) -> float:
	if party_size >= 2:
		return base
	return base * solo_factor


# --- 장비 스탯 (드랍·제작 2026-07-23) — 단일 소스 (§3). 제작/강화 UI·전투·HUD가 전부 이 함수만 부른다. ---

# 한 장비의 레벨별 스탯 = base + step*level. total_stats·강화 미리보기가 같이 부른다(갈라짐 방지).
static func equip_stat_at_level(equip: EquipDef, level: int) -> Dictionary:
	return {
		"attack": equip.base_attack + equip.atk_per_level * level,
		"hp": equip.base_hp + equip.hp_per_level * level,
	}


# 착용 장비 총 스탯. equip_levels = [[EquipDef, level], …]. 미착용이면 {attack=0, hp=0} (항등 폴백).
static func total_stats(equip_levels: Array) -> Dictionary:
	var atk := 0
	var hp := 0
	for pair: Array in equip_levels:
		var s := equip_stat_at_level(pair[0] as EquipDef, int(pair[1]))
		atk += int(s["attack"])
		hp += int(s["hp"])
	return {"attack": atk, "hp": hp}


# 강화 미리보기 델타(from→to 레벨). 강화 UI "다음 단계"와 실제 적용이 같은 함수를 부른다.
static func upgraded_stats(equip: EquipDef, from_level: int, to_level: int) -> Dictionary:
	var a := equip_stat_at_level(equip, from_level)
	var b := equip_stat_at_level(equip, to_level)
	return {"attack": int(b["attack"]) - int(a["attack"]), "hp": int(b["hp"]) - int(a["hp"])}


# 강화 비용(골드). UI 미리보기 = 실제 차감 단일 소스. 곡선 = base * (다음 레벨).
static func upgrade_cost(equip: EquipDef, current_level: int) -> int:
	return equip.upgrade_gold_base * (current_level + 1)


# --- 직업 레벨 · 캐릭터 스탯 5종 (성장축 2026-07-25, GDD v1.8) — 단일 소스 (§3) ---
#
# 🔒 축 경계(GDD §6 확정): 이 절은 **레벨 스탯만** 다룬다. 공격력·체력은 위 장비 절(total_stats)의 몫이다.
#   두 파이프를 하나로 합치지 마라 — 합치면 data/equipment/*.tres에 "crit"을 적어도 코드가 조용히 받아들인다
#   (기획 위반이 컴파일도 리뷰도 안 걸리고 통과한다). 분리하면 EquipDef엔 crit 필드가 아예 없다.
#
# 와이어 키 = 아래 문자열 **그대로** 쓴다: G_STATS "lv" 페이로드 키 · SubJobDef.step() 키 · clamp 키.
#   별도 매핑 표를 만들면 그게 두 번째 진실원이 되어 갈라진다.
const LEVEL_STAT_KEYS: Array[String] = ["crit", "crit_dmg", "haste", "move", "leech"]

# 키별 **하드 상한** — 데이터가 잘못 커지거나 조작 공지가 와도 여기서 잘린다.
# 데이터 유도 상한(GameState.max_level_stats)과 이중 방어: 정직한 최대치는 데이터 상한이,
# 데이터 자체의 실수는 이 상수가 잡는다(max_equip_stats + 상한 상수 철학의 미러).
const LEVEL_STAT_MAX: Dictionary = {
	"crit": 1.0,      # 확률 — 100% 초과는 무의미
	"crit_dmg": 3.0,  # 치명 배율 추가분(총 배율 = CRIT_BASE_MULT + 이 값)
	"haste": 0.5,     # 공속 +50% → 쿨다운 ×1/1.5. ⚠ 퇴화 한계: effective_cooldown*0.9 > SAME_SWING_MS를 지켜야 한다
	"move": 0.3,      # 이속 +30% — GDD 예산(+15%)의 2배 여유. 🔴 이 값을 올리면 LAG_MAX_LEAD_DIST(외삽 상한)를
	                  #   같이 재유도해야 한다 — 안 하면 지연 보상이 퇴행한다(테스트 불변식이 그때 빨개진다)
	"leech": 0.5,     # 피흡 50%
}

const SUB_JOB_WEIGHT := 0.4  # 서브(비-메인) 하위 직업 기여 배율 — GDD §5 "서브도 효과가 있다" · 값은 §11 실기 TBD
const CRIT_BASE_MULT := 1.5  # 치명타 기본 배율 (GDD §6 = 150%). 치명 총 배율 = 이 값 + lv_stats.crit_dmg


# 레벨 스탯 한 칸 clamp — 유한성 가드 먼저(JSON 1e999 → INF, clamp_arrow_range와 같은 철학).
# cap = 데이터 유도 상한(없으면 하드 상한만). 음수는 0으로 — 디버프 주입 차단.
static func clamp_level_stat(key: String, value: float, cap: float = INF) -> float:
	if not is_finite(value):
		return 0.0
	var hard := float(LEVEL_STAT_MAX.get(key, 0.0))
	var top := hard if not is_finite(cap) else minf(hard, maxf(cap, 0.0))
	return clampf(value, 0.0, top)


# 레벨 스탯 묶음 clamp — 🔴 **payload가 아니라 LEVEL_STAT_KEYS를 순회한다**(allowlist 관용구):
# 모르는 키는 자동 폐기되고, 빠진 키는 0.0으로 채워져 하류가 항등 폴백을 얻는다.
static func clamp_level_stats(stats: Dictionary, caps: Dictionary = {}) -> Dictionary:
	var out := {}
	for key: String in LEVEL_STAT_KEYS:
		out[key] = clamp_level_stat(key, float(stats.get(key, 0.0)), float(caps.get(key, INF)))
	return out


# 빈 레벨 스탯(전부 0) — 성장축 미도입/미착용 경로의 항등 폴백.
static func empty_level_stats() -> Dictionary:
	var out := {}
	for key: String in LEVEL_STAT_KEYS:
		out[key] = 0.0
	return out


# 하위 직업 하나의 레벨별 스탯 = step * level (base 없음 — GDD §6).
static func sub_job_stat_at_level(def: SubJobDef, level: int) -> Dictionary:
	var out := {}
	var lv := clampi(level, 0, def.max_level)
	for key: String in LEVEL_STAT_KEYS:
		out[key] = def.step(key) * float(lv)
	return out


# 총 레벨 스탯 = 메인 온전 + 서브들 × SUB_JOB_WEIGHT (GDD §5 "메인 1개 + 서브 합산").
#   levels = {sub_id: level} (보유분) · defs = {sub_id: SubJobDef}
# ⚠ CombatMath는 오토로드를 참조하지 않는다(-s 테스트 호환, 위 total_stats와 같은 규약) —
#   id→SubJobDef 리졸브는 부르는 쪽(GameState.current_level_stats)이 한다.
# 보유 0이면 전부 0 = 항등 폴백.
static func level_stats(main_id: String, levels: Dictionary, defs: Dictionary,
		sub_weight: float = SUB_JOB_WEIGHT) -> Dictionary:
	var out := empty_level_stats()
	for sid: String in levels:
		var def := defs.get(sid) as SubJobDef
		if def == null:
			continue  # allowlist 밖 / 리졸브 실패 — 조용히 건너뛴다(폐기가 안전한 방향)
		var w := 1.0 if sid == main_id else maxf(sub_weight, 0.0)
		var s := sub_job_stat_at_level(def, int(levels[sid]))
		for key: String in LEVEL_STAT_KEYS:
			out[key] = float(out[key]) + float(s[key]) * w
	return clamp_level_stats(out)


# 치명타 총 배율. crit_dmg = 레벨 스탯의 배율 **추가분**(0 = 기본 150%).
static func crit_mult(crit_dmg: float) -> float:
	return CRIT_BASE_MULT + clamp_level_stat("crit_dmg", crit_dmg)


# 🔴 최종 데미지 확정 — 단일 소스 (§3). 근접·투사체·폭발 **3경로 전부** 이 함수만 부른다.
# 곱 순서 고정: (직업 기본 + 장비 보너스) × 차지 배율 × 치명 배율 → **반올림 1회**.
#   경로마다 곱 순서나 반올림 횟수가 갈라지면 같은 상황에서 데미지가 달라진다
#   (charge_damage가 이미 round를 하므로, 치명을 그 밖에서 곱하면 이중 반올림이 된다).
# 🔴 굴림(crit_roll01)은 **호출부(호스트 RNG)** 가 만든다 — CombatMath가 RNG를 쥐면 테스트가 결정론을 잃는다.
#   굴림 단위 = 데미지 인스턴스 1회(폭발이 3마리를 때리면 3번 굴린다 — 사용자 확정 2026-07-25).
# lv_stats 비어 있고 charge 0·combo_mult 1이면 calc_damage와 **정확히 같은 값**(항등 폴백).
# 🔴 combo_mult = 평타 콤보 타별 데미지 배율(combo_damage_mult_at). **곱셈 안쪽**에 넣어 반올림이
#   여전히 1회이게 한다 — 호출부에서 결과에 곱하면 이중 반올림이 되고, 그게 정확히 이 함수가
#   존재하는 이유다. 🔴 배율은 **호스트가 센 타수**로 리졸브한다(authoritative_combo) — 발신자가
#   주장한 타수로 곱하면 매 발사가 마무리 타가 된다.
static func confirm_damage(job: JobDef, bonus_attack: int, lv_stats: Dictionary,
		charge_level: int, crit_roll01: float, combo_mult: float = 1.0) -> Dictionary:
	var base := float(calc_damage(job, bonus_attack))
	var mult := CHARGE_DAMAGE_MULT[clamp_charge_level(charge_level)]
	var chance := clamp_level_stat("crit", float(lv_stats.get("crit", 0.0)))
	var is_crit := is_finite(crit_roll01) and crit_roll01 >= 0.0 and crit_roll01 < chance
	var cmult := crit_mult(float(lv_stats.get("crit_dmg", 0.0))) if is_crit else 1.0
	return {"damage": int(round(base * mult * clamp_combo_mult(combo_mult) * cmult)), "crit": is_crit}


# 피흡 적립량(소수) — 🔴 **실제로 깎인 HP** 기준으로 부른다(오버킬 기준이면 1HP 잔몹을 치명타로 때려
# 회복을 부풀릴 수 있다). 정수 절삭은 호출부가 소수 잔량을 누적해 처리한다(데미지가 4~34 정수라
# 매 타격 절삭하면 6% 흡혈이 0이 되어 스탯이 아예 작동하지 않는다 — GDD §6 소수 누적 확정).
static func leech_gain(applied_damage: int, leech: float) -> float:
	if applied_damage <= 0:
		return 0.0
	return float(applied_damage) * clamp_level_stat("leech", leech)


# --- 공격속도 (haste) — 단일 소스 (§3) ---
#
# 🔴 **핵심 계약: 쿨다운과 스윙 창(EquipDef.swing_time)·차지 스텝에 같은 배율을 곱한다.**
#   그러면 rules §3의 스윙 창 부등식(swing_time < attack_cooldown)이 k = haste_scale(h) > 0 어디서나
#   `swing_time·k < cooldown·k`로 **자동 보존**된다 — 부등식을 haste마다 다시 검사할 필요가 없다.
#   배율 함수를 공유하는 것 자체가 계약의 증명이다. 각자 1/(1+h)를 다시 쓰면 그 증명이 깨진다.
static func clamp_haste(haste: float) -> float:
	return clamp_level_stat("haste", haste)


static func haste_scale(haste: float) -> float:
	return 1.0 / (1.0 + clamp_haste(haste))


static func effective_cooldown(job: JobDef, haste: float = 0.0) -> float:
	return job.attack_cooldown * haste_scale(haste)


static func effective_charge_step(step_time: float, haste: float = 0.0) -> float:
	if not is_finite(step_time) or step_time <= 0.0:
		return step_time  # 차지 무기가 아님 — 그대로 넘겨 호출부의 "0 = 차지 불가" 판정을 보존
	return step_time * haste_scale(haste)


# --- 이동속도 (move) — 단일 소스 (§3) ---
# ⚠ 로컬 이동만 고치면 안 된다: 원격 위치 clamp(player.gd)가 job.move_speed를 기준으로 상한을 잡으므로,
#   빨라진 정당 이동이 깎이면 지연 보상의 외삽이 과소평가되고 "피했는데 맞았다"가 빠른 피어에게 재발한다
#   (2026-07-24에 고친 그 버그). 두 상한 모두 이 함수로 유도한다.
static func clamp_move(move: float) -> float:
	return clamp_level_stat("move", move)


static func effective_move_speed(base_speed: float, move: float) -> float:
	return base_speed * (1.0 + clamp_move(move))


# --- EXP · 레벨 파생 (§3) ---
# 🔴 레벨은 **저장하지 않고 EXP에서 파생**한다 — 둘을 다 저장하면 어긋난 상태(손상·구버전 세이브)가
#   생기고, 레벨은 스탯 공지의 근거라서 어긋남이 곧 클라 간 스탯 발산이다.
# 곡선 = 레벨 n 도달에 필요한 **누적** EXP(인덱스 = 레벨, [0] = 0). 데이터 = JobDef.exp_curve.
static func default_exp_curve() -> PackedInt32Array:
	return PackedInt32Array([0, 60, 150, 280, 460, 700])


# 누적 EXP → 레벨. curve가 비었거나 깨졌으면 기본 곡선. max_level로 clamp(초과분은 폐기 = 만레벨 유지).
static func level_for_exp(exp: int, curve: PackedInt32Array, max_level: int) -> int:
	var c := curve if curve.size() >= 2 else default_exp_curve()
	var top := mini(max_level, c.size() - 1)
	var lv := 0
	for n: int in range(1, top + 1):
		if exp >= c[n]:
			lv = n
		else:
			break
	return lv


# UI 진행 바용 — {"level", "cur"(현 레벨 구간 진행량), "need"(구간 총량, 만레벨 = 0)}.
# 레벨업 판정과 바 표시가 같은 함수를 지난다(갈라짐 방지).
static func exp_progress(exp: int, curve: PackedInt32Array, max_level: int) -> Dictionary:
	var c := curve if curve.size() >= 2 else default_exp_curve()
	var lv := level_for_exp(exp, c, max_level)
	var top := mini(max_level, c.size() - 1)
	if lv >= top:
		return {"level": lv, "cur": 0, "need": 0}  # 만레벨 = 바 없음(잉여 EXP는 폐기, GDD §11)
	var floor_exp := c[lv]
	return {"level": lv, "cur": exp - floor_exp, "need": c[lv + 1] - floor_exp}
