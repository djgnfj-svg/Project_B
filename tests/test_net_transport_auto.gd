extends SceneTree
# 전송 계층 계약 단위 테스트 (P2P 직결 도입, 2026-07-26) — 오토로드·소켓 없이 상수/스키마만 검사한다.
#
# 왜 필요한가: P2P 전환의 위험은 대부분 **실기에서만** 드러나는데(verify §2), 그중 두 가지는
# "상수 한 줄을 잘못 고치면 조용히 깨지는" 성질이라 헤드리스로 못 박아둘 수 있다.
#   ⑴ fast(유실 허용) 채널 분류 — 사건 kind를 여기 넣으면 화살이 안 생기거나 HP가 영구히 갈라진다.
#   ⑵ Net이 소비하는 kind 이름의 유일성 — 겹치면 그 이름을 쓰던 기능이 **에러 없이** 죽는다
#      (rules §5: "nping" 사고를 실제로 겪었다).
# ⚠ 이 파일은 실제 연결을 맺지 않는다 — WebRTC는 웹 전용이라 네이티브 헤드리스에서 돌 수 없다.
#   협상·폴백·지연은 웹 2클라 실기 몫이다(verify §2).

const NetSchema := preload("res://src/core/net_schema.gd")
const NetScript := preload("res://src/net/net.gd")


func _init() -> void:
	var failures := 0

	# --- ⑴ fast 채널 분류 = §3 하드 계약 ---
	# 🔴 "다음 패킷이 곧 덮어쓰는 것"만 유실을 허용한다. 아래 집합이 바뀌면 이 테스트가 빨개져야 한다.
	var fast: Dictionary = NetScript.RTC_FAST_KINDS
	var expected := [NetSchema.G_POS, NetSchema.G_MOB_POS]
	failures += _check(fast.size() == expected.size(), "fast 분류: 정확히 %d종 (현재 %d종)" % [expected.size(), fast.size()])
	for k: String in expected:
		failures += _check(fast.has(k), "fast 분류: %s 포함(최신값만 의미 있는 스트림)" % k)

	# 🔴 사건 kind는 절대 fast에 들어가면 안 된다 — 한 통 유실이 곧 영구 상태 갈라짐이다.
	#   (화살이 안 생긴다/안 사라진다·드랍이 유령으로 남는다·HP가 클라마다 다르다)
	var events := [NetSchema.G_SHOOT, NetSchema.G_ARROW_HIT, NetSchema.G_DROP, NetSchema.G_PICK_REQ,
		NetSchema.G_PICK_OK, NetSchema.G_ENEMY_HP, NetSchema.G_PLAYER_HP, NetSchema.G_EXP,
		NetSchema.G_SCENE, NetSchema.G_STAGE_CLEAR, NetSchema.G_WIPE, NetSchema.G_HIT_REQ,
		NetSchema.G_ROLL, NetSchema.G_ATK, NetSchema.G_JOB, NetSchema.G_STATS, NetSchema.G_SIT,
		NetSchema.G_MOB_ATK, NetSchema.G_BOSS_ATK, NetSchema.G_BOSS_SPRAY, NetSchema.G_BOSS_PHASE,
		NetSchema.G_SWAMP]
	for k: String in events:
		failures += _check(not fast.has(k), "fast 분류: 사건 %s 제외(유실 시 상태 갈라짐)" % k)

	# 🔴 RTT 계측은 예고와 **같은 채널**이어야 한다 (리뷰 I4) — 측정 채널이 유실 허용이면 손실 구간에서
	#   실패한 왕복이 샘플에 안 잡혀 RTT가 낙관적으로 보고되고, strike_delay_s가 그만큼 과소 보상한다.
	failures += _check(not fast.has(NetSchema.G_PING) and not fast.has(NetSchema.G_PONG),
		"fast 분류: ping/pong 제외(측정 채널 = 예고 채널, §3 지연 보상 입력)")

	# --- ⑵ Net이 소비하는 kind의 유일성 (rules §5) ---
	# Net이 가로채는 이름이 게임 kind와 겹치면 그 게임 기능이 조용히 죽는다. 스키마 상수 전체를 훑어
	# 값 중복이 하나도 없음을 단정한다 — 새 kind를 추가할 때 grep을 잊어도 여기서 걸린다.
	# ⚠ 클래스 이름에 직접 부르면 "non-static function" 파스 에러 — Script 리소스 **인스턴스**로 받아 부른다.
	var schema_script: Script = NetSchema
	var consts: Dictionary = schema_script.get_script_constant_map()
	var seen: Dictionary = {}
	var dup := ""
	for name: String in consts:
		if not name.begins_with("G_"):
			continue
		var val := str(consts[name])
		if seen.has(val):
			dup = "%s == %s (\"%s\")" % [name, str(seen[val]), val]
		seen[val] = name
	failures += _check(dup.is_empty(), "kind 유일성: G_* 값 중복 없음%s" % ("" if dup.is_empty() else " — 충돌 " + dup))
	# Net 소비분이 실제로 등록돼 있는지(오타로 상수만 만들고 안 쓰는 것 방지)
	for k: String in [NetSchema.G_PING, NetSchema.G_PONG, NetSchema.G_RTC_SDP, NetSchema.G_RTC_ICE, NetSchema.G_KEEP]:
		failures += _check(not k.is_empty(), "Net 소비 kind 정의됨: %s" % k)

	# --- ⑶ 릴레이 keepalive 주기 < 서버 유휴 한도 (리뷰 C1) ---
	# 🔴 직결이 열리면 릴레이로 나가는 게임 프레임이 0이 되어, 서버의 3분 무수신 스윕이 방을 끊는다.
	#   ⚠ 아래 두 값은 `server/relay-worker/src/index.js`의 **JS 미러**다(rules §2: 스키마를 바꾸면
	#     두 파일을 같이 고친다). 서버에서 값을 낮추면 여기도 낮추고, 이 단정이 그 사실을 알려준다.
	var server_idle_limit_s := 180.0   # index.js IDLE_LIMIT_MS = 180_000
	var server_seen_throttle_s := 30.0 # index.js SEEN_WRITE_MS = 30_000 — 이보다 잦아야 seen이 실제로 갱신된다
	failures += _check(NetScript.RELAY_KEEPALIVE_S > server_seen_throttle_s,
		"keepalive: 서버 seen 스로틀(%ds)보다 길다 — 매번 스토리지에 쓰지 않게" % int(server_seen_throttle_s))
	failures += _check(NetScript.RELAY_KEEPALIVE_S * 3.0 < server_idle_limit_s,
		"keepalive: 유휴 한도(%ds)의 1/3 미만 — 한두 통 유실돼도 방이 안 끊긴다" % int(server_idle_limit_s))

	# --- ⑷ 협상/워치독 타이밍 정합 ---
	# 무수신 워치독은 ping 주기보다 넉넉히 길어야 정상 트래픽을 끊김으로 오판하지 않는다.
	failures += _check(NetScript.RTC_SILENCE_LIMIT_S > NetScript.PING_INTERVAL_S * 2.0,
		"워치독: ping 주기의 2배 초과 — 정상 왕복을 단절로 오판하지 않는다")
	failures += _check(NetScript.RTC_FAST_LIFETIME_MS > 0 and NetScript.RTC_FAST_LIFETIME_MS < 1000,
		"fast 수명: 0 초과·1s 미만(재전송 대기가 곧 지연이라 짧게)")
	failures += _check(NetScript.RTC_CH_FAST != NetScript.RTC_CH_SAFE,
		"negotiated 채널 id: fast/safe가 서로 다르다(같으면 두 채널이 겹쳐 협상이 깨진다)")

	if failures == 0:
		print("TEST_OK net_transport")
		quit(0)
	else:
		printerr("TEST_FAIL net_transport — %d개 실패" % failures)
		quit(1)


func _check(cond: bool, label: String) -> int:
	if cond:
		print("  OK  %s" % label)
		return 0
	printerr("  FAIL %s" % label)
	return 1
