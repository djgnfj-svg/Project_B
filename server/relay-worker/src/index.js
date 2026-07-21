// Project_B 중계 서버 — Cloudflare Workers(Durable Object) 포팅.
// 방 코드 스코프의 메시지 릴레이만 한다. 게임 로직 없음 (projectb-rules §1).
// ⚠ 메시지 스키마 정본은 res://src/core/net_schema.gd — 아래 상수는 그 미러다.
//   스키마를 바꾸면 net_schema.gd와 이 파일을 같이 고쳐라 (rules §3).
// 동작 준거는 server/relay/relay.gd(로컬 개발용 Godot 릴레이)와 1:1 동일 + 배포 필수 3종
// (자원 상한·페이로드 상한·하트비트/좀비 정리 — rules §2)을 추가한다.

const KEY_TYPE = "t";
const C_CREATE = "create";
const C_JOIN = "join";
const C_RELAY = "relay";
const S_CREATED = "created";
const S_JOINED = "joined";
const S_JOIN_FAIL = "join_fail";
const S_PEER_JOINED = "peer_joined";
const S_PEER_LEFT = "peer_left";
const S_ROOM_CLOSED = "room_closed";
const S_MSG = "msg";
const FAIL_NO_ROOM = "no_room";
const FAIL_FULL = "full";
const FAIL_SERVER_FULL = "server_full"; // 서버 전체 상한 — Worker 전용 (net_schema.gd에도 등재)
const KEY_KIND = "k";
const G_POS = "pos";
const ROOM_CODE_LEN = 4;
const ROOM_CODE_CHARS = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"; // 혼동 문자(I/L/O/0/1) 제외
const MAX_ROOM_PEERS = 2; // GDD §3: 해커톤 = 2인 협동
const HOST_ID = 1;

// 배포 필수 3종 (rules §2) — 무료 티어 보호용 상한
const MAX_CONNS = 64; // 동시 연결 상한
const MAX_ROOMS = 24; // 동시 방 상한
const MAX_MSG_UNITS = 2048; // 메시지 상한 (UTF-16 코드 유닛 — 바이트로는 최대 ~3배. pos/atk/ehp는 100 내외)
const SWEEP_MS = 60_000; // 좀비 정리 주기
const IDLE_LIMIT_MS = 180_000; // 이 시간 무수신이면 좀비로 간주 (정상 클라는 pos를 초당 15회 송신)
const SEEN_WRITE_MS = 30_000; // attachment의 seen 갱신 스로틀 — 15Hz마다 스토리지에 쓰지 않게

// 소켓별 상태는 전부 attachment에 둔다 — 인메모리는 하이버네이션(유휴 퇴거)에서 날아가므로
// 좀비 판정(seen)·방 재구성(room/id/nextId)이 전부 attachment만으로 가능해야 한다.
// {room, id, seen, nextId?} — nextId는 호스트 소켓에만 (방 수명 내 id 단조 증가 보장, relay.gd와 동일)

export class RelayHub {
	constructor(state, _env) {
		this.state = state;
		this.rooms = null; // code -> {peers: Map(id -> ws), nextId} — 하이버네이션 후 attachment로 재구성
	}

	async fetch(request) {
		if (request.headers.get("Upgrade") !== "websocket") {
			return new Response("Project_B relay — WebSocket 전용", { status: 426 });
		}
		if (this.state.getWebSockets().length >= MAX_CONNS) {
			return new Response("relay full", { status: 503 });
		}
		const pair = new WebSocketPair();
		const [client, server] = [pair[0], pair[1]];
		this.state.acceptWebSocket(server); // 하이버네이션 API — 유휴 시 과금/실행 없이 연결 유지
		server.serializeAttachment({ room: "", id: 0, seen: Date.now() });
		if ((await this.state.storage.getAlarm()) === null) {
			await this.state.storage.setAlarm(Date.now() + SWEEP_MS);
		}
		return new Response(null, { status: 101, webSocket: client });
	}

	webSocketMessage(ws, message) {
		if (typeof message !== "string") return; // 텍스트 프레임만 (relay.gd 동일)
		if (message.length > MAX_MSG_UNITS) {
			ws.close(1009, "payload too large");
			return;
		}
		const info = this._info(ws);
		const now = Date.now();
		if (now - (info.seen ?? 0) > SEEN_WRITE_MS) {
			info.seen = now;
			ws.serializeAttachment(info);
		}
		let msg;
		try {
			msg = JSON.parse(message);
		} catch {
			return;
		}
		if (typeof msg !== "object" || msg === null) return;
		this._ensureRooms();
		switch (String(msg[KEY_TYPE] ?? "")) {
			case C_CREATE: {
				if (info.room !== "") return; // 이미 방 소속 — 무시
				if (this.rooms.size >= MAX_ROOMS) {
					this._send(ws, { [KEY_TYPE]: S_JOIN_FAIL, reason: FAIL_SERVER_FULL });
					return;
				}
				const code = this._newCode();
				this.rooms.set(code, { peers: new Map([[HOST_ID, ws]]), nextId: HOST_ID + 1 });
				this._setInfo(ws, code, HOST_ID);
				this._persistNextId(this.rooms.get(code));
				this._send(ws, { [KEY_TYPE]: S_CREATED, room: code, id: HOST_ID });
				console.log(`[relay] room ${code} created`);
				break;
			}
			case C_JOIN: {
				if (info.room !== "") return;
				const code = String(msg.room ?? "").trim().toUpperCase();
				const room = this.rooms.get(code);
				if (!room) {
					this._send(ws, { [KEY_TYPE]: S_JOIN_FAIL, reason: FAIL_NO_ROOM });
					return;
				}
				if (room.peers.size >= MAX_ROOM_PEERS) {
					this._send(ws, { [KEY_TYPE]: S_JOIN_FAIL, reason: FAIL_FULL });
					return;
				}
				const pid = room.nextId;
				room.nextId = pid + 1;
				this._persistNextId(room);
				const existing = [...room.peers.keys()];
				room.peers.set(pid, ws);
				this._setInfo(ws, code, pid);
				this._send(ws, { [KEY_TYPE]: S_JOINED, room: code, id: pid, peers: existing });
				for (const otherId of existing) {
					this._send(room.peers.get(otherId), { [KEY_TYPE]: S_PEER_JOINED, id: pid });
				}
				console.log(`[relay] peer ${pid} joined room ${code}`);
				break;
			}
			case C_RELAY: {
				const room = this.rooms.get(info.room);
				if (info.room === "" || !room) return; // 방 미소속 릴레이는 버린다 (신뢰 경계)
				const data = msg.data;
				if (typeof data !== "object" || data === null || Array.isArray(data)) return;
				const out = JSON.stringify({ [KEY_TYPE]: S_MSG, from: info.id, data });
				const kind = String(data[KEY_KIND] ?? "");
				if (kind !== G_POS) {
					// pos는 초당 15회라 제외 — 저빈도 게임 이벤트만 기록 (운영 진단용)
					console.log(`[relay] ${kind}: ${info.id} -> room ${info.room}: ${JSON.stringify(data)}`);
				}
				for (const [pid, peer] of room.peers) {
					if (pid !== info.id) this._sendRaw(peer, out);
				}
				break;
			}
		}
	}

	webSocketClose(ws, _code, _reason, _clean) {
		this._dropClient(ws);
	}

	webSocketError(ws, _error) {
		this._dropClient(ws);
	}

	// 좀비 피어 정리 (rules §2 필수 3종) — 무수신 연결을 주기적으로 끊는다.
	// 판정은 attachment의 seen(하이버네이션 생존) 기준. close 핸들러 호출은 죽은 TCP 피어에서
	// 보장되지 않으므로 방 정리(_dropClient)를 여기서 직접 호출한다 (_dropClient는 멱등).
	async alarm() {
		const now = Date.now();
		for (const ws of this.state.getWebSockets()) {
			const info = this._info(ws);
			if (now - (info.seen ?? 0) > IDLE_LIMIT_MS) {
				console.log(`[relay] closing idle peer (room=${info.room})`);
				try {
					ws.close(1001, "idle timeout");
				} catch {
					// 이미 닫힌 소켓 — 정리만 진행
				}
				this._dropClient(ws);
			}
		}
		if (this.state.getWebSockets().length > 0) {
			await this.state.storage.setAlarm(now + SWEEP_MS);
		}
	}

	// 하이버네이션에서 깨어난 뒤 방 상태를 소켓 attachment로 재구성.
	// nextId는 호스트 attachment에 영속화된 값을 우선 사용 — 이탈 피어 id 재사용 방지 (relay.gd의
	// 방 수명 내 id 단조 증가와 동일. GDD §11 재접속 처리가 id 기준 상태를 보관하게 되면 필수)
	_ensureRooms() {
		if (this.rooms !== null) return;
		this.rooms = new Map();
		for (const ws of this.state.getWebSockets()) {
			const info = this._info(ws);
			if (info.room === "") continue;
			let room = this.rooms.get(info.room);
			if (!room) {
				room = { peers: new Map(), nextId: HOST_ID + 1 };
				this.rooms.set(info.room, room);
			}
			room.peers.set(info.id, ws);
			room.nextId = Math.max(room.nextId, info.id + 1, info.nextId ?? 0);
		}
	}

	_dropClient(ws) {
		this._ensureRooms();
		const info = this._info(ws);
		if (info.room === "") return; // 이미 정리됨 (alarm→close 이중 호출 등) — 멱등
		this._setInfo(ws, "", 0);
		const room = this.rooms.get(info.room);
		if (!room) return;
		room.peers.delete(info.id);
		if (info.id === HOST_ID) {
			// 호스트 권한 모델(rules §1): 호스트 이탈 = 방 종료
			for (const peer of room.peers.values()) {
				this._send(peer, { [KEY_TYPE]: S_ROOM_CLOSED });
				this._setInfo(peer, "", 0);
			}
			this.rooms.delete(info.room);
			console.log(`[relay] room ${info.room} closed (host left)`);
		} else if (room.peers.size === 0) {
			this.rooms.delete(info.room);
			console.log(`[relay] room ${info.room} emptied`);
		} else {
			for (const peer of room.peers.values()) {
				this._send(peer, { [KEY_TYPE]: S_PEER_LEFT, id: info.id });
			}
			console.log(`[relay] peer ${info.id} left room ${info.room}`);
		}
	}

	// attachment 읽기 — null 방어 (alarm 안에서 throw하면 Cloudflare가 alarm을 재시도해 루프 위험)
	_info(ws) {
		let info = null;
		try {
			info = ws.deserializeAttachment();
		} catch {
			// 닫힌 소켓 등 — 기본값으로
		}
		return info ?? { room: "", id: 0, seen: 0 };
	}

	// room/id 갱신 — seen 등 다른 필드는 보존 (닫힌 소켓이면 조용히 무시)
	_setInfo(ws, room, id) {
		try {
			ws.serializeAttachment({ ...this._info(ws), room, id });
		} catch {
			// 닫힌 소켓 — 정리 경로에서만 도달, 무시
		}
	}

	// 방의 nextId를 호스트 attachment에 영속화 — 하이버네이션 후 _ensureRooms가 복원
	_persistNextId(room) {
		const hostWs = room.peers.get(HOST_ID);
		if (!hostWs) return;
		try {
			hostWs.serializeAttachment({ ...this._info(hostWs), nextId: room.nextId });
		} catch {
			// 닫힌 소켓 — 무시
		}
	}

	_send(ws, msg) {
		this._sendRaw(ws, JSON.stringify(msg));
	}

	_sendRaw(ws, text) {
		try {
			ws.send(text);
		} catch {
			// 닫히는 중인 소켓 — close 콜백이 정리한다
		}
	}

	_newCode() {
		for (;;) {
			const buf = new Uint8Array(ROOM_CODE_LEN);
			crypto.getRandomValues(buf);
			let code = "";
			for (const b of buf) code += ROOM_CODE_CHARS[b % ROOM_CODE_CHARS.length];
			if (!this.rooms.has(code)) return code;
		}
	}
}

export default {
	fetch(request, env) {
		// 단일 허브 DO — 방 코드가 전역 유일해야 하므로 모든 연결이 한 인스턴스로 (해커톤 규모엔 충분:
		// 상한 기준 최악 ~960 msg/s의 2KB JSON 릴레이는 DO 단일 스레드 용량 내).
		// 확장 필요 시 탈출로: 방 코드를 DO 이름으로(idFromName(code)) 방 단위 샤딩 — create는 DO 내
		// storage 플래그로 선점 확인. 그 시점엔 접속 URL에 방 코드가 실려야 한다.
		return env.RELAY_HUB.get(env.RELAY_HUB.idFromName("hub")).fetch(request);
	},
};
