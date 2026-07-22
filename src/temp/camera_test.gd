extends Camera2D
# ⚠ TEMP — 카메라 무빙 테스트 전용. 어떤 씬에도 연결돼 있지 않다. 확인 끝나면 이 폴더(src/temp)째 삭제.
# 사용법(테스트 시): 로컬 플레이어 노드(CharacterBody2D) 밑에 이 스크립트를 단 Camera2D를 자식으로 붙이면
# 플레이어를 따라가며 맵 경계(limit_*) 안에서만 움직인다. 현재 게임은 고정 카메라가 정본이다.

const MAP_W: int = 640
const MAP_H: int = 384
const SMOOTH_SPEED: float = 6.0  # 연출값 — 추적 감속


func _ready() -> void:
	limit_left = 0
	limit_top = 0
	limit_right = MAP_W
	limit_bottom = MAP_H
	position_smoothing_enabled = true
	position_smoothing_speed = SMOOTH_SPEED
	make_current()
