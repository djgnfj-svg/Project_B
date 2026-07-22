extends Node
# G_SCENE 송수신 공용 컴포넌트 — 씬 전환 지시(호스트)와 수신 검증을 한 곳에.
# 마을(게이트 출발)·스테이지(클리어/전멸 귀환)가 자식 노드로 문다 (rules §2 — 권한·동기화 로직 복사 금지).
# ⚠ 씬 전용 글루(오토로드 전역 식별자 사용) — -s 헤드리스 테스트에서 preload 금지 (rules §5).

const NetSchema := preload("res://src/core/net_schema.gd")

var _departed: bool = false  # 전환 지시 중복 방지 (연타·수신 에코)


func _ready() -> void:
	EventBus.net_msg.connect(_on_net_msg)


# 호스트 전용 — 전환 지시 브로드캐스트 + 로컬 전환. 게스트/중복 호출은 조용히 무시.
func request(scene_id: String) -> void:
	if _departed or not Net.is_host():
		return
	_departed = true
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_SCENE, "scene": scene_id})
	EventBus.scene_change.emit(scene_id)


func _on_net_msg(from_id: int, data: Dictionary) -> void:
	if str(data.get(NetSchema.KEY_KIND, "")) != NetSchema.G_SCENE:
		return
	if from_id != NetSchema.HOST_ID or Net.is_host() or _departed:
		return  # 씬 전환 지시는 호스트 발신만 신뢰 (rules §3) + 중복 방지
	# allowlist — 임의 문자열로 씬 전환을 조작할 수 없게 (main의 매핑과 이중 방어)
	var sid := str(data.get("scene", ""))
	if sid == NetSchema.SCENE_STAGE or sid == NetSchema.SCENE_VILLAGE:
		_departed = true
		EventBus.scene_change.emit(sid)
