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


# 유한성 가드 먼저(JSON 1e999 → INF, clamp_level_stat과 같은 철학). 음수는 0 — 사거리 디버프 주입 차단.
static func clamp_reach(reach: float) -> float:
	if not is_finite(reach):
		return 0.0
	return clampf(reach, 0.0, MAX_REACH_BONUS)


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


# haste = 그 피어가 공지한(그리고 호스트가 clamp한) 공격속도 보너스 — 0 = 항등(성장축 도입 전과 동일).
static func is_hit_cooldown_ok(last_confirm_msec: int, now_msec: int, job: JobDef, haste: float = 0.0) -> bool:
	var dt := now_msec - last_confirm_msec
	return dt <= SAME_SWING_MS or dt >= int(effective_cooldown(job, haste) * 0.9 * 1000.0)


# 구르기 타이밍 — 단일 소스 (§3). 로컬 이동(player)과 호스트 i-frame 검증이 같은 값을 읽는다.
# player.gd에 사본을 남기면 첫 손맛 튜닝에서 구르기 거리와 무적 창이 갈라진다.
# ⚠ 애니 미러: assets/sprites/player/*_frames.tres의 roll(4프레임/speed 16 = 0.25s)이 이 값과 맞물린다.
#   ROLL_TIME_S를 바꾸면 3개 .tres의 roll speed도 같이 조정할 것 (애니가 짧으면 마지막 프레임에 얼어붙는다).
const ROLL_TIME_S := 0.25
const ROLL_COOLDOWN_S := 0.8
const ROLL_IFRAME_GRACE_MS := 120  # 지연 여유 — 사거리 검증 2.0배 완충과 같은 철학


# 호스트의 구르기 그랜트 검증 — 쿨다운(지터 여유 0.9배) 강제. 스팸해도 정직한 구르기 이상의 무적을 못 얻는다.
static func is_roll_grant_ok(last_grant_msec: int, now_msec: int) -> bool:
	return now_msec - last_grant_msec >= int(ROLL_COOLDOWN_S * 0.9 * 1000.0)


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
	return now_msec - last_shot_msec >= int(float(lv) * step * 0.9 * 1000.0)


# 화살 명중 판정 — 호스트만. 화살 현재 위치와 적 중심 거리 <= 화살굵기+적반경.
# is_strike_hit 재사용(같은 거리 질의) — 물리 레이어 대신 매 프레임 거리 질의라 물리 레이어 함정(§5) 회피 + 단위 테스트 가능.
static func is_arrow_hit(arrow_pos: Vector2, enemy_pos: Vector2, enemy_radius: float = 0.0) -> bool:
	return is_strike_hit(arrow_pos, enemy_pos, ARROW_HIT_RADIUS + enemy_radius)


# 호스트의 발사 쿨다운 검증 — 발사 간격은 공격자 job 쿨다운(지터 여유 0.9배) 강제. 스팸해도 정직한 발사율 이상 못 얻는다.
# 근접의 is_hit_cooldown_ok와 달리 SAME_SWING 다중타격 허용이 없다 — 화살 하나=한 발이라 매 발사 독립 게이트.
static func is_fire_rate_ok(last_shot_msec: int, now_msec: int, job: JobDef, haste: float = 0.0) -> bool:
	return now_msec - last_shot_msec >= int(effective_cooldown(job, haste) * 0.9 * 1000.0)


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
const LAG_MAX_LEAD_DIST := 90.0     # 외삽 거리 상한(px) — 지연 스파이크 한 번이 판정을 화면 밖으로 날리지 않게.
# 🔴 유도식(성장축 2026-07-25 재산정): 최고 이속 × ROLL_SPEED_MULT × 최대 lead
#   = (110 × (1+LEVEL_STAT_MAX["move"]=0.3)) × 2.6 × (LAG_MAX_ONE_WAY_MS 0.2s + 송신주기 1/30s) ≈ 87px → 90.
#   ⚠ 상한을 무한정 키울 수도 없다 — 두 목적이 충돌한다(스파이크 억제는 작기를, 정당 외삽 커버는 크기를 요구).
#   그래서 이속 하드 상한을 0.3으로 조여 균형을 잡았다.
#   ⚠ 이 값이 실제 최대 외삽보다 **작으면** 추정 좌표가 예고 안에 남아 "둘 다 맞아야 확정" 규약이
#   맞는 쪽으로 기운다 → 빠르게 빠져나가는 피어가 다시 맞는다(2026-07-24에 고친 버그의 부분 퇴행).
#   이속 상한(LEVEL_STAT_MAX["move"])이나 직업 move_speed를 올리면 여기도 재유도해라 —
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
# lv_stats 비어 있고 charge 0이면 calc_damage와 **정확히 같은 값**(항등 폴백).
static func confirm_damage(job: JobDef, bonus_attack: int, lv_stats: Dictionary,
		charge_level: int, crit_roll01: float) -> Dictionary:
	var base := float(calc_damage(job, bonus_attack))
	var mult := CHARGE_DAMAGE_MULT[clamp_charge_level(charge_level)]
	var chance := clamp_level_stat("crit", float(lv_stats.get("crit", 0.0)))
	var is_crit := is_finite(crit_roll01) and crit_roll01 >= 0.0 and crit_roll01 < chance
	var cmult := crit_mult(float(lv_stats.get("crit_dmg", 0.0))) if is_crit else 1.0
	return {"damage": int(round(base * mult * cmult)), "crit": is_crit}


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
