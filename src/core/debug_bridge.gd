extends Node
# 웹 디버그 브리지 — 브라우저 자동화(리드의 실기 검증·테스트)용. URL 쿼리에 debug=1일 때만 활성.
#  window.pb_press("액션") / pb_release("액션") : 입력 액션을 이벤트로 주입
#    (parse_input_event 경유 — _unhandled_input(공격)과 폴링(get_vector·just_pressed) 둘 다 구동)
#  window.pb_dump() : 게임 상태(방·플레이어 위치·적 HP)를 console.log("[PB] …")로 출력
#  window.pb_hurt(pid, dmg) : 호스트 전용 — 플레이어 데미지를 권한 경로(Health.apply_damage)로 주입.
#    잔몹 없이 데미지→php 브로드캐스트→HUD→사망까지 전 구간 실기 검증용.
#  window.pb_smite(eid, dmg) : 호스트 전용 — 적 데미지를 권한 경로로 주입 (확정→ehp→클리어 판정).
#    조준(마우스)은 자동화 불가라, 적중 이후의 챕터 진행 파이프라인 실기 검증용.
# 로컬 입력 시뮬레이션/관측일 뿐 네트워크 신뢰 경계(rules §3)는 그대로다.

var _cb_press: JavaScriptObject = null
var _cb_release: JavaScriptObject = null
var _cb_dump: JavaScriptObject = null
var _cb_hurt: JavaScriptObject = null
var _cb_smite: JavaScriptObject = null


func _ready() -> void:
	if not OS.has_feature("web"):
		return
	var search := str(JavaScriptBridge.eval("window.location.search", true))
	if not ("debug=1" in search):
		return
	_cb_press = JavaScriptBridge.create_callback(_on_press)
	_cb_release = JavaScriptBridge.create_callback(_on_release)
	_cb_dump = JavaScriptBridge.create_callback(_on_dump)
	_cb_hurt = JavaScriptBridge.create_callback(_on_hurt)
	_cb_smite = JavaScriptBridge.create_callback(_on_smite)
	var win: JavaScriptObject = JavaScriptBridge.get_interface("window")
	win.pb_press = _cb_press
	win.pb_release = _cb_release
	win.pb_dump = _cb_dump
	win.pb_hurt = _cb_hurt
	win.pb_smite = _cb_smite
	print("[debug_bridge] active (debug=1)")


func _on_press(args: Array) -> void:
	if args.size() >= 1:
		_send_action(str(args[0]), true)


func _on_release(args: Array) -> void:
	if args.size() >= 1:
		_send_action(str(args[0]), false)


func _send_action(action_name: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action_name
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _on_dump(_args: Array) -> void:
	var net: Node = get_tree().root.get_node_or_null("Net")
	var gs: Node = get_tree().root.get_node_or_null("GameState")
	var out := {
		"my_id": net.get("my_id") if net != null else -1,
		"room": net.get("room_code") if net != null else "",
		"chapter": gs.get("current_chapter_id") if gs != null else "",
		"stage_idx": gs.get("current_stage_idx") if gs != null else -1,
		"players": {},
		"enemies": {},
	}
	for p: Node in get_tree().get_nodes_in_group("player"):
		var body := p as Node2D
		var ph: Node = p.get_node_or_null("Health")
		out["players"][str(p.get("peer_id"))] = [
			roundf(body.global_position.x), roundf(body.global_position.y), bool(p.get("is_local")),
			int(ph.get("hp")) if ph != null else -1]
	for e: Node in get_tree().get_nodes_in_group("enemy"):
		var eh: Node = e.get_node_or_null("Health")
		out["enemies"][str(e.get("eid"))] = {
			"hp": int(eh.get("hp")) if eh != null else int(e.get("hp")),
			"visible": (e as Node2D).visible}
	JavaScriptBridge.eval("console.log('[PB] ' + %s)" % JSON.stringify(JSON.stringify(out)), true)


# 호스트 전용 — 권한 경로 그대로(Health.apply_damage → hp_confirmed → php 브로드캐스트) 데미지 주입
func _on_hurt(args: Array) -> void:
	var net: Node = get_tree().root.get_node_or_null("Net")
	if net == null or not bool(net.call("is_host")) or args.size() < 2:
		return
	var pid := int(args[0])
	for p: Node in get_tree().get_nodes_in_group("player"):
		if int(p.get("peer_id")) == pid:
			var h: Node = p.get_node_or_null("Health")
			if h != null:
				h.call("apply_damage", int(args[1]))
			return


# 호스트 전용 — 적 데미지를 권한 경로 그대로(apply_damage → ehp 브로드캐스트 → 클리어 판정) 주입
func _on_smite(args: Array) -> void:
	var net: Node = get_tree().root.get_node_or_null("Net")
	if net == null or not bool(net.call("is_host")) or args.size() < 2:
		return
	var eid := str(args[0])
	for e: Node in get_tree().get_nodes_in_group("enemy"):
		if str(e.get("eid")) == eid:
			var h: Node = e.get_node_or_null("Health")
			if h != null:
				h.call("apply_damage", int(args[1]))
			return
