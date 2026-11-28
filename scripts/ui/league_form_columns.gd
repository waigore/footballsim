class_name LeagueFormColumns
extends RefCounted


const LAST := LeagueFormGuide.LAST

const FORM_COLS := [
	{"key": "position", "label": "#", "num": false},
	{"key": "club", "label": "CLUB", "num": false},
	{"key": "form", "label": "FORM", "num": false, "sort": false},
	{"key": "points", "label": "PTS", "num": true},
]

const FORM_CAPTION := "LAST 5 · OLDEST FIRST"

const PIP := 18.0
const GAP := 4.0
const PTS_W := 26.0
const INSET := 12.0
const TAIL := 10.0
const CAPTION_H := 14.0
const MARK_INK := Color(0.06, 0.06, 0.05)
const EMPTY := "—"


static func lane(limit: int = LAST) -> float:
	return float(limit) * PIP + float(limit - 1) * GAP


static func min_row(limit: int = LAST) -> float:
	return LeagueColumns.CLUB_INDENT + LeagueColumns.MIN_CLUB_W + INSET + lane(limit) \
		+ INSET + PTS_W + TAIL


static func places(row: Rect2, limit: int = LAST) -> Dictionary:
	var right := row.end.x - TAIL
	var form_right := right - PTS_W - INSET
	var form_left := form_right - lane(limit)
	var club_x := row.position.x + LeagueColumns.CLUB_INDENT
	return {
		"pos_x": row.position.x + LeagueColumns.POS_INDENT,
		"club_x": club_x,
		"club_w": maxf(form_left - INSET - club_x, LeagueColumns.MIN_CLUB_W),
		"cols": [
			{"key": "form", "label": "FORM", "right": form_right, "w": lane(limit),
				"form": true, "sort": false},
			{"key": "points", "label": "PTS", "right": right, "w": PTS_W},
		],
	}


static func mark_color(mark: String) -> Color:
	if mark == LeagueFormGuide.WIN:
		return UiChrome.C_LIVE
	if mark == LeagueFormGuide.DRAW:
		return UiChrome.C_SOFT
	return UiChrome.C_DANGER

# gd-tools: no cover start


static func draw(c: CanvasItem, cache: Dictionary, col: Dictionary, rect: Rect2,
		marks: Array, fonts: Dictionary) -> void:
	var right := float(col["right"])
	var baseline := rect.position.y + rect.size.y * 0.5 + 4.0
	if marks.is_empty():
		UiChrome.text_r(c, right, baseline, EMPTY, 9, UiChrome.C_DIM, fonts["med"])
		return
	var box: float = minf(rect.size.y - 12.0, 16.0)
	var top := rect.position.y + rect.size.y * 0.5 - box * 0.5
	for i in range(marks.size()):
		var x := right - float(marks.size() - i) * (PIP + GAP) + GAP
		var colour := mark_color(str(marks[i]))
		UiChrome.panel(c, cache, Rect2(x, top, PIP, box), colour, 3, colour, 0)
		UiChrome.text_c(c, x + PIP * 0.5, top + box * 0.5 + 4.0, str(marks[i]), 8,
			MARK_INK, fonts["bold"])

# gd-tools: no cover end
