extends Node2D
# 마을 씬 — 걸어 다니는 거점 (GDD §3). 지금은 스폰 + 출발 게이트만; 제작·강화·창고는 이후 확장.
# 씬 전환 확정 권한 = 호스트 (rules §1·§3): 호스트가 게이트 앞에서 상호작용(interact)하면
# 자식 SceneFlow가 G_SCENE 브로드캐스트 + 수신 검증을 담당 (rules §2 — 복사 금지, 스테이지와 공용).
# 피어 동기화는 자식 PeerSync가 담당 — 여기서 스폰/G_POS를 다루지 않는다.

const NetSchema := preload("res://src/core/net_schema.gd")
const PlayerActor := preload("res://src/player/player.gd")
const SceneFlowNode := preload("res://src/net/scene_flow.gd")

var _local_in_gate: bool = false  # 로컬 플레이어가 게이트 영역 안 — 상호작용 게이트 + 안내 표시

@onready var _gate: Area2D = $Gate
@onready var _hint: Label = $Gate/Hint
@onready var _scene_flow: SceneFlowNode = $SceneFlow


func _ready() -> void:
	_gate.body_entered.connect(_on_gate_body_entered)
	_gate.body_exited.connect(_on_gate_body_exited)
	_hint.visible = false


# 출발 확인은 폴링이 아니라 _unhandled_input — UI(Control)가 소비한 입력은 여기 안 온다
func _unhandled_input(event: InputEvent) -> void:
	if not (_local_in_gate and event.is_action_pressed("interact")):
		return
	# 게스트의 F는 SceneFlow가 무시 — 출발 권한은 호스트만 (안내는 진입 시 이미 표시)
	_scene_flow.request(NetSchema.SCENE_STAGE)


func _on_gate_body_entered(body: Node2D) -> void:
	var p := body as PlayerActor
	if p == null or not p.is_local:
		return  # 원격 아바타의 진입은 무시 — 안내·상호작용은 각자 자기 로컬만
	_local_in_gate = true
	_hint.text = "F — 스테이지로 출발" if Net.is_host() else "방장이 출발할 수 있어요"
	_hint.visible = true


func _on_gate_body_exited(body: Node2D) -> void:
	var p := body as PlayerActor
	if p == null or not p.is_local:
		return
	_local_in_gate = false
	_hint.visible = false
