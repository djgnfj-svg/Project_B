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
const G_POS := "pos"                  # {k, s, x, y, f, a}  자기 캐릭터 위치+좌우 플립+조준각(a, 라디안 — 무기 표시 전용, 판정 아님) (각자 자기 것만 보낸다). s = 씬 id — 다른 씬 피어의 유령 스폰 방지
const G_ATK := "atk"                  # {k, dx, dy}   공격 연출 (방향) — 판정 아님, 원격 표시용
const G_JOB := "job"                  # {k, job}      직업 공지 (id 문자열) — 스테이지 입장·피어 합류 시. 수신 측은 자기 data/jobs에서 리졸브(모르는 id = 기본 직업)
const G_STATS := "stats"              # {k, atk, hp, weapon}  장비 총 스탯 + 착용 무기 id 공지. atk/hp = 호스트가 데미지/HP 확정에 사용(트러스트=발신자, clamp). weapon = 원격 무기 겉모습(표시 전용, allowlist 리졸브만). 4인/PvP 전 검증 게이트(rules §2)
const G_HIT_REQ := "hitreq"           # {k, eid}      게스트 → 호스트: 적중 요청 (호스트가 사거리 검증 후 확정)
const G_ENEMY_HP := "ehp"             # {k, eid, hp}  호스트 → 전원: 적 HP 확정 브로드캐스트 (hp<=0 = 사망)
const G_SCENE := "scene"              # {k, scene, c, i} 호스트 → 전원: 씬 전환 지시 — 전환 확정 권한은 호스트 (rules §1·§3). scene=stage일 때 c=챕터 id·i=스테이지 인덱스 — 수신 측은 data/chapters 스캔 allowlist + 범위 검증(scene_flow)
const G_ROLL := "roll"                # {k, dx, dy}   발신자=본인: 구르기 시작 선언 — 호스트가 쿨다운 검증 후 i-frame 창 부여. dx/dy = 원격 구르기 연출(peer_sync가 소비, 표시 전용)
const G_MOB_POS := "mpos"             # {k, m}        호스트 → 전원: 잔몹 위치 배치 (m = [[eid, x, y, f], …], 10Hz). ⚠ 릴레이 2곳 로그 제외 목록에 등록 (고빈도)
const G_MOB_ATK := "matk"             # {k, eid, x, y} 호스트 → 전원: 잔몹 텔레그래프 시작(타격 중심). 타격 시각은 def.telegraph_s를 각자 로컬 리졸브
const G_PLAYER_HP := "php"            # {k, pid, hp}  호스트 → 전원: 플레이어 HP 확정 (hp<=0 = 사망 → 관전, 사망자에게 hp 1 = 클리어 부활). 자기 HP도 이것만 믿는다 (§3)
const G_STAGE_CLEAR := "clear"        # {k}           호스트 → 전원: 스테이지 클리어 (부활 자체는 php로 — clear는 흐름/배너)
const G_WIPE := "wipe"                # {k}           호스트 → 전원: 전멸 (배너 후 호스트가 G_SCENE village 송신)
const G_SIT := "sit"                  # {k, on}       발신자=본인: 모닥불 앉기 상태 공지 — 표시/회복 힌트일 뿐, 회복 확정은 호스트가 거리·생존 재검증 후 (campfire 씬)

# 드랍/픽업 (공유 드랍 — 호스트 롤·선착 픽업, 2026-07-23). 상태 확정 권한 = 호스트 (§1·§3).
const G_DROP := "drop"                # {k, s, d}     호스트→전원: 한 킬의 드랍 묶음. s=stage_token(유령 스폰 차단, G_POS "s" 미러). d=[[did,dk,id,q,x,y,r], …] did=드랍 고유 id·dk=kind(gold/material/blueprint)·id=ref_id·q=수량(gold=금액)·x/y=위치·r=rarity
const G_PICK_REQ := "pickreq"         # {k, did}      게스트→호스트: 픽업 요청 (선착 — 호스트가 존재·선착 확정)
const G_PICK_OK := "pickok"           # {k, did, pid} 호스트→전원: 픽업 확정. did despawn, pid==my_id인 클라만 인벤 반영(collect_drop)

# 보스전 (2026-07-23). 상태 확정 권한 = 호스트 (§1·§3). 전부 저빈도(패턴/생성당 1회) → relay-worker 로그 제외 불필요.
const G_BOSS_ATK := "batk"            # {k, eid, p, x, y, a} 호스트→전원: 보스 패턴 텔레그래프. p=패턴 id·(x,y)=판정 중심·a=각(rad). 타격 시각·판정 반경은 패턴 telegraph_s/range를 각자 로컬 리졸브 (matk 규약 확장)
const G_SWAMP := "swamp"              # {k, s, sw}    호스트→전원: 늪 존 스폰. s=stage_token(유령 스폰 차단, G_DROP "s" 미러)·sw=[[sid,x,y,r,ttl,slow], …] sid=늪 고유 id·(x,y)=중심·r=반경·ttl=지속(초, 로컬 despawn)·slow=늪 안 이동 배율
const G_BOSS_PHASE := "bphase"        # {k, ph}       호스트→전원: 페이즈 전환 표시 큐(연출/배너용). 정본 판정은 호스트 hp — 표시 동기화일 뿐
const G_BOSS_SPRAY := "bspray"        # {k, eid, p, c} 호스트→전원: 물 뿌리기 N개 원 착탄 예고. p=패턴 id(반경·telegraph_s 로컬 리졸브)·c=[[x,y], …] 착탄 중심들. 판정은 호스트가 착탄점마다 is_strike_hit(표시 전용 메시지)

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
