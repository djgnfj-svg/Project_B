class_name EquipDef
extends Resource
# 장비 정의 스키마 (core — 리드 전용). 개체는 data/equipment/*.tres (projectb-rules §4).
# 🔒 장비는 수치만 (GDD §6). 스탯 합산·강화 결과는 CombatMath 단일 소스가 계산 (rules §3).

const SLOT_WEAPON := 0
const SLOT_ARMOR := 1

@export var id: String = ""            # data/equipment/<id>.tres 파일명과 일치 — 인벤/레시피/저장의 키
@export var display_name: String = ""
@export_multiline var description: String = ""  # 아이템 툴팁 설명(선택) — 비면 스탯만 표시 (UI item_ui 헬퍼)
@export var icon: Texture2D            # 제작/강화 UI·인벤 표시 (도형 금지, rules §0)
@export_enum("weapon", "armor") var slot_name: String = "weapon"

# 기본 수치 + 강화 단계당 증가 (레벨 0 = 미강화). CombatMath.equip_stat_at_level이 base + step*level.
@export var base_attack: int = 0
@export var base_hp: int = 0
@export var atk_per_level: int = 0
@export var hp_per_level: int = 0
@export var max_level: int = 5
@export var upgrade_gold_base: int = 10  # 강화 비용 = base * (다음레벨) — CombatMath.upgrade_cost

# 무기 표시용 (slot=weapon만) — JobDef.weapon_texture/grip을 장비로 이관하는 자리 (rules §3).
# 장비 착용 시 player.gd의 WeaponPivot/Weapon 텍스처를 이걸로 교체 (후속 슬라이스).
@export var weapon_texture: Texture2D
@export var weapon_grip: Vector2 = Vector2(4, 8)

# 무기 손맛 (slot=weapon만) — 무기별 평타 연출. player.set_weapon_visual이 읽어 로컬·원격 모두 반영.
# ⚠ 손맛 "전역 크기"(셰이크 상한·페이드 시간 등)는 스크립트 const가 정본(rules §0) — 여기 값은
#   "이 무기가 어느 연출을 쓰는가"(콘텐츠·rules §4)와 무게 배율뿐이다. 전부 표시 전용(네트워크 0).
@export_group("무기 손맛")
@export var swing_texture: Texture2D               # 스윙 궤적 FX 트레일 (null → 기본 swoosh_arc 폴백)
@export var swing_tex_radius: float = 46.0         # swing_texture 호 바깥 반지름(px) — 스케일=도달/반지름 정합 (rules §3)
@export var swing_color: Color = Color(1, 1, 1, 1) # 궤적 틴트(그레이스케일 도트 재활용용, 페이드 알파와 곱)
@export var swing_sfx: String = "swing"            # 스윙(휘두름) 효과음 id (Audio.SFX 키)
@export var hit_sfx: String = ""                   # 적중 시 무기 고유 타격음 id (비면 무음 — 범용 피격음은 combat_impact가 별도 재생)
@export var hit_shake: float = 1.5                 # 적중 시 스크린셰이크 강도 (무기 무게감)

# 스윙 모션(휘두르는 동작) — 무기별로 호 넓이·속도·내지르기를 갈라 무게감을 동작으로 표현. 스윙형 한정.
# ⚠ swing_time 계약(rules §3): 반드시 착용 직업의 attack_cooldown보다 짧아야 한다 — 원격 스윙 창-잠금
#   가드(play_attack_fx)가 정당한 연속 공격의 연출을 무시하지 않게. (전사 쿨다운 0.4s)
@export var swing_arc: float = 1.9                 # 스윙 호 반각(rad) — 조준각 기준 ±이만큼 쓸고 지나감 (클수록 넓게)
@export var swing_time: float = 0.25              # 스윙 창 길이(s) — 클수록 느리고 묵직 (반드시 < attack_cooldown)
@export var swing_lunge: float = 5.0             # 스윕 중 앞으로 내지르는 거리(px)


func slot() -> int:
	return SLOT_ARMOR if slot_name == "armor" else SLOT_WEAPON
