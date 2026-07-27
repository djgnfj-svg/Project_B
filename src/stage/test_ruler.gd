extends Node2D
# 시험장 거리 눈금 — 🔴 **개발 도구다. 정상 플레이 씬에는 넣지 마라.**
# 화살 사거리·평타 도달을 **눈으로 재기** 위한 것: 기준점(= 플레이어 스폰)에서 각 거리에 세로선과
# 숫자를 그린다. docs/TUNING.md §9 실기 2번("화살 길이 = 죽는 거리")이 이것 없이는 감으로만 판정된다.
#
# 🔴 **Label 노드를 쓰지 않고 `draw_string`으로 그린다** — 월드에 놓인 Label은 그 아래 게임 클릭을
#   먹는다(rules §5. 보스전 480px 밴드·마을 안내문 3개·모닥불 2개가 실제로 그랬고, 발사가 통째로
#   죽었다). 그리기(`_draw`)는 노드가 아니라 클릭을 먹을 수 없다 — 이 자리에서 그 함정을 원천 차단한다.
# z_index = -9 (바닥 디테일 층) — 텔레그래프(-1)·몸(0)보다 아래라 판정 표시를 가리지 않는다(rules §5 z 표).

@export var origin: Vector2 = Vector2.ZERO          # 기준점 — PeerSync.spawn_base와 맞춘다(미러)
@export var marks: Array[float] = [50.0, 150.0, 300.0, 480.0]
@export var band_height: float = 240.0
@export var line_color: Color = Color(1, 1, 1, 0.22)
@export var text_color: Color = Color(1, 1, 1, 0.5)


func _ready() -> void:
	z_index = -9
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var fsize := ThemeDB.fallback_font_size
	var half := band_height * 0.5
	# 기준선(가로) — 어디서부터 잰 거리인지 보이게
	draw_line(Vector2(origin.x, origin.y), Vector2(origin.x + marks.max(), origin.y), line_color, 1.0)
	for d: float in marks:
		var x := origin.x + d
		draw_line(Vector2(x, origin.y - half), Vector2(x, origin.y + half), line_color, 1.0)
		draw_string(font, Vector2(x + 3.0, origin.y - half + float(fsize)), "%dpx" % int(d),
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, text_color)
