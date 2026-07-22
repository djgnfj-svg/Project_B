extends Node
# 브라우저 로컬 저장 오토로드 (projectb-rules §1). user:// = 웹에선 IndexedDB (rules §5 — 웹 실기 검증 필수).
# 직렬화 대상 = GameState 인벤(골드·재료·도면·장비). 각 클라가 자기 것만 저장 (개인·비네트워크, GDD §3).
# 커밋 모델(GDD §11): 픽업/제작/강화 = 인메모리 즉시 → stage_cleared·마을 거래 시 commit(디스크).
#   전멸/마을 귀환 = reload()로 마지막 저장분 롤백 → 전멸 스테이지 픽업 소실, 클리어분 생존.
# ⚠ EventBus·GameState 전역 식별자를 직접 쓰지 않는다 — /root 경로로 접근 (rules §5 -s 컴파일 함정).

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1


func _ready() -> void:
	load_from_disk()


func _gs() -> Node:
	return get_node_or_null("/root/GameState")


# 인메모리 인벤을 디스크에 기록. 저장 시점 = 스테이지 클리어마다 + 마을 제작/강화 거래 후.
func commit() -> void:
	var gs := _gs()
	if gs == null:
		return
	var data := {"v": SAVE_VERSION, "inv": gs.to_save_dict()}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("[SaveManager] 저장 파일 열기 실패: %s" % SAVE_PATH)
		return
	f.store_string(JSON.stringify(data))
	f.close()


func load_from_disk() -> void:
	var gs := _gs()
	if gs == null or not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary and int((parsed as Dictionary).get("v", 0)) == SAVE_VERSION:
		gs.from_save_dict((parsed as Dictionary).get("inv", {}))


# 전멸/마을 귀환 롤백 — 인메모리를 마지막 저장분으로 되돌린다. 저장 파일이 없으면 빈 인벤.
func reload() -> void:
	var gs := _gs()
	if gs == null:
		return
	gs.clear_inventory()
	load_from_disk()
