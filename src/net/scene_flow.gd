extends Node
# G_SCENE 송수신 공용 컴포넌트 — 씬 전환 지시(호스트)와 수신 검증을 한 곳에.
# 마을(게이트 출발)·스테이지(클리어/전멸 귀환)가 자식 노드로 문다 (rules §2 — 권한·동기화 로직 복사 금지).
# ⚠ 씬 전용 글루(오토로드 전역 식별자 사용) — -s 헤드리스 테스트에서 preload 금지 (rules §5).

const NetSchema := preload("res://src/core/net_schema.gd")

var _departed: bool = false  # 전환 지시 중복 방지 (연타·수신 에코)


func _ready() -> void:
	EventBus.net_msg.connect(_on_net_msg)


# 호스트 전용 — 비-스테이지 씬(마을) 전환 지시 브로드캐스트 + 로컬 전환. 게스트/중복 호출은 조용히 무시.
func request(scene_id: String) -> void:
	if _departed or not Net.is_host():
		return
	_departed = true
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_SCENE, "scene": scene_id})
	EventBus.scene_change.emit(scene_id)


# 호스트 전용 — 챕터 스테이지 전환 지시 (마을 출발·클리어 후 다음 칸·모닥불 출발 공용).
# 검증 단일 소스 = GameState.is_valid_stage — 수신 측(_on_net_msg)과 같은 함수를 지난다.
func request_stage(chapter_id: String, idx: int) -> void:
	if _departed or not Net.is_host():
		return
	if not GameState.is_valid_stage(chapter_id, idx):
		push_error("[SceneFlow] 무효 스테이지 지시 — %s[%d]" % [chapter_id, idx])
		return
	_departed = true
	GameState.begin_stage(chapter_id, idx)
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_SCENE,
		"scene": NetSchema.SCENE_STAGE, "c": chapter_id, "i": idx})
	EventBus.scene_change.emit(NetSchema.SCENE_STAGE)


func _on_net_msg(from_id: int, data: Dictionary) -> void:
	if str(data.get(NetSchema.KEY_KIND, "")) != NetSchema.G_SCENE:
		return
	if from_id != NetSchema.HOST_ID or Net.is_host() or _departed:
		return  # 씬 전환 지시는 호스트 발신만 신뢰 (rules §3) + 중복 방지
	var sid := str(data.get("scene", ""))
	if sid == NetSchema.SCENE_STAGE:
		# 신뢰 경계(rules §3): 챕터 id = data/chapters 스캔 allowlist, 인덱스 = 범위 검증 —
		# 임의 문자열/인덱스로 load 경로를 조작할 수 없다 (main의 로드 실패 폴백과 이중 방어)
		var cid := str(data.get("c", ""))
		var idx := int(data.get("i", -1))
		if not GameState.is_valid_stage(cid, idx):
			return
		_departed = true
		GameState.begin_stage(cid, idx)
		EventBus.scene_change.emit(NetSchema.SCENE_STAGE)
	elif sid == NetSchema.SCENE_VILLAGE:
		_departed = true
		EventBus.scene_change.emit(sid)
