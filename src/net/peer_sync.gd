extends Node
# 피어/직업 동기화 공용 컴포넌트 — 마을·스테이지가 자식 노드로 문다 (rules §2 리팩터 게이트).
# 책임: 피어당 플레이어 스폰(부모 씬에 add_child)·G_POS 반영·G_JOB 공지/잠금·G_ATK 연출 중계.
# 권한·전투 확정은 여기 없다 — 그건 CombatAuthority(src/stage) 몫.
# ⚠ 씬 전용 글루(오토로드 전역 식별자 사용) — -s 헤드리스 테스트에서 preload 금지 (rules §5).

const NetSchema := preload("res://src/core/net_schema.gd")
const PlayerScene := preload("res://src/player/player.tscn")
const PlayerActor := preload("res://src/player/player.gd")

@export var scene_id: String = ""  # net_schema SCENE_* 중 하나 — G_POS 씬 필터의 기준
@export var spawn_base: Vector2 = Vector2(280.0, 180.0)
@export var spawn_gap: float = 80.0  # 피어별 가로 간격 (연출값)

var _players: Dictionary = {}  # peer_id -> PlayerActor
var _peer_jobs: Dictionary = {}  # peer_id -> 잠긴 직업 id — "시작 시 선택·이후 고정"(GDD §5) 강제
var _pos_seen: Dictionary = {}  # peer_id -> true — 첫 G_POS 수신 시 재공지 트리거 (공지 유실 경합 복구)
var _peer_stats: Dictionary = {}  # peer_id -> {atk, hp, weapon, lv, ms, ss} — 장비 스탯 + 레벨 5스탯 + 장착 하위 직업 id(메인 ms / 서브 ss) 공지(G_STATS). 스폰 전 도착 시 버퍼링(_peer_jobs 미러)


func _ready() -> void:
	EventBus.peer_joined.connect(_on_peer_joined)
	EventBus.peer_left.connect(_on_peer_left)
	EventBus.net_msg.connect(_on_net_msg)
	EventBus.inventory_changed.connect(_on_inventory_changed)  # 로컬 장비 변동 → 스탯 재공지+반영
	EventBus.job_change_requested.connect(_on_job_change_requested)  # 설정 "직업 변경" (마을 씬만 처리)
	# 레벨/메인 하위 직업 변동 → 같은 경로로 재공지 (성장축 GDD v1.8). EXP만 오른 킬에는 오지 않는다
	# (GameState.add_exp가 레벨 변동 시에만 emit) — 킬마다 G_STATS를 쏘지 않기 위한 분리.
	EventBus.growth_changed.connect(_on_inventory_changed)
	# ⚠ _ready 시점 부모는 아직 자식 셋업 중 — 여기서 get_parent().add_child 하면
	# "busy setting up children"으로 스폰이 조용히 실패한다 (웹 실기에서 확인) → 한 프레임 미룬다.
	_initial_spawn.call_deferred()


# 원격은 여기서 눈뜨자마자 스폰하지 않는다 — 같은 씬임을 증명하는 첫 G_POS 수신에서만 스폰.
# (다른 씬에 있는 피어를 즉시 스폰하면 pos를 영영 못 받는 유령 아바타가 된다 — 재접속/전환 창 케이스)
func _initial_spawn() -> void:
	_spawn(Net.my_id, true)
	_announce_job()
	_apply_local_stats()  # 로컬 장비 스탯 반영(max_hp) + 공지


# CombatAuthority 등 형제 컴포넌트용 조회 (없으면 null)
func player(peer_id: int) -> PlayerActor:
	return _players.get(peer_id) as PlayerActor


func has_player(peer_id: int) -> bool:
	return _players.has(peer_id)


# 그 피어가 G_STATS로 **공지한** 착용 무기 id (미공지면 ""). 호스트가 G_SHOOT의 무기 주장을 교차검증할 때 쓴다
# (rules §3 — 발사 메시지의 "w"를 그대로 믿으면 전사가 지팡이를 사칭해 차지 배율·폭발을 얻는다, 2026-07-24 리뷰).
# 공지 자체는 여전히 발신자 트러스트지만, 장비 스탯(atk/hp)과 **같은 한 장의 공지**로 묶여 표면이 늘지 않는다.
# 그 피어가 G_JOB으로 공지한(그리고 스테이지에선 첫 공지로 잠긴) 직업 id. 미공지면 "".
# 호스트가 공지 무기를 그 직업이 들 수 있는지 대조할 때 쓴다 (rules §3 — peer_weapon_id와 한 쌍).
func peer_job_id(peer_id: int) -> String:
	return str(_peer_jobs.get(peer_id, ""))


func peer_weapon_id(peer_id: int) -> String:
	var st_v: Variant = _peer_stats.get(peer_id)
	if st_v == null:
		return ""
	return str((st_v as Dictionary).get("weapon", ""))


# 그 피어가 G_STATS로 공지한(그리고 수신부가 clamp한) 레벨 5스탯. 미공지면 전부 0(항등 폴백).
# 호스트가 공속 검증(is_hit_cooldown_ok 등)에 쓴다 — **발신자 주장이 아니라 자기가 clamp한 값**을
# 게이트에 넣는 것이 규약이다(peer_weapon_id와 같은 철학, rules §3).
func peer_level_stats(peer_id: int) -> Dictionary:
	var st_v: Variant = _peer_stats.get(peer_id)
	if st_v == null:
		return CombatMath.empty_level_stats()
	var lv_v: Variant = (st_v as Dictionary).get("lv")
	if lv_v == null:
		return CombatMath.empty_level_stats()
	return lv_v as Dictionary


# 그 피어의 활성 특성 {reach, roll_cd, …}. 미공지/특성 없음 = 전부 0(항등).
# 🔴 공지된 것은 **id뿐**(메인 "ms" + 서브 "ss")이고 값은 내 data/subjobs에서 리졸브한다
#   (peer_weapon_id 철학 §3 — 수치를 받으면 그게 곧 스푸핑 표면이다).
#   계열은 그 피어가 G_JOB으로 공지한 직업 — 남의 계열 특성을 주장하면 traits_of가 폐기한다.
#   G_JOB이 아직 안 왔으면(계열 미상) 0 = 특성 꺼짐 쪽으로 떨어진다. 첫 G_POS 재공지가 곧 복구하고,
#   그때까지는 "정당한 특성을 잠깐 못 받는" 보수적 방향이라 안전하다(그 반대는 스푸핑 허용).
func peer_traits(peer_id: int) -> Dictionary:
	var st_v: Variant = _peer_stats.get(peer_id)
	if st_v == null:
		return CombatMath.empty_traits()
	var st := st_v as Dictionary
	return GameState.traits_of(
		str(st.get("ms", "")), st.get("ss", []) as Array, str(_peer_jobs.get(peer_id, "")))


# 그 피어의 궤적 아이덴티티 {color, ghost} — **표시 전용**(판정 무관). peer_traits의 미러다:
# 같은 공지("ms")·같은 계열 근거·같은 로컬 리졸브를 쓰고, 미공지/계열 미상이면 항등(흰색·1.0)으로
# 떨어진다. 🔴 새 네트워크 필드 0개 — 색을 payload에 실으면 남의 화면을 칠하는 권한이 생긴다(rules §3).
func peer_main_fx(peer_id: int) -> Dictionary:
	var st_v: Variant = _peer_stats.get(peer_id)
	if st_v == null:
		return GameState.main_fx_of("", "")
	var st := st_v as Dictionary
	return GameState.main_fx_of(str(st.get("ms", "")), str(_peer_jobs.get(peer_id, "")))


# 그 피어의 **하위 직업 스킬**(G_SKILL 확정용). 🔴 `peer_traits`/`peer_main_fx`의 정확한 미러다:
#   같은 공지("ms") · 같은 계열 근거(G_JOB) · 같은 로컬 리졸브(`GameState.main_skill_of` =
#   `main_slot_def` 게이트: 계열 일치 · 공유 하위 직업 배제 · 모르는 id 폐기).
# 🔴 **그런데 이쪽은 표시가 아니라 판정이다** — 호스트가 이 결과로 데미지 배율·반경·사거리·쿨다운을
#   정한다. 그래서 **메시지에는 수치가 한 칸도 안 실린다**(`peer_weapon_id` 철학, rules §3):
#   "안 낀 스킬을 쏘는 것"과 "남의 계열 스킬을 주장하는 것"이 이 한 함수에서 함께 막힌다.
# ⚠ 미공지·계열 미상(G_STATS가 G_JOB보다 먼저 도착한 창)이면 null = **발동이 조용히 거부**된다.
#   관대한 쪽이 아니라 안전한 쪽으로 떨어지는 것이고, `peer_traits`가 그 창에서 특성을 0으로 두는 것과
#   같은 방향이다. 창은 첫 G_POS 재공지(위 `_pos_seen`)·G_JOB 분기 재적용이 곧 닫는다.
func peer_skill(peer_id: int) -> SkillDef:
	var st_v: Variant = _peer_stats.get(peer_id)
	if st_v == null:
		return null
	var st := st_v as Dictionary
	return GameState.main_skill_of(str(st.get("ms", "")), str(_peer_jobs.get(peer_id, "")))


func _spawn(peer_id: int, is_local: bool) -> void:
	if peer_id == 0 or _players.has(peer_id):
		return
	var p := PlayerScene.instantiate() as PlayerActor
	get_parent().add_child(p)
	# 스폰 슬롯 = 방 내 순번(현재 인원). peer_id 기반이면 재접속마다 id가 증가해
	# (릴레이는 id 재사용 안 함) 몇 번 새로고침이면 뷰포트 밖에서 스폰된다.
	# 클라이언트마다 순번이 달라도 무해 — 원격 위치는 첫 G_POS 수신에서 실좌표로 스냅된다.
	p.setup(peer_id, is_local, spawn_base + Vector2(spawn_gap * float(_players.size()), 0.0), scene_id)
	if is_local:
		p.set_job(GameState.selected_job())
	else:
		# 스폰 전에 도착해 쌓인 공지 반영 — 없으면 기본(전사)으로 두고 G_JOB 수신 시 확정
		var jid := str(_peer_jobs.get(peer_id, ""))
		if not jid.is_empty():
			p.set_job(GameState.job_def(jid))
	# 스폰 전 도착한 스탯 공지 반영 (job 버퍼링 미러). 로컬은 _apply_local_stats가 따로 반영.
	if _peer_stats.has(peer_id):
		var st := _peer_stats[peer_id] as Dictionary
		p.set_equip_stats(int(st.get("atk", 0)), int(st.get("hp", 0)))
		p.set_level_stats(st.get("lv", {}) as Dictionary)  # 레벨 5스탯도 같은 버퍼에서(공짜)
		# 무기 겉모습(표시용) — id는 allowlist 리졸브(모르면 null→직업 기본 무기 폴백)
		p.set_weapon_visual(_remote_weapon_def(peer_id, str(st.get("weapon", ""))))
		p.set_traits(peer_traits(peer_id))  # 하위 직업 특성 — 같은 버퍼에서
		p.set_subjob_fx(peer_main_fx(peer_id))  # 궤적 아이덴티티(표시 전용) — 특성과 **항상 같이** 간다
	_players[peer_id] = p
	# 스폰 완료 공지 — 호스트가 챕터 이월 HP를 재확정하는 입구 (CombatAuthority). 잡 반영 뒤에 emit.
	EventBus.player_spawned.emit(peer_id, p)


# 직업 공지 — 내 직업 id를 방 전원에 브로드캐스트.
# 씬 입장 시 1회 + 새 피어 합류 시 재공지(늦게 온 피어도 기존 피어 직업을 알게).
func _announce_job() -> void:
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_JOB, "job": GameState.selected_job_id})


# 장비 총 스탯 공지 — 내 착용 장비 {attack, hp}를 방 전원에. 호스트가 데미지/HP 확정에 쓴다.
func _announce_stats() -> void:
	var s := GameState.current_stats()
	Net.send_game({NetSchema.KEY_KIND: NetSchema.G_STATS,
		"atk": int(s["attack"]), "hp": int(s["hp"]),
		"weapon": GameState.equipped_id(EquipDef.SLOT_WEAPON),  # 착용 무기 id (표시용, 원격 겉모습)
		"lv": GameState.current_level_stats(),  # 직업 레벨 5스탯 (호스트가 치명/피흡/공속 확정에 사용)
		# 장착 하위 직업 id — **수치가 아니라 id만** 보낸다(GDD v2.0 특성). 수신 측이 자기 data/subjobs에서
		# 리졸브해 특성값을 얻는다(peer_weapon_id 철학 §3 — 수치를 받으면 그게 곧 스푸핑 표면).
		# "ms" = 메인(메인 특성) · "ss" = 서브 칸(서브 특성). 자리가 곧 어느 특성이 켜지는지를 정한다.
		"ms": GameState.announced_main_id(),  # "ss"와 같은 소스(필터 통과분) — active_traits와 근거 통일
		"ss": GameState.announced_sub_ids()})  # 🔴 원본 슬롯이 아니라 **필터 통과분**(active_traits와 같은 소스)


# 로컬 장비 스탯을 내 플레이어에 반영(max_hp) + 공지. 스폰·인벤 변동 시.
func _apply_local_stats() -> void:
	var s := GameState.current_stats()
	var lp := player(Net.my_id)
	if lp != null:
		lp.set_equip_stats(int(s["attack"]), int(s["hp"]))
		lp.set_level_stats(GameState.current_level_stats())  # 내 레벨 스탯 반영(호스트면 자기 판정 입력)
		# 로컬 무기 겉모습 = 내가 착용한 무기 (미착용이면 null → 직업 기본)
		lp.set_weapon_visual(GameState.equip_def(GameState.equipped_id(EquipDef.SLOT_WEAPON)))
		# 🔴 내 특성은 _peer_stats가 아니라 GameState에서 온다 — **Net에 루프백이 없어 로컬 항목이
		#   아예 없다.** 성장축 리뷰 Critical(호스트 자기 공속이 게이트에 안 들어가 자기 타격이 걸러졌던 것)과
		#   같은 함정이라, 치명·피흡·공속과 소스를 통일해 둔다.
		lp.set_traits(GameState.active_traits())
		# 궤적 아이덴티티도 같은 소스에서 — 🔴 여기서 빠지면 **내 화면의 내 칼만** 색이 안 바뀌고
		#   상대 화면에서는 바뀐다(원격 경로는 G_STATS로 도달하므로). 위 특성과 같은 함정이다.
		lp.set_subjob_fx(GameState.active_main_fx())
	_announce_stats()


func _on_inventory_changed() -> void:
	_apply_local_stats()  # 픽업/제작/강화로 장비가 바뀌면 즉시 반영+재공지


# 직업 변경 (마을 씬만 — 전투 스테이지에선 스탯 취사선택 악용이 되므로 잠금 유지, GDD §5).
# 내 직업만 교체 → 로컬 반영 + 재공지(마을 잠금 해제 덕에 상대가 반영). 장비/골드는 그대로.
func _on_job_change_requested(job_id: String) -> void:
	if scene_id != NetSchema.SCENE_VILLAGE:
		return
	if not GameState.job_ids().has(job_id) or job_id == GameState.selected_job_id:
		return
	GameState.selected_job_id = job_id
	# 🔴 **직업 공지가 먼저다.** 아래 apply_job_loadout이 무기 해제·지급으로 G_STATS를 여러 번 쏘는데,
	#   G_JOB이 그보다 늦게 나가면 상대는 그 창 동안 "새 무기 + 옛 직업"으로 본다 — 고치려던 불일치의
	#   거울상이다(마을엔 전투가 없어 무해하지만, 순서를 맞춰 두는 값이 0이다).
	_announce_job()
	# 직업 전환 뒤처리 3종 — 마을 진입(main)과 **같은 한 줄**. 없으면 직업만 바뀌고 맨손으로 남고,
	# 메인 하위 직업이 옛 계열에 남아 메인 특성·5스탯이 통째로 꺼진다.
	GameState.apply_job_loadout()
	var lp := player(Net.my_id)
	if lp != null:
		lp.set_job(GameState.selected_job())
	_apply_local_stats()   # 무기 겉모습·max_hp 재반영 + G_STATS 재공지(최종 상태가 마지막에 이긴다)


func _on_peer_joined(_peer_id: int) -> void:
	_announce_job()  # 스폰은 안 한다 — 상대의 첫 G_POS(씬 일치)가 스폰 트리거
	_announce_stats()  # 늦게 온 피어도 내 장비 스탯을 알게 (G_JOB 재공지와 짝)


func _on_peer_left(peer_id: int) -> void:
	if _players.has(peer_id):
		_players[peer_id].queue_free()
		_players.erase(peer_id)
	_peer_jobs.erase(peer_id)  # 같은 id로 새 피어가 들어와도 이전 잠금이 남지 않게
	_pos_seen.erase(peer_id)
	_peer_stats.erase(peer_id)


func _on_net_msg(from_id: int, data: Dictionary) -> void:
	match str(data.get(NetSchema.KEY_KIND, "")):
		NetSchema.G_POS:
			if str(data.get("s", "")) != scene_id:
				return  # 다른 씬의 피어 (전환 창·재접속 대기) — 유령 스폰/좌표 오염 방지
			if not _players.has(from_id):
				_spawn(from_id, false)  # 첫 G_POS = 같은 씬 증명 — 여기가 원격 스폰의 유일한 입구
				if not _players.has(from_id):
					return  # 스폰 거부(peer_id 0 등) — 인덱싱 에러 방지
			_players[from_id].apply_remote_pos(
				Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0))),
				bool(data.get("f", false)),
				float(data.get("a", 0.0)),
				int(data.get("c", 0)),  # 차지 상태(법사 지팡이) — 표시 전용, 실제 발사 레벨은 G_SHOOT를 호스트가 재검증
				# 속도 — 호스트 지연 보상 외삽의 입력(§3). 수신부가 유한성·이동 상한으로 clamp한다
				Vector2(float(data.get("vx", 0.0)), float(data.get("vy", 0.0))),
				# 송신 시퀀스 — P2P fast 채널(unordered)의 순서 뒤바뀜을 수신부가 폐기하는 근거(§3).
				# 키가 없으면 0 = 항등 폴백(릴레이 경로·구버전 클라와 그대로 호환).
				int(data.get("n", 0)))
			if not _pos_seen.has(from_id):
				# 첫 G_POS = 상대가 같은 씬에서 듣고 있다는 증명 — 씬 전환 중 드랍된 공지를 재전송
				_pos_seen[from_id] = true
				_announce_job()
				_announce_stats()
		NetSchema.G_JOB:
			if _peer_jobs.has(from_id) and scene_id != NetSchema.SCENE_VILLAGE:
				return  # 스테이지: 첫 공지 잠금(스탯 취사선택 악용 차단, GDD §5). 마을: 직업 변경 허용
			# 신뢰 경계(rules §3): id 문자열만 받고 수치는 내 data/jobs에서 리졸브.
			# 모르는 id는 GameState가 기본 직업으로 떨어뜨린다. 이후 사거리·쿨다운 검증이 이 job 기준.
			# 아직 스폰 전이면 기록만 — _spawn이 반영한다 (G_JOB은 씬 무관 전역 공지라 스폰 트리거 아님).
			_peer_jobs[from_id] = str(data.get("job", ""))
			if _players.has(from_id):
				_players[from_id].set_job(GameState.job_def(str(data.get("job", ""))))
				# 🔴🔴 **계열이 늦게 확정되면 특성·궤적을 다시 적용해야 한다** (netreview 2026-08-01).
				#   `peer_traits`/`peer_main_fx`가 **둘 다 계열을 `_peer_jobs`에서 읽는다.** G_STATS가
				#   G_JOB보다 먼저 도착하면 그 순간 계열 미상이라 특성이 **전부 0으로 굳고**, 이 분기가
				#   재적용하지 않으면 **그 판 내내 복구되지 않는다** — 스테이지 안에서 G_STATS 재발화
				#   조건이 `inventory_changed`/`growth_changed`뿐이라 다음 재공지가 영영 안 올 수 있다.
				# 🔴 **도달 경로는 P2P다.** `Net.send_game`이 메시지마다 경로를 고르므로(직결 ~14ms vs
				#   릴레이 140~215ms), 씬 진입의 G_JOB이 릴레이로 나간 뒤 직결이 열리고 그다음
				#   `_apply_local_stats`가 G_STATS만 직결로 보내면 **순서가 뒤집힌다.** ⚠ `_pos_seen`
				#   재공지(위 G_POS 분기)는 두 줄이 **연속**이라 같은 경로로 나가 이 창을 안 만든다 —
				#   즉 복구가 그쪽에 걸려 있지 않다.
				# 🔴 증상 = **검성의 `reach`가 꺼진 채 호스트가 판정한다**(도달 54.6 → 42px) → 팁 타격이
				#   **무음 거부**된다. rules §2 *"G_STATS는 이제 판정 입력이라 놓치면 영구 결함"* 과 같은
				#   고장 모드이고, 스윙·궤적·소리가 다 정상이라 화면에 이유가 없다.
				# ⚠ **새 메시지·새 필드 0개다** — `_peer_stats`에 이미 버퍼된 값을 계열만 새로 얹어 다시
				#   리졸브할 뿐이다. 계열이 이미 맞았으면 같은 값이 나온다(항등 경로 불변).
				# ⚠ 🔵 이 결함은 궤적 아이덴티티 도입 **이전부터** 특성 축에 있었다. 다만 이제
				#   **흰 궤적**으로 화면에 드러난다(전에는 단서가 아예 없었다).
				_players[from_id].set_traits(peer_traits(from_id))
				_players[from_id].set_subjob_fx(peer_main_fx(from_id))
		NetSchema.G_STATS:
			# 장비 스탯 공지 — 발신자 트러스트(G_JOB과 동일 co-op 모델). 클램프 = 데이터 유도 현실 상한
			# (정직한 최강 장비는 통과, 임의 수 주입 차단 — 부풀린 hp가 모닥불 회복 천장으로 새는 것 방지).
			var cap := GameState.max_equip_stats()
			var atk := clampi(int(data.get("atk", 0)), 0, int(cap["attack"]))
			var hp := clampi(int(data.get("hp", 0)), 0, int(cap["hp"]))
			# 무기 id는 표시 전용 — allowlist 리졸브만 하면 안전(모르는 id→null→직업 기본, 경로 조작 불가)
			var wid := str(data.get("weapon", ""))
			# 레벨 5스탯 — atk/hp와 같은 규약(발신자 트러스트 + 데이터 유도 상한 clamp).
			# clamp_level_stats가 payload가 아니라 LEVEL_STAT_KEYS를 순회하므로 모르는 키는 자동 폐기되고
			# 빠진 키는 0으로 채워진다(하류 항등 폴백). Dictionary가 아닌 오염 페이로드도 여기서 걸린다.
			var lv_raw: Variant = data.get("lv", {})
			var lv := CombatMath.clamp_level_stats(
				(lv_raw as Dictionary) if lv_raw is Dictionary else {}, GameState.max_level_stats())
			# 하위 직업 id는 **문자열로 보관하고 리졸브는 조회 시점에** 한다(peer_traits).
			# 여기서 값으로 바꿔 두면 G_STATS가 G_JOB보다 먼저 도착한 순간 계열을 몰라 0으로 굳는다.
			# "ss"는 Array가 아니면 빈 배열로 — 오염 페이로드가 traits_of에 들어가지 않게(lv의 Dictionary 가드 미러).
			# 개수 초과분은 traits_of가 SUB_SLOT_COUNT에서 잘라낸다(특성 쌓기 차단).
			var ss_raw: Variant = data.get("ss", [])
			_peer_stats[from_id] = {"atk": atk, "hp": hp, "weapon": wid, "lv": lv,
				"ms": str(data.get("ms", "")),
				"ss": (ss_raw as Array) if ss_raw is Array else []}
			if _players.has(from_id):
				_players[from_id].set_equip_stats(atk, hp)
				_players[from_id].set_level_stats(lv)
				_players[from_id].set_weapon_visual(_remote_weapon_def(from_id, wid))
				_players[from_id].set_traits(peer_traits(from_id))  # 원격 특성 — 연출·판정 기하 공용
				_players[from_id].set_subjob_fx(peer_main_fx(from_id))  # 궤적 아이덴티티(표시 전용)
		NetSchema.G_ATK:
			if _players.has(from_id):
				var dir := Vector2(float(data.get("dx", 1.0)), float(data.get("dy", 0.0)))
				# "cb" = 그 피어의 콤보 타수. 🔴 **v2.2(2026-07-29)부터 표시 전용이 아니다** — 같은 타수가
				# 호스트에서 데미지 배율·마무리 각을 고른다(`combat_authority`의 G_ATK 분기가 **자기 수신
				# 간격으로 따로 센다** — 여기서 넘기는 값은 판정에 안 쓰인다).
				# ⚠ 그래서 이 경로는 여전히 "주장 그대로 그리기"이고, 그것이 계약이다: 호스트가
				# `min(주장, 자기 계수)`를 쓰므로 갈라짐이 항상 **표시 ⊇ 판정** 쪽으로만 떨어진다(§3).
				# 없으면 0 = 도입 전과 같은 첫 타 궤적. 범위 밖 값은 play_attack_fx가 clamp한다.
				_players[from_id].play_attack_fx(
					dir.normalized() if dir.length() > 0.001 else Vector2.RIGHT, int(data.get("cb", 0)))
		NetSchema.G_SHOOT:
			# 원격 궁수 발사 연출(활 반동) — 표시 전용. 화살 스폰은 ArrowField, 판정은 CombatAuthority(호스트)가 별도.
			if _players.has(from_id):
				_players[from_id].play_shoot_fx()
		NetSchema.G_ROLL:
			# 구르기 연출 중계 — 표시 전용. i-frame 판정은 CombatAuthority(호스트 그랜트)가 별도로 한다.
			if _players.has(from_id):
				_players[from_id].play_roll_fx(
					Vector2(float(data.get("dx", 0.0)), float(data.get("dy", 0.0))))
		NetSchema.G_SKILL:
			# 원격 하위 직업 스킬 연출 — 표시 전용(G_ROLL·G_ATK 중계와 같은 규약). 데미지 확정은
			# CombatAuthority(호스트)가 **같은 메시지를 따로 받아** 한다.
			# 🔴 **기하는 그 피어의 공지 하위 직업에서 리졸브한다**(`peer_skill`) — 메시지에는 방향뿐이라
			#   "남의 화면에 거대한 원을 그리는" 권한이 애초에 없다. 호스트 판정과 **같은 함수**를 지나므로
			#   내 화면의 원/띠 크기가 곧 호스트가 세우는 판정 기하다(§3 "맞는 곳 = 보이는 곳").
			# ⚠ null(미공지·계열 불일치·스킬 없음)이면 아무것도 안 그린다 — 호스트도 같은 게이트에서
			#   판정을 거부하므로 **표시와 판정이 함께** 없어진다(한쪽만 새지 않는다).
			if _players.has(from_id):
				var kdir := Vector2(float(data.get("dx", 1.0)), float(data.get("dy", 0.0)))
				_players[from_id].play_skill_fx(
					kdir.normalized() if kdir.length() > 0.001 else Vector2.RIGHT,
					peer_skill(from_id))


# 🔴 원격 피어의 무기 겉모습 — **호스트 판정과 같은 필터를 지난다**(`can_job_equip`, 2026-07-28
#   netreview I-3). 필터가 없으면 "궁수가 대검을 공지"한 상태에서 화면엔 ±109° 궤적이 그려지는데
#   호스트 판정은 무기를 폐기해 **직업 기본 + 전방위(360°)** 로 돌아간다 = **표시 ⊂ 판정**,
#   즉 "안 보이는데 맞는다"(§3 금지 방향)다.
# ⚠ 그 조합은 변조 클라만의 것이 아니다 — **정직한 클라가 상태 버그로 도달했던 부류**다
#   (2026-07-26 "전사로 들어왔는데 마법 지팡이를 쓴다" 신고. rules §3 직업 귀속).
# ⚠ 로컬(`_apply_local_stats`)은 `GameState.equipped_id`라 이미 착용 규칙을 지나므로 필터가 없다.
func _remote_weapon_def(peer_id: int, weapon_id: String) -> EquipDef:
	var e := GameState.equip_def(weapon_id)
	if not GameState.can_job_equip(peer_job_id(peer_id), e):
		return null  # 무장 해제 = 호스트가 판정에 쓰는 값(직업 기본 기하)과 일치시킨다
	return e
