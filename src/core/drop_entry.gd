class_name DropEntry
extends Resource
# 드랍 테이블의 한 항목 (core — 리드 전용). DropTable이 배열로 쥔다 (projectb-rules §4).
# 저작은 EnemyDef .tres 안의 sub_resource로 (goblin_melee.tres 등 참조).

# 종류: gold = 금액 범위, material = data/materials/<ref_id>, blueprint = data/recipes/<ref_id> 언락
@export_enum("gold", "material", "blueprint") var kind: String = "material"

@export var ref_id: String = ""     # material=재료 id, blueprint=레시피 id. gold는 무시
@export var chance: float = 1.0     # 드랍 확률 0~1 (gold는 무시 — gold_max>0이면 항상)
@export var qty_min: int = 1        # material 수량 하한
@export var qty_max: int = 1        # material 수량 상한
@export var gold_min: int = 0       # kind=gold 금액 하한
@export var gold_max: int = 0       # kind=gold 금액 상한
