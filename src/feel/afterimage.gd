extends Node
# 대쉬 잔상 — 스프라이트의 현재 프레임을 그 자리에 "떼어 놓고" 페이드시킨다 (사용자 요청 2026-07-26:
# "구르기 보다는 잔상이 남는 대쉬"). 표시 전용·각 클라 로컬이라 **네트워크 메시지 0개**다.
# preload로만 쓴다(const AfterImage := preload(...)); 정적 함수라 인스턴스 불필요 (HitStop 미러).
#
# 🔴 잔상은 **씬 루트에 붙인다** — 플레이어의 자식으로 두면 플레이어를 따라다녀서 "지나온 자리에
#   남는다"가 성립하지 않는다(잔상이 몸에 겹쳐 그냥 흐릿한 몸으로 보인다).
# ⚠ z_index는 몸(Sprite z=1)보다 낮게 둔다. 음수로 내리면 배경 타일(z=-10)과의 사이라 안전하지만,
#   0이면 바닥 위·몸 아래에 정확히 깔린다 (rules §5 z 배치: 바닥 -10 < 텔레그래프 -1 < 몸/무기 0+).
#
# 연출값 (rules §0 예외 — 사용자가 플레이하며 조인다).

const FADE_S := 0.26            # 잔상 하나가 사라지기까지(s)
const START_ALPHA := 0.55       # 태어날 때 불투명도
const TINT := Color(0.72, 0.86, 1.0)  # 청백 — 몸과 구분되게(잔상이 몸으로 안 읽히게)
const SPAWN_INTERVAL := 0.045   # 잔상 사이 최소 간격(s) — 호출부가 이 값으로 타이머를 돈다
const Z_INDEX := 0              # 몸(1) 아래 · 바닥(-10) 위

# --- 무기 잔상 (스윙 궤적 축 2026-07-29) — 칼이 지나간 각마다 칼 그림을 떼어 놓는다 ---
const WEAPON_FADE_S := 0.16     # 대쉬 잔상보다 짧다 — 스윙 창(0.24s)이 대쉬보다 짧아 오래 남으면 겹쳐 뭉갠다
# 태어날 때 불투명도 (실물 칼과 구분되게).
# ⚠ 2026-08-01에 0.5 → 0.34로 내렸다 — 리본이 칼끝 **선**(7px)에서 칼날 폭 **면**으로 바뀌면서
#   칠해지는 면적이 약 5배가 됐고, 잔상 4장이 그 위에 겹치면 하얗게 탄다. 손맛값이라 사용자가 조인다
#   (`docs/TUNING.md` — 짝 노브는 `player.GHOST_STEPS`·`player.TRAIL_ALPHA_MAX`).
# 🔴 **0.34 → 0.46** (2026-08-02 사용자: *"검기 임팩트? 리본들을 좀더 강렬하게"*). 리본 알파도
#   같은 요청으로 0.72 → 0.88이 됐으니 **짝을 맞춰** 올린다 — 한쪽만 올리면 잔상이 리본에 묻혀
#   "칼이 여러 자루 지나갔다"가 안 읽힌다(위 0.5 → 0.34 조정이 정확히 그 반대 방향이었다).
const WEAPON_ALPHA := 0.46
# 🔴 **고정 z다 — `WeaponPivot.z_index`를 복사하지 마라.** 그 값은 조준 방향에 따라 0↔2를 오가므로
#   (등에 멘 대검은 규칙이 반대다) 복사하면 잔상이 스윙 도중 몸 앞뒤를 오가며 깜빡인다.
#   몸(1) 위 · 리본(3) 아래에 고정한다.
const WEAPON_Z_INDEX := 2


# sprite = 복제할 표시 노드(AnimatedSprite2D), host = 잔상을 남기는 주체(플레이어 등).
# host의 부모(씬 루트)에 붙인다 — 부모가 없으면(테스트·해제 중) 조용히 아무것도 안 한다.
static func spawn(sprite: AnimatedSprite2D, host: Node2D) -> void:
	if sprite == null or host == null or not sprite.is_inside_tree():
		return
	var parent := host.get_parent()
	if parent == null:
		return
	var frames := sprite.sprite_frames
	if frames == null or not frames.has_animation(sprite.animation):
		return
	var count := frames.get_frame_count(sprite.animation)
	if count <= 0:
		return
	var tex := frames.get_frame_texture(sprite.animation, clampi(sprite.frame, 0, count - 1))
	if tex == null:
		return
	var ghost := Sprite2D.new()
	ghost.texture = tex
	ghost.global_position = sprite.global_position
	ghost.rotation = sprite.global_rotation
	ghost.scale = sprite.global_scale
	ghost.flip_h = sprite.flip_h
	ghost.flip_v = sprite.flip_v
	ghost.offset = sprite.offset
	ghost.centered = sprite.centered
	ghost.z_index = Z_INDEX
	ghost.modulate = Color(TINT.r, TINT.g, TINT.b, START_ALPHA)
	parent.add_child(ghost)
	# 페이드 후 자기 정리 — 타이머가 아니라 트윈에 매달아야 씬이 먼저 사라져도 같이 죽는다.
	var tw := ghost.create_tween()
	tw.tween_property(ghost, "modulate:a", 0.0, FADE_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(ghost.queue_free)


# 무기 잔상 — 칼 그림을 그 각도에 떼어 놓는다. 둘 다 칼의 실제 배치식에서 나오므로 리본과도, 칼과도
# 정확히 포개진다.
# ⚠ 리본과의 대비는 여기 적지 않는다 — `player.gd`의 `_draw_swing_trail` 주석이 정본이다.
#   (옛 서술 *"리본이 칼끝 선이라면 이쪽은 면"* 은 2026-08-01에 **거짓이 됐다** — 리본도 면이다.
#    대비를 두 파일에 적으면 한쪽만 고쳐져 갈라진다. 이 프로젝트의 지배 고장 모드.)
#
# 🔴 **위 `spawn`처럼 노드를 통째로 복제할 수 없다.** 칼은 `WeaponPivot`(회전 중심) →
#   `Weapon`(centered=false · position = 그립 보정) **2단 구조**라, `Weapon` 하나만 복제하면
#   회전 중심이 칼 좌상단으로 바뀌어 전혀 다른 호를 그린다. 그래서 회전 중심(pivot)과
#   그림 오프셋(weapon.position)을 나눠 받는다.
# 🔴 **각은 호출부가 넘긴다** — `pivot.global_rotation`을 읽으면 안 된다: `_update_weapon`이 이 프레임의
#   회전을 아직 안 썼을 수 있어 **한 프레임 뒤처진 잔상**이 남는다(리본이 `_swing_angle_at`을 쓰는 것과 같은 이유).
# ⚠ `global_*`은 **add_child 뒤에** 대입한다 — 트리 밖에서는 global이 local과 같아 부모 변환이 반영되지 않는다.
static func spawn_weapon(weapon: Sprite2D, pivot: Node2D, host: Node2D,
		angle: float, tint: Color) -> void:
	if weapon == null or pivot == null or host == null or weapon.texture == null:
		return
	var parent := host.get_parent()
	if parent == null:
		return
	var ghost := Sprite2D.new()
	ghost.texture = weapon.texture
	ghost.centered = weapon.centered
	ghost.offset = weapon.position   # 그립 보정 — 회전 중심(pivot)에서 칼이 놓이는 자리
	ghost.flip_v = weapon.flip_v
	ghost.z_index = WEAPON_Z_INDEX
	ghost.modulate = Color(tint.r, tint.g, tint.b, tint.a * WEAPON_ALPHA)
	parent.add_child(ghost)
	ghost.global_position = pivot.global_position
	ghost.global_rotation = angle
	var tw := ghost.create_tween()
	tw.tween_property(ghost, "modulate:a", 0.0, WEAPON_FADE_S).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(ghost.queue_free)
