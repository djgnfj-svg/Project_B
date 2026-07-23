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
