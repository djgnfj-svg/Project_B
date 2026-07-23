extends Node2D
# 챕터 전투 스테이지 공용 루트 — 배치는 각 stage_*.tscn이, 전투·진행은 자식 컴포넌트가 담당.
# 여기서는 PeerSync 씬 토큰만 챕터 좌표(stage:챕터:인덱스)로 갱신한다 — 같은 tscn이 챕터 내
# 여러 칸에 재사용돼도 다른 칸 피어의 G_POS가 섞이지 않게 (유령 스폰 방지, peer_sync 규약).
# ⚠ 자식(PeerSync)의 _ready가 먼저 돌지만 스폰은 call_deferred라 이 갱신이 앞선다 (rules §5).

const PeerSyncNode := preload("res://src/net/peer_sync.gd")


func _ready() -> void:
	($PeerSync as PeerSyncNode).scene_id = GameState.stage_token()
	# 카메라 = 순수 추적 (맵 클램프 없음) → 던전에서 카메라가 플레이어를 따라온다.
	# void 방지 = 각 stage_*.tscn의 Ground region을 화면보다 크게 타일로 깔았다(어디로 가도 바닥이 화면을 채움).
	# 단일 화면 고정으로 되돌리려면 여기서 set_meta("map_rect", Rect2(...))를 부활 (camera_rig가 읽음).
