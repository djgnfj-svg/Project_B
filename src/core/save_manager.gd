extends Node
# 브라우저 로컬 저장 오토로드 (projectb-rules §1). user:// = 웹에선 IndexedDB (rules §5 — 웹 실기 검증 필수).
# 직렬화 대상 = GameState 인벤(골드·재료·도면·장비). 각 클라가 자기 것만 저장 (개인·비네트워크, GDD §3).
# 커밋 모델(GDD §11): 픽업/제작/강화 = 인메모리 즉시 → stage_cleared·마을 거래 시 commit(디스크).
#   전멸/마을 귀환 = reload()로 마지막 저장분 롤백 → 전멸 스테이지 픽업 소실, 클리어분 생존.
# ⚠ EventBus·GameState 전역 식별자를 직접 쓰지 않는다 — /root 경로로 접근 (rules §5 -s 컴파일 함정).

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1

# 저장 경로 — 오토로드는 기본값(user://save.json)을 쓴다. 헤드리스 테스트만 임시 경로로 교체해
# 실제 세이브를 안 건드리게 격리한다 (projectb-verify §1 세이브 테스트 경고). _ready 전에 설정할 것.
var save_path: String = SAVE_PATH
# GameState 주입 — 오토로드 환경은 null(→ /root/GameState). -s 헤드리스 테스트만 인스턴스를 넣어
# 트리 밖에서 검증한다 (절대경로 get_node가 -s에선 "active scene tree 밖"으로 실패, rules §5).
var game_state_override: Node = null


func _ready() -> void:
	load_from_disk()
	# 저장 시점(GDD §3·§11): 스테이지 클리어=commit(픽업 확정 영속), 전멸=reload(마지막 저장분 롤백).
	# EventBus는 /root로(rules §5). 클리어/전멸은 각 클라가 자기 인벤을 커밋/롤백(개인 저장).
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.stage_cleared.connect(commit)
		bus.stage_wiped.connect(reload)


func _gs() -> Node:
	if game_state_override != null:
		return game_state_override
	return get_node_or_null("/root/GameState")


# 인메모리 인벤을 디스크에 기록. 저장 시점 = 스테이지 클리어마다 + 마을 제작/강화 거래 후.
func commit() -> void:
	var gs := _gs()
	if gs == null:
		return
	var data := {"v": SAVE_VERSION, "inv": gs.to_save_dict()}
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		push_error("[SaveManager] 저장 파일 열기 실패: %s" % save_path)
		return
	f.store_string(JSON.stringify(data))
	f.close()


func load_from_disk() -> void:
	var gs := _gs()
	if gs == null or not FileAccess.file_exists(save_path):
		return
	var f := FileAccess.open(save_path, FileAccess.READ)
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
	# 파일이 없어 from_save_dict가 안 불려도(첫 판 전멸) 인벤 변동을 알린다 — HUD·스탯 공지 드리프트 방지.
	# 파일이 있으면 from_save_dict가 이미 emit했지만 중복은 무해(멱등 새로고침).
	if is_inside_tree():  # -s 테스트(트리 밖)는 /root 조회가 에러 — 오토로드는 항상 트리 안 (rules §5)
		var bus := get_node_or_null("/root/EventBus")
		if bus != null:
			bus.inventory_changed.emit()
