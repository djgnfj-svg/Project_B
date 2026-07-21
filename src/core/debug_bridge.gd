extends Node
# 웹 디버그 입력 브리지 — 브라우저 자동화(리드의 실기 검증·테스트)가 JS에서 입력 액션을
# 누르고 뗄 수 있게 한다: window.pb_press("move_left") / window.pb_release("move_left").
# URL 쿼리에 debug=1이 있을 때만 활성 — 일반 플레이 경로에선 아무것도 하지 않는다.
# 로컬 입력 시뮬레이션일 뿐이라 네트워크 신뢰 경계(rules §3 — 호스트 검증)는 그대로다.

var _cb_press: JavaScriptObject = null
var _cb_release: JavaScriptObject = null


func _ready() -> void:
	if not OS.has_feature("web"):
		return
	var search := str(JavaScriptBridge.eval("window.location.search", true))
	if not ("debug=1" in search):
		return
	_cb_press = JavaScriptBridge.create_callback(_on_press)
	_cb_release = JavaScriptBridge.create_callback(_on_release)
	var win: JavaScriptObject = JavaScriptBridge.get_interface("window")
	win.pb_press = _cb_press
	win.pb_release = _cb_release
	print("[debug_bridge] active (debug=1)")


func _on_press(args: Array) -> void:
	if args.size() >= 1:
		Input.action_press(str(args[0]))


func _on_release(args: Array) -> void:
	if args.size() >= 1:
		Input.action_release(str(args[0]))
