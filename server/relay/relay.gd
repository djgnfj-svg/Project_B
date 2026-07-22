extends Node
# WebSocket 중계 서버 본체 — 방 코드 스코프의 메시지 릴레이만 한다. 게임 로직 없음 (projectb-rules §1).
# 실행 진입은 relay_server.gd. 메시지 스키마는 core net_schema.gd 단일 소스 (rules §3).

const NetSchema := preload("res://src/core/net_schema.gd")

var _tcp := TCPServer.new()
var _pending: Array[WebSocketPeer] = []  # 핸드셰이크 진행 중
var _clients: Dictionary = {}            # WebSocketPeer -> {room: String(""=미소속), id: int}
var _rooms: Dictionary = {}              # code -> {peers: Dictionary[int -> WebSocketPeer], next_id: int}
var _rng := RandomNumberGenerator.new()


func listen(port: int) -> Error:
	_rng.randomize()
	var err := _tcp.listen(port)
	if err == OK:
		print("[relay] listening on port %d" % port)
	else:
		push_error("[relay] listen failed on port %d — error %d" % [port, err])
	return err


func _process(_delta: float) -> void:
	while _tcp.is_connection_available():
		var ws := WebSocketPeer.new()
		if ws.accept_stream(_tcp.take_connection()) == OK:
			_pending.append(ws)

	for i in range(_pending.size() - 1, -1, -1):
		var ws: WebSocketPeer = _pending[i]
		ws.poll()
		match ws.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				_clients[ws] = {"room": "", "id": 0}
				_pending.remove_at(i)
			WebSocketPeer.STATE_CLOSED:
				_pending.remove_at(i)

	for ws_v: Variant in _clients.keys():
		var ws := ws_v as WebSocketPeer
		ws.poll()
		if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			_drop_client(ws)
			continue
		while ws.get_available_packet_count() > 0:
			var pkt := ws.get_packet()
			if not ws.was_string_packet():
				continue
			_handle(ws, NetSchema.decode(pkt.get_string_from_utf8()))


func _handle(ws: WebSocketPeer, msg: Dictionary) -> void:
	if msg.is_empty():
		return
	var info: Dictionary = _clients[ws]
	match str(msg.get(NetSchema.KEY_TYPE, "")):
		NetSchema.C_CREATE:
			if str(info["room"]) != "":
				return  # 이미 방 소속 — 무시
			var code := _new_code()
			_rooms[code] = {"peers": {NetSchema.HOST_ID: ws}, "next_id": NetSchema.HOST_ID + 1}
			info["room"] = code
			info["id"] = NetSchema.HOST_ID
			_send(ws, {NetSchema.KEY_TYPE: NetSchema.S_CREATED, "room": code, "id": NetSchema.HOST_ID})
			print("[relay] room %s created" % code)

		NetSchema.C_JOIN:
			if str(info["room"]) != "":
				return
			var code := str(msg.get("room", "")).strip_edges().to_upper()
			if not _rooms.has(code):
				_send(ws, {NetSchema.KEY_TYPE: NetSchema.S_JOIN_FAIL, "reason": NetSchema.FAIL_NO_ROOM})
				return
			var room: Dictionary = _rooms[code]
			var peers: Dictionary = room["peers"]
			if peers.size() >= NetSchema.MAX_ROOM_PEERS:
				_send(ws, {NetSchema.KEY_TYPE: NetSchema.S_JOIN_FAIL, "reason": NetSchema.FAIL_FULL})
				return
			var pid := int(room["next_id"])
			room["next_id"] = pid + 1
			var existing: Array = peers.keys()
			peers[pid] = ws
			info["room"] = code
			info["id"] = pid
			_send(ws, {NetSchema.KEY_TYPE: NetSchema.S_JOINED, "room": code, "id": pid, "peers": existing})
			for other_id: Variant in existing:
				_send(peers[other_id], {NetSchema.KEY_TYPE: NetSchema.S_PEER_JOINED, "id": pid})
			print("[relay] peer %d joined room %s" % [pid, code])

		NetSchema.C_RELAY:
			var code := str(info["room"])
			if code == "" or not _rooms.has(code):
				return  # 방 미소속 릴레이는 버린다 (신뢰 경계)
			var data_v: Variant = msg.get("data")
			if not (data_v is Dictionary):
				return
			var peers: Dictionary = _rooms[code]["peers"]
			var out := {NetSchema.KEY_TYPE: NetSchema.S_MSG, "from": int(info["id"]), "data": data_v}
			var kind := str((data_v as Dictionary).get(NetSchema.KEY_KIND, ""))
			if kind != NetSchema.G_POS and kind != NetSchema.G_MOB_POS:
				# pos(15Hz)·mpos(10Hz)는 고빈도라 제외 — 저빈도 게임 이벤트만 기록 (운영 진단용)
				print("[relay] %s: %d -> room %s: %s" % [kind, int(info["id"]), code, NetSchema.encode(data_v)])
			for pid: Variant in peers:
				if int(pid) != int(info["id"]):
					_send(peers[pid], out)


func _drop_client(ws: WebSocketPeer) -> void:
	var info: Dictionary = _clients[ws]
	_clients.erase(ws)
	var code := str(info["room"])
	if code == "" or not _rooms.has(code):
		return
	var room: Dictionary = _rooms[code]
	var peers: Dictionary = room["peers"]
	var left_id := int(info["id"])
	peers.erase(left_id)
	if left_id == NetSchema.HOST_ID:
		# 호스트 권한 모델(rules §1): 호스트 이탈 = 방 종료.
		# (게스트만 이탈 시 방 유지 — GDD §11 재접속 처리 확정 대기)
		for pid: Variant in peers:
			var other := peers[pid] as WebSocketPeer
			_send(other, {NetSchema.KEY_TYPE: NetSchema.S_ROOM_CLOSED})
			if _clients.has(other):
				_clients[other]["room"] = ""
				_clients[other]["id"] = 0
		_rooms.erase(code)
		print("[relay] room %s closed (host left)" % code)
	else:
		if peers.is_empty():
			_rooms.erase(code)
			print("[relay] room %s emptied" % code)
		else:
			for pid: Variant in peers:
				_send(peers[pid], {NetSchema.KEY_TYPE: NetSchema.S_PEER_LEFT, "id": left_id})
			print("[relay] peer %d left room %s" % [left_id, code])


func _send(ws: WebSocketPeer, msg: Dictionary) -> void:
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(NetSchema.encode(msg))


func _new_code() -> String:
	while true:
		var code := ""
		for _i in NetSchema.ROOM_CODE_LEN:
			code += NetSchema.ROOM_CODE_CHARS[_rng.randi_range(0, NetSchema.ROOM_CODE_CHARS.length() - 1)]
		if not _rooms.has(code):
			return code
	return ""  # 도달 불가
