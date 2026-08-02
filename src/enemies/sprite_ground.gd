extends RefCounted
# 시트 실측 — 스프라이트 시트의 알파에서 「발밑 y · 몸 중심 x · 몸 폭」을 재서 돌려준다.
# 접지 그림자(그리고 앞으로 발밑에 붙는 무엇이든)의 배치 단일 소스다.
#
# 🔴 왜 코드가 재나 — 손으로 맞춘 상수는 시트가 바뀌면 조용히 틀린다.
#   `boss.tscn`의 `Shadow.position`(6, 42)은 **옛 망령 시트**의 발밑이었다. 보스가 미노로 바뀌면서
#   그 값만 안 따라와, 방향에 따라 발밑이 최대 6 tex px(화면 9px — 줌 1.5) 어긋난 채로 남았다
#   (2026-08-02 사용자 신고 *"보스 뭔가 땅에 안 붙어 있는데"*). x=6은 아예 근거를 잃어
#   미노 실물 중심(거의 정중앙)에서 9 월드px 오른쪽으로 밀려 있었다.
#   사람이 지키는 미러는 조용히 깨진다 — 이 프로젝트는 콘 텔레그래프에서 두 번, 공격 애니 길이에서
#   한 번 같은 값을 치렀고 둘 다 「코드가 유도」로 옮겨서 닫았다(rules §3). 여기도 같은 처방이다.
#
# 🔴 **표시 전용이다 — 판정 기하가 아니다.** `body_radius`(판정)와는 아무 관계가 없고, 여기 값이
#   틀려도 맞는 곳은 한 픽셀도 안 움직인다. 반대로 이 값을 판정에 끌어 쓰지 마라(§3).
#
# ⚠ 오토로드를 참조하지 않는다 — 그래야 `-s` 헤드리스가 preload해 트립와이어를 걸 수 있다
#   (`nav_grid.gd`와 같은 이유, rules §5). `boss.gd`는 씬 글루라 그쪽엔 못 둔다.

# 지면선을 정의하는 포즈 = **서 있는 것**. 이 접두사로 시작하는 애니만 표본으로 삼는다
# (`idle` · `idle_s` · `idle_ne` … 전부 걸린다).
# 🔴 공격 애니를 섞지 마라 — 미노 `slam_*`은 도끼가 바닥을 치느라 최하단이 60~61 tex px까지
#   내려간다(idle은 50~52). 섞으면 그림자가 발밑이 아니라 **도끼 끝**에 맞춰진다.
const IDLE_PREFIX := "idle"

# 표본 상한 — 웹(WASM 단일 스레드)에서 시트 디코드·스캔이 한 번에 끝나게. 8방향 시트가 8장,
# 4프레임 idle을 가진 시트라도 이 안에 들어온다.
const MAX_SAMPLES := 16


# 시트를 재서 스프라이트 **로컬 px**(원점 = 프레임 중심, `centered = true` 전제)로 돌려준다.
#   ok    : 실측 성공 여부. false면 호출부는 도입 전 동작으로 떨어져야 한다(항등 폴백).
#   foot  : 발밑 y — 최하단 불투명 픽셀의 **아래 모서리**. 아래가 +.
#   cx    : 몸 중심 x — 실루엣 바운딩 박스의 가로 중심. 오른쪽이 +.
#   width : 몸 폭(실루엣 바운딩 박스 가로).
#   samples: 실제로 잰 프레임 수(트립와이어 진단용).
#
# 🔴 **프레임마다가 아니라 표본의 중앙값 하나를 돌려준다** — 그림자는 몸이 아니라 **지면**에 붙는다.
#   프레임을 따라가면 걷기 상하 흔들림(미노 walk 최하단 49~52)을 그림자가 같이 타서 "그림자가
#   모델에 붙어 다닌다"가 되고, 그건 지금 증상보다 나쁘다. 중앙값을 쓰는 이유는 평균과 달리
#   한 방향의 극단 포즈(무기를 크게 뻗은 컷)에 안 끌려가기 때문이다.
static func measure(sf: SpriteFrames) -> Dictionary:
	var out := {"ok": false, "foot": 0.0, "cx": 0.0, "width": 0.0, "samples": 0}
	if sf == null:
		return out
	var texs := _sample_textures(sf)
	if texs.is_empty():
		return out
	var foots := PackedFloat32Array()
	var cxs := PackedFloat32Array()
	var widths := PackedFloat32Array()
	# 같은 아틀라스를 여러 프레임이 공유하므로(8방향 시트) **디코드는 아틀라스당 한 번**만 한다.
	# 프레임마다 `get_image()`를 부르면 576×576 디코드를 8회 반복해 웹에서 로딩 히치가 된다.
	var atlas_cache: Dictionary = {}
	for t: Texture2D in texs:
		var img := _frame_image(t, atlas_cache)
		if img == null or img.is_empty():
			continue
		var used := img.get_used_rect()
		if used.size.x <= 0 or used.size.y <= 0:
			continue   # 빈 프레임 — 지면선 정보가 없다
		var w := float(img.get_width())
		var h := float(img.get_height())
		foots.append(float(used.position.y + used.size.y) - h * 0.5)
		cxs.append(float(used.position.x) + float(used.size.x) * 0.5 - w * 0.5)
		widths.append(float(used.size.x))
	if foots.is_empty():
		return out
	out["ok"] = true
	out["foot"] = _median(foots)
	out["cx"] = _median(cxs)
	out["width"] = _median(widths)
	out["samples"] = foots.size()
	return out


# 표본 프레임 고르기 — idle 계열 전부. 하나도 없는 시트(폴백 SpriteFrames 등)는 각 애니 0프레임으로.
static func _sample_textures(sf: SpriteFrames) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for n: StringName in sf.get_animation_names():
		if not String(n).begins_with(IDLE_PREFIX):
			continue
		for i in range(sf.get_frame_count(n)):
			if out.size() >= MAX_SAMPLES:
				return out
			var t := sf.get_frame_texture(n, i)
			if t != null:
				out.append(t)
	if not out.is_empty():
		return out
	for n: StringName in sf.get_animation_names():
		if out.size() >= MAX_SAMPLES:
			break
		if sf.get_frame_count(n) <= 0:
			continue
		var t := sf.get_frame_texture(n, 0)
		if t != null:
			out.append(t)
	return out


# 프레임 한 장의 이미지. AtlasTexture면 아틀라스를 캐시에서 꺼내 region만 잘라 쓴다.
# ⚠ 실패(널·VRAM 압축 등)는 예외가 아니라 null이다 — 호출부가 항등 폴백으로 떨어지게.
static func _frame_image(t: Texture2D, atlas_cache: Dictionary) -> Image:
	var at := t as AtlasTexture
	if at != null and at.atlas != null:
		var key := at.atlas.get_instance_id()
		var full: Image = atlas_cache.get(key, null) as Image
		if full == null:
			full = at.atlas.get_image()
			if full == null:
				return null
			atlas_cache[key] = full
		var r := Rect2i(at.region)
		r = r.intersection(Rect2i(Vector2i.ZERO, full.get_size()))
		if r.size.x <= 0 or r.size.y <= 0:
			return null
		return full.get_region(r)
	return t.get_image()


static func _median(v: PackedFloat32Array) -> float:
	var a := v.duplicate()
	a.sort()
	var n := a.size()
	if n == 0:
		return 0.0
	if n % 2 == 1:
		return a[n / 2]
	return (a[n / 2 - 1] + a[n / 2]) * 0.5
