class_name LeagueTableView
extends RefCounted

## The league table in its two readings (#72/#74): a compact standings strip
## (#, club, P, GD, PTS) and the full sheet with the overall record plus the
## home and away splits, sorted by any column.
##
## Sorting never renumbers the league: every row keeps the official `position`
## the save computed, so the `#` column and the zone bands always show the real
## place (the list order is the player's, the numbers are the league's).
##
## The reading, the sorted column and the direction live in the save's
## `save_meta`, so leaving the sheet or reopening the save brings them back. A
## save that has never been touched opens on the device default: compact on a
## phone, full on a desktop.
##
## Geometry, sorting and paint only. `LeagueBook` keeps the table pose and hands
## geometry and paint here, because the book is already at its method budget.

const COMPACT := "compact"
const FULL := "full"
const MODES := [COMPACT, FULL]

const META_MODE := "table_mode"
const META_SORT := "table_sort"
const META_DIR := "table_dir"

const ROW_H := 22.0
## Room for the place number before the club name.
const POS_W := 22.0
## The club column never collapses; a name wider than it is shortened instead.
const CLUB_MIN := 150.0
## One number box and the air between two of them.
const NUM_W := 28.0
const NUM_GAP := 2.0
## Rows start below a one-line header, or below the group captions of the full
## sheet (OVERALL / HOME / AWAY).
const HEAD_ONE := 22.0
const HEAD_TWO := 34.0

## `num` boxes sit on a right-aligned rail; `group` names the caption band the
## full sheet paints above them. `position` is never sortable: `#` is the league.
const COMPACT_COLS := [
	{"key": "position", "label": "#", "num": false},
	{"key": "club", "label": "CLUB", "num": false},
	{"key": "played", "label": "P", "num": true},
	{"key": "gd", "label": "GD", "num": true},
	{"key": "points", "label": "PTS", "num": true},
]

const FULL_COLS := [
	{"key": "position", "label": "#", "num": false},
	{"key": "club", "label": "CLUB", "num": false},
	{"key": "played", "label": "P", "num": true, "group": "OVERALL"},
	{"key": "won", "label": "W", "num": true, "group": "OVERALL"},
	{"key": "drawn", "label": "D", "num": true, "group": "OVERALL"},
	{"key": "lost", "label": "L", "num": true, "group": "OVERALL"},
	{"key": "gf", "label": "GF", "num": true, "group": "OVERALL"},
	{"key": "ga", "label": "GA", "num": true, "group": "OVERALL"},
	{"key": "gd", "label": "GD", "num": true, "group": "OVERALL"},
	{"key": "points", "label": "PTS", "num": true, "group": "OVERALL"},
	{"key": "home_played", "label": "P", "num": true, "group": "HOME"},
	{"key": "home_won", "label": "W", "num": true, "group": "HOME"},
	{"key": "home_drawn", "label": "D", "num": true, "group": "HOME"},
	{"key": "home_lost", "label": "L", "num": true, "group": "HOME"},
	{"key": "home_gf", "label": "GF", "num": true, "group": "HOME"},
	{"key": "home_ga", "label": "GA", "num": true, "group": "HOME"},
	{"key": "away_played", "label": "P", "num": true, "group": "AWAY"},
	{"key": "away_won", "label": "W", "num": true, "group": "AWAY"},
	{"key": "away_drawn", "label": "D", "num": true, "group": "AWAY"},
	{"key": "away_lost", "label": "L", "num": true, "group": "AWAY"},
	{"key": "away_gf", "label": "GF", "num": true, "group": "AWAY"},
	{"key": "away_ga", "label": "GA", "num": true, "group": "AWAY"},
]

## Reading, sorted column ("": official order) and direction (1 asc, -1 desc).
var mode := ""
var sort := ""
var dir := -1

## Take the reading, sort and direction the save remembers. Called when the
## table opens, so two saves never share one table's choices.
func attach(save: LeagueSave) -> void:
	mode = ""
	sort = ""
	dir = -1
	if save == null:
		return
	var meta := save.read_meta()
	var saved_mode := str(meta.get(META_MODE, ""))
	mode = saved_mode if MODES.has(saved_mode) else ""
	var saved_sort := str(meta.get(META_SORT, ""))
	sort = saved_sort if sortable(saved_sort) else ""
	dir = 1 if str(meta.get(META_DIR, "desc")) == "asc" else -1

static func columns(reading: String) -> Array:
	return FULL_COLS if reading == FULL else COMPACT_COLS

## Keys a header can sort by: every visible field except the official place.
static func sortable(key: String) -> bool:
	if key == "" or key == "position":
		return false
	for col in FULL_COLS:
		if str(col["key"]) == key:
			return true
	return false

## A row's value for one column. Goal difference is derived, the club column
## sorts by name, everything else is a saved integer.
static func cell(row: Dictionary, key: String) -> int:
	if key == "gd":
		return int(row.get("gf", 0)) - int(row.get("ga", 0))
	return int(row.get(key, 0))

static func numeric(cols: Array) -> int:
	var count := 0
	for col in cols:
		if bool(col["num"]):
			count += 1
	return count

# ------------------------------------------------------------------ layout ---

func layout(vp: Vector2, view: Dictionary) -> Array:
	var reading := _reading(vp)
	var cols := columns(reading)
	var rows := ordered(view.get("table", []))
	var row_w := maxf(vp.x - 48.0, POS_W + CLUB_MIN + float(numeric(cols)) * (NUM_W + NUM_GAP))
	var places := _places(Rect2(24.0, 0.0, row_w, ROW_H))
	var top: float = LeagueSheet.HEADER + (HEAD_TWO if reading == FULL else HEAD_ONE)
	var items := _header(places)
	for i in range(rows.size()):
		items.append({
			"id": "club:" + str(rows[i]["club_id"]), "kind": "table_row", "row": rows[i],
			"zone": LeagueRules.zone(int(rows[i]["position"]), view.get("rules", {})),
			"rect": Rect2(24.0, top + float(i) * ROW_H, row_w, ROW_H - 1.0), "places": places,
		})
	items.append({"id": "back", "kind": "button", "label": "BACK", "pinned": true,
		"rect": Rect2(24.0, vp.y - LeagueSheet.BAR_H + 6.0, 110.0, LeagueSheet.BAR_H - 14.0),
		"primary": true})
	# Two doors rather than one toggle: the gold one is the reading on screen,
	# so the player never has to guess what a press will do.
	items.append({"id": "tbl:mode:" + COMPACT, "kind": "button", "label": "COMPACT",
		"pinned": true, "primary": reading == COMPACT,
		"rect": Rect2(142.0, vp.y - LeagueSheet.BAR_H + 6.0, 104.0, LeagueSheet.BAR_H - 14.0)})
	items.append({"id": "tbl:mode:" + FULL, "kind": "button", "label": "FULL",
		"pinned": true, "primary": reading == FULL,
		"rect": Rect2(252.0, vp.y - LeagueSheet.BAR_H + 6.0, 78.0, LeagueSheet.BAR_H - 14.0)})
	return items

## The reading this sheet draws. With no saved choice the device decides once;
## the resolved value is what a mode press flips.
func _reading(vp: Vector2) -> String:
	if mode == "":
		mode = COMPACT if LeagueSheet.compact(vp) else FULL
	return mode

## Rows in the player's chosen order, each keeping its official position. Ties
## fall back to the official place so a re-sort is never arbitrary. A sort on a
## column the current reading does not show is left for the reading that does:
## the compact strip never sorts by a number the player cannot see.
func ordered(rows: Array) -> Array:
	if sort == "" or rows.size() < 2 or not _shown(sort):
		return rows
	var out := rows.duplicate()
	var key := sort
	var sign := dir
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if key == "club":
			var na := str(a["club_name"])
			var nb := str(b["club_name"])
			if na != nb:
				return na < nb if sign > 0 else na > nb
		else:
			var va := cell(a, key)
			var vb := cell(b, key)
			if va != vb:
				return va < vb if sign > 0 else va > vb
		return int(a["position"]) < int(b["position"])
	)
	return out

func _shown(key: String) -> bool:
	for col in columns(mode):
		if str(col["key"]) == key:
			return true
	return false

## Column rails for a row at this width. Compact keeps `LeagueColumns`, the
## measured layout #71 settled; the full sheet walks the columns from the club
## column's right edge so the whole record fits a phone in landscape.
func _places(row: Rect2) -> Dictionary:
	if mode == COMPACT:
		var fit := LeagueColumns.of(row)
		var rail: Array = [
			{"key": "played", "label": "P", "right": float(fit["p_r"]),
				"w": LeagueColumns.NUM_W, "group": ""},
			{"key": "gd", "label": "GD", "right": float(fit["gd_r"]),
				"w": LeagueColumns.NUM_W, "group": ""},
			{"key": "points", "label": "PTS", "right": float(fit["pts_r"]),
				"w": LeagueColumns.NUM_W, "group": ""},
		]
		return {"pos_x": float(fit["pos_x"]), "club_x": float(fit["club_x"]),
			"club_w": float(fit["club_w"]), "cols": rail}
	var club_x := row.position.x + POS_W
	var club_w := row.size.x - POS_W - float(numeric(FULL_COLS)) * (NUM_W + NUM_GAP)
	var out := {"pos_x": row.position.x, "club_x": club_x, "club_w": club_w, "cols": []}
	var x := club_x + club_w
	for col in FULL_COLS:
		if bool(col["num"]):
			out["cols"].append({"key": str(col["key"]), "label": str(col["label"]),
				"right": x + NUM_W, "w": NUM_W, "group": str(col.get("group", ""))})
			x += NUM_W + NUM_GAP
	return out

## The header is part of the scrolling content, so a column stays above its
## numbers when the sheet is panned sideways and its tap target travels with it.
func _header(places: Dictionary) -> Array:
	var items: Array = []
	var y := LeagueSheet.HEADER + 6.0
	if mode == FULL:
		items.append_array(_captions(places, y))
		y += 12.0
	items.append(_head_cell(y, float(places["pos_x"]), 20.0, "#", "", false))
	items.append(_head_cell(y, float(places["club_x"]), float(places["club_w"]),
		"CLUB", "club", false))
	for col in places["cols"]:
		items.append(_head_cell(y, float(col["right"]) - float(col["w"]), float(col["w"]),
			str(col["label"]), str(col["key"]), true))
	return items

func _captions(places: Dictionary, y: float) -> Array:
	var out: Array = []
	var bands: Array = []
	for col in places["cols"]:
		var group := str(col["group"])
		if group == "":
			continue
		var left := float(col["right"]) - float(col["w"])
		if bands.is_empty() or str(bands[bands.size() - 1]["label"]) != group:
			bands.append({"label": group, "left": left, "right": float(col["right"])})
		else:
			bands[bands.size() - 1]["right"] = float(col["right"])
	for band in bands:
		out.append({"id": "", "kind": "caption", "label": str(band["label"]),
			"rect": Rect2(float(band["left"]), y, float(band["right"]) - float(band["left"]), 11.0)})
	return out

func _head_cell(y: float, x: float, w: float, label: String, key: String,
		right_align: bool) -> Dictionary:
	var id: String = "" if key == "" else "tbl:sort:" + key
	return {"id": id, "kind": "head", "label": label, "align_right": right_align,
		"sorted": key != "" and key == sort, "rect": Rect2(x, y, w, 12.0)}

# ------------------------------------------------------------------- press ---

## A reading or header press. Writes the choice through to the save so it is
## the save's, not this run's, and returns true when anything changed.
func press(id: String, save: LeagueSave) -> bool:
	if id.begins_with("tbl:mode:"):
		var wanted := id.substr(9)
		var current: String = mode if mode != "" else COMPACT
		if not MODES.has(wanted) or wanted == current:
			return false
		mode = wanted
		_store(save, META_MODE, mode)
		return true
	if not id.begins_with("tbl:sort:"):
		return false
	var key := id.substr(9)
	if not sortable(key):
		return false
	if key == sort:
		dir = -dir
	else:
		sort = key
		dir = 1 if key == "club" else -1
	_store(save, META_SORT, sort)
	_store(save, META_DIR, "asc" if dir > 0 else "desc")
	return true

func _store(save: LeagueSave, key: String, value: String) -> void:
	if save != null:
		save.put_meta(key, value)

# gd-tools: no cover start

# ------------------------------------------------------------------- paint ---

func draw_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		hints: DateHints) -> void:
	var bold: Font = fonts["bold"]
	UiChrome.wordmark(c, Vector2(24.0, 30.0), 18, bold)
	UiChrome.text(c, Vector2(24.0, 48.0), "LEAGUE TABLE", 12, UiChrome.C_GOLD, bold)
	var date := str(view.get("date", ""))
	var label := FixtureCalendar.day_label(date)
	var parts: Array = []
	if str(view.get("name", "")) != "":
		parts.append(str(view.get("name", "")))
	if label != "":
		parts.append(label)
	UiChrome.text_r(c, vp.x - 24.0, 30.0, " · ".join(PackedStringArray(parts)), 10,
		UiChrome.C_DIM, bold)
	if date != "":
		hints.add(DateHints.strip_right(bold, label, vp.x - 24.0, 30.0, 10), date)
	var y := vp.y - LeagueSheet.BAR_H + 24.0
	# The legend shares the bar with the two reading doors on a wide sheet; a
	# phone sheet has no room there, so it moves up beside the title.
	if vp.x < 620.0:
		_legend(c, vp.x - 24.0, 48.0, fonts, true, true)
	else:
		_legend(c, 350.0, y, fonts, false, false)
		# The sentence only rides the legend when the sheet is wide enough for both.
		if vp.x >= 760.0:
			UiChrome.text_r(c, vp.x - 24.0, y, "TAP A COLUMN TO SORT · COLOURED BAND = PLACE",
				8, UiChrome.C_DIM, fonts["med"])

func _legend(c: CanvasItem, anchor: float, y: float, fonts: Dictionary, narrow: bool,
		from_right: bool) -> void:
	var labels: Array = ["UCL", "UEL", "UECL", "REL"]
	var bands: Array = ["ucl", "uel", "uecl", "relegation"]
	var size := 8
	if not narrow:
		labels = ["UCL", "UEL", "UECL", "RELEGATION"]
		size = 9
	var bold: Font = fonts["bold"]
	var gap := 8.0
	var total := -gap
	for label in labels:
		total += bold.get_string_size(str(label), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + gap
	var x: float = anchor - total if from_right else anchor
	for i in range(labels.size()):
		var label := str(labels[i])
		UiChrome.text(c, Vector2(x, y), label, size, LeagueSheet.zone_color(str(bands[i])), bold)
		x += bold.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + gap

func draw_body(c: CanvasItem, _vp: Vector2, fonts: Dictionary, items: Array,
		_view: Dictionary) -> void:
	for item in items:
		var kind := str(item["kind"])
		if kind == "table_row":
			_draw_row(c, item["rect"], item, fonts)
		elif kind == "head":
			_draw_head(c, item["rect"], item, fonts)
		elif kind == "caption":
			UiChrome.text(c, Vector2((item["rect"] as Rect2).position.x + 2.0,
				(item["rect"] as Rect2).position.y + 8.0), str(item["label"]), 7,
				UiChrome.C_DIM, fonts["bold"])

func _draw_head(c: CanvasItem, rect: Rect2, item: Dictionary, fonts: Dictionary) -> void:
	var size := 9
	if mode != COMPACT:
		size = 8
	var colour: Color = UiChrome.C_GOLD if bool(item["sorted"]) else UiChrome.C_DIM
	var y := rect.position.y + float(size) + 1.0
	if bool(item["align_right"]):
		UiChrome.text_r(c, rect.end.x, y, str(item["label"]), size, colour, fonts["bold"])
	else:
		UiChrome.text(c, Vector2(rect.position.x, y), str(item["label"]), size, colour, fonts["bold"])
	if bool(item["sorted"]):
		c.draw_rect(Rect2(rect.position.x, rect.end.y - 1.0, rect.size.x, 1.0), UiChrome.C_GOLD)

func _draw_row(c: CanvasItem, rect: Rect2, item: Dictionary, fonts: Dictionary) -> void:
	var row: Dictionary = item["row"]
	var band := str(item["zone"])
	if band != "":
		c.draw_rect(Rect2(rect.position.x, rect.position.y + 2.0, 4.0, rect.size.y - 4.0),
			LeagueSheet.zone_color(band))
	var places: Dictionary = item["places"]
	var y := rect.position.y + rect.size.y * 0.5 + 4.0
	UiChrome.text(c, Vector2(float(places["pos_x"]), y), "%d" % int(row["position"]), 10,
		UiChrome.C_DIM, fonts["med"])
	UiChrome.text(c, Vector2(float(places["club_x"]), y),
		LeagueColumns.fit_name(str(row["club_name"]), fonts["bold"],
			12 if mode == COMPACT else 11, float(places["club_w"])),
		12 if mode == COMPACT else 11, UiChrome.C_TEXT, fonts["bold"])
	for col in places["cols"]:
		var key := str(col["key"])
		var points := key == "points"
		UiChrome.text_r(c, float(col["right"]), y, _text(row, key), 10 if points else 9,
			UiChrome.C_TEXT if points else UiChrome.C_SOFT, fonts["bold"] if points else fonts["med"])

static func _text(row: Dictionary, key: String) -> String:
	if key == "gd":
		return "%+d" % cell(row, key)
	return "%d" % cell(row, key)

# gd-tools: no cover end
