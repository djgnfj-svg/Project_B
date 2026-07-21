extends Node
# 런타임 진행 상태 오토로드 (projectb-rules §1) — 지금은 직업 선택만.
# 장비/인벤토리/재료·챕터 해금·파티는 해당 시스템 구현 때 여기로 확장한다.
# id→Resource 리졸버는 장차 Db 오토로드 몫 — Db 도입 시 이관 (rules §1).

const DEFAULT_JOB_ID := "warrior"

# 시작 시 선택, 이후 고정 (GDD §5). 로비에서 정하고 스테이지가 읽는다.
var selected_job_id: String = DEFAULT_JOB_ID

var _job_ids: Array[String] = []  # data/jobs/ 스캔 캐시


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
