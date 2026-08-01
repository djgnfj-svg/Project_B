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

# 계열 = JobDef.id("warrior") — 다른 계열의 하위 직업은 보유 불가 (GDD §5).
# 🔒 예외 = SERIES_SHARED("*") = **공유 하위 직업**(GDD v2.0): 계열 무관으로 누구나 보유하되
#   **서브 자리 전용**이다(메인은 항상 계열 하위 직업 — "계열 = 플레이 방식의 변환" 축을 지킨다).
#   그래서 공유 하위 직업엔 메인 특성이 없다(아래 main_trait_key를 비워 둔다).
const SERIES_SHARED := "*"

@export var series_id: String = ""
@export var order: int = 0               # 계열 내 해금 순서 (0 = 시작 하위 직업). 다음 해금 대상 = order+1
@export var unlocks_next_at: int = 3     # 이 하위 직업이 **메인일 때** 다음 것을 여는 레벨 (GDD §6 초안 3)
@export var max_level: int = 5            # 레벨 상한 (GDD §6 초안 5)


func is_shared() -> bool:
	return series_id == SERIES_SHARED


# 이 하위 직업을 그 계열의 플레이어가 보유/장착할 수 있나 — 계열 일치 또는 공유.
# 🔴 저장·네트워크로 들어온 id가 전부 이 게이트를 지난다(남의 계열 특성 주장 폐기).
func is_usable_by(series: String) -> bool:
	return series_id == series or is_shared()

# 레벨당 스탯 증가 — 키는 CombatMath.LEVEL_STAT_KEYS와 **미러**다 (step()이 유일한 키→값 진입점).
# 새 스탯을 늘릴 땐 여기 @export + LEVEL_STAT_KEYS + step() 세 곳을 함께 (rules §2 게이트).
@export_group("레벨당 성장")
@export var crit_per_level: float = 0.0      # 치명타 확률 증가(0.04 = +4%p)
@export var crit_dmg_per_level: float = 0.0  # 치명타 데미지 배율 증가(0.1 = +10%p, 기본 배율은 CRIT_BASE_MULT)
@export var haste_per_level: float = 0.0     # 공격속도 증가율(0.05 = +5% → 쿨다운 1/(1+h))
@export var move_per_level: float = 0.0      # 이동속도 증가율(0.03 = +3%)
@export var leech_per_level: float = 0.0     # 피흡 비율(0.012 = 준 데미지의 1.2%)

# --- 특성 — 메인형 / 서브형 (GDD v2.0 §5·§6 · v1.9 신설) ---
# 🔒 **낀 자리에 따라 하나만 켜진다.** 메인으로 두면 메인 특성, 서브로 두면 서브 특성 —
#   같은 하위 직업이라도 자리가 다르면 다른 효과다. 동시 활성은 하위 직업당 1개,
#   판 전체로는 최대 3개(메인 1 + 서브 2)이고 이 상한은 슬롯 구조가 강제한다.
# 🔒 5스탯과 달리 **레벨로 자라지 않는다**(켜짐/꺼짐) — 레벨 곱도 서브 가중도 타지 않는다.
# 🔒 특성 경계: **무기·모션·조작을 바꾸는 값은 여기 넣지 마라**(그건 2차 전직 = 비범위 §10).
#   **공격력·체력도 금지**(장비 축)이고 **공격속도·치명타도 금지**(5스탯 축 = 화력 예산 안).
#   특성이 쓰는 것은 CombatMath.TRAIT_KEYS — 전부 데미지에 곱해지지 않는 축이다.
# 🔴 값의 상한은 CombatMath.TRAIT_MAX가 강제한다 — 여기에 더 큰 값을 써도 그 위로는 안 올라간다.
#   같은 키를 메인·서브가 같이 밀면 합산된 뒤 그 상한에서 잘린다(GDD §6 "보상은 있되 끝이 있다").
@export_group("특성 — 메인 자리")
@export var main_trait_name: String = ""   # 「검기 파형」 — UI 표시용(문구는 키+값에서 자동 생성)
@export var main_trait_key: String = ""    # CombatMath.TRAIT_KEYS 중 하나. 빈 문자열 = 특성 없음
@export var main_trait_value: float = 0.0

@export_group("특성 — 서브 자리")
@export var sub_trait_name: String = ""
@export var sub_trait_key: String = ""
@export var sub_trait_value: float = 0.0

# --- 궤적 아이덴티티 (2026-08-01) — 🔴 **표시 전용이라 위 두 축 어디에도 속하지 않는다** ---
# 왜 여기 있나: 하위 직업이 스탯·특성으로만 갈려서 **화면에서 서로 구분되지 않았다**(스프라이트도
#   계열 단위라 셋이 같은 캐릭터다). 겉모습을 만들려면 아트 3벌이 필요한데, 궤적 색·밀도는
#   데이터 두 칸으로 같은 구분을 낸다.
# 🔒 축 경계 — **화면에만 나타나는 값만 여기 넣어라.** 사거리·속도·데미지처럼 판정에 닿는 값을
#   표시 필드로 우회시키면 화력 예산 트립와이어(test_game_state_auto)가 그것을 **영영 못 본다**.
#   판정에 닿는 것은 CombatMath.TRAIT_KEYS(예산 밖 축) 또는 5스탯(예산 안)의 몫이다.
# 🔴 **네트워크로 오가는 것은 여전히 id뿐이다**(G_STATS "ms") — 색·배율은 각 클라가 자기
#   data/subjobs에서 리졸브한다(traits_of·peer_weapon_id와 같은 철학, rules §3). 값을 실으면
#   그게 곧 스푸핑 표면이고, 표시 전용이라도 남의 화면을 칠하는 권한이 생긴다.
# 🔴 **메인 자리 전용이다** — 서브까지 색을 내면 셋이 겹쳐 무슨 색인지 못 읽는다. 리졸브
#   (GameState.main_fx_of)가 trait_at(true)와 **같은 게이트**(계열 일치·공유 배제)를 지난다.
# 기본값이 항등(흰색·배율 1)이라 값을 안 적은 .tres는 도입 전과 **완전히 같다.**
@export_group("궤적 아이덴티티 — 표시 전용")
# 궤적 틴트 — 무기 `EquipDef.swing_color`와 **곱해진다**(현재 근접 4종은 전부 흰색이라 이 색이 그대로 나온다).
# ⚠ 알파 0은 궤적을 통째로 지운다(에러 없이 "칼만 도는" 화면) — 전수 트립와이어가 막는다.
@export var fx_color: Color = Color(1, 1, 1, 1)
# 칼 잔상 장수 배율 — 클수록 호가 촘촘히 채워져 "몰아친다"로 읽힌다. 🔴 상한은 여기가 아니라
#   CombatMath.fx_ghost_mult()가 쥔다(잔상 한 장 = Sprite2D 하나 = 드로우콜, 웹 Compatibility §5).
@export var fx_ghost_mult: float = 1.0
# 리본 질감 — null = 단색(도입 전과 항등). 궤적 띠 전체에 UV로 매핑된다:
#   **가로 = 꼬리→선단(시간축) · 세로 = 칼끝→칼밑(날 폭)**. 그리는 쪽은 이 방향을 전제해야 한다.
# 🎨 🔴 **중립(그레이스케일)으로 그리고 색은 `fx_color`가 입힌다** — `blast.png` 선례와 같은 규약
#   (rules §4: "폭발 텍스처는 중립으로 그리고 원소색은 데이터가 입힌다"). 텍스처에 색을 박으면
#   `_fx_color`의 곱셈과 이중으로 걸려 탁해지고, 같은 질감을 다른 하위 직업에 재사용할 수 없다.
# ⚠ 알파가 곧 질감이다 — 리본은 이미 `vertex_colors`로 꼬리 페이드를 하므로, 텍스처 알파는
#   **얼룩·결**만 담당한다(전체를 어둡게 깔면 리본이 통째로 흐려진다).
@export var fx_trail_tex: Texture2D = null


# 자리별 특성 → {key, value, name}. 키가 비었으면 null(특성 없음 = 항등).
# 🔴 **공유 하위 직업의 메인 특성은 여기서 막는다** — 데이터에 실수로 채워 넣어도 메인 자리에
#   못 끼므로 도달 불가지만, 리졸버가 자리를 착각하는 순간 조용히 켜지는 것을 구조로 차단한다.
func trait_at(as_main: bool) -> Dictionary:
	if as_main:
		if is_shared() or main_trait_key.is_empty():
			return {}
		return {"key": main_trait_key, "value": main_trait_value, "name": main_trait_name}
	if sub_trait_key.is_empty():
		return {}
	return {"key": sub_trait_key, "value": sub_trait_value, "name": sub_trait_name}


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
