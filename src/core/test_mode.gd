extends Node
# 테스트 모드 — ?test=1(웹) / --test(네이티브)일 때만 활성. 기본 OFF라 프로덕션(master) 무영향.
# 켜지면: 솔로 자동 호스트 → 보스 아레나 직행 + 패턴 테스트 랩(무적 플레이어 + 무적 NPC 더미 + 패턴 버튼 패널).
# ⚠ "마스터랑 겹치지 않게" = is_active()가 꺼지면 모든 훅이 항등이다. 훅은 전부 TestMode.is_active() 가드.
#   (오토로드 전역 식별자라 -s 헤드리스 테스트가 preload하는 파일에서는 참조 금지 — rules §5.
#    실제 참조처는 씬 스크립트뿐. health_component은 필드만 두고 여기를 참조하지 않는다.)

const NPC_PEER_ID := 777  # 랩 더미 파트너의 가짜 피어 id — 코옵 2인 카운트를 채운다("player" 그룹 기준)

var _active: bool = false


func _ready() -> void:
	if OS.has_feature("web"):
		var search := str(JavaScriptBridge.eval("window.location.search", true))
		_active = "test=1" in search
	else:
		_active = OS.get_cmdline_args().has("--test")
	if _active:
		print("[test_mode] ACTIVE — 패턴 테스트 랩 (솔로·무적·NPC 더미)")


func is_active() -> bool:
	return _active
