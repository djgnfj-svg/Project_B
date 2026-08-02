extends Node
# 런타임 진행 상태 오토로드 (projectb-rules §1) — 지금은 직업 선택만.
# 장비/인벤토리/재료·챕터 해금·파티는 해당 시스템 구현 때 여기로 확장한다.
# id→Resource 리졸버는 장차 Db 오토로드 몫 — Db 도입 시 이관 (rules §1).

const DEFAULT_JOB_ID := "warrior"
const DEFAULT_CHAPTER_ID := "chapter1"  # 챕터 해금/선택 시스템 전까지의 출발 챕터 (GDD §6 — 방장 해금 기준은 후속)

# 시작 시 선택, 이후 고정 (GDD §5). 로비에서 정하고 스테이지가 읽는다.
# 🔴 setter로 **직업 귀속 재검증**을 건다 (revalidate_equipped) — `can_equip_job`은 equip() 시점에만
#   걸리므로, 직업이 **나중에** 바뀌는 경로(로비 재선택·마을 직업 변경·세이브 로드)에서 남의 직업 무기가
#   착용된 채 남는다. 대입 지점이 여럿(lobby·peer_sync·테스트)이라 호출 규약으로는 반드시 새는 자리다.
#   ⚠ setter 본문 안의 대입은 setter를 다시 부르지 않는다(Godot 4 — 무한 재귀 없음).
var selected_job_id: String = DEFAULT_JOB_ID:
	set(value):
		if value == selected_job_id:
			return
		selected_job_id = value
		revalidate_equipped()

# 챕터 진행 좌표 — 쓰기는 scene_flow(G_SCENE 검증 통과)만, 읽기는 main·HUD·chapter_flow·씬 토큰.
var current_chapter_id: String = ""
var current_stage_idx: int = -1

var _job_ids: Array[String] = []  # data/jobs/ 스캔 캐시
var _chapter_ids: Array[String] = []  # data/chapters/ 스캔 캐시
var _material_ids: Array[String] = []    # data/materials/ 스캔 캐시
var _equipment_ids: Array[String] = []   # data/equipment/ 스캔 캐시
var _recipe_ids: Array[String] = []      # data/recipes/ 스캔 캐시
# 「도굴」(drop_find) 소수 잔량 — kind -> float. **호스트만 쓴다**(DropAuthority가 읽고 쓴다).
# 🔴 여기 두는 이유: DropAuthority는 씬 컴포넌트라 스테이지마다 새로 태어나 잔량이 버려진다.
#   드랍 수량이 1~2라 잔량 1개분 손실이 곧 +15%를 ~+8%로 깎는다(리뷰 M-2). 판 단위로 들고 가야
#   비율이 약속대로 나온다. **저장 대상 아님** — 런타임 진행 상태다(carried_party_hp와 같은 성격).
var drop_find_frac: Dictionary = {}
var _party_hp: Dictionary = {}  # peer_id -> 확정 HP — 챕터 내 스테이지 간 이월 (php 확정만 기록, player.gd 확정 경로가 쓴다)

# --- 인벤토리/장비 (드랍·제작 2026-07-23) — 각 클라 자기 것만, 브라우저 로컬 저장(개인·비네트워크, GDD §3) ---
var gold: int = 0
var materials: Dictionary = {}            # mat_id(String) -> qty(int)
var unlocked_blueprints: Dictionary = {}  # recipe_id(String) -> true
var owned_equipment: Dictionary = {}      # equip_id(String) -> level(int, 0=미강화)
var equipped: Dictionary = {}             # slot(int, EquipDef.SLOT_*) -> equip_id(String)

# --- 창고 (개인·로컬, 비네트워크 — 마을 보관함, GDD §3·§6 사용자 확정: 공유 아님) ---
# 인벤과 대칭 컨테이너다. 넣기/빼기는 로컬 GameState 조작뿐(네트워크 0개) — 저장은 인벤과 함께 IndexedDB.
# 창고 장비는 착용 불가(예치 시 해제) — 장착은 가방(owned_equipment)에서만.
var storage_gold: int = 0
var storage_materials: Dictionary = {}    # mat_id(String) -> qty(int)
var storage_equipment: Dictionary = {}    # equip_id(String) -> level(int)

# --- 직업 레벨 성장축 (2026-07-25, GDD v1.8) + 조립 축 (2026-07-26, GDD v2.0) ---
# 각 클라 자기 것(비네트워크), 저장 대상. 계열(selected_job_id) 안의 하위 직업들이 5스탯을 담당한다.
# 🔴 v2.0: 효과는 **보유 전부**가 아니라 **장착한 3칸**(메인 1 + 서브 2)에서만 나온다 (GDD §5).
#   보유는 계속 늘고 EXP도 보유 전부에 적립되지만, 안 낀 것은 꺼져 있다("지금 안 쓰는 것").
#   총 화력 예산이 보유 개수가 아니라 **슬롯 수**에 묶이면서 하위 직업 추가 시 재역산이 사라졌다.
const SUB_SLOT_COUNT := 2          # 서브 슬롯 칸 수 — 늘리면 max_level_stats 상한이 함께 커진다(예산 재역산 1회 필요)
var main_sub_job_id: String = ""   # 메인(활성) 하위 직업 — 마을에서만 변경 (GDD §5). 공유는 못 온다
var sub_slot_ids: Array[String] = ["", ""]  # 서브 슬롯 — 빈 문자열 = 빈 칸. 계열/공유 둘 다 가능
# 🔴 **레벨은 저장하지 않는다 — EXP에서 파생한다**(CombatMath.level_for_exp). 둘을 다 들고 있으면
#   어긋난 상태가 생기고, 레벨은 G_STATS 스탯 공지의 근거라 어긋남이 곧 클라 간 스탯 발산이다.
var sub_job_exp: Dictionary = {}   # sub_id(String) -> 누적 EXP(int). **키의 존재 = 보유(해금됨)**
var _sub_job_ids: Array[String] = []      # data/subjobs/ 스캔 캐시
var _sub_job_cache: Dictionary = {}       # id -> SubJobDef (_equip_cache와 같은 이유 — 반복 .tres 재파싱 방지)


# 직업 id 목록 — data/jobs/*.tres 파일명에서 유도. 하드코딩 금지: "새 직업 = 파일 한 장" (rules §4).
# 익스포트 pck에선 .tres가 .remap(바이너리 변환 리맵)으로 보일 수 있어 접미사를 벗겨 판별한다.
func job_ids() -> Array[String]:
	if _job_ids.is_empty():
		for f: String in DirAccess.get_files_at("res://data/jobs"):
			var base := f.trim_suffix(".remap")
			if base.get_extension() == "tres" or base.get_extension() == "res":
				_job_ids.append(base.get_basename())
		if _job_ids.is_empty():
			push_error("[GameState] data/jobs 스캔 실패 — 기본 직업만 사용")
			_job_ids.append(DEFAULT_JOB_ID)
	return _job_ids


# id → JobDef 리졸버. 네트워크로 받은 id도 여길 지나므로(신뢰 경계),
# 스캔된 allowlist 밖 id는 기본 직업으로 떨어뜨린다 — 임의 문자열로 load 경로를 조작할 수 없다.
func job_def(id: String) -> JobDef:
	if id not in job_ids():
		if not id.is_empty():
			push_warning("[GameState] 모르는 직업 id '%s' — 기본 직업으로 폴백" % id)
		return load("res://data/jobs/%s.tres" % DEFAULT_JOB_ID) as JobDef
	return load("res://data/jobs/%s.tres" % id) as JobDef


func selected_job() -> JobDef:
	return job_def(selected_job_id)


# 🔴 "준비중" 게이트 단일 소스 (데모용 2026-07-29) — **플레이어가 고르는 UI 전부**가 이 함수를 지난다
#   (로비 직업 선택 · 설정 패널 「직업 변경」). 판정 규칙을 UI마다 복사하면 한쪽만 풀렸을 때
#   "로비에선 못 고르는데 마을에서 바꿔진다"가 된다 — 잠금은 새는 순간 의미가 없다.
# ⚠ 신뢰 경계가 아니다 — 호스트 판정·네트워크 공지는 도입 전과 완전히 같다(`job_ids()` allowlist 그대로).
#   `?debug=1` F1 패널은 **의도적으로** 이 게이트를 안 지난다(궁수·법사 개발·실기 확인용).
func is_job_playable(id: String) -> bool:
	if id not in job_ids():
		return false
	var j := job_def(id)
	return j != null and not j.coming_soon


# 플레이어가 고를 수 있는 직업 — 준비중 제외. 전부 준비중이면 기본 직업만이라도 돌려준다
# (데이터를 잘못 채워 선택지가 0개가 되면 로비에서 아무것도 못 고르고 게임이 시작조차 안 된다).
func playable_job_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in job_ids():
		if is_job_playable(id):
			out.append(id)
	if out.is_empty():
		push_error("[GameState] 고를 수 있는 직업이 0개 — coming_soon 데이터 확인. 기본 직업으로 폴백")
		out.append(DEFAULT_JOB_ID)
	return out


# --- 챕터 진행 (챕터1 골격 2026-07-22) ---

# 챕터 id 목록 — data/chapters/*.tres 스캔. job_ids와 같은 allowlist 규약 (rules §4).
func chapter_ids() -> Array[String]:
	if _chapter_ids.is_empty():
		for f: String in DirAccess.get_files_at("res://data/chapters"):
			var base := f.trim_suffix(".remap")
			if base.get_extension() == "tres" or base.get_extension() == "res":
				_chapter_ids.append(base.get_basename())
		if _chapter_ids.is_empty():
			push_error("[GameState] data/chapters 스캔 실패 — 기본 챕터만 사용")
			_chapter_ids.append(DEFAULT_CHAPTER_ID)
	return _chapter_ids


# id → ChapterDef 리졸버. 네트워크로 받은 챕터 id도 여길 지난다(신뢰 경계) —
# allowlist 밖 id는 기본 챕터로 폴백, 임의 문자열로 load 경로를 조작할 수 없다.
func chapter_def(id: String) -> ChapterDef:
	if id not in chapter_ids():
		if not id.is_empty():
			push_warning("[GameState] 모르는 챕터 id '%s' — 기본 챕터로 폴백" % id)
		return load("res://data/chapters/%s.tres" % DEFAULT_CHAPTER_ID) as ChapterDef
	return load("res://data/chapters/%s.tres" % id) as ChapterDef


# G_SCENE 스테이지 지시의 검증 단일 소스 — 호스트 송신 전·게스트 수신 시 둘 다 이걸 지난다.
func is_valid_stage(chapter_id: String, idx: int) -> bool:
	if chapter_id not in chapter_ids():
		return false
	var ch := chapter_def(chapter_id)
	return ch != null and ch.is_valid_index(idx)  # null 가드 — 깨진 익스포트에서 스캔은 되고 로드가 실패하는 케이스


func begin_stage(chapter_id: String, idx: int) -> void:
	current_chapter_id = chapter_id
	current_stage_idx = idx


# 마을/로비 복귀 — 챕터 좌표와 이월 HP를 함께 리셋 (마을 = 풀피 거점).
func leave_chapter() -> void:
	current_chapter_id = ""
	current_stage_idx = -1
	_party_hp.clear()
	drop_find_frac.clear()  # 「도굴」 잔량은 판(챕터) 단위 — 마을로 나오면 리셋


func in_chapter() -> bool:
	return not current_chapter_id.is_empty()


func stage_scene_path() -> String:
	if not in_chapter():
		return ""
	return chapter_def(current_chapter_id).stage_scenes[current_stage_idx]


# PeerSync 씬 토큰 — 같은 tscn(모닥불 등)이 챕터 내 여러 칸에 재사용돼도 칸마다 다른 토큰이
# 되도록 좌표를 박는다. 다른 칸 피어의 G_POS 유령 스폰 방지 (peer_sync 규약).
func stage_token() -> String:
	return "stage:%s:%d" % [current_chapter_id, current_stage_idx]


func is_last_stage() -> bool:
	return in_chapter() and current_stage_idx == chapter_def(current_chapter_id).stage_count() - 1


# HUD 진행 표기 — 마을(비챕터)은 빈 문자열
func progress_label() -> String:
	if not in_chapter():
		return ""
	var ch := chapter_def(current_chapter_id)
	if ch.is_rest(current_stage_idx):
		return "%s · 모닥불" % ch.display_name
	return "%s · 스테이지 %d/%d" % [
		ch.display_name, ch.combat_ordinal(current_stage_idx), ch.combat_total()]


# --- 파티 HP 이월 (스테이지 간 — GDD §4 한 호흡 진행, 모닥불 회복이 의미를 갖는 전제) ---

# 확정 HP 기록 — player.gd의 두 확정 경로(권한/php 수신)만 부른다. 모든 클라가 각자 기록하지만
# 스폰 시 재확정은 호스트만 한다(CombatAuthority) — 게스트 기록은 표시·폴백용.
func record_party_hp(peer_id: int, hp: int) -> void:
	_party_hp[peer_id] = hp


# 이월 HP 조회 — 기록 없으면 -1 (챕터 첫 판 = 풀피 유지)
func carried_hp(peer_id: int) -> int:
	return int(_party_hp.get(peer_id, -1))


# 피어 이탈 시 잔류 기록 정리 (릴레이 id는 재사용되지 않지만 챕터 내 누적 방지)
func drop_party_hp(peer_id: int) -> void:
	_party_hp.erase(peer_id)


# --- data 리졸버 (materials·equipment·recipes) — job/chapter와 같은 스캔 allowlist 규약 (rules §4) ---
# 네트워크로 받은 id(드랍·픽업)도 여길 지난다(신뢰 경계) — allowlist 밖 id는 폐기(null/무시).

func _scan_ids(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f: String in DirAccess.get_files_at(dir):
		var base := f.trim_suffix(".remap")
		if base.get_extension() == "tres" or base.get_extension() == "res":
			out.append(base.get_basename())
	return out


func material_ids() -> Array[String]:
	if _material_ids.is_empty():
		_material_ids = _scan_ids("res://data/materials")
	return _material_ids


func material_def(id: String) -> MaterialDef:
	if id not in material_ids():
		return null
	return load("res://data/materials/%s.tres" % id) as MaterialDef


func equipment_ids() -> Array[String]:
	if _equipment_ids.is_empty():
		_equipment_ids = _scan_ids("res://data/equipment")
	return _equipment_ids


# ⚠ 캐시 필수(2026-07-24 리뷰): 투사체 파라미터 리졸브가 **발사마다** 이 함수를 탄다
# (표시 스폰 + 호스트 등록 = 샷당 2회 이상, 궁수 연사 0.15s면 클라당 ~13회/s). 캐시가 없으면
# 반환 EquipDef의 refcount가 0으로 떨어져 매번 .tres 재파싱 → WASM에서 "쏘는 순간" 프레임 히치.
# allowlist(equipment_ids) 통과분만 담으므로 조작 id가 캐시에 들어오지 못한다.
var _equip_cache: Dictionary = {}  # id -> EquipDef


func equip_def(id: String) -> EquipDef:
	if _equip_cache.has(id):
		return _equip_cache[id] as EquipDef
	if id not in equipment_ids():
		return null
	var e := load("res://data/equipment/%s.tres" % id) as EquipDef
	if e != null:
		_equip_cache[id] = e
	return e


# 🔴 **G_STATS 미도착 창(폴백)에서 호스트가 쓸 「그 직업이 낼 수 있는 가장 긴 근접 무기」**
#   (netreview 2026-08-02 I-3). 전엔 폴백이 `melee_weapon = null` → **직업 기본 사거리**였는데,
#   그 창에는 무기뿐 아니라 **reach 특성도 모른다**(`wid`와 `ms`/`ss`가 같은 G_STATS 메시지다).
#   그래서 호스트 수용이 `기본 × 1 × SLACK`으로 고정되는데 로컬은 `무기 도달 × (1+reach)`까지
#   뻗어 **정당한 팁 타격이 무음 거부**됐다 — 창 + 검성이 실측 20px 띠였고 **스테이지 전환마다**
#   재발했다(창은 콤보가 필요 없어 전환 직후 첫 스윙에 바로 닿는다).
# 🔵 **신뢰 표면은 안 넓어진다** — 이 폴백이 여는 최대 수용(창 80 → 240px)은 변조 게스트가
#   `long_spear`를 **공지**해서 이미 얻을 수 있는 값과 **정확히 같다**(§2 G_STATS 게이트에 등재된
#   기존 표면). 즉 새 상한이 아니라 **이미 열려 있는 상한을 정직한 클라에게도 그 창에서만 허용**하는
#   것이고, 부호는 §3 「정직한 플레이어의 행동이 살아남는 쪽」이다.
# ⚠ 발사형은 제외한다 — 근접 판정의 폴백이라 `is_projectile_weapon`이 참인 것을 섞으면 안 된다.
#   기준 함수는 호스트 근접 거부 게이트와 **같은 것**을 쓴다(사본 금지).
var _widest_melee_cache: Dictionary = {}  # job_id -> EquipDef (또는 null)


func widest_melee_for_job(job_id: String) -> EquipDef:
	if _widest_melee_cache.has(job_id):
		return _widest_melee_cache[job_id] as EquipDef
	var jd := job_def(job_id)
	var best: EquipDef = null
	# 🔴🔴 **바닥은 「직업 기본」이다 — 못 이기면 null을 돌려 옛 폴백과 항등으로 떨어진다**
	#   (netreview N-1 ②). 안 두면 `melee_range`가 직업 기본보다 **짧은** 무기(도끼 38 < 전사 42)가
	#   유일 후보일 때 폴백이 **더 좁아진다** = 고치려던 것을 반대로 만든다.
	var best_reach: float = jd.attack_range if jd != null else 0.0
	for eid: String in equipment_ids():
		var e := equip_def(eid)
		if e == null or e.slot() != EquipDef.SLOT_WEAPON:
			continue
		if not can_job_equip(job_id, e) or CombatMath.is_projectile_weapon(e):
			continue
		# 🔴🔴 **선택 지표는 소비 지점과 「같은 함수」여야 한다** (netreview N-1 ①). 전엔
		#   `maxf(melee_range, combo_finish_range)`로 골랐는데 **소비는 `melee_range`만 읽었다**
		#   (폴백은 `melee_weapon == null`이라 `is_finish`가 false로 떨어진다) — 즉
		#   `combo_finish_range`로만 긴 무기는 폴백에 **1px도 기여하지 못했다.** 오늘은 창(80)이
		#   양쪽에서 이겨 마스킹됐고, **테스트도 같은 잘못된 지표를 미러해 초록이었다**(코드와
		#   테스트가 같은 모델을 공유하면 검출력이 0이다).
		#   ⚠ 짝으로 `combat_authority`가 폴백일 때 `is_finish = true`를 넘긴다 — 지표가 마무리
		#   도달로 고른 무기를 소비도 마무리 기준으로 읽어야 둘이 같은 값이 된다.
		if jd == null:
			continue
		var r := CombatMath.effective_attack_range(jd, 0.0, e, true)
		if r > best_reach:
			best_reach = r
			best = e
	_widest_melee_cache[job_id] = best
	return best


func recipe_ids() -> Array[String]:
	if _recipe_ids.is_empty():
		_recipe_ids = _scan_ids("res://data/recipes")
	return _recipe_ids


func recipe_def(id: String) -> RecipeDef:
	if id not in recipe_ids():
		return null
	return load("res://data/recipes/%s.tres" % id) as RecipeDef


# --- 인벤토리 조작 (각 클라 로컬) — 변동 시 inventory_changed emit. EventBus는 /root로(rules §5 -s 함정) ---

func _bus() -> EventBusHub:
	if not is_inside_tree():
		return null  # -s 테스트(트리 밖)는 /root 절대경로 조회가 에러 — 오토로드는 항상 트리 안 (rules §5)
	return get_node_or_null("/root/EventBus") as EventBusHub


# 공유 하위 직업 해금을 스테이지 클리어에 매단다 (GDD v2.0 §6 — 보스/챕터 클리어로 연다).
# 🔴 **여기서 연결하는 이유 = 저장 순서다.** SaveManager도 stage_cleared에 commit을 물려 두는데,
#   Godot은 연결 순서대로 호출하고 오토로드 순서가 GameState(21행) → SaveManager(22행)라
#   이 연결이 먼저 등록된다 → **해금이 그 판 저장에 포함된다.** 반대로 씬 컴포넌트에서 연결하면
#   commit이 먼저 돌아 해금이 다음 클리어까지 저장되지 않는다(전멸하면 조용히 사라진다).
# 🔴 호스트 가드가 없는 것도 의도다 — stage_cleared는 호스트 판정과 게스트 G_STAGE_CLEAR 수신
#   양쪽에서 발화하므로 **각 클라가 자기 진행에 로컬로 해금**한다(EXP와 달리 새 메시지가 필요 없다).
func _ready() -> void:
	var b := _bus()
	if b != null:
		b.stage_cleared.connect(_on_stage_cleared)


func _on_stage_cleared() -> void:
	if is_last_stage():  # 마지막 칸 = 보스 (ChapterDef 관례, rules §4)
		unlock_shared_sub_jobs()


func _notify_inventory() -> void:
	var b := _bus()
	if b != null:
		b.inventory_changed.emit()


func add_gold(amount: int) -> void:
	gold = maxi(0, gold + amount)
	_notify_inventory()


func spend_gold(amount: int) -> bool:
	if gold < amount:
		return false
	gold -= amount
	_notify_inventory()
	return true


func material_count(id: String) -> int:
	return int(materials.get(id, 0))


func add_material(id: String, qty: int) -> void:
	if id not in material_ids():  # allowlist — 모르는 재료 폐기 (신뢰 경계)
		push_warning("[GameState] 모르는 재료 id '%s' 드랍 — 폐기" % id)
		return
	materials[id] = material_count(id) + qty
	_notify_inventory()


func has_materials(costs: Dictionary) -> bool:
	for id: String in costs:
		if material_count(id) < int(costs[id]):
			return false
	return true


func _spend_materials(costs: Dictionary) -> void:
	for id: String in costs:
		materials[id] = maxi(0, material_count(id) - int(costs[id]))


func has_blueprint(recipe_id: String) -> bool:
	var r := recipe_def(recipe_id)
	if r != null and r.unlocked_by_default:  # 튜토 제작템은 도면 없이도 제작 가능
		return true
	return unlocked_blueprints.has(recipe_id)


func unlock_blueprint(recipe_id: String) -> void:
	if recipe_id not in recipe_ids():  # allowlist
		push_warning("[GameState] 모르는 도면 id '%s' 드랍 — 폐기" % recipe_id)
		return
	if not unlocked_blueprints.has(recipe_id):
		unlocked_blueprints[recipe_id] = true
		var b := _bus()
		if b != null:
			b.blueprint_unlocked.emit(recipe_id)
	_notify_inventory()


# 드랍 픽업 확정 라우팅 — 호스트가 선착 확정한 뒤, 주운 클라가 자기 인벤에 반영한다.
func collect_drop(kind: String, ref_id: String, qty: int) -> void:
	match kind:
		"gold":
			add_gold(qty)
		"material":
			add_material(ref_id, qty)
		"blueprint":
			unlock_blueprint(ref_id)
		_:
			push_warning("[GameState] 모르는 드랍 kind '%s'" % kind)


# --- 제작·강화 (마을 로컬 — 네트워크 0개, 각 클라 자기 인벤) ---

func can_craft(recipe_id: String) -> bool:
	var r := recipe_def(recipe_id)
	if r == null or not has_blueprint(recipe_id):
		return false
	# 직업 귀속 — 다른 직업 무기는 제작 불가(재료만 태우고 못 쓰는 걸 차단). equip()과 같은 규칙(can_equip_job).
	if not can_equip_job(equip_def(r.result_equip_id)):
		return false
	# 이미 보유(가방/창고)한 장비는 재제작 불가 — 장비는 id당 1개(중복 제작이 재료만 태우는 걸 차단).
	if owned_equipment.has(r.result_equip_id) or storage_equipment.has(r.result_equip_id):
		return false
	return gold >= r.gold_cost and has_materials(r.material_costs)


func craft(recipe_id: String) -> bool:
	if not can_craft(recipe_id):
		return false
	var r := recipe_def(recipe_id)
	gold -= r.gold_cost
	_spend_materials(r.material_costs)
	add_equipment(r.result_equip_id)
	# 슬롯이 비어 있으면 자동 장착 — 첫 제작이 바로 효과나게 (QoL). 재장착은 패널에서.
	# ⚠ 반드시 가방 보유(owned) 확인 — 창고에만 있는 아이템에 equipped를 물리면 음수 레벨 스탯이 된다(방어).
	# ⚠ 직접 대입이 아니라 equip()으로 — 직업 귀속 검사(can_equip_job)를 우회하는 두 번째 입구를
	#   만들지 않는다. 지금은 can_craft가 같은 검사를 이미 하지만, 그 검사가 바뀌면 조용히 샌다.
	var e := equip_def(r.result_equip_id)
	if e != null and equipped_id(e.slot()).is_empty():
		equip(r.result_equip_id)  # 가방 보유(owned) 확인은 equip()의 equip_level < 0 게이트가 한다
	_notify_inventory()
	return true


func add_equipment(equip_id: String) -> void:
	if equip_id not in equipment_ids():  # allowlist
		push_warning("[GameState] 모르는 장비 id '%s'" % equip_id)
		return
	# 가방·창고 어디에도 없을 때만 신규 생성 — 장비는 id당 1개(중복 생성 방지, 창고 대칭 도입).
	if not owned_equipment.has(equip_id) and not storage_equipment.has(equip_id):
		owned_equipment[equip_id] = 0  # 레벨 0 = 미강화
	_notify_inventory()


func equip_level(equip_id: String) -> int:
	return int(owned_equipment.get(equip_id, -1))  # -1 = 미보유


func can_upgrade(equip_id: String) -> bool:
	var lv := equip_level(equip_id)
	if lv < 0:
		return false
	var e := equip_def(equip_id)
	if e == null or lv >= e.max_level:
		return false
	return gold >= CombatMath.upgrade_cost(e, lv)


func upgrade_equipment(equip_id: String) -> bool:
	if not can_upgrade(equip_id):
		return false
	var e := equip_def(equip_id)
	gold -= CombatMath.upgrade_cost(e, equip_level(equip_id))
	owned_equipment[equip_id] += 1
	_notify_inventory()
	return true


# 직업 귀속 판정 단일 소스 — 무기 job_id가 비면 범용, 아니면 그 직업과 일치해야 착용/제작 가능.
# equip()·can_craft()·revalidate_equipped()가 같은 규칙을 쓴다(전사가 활 못 듦). 방어구는 보통 job_id 비움 = 범용.
# 🔴 **호스트의 판정 리졸브도 이 함수를 지난다** — `combat_authority`가 G_STATS로 공지된 무기를 그 피어의
#   공지 직업과 대조할 때(rules §3 투사체 계약). 그래서 직업 인자를 받는 형태가 원본이고, 로컬용은
#   `selected_job_id`를 넣는 얇은 래퍼다. 호스트에 사본 조건문을 두면 다음 튜닝에서 갈라진다.
func can_job_equip(job_id: String, e: EquipDef) -> bool:
	return e != null and (e.job_id.is_empty() or e.job_id == job_id)


func can_equip_job(e: EquipDef) -> bool:
	return can_job_equip(selected_job_id, e)


func equip(equip_id: String) -> void:
	if equip_level(equip_id) < 0:
		return
	var e := equip_def(equip_id)
	if e == null or not can_equip_job(e):
		return  # 직업 귀속 위반 = 착용 거부 (전사가 활 등)
	equipped[e.slot()] = equip_id
	_notify_inventory()


func equipped_id(slot: int) -> String:
	return str(equipped.get(slot, ""))


# 🔴 직업 귀속 재검증 — 현재 직업이 들 수 없는 착용 장비를 해제한다(장비 자체는 가방에 그대로 남는다).
# **직업이 바뀌는 모든 경로의 뒤처리 단일 소스**: selected_job_id setter + 세이브 로드(from_save_dict).
# 없으면 "전사인데 마법 지팡이"가 된다 — 겉모습만이 아니다. G_STATS "weapon"이 그 무기를 공지하고
# 호스트가 `peer_weapon_id`로 판정을 리졸브하므로(rules §3) **전사가 실제로 차지 폭발을 쓴다**.
# 에러가 안 나고 화면에만 드러나는 부류라 실기 신고로만 발견됐다 (2026-07-26).
# 반환 = 실제로 해제된 것이 있는지(호출부 로깅·테스트용).
# 🔴 **판 도중엔 돌지 않는다 — `autofill_sub_slots`의 in_chapter 가드와 같은 이유이고 더 세다.**
#   해제는 내 판정 무기와 atk를 즉시 바꾸는데 상대 호스트의 원격 아바타는 G_STATS 도달 뒤에야 바뀐다 →
#   그 창에서 타격이 **무음 거부**된다. 오늘은 호출부(로비 씬·마을 전용 가드)가 막지만, 가드가
#   호출부에 흩어져 있으면 다음 사람이 스테이지에서 직업을 대입하는 순간 전투 중에 무기가 사라진다.
func revalidate_equipped() -> bool:
	if in_chapter():
		push_error("[GameState] 판 도중 직업 귀속 재검증 시도 — 무시 (마을/로비에서만)")
		return false
	var drop: Array[int] = []
	for slot: int in equipped:
		if not can_equip_job(equip_def(str(equipped[slot]))):
			drop.append(slot)
	if drop.is_empty():
		return false
	for slot: int in drop:
		equipped.erase(slot)
	_notify_inventory()
	return true


# 장착 해제 — 그 슬롯을 비운다(장비는 이미 가방(owned)에 있으므로 슬롯만 지우면 됨).
func unequip(slot: int) -> void:
	if equipped.has(slot):
		equipped.erase(slot)
		_notify_inventory()


# 🔴 직업 전환 뒤처리 **단일 소스** (2026-07-26 리뷰 I-2) — 직업이 확정되는 자리는 이 한 줄만 부른다.
# 세 동작이 늘 같이 가야 한다: 남의 직업 무기 해제 → 내 직업 시작 무기 지급/착용 → 시작 하위 직업 지급.
# 하나라도 빠지면 조용히 깨진다 — 해제만 하면 맨손, 지급만 하면 "전사가 지팡이"(이번 신고), 하위 직업을
# 빼면 메인이 옛 계열에 남아 메인 특성·5스탯이 통째로 꺼진다. 세 줄을 호출부마다 손으로 맞춰 들고 있으면
# 네 번째 자리에서 반드시 빠진다(rules §2 "권한·동기화 로직은 복사 금지"와 같은 이유).
# ⚠ 인자를 받지 않는다 — `selected_job_id`(revalidate가 보는 값)와 job 인자가 어긋날 여지를 없앤다.
func apply_job_loadout() -> void:
	revalidate_equipped()
	grant_starting_loadout(selected_job())
	grant_starting_sub_job(selected_job())


# 새 게임 기본 지급 — 직업의 시작 무기를 지급하고, **무기 슬롯이 비어 있으면** 착용까지.
# 지급은 멱등(이미 가방/창고에 있으면 재지급 안 함)이고, 이미 뭘 착용 중이면 강제 교체하지 않는다.
# 세이브 로드 후(마을 진입 시) 부른다 → 로드한 판의 착용/보관 상태를 존중한다.
func grant_starting_loadout(job: JobDef) -> void:
	if job == null or job.starting_weapon_id.is_empty():
		return
	var wid := job.starting_weapon_id
	if not owned_equipment.has(wid) and not storage_equipment.has(wid):
		add_equipment(wid)  # allowlist 통과분만 추가 (미보유일 때만 — 재지급 안 함)
	# 🔴 **빈 무기 슬롯은 보유분으로도 채운다.** 예전엔 "이미 보유 = 전부 스킵"이라, 직업을 바꿔
	#   revalidate_equipped가 남의 무기를 해제한 뒤 **맨손으로 남았다**(그 직업을 전에 해본 적이 있으면
	#   가방에 무기가 있는데도). 강제 재장착은 여전히 안 한다 — 슬롯이 비었을 때만.
	if owned_equipment.has(wid) and equipped_id(EquipDef.SLOT_WEAPON).is_empty():
		equip(wid)


# 착용 장비 → [[EquipDef, level], …] (CombatMath.total_stats 입력)
func equipped_defs() -> Array:
	var out: Array = []
	for slot: int in equipped:
		var eid: String = equipped[slot]
		var e := equip_def(eid)
		if e != null:
			out.append([e, equip_level(eid)])
	return out


# 착용 장비 총 스탯 {attack, hp} — HUD·전투(calc_damage/max_hp)가 부른다 (단일 소스 CombatMath)
func current_stats() -> Dictionary:
	return CombatMath.total_stats(equipped_defs())


# 🔴 투사체 파라미터 리졸브 — 단일 소스 (rules §3, 차지 지팡이 2026-07-24).
# 표시(ArrowField: 탄 겉모습·속도·수명·폭발 FX 반경)와 판정(CombatAuthority: 호스트 전진·명중·폭발 반경)이
# 반드시 같은 값을 얻어야 "맞는 곳=보이는 곳"이 유지된다 — 한쪽에서 직접 계산하면 갈라진다.
# weapon_id = G_SHOOT "w"(발신자 주장) → **allowlist 리졸브만** 한다(모르는 id → null → 기본 화살 폴백,
# 경로 조작 불가 §3). 리졸브되면 사거리·속도·폭발 반경은 전송값이 아니라 **내 로컬 무기 데이터**에서 나온다
# (스푸핑 표면 최소화). 리졸브 실패 시에만 전송 사거리(fallback_range)를 clamp해 쓴다(궁수 구경로 호환).
# 🔴 **proj_range = 발사자 아바타의 「투사체 사거리」 특성**(player.trait_value) — 기본값 0이면 특성
#   도입 전과 **완전 항등**이다. 인자로 받는 이유: GameState는 peer_sync를 참조하지 않는다(모듈 경계 §0 +
#   `-s` 테스트 호환). 그래서 "누가 쐈나"를 아는 **호출부**가 그 값을 실어 준다.
#   🔴 두 호출부(표시 ArrowField · 판정 CombatAuthority)가 **같은 아바타**에서 읽어야 "맞는 곳 = 보이는
#   곳"이 유지된다 — 이 함수가 존재하는 이유 그 자체다. 값 자체는 네트워크로 오지 않는다(하위 직업 id만).
# 🔴 **combo = 평타 콤보 타수**(궁수 "평·평·쭉", 2026-07-27). 기본값 0 = 도입 전과 **완전 항등**이다.
#   네트워크로 오는 것은 **타수(정수)뿐**이고 사거리·데미지 배율은 여기서 로컬 .tres로 리졸브한다
#   (차지 레벨 "c"와 같은 철학 — 배율을 전송하면 그게 곧 스푸핑 표면).
#   🔴 표시(ArrowField)는 **발신자 주장 타수**를, 판정(CombatAuthority)은 **호스트가 센 타수**
#   (CombatMath.authoritative_combo ≤ 주장)를 넘긴다. 그래서 갈라짐은 항상 "그려졌는데 안 맞는다"
#   쪽으로만 떨어진다 — G_SHOOT "w"(무기 사칭) 처리와 같은 관용구다.
func projectile_params(weapon_id: String, fallback_range: float, charge: int,
		proj_range: float = 0.0, combo: int = 0) -> Dictionary:
	var e := equip_def(weapon_id)
	var lv := CombatMath.clamp_charge_level(charge)
	var is_charge := e != null and e.motion_type == "charge"
	var speed := CombatMath.clamp_projectile_speed(e.projectile_speed if e != null else 0.0)
	# 사거리 특성·콤보 배율은 여기 한 곳에서만 곱한다(단일 소스 §3). 결과는 아래 projectile_lifetime_s
	# 안에서 MAX_ARROW_RANGE clamp를 그대로 지난다 — 상한을 우회하는 계산 순서를 만들지 마라(심층 방어).
	# ⚠ 콤보 배율은 **무기 리졸브에 실패하면 항등(1.0)** 이다 — 모르는 id에 배율을 실을 자리가 없다.
	var travel := CombatMath.effective_projectile_range(
		e.arrow_range if e != null else fallback_range, proj_range,
		CombatMath.combo_range_mult_at(e, combo))
	return {
		"level": lv if is_charge else 0,  # 비차지 무기에 실린 레벨 주장은 여기서 떨군다(심층 방어 — is_charge_time_ok와 이중)
		"speed": speed,
		"life": CombatMath.projectile_lifetime_s(travel, speed),
		# 🔴 **비차지 무기에 실린 레벨 주장은 반경에서도 떨군다** (2026-07-27 netreview I1).
		#   `level`·`scale`·`step_time`은 처음부터 `is_charge` 게이트를 지났는데 여기만 `lv`를 날것으로 썼다.
		#   법사 지팡이가 둘 다 charge였을 땐 도달 불가였고, **낡은 지팡이가 shoot(마법볼)로 갈라지면서
		#   `blast_radius > 0`인 비차지 무기가 처음 생겨** 열린 경로다.
		# 🔴 **판정이 아니라 표시가 문제였다.** 판정 쪽은 `is_charge_time_ok`가 c≥1을 통째로 거부하지만,
		#   `arrow_field`는 그 게이트 없이 이 함수를 직접 불러 `_blasts[aid].radius`로 기억한다 —
		#   조작 클라의 `w="worn_staff", c=3` 한 통이면 **정직한 파트너 화면에도** 48px 폭발 FX·소리·
		#   반경 비례 셰이크가 뜬다(정상 20px). 표시 스푸핑이라 "사칭자 화면에만"이라는 기존 완화가 안 통한다.
		# 🔴 **층수 문제라 한 줄 조임 이상이다** — `level`은 스스로 "이중"이라 적을 수 있었지만 `blast`의
		#   방어층은 `combat_authority.gd`(씬 글루) **하나뿐**이었고, 그 파일 주석이 이미 인정했듯 거긴
		#   `-s`가 preload할 수 없어 **지워도 스위트 8종이 전부 초록이다.** 이 함수는 헤드리스로 겨눌 수
		#   있으므로, 이 게이트가 그 결함 클래스를 자동 방어 안으로 들여놓는 유일한 자리다.
		#   ⚠ **항등이다** — charge 무기는 무변경, 정직한 shoot는 애초에 c=0이라 결과가 같다(순수 조임).
		"blast": CombatMath.charge_blast_radius(e.blast_radius if e != null else 0.0, lv if is_charge else 0),
		"texture": e.projectile_texture if e != null else null,
		"spin": e.projectile_spin if e != null else false,
		"scale": CombatMath.CHARGE_ORB_SCALE[lv] if is_charge else 1.0,
		"tint": e.swing_color if e != null else Color(1, 1, 1, 1),
		"blast_sfx": e.blast_sfx if e != null else "",
		"step_time": e.charge_step_time if is_charge else 0.0,  # 0 = 차지 무기가 아님 → 호스트가 레벨 주장을 거부
		# 그 타의 데미지 배율 — 호스트가 confirm_damage에 넘긴다(사거리와 **같은 리졸브**를 지나야
		# "더 멀리 나가는 타 = 더 아픈 타"가 데이터 한 장에서 함께 온다). 표시 쪽은 안 쓴다.
		"combo_dmg": CombatMath.combo_damage_mult_at(e, combo),
	}


# 데이터에서 유도한 이론상 최대 장비 스탯(각 스탯 최대 레벨) — G_STATS 수신 클램프의 현실 상한(심층 방어).
# 정직한 최강 장비는 통과, 임의 수 주입만 막는다 (rules §2: 4인/PvP 전 본격 검증 게이트).
func max_equip_stats() -> Dictionary:
	var atk := 0
	var hp := 0
	for id: String in equipment_ids():
		var e := equip_def(id)
		if e == null:
			continue
		var s := CombatMath.equip_stat_at_level(e, e.max_level)
		atk = maxi(atk, int(s["attack"]))
		hp = maxi(hp, int(s["hp"]))
	return {"attack": atk, "hp": hp}


# --- 직업 레벨 성장축 (GDD v1.8) — 리졸버·EXP 적립·해금·레벨 스탯 ---
# 리졸버는 job/equipment와 같은 스캔 allowlist 규약 (rules §4) — 저장·네트워크로 들어온 id도 여길 지난다.

func sub_job_ids() -> Array[String]:
	if _sub_job_ids.is_empty():
		_sub_job_ids = _scan_ids("res://data/subjobs")
	return _sub_job_ids


func sub_job_def(id: String) -> SubJobDef:
	if _sub_job_cache.has(id):
		return _sub_job_cache[id] as SubJobDef
	if id not in sub_job_ids():
		return null  # allowlist 밖 — 폐기(경로 조작 불가)
	var s := load("res://data/subjobs/%s.tres" % id) as SubJobDef
	if s != null:
		_sub_job_cache[id] = s
	return s


# 한 계열의 하위 직업 id들 — order 정렬. 해금 체인의 단일 소스.
func sub_jobs_of_series(series_id: String) -> Array[String]:
	var pairs: Array = []
	for sid: String in sub_job_ids():
		var d := sub_job_def(sid)
		if d != null and d.series_id == series_id:
			pairs.append([d.order, sid])
	pairs.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	var out: Array[String] = []
	for p: Array in pairs:
		out.append(str(p[1]))
	return out


# 현재(또는 지정) 계열에서 **보유한** 하위 직업 — order 정렬. sub_job_exp의 키 = 보유.
# ⚠ **계열 것만**이다(공유 제외) — 해금 체인·시작 지급이 계열 안에서만 돌기 때문.
#   EXP 적립·UI 목록처럼 "쓸 수 있는 전부"가 필요하면 all_owned_sub_jobs를 써라.
func owned_sub_jobs(series_id: String = "") -> Array[String]:
	var series := series_id if not series_id.is_empty() else selected_job_id
	var out: Array[String] = []
	for sid: String in sub_jobs_of_series(series):
		if sub_job_exp.has(sid):
			out.append(sid)
	return out


# 공유 하위 직업(계열 무관·서브 전용, GDD v2.0) — order 정렬. 계열과 별개의 목록이다.
func shared_sub_jobs() -> Array[String]:
	return sub_jobs_of_series(SubJobDef.SERIES_SHARED)


func owned_shared_sub_jobs() -> Array[String]:
	var out: Array[String] = []
	for sid: String in shared_sub_jobs():
		if sub_job_exp.has(sid):
			out.append(sid)
	return out


# 이 계열에서 **쓸 수 있는 보유분 전부** = 계열 보유 + 공유 보유. EXP 적립·훈련소 목록의 기준.
func all_owned_sub_jobs(series_id: String = "") -> Array[String]:
	var out := owned_sub_jobs(series_id)
	out.append_array(owned_shared_sub_jobs())
	return out


# 계열의 EXP 곡선 (JobDef.exp_curve, 비면 CombatMath 기본) — 레벨 파생·HUD 바 공용.
# ⚠ series_id를 비우면 **현재 선택 계열**이다. 하위 직업의 레벨을 구할 때는 반드시 그 하위 직업의
#   계열을 넘겨라 — 선택 직업 기준으로 계산하면 계열이 섞인 상태에서 표시 레벨이 거짓말한다
#   (전사로 키운 뒤 궁수를 골라도 HUD가 "검사 LvN"을 띄우던 문제, 2026-07-25 리뷰 I3).
func exp_curve(series_id: String = "") -> PackedInt32Array:
	var j := job_def(series_id) if not series_id.is_empty() else selected_job()
	if j != null and j.exp_curve.size() >= 2:
		return j.exp_curve
	return CombatMath.default_exp_curve()


func has_sub_job(id: String) -> bool:
	return sub_job_exp.has(id)


func sub_job_level(id: String) -> int:
	if not sub_job_exp.has(id):
		return 0
	var d := sub_job_def(id)
	if d == null:
		return 0
	return CombatMath.level_for_exp(int(sub_job_exp[id]), exp_curve(d.series_id), d.max_level)


func main_sub_job() -> SubJobDef:
	var d := sub_job_def(main_sub_job_id)
	if d == null or d.series_id != selected_job_id:
		return null  # 타 계열 진행분은 이 판에서 없는 것으로 본다 (HUD가 남의 계열 레벨을 띄우지 않게)
	return d


# --- 장착 슬롯 (GDD v2.0 §5) — 메인 1 + 서브 2 ---

func sub_slot_id(index: int) -> String:
	if index < 0 or index >= sub_slot_ids.size():
		return ""
	return sub_slot_ids[index]


# 그 하위 직업을 **서브 칸에** 낄 수 있나 — 보유 + (계열 일치 또는 공유).
func can_equip_sub(id: String) -> bool:
	if not sub_job_exp.has(id):
		return false
	var d := sub_job_def(id)
	return d != null and d.is_usable_by(selected_job_id)


# 장착 중인 3개 — [메인] + 유효 서브. 🔴 여기서 **중복·미보유·타 계열·빈 칸을 전부 걸러낸다**:
#   같은 하위 직업이 메인과 서브에 동시에 들어가면 5스탯이 이중 계상되고 특성이 두 자리로 켜진다.
func equipped_sub_jobs() -> Array[String]:
	var out: Array[String] = []
	var main := main_sub_job()
	if main != null:
		out.append(main_sub_job_id)
	for i: int in range(SUB_SLOT_COUNT):
		var sid := sub_slot_id(i)
		if sid.is_empty() or sid in out:
			continue
		if can_equip_sub(sid):
			out.append(sid)
	return out


# 서브 칸 교체 — 마을에서만(메인 전환과 같은 이유: 판 도중 교체 = 상황별 취사선택 이득, GDD §5).
# id "" = 비우기. 메인과 같은 것을 서브에 끼려 하면 거부(equipped_sub_jobs 필터의 선제 방어).
func set_sub_slot(index: int, id: String) -> bool:
	if in_chapter():
		return false
	if index < 0 or index >= SUB_SLOT_COUNT:
		return false
	if not id.is_empty():
		if id == main_sub_job_id or not can_equip_sub(id):
			return false
		# 이미 다른 칸에 낀 것을 이 칸으로 → 두 칸을 맞바꾼다(같은 것이 두 칸을 먹지 않게)
		for i: int in range(SUB_SLOT_COUNT):
			if i != index and sub_slot_ids[i] == id:
				sub_slot_ids[i] = sub_slot_ids[index]
	if sub_slot_ids[index] == id:
		return true
	sub_slot_ids[index] = id
	_notify_growth()
	return true


# 빈 서브 칸을 보유분으로 자동 채운다 — 레벨 높은 순. 새 판·해금 직후·구 세이브 로드에서 부른다.
# 🔴 구 세이브에는 슬롯 필드가 없다 → 빈 칸으로 로드되는데, 그대로 두면 **이미 키운 하위 직업이
#   전부 꺼진 채** 판에 들어가 "업데이트했더니 약해졌다"가 된다. 자동 채움이 그 폴백이다.
func autofill_sub_slots() -> void:
	# 🔴 **판 도중엔 절대 슬롯을 바꾸지 않는다** — set_sub_slot의 마을 전용 가드를 여기서도 건다.
	#   전투 중 레벨업 해금(_try_unlock_next)이 빈 칸을 채우면 특성이 **판 도중 켜지고**, 그 순간
	#   내 로컬 판정 기하는 즉시 넓어지는데 호스트의 원격 아바타는 G_STATS 도달(편도 70~200ms)
	#   뒤에야 바뀐다 → 그 창에서 늘어난 사거리 타격이 **무음 거부**되고(화면엔 스윙만 나감),
	#   roll_dist 쪽은 반대로 정당 변위가 clamp돼 "피했는데 맞았다"가 부분 재발한다(2026-07-24 버그).
	#   해금 자체는 그대로 두고 슬롯 채움만 마을 진입(grant_starting_sub_job)으로 미룬다.
	if in_chapter():
		return
	var equipped_now := equipped_sub_jobs()
	var pool: Array[String] = []
	for sid: String in all_owned_sub_jobs():
		if sid not in equipped_now and can_equip_sub(sid):
			pool.append(sid)
	pool.sort_custom(func(a: String, b: String) -> bool: return sub_job_level(a) > sub_job_level(b))
	var changed := false
	for i: int in range(SUB_SLOT_COUNT):
		var cur := sub_slot_id(i)
		if not cur.is_empty() and cur != main_sub_job_id and can_equip_sub(cur):
			continue  # 이미 유효한 칸은 존중
		if pool.is_empty():
			if not cur.is_empty():
				sub_slot_ids[i] = ""  # 무효한 잔재(미보유·타 계열·메인과 중복)는 비운다
				changed = true
			continue
		sub_slot_ids[i] = pool.pop_front()
		changed = true
	if changed:
		_notify_growth()


# --- 특성 리졸브 (GDD v2.0 §5·§6) ---
# 🔴 **자리별로 하나씩만** 켠다 — 메인 id는 메인 특성, 서브 id는 서브 특성. 같은 하위 직업이라도
#   자리가 다르면 다른 효과이고, 한 장이 두 개를 동시에 켜지는 않는다(SubJobDef.trait_at).
# 🔴 값은 **id를 allowlist 리졸브해 로컬 .tres에서** 읽는다. 수치를 네트워크로 받으면 그게 곧
#   스푸핑 표면이다(peer_weapon_id·projectile_params와 같은 철학 — rules §3).
# 계열 불일치는 폐기 — 남의 계열 특성을 주장하는 공지를 버린다. 공유("*")는 어느 계열이든 통과하되
#   **메인 자리에서는 SubJobDef.trait_at이 막는다**(서브 전용, GDD §5).
# ⚠ 보유 여부는 **검증하지 않는다** — 원격 피어의 보유는 알 길이 없다(rules §2 4인/PvP 게이트 대상).
#   atk/hp 공지와 같은 수준의 발신자 트러스트이고, 상한(TRAIT_MAX)이 최악을 묶는다.
func traits_of(main_id: String, sub_ids: Array, series_id: String) -> Dictionary:
	var out := CombatMath.empty_traits()
	var seen: Array[String] = []
	var add := func(sid: String, as_main: bool) -> void:
		if sid.is_empty() or sid in seen:
			return
		var d := sub_job_def(sid)
		if d == null or not d.is_usable_by(series_id):
			return
		seen.append(sid)
		var t := d.trait_at(as_main)
		if t.is_empty():
			return
		var key := str(t["key"])
		if key in CombatMath.TRAIT_KEYS:  # 모르는 키(데이터 오타)는 조용히 폐기 — clamp_traits 관용구 미러
			out[key] = float(out[key]) + float(t["value"])
	add.call(main_id, true)
	var n := 0
	for v: Variant in sub_ids:
		if n >= SUB_SLOT_COUNT:
			break  # 🔴 슬롯 수 초과분은 버린다 — 공지에 서브를 10개 실어 특성을 쌓는 것 차단
		n += 1
		add.call(str(v), false)
	return CombatMath.clamp_traits(out)


# 내 활성 특성 — 로컬 판정 기하·연출·훈련소 패널·자기 공지가 전부 이 값을 쓴다.
# 🔴 입력은 **`equipped_sub_jobs()`(필터를 지난 목록)** 이지 `sub_slot_ids`(원본)가 아니다.
#   원본을 넘기면 traits_of가 보유 검증을 안 하므로 슬롯에 미보유·중복 id가 남는 순간
#   **특성은 켜지는데 5스탯(current_level_stats)은 안 들어가는** 상태가 된다 — 같은 화면이
#   서로 다른 근거를 보게 된다. 두 함수가 같은 목록에서 파생돼야 그 클래스가 구조적으로 사라진다.
func active_traits() -> Dictionary:
	return traits_of(announced_main_id(), announced_sub_ids(), selected_job_id)


# 메인 하위 직업의 **궤적 아이덴티티** {color, ghost} — 표시 전용(판정 무관·네트워크 0).
# 🔴 **traits_of와 같은 게이트를 지난다**: id allowlist 리졸브 · 계열 불일치 폐기 · 공유는 메인 불가.
#   사본 조건문을 두면 "메인 특성은 안 켜지는데 색만 바뀌는" 상태가 열린다 — 둘 다 **메인 자리**
#   소속이라 같은 근거에서 파생돼야 한다(active_traits ↔ announced_main_id 통일과 같은 이유).
# 🔴 공유 하위 직업 배제는 `SubJobDef.trait_at(true)`가 메인 특성을 막는 것과 **같은 근거**다
#   (메인 자리는 계열 전용, GDD §5). 여기서만 통과시키면 곡예사를 메인으로 주장한 공지가
#   특성은 못 얻고 색만 얻는다.
# 미상·불일치·미지정 = 항등(흰색 · 배율 1.0) = 도입 전과 완전히 같다.
func main_fx_of(main_id: String, series_id: String) -> Dictionary:
	var out := {"color": Color(1, 1, 1, 1), "ghost": 1.0, "tex": null, "frames": null}
	if main_id.is_empty():
		return out
	var d := sub_job_def(main_id)
	if d == null or d.is_shared() or not d.is_usable_by(series_id):
		return out
	out["color"] = d.fx_color
	out["ghost"] = CombatMath.fx_ghost_mult(d)  # 🔴 상한은 CombatMath 단일 소스(전수 트립와이어가 닿는 자리)
	# 🔴 질감도 **같은 게이트 안에서** 나온다 — 위 세 폐기 조건 중 하나라도 걸리면 null(단색)이다.
	#   밖에서 따로 읽으면 "색은 폐기됐는데 질감만 남는" 조합이 생긴다.
	out["tex"] = d.fx_trail_tex
	# 🔴 몸 시트도 **같은 게이트 안에서** 나온다(2026-08-02) — 같은 근거다. 밖에서 읽으면
	#   "곡예사를 메인으로 주장한 공지가 특성·색은 못 얻고 겉모습만 얻는" 조합이 열린다.
	out["frames"] = d.body_frames
	return out


# 내 궤적 아이덴티티 — 로컬 아바타 연출용. active_traits와 **같은 입력**(필터 통과분)을 쓴다.
func active_main_fx() -> Dictionary:
	return main_fx_of(announced_main_id(), selected_job_id)


# 공지용 메인 id — 무효(타 계열 진행분·미보유)면 빈 문자열. 🔴 `main_sub_job_id` 원본을 그대로
# 보내면 "나는 0으로 계산하는데 상대에겐 id를 보내는" 상태가 된다(수신 측 계열 필터가 같은 결과를
# 내서 지금은 무해하지만, 같은 것을 두 근거로 계산하는 구조가 남는다 — active_traits와 통일).
func announced_main_id() -> String:
	return main_sub_job_id if main_sub_job() != null else ""


# 공지용(그리고 특성 리졸브용) 서브 id 목록 — 필터를 지난 것만. equipped_sub_jobs()가 메인을
# 맨 앞에 두므로 그 한 칸만 덜어낸다. 🔴 `sub_slot_ids` 원본을 직접 쓰지 마라(위 이유).
func announced_sub_ids() -> Array[String]:
	var eq := equipped_sub_jobs()
	if main_sub_job() != null and not eq.is_empty() and eq[0] == main_sub_job_id:
		return eq.slice(1)
	return eq


# HUD EXP 바 — 메인 하위 직업의 {level, cur, need}. 미보유 = 0/0/0(표기 없음).
func main_exp_progress() -> Dictionary:
	var d := main_sub_job()
	if d == null:
		return {"level": 0, "cur": 0, "need": 0}
	return CombatMath.exp_progress(int(sub_job_exp.get(main_sub_job_id, 0)), exp_curve(d.series_id), d.max_level)


func _notify_growth() -> void:
	var b := _bus()
	if b != null:
		b.growth_changed.emit()


# 새 판 기본 지급 — 계열의 첫 하위 직업을 0 EXP로. grant_starting_loadout 미러(멱등: 이미 이 계열
# 진행분이 있으면 재지급 안 하고 메인만 보정). 세이브 로드 후 마을 진입에서 부른다.
func grant_starting_sub_job(job: JobDef) -> void:
	if job == null:
		return
	var owned := owned_sub_jobs(job.id)
	if not owned.is_empty():
		# 로드한 판 — 진행을 존중. 메인이 비었거나 이 계열 보유분이 아니면 첫 하위 직업으로 보정.
		if main_sub_job_id not in owned:
			main_sub_job_id = owned[0]
			_notify_growth()
		autofill_sub_slots()  # 구 세이브(슬롯 필드 없음)·계열 전환 뒤 빈 칸을 보유분으로 채운다
		return
	if job.starting_sub_job_id.is_empty():
		return  # 성장축이 없는 계열(데이터 미작성) — 조용히 넘어간다(전 슬라이스 호환)
	var sid := job.starting_sub_job_id
	var d := sub_job_def(sid)
	if d == null:
		push_warning("[GameState] 모르는 하위 직업 id '%s' — 지급 생략" % sid)
		return
	if d.series_id != job.id:
		push_warning("[GameState] 하위 직업 '%s'의 계열(%s)이 직업(%s)과 불일치 — 지급 생략" % [sid, d.series_id, job.id])
		return
	sub_job_exp[sid] = 0
	main_sub_job_id = sid
	autofill_sub_slots()  # 공유 하위 직업을 이미 보유 중이면(다른 계열에서 얻음) 바로 서브 칸에
	_notify_growth()


# EXP 적립 — 현재 계열 **보유 전부 + 공유 보유 전부**에 동일 적립 (GDD §6 계열 공용 풀).
# 🔴 **장착 여부와 무관하다** — 안 낀 것도 자란다("키운 것이 사라지는 게 아니라 지금 안 쓰는 것", GDD §5).
#   여기에 equipped 필터를 넣으면 슬롯 교체가 곧 성장 포기가 되어 조립이 벌이 된다.
# 반환 = 레벨/해금이 변했나 → 호출부가 이때만 G_STATS 재공지를 트리거한다(킬마다 재공지 방지).
# ⚠ 다른 계열의 진행분은 건드리지 않는다 — 전사로 키운 EXP가 궁수 판에서 섞이지 않는다(공유는 예외 = 항상 받는다).
func add_exp(amount: int) -> bool:
	if amount <= 0:
		return false
	var owned := all_owned_sub_jobs()
	if owned.is_empty():
		return false
	var before := {}
	for sid: String in owned:
		before[sid] = sub_job_level(sid)
		sub_job_exp[sid] = int(sub_job_exp.get(sid, 0)) + amount
	var b := _bus()
	var changed := false
	for sid: String in owned:
		var lv := sub_job_level(sid)
		if lv > int(before[sid]):
			changed = true
			if b != null:
				b.sub_job_level_up.emit(sid, lv)
	if _try_unlock_next():
		changed = true
	if b != null:
		var p := main_exp_progress()
		b.exp_changed.emit(int(p["cur"]), int(p["need"]))  # 가벼운 훅(HUD 바) — 재공지를 유발하지 않는다
	if changed:
		_notify_growth()
	return changed


# 해금 — 메인이 unlocks_next_at에 닿으면 계열의 다음(order+1) 하위 직업을 연다.
# 해금분은 **0 EXP로 시작**한다 → "해금 이후 적립분만 받으므로 자연히 레벨이 낮다"(GDD §6).
func _try_unlock_next() -> bool:
	var main := main_sub_job()
	if main == null:
		return false
	if sub_job_level(main_sub_job_id) < main.unlocks_next_at:
		return false
	for sid: String in sub_jobs_of_series(main.series_id):
		if sub_job_exp.has(sid):
			continue
		var d := sub_job_def(sid)
		if d != null and d.order == main.order + 1:
			sub_job_exp[sid] = 0
			autofill_sub_slots()  # 빈 칸이 있으면 바로 낀다 — 해금하고도 꺼져 있는 것을 방지
			var b := _bus()
			if b != null:
				b.sub_job_unlocked.emit(sid)
			return true
	return false


# 공유 하위 직업 해금 — 보스/챕터 클리어로 연다 (GDD v2.0 §6, 계열 레벨이 조건이 될 수 없으므로).
# 현재 페이싱 = **챕터1 보스 첫 처치에 보유 안 한 공유 전부**(= 2개 동시). 보유가 슬롯을 넘어야
#   조립이 시작되기 때문이다. 공유가 3개 이상으로 늘면 여기에 "2회 완주" 단계를 나눈다.
# 멱등 — 이미 보유한 것은 건드리지 않는다(두 번째 클리어에서 EXP가 0으로 리셋되지 않게).
func unlock_shared_sub_jobs() -> bool:
	var changed := false
	var b := _bus()
	for sid: String in shared_sub_jobs():
		if sub_job_exp.has(sid):
			continue
		sub_job_exp[sid] = 0
		changed = true
		if b != null:
			b.sub_job_unlocked.emit(sid)
	if changed:
		autofill_sub_slots()
		_notify_growth()
	return changed


# 메인 전환 — 마을에서만(GDD §5). 판 도중 전환은 상황별 스탯 취사선택 이득이라 거부한다.
# 🔒 **공유 하위 직업은 메인이 될 수 없다**(GDD v2.0 §5) — 계열 불일치 검사가 그대로 막는다("*" != 계열).
func set_main_sub_job(id: String) -> bool:
	if in_chapter():
		return false
	if not sub_job_exp.has(id):
		return false  # 미보유
	var d := sub_job_def(id)
	if d == null or d.series_id != selected_job_id:
		return false  # 타 계열·공유 거부
	if main_sub_job_id == id:
		return true
	var prev := main_sub_job_id
	main_sub_job_id = id
	# 새 메인이 서브 칸에 껴 있었다면 그 칸을 이전 메인으로 넘긴다 — 자리 맞바꿈(칸이 비지 않게).
	for i: int in range(SUB_SLOT_COUNT):
		if sub_slot_ids[i] == id:
			sub_slot_ids[i] = prev if (not prev.is_empty() and can_equip_sub(prev)) else ""
	autofill_sub_slots()  # 빈 칸 보정 (자체 _notify_growth 포함이지만 아래에서 한 번 더 쏴도 무해)
	_notify_growth()
	return true


# 현재 레벨 스탯 {crit, crit_dmg, haste, move, leech} — 전투(호스트 확정)·공지·UI 공용 (단일 소스 CombatMath).
# 🔴 v2.0: **장착한 3칸만** 센다(보유 전부가 아니라). 이게 예산을 슬롯 수에 묶는 그 자리다 —
#   여기서 all_owned로 되돌리면 하위 직업을 늘릴 때마다 총량이 부풀어 재역산 부채가 되살아난다.
func current_level_stats() -> Dictionary:
	var levels := {}
	var defs := {}
	for sid: String in equipped_sub_jobs():
		var d := sub_job_def(sid)
		if d == null:
			continue
		levels[sid] = sub_job_level(sid)
		defs[sid] = d
	return CombatMath.level_stats(main_sub_job_id, levels, defs)


# 데이터에서 유도한 이론상 최대 레벨 스탯 — G_STATS "lv" 수신 clamp의 현실 상한 (max_equip_stats 미러).
# 계열별로 "그 계열 하위 직업 전부를 만레벨·전부 메인 취급"한 관대한 합 → 정직한 최대치(서브 가중 < 1)는
# 절대 안 잘리고, 임의 수 주입만 막는다. 하드 상한(CombatMath.LEVEL_STAT_MAX)과 이중 방어.
# 🔴 v2.0 재유도: 상한은 **슬롯 기준**이다 — 「가장 센 계열 하나를 메인(가중 1) + 그 다음 센
#   SUB_SLOT_COUNT개를 서브(가중 w)」. 하위 직업이 몇 개든 낄 수 있는 것은 3개뿐이므로
#   **콘텐츠가 늘어도 상한이 안 부푼다**(v1.8~v1.9의 "보유 전부 합산" 상한이 개수에 비례해
#   넓어지던 문제 = 2026-07-25 리뷰 I2의 구조적 해소).
#   서브 후보에는 **공유 하위 직업도 들어간다**(서브 칸에 낄 수 있으므로) — 메인 후보는 계열 것만.
#   키마다 독립으로 상위 N을 고르므로 실제 조합보다 관대하지만, 정직한 최대치는 절대 안 잘린다.
func max_level_stats() -> Dictionary:
	var series_vals := {}   # series -> {key: Array[float] 만레벨 스텝들}
	var shared_vals := {}   # key -> Array[float]
	for key: String in CombatMath.LEVEL_STAT_KEYS:
		shared_vals[key] = [] as Array[float]
	for sid: String in sub_job_ids():
		var d := sub_job_def(sid)
		if d == null:
			continue
		var s := CombatMath.sub_job_stat_at_level(d, d.max_level)
		if d.is_shared():
			for key: String in CombatMath.LEVEL_STAT_KEYS:
				(shared_vals[key] as Array).append(float(s[key]))
			continue
		if not series_vals.has(d.series_id):
			var t := {}
			for key: String in CombatMath.LEVEL_STAT_KEYS:
				t[key] = [] as Array[float]
			series_vals[d.series_id] = t
		for key: String in CombatMath.LEVEL_STAT_KEYS:
			((series_vals[d.series_id] as Dictionary)[key] as Array).append(float(s[key]))
	var out := CombatMath.empty_level_stats()
	var w := CombatMath.SUB_JOB_WEIGHT
	var desc := func(a: float, b: float) -> bool: return a > b
	for series: String in series_vals:
		var per_key: Dictionary = series_vals[series]
		for key: String in CombatMath.LEVEL_STAT_KEYS:
			var mine: Array = (per_key[key] as Array).duplicate()
			mine.sort_custom(desc)
			if mine.is_empty():
				continue
			var cap := float(mine[0])                     # 메인 = 계열 최강 1개(가중 1)
			var pool: Array = mine.slice(1)               # 나머지 계열 것 + 공유 전부가 서브 후보
			pool.append_array(shared_vals[key] as Array)
			pool.sort_custom(desc)
			for i: int in range(mini(SUB_SLOT_COUNT, pool.size())):
				cap += w * float(pool[i])
			out[key] = maxf(float(out[key]), cap)
	return out

# ⚠ 특성에는 max_level_stats 같은 "데이터 유도 상한"이 없다 — **필요가 없기 때문**이다.
#   5스탯은 수치가 G_STATS로 오지만(그래서 데이터 상한이 필요), 특성은 **id만** 오고 값은 각자
#   자기 data/subjobs에서 읽는다(traits_of). 조작 공지가 넣을 수 있는 최악은 "가진 척한 id"이고
#   그 값도 결국 로컬 데이터라 CombatMath.TRAIT_MAX 하나로 충분히 묶인다.


# --- 창고 넣기/빼기 (각 클라 로컬 — 네트워크 0개, inventory_changed로 UI 갱신) ---
# 전부 clampi로 보유량 상한을 강제 → 음수/초과 이동 없음. 재료·창고는 0이 되면 키를 지워 표시 정돈.

func storage_material_count(id: String) -> int:
	return int(storage_materials.get(id, 0))


func deposit_gold(amount: int) -> void:
	var a := clampi(amount, 0, gold)
	if a <= 0:
		return
	gold -= a
	storage_gold += a
	_notify_inventory()


func withdraw_gold(amount: int) -> void:
	var a := clampi(amount, 0, storage_gold)
	if a <= 0:
		return
	storage_gold -= a
	gold += a
	_notify_inventory()


func deposit_material(id: String, qty: int) -> void:
	var a := clampi(qty, 0, material_count(id))
	if a <= 0:
		return
	var left := material_count(id) - a
	if left <= 0:
		materials.erase(id)
	else:
		materials[id] = left
	storage_materials[id] = storage_material_count(id) + a
	_notify_inventory()


func withdraw_material(id: String, qty: int) -> void:
	var a := clampi(qty, 0, storage_material_count(id))
	if a <= 0:
		return
	var left := storage_material_count(id) - a
	if left <= 0:
		storage_materials.erase(id)
	else:
		storage_materials[id] = left
	materials[id] = material_count(id) + a
	_notify_inventory()


# 장비 예치 — 장착 중이면 먼저 해제(창고 장비는 착용 불가). 레벨은 그대로 따라간다.
func deposit_equipment(equip_id: String) -> void:
	if not owned_equipment.has(equip_id):
		return
	var lv := int(owned_equipment[equip_id])
	var e := equip_def(equip_id)
	if e != null and equipped_id(e.slot()) == equip_id:
		equipped.erase(e.slot())
	owned_equipment.erase(equip_id)
	storage_equipment[equip_id] = lv
	_notify_inventory()


# 장비 회수 — 가방으로 되돌린다(자동 장착 안 함, 장착은 패널에서).
func withdraw_equipment(equip_id: String) -> void:
	if not storage_equipment.has(equip_id):
		return
	var lv := int(storage_equipment[equip_id])
	storage_equipment.erase(equip_id)
	owned_equipment[equip_id] = lv
	_notify_inventory()


# --- 저장 직렬화 (SaveManager가 부른다) ---

func clear_inventory() -> void:
	gold = 0
	materials.clear()
	unlocked_blueprints.clear()
	owned_equipment.clear()
	equipped.clear()
	storage_gold = 0
	storage_materials.clear()
	storage_equipment.clear()
	# 성장축도 함께 리셋 — 파일만 지우고 오토로드 메모리를 안 지우면 옛 진행이 다음 저장에 도로 써진다(rules §5)
	main_sub_job_id = ""
	sub_job_exp.clear()
	for i: int in range(SUB_SLOT_COUNT):
		sub_slot_ids[i] = ""  # 슬롯도 같이 — 안 지우면 미보유 id가 남아 다음 판 첫 공지에 실린다
	_notify_growth()  # 인벤 알림과 대칭 — 안 쏘면 HUD 레벨 표기가 스테일로 남는다


func to_save_dict() -> Dictionary:
	return {
		"gold": gold,
		"materials": materials.duplicate(),
		"blueprints": unlocked_blueprints.keys(),
		"equipment": owned_equipment.duplicate(),
		"equipped": {"0": equipped_id(EquipDef.SLOT_WEAPON), "1": equipped_id(EquipDef.SLOT_ARMOR)},
		"storage_gold": storage_gold,
		"storage_materials": storage_materials.duplicate(),
		"storage_equipment": storage_equipment.duplicate(),
		# 성장축 (GDD v1.8) — 🔴 SAVE_VERSION은 올리지 않는다(정확일치 검사라 올리면 배포본 세이브가
		# 전부 조용히 무시된다, rules §5). 필드 추가 + 구 세이브는 키 없음 → 레벨 0으로 읽힌다.
		# 레벨은 저장 대상이 아니다 — EXP에서 파생(위 sub_job_exp 주석).
		"main_sub": main_sub_job_id,
		"sub_exp": sub_job_exp.duplicate(),
		# 조립 축 (GDD v2.0) — 장착 서브 칸. 같은 규칙으로 **버전은 올리지 않는다**:
		# 구 세이브엔 키가 없어 빈 칸으로 읽히고, autofill_sub_slots가 보유분으로 채운다.
		"sub_slots": sub_slot_ids.duplicate(),
	}


# 로드 — 모든 id를 allowlist로 재검증(손상·조작 세이브의 모르는 id는 폐기). JSON은 수를 float로 만드므로 int 캐스트.
func from_save_dict(d: Dictionary) -> void:
	clear_inventory()
	gold = maxi(0, int(d.get("gold", 0)))
	var mats: Dictionary = d.get("materials", {})
	for mid: String in mats:
		if mid in material_ids():
			materials[mid] = maxi(0, int(mats[mid]))
	for rid: Variant in d.get("blueprints", []):
		if str(rid) in recipe_ids():
			unlocked_blueprints[str(rid)] = true
	var eqp: Dictionary = d.get("equipment", {})
	for eid: String in eqp:
		if eid in equipment_ids():
			owned_equipment[eid] = maxi(0, int(eqp[eid]))
	var worn: Dictionary = d.get("equipped", {})
	var w := str(worn.get("0", ""))
	var a := str(worn.get("1", ""))
	if w in owned_equipment:
		equipped[EquipDef.SLOT_WEAPON] = w
	if a in owned_equipment:
		equipped[EquipDef.SLOT_ARMOR] = a
	# 창고 — 인벤과 같은 allowlist 재검증(손상·조작 세이브의 모르는 id 폐기), JSON float→int 캐스트.
	storage_gold = maxi(0, int(d.get("storage_gold", 0)))
	var smats: Dictionary = d.get("storage_materials", {})
	for mid: String in smats:
		if mid in material_ids():
			var q := maxi(0, int(smats[mid]))
			if q > 0:
				storage_materials[mid] = q
	var seqp: Dictionary = d.get("storage_equipment", {})
	for eid: String in seqp:
		# 창고와 가방 양쪽에 같은 id가 오면(손상 세이브) 가방 우선 — 창고분은 버려 id당 1개 불변식 유지.
		if eid in equipment_ids() and not owned_equipment.has(eid):
			storage_equipment[eid] = maxi(0, int(seqp[eid]))
	# 성장축 (GDD v1.8) — 인벤과 같은 allowlist 재검증. 구 세이브엔 키가 없다 → 빈 상태로 두고
	# 마을 진입의 grant_starting_sub_job이 0 EXP로 지급한다("구 세이브는 레벨 0으로 읽힌다").
	# ⚠ EXP 상한 clamp가 없어도 안전하다: 레벨은 level_for_exp가 max_level로 clamp하고, 공지된 스탯은
	#   수신 측이 max_level_stats로 다시 clamp한다 → 조작 세이브가 정직한 만성장을 초과할 수 없다.
	var sexp: Dictionary = d.get("sub_exp", {})
	for sid: String in sexp:
		if sid in sub_job_ids():
			sub_job_exp[sid] = maxi(0, int(sexp[sid]))
	var ms := str(d.get("main_sub", ""))
	if sub_job_exp.has(ms):
		main_sub_job_id = ms  # 보유분이 아니면 비워 둔다 — grant_starting_sub_job이 첫 하위 직업으로 보정
	# 장착 서브 칸 (GDD v2.0) — 보유분만 통과시킨다. 구 세이브엔 키가 없어 전부 빈 칸이 되고,
	# 마을 진입의 grant_starting_sub_job → autofill_sub_slots가 보유분으로 채운다("약해지지 않게").
	# ⚠ 여기서 can_equip_sub(계열 검사)까지 걸지 않는 이유: 로드 시점엔 selected_job_id가 아직
	#   이 세이브의 계열이 아닐 수 있다. 계열 필터는 사용 시점(equipped_sub_jobs)이 매번 다시 건다.
	# ⚠ 타입 가드 — 조작 세이브가 `"sub_slots": "x"`를 넣으면 Array 대입이 런타임 에러다(lv류 미러).
	var slots_v: Variant = d.get("sub_slots", [])
	var slots: Array = (slots_v as Array) if slots_v is Array else []
	var seen_slots: Array[String] = []
	for i: int in range(SUB_SLOT_COUNT):
		var sid := str(slots[i]) if i < slots.size() else ""
		# 🔴 중복도 폐기한다 — 손상 세이브의 ["a","a"]는 한 칸을 조용히 죽이고(둘 다 유효해 보여
		#   autofill이 건너뛴다) 훈련소 패널은 두 칸 다 장착으로 그린다.
		if sid.is_empty() or sid == main_sub_job_id or sid in seen_slots or not sub_job_exp.has(sid):
			sub_slot_ids[i] = ""
			continue
		seen_slots.append(sid)
		sub_slot_ids[i] = sid
	# 🔴 **여기서 직업 귀속 필터를 걸지 않는다 — 걸면 정당한 장비가 조용히 벗겨진다** (리뷰 I-1).
	#   세이브는 직업을 담지 않고 `SaveManager._ready`가 로비보다 먼저 도므로, 이 시점
	#   `selected_job_id`는 **항상 기본 직업(warrior)** 이다. 여기서 파괴적으로 걸면 법사가 제작한
	#   상위 지팡이가 부팅 때마다 해제되고, 마을 진입의 `grant_starting_loadout`은 **시작 무기만**
	#   채우므로 그대로 다운그레이드된 채 판에 들어간다(에러 없음).
	#   ⚠ 12줄 위 서브 슬롯 로드가 같은 사실을 근거로 이미 같은 결정을 내려 뒀다 — 두 축의 규약을 맞춘다.
	#   실제 필터는 **직업이 확정되는 경계**(apply_job_loadout: 로비→마을 진입·마을 직업 변경)가 건다.
	_notify_inventory()
	_notify_growth()
