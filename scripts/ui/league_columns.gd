class_name LeagueColumns
extends RefCounted


const COMPACT_COLS := [
	{"key": "position", "label": "#", "num": false},
	{"key": "club", "label": "CLUB", "num": false},
	{"key": "played", "label": "P", "num": true},
	{"key": "won", "label": "W", "num": true},
	{"key": "drawn", "label": "D", "num": true},
	{"key": "lost", "label": "L", "num": true},
	{"key": "gf", "label": "GF", "num": true},
	{"key": "ga", "label": "GA", "num": true},
	{"key": "gd", "label": "GD", "num": true},
	{"key": "points", "label": "PTS", "num": true},
]


const POS_INDENT := 10.0
const CLUB_INDENT := 32.0

const NUM_W := 26.0
const NUM_GAP := 10.0


const MIN_NUM_W := 18.0
const MIN_GAP := 4.0

const TAIL := 10.0


const MIN_CLUB_W := 100.0


const CLUB_SHARE := 0.42
const MAX_CLUB_W := 460.0


static func numbers(cols: Array) -> Array:
	var out: Array = []
	for col in cols:
		if bool(col["num"]):
			out.append(col)
	return out


static func min_row(cols: Array, club_min: float = MIN_CLUB_W) -> float:
	var n := float(maxi(numbers(cols).size(), 1))
	return CLUB_INDENT + club_min + n * (MIN_NUM_W + MIN_GAP) + TAIL


static func of(row: Rect2, cols: Array, club_min: float = MIN_CLUB_W,
		club_share: float = CLUB_SHARE) -> Dictionary:
	var boxes := numbers(cols)
	var club_x := row.position.x + CLUB_INDENT
	var right := row.end.x - TAIL
	var n := float(maxi(boxes.size(), 1))
	var room := right - club_x
	var floor_pitch := MIN_NUM_W + MIN_GAP
	var club_w := clampf(room * club_share, club_min, MAX_CLUB_W)
	club_w = minf(club_w, maxf(room - n * floor_pitch, club_min))
	var pitch := maxf((room - club_w) / n, floor_pitch)
	var gap := clampf(pitch - NUM_W, MIN_GAP, NUM_GAP)
	var w := pitch - gap
	var rail: Array = []
	for i in range(boxes.size()):
		var col: Dictionary = boxes[i]
		rail.append({
			"key": str(col["key"]), "label": str(col["label"]),
			"right": right - float(boxes.size() - 1 - i) * pitch, "w": w,
		})
	return {
		"pos_x": row.position.x + POS_INDENT,
		"club_x": club_x,
		"club_w": club_w,
		"cols": rail,
	}


static func club_label(row: Dictionary) -> String:
	var name := str(row.get("club_name", "")).strip_edges()
	if name != "":
		return name
	return str(row.get("club_abbr", ""))


static func text(row: Dictionary, key: String) -> String:
	if key == "gd":
		return "%+d" % (int(row.get("gf", 0)) - int(row.get("ga", 0)))
	return "%d" % int(row.get(key, 0))


static func fit_name(s: String, font: Font, size: int, max_w: float) -> String:
	if font == null or max_w <= 0.0:
		return s
	if font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= max_w:
		return s
	var cut := s
	while cut.length() > 1:
		cut = cut.substr(0, cut.length() - 1).strip_edges()
		var probe := cut + "…"
		if font.get_string_size(probe, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= max_w:
			return probe
	return "…"


static func fit_caption(s: String, font: Font, size: int, room: float) -> String:
	if s == "" or room <= 0.0:
		return ""
	return fit_name(s, font, ChromeDensity.read_size(size), room)
