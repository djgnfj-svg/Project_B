extends Node
# Net 오토로드 — WebSocket 중계 연결·방·릴레이 송수신의 단일 소스 (projectb-rules §1).
# 결과는 전부 EventBus 시그널로 알린다. 다른 모듈은 상태 조회(my_id·peer_ids 등)와
# host_room/join_room/send_game/leave만 부른다.

const NetSchema := preload("res://src/core/net_schema.gd")

# 공용 릴레이 — 클론 실행·workers.dev 임시배포에서도 "방 만들기"가 바로 되는 기본값.
const DEFAULT_RELAY_URL := "wss://relay.jachana.com"
const LOCAL_RELAY_PORT := 9080
const LOCAL_RELAY_URL := "ws://localhost:%d" % LOCAL_RELAY_PORT

enum State { DISCONNECTED, CONNECTING, CONNECTED, IN_ROOM }

var state: State = State.DISCONNECTED
var my_id: int = 0
var room_code: String = ""
var peer_ids: Array[int] = []  # 나를 제외한 방 피어
var relay_url: String = ""  # 마지막으로 접속(시도)한 릴레이 주소 — invite_url()의 재료

var _ws: WebSocketPeer = null
var _pending_msg: Dictionary = {}  # 연결 완료 직후 보낼 create/join
var _bus_cache: EventBusHub = null

# --- 왕복 지연 계측 (2026-07-24) — 지연 보상(CombatMath §3)의 입력 + HUD 핑 표시 ---
# 주기적으로 G_PING을 방에 뿌리고 상대의 G_PONG으로 RTT를 잰다. 시계 동기화는 필요 없다 —
# 자기가 찍은 타임스탬프를 그대로 돌려받아 자기 시계로만 차를 재기 때문.
# ⚠ 이 두 메시지는 net_msg로 올려보내지 않는다(게임 로직 오염 방지) — 여기서 소비하고 끝낸다.
const PING_INTERVAL_S := 0.5
const RTT_EMA_ALPHA := 0.3   # 새 샘플 가중 — 낮을수록 안정, 높을수록 지연 변화에 민감
const RTT_MAX_MS := 2000.0   # 비정상 샘플(탭 프리즈 후 큐 폭포 등)이 EMA를 오염시키지 않게 버리는 상한

var _rtt_ms: Dictionary = {}  # peer_id -> 평활화된 RTT(ms). 아직 왕복이 없으면 키 없음
var _ping_accum: float = 0.0


# -s 헤드리스 테스트에선 오토로드 전역 식별자를 쓸 수 없다 — /root 경로 + 타입으로 조회 (rules §5)
func _bus() -> EventBusHub:
	if _bus_cache == null:
		_bus_cache = get_tree().root.get_node("EventBus") as EventBusHub
		if _bus_cache == null:
			push_error("Net: /root/EventBus 없음 — 시그널 전달 불가")
	return _bus_cache



func is_host() -> bool:
	return my_id == NetSchema.HOST_ID


# 이 환경의 릴레이 기본값 — 배포 관례: game.<도메인> 페이지면 wss://relay.<도메인> (단일 소스, 로비도 이걸 쓴다).
# 로컬 웹 빌드 테스트(localhost 서빙)만 로컬 릴레이, 그 외(네이티브·workers.dev 포함)는 공용 릴레이.
func default_relay_url() -> String:
	if OS.has_feature("web"):
		var page_host := str(JavaScriptBridge.eval("window.location.hostname", true))
		if page_host.begins_with("game."):
			return "wss://relay." + page_host.trim_prefix("game.")
		# 로컬/LAN 서빙(scripts/dev_local.sh)이면 **페이지를 준 그 PC**의 릴레이를 쓴다.
		# 같은 공유기의 두 대가 공용 릴레이로 가면 한국→홍콩→한국을 왕복해 RTT가 ~200ms 붙는다
		# (실측 2026-07-24) — 로컬 릴레이는 ~15ms다. 링크에 ?relay=를 손으로 붙이지 않아도 되게 자동 판별.
		# ⚠ https 페이지에서 ws://(비보안)는 브라우저가 mixed content로 조용히 막는다 →
		#   그 경우엔 공용 릴레이로 폴백한다. 사설 IP는 인증서가 없어 https로 서빙될 일이 없지만 방어적으로.
		if _is_lan_host(page_host):
			var page_proto := str(JavaScriptBridge.eval("window.location.protocol", true))
			if page_proto != "https:":
				return "ws://%s:%d" % [page_host, LOCAL_RELAY_PORT]
	return DEFAULT_RELAY_URL


# 로컬호스트 또는 사설 대역(RFC1918) — "이 페이지를 준 PC가 곧 릴레이"로 볼 수 있는 주소인가.
func _is_lan_host(host: String) -> bool:
	if host == "localhost" or host == "127.0.0.1":
		return true
	if host.begins_with("192.168.") or host.begins_with("10."):
		return true
	if host.begins_with("172."):
		# 172.16.0.0 ~ 172.31.255.255 만 사설 — 172.32+ 는 공인이라 제외
		var parts := host.split(".")
		if parts.size() >= 2:
			var second := int(parts[1])
			return second >= 16 and second <= 31
	return false


# 초대 링크 — 방에 있을 때 이 URL을 열면 바로 같은 방에 참가한다 (GDD §10 "코드 포함 초대 링크").
# 릴레이가 페이지 기본값과 다를 때만 &relay=를 붙인다. 페이지 주소를 못 정하면 빈 문자열(코드 공유 폴백).
func invite_url() -> String:
	if room_code.is_empty():
		return ""
	var base := ""
	if OS.has_feature("web"):
		base = str(JavaScriptBridge.eval("window.location.origin + window.location.pathname", true))
	elif relay_url.begins_with("wss://relay."):
		base = "https://game." + relay_url.trim_prefix("wss://relay.")  # 네이티브 개발 실행 → 배포 페이지로 유도
	if base.is_empty():
		return ""
	# relay 파라미터는 웹에서만 — 네이티브는 base 자체를 relay_url에서 유도해 수신자 기본값과 항상 일치
	var url := base + "?join=" + room_code
	if OS.has_feature("web") and relay_url != default_relay_url():
		url += "&relay=" + relay_url.uri_encode()
	return url


func is_in_room() -> bool:
	return state == State.IN_ROOM


# 그 피어와의 왕복 지연(ms). 아직 측정 전이면 0 — 호출부는 0을 "보상 없음"(항등)으로 다뤄야 한다.
func rtt_ms(peer_id: int) -> float:
	return float(_rtt_ms.get(peer_id, 0.0))


# 그 피어와의 편도 지연(ms) = RTT의 절반. 지연 보상(CombatMath)의 표준 입력.
func one_way_ms(peer_id: int) -> float:
	return rtt_ms(peer_id) * 0.5


# 원격 피어 중 최대 편도 지연(ms) — 예고 타격 지연 보상(strike_delay_s)의 입력.
# 가장 느린 피어를 기준으로 해야 모두가 온전한 회피 창을 갖는다. 솔로/미측정이면 0(항등).
func max_remote_one_way_ms() -> float:
	var worst := 0.0
	for pid: int in peer_ids:
		worst = maxf(worst, one_way_ms(pid))
	return worst


# 표시용 — 내 화면에 띄울 핑. 호스트는 가장 느린 게스트, 게스트는 호스트와의 RTT.
func display_rtt_ms() -> float:
	if is_host():
		var worst := 0.0
		for pid: int in peer_ids:
			worst = maxf(worst, rtt_ms(pid))
		return worst
	return rtt_ms(NetSchema.HOST_ID)


func _tick_ping(delta: float) -> void:
	if state != State.IN_ROOM or peer_ids.is_empty():
		return
	_ping_accum += delta
	if _ping_accum < PING_INTERVAL_S:
		return
	_ping_accum = 0.0
	send_game({NetSchema.KEY_KIND: NetSchema.G_PING, "t": Time.get_ticks_usec()})


# ping/pong 소비 — 처리했으면 true(= net_msg로 올리지 않는다).
func _consume_latency_msg(from_id: int, data: Dictionary) -> bool:
	match str(data.get(NetSchema.KEY_KIND, "")):
		NetSchema.G_PING:
			# 받은 타임스탬프를 그대로 돌려준다 — 내용을 해석하지 않으므로 위조 이득이 없다
			send_game({NetSchema.KEY_KIND: NetSchema.G_PONG, "t": data.get("t", 0)})
			return true
		NetSchema.G_PONG:
			var sent_usec := int(data.get("t", 0))
			if sent_usec <= 0:
				return true
			var sample := float(Time.get_ticks_usec() - sent_usec) / 1000.0
			if sample < 0.0 or sample > RTT_MAX_MS:
				return true  # 시계 역행·프리즈 후 폭포 — 버린다
			if _rtt_ms.has(from_id):
				_rtt_ms[from_id] = float(_rtt_ms[from_id]) * (1.0 - RTT_EMA_ALPHA) + sample * RTT_EMA_ALPHA
			else:
				_rtt_ms[from_id] = sample
			return true
	return false


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
			# 방 종료·참가 실패 후 — 기존 연결 재사용, 바로 요청 (url 변경은 재사용 시 무시됨 → relay_url도 유지)
			_send(first_msg)
		State.DISCONNECTED:
			relay_url = url
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


func _process(delta: float) -> void:
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
			# 수신을 모두 비운 뒤에 보낸다 — 같은 프레임에 도착한 pong이 먼저 반영돼 RTT가 한 프레임 덜 늙는다
			_tick_ping(delta)
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
	_rtt_ms = {}
	_ping_accum = 0.0


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
			_rtt_ms.erase(pid)  # 같은 id로 새 피어가 와도 옛 지연 추정이 남지 않게
			_bus().peer_left.emit(pid)
		NetSchema.S_ROOM_CLOSED:
			state = State.CONNECTED
			my_id = 0
			room_code = ""
			peer_ids = []
			_rtt_ms = {}
			_bus().room_closed.emit()
		NetSchema.S_MSG:
			var data_v: Variant = msg.get("data")
			if data_v is Dictionary:
				var from_id := int(msg.get("from", 0))
				var data := data_v as Dictionary
				if _consume_latency_msg(from_id, data):
					return  # ping/pong은 Net이 끝낸다 — 게임 로직으로 올리지 않는다
				_bus().net_msg.emit(from_id, data)
