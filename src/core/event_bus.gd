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

# --- flow (마을/스테이지가 emit, src/main이 씬 스왑) ---
signal scene_change(scene_id: String)  # 호스트 로컬 결정 또는 게스트의 G_SCENE 수신 후 emit — 스왑은 main만 한다

# --- combat (플레이어/적이 emit, 스테이지가 권한 처리) ---
signal attack_hit(enemy: Node, job: JobDef)     # 로컬 공격 판정이 적에 닿음(공격자 job 동봉) — 확정은 호스트 경로(stage)
signal enemy_hp_confirmed(eid: String, hp: int)  # 호스트 전용 emit(enemy take_hit/부활) — stage가 ehp 브로드캐스트
