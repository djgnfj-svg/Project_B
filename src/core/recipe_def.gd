class_name RecipeDef
extends Resource
# 제작 레시피 스키마 (core — 리드 전용). 개체는 data/recipes/*.tres (projectb-rules §4).
# 도면(설계도) = 이 레시피를 언락하는 토큰 — 도면 드랍의 ref_id = recipe id (GDD §7).
# 완성 장비는 직접 드랍하지 않는다 — 오직 제작으로만 얻는다 (GDD §6).

@export var id: String = ""                  # data/recipes/<id>.tres 파일명 = 도면 id (드랍 blueprint ref_id)
@export var display_name: String = ""
@export var result_equip_id: String = ""     # 결과 EquipDef id (GameState.equip_def로 리졸브 — allowlist)
@export var gold_cost: int = 0
@export var material_costs: Dictionary = {}   # mat_id(String) -> qty(int)
@export var unlocked_by_default: bool = false # true = 도면 없이 처음부터 제작 가능(튜토 제작템, GDD §7)
