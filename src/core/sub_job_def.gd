class_name SubJobDef
extends Resource
# 하위 직업 정의 스키마 (core — 리드 전용). 개체는 data/subjobs/*.tres (projectb-rules §4).
# 계열(series_id = JobDef.id) 안의 성장 갈래 — 무기·모션·스프라이트를 바꾸지 않는다 (GDD §5).
#
# 🔒 축 경계 (GDD §6 확정): 여기엔 **공격력·체력 필드를 절대 넣지 마라.** 그건 장비 축(EquipDef)의 몫이다.
#   반대로 EquipDef에 crit/haste를 넣는 것도 금지 — 기획 변경(planner 승인)이 선행 조건이다.
#   두 축이 같은 스탯을 밀면 ⑴ 강화할 이유가 옅어지고 ⑵ "정직한 최강 장비" 기준의 스탯 상한 검증이 흐려진다.
#
# 🔴 base 값이 없다 — 레벨 0 = 전부 0 (GDD §6 "레벨업 시 정해진 만큼 자동 상승").
#   수치는 총 화력 예산(GDD §6: 무장만 최대치의 1.5배)에서 역산한다 — 값 자체는 §11 실기 TBD.

@export var id: String = ""              # data/subjobs/<id>.tres 파일명과 일치 — 저장·해금 체인의 키
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D              # UI 표시 (도형 금지, rules §0)

@export var series_id: String = ""       # 계열 = JobDef.id("warrior") — 다른 계열의 하위 직업은 보유 불가 (GDD §5)
@export var order: int = 0               # 계열 내 해금 순서 (0 = 시작 하위 직업). 다음 해금 대상 = order+1
@export var unlocks_next_at: int = 3     # 이 하위 직업이 **메인일 때** 다음 것을 여는 레벨 (GDD §6 초안 3)
@export var max_level: int = 5            # 레벨 상한 (GDD §6 초안 5)

# 레벨당 스탯 증가 — 키는 CombatMath.LEVEL_STAT_KEYS와 **미러**다 (step()이 유일한 키→값 진입점).
# 새 스탯을 늘릴 땐 여기 @export + LEVEL_STAT_KEYS + step() 세 곳을 함께 (rules §2 게이트).
@export_group("레벨당 성장")
@export var crit_per_level: float = 0.0      # 치명타 확률 증가(0.04 = +4%p)
@export var crit_dmg_per_level: float = 0.0  # 치명타 데미지 배율 증가(0.1 = +10%p, 기본 배율은 CRIT_BASE_MULT)
@export var haste_per_level: float = 0.0     # 공격속도 증가율(0.05 = +5% → 쿨다운 1/(1+h))
@export var move_per_level: float = 0.0      # 이동속도 증가율(0.03 = +3%)
@export var leech_per_level: float = 0.0     # 피흡 비율(0.012 = 준 데미지의 1.2%)


# 키 → 레벨당 증가값. CombatMath.LEVEL_STAT_KEYS 루프의 진입점 — 모르는 키는 0.0(항등).
func step(key: String) -> float:
	match key:
		"crit":
			return crit_per_level
		"crit_dmg":
			return crit_dmg_per_level
		"haste":
			return haste_per_level
		"move":
			return move_per_level
		"leech":
			return leech_per_level
	return 0.0
