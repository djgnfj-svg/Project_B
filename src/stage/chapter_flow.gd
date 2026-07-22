extends Node
# 챕터 진행 결정 컴포넌트 — CombatAuthority의 클리어/전멸 신호를 받아 호스트가 다음 씬을 지시한다.
# 클리어: 마지막 칸이면 챕터 완주 → 마을, 아니면 다음 칸(모닥불 포함) — 칸 목록은 ChapterDef(data)가 쥔다.
# 전멸: 마을 귀환 — 재도전은 챕터 처음부터 (GDD §4 확정). 전투 씬이 SceneFlow와 함께 자식으로 문다.
# 전환 확정 권한 = 호스트 (rules §1·§3) — 게스트는 G_SCENE 수신(SceneFlow)으로만 따라온다.
# ⚠ 씬 전용 글루(오토로드 전역 식별자 사용) — -s 헤드리스 테스트에서 preload 금지 (rules §5).

const NetSchema := preload("res://src/core/net_schema.gd")
const SceneFlowNode := preload("res://src/net/scene_flow.gd")

const NEXT_DELAY_S := 3.0  # 클리어/전멸 배너 연출 후 전환 지연 (연출값)

@export var scene_flow_path: NodePath  # 형제 SceneFlow — 전환 지시 송신로

var _scene_flow: SceneFlowNode = null


func _ready() -> void:
	_scene_flow = get_node(scene_flow_path) as SceneFlowNode
	if _scene_flow == null:
		push_error("[ChapterFlow] scene_flow_path 미배선 — 진행 전환 불능")
		return
	EventBus.stage_cleared.connect(_on_cleared)
	EventBus.stage_wiped.connect(_on_wiped)


func _on_cleared() -> void:
	if not Net.is_host():
		return
	# 목적지는 지금 확정해 캡처 — 타이머 발화 시점의 GameState 드리프트에 좌우되지 않게
	var chapter := GameState.current_chapter_id
	var next_idx := GameState.current_stage_idx + 1
	var chapter_done := GameState.is_last_stage()
	_transition_later(func(sf: SceneFlowNode) -> void:
		if chapter_done:
			sf.request(NetSchema.SCENE_VILLAGE)  # 챕터 완주 — 보상 지급은 드랍/제작 시스템에서 (후속)
		else:
			sf.request_stage(chapter, next_idx))


func _on_wiped() -> void:
	if not Net.is_host():
		return
	_transition_later(func(sf: SceneFlowNode) -> void:
		sf.request(NetSchema.SCENE_VILLAGE))


# ⚠ SceneTree 타이머는 씬 해제 후에도 발화한다 — self 멤버 대신 로컬 캡처 + is_instance_valid
# (combat_authority와 동일 규약 — 끊김→로비 전환 등으로 지연 중 씬이 해제되는 케이스)
func _transition_later(action: Callable) -> void:
	var sf := _scene_flow
	get_tree().create_timer(NEXT_DELAY_S).timeout.connect(func() -> void:
		if is_instance_valid(sf):
			action.call(sf))
