extends Node
# 런타임 진행 상태 오토로드 (projectb-rules §1) — 지금은 직업 선택만.
# 장비/인벤토리/재료·챕터 해금·파티는 해당 시스템 구현 때 여기로 확장한다.
# id→Resource 리졸버는 장차 Db 오토로드 몫 — Db 도입 시 이관 (rules §1).

const DEFAULT_JOB_ID := "warrior"
const DEFAULT_CHAPTER_ID := "chapter1"  # 챕터 해금/선택 시스템 전까지의 출발 챕터 (GDD §6 — 방장 해금 기준은 후속)

# 시작 시 선택, 이후 고정 (GDD §5). 로비에서 정하고 스테이지가 읽는다.
var selected_job_id: String = DEFAULT_JOB_ID

# 챕터 진행 좌표 — 쓰기는 scene_flow(G_SCENE 검증 통과)만, 읽기는 main·HUD·chapter_flow·씬 토큰.
var current_chapter_id: String = ""
var current_stage_idx: int = -1

var _job_ids: Array[String] = []  # data/jobs/ 스캔 캐시
var _chapter_ids: Array[String] = []  # data/chapters/ 스캔 캐시
var _material_ids: Array[String] = []    # data/materials/ 스캔 캐시
var _equipment_ids: Array[String] = []   # data/equipment/ 스캔 캐시
var _recipe_ids: Array[String] = []      # data/recipes/ 스캔 캐시
var _party_hp: Dictionary = {}  # peer_id -> 확정 HP — 챕터 내 스테이지 간 이월 (php 확정만 기록, player.gd 확정 경로가 쓴다)

# --- 인벤토리/장비 (드랍·제작 2026-07-23) — 각 클라 자기 것만, 브라우저 로컬 저장(개인·비네트워크, GDD §3) ---
var gold: int = 0
var materials: Dictionary = {}            # mat_id(String) -> qty(int)
var unlocked_blueprints: Dictionary = {}  # recipe_id(String) -> true
var owned_equipment: Dictionary = {}      # equip_id(String) -> level(int, 0=미강화)
var equipped: Dictionary = {}             # slot(int, EquipDef.SLOT_*) -> equip_id(String)


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


func equip_def(id: String) -> EquipDef:
	if id not in equipment_ids():
		return null
	return load("res://data/equipment/%s.tres" % id) as EquipDef


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
	return get_node_or_null("/root/EventBus") as EventBusHub


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
	return gold >= r.gold_cost and has_materials(r.material_costs)


func craft(recipe_id: String) -> bool:
	if not can_craft(recipe_id):
		return false
	var r := recipe_def(recipe_id)
	gold -= r.gold_cost
	_spend_materials(r.material_costs)
	add_equipment(r.result_equip_id)
	# 슬롯이 비어 있으면 자동 장착 — 첫 제작이 바로 효과나게 (QoL). 재장착은 패널에서.
	var e := equip_def(r.result_equip_id)
	if e != null and equipped_id(e.slot()).is_empty():
		equipped[e.slot()] = r.result_equip_id
	_notify_inventory()
	return true


func add_equipment(equip_id: String) -> void:
	if equip_id not in equipment_ids():  # allowlist
		push_warning("[GameState] 모르는 장비 id '%s'" % equip_id)
		return
	if not owned_equipment.has(equip_id):
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


func equip(equip_id: String) -> void:
	if equip_level(equip_id) < 0:
		return
	var e := equip_def(equip_id)
	if e == null:
		return
	equipped[e.slot()] = equip_id
	_notify_inventory()


func equipped_id(slot: int) -> String:
	return str(equipped.get(slot, ""))


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


# --- 저장 직렬화 (SaveManager가 부른다) ---

func clear_inventory() -> void:
	gold = 0
	materials.clear()
	unlocked_blueprints.clear()
	owned_equipment.clear()
	equipped.clear()


func to_save_dict() -> Dictionary:
	return {
		"gold": gold,
		"materials": materials.duplicate(),
		"blueprints": unlocked_blueprints.keys(),
		"equipment": owned_equipment.duplicate(),
		"equipped": {"0": equipped_id(EquipDef.SLOT_WEAPON), "1": equipped_id(EquipDef.SLOT_ARMOR)},
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
	_notify_inventory()
