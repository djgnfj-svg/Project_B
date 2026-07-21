extends Node
# Net 오토로드 — WebSocket 중계 연결·방·릴레이 송수신의 단일 소스 (projectb-rules §1).
# 결과는 전부 EventBus 시그널로 알린다. 다른 모듈은 상태 조회(my_id·peer_ids 등)와
# host_room/join_room/send_game/leave만 부른다.

const NetSchema := preload("res://src/core/net_schema.gd")

const DEFAULT_RELAY_URL := "ws://localhost:9080"

enum State { DISCONNECTED, CONNECTING, CONNECTED, IN_ROOM }

var state: State = State.DISCONNECTED
var my_id: int = 0
var room_code: String = ""
var peer_ids: Array[int] = []  # 나를 제외한 방 피어

var _ws: WebSocketPeer = null
var _pending_msg: Dictionary = {}  # 연결 완료 직후 보낼 create/join
var _bus_cache: EventBusHub = null


# -s 헤드리스 테스트에선 오토로드 전역 식별자를 쓸 수 없다 — /root 경로 + 타입으로 조회 (rules §5)
func _bus() -> EventBusHub:
	if _bus_cache == null:
		_bus_cache = get_tree().root.get_node("EventBus") as EventBusHub
		if _bus_cache == null:
			push_error("Net: /root/EventBus 없음 — 시그널 전달 불가")
	return _bus_cache



func is_host() -> bool:
	return my_id == NetSchema.HOST_ID


func is_in_room() -> bool:
	return state == State.IN_ROOM


func host_room(url: String) -> void:
	_start(url, {NetSchema.KEY_TYPE: NetSchema.C_CREATE})


func join_room(url: String, code: String) -> void:
	_start(url, {NetSchema.KEY_TYPE: NetSchema.C_JOIN, "room": code.strip_edges().to_upper()})


func send_game(data: Dictionary) -> void:
	if state != State.IN_ROOM:
		return
	_send({NetSchema.KEY_TYPE: NetSchema.C_RELAY, "data": data})


func leave() -> void:
	if _ws != null:
		_ws.close()


func _start(url: String, first_msg: Dictionary) -> void:
	match state:
		State.CONNECTED:
			# 방 종료·참가 실패 후 — 기존 연결 재사용, 바로 요청 (url 변경은 재사용 시 무시됨)
			_send(first_msg)
		State.DISCONNECTED:
			_ws = WebSocketPeer.new()
			var err := _ws.connect_to_url(url)
			if err != OK:
				_ws = null
				_bus().net_connect_failed.emit("connect error %d" % err)
				return
			_pending_msg = first_msg
			state = State.CONNECTING
		_:
			push_warning("Net: busy (state=%d) — ignored" % state)


func _send(msg: Dictionary) -> void:
	if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(NetSchema.encode(msg))


func _process(_delta: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if state == State.CONNECTING:
				state = State.CONNECTED
				_bus().net_connected.emit()
				if not _pending_msg.is_empty():
					_send(_pending_msg)
					_pending_msg = {}
			while _ws.get_available_packet_count() > 0:
				var pkt := _ws.get_packet()
				if _ws.was_string_packet():
					_handle(NetSchema.decode(pkt.get_string_from_utf8()))
		WebSocketPeer.STATE_CLOSED:
			var was := state
			_reset()
			if was == State.CONNECTING:
				_bus().net_connect_failed.emit("연결 실패")
			else:
				_bus().net_disconnected.emit()


func _reset() -> void:
	_ws = null
	_pending_msg = {}
	state = State.DISCONNECTED
	my_id = 0
	room_code = ""
	peer_ids = []


func _handle(msg: Dictionary) -> void:
	match str(msg.get(NetSchema.KEY_TYPE, "")):
		NetSchema.S_CREATED:
			state = State.IN_ROOM
			my_id = int(msg.get("id", 0))
			room_code = str(msg.get("room", ""))
			peer_ids = []
			_bus().room_created.emit(room_code)
		NetSchema.S_JOINED:
			state = State.IN_ROOM
			my_id = int(msg.get("id", 0))
			room_code = str(msg.get("room", ""))
			peer_ids = []
			var peers_v: Variant = msg.get("peers", [])
			if peers_v is Array:
				for v: Variant in peers_v:
					peer_ids.append(int(v))
			_bus().room_joined.emit(room_code, peer_ids)
		NetSchema.S_JOIN_FAIL:
			# 연결 유지(state=CONNECTED 그대로) — 로비에서 코드 고쳐 바로 재시도 가능
			_bus().room_join_failed.emit(str(msg.get("reason", "")))
		NetSchema.S_PEER_JOINED:
			var pid := int(msg.get("id", 0))
			if pid != 0 and not peer_ids.has(pid):
				peer_ids.append(pid)
			_bus().peer_joined.emit(pid)
		NetSchema.S_PEER_LEFT:
			var pid := int(msg.get("id", 0))
			peer_ids.erase(pid)
			_bus().peer_left.emit(pid)
		NetSchema.S_ROOM_CLOSED:
			state = State.CONNECTED
			my_id = 0
			room_code = ""
			peer_ids = []
			_bus().room_closed.emit()
		NetSchema.S_MSG:
			var data_v: Variant = msg.get("data")
			if data_v is Dictionary:
				_bus().net_msg.emit(int(msg.get("from", 0)), data_v as Dictionary)
