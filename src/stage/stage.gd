extends Node2D
# 챕터 전투 스테이지 공용 루트 — 배치는 각 stage_*.tscn이, 전투·진행은 자식 컴포넌트가 담당.
# 여기서는 PeerSync 씬 토큰만 챕터 좌표(stage:챕터:인덱스)로 갱신한다 — 같은 tscn이 챕터 내
# 여러 칸에 재사용돼도 다른 칸 피어의 G_POS가 섞이지 않게 (유령 스폰 방지, peer_sync 규약).
# ⚠ 자식(PeerSync)의 _ready가 먼저 돌지만 스폰은 call_deferred라 이 갱신이 앞선다 (rules §5).

const PeerSyncNode := preload("res://src/net/peer_sync.gd")


func _ready() -> void:
	($PeerSync as PeerSyncNode).scene_id = GameState.stage_token()
	# 카메라 맵 클램프 (camera_rig가 읽음) — 스테이지 바닥 = 640×360 (stage_*.tscn Ground 미러)
	set_meta("map_rect", Rect2(0, 0, 640, 360))
