extends Node2D
# 조합 루트 — 로비 → 마을 ⇄ 스테이지 전환 (rules §2 src/main).
# 씬 전환 판단은 여기서만 한다. 각 씬은 자기 일만 하고 EventBus.scene_change로 알린다.
# 멀티에선 전환을 호스트가 지시(G_SCENE)하고, 수신·검증은 각 씬이 한 뒤 여기로 emit한다.

const NetSchema := preload("res://src/core/net_schema.gd")
const LobbyScene := preload("res://src/ui/lobby.tscn")
const VillageScene := preload("res://src/village/village.tscn")
const TestLabScript := preload("res://src/stage/test_lab.gd")  # ?test=1 패턴 랩 (프로덕션 무접촉)

var _current: Node = null


func _ready() -> void:
	print("Project_B boot OK")
	EventBus.room_created.connect(func(_code: String) -> void: _enter_after_room())
	EventBus.room_joined.connect(func(_code: String, _peers: Array[int]) -> void: _enter_after_room())
	EventBus.room_closed.connect(_to_lobby)
	EventBus.net_disconnected.connect(_to_lobby)
	EventBus.scene_change.connect(_on_scene_change)
	_to_lobby()


func _to_lobby() -> void:
	GameState.leave_chapter()  # 끊김/방 종료 — 이전 판의 챕터 좌표·이월 HP가 남지 않게
	_swap(LobbyScene.instantiate())


func _to_village() -> void:
	GameState.leave_chapter()
	# 직업 전환 뒤처리 3종(귀속 재검증 + 시작 무기 + 시작 하위 직업) — GameState 단일 소스(멱등).
	# 🔴 로비에서 고른 직업이 **실제로 확정되는 경계**가 여기다: 세이브 로드는 직업을 모르므로
	#   "법사로 지팡이를 낀 채 저장 → 전사로 재접속"의 무기 정리도 이 줄이 한다(2026-07-26 신고).
	GameState.apply_job_loadout()
	_swap(VillageScene.instantiate())


# 방 생성/참가 후 진입 — 기본 마을. 테스트 모드(?test=1)면 마을·잔몹 스킵하고 보스 아레나 직행(패턴 랩).
func _enter_after_room() -> void:
	if TestMode.is_active():
		_to_boss_test()
	else:
		_to_village()


# 테스트 랩 — 첫 챕터 마지막 칸(보스)으로 직행 + 랩 컨트롤러 부착. 솔로 호스트 전제.
func _to_boss_test() -> void:
	GameState.leave_chapter()
	GameState.apply_job_loadout()
	var chapters := GameState.chapter_ids()
	if chapters.is_empty():
		_to_village()
		return
	var cid: String = chapters[0]
	var boss_idx := GameState.chapter_def(cid).stage_count() - 1
	GameState.begin_stage(cid, boss_idx)
	var ps := load(GameState.stage_scene_path()) as PackedScene
	if ps == null:
		push_error("[main] 테스트 보스 씬 로드 실패 — 마을 폴백")
		GameState.leave_chapter()
		_to_village()
		return
	var stage := ps.instantiate()
	_swap(stage)
	var lab := TestLabScript.new()   # 스테이지 위에 랩 UI/NPC를 얹는다 (프로덕션 경로는 안 탐)
	lab.name = "TestLab"
	stage.add_child(lab)


# 씬 id → 씬 매핑 — id는 net_schema SCENE_*가 단일 소스. 모르는 id는 무시(allowlist).
# 스테이지 씬 경로는 GameState(챕터 좌표 — scene_flow 검증을 통과한 값)에서 리졸브한다.
func _on_scene_change(scene_id: String) -> void:
	# 테스트 랩(?test=1): 보스를 깨거나 전멸해도 마을로 안 가고 **새 보스로 다시** 시작한다.
	# 마을 왕복 없이 같은 보스를 반복 테스트하기 위함 (프로덕션 무접촉 — TestMode 게이트).
	if TestMode.is_active() and scene_id == NetSchema.SCENE_VILLAGE:
		_to_boss_test()
		return
	match scene_id:
		NetSchema.SCENE_VILLAGE:
			GameState.leave_chapter()  # 귀환 = 챕터 종료 (완주·전멸 공통) — 이월 HP 리셋
			# 전멸 롤백으로 무기를 잃었으면 재지급(멱등) + 귀속 재검증 — _to_village와 같은 한 줄.
			# ⚠ leave_chapter() 뒤여야 한다: revalidate_equipped은 판 도중(in_chapter)엔 돌지 않는다.
			# 🔴 **여기가 판 중 해금분이 슬롯에 껴지는 유일한 자리다** (조립 축 v2.0, 리뷰 I-1).
			# autofill_sub_slots는 판 도중(in_chapter)엔 슬롯을 안 바꾼다 — 특성이 판 도중 켜지면
			# 내 판정 기하만 먼저 넓어져 타격이 무음 거부되기 때문(§3). 그래서 "마을에 돌아올 때
			# 채운다"로 미뤄 뒀는데, 이 줄이 없으면 **보스를 깨고 해금해도 칸이 영영 빈 채로 남는다**
			# (토스트만 뜨고 아무것도 안 세짐 = 조립 축의 첫 경험이 망가진다). 멱등이라 안전하다.
			GameState.apply_job_loadout()
			_swap(VillageScene.instantiate())
		NetSchema.SCENE_STAGE:
			var path := GameState.stage_scene_path()
			var ps := load(path) as PackedScene
			if ps == null:
				push_error("[main] 스테이지 씬 로드 실패 '%s' — 마을 폴백" % path)
				GameState.leave_chapter()
				_swap(VillageScene.instantiate())
				return
			_swap(ps.instantiate())
		_:
			push_warning("[main] 모르는 씬 id '%s' — 전환 무시" % scene_id)


# 🔴 **이전 씬을 트리에서 먼저 뗀다 — `queue_free()`만으로는 부족하다** (2026-08-01 실기 신고
#   "잡몹 스테이지2 갈 때 멈춘다"의 원인). `queue_free`는 **프레임 끝**에 실행되는데 바로 아래
#   `add_child(next)`는 새 씬의 `_ready`를 **그 자리에서 동기 실행**한다 → 그 순간 이전 씬 노드가
#   아직 그룹에 살아 있어, `_ready`에서 그룹을 **일회 스캔**하는 컴포넌트가 유령을 딕셔너리에
#   영구히 박는다(실측: stage_2의 스캔이 `["stage_1", "stage_2"]`를 잡았다). 다음 프레임에 그것이
#   해제되면 `entry["health"] as HealthComponent`가 **캐스트 단계에서** 터진다 —
#   `SCRIPT ERROR: Trying to cast a freed object.` → 그 함수가 통째로 중단된다.
#   ⚠ `x == null` 가드로는 못 막는다. **캐스트가 먼저 터진다.**
#   실제 피해: `combat_authority._check_clear`가 첫 반복에서 죽어 **스테이지2가 영영 클리어되지
#   않았고**(Dictionary는 삽입 순서라 유령이 항상 첫 항목), `mob_sync._physics_process`도 같은 자리에서
#   죽어 `G_MOB_POS`가 안 나가 **게스트 화면의 잔몹이 얼어붙었다**(초당 60회 에러).
#   `remove_child`는 그룹 조회에서 **즉시** 빠진다(실측 1 → 0). rules §5 「씬 스왑 프레임엔 이전 씬
#   노드가 그룹에 남아 있다」의 근본 처방이다 — 그 항목은 매 프레임 스캔(player)만 리시로 덮고 있었다.
# 🔴🔴 **이것은 「그룹 조회」만 닫는다 — EventBus 구독은 그대로 살아 있다** (netreview 2026-08-01).
#   `remove_child`는 시그널을 끊지 않는다(`src/` 전체에 `_exit_tree`·`disconnect(`가 0건이고, 구독은
#   프레임 끝 `queue_free`로 **객체가 해제될 때** 비로소 끊긴다). 그래서 rules §2에 등재된
#   「한 프레임 동안 두 씬의 ExpAuthority가 같이 `net_msg`에 붙어 G_EXP가 2배 적립된다」 창은
#   **여전히 열려 있다.** 실재 근거도 확인됐다 — `net.gd`가 `while ...get_available_packet_count()`로
#   한 프레임에 여러 패킷을 동기 emit하고, 게스트는 SceneFlow가 **그 루프 안에서** `scene_change`를
#   올린다. 지금은 `ChapterFlow.NEXT_DELAY_S`(3초)가 도달을 막아 무해할 뿐이다.
#   ⚠ **이 줄을 "근본 처방"이라고 읽고 §2의 G_EXP dedup 게이트를 지우지 마라** — 그건 별개 축이다.
func _swap(next: Node) -> void:
	if _current != null:
		remove_child(_current)
		_current.queue_free()
	_current = next
	add_child(next)
