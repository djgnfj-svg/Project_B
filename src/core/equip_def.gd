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


func slot() -> int:
	return SLOT_ARMOR if slot_name == "armor" else SLOT_WEAPON
