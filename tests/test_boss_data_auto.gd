extends SceneTree
# 보스 데이터 계약 — `data/enemies/*.tres` 전수 스캔 (신설 2026-07-26).
#
# 왜 데이터만 보나: `src/enemies/boss.gd`는 씬 전용 글루라 `-s`에서 preload가 안 된다
#   (EventBus/Net 전역 식별자 — rules §5). 그래서 코드는 헤드리스로 못 잡지만,
#   **이번에 드러난 함정 대부분은 데이터 쪽**이었고 그건 `.tres`만 읽으면 잡힌다.
#
# 전부 **에러를 안 낸다** — 그게 여기 있는 이유다:
#   ⑴ 패턴 id와 같은 이름의 애니가 없으면 `_play`의 `_has_anim` 가드가 조용히 건너뛴다 → 공격 모션 무.
#   ⑵ 공격 애니가 `loop = true`면 `is_playing()`이 영원히 true라 `_anim_scale` 복귀와 idle 복귀가
#      통째로 멈춘다 → 애니 무한 반복 + 늘려둔 speed_scale이 다음 애니로 굳는다.
#   ⑶ `walk`가 없으면 이동 시 idle로 미끄러지고(옛 결함), 공격 애니 이름이 안 갈려
#      다음 예고가 이전 스윙 마지막 프레임으로 얼어붙는다.
#   ⑷ 애니 길이가 `telegraph_s`와 크게 갈라지면 `speed_scale` 배율이 1에서 멀어져
#      휘두름이 슬로모션/속사처럼 보인다(코드는 길이를 맞춰주지만 배속은 못 숨긴다).
#   ⑸ `telegraph_s = 0`이면 boss.gd의 센티널(`_telegraph_hold_s > 0.0`)이 호스트/게스트에서
#      다르게 읽혀 예고 지속·애니 배율이 갈라진다.
#
# ⚠ 파일명·프레임 수·애니 개수를 박지 않는다 — **새 보스 `.tres`가 자동으로 이 단정에 걸리게**
#   ("새 보스 = 파일 한 장", rules §4). 이 스크립트는 오토로드를 안 쓴다.

const DATA_DIR := "res://data/enemies"
# 애니 기본 길이 ≤ telegraph_s × 이 배수. 정확일치를 요구하지 않는 이유 = boss.gd가 매 회차
# speed_scale로 길이를 맞추기 때문(예고 길이는 지연 보상분 때문에 RTT에 따라 가변이다).
# 즉 이건 "배율이 1에서 너무 멀지 않은가" = 아트와 데이터가 크게 갈라지지 않았나의 트립와이어다.
const LEN_TOLERANCE := 1.5

var _fail := 0
var _checks := 0


func _init() -> void:
	_run()


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("  ok   %s" % label)
	else:
		_fail += 1
		print("  FAIL %s" % label)


# 애니 기본 재생 길이(초) = Σ프레임 duration / speed. `boss.gd _anim_base_length`와 같은 유도식을
# 여기서 재현한다 — 그 파일을 preload할 수 없기 때문이다(위 헤더). 프레임 duration은 프레임별로
# 다를 수 있어 개수로 가정하지 않고 합산한다.
func _anim_len(sf: SpriteFrames, anim: StringName) -> float:
	if not sf.has_animation(anim):
		return 0.0
	var speed := sf.get_animation_speed(anim)
	var count := sf.get_frame_count(anim)
	if speed <= 0.0 or count <= 0:
		return 0.0
	var total := 0.0
	for i in count:
		total += sf.get_frame_duration(anim, i)
	return total / speed


# data/enemies 전수 스캔 → BossDef만. 스캔 규약은 GameState._scan_ids 미러(.remap = 익스포트 빌드).
func _boss_defs() -> Array:
	var out: Array = []
	for f: String in DirAccess.get_files_at(DATA_DIR):
		var base := f.trim_suffix(".remap")
		if base.get_extension() != "tres" and base.get_extension() != "res":
			continue
		var res: Resource = load("%s/%s" % [DATA_DIR, base])
		if res is BossDef:
			out.append([base, res as BossDef])
	return out


func _check_boss(file: String, def: BossDef) -> void:
	var sf := def.frames
	if sf == null:
		# frames가 없으면 boss.gd가 sprite 1장을 idle로 감싼다 → 공격 애니가 통째로 없다
		_check(false, "%s: frames(SpriteFrames)가 없다 — 공격 애니가 통째로 안 나온다" % file)
		return
	_check(sf.has_animation(&"idle"), "%s: idle 애니 존재" % file)
	_check(sf.has_animation(&"walk"),
		"%s: walk 애니 존재 (없으면 이동 미끄러짐 + 다음 공격 애니가 얼어붙는다)" % file)
	if sf.has_animation(&"death"):
		# 시체 남김이 loop=false 전제 — 반복되면 시체가 계속 죽는 모션을 반복한다
		_check(not sf.get_animation_loop(&"death"), "%s: death loop=false (시체 남김 전제)" % file)
	_check(not def.patterns.is_empty(), "%s: patterns가 1개 이상 (%d개)" % [file, def.patterns.size()])
	for p: BossPatternDef in def.patterns:
		if p == null:
			_check(false, "%s: patterns에 null 항목" % file)
			continue
		var label := "%s/%s" % [file, p.id]
		_check(not p.id.is_empty(), "%s: 패턴 id가 비어 있지 않다" % label)
		_check(p.telegraph_s > 0.0,
			"%s: telegraph_s > 0 (%.2f) — 0이면 호스트/게스트 예고 지속이 갈라진다"
			% [label, p.telegraph_s])
		# range = 판정 반경(원)/사거리(콘)이자 셰이더가 그리는 반지름. 0이면 판정은 사실상 안 맞는데
		# 예고는 픽셀 격자+여유 때문에 작은 블롭으로 **보인다** — 이 계약에서 유일하게 "보이는데 안
		# 맞는" 방향의 이탈이라(나머지는 전부 과예고 = 안전) 데이터로 못 들어오게 막는다.
		_check(p.range > 0.0,
			"%s: range > 0 (%.1f) — 0이면 예고만 보이고 판정이 없다"
			% [label, p.range])
		var anim := StringName(p.id)
		var has := sf.has_animation(anim)
		_check(has, "%s: 패턴 id와 같은 이름의 애니 존재 (없으면 공격 모션이 조용히 안 나온다)" % label)
		if not has:
			continue
		_check(not sf.get_animation_loop(anim),
			"%s: loop=false (true면 무한 반복 + speed_scale 굳음)" % label)
		var base := _anim_len(sf, anim)
		_check(base > 0.0, "%s: 애니 길이 > 0 (프레임 %d · speed %.2f)"
			% [label, sf.get_frame_count(anim), sf.get_animation_speed(anim)])
		var ratio := (base / p.telegraph_s) if p.telegraph_s > 0.0 else INF
		_check(ratio <= LEN_TOLERANCE,
			"%s: 애니 %.3fs ≤ telegraph_s %.2fs × %.1f (speed_scale %.3f 필요)"
			% [label, base, p.telegraph_s, LEN_TOLERANCE, ratio])


func _run() -> void:
	var bosses := _boss_defs()
	# 스캔이 0건이면 아래 단정이 전부 건너뛰어져 **조용히 통과**한다 (verify §3 침묵 통과 방지)
	_check(not bosses.is_empty(),
		"%s 스캔: BossDef가 1개 이상 (%d개)" % [DATA_DIR, bosses.size()])
	for entry: Variant in bosses:
		var arr := entry as Array
		var file := str(arr[0])
		var def := arr[1] as BossDef
		print("[%s] %s" % [file, def.display_name])
		_check_boss(file, def)

	print("검사 %d건" % _checks)
	if _fail == 0:
		print("TEST_OK boss_data")
	else:
		print("TEST_FAIL boss_data failures=%d" % _fail)
	quit(1 if _fail > 0 else 0)
