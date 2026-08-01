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
const G_POS := "pos"                  # {k, n, s, x, y, f, a, c, vx, vy}  n = 송신 시퀀스(단조 증가) — 🔴 **P2P fast 채널이 unordered**라 순서가 뒤바뀐 위치 패킷이 앵커를 과거로 되돌릴 수 있다(릴레이 TCP에선 구조적으로 불가능했던 결함). 되돌아간 앵커는 net_anchor와 net_anchor_lead를 **같은 방향으로 함께** 낡게 만들어 "둘 다 맞아야 확정"인 방어자 우대 규약을 무력화한다 → 수신부가 CombatMath.is_pos_seq_fresh로 폐기. 0/미부착 = 항등 폴백(구버전·릴레이 경로). 자기 캐릭터 위치+좌우 플립+조준각(a, 라디안 — 무기 표시 전용, 판정 아님) (각자 자기 것만 보낸다). s = 씬 id — 다른 씬 피어의 유령 스폰 방지. c = 현재 차지 레벨(0~3, 법사 지팡이 — 원격 차지 오브 표시 전용, 판정 아님. 실제 발사 레벨은 G_SHOOT "c"를 호스트가 별도 검증). vx/vy = 현재 속도(px/s) — 호스트가 지연 보상 외삽에 쓴다(CombatMath.extrapolate). 속도는 이동 상한으로 clamp되고 외삽 결과도 거리 상한이 있어, 부풀려 보내도 "방어자 우대" 규약상 회피가 관대해질 뿐 피해를 못 만든다 (§3 지연 보상)
const G_ATK := "atk"                  # {k, dx, dy, cb} 공격 선언 (방향 + 콤보 타수). 🔴 **"cb"는 v2.2(2026-07-29)부터 판정 입력이다 — 「궤적만 정한다」가 아니다.** 근접 콤보의 타별 데미지·마무리 각이 이 타수에서 나온다. 호스트는 주장을 그대로 믿지 않고 **자기 수신 간격으로 직접 세며**(CombatMath.advance_combo) 이 값은 `min` 상한으로만 쓴다 = G_SHOOT "cb"와 **같은 규약**. 🔴 **근접 타수는 이 메시지로만 셀 수 있다** — G_HIT_REQ는 맞았을 때만 오므로 그걸로 세면 **헛친 스윙이 누락돼** 정직한 마무리 타가 `min`에 깎인다(근접은 헛치는 것이 흔하다). 그래서 이 kind는 유실 허용(fast) 채널에 **절대 넣지 마라** — 한 통이 사라지면 그 콤보가 끝날 때까지 호스트가 1타 밀린 채 간다. dx/dy는 표시용(판정 방향은 G_HIT_REQ가 따로 싣는다)
const G_JOB := "job"                  # {k, job}      직업 공지 (id 문자열) — 스테이지 입장·피어 합류 시. 수신 측은 자기 data/jobs에서 리졸브(모르는 id = 기본 직업)
const G_STATS := "stats"              # {k, atk, hp, weapon, lv}  장비 총 스탯 + 착용 무기 id + **레벨 스탯** 공지. atk/hp = 호스트가 데미지/HP 확정에 사용(트러스트=발신자, clamp). weapon = 원격 무기 겉모습(표시 전용, allowlist 리졸브만). lv = 직업 레벨 5스탯 {crit, crit_dmg, haste, move, leech} — 키는 CombatMath.LEVEL_STAT_KEYS 그대로, 호스트가 치명/피흡/공속 확정에 쓰므로 수신 측이 **키 목록을 순회**해 데이터 유도 상한(GameState.max_level_stats)으로 clamp한다(모르는 키 자동 폐기). 4인/PvP 전 검증 게이트(rules §2)
const G_HIT_REQ := "hitreq"           # {k, eid, dx, dy}  게스트 → 호스트: 적중 요청 (호스트가 **부채꼴** 검증 후 확정). dx/dy = 그 타격의 조준 방향 — 🔴 **표시 전용이던 방향이 판정 값으로 승격됐다**(무기 모션 축 2026-07-28). 호스트는 이 방향으로 `swing_arc` 부채꼴을 세워 검증한다. 스푸핑해도 **판정이 넓어지지 않는다**: 부채꼴은 **그 무기의 원**(호스트가 `peer_weapon_id`로 리졸브한 `melee_range` 기준)의 부분집합이라 어떤 방향을 주장해도 그 원을 못 넘고, 얻는 것은 "자기 화면과 다른 쪽을 때리기"뿐인데 그건 자기 화면에 헛스윙으로 보인다(협동 2인이라 남에게 피해 없음). ⚠ **"도입 전보다 좁다"고 쓰지 마라** — 반경 자체가 무기로 바뀌므로 부분집합 관계는 **같은 반경에서만** 성립한다(사거리 상한은 `MAX_MELEE_RANGE`가 따로 잡는다).
# 🔴 **부채꼴은 게임 정합 장치이지 안티치트가 아니다** (2026-07-28 netreview m-3). 방향이 없거나 non-finite면 각 검사를 **생략**하므로(접속 창·구버전에서 정당한 근접타가 조용히 사라지는 것을 피하려는 선택), 변조 클라는 `dx`/`dy`를 **빼기만 하면** 도입 전 판정을 그대로 받는다. 회귀는 아니지만 **여기에 신뢰를 얹지 마라** — 이 경로의 실제 신뢰 경계는 넷이다: `can_job_equip` 대조 · `is_projectile_weapon` 거부 · 사거리(`HIT_REACH_SLACK`) · `_confirm_damage`의 쿨다운 게이트.
const G_ENEMY_HP := "ehp"             # {k, eid, hp, cr}  호스트 → 전원: 적 HP 확정 브로드캐스트 (hp<=0 = 사망). cr = 1이면 이번 확정이 치명타(표시 강조 전용 — 게스트가 자기 치명을 아는 유일한 경로. 굴림은 호스트만 §1). php(플레이어 HP)엔 없다 — 적은 치명타를 굴리지 않는다
const G_SCENE := "scene"              # {k, scene, c, i} 호스트 → 전원: 씬 전환 지시 — 전환 확정 권한은 호스트 (rules §1·§3). scene=stage일 때 c=챕터 id·i=스테이지 인덱스 — 수신 측은 data/chapters 스캔 allowlist + 범위 검증(scene_flow)
const G_ROLL := "roll"                # {k, dx, dy}   발신자=본인: 구르기 시작 선언 — 호스트가 쿨다운 검증 후 i-frame 창 부여. dx/dy = 원격 구르기 연출(peer_sync가 소비, 표시 전용)
const G_MOB_POS := "mpos"             # {k, m}        호스트 → 전원: 잔몹 위치 배치 (m = [[eid, x, y, f], …], 10Hz). ⚠ 릴레이 2곳 로그 제외 목록에 등록 (고빈도)
const G_MOB_ATK := "matk"             # {k, eid, x, y} 호스트 → 전원: 잔몹 텔레그래프 시작(타격 중심). 타격 시각은 def.telegraph_s를 각자 로컬 리졸브
# {k, eid, ox, oy, dx, dy, aid} 호스트 → 전원: 원거리 잔몹 발사. (ox,oy)=원점·(dx,dy)=정규화 방향·aid=투사체 고유 id.
# 🔴 **수치는 하나도 싣지 않는다** — 속도·사거리·데미지·명중 반경은 각 클라가 `eid`로 찾은 자기 씬의
#   EnemyDef에서 리졸브한다(peer_weapon_id·projectile_params와 같은 철학). 스푸핑 표면 0.
# 🔴 **RTC_FAST_KINDS에 절대 넣지 마라** — 사건 kind다. 한 통 유실이면 화살이 안 보이는데 데미지만 온다.
# 🔴 aid 네임스페이스 = "m:<eid>:<seq>". 플레이어는 "<피어id>:<seq>"이고 G_SHOOT 수신부가
#   `aid.begins_with(str(from_id) + ":")`로 검증한다 — 나중에 같은 검증을 몹에 미러하려는 사람이
#   이 접두사를 모르면 **정직한 화살이 조용히 거부된다.**
# 신뢰 경계: 수신부가 `from_id != HOST_ID`면 폐기(MobSync 최상단). 게스트는 이 kind를 발신하지 않는다.
const G_MOB_SHOOT := "mshoot"
const G_PLAYER_HP := "php"            # {k, pid, hp}  호스트 → 전원: 플레이어 HP 확정 (hp<=0 = 사망 → 관전, 사망자에게 hp 1 = 클리어 부활). 자기 HP도 이것만 믿는다 (§3)
const G_STAGE_CLEAR := "clear"        # {k}           호스트 → 전원: 스테이지 클리어 (부활 자체는 php로 — clear는 흐름/배너)
const G_WIPE := "wipe"                # {k}           호스트 → 전원: 전멸 (배너 후 호스트가 G_SCENE village 송신)
const G_SIT := "sit"                  # {k, on}       발신자=본인: 모닥불 앉기 상태 공지 — 표시/회복 힌트일 뿐, 회복 확정은 호스트가 거리·생존 재검증 후 (campfire 씬)

# 직업 레벨 EXP (성장축 2026-07-25, GDD v1.8). 확정 권한 = 호스트 (§1·§3) — 각 클라가 킬을 세면 레벨이 조용히 갈린다.
# ⚠ **stage_token("s") 가드를 의도적으로 붙이지 않는다** — G_DROP/G_SWAMP와 다르다. 토큰 가드의 목적은
#   "다른 칸에 유령 오브젝트가 생기는 것" 차단인데 EXP는 비공간적이고, 씬 전환 창에 도착한 지급을 버리면
#   그게 곧 클라 간 레벨 발산(= 고치려는 문제 자체)이다. 신뢰 경계는 `from_id == HOST_ID`뿐.
const G_EXP := "exp"                  # {k, e}        호스트 → 전원: 킬 EXP 지급(e = 적립량). 파티 전원 동일 지급 = 관전 중 사망자도 받는다(GDD §6)

# 투사체 (궁수 활 — 실제 이동 화살, 2026-07-24). 상태 확정 권한 = 호스트 (§1·§3).
# 결정론적 직선 이동 = 각 클라가 로컬로 표시 화살 시뮬(위치 스트림 불필요, 네트워크 최소). 명중 판정은 호스트만.
const G_SHOOT := "shoot"              # {k, ox, oy, dx, dy, aid, r, w, c, cb} 발신자=본인: 발사 선언. (ox,oy)=원점·(dx,dy)=정규화 방향·aid=투사체 고유 id("피어id:seq")·r=사거리(px, 무기 EquipDef.arrow_range)·w=착용 무기 id(선택 — 수신 측이 allowlist 리졸브해 탄 겉모습/속도/폭발 반경을 얻는다, 경로는 절대 안 보냄 §3)·c=차지 레벨(선택, 0~3 — 법사 지팡이). 각 클라가 표시 투사체 스폰. 호스트는 발사 쿨다운+원점 근접+차지 시간(is_charge_time_ok) 검증 후 권한 투사체 등록(명중 판정용), r·속도·폭발 반경은 MAX로 clamp(§3). ⚠ 연사(~6.6Hz) 고빈도 → 릴레이 2곳 로그 제외 목록에 등록
# 🔴 cb = 평타 콤보 타수(궁수 "평·평·쭉", 2026-07-27). ⚠ **v2.2(2026-07-29)에 G_ATK "cb"도 판정 입력이 되어
#   두 kind의 성격이 같아졌다** — 아래 규약(호스트가 직접 세고 주장은 상한)을 **양쪽이 공유한다**. 갈리는 것은
#   무엇을 고르는가뿐이다: 이쪽은 사거리·데미지, 저쪽은 데미지·마무리 각(근접은 사거리를 안 쓴다). 호스트는 이 값을
#   판정에 그대로 쓰지 않는다: 자기 수신 간격으로 직접 세고(CombatMath.advance_combo) **주장은 상한으로만**
#   쓴다(authoritative_combo = min). 표시(ArrowField)는 주장값을 그대로 그리므로 사칭자는 **자기 화면에만**
#   강화살이 그려지고 판정은 안 난다(G_SHOOT "w" 무기 사칭과 같은 안전한 방향의 갈라짐).
#   ⚠ 배율·뜸 **수치는 절대 전송하지 않는다** — 각 클라가 무기 id로 EquipDef.combo_*를 로컬 리졸브한다.
const G_ARROW_HIT := "arrowhit"       # {k, aid, x, y} 호스트→전원: 투사체 aid 종료(적중)를 (x,y)에서. 각 클라가 표시 투사체 despawn + 임팩트/폭발 연출(반경은 스폰 때 리졸브한 로컬 값 — 전송 불필요). 데미지 자체는 G_ENEMY_HP 경유. ⚠ 명중마다 고빈도 → 릴레이 2곳 로그 제외 목록에 등록

# 드랍/픽업 (공유 드랍 — 호스트 롤·선착 픽업, 2026-07-23). 상태 확정 권한 = 호스트 (§1·§3).
const G_DROP := "drop"                # {k, s, d}     호스트→전원: 한 킬의 드랍 묶음. s=stage_token(유령 스폰 차단, G_POS "s" 미러). d=[[did,dk,id,q,x,y,r], …] did=드랍 고유 id·dk=kind(gold/material/blueprint)·id=ref_id·q=수량(gold=금액)·x/y=위치·r=rarity
const G_PICK_REQ := "pickreq"         # {k, did}      게스트→호스트: 픽업 요청 (선착 — 호스트가 존재·선착 확정)
const G_PICK_OK := "pickok"           # {k, did, pid} 호스트→전원: 픽업 확정. did despawn, pid==my_id인 클라만 인벤 반영(collect_drop)

# 보스전 (2026-07-23). 상태 확정 권한 = 호스트 (§1·§3). 전부 저빈도(패턴/생성당 1회) → relay-worker 로그 제외 불필요.
const G_BOSS_ATK := "batk"            # {k, eid, p, x, y, a} 호스트→전원: 보스 패턴 텔레그래프. p=패턴 id·(x,y)=판정 중심·a=각(rad). 타격 시각·판정 반경은 패턴 telegraph_s/range를 각자 로컬 리졸브 (matk 규약 확장)
const G_SWAMP := "swamp"              # {k, s, sw}    호스트→전원: 늪 존 스폰. s=stage_token(유령 스폰 차단, G_DROP "s" 미러)·sw=[[sid,x,y,r,ttl,slow], …] sid=늪 고유 id·(x,y)=중심·r=반경·ttl=지속(초, 로컬 despawn)·slow=늪 안 이동 배율
const G_ROCK := "rock"                # {k, s, rk}    호스트→전원: 낙석(P4) 바위 지형 스폰. s=stage_token(유령 스폰 차단, G_SWAMP "s" 미러)·rk=[[rid,x,y,r,ttl], …] rid=바위 고유 id·(x,y)=중심·r=충돌 반경·ttl=지속(초, 로컬 despawn). 판정 없음(지형)·돌진 충돌은 호스트 로컬(각 클라 자기 플레이어도 로컬 충돌) — G_SWAMP 미러(장판 대신 정적 몸)
const G_BOSS_PHASE := "bphase"        # {k, ph}       호스트→전원: 페이즈 전환 표시 큐(연출/배너용). 정본 판정은 호스트 hp — 표시 동기화일 뿐
const G_BOSS_SPRAY := "bspray"        # {k, eid, p, c} 호스트→전원: 물 뿌리기 N개 원 착탄 예고. p=패턴 id(반경·telegraph_s 로컬 리졸브)·c=[[x,y], …] 착탄 중심들. 판정은 호스트가 착탄점마다 is_strike_hit(표시 전용 메시지)

# ── 코옵 파훼 기믹 (소울 브레이크: 둘이 동시에 F 눌러 시전 취소) ──
const G_COOP_CALL := "ccall"          # {k, t}   호스트→전원: 코옵 파훼 시전 시작. t=파훼 창(초). 각 클라 프롬프트 표시
const G_COOP_IN := "cin"              # {k}      발신자=본인→호스트: 파훼 입력(F 눌렀다). 호스트가 생존 피어별 1회 집계
const G_COOP_RES := "cres"            # {k, ok}  호스트→전원: 파훼 결과. ok=1 전원 입력 성공(시전 취소·보스 그로기), ok=0 실패(파티 피해). 판정 권한=호스트 (rules §3)
const G_COOP_GAUGE := "cgauge"         # {k, du, re}  호스트→전원: C1 영혼 비석 두 게이지 표시 동기화(du=비석 내구도·re=A 저항). 저빈도(~6Hz), 표시 전용 — 판정은 호스트가 이미 확정(내구도 0/저항 0은 G_COOP_RES로 결말 통지)
const G_THORN := "cthorn"              # {k, x, y, t}  호스트→전원: C1 가시 링/파편 스폰(표시 동기화). t="ring"(예고→버스트 회피 대상)·"shard"(회수 아이템). 🔴 판정(링 피격·파편 회수)은 호스트만 — 게스트는 링을 보고 피할 수 있게 표시만(G_MOB_ATK 예고 규약 미러)

# 왕복 지연 계측 (2026-07-24) — 지연 보상(§3)의 입력이자 HUD 핑 표시의 출처. Net 오토로드가 자체 처리한다
# (게임 로직으로 안 올라온다 — net_msg emit 전에 Net이 가로챈다). 각자 상대에게 보내고 상대는 즉시 에코.
# ⚠ 이름이 "ping"/"pong"이 아니다 — `tests/test_net_room_auto.gd`가 그 두 문자열을 **임의의 게임 메시지**로
#   이미 쓰고 있어서, 같은 이름을 쓰면 Net이 테스트 메시지를 가로채 왕복 테스트가 조용히 깨진다(실제로 겪음).
#   Net이 소비하는 메시지에 이름을 붙일 땐 기존 테스트/게임 kind와 겹치지 않는지 먼저 grep해라.
const G_PING := "nping"               # {k, t}  발신자→상대: t = 발신자의 로컬 usec 타임스탬프(그대로 돌려받을 불투명 값)
const G_PONG := "npong"               # {k, t}  수신 즉시 에코 — 원 발신자가 (지금 − t)로 RTT를 계산한다. 시계 동기화 불필요(자기 시계만 씀)

# P2P 직결 시그널링 (2026-07-26) — 게임 메시지 경로에서 릴레이를 걷어내기 위한 WebRTC 협상.
# 🔴 **이 두 메시지만 릴레이를 탄다.** 연결 수립 후의 게임 페이로드는 전부 DataChannel 직결로 흐른다
#   (릴레이 왕복 ~207ms → 직결 10~40ms, 실측 근거는 rules §5). 협상은 연결당 몇 통뿐이라 저빈도.
# ⚠ G_PING/G_PONG과 같이 **Net이 소비한다** — net_msg로 게임 로직에 올리지 않는다. 이름은 기존 kind와
#   겹치지 않는지 grep으로 확인했다(rules §5 "nping" 사고 재발 방지).
const G_RTC_SDP := "rtcsdp"           # {k, ty, sdp}      offer/answer 교환. ty = "offer"|"answer"(그 외 폐기)
const G_RTC_ICE := "rtcice"           # {k, m, i, n}      ICE 후보. m=media·i=index·n=name(후보 문자열)
# 🔴 릴레이 유지용 keepalive — **직결이 열리면 릴레이로 나가는 프레임이 0이 된다**는 함정의 대응(리뷰 C1).
#   릴레이 Worker는 `seen`(그 소켓이 마지막으로 보낸 시각) 기준 3분 무수신을 좀비로 간주해 연결을 끊는데,
#   P2P 성공 후엔 게임 트래픽이 전부 직결로 빠져 그 조건이 **상시 성립**한다 → 3분마다 방이 끊기고
#   `net_disconnected` → 로비 복귀 → 챕터 진행·이월 HP 소실. ⚠ 로컬 릴레이(server/relay/relay.gd)엔
#   유휴 스윕이 없어 `dev_local.sh`에선 **영원히 재현되지 않는다** — 배포본에서만 터진다.
# ⚠ RTT 계측(G_PING)과 **의도적으로 분리**한다 — keepalive는 릴레이 왕복(~207ms)이라 이걸로 RTT를 재면
#   직결 지연 추정이 릴레이 값으로 오염돼 지연 보상(§3)이 과보상한다. 그래서 응답도 없는 단방향이다.
const G_KEEP := "nkeep"               # {k}  발신자→방: 릴레이 소켓 살아있음 통보. 수신 측은 Net이 소비하고 버린다(무동작)

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
