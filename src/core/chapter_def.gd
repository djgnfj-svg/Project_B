class_name ChapterDef
extends Resource
# 챕터 정의 스키마 (core — 리드 전용). "새 챕터 = 파일 한 장" (projectb-rules §4).
# stage_scenes = 진행 순서대로의 씬 경로 목록. 모닥불(휴식) 칸도 이 목록의 한 칸이다 —
# 파일명이 "campfire"로 시작하면 휴식 칸으로 판별(관례). 마지막 칸 = 보스 스테이지.
# ⚠ PackedScene 배열이 아니라 경로 문자열인 이유: 챕터 로드 시 모든 스테이지가 미리 로드되는
#   것을 피하고(웹 첫 로딩 부담) 씬 순환 preload 함정을 원천 차단 (rules §5).

@export var display_name: String = ""
@export var stage_scenes: Array[String] = []


func stage_count() -> int:
	return stage_scenes.size()


func is_valid_index(i: int) -> bool:
	return i >= 0 and i < stage_scenes.size()


func is_rest(i: int) -> bool:
	return is_valid_index(i) and stage_scenes[i].get_file().begins_with("campfire")


# i까지(포함)의 전투 스테이지 순번 (1-base, 휴식 칸 제외) — HUD "스테이지 n/m" 표기용
func combat_ordinal(i: int) -> int:
	var n := 0
	for j: int in range(mini(i, stage_scenes.size() - 1) + 1):
		if not is_rest(j):
			n += 1
	return n


func combat_total() -> int:
	var n := 0
	for j: int in range(stage_scenes.size()):
		if not is_rest(j):
			n += 1
	return n
