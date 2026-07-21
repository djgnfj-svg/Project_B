extends SceneTree
# 멀티 방 왕복 자동 테스트 — 중계 서버가 먼저 떠 있어야 한다 (CLAUDE.md 「검증 명령」의 스위트 명령 참조).
# 2 프로세스로 돌린다:
#   role=host  : 방 생성 → codefile에 코드 기록 → 게스트 합류 대기 → ping 송신 → pong 수신 = PASS(즉시 종료 = 호스트 이탈)
#   role=guest : codefile 폴링 → 방 참가 → ping 수신 → pong 응답 → 호스트 이탈로 room_closed 수신
#                → 재사용 연결로 새 방 생성 성공 = PASS (방 종료 후 상태기계 데드락 회귀 방지)
# 성공 시 "TEST_OK"를 찍고 exit 0, 실패/타임아웃 시 "TEST_FAIL"과 exit 1 (침묵 통과 방지 — projectb-verify §3).


func _initialize() -> void:
	var driver := Driver.new()
	driver.name = "TestDriver"
	root.add_child(driver)


class Driver:
	extends Node

	const NetSchema := preload("res://src/core/net_schema.gd")
	const NetScript := preload("res://src/net/net.gd")
	const EventBusScript := preload("res://src/core/event_bus.gd")

	const TIMEOUT := 15.0
	const RETRY_DELAY := 1.0
	const MAX_CONNECT_TRIES := 5
	const QUIT_FLUSH_DELAY := 0.5  # 마지막 송신이 소켓으로 나가도록 종료 전 잠깐 폴링 유지

	var role := ""
	var codefile := ""
	var url := "ws://localhost:9081"

	var _net: NetScript = null
	var _elapsed := 0.0
	var _retry_accum := 0.0
	var _connect_tries := 0
	var _joined := false
	var _awaiting_close := false  # 게스트: pong 응답 후 room_closed 대기 중
	var _quit_accum := -1.0  # 0 이상이면 종료 카운트다운 중


	func _ready() -> void:
		for arg: String in OS.get_cmdline_user_args():
			if arg.begins_with("role="):
				role = arg.trim_prefix("role=")
			elif arg.begins_with("codefile="):
				codefile = arg.trim_prefix("codefile=")
			elif arg.begins_with("url="):
				url = arg.trim_prefix("url=")
		if role != "host" and role != "guest":
			_fail("unknown role '%s'" % role)
			return
		if codefile.is_empty():
			_fail("codefile 인자 없음")
			return
		# -s 실행에선 오토로드가 없다 — 오토로드와 같은 이름으로 수동 구성 (Net보다 EventBus 먼저)
		if not get_tree().root.has_node("EventBus"):
			var bus: Node = EventBusScript.new()
			bus.name = "EventBus"
			get_tree().root.add_child(bus)
		if not get_tree().root.has_node("Net"):
			_net = NetScript.new()
			_net.name = "Net"
			get_tree().root.add_child(_net)
		else:
			_net = get_tree().root.get_node("Net") as NetScript
		var bus_node: Node = get_tree().root.get_node("EventBus")
		bus_node.connect("room_created", _on_room_created)
		bus_node.connect("room_joined", _on_room_joined)
		bus_node.connect("peer_joined", _on_peer_joined)
		bus_node.connect("net_msg", _on_net_msg)
		bus_node.connect("room_closed", _on_room_closed)
		bus_node.connect("net_connect_failed", _on_connect_failed)
		bus_node.connect("room_join_failed",
			func(reason: String) -> void: _fail("room_join_failed: " + reason))
		if role == "host":
			_try_connect()


	func _process(delta: float) -> void:
		_elapsed += delta
		if _quit_accum >= 0.0:
			_quit_accum += delta
			if _quit_accum >= QUIT_FLUSH_DELAY:
				get_tree().quit(0)
			return
		if _elapsed > TIMEOUT:
			_fail("timeout %.0fs (role=%s)" % [TIMEOUT, role])
			return
		# 재시도 대기
		if _retry_accum > 0.0:
			_retry_accum -= delta
			if _retry_accum <= 0.0:
				_try_connect()
			return
		# 게스트: 호스트가 방 코드를 쓸 때까지 폴링
		if role == "guest" and not _joined and _net.state == NetScript.State.DISCONNECTED:
			if FileAccess.file_exists(codefile):
				var code := FileAccess.get_file_as_string(codefile).strip_edges()
				if not code.is_empty():
					print("[test:%s] joining room %s" % [role, code])
					_joined = true
					_net.join_room(url, code)


	func _try_connect() -> void:
		if role == "host":
			_connect_tries += 1
			print("[test:host] connect try %d" % _connect_tries)
			_net.host_room(url)


	func _on_connect_failed(reason: String) -> void:
		if role == "host" and _connect_tries < MAX_CONNECT_TRIES:
			_retry_accum = RETRY_DELAY  # 릴레이가 아직 안 떴을 수 있음 — 재시도
			return
		if role == "guest":
			_joined = false
			_retry_accum = RETRY_DELAY
			return
		_fail("connect failed: " + reason)


	func _on_room_created(code: String) -> void:
		if role == "host":
			print("[test:host] room created: %s" % code)
			var f := FileAccess.open(codefile, FileAccess.WRITE)
			if f == null:
				_fail("codefile 쓰기 실패: " + codefile)
				return
			f.store_string(code)
			f.close()
		else:
			# 게스트 2단계: 방 종료 후 재사용 연결로 새 방 생성 성공 = PASS
			print("[test:guest] room_closed 후 새 방 생성 성공: %s" % code)
			_pass()


	func _on_room_closed() -> void:
		if role == "guest" and _awaiting_close:
			print("[test:guest] room_closed 수신 — 재사용 연결로 새 방 생성 시도")
			_awaiting_close = false
			_net.host_room(url)


	func _on_room_joined(code: String, peer_ids: Array[int]) -> void:
		print("[test:guest] joined %s, existing peers=%s" % [code, str(peer_ids)])
		if peer_ids != [NetSchema.HOST_ID]:
			_fail("기존 피어 목록이 [1]이 아님: %s" % str(peer_ids))


	func _on_peer_joined(peer_id: int) -> void:
		print("[test:%s] peer %d joined" % [role, peer_id])
		if role == "host":
			_net.send_game({NetSchema.KEY_KIND: "ping"})


	func _on_net_msg(from_id: int, data: Dictionary) -> void:
		var kind := str(data.get(NetSchema.KEY_KIND, ""))
		if role == "guest" and kind == "ping":
			print("[test:guest] ping from %d — pong 응답, 호스트 이탈 대기" % from_id)
			_net.send_game({NetSchema.KEY_KIND: "pong"})
			_awaiting_close = true
		elif role == "host" and kind == "pong":
			print("[test:host] pong from %d — 왕복 확인" % from_id)
			_pass()


	func _pass() -> void:
		print("TEST_OK role=%s" % role)
		_quit_accum = 0.0


	func _fail(msg: String) -> void:
		printerr("TEST_FAIL role=%s — %s" % [role, msg])
		get_tree().quit(1)
