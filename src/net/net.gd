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

# --- P2P 직결 (WebRTC, 2026-07-26) — 게임 메시지 경로에서 릴레이를 걷어낸다 ---
# 릴레이 왕복은 실측 207ms인데(무료 Cloudflare가 서울 엣지를 안 태우고 홍콩 경유 — rules §5),
# 그 경로를 한 홉도 안 거치는 피어 간 직결로 바꾸면 같은 국가 기준 10~40ms가 된다.
# 🔴 **릴레이가 통째로 사라지지는 않는다** — 방 코드·피어 관리·SDP/ICE 교환(시그널링)은 그대로 릴레이를
#   타고, 연결이 열린 뒤의 **게임 페이로드만** 직결로 흐른다. 협상은 연결당 몇 통이라 지연과 무관하다.
# 🔴 **릴레이는 폴백으로도 남는다** — 대칭형 NAT 등으로 P2P가 안 뚫리면(통상 10~20%) 채널이 안 열리고
#   send_game이 자동으로 릴레이로 떨어진다. 폴백을 지우면 그 환경에서 게임이 아예 성립하지 않는다.
# ⚠ **웹 전용이다.** WebRTC는 브라우저 내장이라 웹 익스포트에서만 쓸 수 있고, 네이티브(에디터 실행·
#   헤드리스 테스트)는 GDExtension이 없어 기존 릴레이 경로 그대로다 — 그래서 `tests/test_net_room_auto`는
#   무영향이다(회귀 0). P2P 실기 검증은 웹 2클라 몫.
const RTC_CONFIG := {
	"iceServers": [{"urls": ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"]}]
}
# negotiated 채널 = 양쪽이 같은 id로 각자 만들고 협상 없이 짝지어진다(2인 고정 구조에 맞다 —
# data_channel_received 비동기 수신을 안 다뤄도 되어 상태기계가 짧아진다).
const RTC_CH_FAST := 1  # unordered + 수명 제한 = UDP에 가깝다. 늦은 패킷은 아예 안 온다(최신값만 의미 있는 스트림)
const RTC_CH_SAFE := 2  # ordered + reliable = 유실되면 상태가 갈리는 확정 메시지용
const RTC_FAST_LIFETIME_MS := 60  # 이보다 늙은 fast 패킷은 폐기 — 재전송 대기가 곧 지연이라 버리는 게 낫다
# 🔴 fast(유실 허용) 채널로 보낼 kind — **"다음 패킷이 곧 덮어쓰는 것"만** 넣는다(§3 하드 계약).
#   pos/mpos는 최신 좌표가 곧 진실이라 한 통 유실이 다음 통으로 자동 복구된다.
#   ⚠ shoot·arrowhit·drop·ehp·php 같은 **사건**은 절대 넣지 마라 — 한 통이 유실되면 화살이 안 생기거나
#     영영 안 사라지고, HP가 영구히 갈라진다(에러 없이 화면만 어긋난다).
#   ⚠ **G_PING/G_PONG은 의도적으로 뺐다**(리뷰 I4). RTT는 예고 도착 지연을 대신 재는 값인데, 예고
#     (G_MOB_ATK·G_BOSS_ATK)는 safe 채널이다. 측정을 fast로 하면 손실 구간에서 **유실된 왕복이 아예
#     샘플로 안 잡혀** RTT가 낙관적으로 보고되고, 그만큼 strike_delay_s가 과소 보상해 그 회차 회피 창이
#     짧아진다("가끔 예고가 늦다"로만 보인다). 측정 채널 = 예고 채널로 맞춰야 §3 지연 보상의 입력이
#     실제 전송 특성을 반영한다. 2Hz라 reliable 비용은 무시 가능하다 — 다시 fast로 내리지 마라.
const RTC_FAST_KINDS := {
	NetSchema.G_POS: true, NetSchema.G_MOB_POS: true,
}
const RTC_NEGOTIATE_TIMEOUT_S := 8.0  # 이 안에 안 열리면 경고 1회(엔트리는 유지 — 늦게 열리면 그때부터 쓴다)
# 🔴 직결이 열려 있어도 릴레이 소켓에 이 주기로 신호를 흘린다 (리뷰 C1).
#   릴레이 Worker는 `seen`(그 소켓의 마지막 수신 시각) 기준 **3분 무수신**을 좀비로 끊는데, P2P가 열리면
#   게임 트래픽이 전부 직결로 빠져 그 조건이 상시 성립한다 → 3분마다 방이 끊기고 로비로 튕긴다.
#   ⚠ 서버의 seen 기록 스로틀이 30초라 그보다 넉넉히 잦아야 하고, 스윕 주기(60s)·유휴 한도(180s)와도
#     여유를 둔다. 45초면 유휴 한도의 1/4이라 한두 통이 유실돼도 안전하다.
const RELAY_KEEPALIVE_S := 45.0
# 🔴 직결 무수신 워치독 (리뷰 I1) — 브라우저는 경로가 끊겨도 곧바로 FAILED로 가지 않는다(먼저
#   disconnected, consent 만료까지 ~30초). 그동안 채널은 STATE_OPEN이고 put_packet도 OK를 돌려줘
#   **릴레이 폴백이 안 걸린 채 메시지가 블랙홀로 간다.** ping이 2Hz로 오가므로 그 공백을 워치독으로 잡는다.
const RTC_SILENCE_LIMIT_S := 3.0

var _p2p: Dictionary = {}  # peer_id -> {pc, fast, safe, remote_set: bool, ice_q: Array, age: float, gave_up: bool, quiet: float}
var _keepalive_accum: float = 0.0



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


# 🔴 릴레이 소켓 유지 (리뷰 C1) — 직결이 열리면 게임 트래픽이 전부 그쪽으로 빠져 릴레이로 나가는
#   프레임이 **0**이 되고, 서버는 3분 무수신을 좀비로 간주해 연결을 끊는다(= 방 종료·로비 튕김·챕터 소실).
#   ⚠ 반드시 `_send`(릴레이 직행)로 보낸다 — `send_game`을 쓰면 직결로 나가버려 목적을 정확히 배반한다.
#   ⚠ 직결이 없을 때는 보낼 필요가 없다(게임 트래픽이 이미 릴레이를 지나 seen을 갱신한다).
func _tick_relay_keepalive(delta: float) -> void:
	if state != State.IN_ROOM or not p2p_active():
		_keepalive_accum = 0.0
		return
	_keepalive_accum += delta
	if _keepalive_accum < RELAY_KEEPALIVE_S:
		return
	_keepalive_accum = 0.0
	_send({NetSchema.KEY_TYPE: NetSchema.C_RELAY, "data": {NetSchema.KEY_KIND: NetSchema.G_KEEP}})


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


# 게임 페이로드 송신 — **P2P 직결이 열려 있으면 릴레이를 안 거친다.**
# 호출부(25곳)는 이 함수만 알면 되고 경로 선택은 전부 여기서 끝난다 — 그래서 P2P 도입이
# 게임 코드 무변경으로 떨어졌다(전송 경계가 send_game/net_msg 한 쌍이었던 덕).
func send_game(data: Dictionary) -> void:
	if state != State.IN_ROOM:
		return
	var text := NetSchema.encode(data)
	var fast: bool = RTC_FAST_KINDS.has(str(data.get(NetSchema.KEY_KIND, "")))
	var need_relay := false
	for pid: int in peer_ids:
		if not _p2p_send(pid, text, fast):
			need_relay = true  # 그 피어와는 아직(또는 영영) 직결이 없다 — 릴레이로 간다
	# ⚠ 2인 전제(NetSchema.MAX_ROOM_PEERS=2)라 "일부만 직결"이 곧 "직결 0명"이고, 릴레이 브로드캐스트가
	#   직결 피어에게 **중복 도달하지 않는다**. 4인으로 늘리면 이 전제가 깨진다 — 그때는 릴레이 페이로드에
	#   수신자 지정(to)을 넣어야 한다(rules §2 게이트).
	if need_relay or peer_ids.is_empty():
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
	_p2p_poll(delta)  # 직결 채널은 시그널링 소켓 상태와 무관하게 돈다
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
			_tick_relay_keepalive(delta)
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
	_p2p_drop_all()


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
			for pid: int in peer_ids:
				_p2p_begin(pid)  # 직결 협상 — 누가 offer를 낼지는 id 크기로 결정론적으로 갈린다
			_bus().room_joined.emit(room_code, peer_ids)
		NetSchema.S_JOIN_FAIL:
			# 연결 유지(state=CONNECTED 그대로) — 로비에서 코드 고쳐 바로 재시도 가능
			_bus().room_join_failed.emit(str(msg.get("reason", "")))
		NetSchema.S_PEER_JOINED:
			var pid := int(msg.get("id", 0))
			if pid != 0 and not peer_ids.has(pid):
				peer_ids.append(pid)
			_p2p_begin(pid)
			_bus().peer_joined.emit(pid)
		NetSchema.S_PEER_LEFT:
			var pid := int(msg.get("id", 0))
			peer_ids.erase(pid)
			_rtt_ms.erase(pid)  # 같은 id로 새 피어가 와도 옛 지연 추정이 남지 않게
			_p2p_drop(pid)      # 직결도 같이 정리 — 같은 id로 새 피어가 와도 죽은 채널을 물려받지 않게
			_bus().peer_left.emit(pid)
		NetSchema.S_ROOM_CLOSED:
			state = State.CONNECTED
			my_id = 0
			room_code = ""
			peer_ids = []
			_rtt_ms = {}
			_p2p_drop_all()
			_bus().room_closed.emit()
		NetSchema.S_MSG:
			var data_v: Variant = msg.get("data")
			if data_v is Dictionary:
				var from_id := int(msg.get("from", 0))
				var data := data_v as Dictionary
				if _consume_latency_msg(from_id, data):
					return  # ping/pong은 Net이 끝낸다 — 게임 로직으로 올리지 않는다
				if _consume_signal_msg(from_id, data):
					return  # SDP/ICE도 Net이 끝낸다 — 게임 로직으로 올리지 않는다
				_bus().net_msg.emit(from_id, data)


# =============================================================================
# P2P 직결 (WebRTC) — 게임 페이로드가 릴레이를 안 거치게 하는 계층.
# 이 블록 밖에서 P2P를 아는 코드는 없다: 송신은 send_game이 알아서 경로를 고르고,
# 수신은 릴레이든 직결이든 똑같이 EventBus.net_msg로 올라간다(호출부 무변경의 근거).
# =============================================================================

# 이 환경에서 직결을 시도할 수 있나. 웹 = 브라우저 내장 WebRTC, 그 외 = GDExtension이 없어 불가.
# ⚠ 네이티브에서 굳이 시도하면 에러 로그가 헤드리스 테스트 판정(SCRIPT ERROR grep, verify §3)을
#   오염시킬 수 있다 — 애초에 안 건드리는 쪽이 회귀 0이다.
func _p2p_available() -> bool:
	return OS.has_feature("web") and ClassDB.can_instantiate("WebRTCPeerConnection")


# 하나라도 직결이 살아 있나 — HUD 경로 표시용(핑이 릴레이분인지 직결분인지 눈으로 갈린다).
func p2p_active() -> bool:
	for pid: int in _p2p:
		if _p2p_ready(int(pid)):
			return true
	return false


# 🔴 **두 채널이 다 열렸을 때만** 직결로 본다 (리뷰 Minor). 하나만 열리면 pos는 릴레이·사건은 직결로
#   갈라져 경로 간 순서 뒤바뀜이 상시화되고, HUD "직결" 표시도 거짓이 된다.
func _p2p_ready(peer_id: int) -> bool:
	var e_v: Variant = _p2p.get(peer_id)
	if e_v == null:
		return false
	var e := e_v as Dictionary
	for key: String in ["fast", "safe"]:
		var ch := e.get(key) as WebRTCDataChannel
		if ch == null or ch.get_ready_state() != WebRTCDataChannel.STATE_OPEN:
			return false
	return true


# 협상 시작. **offer를 내는 쪽은 id가 작은 피어**로 고정한다 — 양쪽이 동시에 offer를 내면
# glare(교착)로 협상이 깨지므로, 결정론적으로 한쪽만 내게 한다(호스트 id=1이 항상 작다).
func _p2p_begin(peer_id: int) -> void:
	if peer_id == 0 or peer_id == my_id or _p2p.has(peer_id) or not _p2p_available():
		return
	# 🔴 방 밖에서는 절대 만들지 않는다 (리뷰 I5). 방이 닫힌 직후 도착한 **낙오 SDP**가 여기로 들어오면
	#   상대 없는 PeerConnection이 생기는데, answer가 영영 안 와서 FAILED로도 안 가 `_p2p_poll`이
	#   못 지운다. 그 좀비 엔트리는 다음 방에서 `_p2p.has()` 가드에 걸려 **새 협상을 영구히 막고**,
	#   증상은 "그 뒤로는 늘 릴레이"뿐이라 화면에 이유가 안 드러난다.
	if state != State.IN_ROOM or not peer_ids.has(peer_id):
		return
	var pc := WebRTCPeerConnection.new()
	if pc == null or pc.initialize(RTC_CONFIG) != OK:
		return  # 직결 불가 환경 — 릴레이 유지(무해한 폴백)
	# negotiated 채널: 양쪽이 같은 id로 각자 만들고 협상 없이 짝지어진다.
	var fast := pc.create_data_channel("fast", {
		"negotiated": true, "id": RTC_CH_FAST,
		"ordered": false, "maxPacketLifeTime": RTC_FAST_LIFETIME_MS})
	var safe := pc.create_data_channel("safe", {
		"negotiated": true, "id": RTC_CH_SAFE, "ordered": true})
	if fast == null or safe == null:
		return
	pc.session_description_created.connect(_on_rtc_session.bind(peer_id))
	pc.ice_candidate_created.connect(_on_rtc_ice.bind(peer_id))
	_p2p[peer_id] = {"pc": pc, "fast": fast, "safe": safe,
		"remote_set": false, "ice_q": [], "age": 0.0, "gave_up": false, "quiet": 0.0}
	if my_id < peer_id:
		pc.create_offer()


# 로컬 SDP 생성 완료 → 로컬에 반영하고 상대에게 시그널링으로 보낸다.
# ⚠ 여기서 send_game을 쓰면 안 된다 — send_game이 직결을 타려 하는데 그 직결을 지금 만드는 중이다(순환).
#   시그널링은 **항상 릴레이(_send)** 로만 나간다.
func _on_rtc_session(type: String, sdp: String, peer_id: int) -> void:
	var e_v: Variant = _p2p.get(peer_id)
	if e_v == null:
		return
	var pc := (e_v as Dictionary).get("pc") as WebRTCPeerConnection
	if pc == null:
		return
	pc.set_local_description(type, sdp)
	_send({NetSchema.KEY_TYPE: NetSchema.C_RELAY,
		"data": {NetSchema.KEY_KIND: NetSchema.G_RTC_SDP, "ty": type, "sdp": sdp}})


func _on_rtc_ice(media: String, index: int, name: String, peer_id: int) -> void:
	if not _p2p.has(peer_id):
		return
	_send({NetSchema.KEY_TYPE: NetSchema.C_RELAY,
		"data": {NetSchema.KEY_KIND: NetSchema.G_RTC_ICE, "m": media, "i": index, "n": name}})


# 시그널링 수신 — 처리했으면 true(= net_msg로 올리지 않는다). ping/pong과 같은 규약.
func _consume_signal_msg(from_id: int, data: Dictionary) -> bool:
	match str(data.get(NetSchema.KEY_KIND, "")):
		NetSchema.G_RTC_SDP:
			_rtc_on_sdp(from_id, str(data.get("ty", "")), str(data.get("sdp", "")))
			return true
		NetSchema.G_RTC_ICE:
			_rtc_on_ice(from_id, str(data.get("m", "")), int(data.get("i", 0)), str(data.get("n", "")))
			return true
		NetSchema.G_KEEP:
			return true  # 릴레이 소켓 유지용 — 도착 자체가 목적이다(서버 seen 갱신). 게임 로직엔 안 올린다
	return false


func _rtc_on_sdp(peer_id: int, type: String, sdp: String) -> void:
	if type != "offer" and type != "answer":
		return  # 알 수 없는 타입 폐기 — 신뢰 경계(릴레이를 타고 오는 값이다)
	if not _p2p.has(peer_id):
		_p2p_begin(peer_id)  # offer가 방 상태 갱신보다 먼저 도착한 경우
	var e_v: Variant = _p2p.get(peer_id)
	if e_v == null:
		return
	var e := e_v as Dictionary
	var pc := e.get("pc") as WebRTCPeerConnection
	if pc == null or pc.set_remote_description(type, sdp) != OK:
		return
	e["remote_set"] = true
	# remote description 전에 도착해 쌓아둔 ICE 후보를 이제 흘려보낸다.
	# 🔴 큐가 없으면 먼저 온 후보가 조용히 버려져 연결이 **가끔** 안 뚫린다(트리클 ICE는 SDP보다 빨리 온다).
	for c: Variant in (e.get("ice_q", []) as Array):
		var arr := c as Array
		pc.add_ice_candidate(str(arr[0]), int(arr[1]), str(arr[2]))
	e["ice_q"] = []


func _rtc_on_ice(peer_id: int, media: String, index: int, name: String) -> void:
	var e_v: Variant = _p2p.get(peer_id)
	if e_v == null:
		return
	var e := e_v as Dictionary
	if bool(e.get("remote_set", false)):
		var pc := e.get("pc") as WebRTCPeerConnection
		if pc != null:
			pc.add_ice_candidate(media, index, name)
	else:
		(e.get("ice_q", []) as Array).append([media, index, name])


# 직결 송신 — 보냈으면 true, 채널이 없거나 안 열렸으면 false(호출부가 릴레이로 떨어뜨린다).
func _p2p_send(peer_id: int, text: String, fast: bool) -> bool:
	# 두 채널이 다 열리기 전에는 통째로 릴레이를 쓴다 — 한 채널만 태우면 같은 피어에게 가는 메시지가
	# 두 경로로 갈라져 순서가 뒤섞인다(사건이 그것이 서술하는 위치보다 먼저 도착하는 식).
	if not _p2p_ready(peer_id):
		return false
	var e_v: Variant = _p2p.get(peer_id)
	if e_v == null:
		return false
	var e := e_v as Dictionary
	var ch := (e.get("fast") if fast else e.get("safe")) as WebRTCDataChannel
	if ch == null or ch.get_ready_state() != WebRTCDataChannel.STATE_OPEN:
		return false
	return ch.put_packet(text.to_utf8_buffer()) == OK


func _p2p_poll(delta: float) -> void:
	if _p2p.is_empty():
		return
	var dead: Array[int] = []
	# ⚠ 아래 net_msg emit이 동기라 구독자가 방을 떠나게 만들면 순회 중 _p2p가 바뀔 수 있다 → 키 스냅샷.
	for pid_v: Variant in _p2p.keys():
		var pid := int(pid_v)
		if not _p2p.has(pid):
			continue  # 이 순회 안에서 정리된 피어
		var e := _p2p[pid] as Dictionary
		var pc := e.get("pc") as WebRTCPeerConnection
		if pc == null:
			dead.append(pid)
			continue
		pc.poll()
		var conn := pc.get_connection_state()
		# 🔴 DISCONNECTED도 죽은 것으로 본다 (리뷰 I1) — FAILED만 기다리면 consent 만료까지 ~30초 동안
		#   채널이 STATE_OPEN인 채 메시지가 사라진다(릴레이 폴백이 안 걸린다).
		if conn == WebRTCPeerConnection.STATE_FAILED or conn == WebRTCPeerConnection.STATE_CLOSED \
				or conn == WebRTCPeerConnection.STATE_DISCONNECTED:
			dead.append(pid)  # 정리하면 send_game이 자동으로 릴레이로 돌아간다
			continue
		var got := false
		for key: String in ["fast", "safe"]:
			var ch := e.get(key) as WebRTCDataChannel
			if ch == null:
				continue
			ch.poll()
			while ch.get_available_packet_count() > 0:
				got = true
				var d := NetSchema.decode(ch.get_packet().get_string_from_utf8())
				if d.is_empty():
					continue
				# 🔴 릴레이 경로와 **똑같은 순서**로 흘린다(Net 소비분 → net_msg). 여기서 갈라지면
				#   경로에 따라 게임 동작이 달라진다. from_id는 채널의 주인이라 위조 여지가 릴레이보다 좁다.
				if _consume_latency_msg(pid, d):
					continue
				if _consume_signal_msg(pid, d):
					continue  # 현재는 시그널링이 릴레이로만 오지만, 재협상을 붙이면 이 경로가 살아난다
				_bus().net_msg.emit(pid, d)
		# 무수신 워치독 — ping이 2Hz로 오가므로 몇 초 침묵은 곧 경로 단절이다 (리뷰 I1).
		if _p2p_ready(pid):
			e["quiet"] = 0.0 if got else float(e.get("quiet", 0.0)) + delta
			if float(e["quiet"]) > RTC_SILENCE_LIMIT_S:
				push_warning("Net: P2P 직결 무응답 %.1fs (peer %d) — 릴레이로 되돌린다" % [float(e["quiet"]), pid])
				dead.append(pid)
				continue
		# 협상 타임아웃 — 경고 1회만 찍고 엔트리는 남긴다. 늦게 열리면 그때부터 직결을 쓰는 편이 낫다.
		elif not bool(e.get("gave_up", false)):
			e["age"] = float(e.get("age", 0.0)) + delta
			if float(e["age"]) > RTC_NEGOTIATE_TIMEOUT_S:
				e["gave_up"] = true
				push_warning("Net: P2P 직결 실패 (peer %d) — 릴레이 폴백으로 계속" % pid)
	for pid: int in dead:
		_p2p_drop(pid)


func _p2p_drop(peer_id: int) -> void:
	var e_v: Variant = _p2p.get(peer_id)
	if e_v == null:
		return
	var e := e_v as Dictionary
	var pc := e.get("pc") as WebRTCPeerConnection
	if pc != null:
		pc.close()
	_p2p.erase(peer_id)
	# 🔴 전송 경로가 통째로 바뀌므로 지연 추정도 버린다 (리뷰 I2, S_PEER_LEFT의 erase와 같은 이유).
	#   직결 20ms로 수렴한 EMA를 들고 릴레이(~200ms)로 돌아가면, 200에 근접하기까지 ~2.5초 동안
	#   strike_delay_s가 거의 0이 되고 net_anchor_lead가 net_anchor와 같아져 "둘 다 맞아야" 규약이
	#   한쪽 판정으로 퇴화한다 — 2026-07-24에 고친 "게스트만 피했는데 맞았다"가 그 창에서 재발한다.
	_rtt_ms.erase(peer_id)


func _p2p_drop_all() -> void:
	for pid_v: Variant in _p2p.keys():
		_p2p_drop(int(pid_v))
	_p2p = {}
