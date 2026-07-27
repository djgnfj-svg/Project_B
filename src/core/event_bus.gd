class_name EventBusHub
extends Node
# 모듈 간 유일 통신로 (projectb-rules §0·§1). 시그널 추가는 리드가 한다.
# class_name(core·리드 전용)을 두는 이유: -s 헤드리스 테스트에선 오토로드 전역 식별자가
# 컴파일되지 않으므로, 테스트 대상 스크립트는 /root 경로 + 이 타입으로 접근한다 (rules §5).
# 필드를 붙이는 쪽이 emit해야 한다 — 발신자 없는 시그널은 에러 없이 조용히 안 돈다.

# --- net (src/net/net.gd가 emit) ---
signal net_connected
signal net_connect_failed(reason: String)
signal net_disconnected
signal room_created(code: String)
signal room_joined(code: String, peer_ids: Array[int])
signal room_join_failed(reason: String)
signal room_closed
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal net_msg(from_id: int, data: Dictionary)
signal player_spawned(peer_id: int, player: Node)  # PeerSync가 스폰 완료(잡 반영 포함) 시 emit — 호스트의 이월 HP 확정(CombatAuthority) 등 스폰 후속 처리용

# --- flow (마을/스테이지가 emit, src/main이 씬 스왑) ---
signal scene_change(scene_id: String)  # 호스트 로컬 결정 또는 게스트의 G_SCENE 수신 후 emit — 스왑은 main만 한다
signal leave_to_village_requested  # 설정 → "마을로 가기" — SceneFlow(호스트 권한)가 받아 전원 귀환. 게스트 발신은 무시됨
signal job_change_requested(job_id: String)  # 설정 → "직업 변경" — PeerSync(마을 씬만)가 받아 로컬 직업 교체+재공지

# --- combat (플레이어/적이 emit, 스테이지가 권한 처리) ---
signal attack_hit(enemy: Node, job: JobDef)     # 로컬 공격 판정이 적에 닿음(공격자 job 동봉) — 확정은 호스트 경로(stage)
signal enemy_hp_confirmed(eid: String, hp: int)  # 호스트 전용 emit(enemy 권한 경로/부활) — stage가 ehp 브로드캐스트
signal player_hp_confirmed(peer_id: int, hp: int)  # 확정 HP 통지 — 호스트=Health 권한 경로, 게스트=php 수신 경로. 호스트일 때만 stage가 php 브로드캐스트
signal mob_telegraph(eid: String, center: Vector2)  # 호스트 전용 emit(잔몹 AI WINDUP) — MobSync가 matk 브로드캐스트
signal mob_strike(eid: String, center: Vector2)     # 호스트 전용 emit(잔몹 AI STRIKE) — CombatAuthority가 데미지 확정

# --- 투사체 (궁수 활 2026-07-24 / 법사 차지 지팡이 확장) — 발사는 로컬 선언, 표시 탄은 각 클라 로컬 시뮬, 명중 확정은 호스트만 ---
signal player_shoot(shooter_id: int, origin: Vector2, dir: Vector2, aid: String, arrow_range: float, weapon_id: String, charge: int, combo: int)  # 로컬 발사 선언(player emit) — ArrowField가 표시 투사체 스폰, CombatAuthority(호스트 자기 발사)가 권한 투사체 등록. arrow_range = 무기 사거리(EquipDef.arrow_range) · weapon_id = 착용 무기 id(수신 측이 allowlist 리졸브해 탄 겉모습/속도/폭발 반경을 얻는다) · charge = 차지 레벨(0~3, 비차지 무기는 0) · combo = 평타 콤보 타수(궁수 "평·평·쭉" — 사거리/데미지 배율은 EquipDef.combo_*를 각 클라가 로컬 리졸브, 타수만 오간다). player가 G_SHOOT도 송신(원격 표시용)
signal arrow_gone_local(aid: String, world_pos: Vector2)  # 호스트 전용 emit(CombatAuthority: 자기 권한 투사체 종료 — 적중/사거리 소진) → 호스트 ArrowField가 자기 표시 탄 despawn+임팩트. 호스트는 자기 G_ARROW_HIT를 릴레이로 못 받으므로(drop_pick_local 미러). 게스트는 G_ARROW_HIT 수신으로 처리

# --- boss (보스전 2026-07-23) — 호스트 전용 emit(보스 AI), 표시(telegraph)와 판정(strike) 분리. mob_* 규약 확장 ---
signal boss_telegraph(eid: String, pattern_id: String, center: Vector2, angle: float)  # 호스트 emit(보스 WINDUP) — MobSync가 G_BOSS_ATK 브로드캐스트(표시). 수신 측은 자기 def에서 패턴 리졸브
signal boss_strike(center: Vector2, angle: float, pattern: BossPatternDef)  # 호스트 emit(보스 STRIKE) — CombatAuthority가 pattern.shape별(원/부채꼴) 플레이어 피격 판정
signal swamp_spawn_local(swamps: Array)  # 호스트 보스 → SwampField 로컬 스폰 (호스트는 자기 G_SWAMP를 릴레이로 못 받으므로 — drop_spawn_local 미러). swamps=[[sid,x,y,r,ttl,slow], …] slow=늪 안 이동 배율
signal boss_spray(eid: String, pattern_id: String, centers: Array, angle: float)  # 호스트 emit(보스 물뿌리기 WINDUP) — MobSync가 G_BOSS_SPRAY 브로드캐스트. 각 클라가 centers마다 원 텔레그래프 표시(N개). 판정은 호스트가 STRIKE 시 boss_strike를 착탄점마다 재사용
signal boss_phase_changed(phase: int)  # 호스트 emit(보스 페이즈 전이) — MobSync가 G_BOSS_PHASE 브로드캐스트, HUD가 배너. 게스트는 G_BOSS_PHASE 수신 시 로컬 emit(mob_telegraph→matk 미러)
signal coop_call(duration: float)      # 코옵 파훼 시전 시작 — HUD 프롬프트("함께 F!")·보스 cast 애니·아레나 텔레그래프. 호스트/게스트 각자 로컬 표시
signal coop_result(success: bool)      # 코옵 파훼 결과 — 배너/연출(성공=취소·그로기, 실패=폭발). 표시 전용, 정본 판정은 호스트

# --- stage flow (호스트=판정 시, 게스트=clear/wipe 수신 시 emit) ---
signal stage_cleared
signal stage_wiped

# --- feel (표시 전용 손맛 — 각 클라 로컬에서 emit·소비, 네트워크 아님) ---
# HP 감소 표시 경로(Health.hp_changed dropped=true)에서 피격 당사자 글루가 emit — 호스트/게스트
# 무관하게 각 클라가 자기 화면 연출(플래시·데미지 숫자·셰이크·SFX·히트스톱)을 재생한다.
# kind = "enemy"|"player" (누가 맞았나), world_pos = 피격 지점, amount = 감소량.
# crit = 이번 확정이 치명타였나 (표시 강조 전용 — 굴림은 호스트만, 표시 쪽에서 다시 굴리지 않는다 §3).
signal combat_impact(kind: String, world_pos: Vector2, amount: int, crit: bool)
signal screen_shake(strength: float)  # 명시적 셰이크 트리거 (사망·보스 슬램 등) — 카메라가 소비
# 방향성 카메라 반동 — 셰이크(무작위 진동)와 **다른 축**이다: 이쪽은 정해진 방향으로 밀렸다 복귀한다.
# 타격은 때린 방향으로, 발사는 그 반대로, 피격은 맞은 방향으로 민다 → "쫀득함"이 방향으로 읽힌다.
# 🔴 **로컬 아바타에서만 emit해라** — 카메라는 뷰포트를 잡은 로컬 인스턴스에만 붙어 있지만(enabled),
#   EventBus는 전역이라 원격 아바타가 emit하면 남이 맞을 때 내 화면이 밀린다(combat_impact가 이미
#   그런 상태라 셰이크는 남의 피격에도 난다 — 킥까지 따라가면 원인 모를 화면 흔들림이 된다).
signal camera_kick(dir: Vector2, strength: float)
# 소리/연출 트리거 (표시·소리 전용, 각 클라 로컬) — Audio가 SFX로, 필요시 연출이 구독.
signal player_swing(world_pos: Vector2, sfx: String)   # 플레이어 공격 스윙(로컬·원격 연출 시점) — sfx = 무기 스윙음 id(EquipDef.swing_sfx). ⚠ 발사(EquipDef.swing_sfx)·**차지 단계 상승(charge_sfx)**도 이 훅을 재사용한다 = "소리 낼 순간" 훅에 가깝다. 여기에 스윙 궤적 같은 **시각** 연출을 매달면 기 모을 때마다 검을 휘두른다 — 시각을 붙일 땐 sfx id로 갈라내거나 별도 시그널을 파라
signal player_roll(world_pos: Vector2)    # 플레이어 구르기 시작
# kind = "enemy"|"player" — 사망 확정 표시.
# 🔴 `respawns` = 그 적이 **되살아나는가**(EnemyDef.respawns — 훈련용 허수아비). 소리에는 무의미하지만
#   「광란」(kill_move)처럼 **처치를 보상하는 구독자**는 이걸 보고 걸러야 한다 — 안 그러면 부활하는
#   허수아비 앞에서 버프가 **상시 유지**된다(에러 없음). `exp_authority`가 무한 EXP 파밍을 코드로 막은
#   것과 같은 부류이고, rules §2가 "허수아비를 씬에 배치하기 전"의 선행 조건으로 걸어 둔 항목이다.
#   ⚠ 플레이어 사망은 항상 false(부활은 별도 경로 — 여기서 말하는 것은 적 데이터의 respawns다).
signal entity_died(kind: String, world_pos: Vector2, respawns: bool)

# 🔴 **개발 도구 전용** (2026-07-28) — 디버그 패널(src/ui)이 그 씬의 SceneFlow(src/net)에 스테이지 이동을
#   요청한다. 모듈 간 직접 참조 금지(rules §0) 때문에 EventBus를 지나는 것이지, 새 권한 경로가 아니다.
# 🔴 **신뢰 경계는 안 바뀐다** — 받는 쪽 `SceneFlow.request_stage`가 `Net.is_host()` + `_departed` +
#   `GameState.is_valid_stage`(챕터 스캔 allowlist) 가드를 **그대로** 지난다. 게스트가 눌러도 아무 일도
#   일어나지 않고, 없는 챕터를 주면 push_error로 끝난다. 네트워크 메시지도 새로 생기지 않는다(G_SCENE 재사용).
signal debug_stage_requested(chapter_id: String, idx: int)
# 내 무기가 적중(공격자 로컬 예측 — 호스트 확정 전 즉발). 무기별 타격 손맛: Audio가 sfx(비면 무음),
# 카메라가 shake. 범용 "피격" 연출(플래시·데미지 숫자·범용 히트음)은 combat_impact가 별도로 담당한다.
signal weapon_impact(world_pos: Vector2, sfx: String, shake: float)

# --- 드랍/인벤 (드랍·제작 2026-07-23) ---
signal enemy_killed(eid: String, def: EnemyDef, world_pos: Vector2)  # 호스트 전용 emit(CombatAuthority, hp<=0 확정) — DropAuthority가 드랍 롤 트리거
signal drop_spawn_local(drops: Array)  # DropAuthority(호스트) → DropField 로컬 스폰 (호스트는 자기 G_DROP를 못 받으므로)
signal drop_pick_local(did: String, pid: int)  # DropAuthority(호스트) → DropField 로컬 픽업 반영 (호스트는 자기 G_PICK_OK를 릴레이로 못 받음 — drop_spawn_local과 대칭)
signal inventory_changed  # 골드/재료/장비/도면 변동 (각 클라 로컬) — HUD·제작/강화 패널 갱신
signal blueprint_unlocked(recipe_id: String)  # 도면 획득 확정 — "설계도 획득!" 배너 연출·제작 가용 갱신
# feel (표시 전용 — 네트워크 아님, rules §2)
signal item_dropped(kind: String, rarity: int, world_pos: Vector2)  # 드랍 등장 연출(착지 팝·등급 반짝임)
signal item_picked(kind: String, rarity: int, world_pos: Vector2)   # 픽업 연출(흡수 팝)

# --- 직업 레벨 성장축 (2026-07-25, GDD v1.8) ---
# EXP 확정 권한 = 호스트 (§1). 게스트는 G_EXP 수신으로만 적립한다 — 각 클라가 킬을 세면
# 패킷 유실·씬 전환·관전 타이밍에 따라 레벨이 **조용히** 갈리고, 레벨은 스탯 공지의 근거라
# 그 발산이 곧 "게스트의 정당한 타격이 간헐 거부됨"으로 나타난다.
signal exp_granted_local(amount: int)  # ExpAuthority(호스트) → 자기 적립 경로 (호스트는 자기 G_EXP를 릴레이로 못 받는다 — drop_spawn_local 미러)
signal growth_changed  # 레벨/메인 하위 직업 변동 (GameState emit) — PeerSync 재공지(G_STATS "lv")·HUD·패널 갱신. ⚠ EXP만 오른 킬에는 emit하지 않는다(킬마다 재공지 = 불필요한 트래픽)
signal exp_changed(cur: int, need: int)  # 매 적립 (GameState emit) — HUD EXP 바 전용, 재공지를 유발하지 않는 가벼운 훅
signal sub_job_level_up(sub_id: String, level: int)  # 레벨업 확정 — HUD 토스트·레벨업음
signal sub_job_unlocked(sub_id: String)  # 다음 하위 직업 해금 (blueprint_unlocked 미러) — HUD 토스트·패널 갱신
