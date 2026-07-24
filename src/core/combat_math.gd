class_name CombatMath
extends RefCounted
# 전투 수치 계산 — 단일 소스 (projectb-rules §3 하드 계약).
# UI 표시·실전투(호스트 확정)가 전부 이 함수만 부른다. 다른 곳에서 같은 계산을 만들면 갈라진다.


# 최종 데미지. bonus_attack = 착용 장비 공격 합(total_stats.attack). 미착용=0 → 기존 동작과 동일(항등 폴백).
static func calc_damage(job: JobDef, bonus_attack: int = 0) -> int:
	return job.attack_damage + bonus_attack


# 호스트의 적중 요청 검증 — 공격자 위치 기준 사거리 내인가 (지연 감안 여유 배율).
# enemy_radius = 적 몸 반경 — 중심거리에서 빼 준다. 거대 보스(radius ~48)는 중심이 멀어
# "붙어도 사거리 밖"이 되므로 몸통 표면까지로 판정한다 (기본 0 = 기존 잔몹 동작 불변).
static func is_hit_in_reach(attacker_pos: Vector2, enemy_pos: Vector2, job: JobDef, enemy_radius: float = 0.0) -> bool:
	return attacker_pos.distance_to(enemy_pos) - enemy_radius <= job.attack_range * 2.0


# 히트 기하 — 단일 소스 (§3). 실제 판정(원형 질의)과 공격 FX 위치가 같은 함수를 부른다.
# 한쪽만 조이면 "맞는 곳"과 "보이는 곳"이 어긋난다 — 손맛 튜닝은 반드시 여기서.
const ATTACK_CENTER_SCALE := 0.6  # 공격 중심까지의 거리 = range * 이 값
const ATTACK_RADIUS_SCALE := 0.5  # 판정 반경 = range * 이 값


static func attack_center_offset(dir: Vector2, job: JobDef) -> Vector2:
	return dir * (job.attack_range * ATTACK_CENTER_SCALE)


static func attack_radius(job: JobDef) -> float:
	return job.attack_range * ATTACK_RADIUS_SCALE


# 한 스윙이 여러 적을 치는 것은 허용하되(SAME_SWING_MS 안), 스윙 간격은 쿨다운(지터 여유 0.9배)을 강제.
# 앵커(last_confirm_msec)는 새 스윙에서만 갱신해야 한다 — 매 확정마다 갱신하면 창이 미끄러져 연사 스팸이 뚫린다.
const SAME_SWING_MS := 50


static func is_hit_cooldown_ok(last_confirm_msec: int, now_msec: int, job: JobDef) -> bool:
	var dt := now_msec - last_confirm_msec
	return dt <= SAME_SWING_MS or dt >= int(job.attack_cooldown * 0.9 * 1000.0)


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
static func is_charge_time_ok(last_shot_msec: int, now_msec: int, level: int, step_time: float) -> bool:
	var lv := clamp_charge_level(level)
	if lv <= 0:
		return true
	if not is_finite(step_time) or step_time <= 0.0:
		return false  # 차지 못 하는 무기인데 레벨을 주장 = 거부
	return now_msec - last_shot_msec >= int(float(lv) * step_time * 0.9 * 1000.0)


# 화살 명중 판정 — 호스트만. 화살 현재 위치와 적 중심 거리 <= 화살굵기+적반경.
# is_strike_hit 재사용(같은 거리 질의) — 물리 레이어 대신 매 프레임 거리 질의라 물리 레이어 함정(§5) 회피 + 단위 테스트 가능.
static func is_arrow_hit(arrow_pos: Vector2, enemy_pos: Vector2, enemy_radius: float = 0.0) -> bool:
	return is_strike_hit(arrow_pos, enemy_pos, ARROW_HIT_RADIUS + enemy_radius)


# 호스트의 발사 쿨다운 검증 — 발사 간격은 공격자 job 쿨다운(지터 여유 0.9배) 강제. 스팸해도 정직한 발사율 이상 못 얻는다.
# 근접의 is_hit_cooldown_ok와 달리 SAME_SWING 다중타격 허용이 없다 — 화살 하나=한 발이라 매 발사 독립 게이트.
static func is_fire_rate_ok(last_shot_msec: int, now_msec: int, job: JobDef) -> bool:
	return now_msec - last_shot_msec >= int(job.attack_cooldown * 0.9 * 1000.0)


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
