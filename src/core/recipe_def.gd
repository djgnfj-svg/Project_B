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
# 도면 등급 — 0=일반(흰) · 1=희귀(파랑) · 2=핵심(금). `MaterialDef.rarity`와 **같은 척도**다
# (드랍 등급 연출 `item_dropped`/`item_picked`·`G_DROP "r"`이 그 값을 그대로 읽는다).
# 🔴 전에는 `drop_authority._rarity_of()`가 도면을 **2로 하드코딩**해서 모든 설계도가 같은 금색이었다
#   — 등급 배관은 이미 다 깔려 있었고 도면만 데이터 자리가 없었다(2026-07-28에 이 필드로 열었다).
# 관례 = **결과 장비의 티어**: 첫 제작(철 무기) 1 · 보스 재료가 드는 상위 무기 2.
@export var rarity: int = 1
