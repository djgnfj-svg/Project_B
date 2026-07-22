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
var _party_hp: Dictionary = {}  # peer_id -> 확정 HP — 챕터 내 스테이지 간 이월 (php 확정만 기록, player.gd 확정 경로가 쓴다)


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
