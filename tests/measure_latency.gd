extends SceneTree
# 릴레이 왕복 지연 계측기 — 자동 테스트가 아니라 **진단 도구**다(그래서 _auto 접미사 없음, 스위트 미포함).
# 실제 게임 경로와 같은 홉을 잰다: 클라A → 릴레이 → 클라B → 릴레이 → 클라A.
# 이 왕복이 곧 "게스트가 움직임 → 호스트가 그 위치로 판정 → 게스트가 결과를 봄"의 전체 지연이다.
#
# 2 프로세스로 돌린다 (test_net_room_auto와 같은 codefile 랑데부):
#   role=host  : 방 생성 → 게스트 합류 대기 → ping N회(간격 GAP_MS) → pong RTT 기록 → 통계 출력
#   role=guest : 참가 → ping 수신 즉시 pong 회신(에코)
# 인자: role= codefile= url= [count=] [gap_ms=]
# 출력: LATENCY_OK + "rtt_ms min/median/p95/max/mean" (실패 시 LATENCY_FAIL + exit 1)


func _initialize() -> void:
	var driver := Driver.new()
	driver.name = "LatencyDriver"
	root.add_child(driver)


class Driver:
	extends Node

	const NetSchema := preload("res://src/core/net_schema.gd")
	const NetScript := preload("res://src/net/net.gd")
	const EventBusScript := preload("res://src/core/event_bus.gd")

	const TIMEOUT := 60.0
	const RETRY_DELAY := 1.0
	const MAX_CONNECT_TRIES := 5
	const QUIT_FLUSH_DELAY := 0.5

	var role := ""
	var codefile := ""
	var url := "ws://localhost:9080"
	var count := 40
	var gap_ms := 120.0
	var pad := 0  # ping 페이로드 패딩 바이트 (Nagle/지연ACK 진단용)

	var _net: NetScript = null
	var _elapsed := 0.0
	var _retry_accum := 0.0
	var _connect_tries := 0
	var _joined := false
	var _quit_accum := -1.0

	var _samples: Array[float] = []
	var _seq := 0
	var _sent_usec: Dictionary = {}  # seq -> 송신 시각(usec)
	var _gap_accum := 0.0
	var _peer_ready := false


	func _ready() -> void:
		for arg: String in OS.get_cmdline_user_args():
			if arg.begins_with("role="):
				role = arg.trim_prefix("role=")
			elif arg.begins_with("codefile="):
				codefile = arg.trim_prefix("codefile=")
			elif arg.begins_with("url="):
				url = arg.trim_prefix("url=")
			elif arg.begins_with("count="):
				count = int(arg.trim_prefix("count="))
			elif arg.begins_with("gap_ms="):
				gap_ms = float(arg.trim_prefix("gap_ms="))
			elif arg.begins_with("pad="):
				pad = int(arg.trim_prefix("pad="))
		if role != "host" and role != "guest":
			_fail("unknown role '%s'" % role)
			return
		if codefile.is_empty():
			_fail("codefile 인자 없음")
			return
		# 폴링 해상도가 곧 측정 해상도다 — 프레임 상한을 풀어 ms 이하로 (헤드리스 단발 실행이라 무해)
		Engine.max_fps = 0
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
		bus_node.connect("peer_joined", _on_peer_joined)
		bus_node.connect("net_msg", _on_net_msg)
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
			_fail("timeout %.0fs (role=%s, samples=%d)" % [TIMEOUT, role, _samples.size()])
			return
		if _retry_accum > 0.0:
			_retry_accum -= delta
			if _retry_accum <= 0.0:
				_try_connect()
			return
		if role == "guest" and not _joined and _net.state == NetScript.State.DISCONNECTED:
			if FileAccess.file_exists(codefile):
				var code := FileAccess.get_file_as_string(codefile).strip_edges()
				if not code.is_empty():
					_joined = true
					_net.join_room(url, code)
			return
		if role == "host" and _peer_ready and _seq < count:
			_gap_accum += delta * 1000.0
			if _gap_accum >= gap_ms:
				_gap_accum = 0.0
				_ping()


	func _try_connect() -> void:
		if role == "host":
			_connect_tries += 1
			_net.host_room(url)


	func _on_connect_failed(reason: String) -> void:
		if _connect_tries < MAX_CONNECT_TRIES:
			_joined = false
			_retry_accum = RETRY_DELAY
			return
		_fail("connect failed: " + reason)


	func _on_room_created(code: String) -> void:
		if role != "host":
			return
		var f := FileAccess.open(codefile, FileAccess.WRITE)
		if f == null:
			_fail("codefile 쓰기 실패: " + codefile)
			return
		f.store_string(code)
		f.close()


	func _on_peer_joined(_peer_id: int) -> void:
		if role == "host":
			_peer_ready = true
			_ping()  # 첫 발은 즉시 (합류 직후 워밍업 샘플)


	func _ping() -> void:
		_seq += 1
		_sent_usec[_seq] = Time.get_ticks_usec()
		var msg := {NetSchema.KEY_KIND: "lat_ping", "n": _seq}
		# pad= 진단용: 작은 프레임이 Nagle+지연ACK로 묶여 200ms가 붙는지 가르는 스위치.
		# 페이로드를 MSS 근처로 키우면 즉시 전송되므로, 패딩 유무로 RTT가 갈리면 원인이 확정된다.
		if pad > 0:
			msg["p"] = "x".repeat(pad)
		_net.send_game(msg)


	func _on_net_msg(_from_id: int, data: Dictionary) -> void:
		var kind := str(data.get(NetSchema.KEY_KIND, ""))
		if role == "guest" and kind == "lat_ping":
			var reply := {NetSchema.KEY_KIND: "lat_pong", "n": int(data.get("n", 0))}
			if pad > 0:
				reply["p"] = "x".repeat(pad)
			_net.send_game(reply)
			return
		if role != "host" or kind != "lat_pong":
			return
		var n := int(data.get("n", 0))
		if not _sent_usec.has(n):
			return
		var rtt_ms := float(Time.get_ticks_usec() - int(_sent_usec[n])) / 1000.0
		_sent_usec.erase(n)
		_samples.append(rtt_ms)
		if _samples.size() >= count:
			_report()


	func _report() -> void:
		var s := _samples.duplicate()
		s.sort()
		# 첫 샘플은 합류 직후 워밍업(TCP/TLS·DO 콜드스타트)이라 통계에서 뺀다 — 정상 플레이 중 지연이 궁금한 것
		var body := s.slice(0, s.size())
		var sum := 0.0
		for v: float in body:
			sum += v
		var n := body.size()
		var p50: float = body[int(n * 0.5)]  # slice()가 Array[float] 타입을 잃으므로 명시 필요
		print("[lat] samples=%d url=%s" % [n, url])
		print("LATENCY_OK rtt_ms min=%.1f p50=%.1f p95=%.1f max=%.1f mean=%.1f" % [
			body[0], p50, body[mini(int(n * 0.95), n - 1)], body[n - 1], sum / float(n)])
		_report_dodge_budget(p50)
		_quit_accum = 0.0


	# 측정한 RTT를 "게스트가 실제로 쓸 수 있는 회피 창"으로 환산한다 — 지연이 게임에 미치는 크기.
	# 지연 보상(CombatMath §3) 이전 게스트의 손실:
	#   ⑴ 예고가 게스트 화면에 뜨기까지 = 편도(RTT/2)
	#   ⑵ 호스트가 판정에 쓰는 게스트 좌표의 나이 = 편도 + 위치 송신 주기의 절반
	# 보상 후에는 ⑴을 STRIKE 지연이, ⑵를 속도 외삽이 상쇄해 표시 창 전체를 쓸 수 있다(설계값).
	func _report_dodge_budget(rtt_ms: float) -> void:
		var one_way := rtt_ms * 0.5
		var send_half := 1000.0 / (2.0 * POS_SEND_RATE_HZ)
		var loss_ms := one_way * 2.0 + send_half
		print("[budget] 편도=%.0fms · 위치주기 절반=%.0fms(%.0fHz) → 보상 전 게스트 손실=%.0fms" % [
			one_way, send_half, POS_SEND_RATE_HZ, loss_ms])
		for row: Array in TELEGRAPHS:
			var name_s := str(row[0])
			var win := float(row[1])
			var before := maxf(win - loss_ms / 1000.0, 0.0)
			print("[budget]   %s 예고 %.2fs → 보상 전 게스트 실효 %.2fs (%.0f%% 손실) · 보상 후 %.2fs (설계)" % [
				name_s, win, before, (1.0 - before / win) * 100.0, win])


	# player.gd POS_SEND_RATE 미러 — 이 값을 바꾸면 여기도 고친다(계측 리포트가 실제와 갈라지지 않게)
	const POS_SEND_RATE_HZ := 30.0
	# data/enemies/*.tres의 telegraph_s 미러 — 회피 창 환산용 참조값
	const TELEGRAPHS: Array = [["고블린/잔몹", 0.6], ["브루트", 0.9], ["보스 패턴", 1.0]]


	func _fail(msg: String) -> void:
		printerr("LATENCY_FAIL role=%s — %s" % [role, msg])
		get_tree().quit(1)
