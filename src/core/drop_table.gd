class_name DropTable
extends Resource
# 드랍 테이블 (core — 리드 전용). EnemyDef.drop_table이 쥔다 — "새 적 = 파일 한 장" (projectb-rules §4).
# 드랍 롤(roll)은 호스트만 부른다 (드랍 생성 = 호스트 권한, rules §1·§3). 결과를 브로드캐스트한다.

@export var entries: Array[DropEntry] = []


# 호스트가 킬(또는 상자 개봉) 시 1회 롤. rng를 주입받아 결정론 테스트 가능(시드 고정).
# 반환 = [{kind, id, qty}] — gold는 {kind="gold", id="", qty=금액}. 빈 배열이면 드랍 없음.
func roll(rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for e: DropEntry in entries:
		if e.kind == "gold":
			if e.gold_max > 0:
				out.append({
					"kind": "gold", "id": "",
					"qty": rng.randi_range(e.gold_min, maxi(e.gold_min, e.gold_max)),
				})
		elif rng.randf() <= e.chance:
			out.append({
				"kind": e.kind, "id": e.ref_id,
				"qty": rng.randi_range(e.qty_min, maxi(e.qty_min, e.qty_max)),
			})
	return out
