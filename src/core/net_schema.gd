extends RefCounted
# 네트워크 메시지 스키마 — 단일 소스 (projectb-rules §3).
# 클라이언트(src/net/net.gd)와 중계 서버(server/relay/relay.gd)가 같은 파일을 쓴다.
# 전송 = WebSocket 텍스트 프레임 + JSON Dictionary. 메시지를 문자열 리터럴로 새로 만들지 마라.

const KEY_TYPE := "t"

# 클라 → 중계
const C_CREATE := "create"            # {t}
const C_JOIN := "join"                # {t, room}
const C_RELAY := "relay"              # {t, data}  (data = 게임 페이로드 Dictionary)

# 중계 → 클라
const S_CREATED := "created"          # {t, room, id}
const S_JOINED := "joined"            # {t, room, id, peers}  (peers = 기존 피어 id 목록)
const S_JOIN_FAIL := "join_fail"      # {t, reason} — create 실패(server_full)에도 온다 (Workers 릴레이)
const S_PEER_JOINED := "peer_joined"  # {t, id}
const S_PEER_LEFT := "peer_left"      # {t, id}
const S_ROOM_CLOSED := "room_closed"  # {t}  (호스트 이탈 — 클라는 로비로)
const S_MSG := "msg"                  # {t, from, data}

# join_fail 사유
const FAIL_NO_ROOM := "no_room"
const FAIL_FULL := "full"
const FAIL_SERVER_FULL := "server_full"  # 서버 전체 방 상한 (Workers 릴레이 자원 상한 — rules §2)

# 게임 페이로드 (data 내부). "k" = 종류.
const KEY_KIND := "k"
const G_POS := "pos"                  # {k, s, x, y, f}  자기 캐릭터 위치+좌우 플립 (각자 자기 것만 보낸다). s = 씬 id — 다른 씬 피어의 유령 스폰 방지
const G_ATK := "atk"                  # {k, dx, dy}   공격 연출 (방향) — 판정 아님, 원격 표시용
const G_JOB := "job"                  # {k, job}      직업 공지 (id 문자열) — 스테이지 입장·피어 합류 시. 수신 측은 자기 data/jobs에서 리졸브(모르는 id = 기본 직업)
const G_HIT_REQ := "hitreq"           # {k, eid}      게스트 → 호스트: 적중 요청 (호스트가 사거리 검증 후 확정)
const G_ENEMY_HP := "ehp"             # {k, eid, hp}  호스트 → 전원: 적 HP 확정 브로드캐스트 (hp<=0 = 사망)
const G_SCENE := "scene"              # {k, scene}    호스트 → 전원: 씬 전환 지시 — 스테이지 전환 확정 권한은 호스트 (rules §1·§3)

# 씬 id — G_SCENE 페이로드·G_POS "s" 필드의 값. main의 씬 매핑·각 씬 PeerSync.scene_id와 짝 (단일 소스)
const SCENE_VILLAGE := "village"
const SCENE_STAGE := "stage"

const ROOM_CODE_LEN := 4
const ROOM_CODE_CHARS := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"  # 혼동 문자(I/L/O/0/1) 제외
const MAX_ROOM_PEERS := 2  # GDD §3: 해커톤 = 2인 협동 (4인은 이후 확장)
const HOST_ID := 1         # 방마다 id 1 = 방장(호스트) — 게임 상태 확정 권한 (rules §1)


static func encode(msg: Dictionary) -> String:
	return JSON.stringify(msg)


static func decode(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	return {}
