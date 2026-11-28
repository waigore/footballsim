class_name LeagueTableView
extends RefCounted


const COMPACT := "compact"
const FULL := "full"
const MODES := [COMPACT, FULL]

const META_MODE := "table_mode"
const META_SORT := LeagueTableSort.META_SORT
const META_DIR := LeagueTableSort.META_DIR

const ROW_H := 22.0


const TAP_ROW_H := 49.0


const POS_W := LeagueColumns.CLUB_INDENT


const ZONE_BAND_W := 4.0

const CLUB_MIN := 150.0

const TAB_H := 30.0

const NUM_W := 28.0
const NUM_GAP := 2.0


const COMPACT_COLS := LeagueColumns.COMPACT_COLS

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


var mode := ""
var order := LeagueTableSort.new()


var league_tab := ""

var cache := {}


var names := InterestNames.new()


func attach(save: LeagueSave) -> void:
	mode = ""
	league_tab = ""
	if save == null:
		order.attach(null)
		return
	var saved_mode := str(save.read_meta().get(META_MODE, ""))
	mode = saved_mode if MODES.has(saved_mode) else ""
	order.attach(save)

static func columns(reading: String) -> Array:
	return FULL_COLS if reading == FULL else COMPACT_COLS

static func numeric(cols: Array) -> int:
	var count := 0
	for col in cols:
		if bool(col["num"]):
			count += 1
	return count


func layout(vp: Vector2, view: Dictionary) -> Array:
	var reading := _reading(vp)
	var rows := order.ordered(view.get("table", []), columns(reading))
	var row_h := row_height(view)
	var row_w := maxf(vp.x - 48.0, _min_row_w(reading))
	var places := _places(Rect2(24.0, 0.0, row_w, row_h))
	var comps: Array = view.get("competitions", [])
	var tab_h: float = TAB_H if comps.size() > 1 else 0.0
	var touch := bool(view.get("touch", false))
	var top: float = LeagueTableHead.rows_top(reading == FULL, touch, tab_h)
	var items: Array = []
	if tab_h > 0.0:
		items.append_array(_tabs(comps, vp))
	items.append_array(LeagueTableHead.cells(places, reading == FULL, order.key, touch, tab_h))
	var interest := LeagueInterestMark.set_of(view.get("interests", []))
	for i in range(rows.size()):
		items.append({
			"id": "club:" + str(rows[i]["club_id"]), "kind": "table_row", "row": rows[i],
			"zone": LeagueRules.zone(int(rows[i]["position"]), view.get("rules", {})),
			"rect": Rect2(24.0, top + float(i) * row_h, row_w, row_h - 1.0), "places": places,
			"interested": interest.has(str(rows[i]["club_id"])),
		})
	items.append({"id": "back", "kind": "button", "label": "BACK", "pinned": true,
		"rect": LeagueExtra.back_rect(touch)})


	items.append({"id": "tbl:mode:" + COMPACT, "kind": "button", "label": "COMPACT",
		"pinned": true, "primary": reading == COMPACT,
		"rect": Rect2(24.0, vp.y - LeagueChrome.BAR_H + 6.0, 104.0, LeagueChrome.BAR_H - 14.0)})
	items.append({"id": "tbl:mode:" + FULL, "kind": "button", "label": "FULL",
		"pinned": true, "primary": reading == FULL,
		"rect": Rect2(134.0, vp.y - LeagueChrome.BAR_H + 6.0, 78.0, LeagueChrome.BAR_H - 14.0)})
	return items


static func row_height(view: Dictionary) -> float:
	return TAP_ROW_H if bool(view.get("touch", false)) else ROW_H


func _reading(vp: Vector2) -> String:
	if mode == "":
		mode = COMPACT if LeagueChrome.compact(vp) else FULL
	return mode


func ordered(rows: Array) -> Array:
	return order.ordered(rows, columns(mode if mode != "" else COMPACT))


func _min_row_w(reading: String) -> float:
	if reading == COMPACT:
		return LeagueColumns.min_row(COMPACT_COLS)
	return POS_W + CLUB_MIN + float(numeric(FULL_COLS)) * (NUM_W + NUM_GAP)


func _places(row: Rect2) -> Dictionary:
	if mode == COMPACT:
		return LeagueColumns.of(row, COMPACT_COLS)
	var pos_x := row.position.x + LeagueColumns.POS_INDENT
	var club_x := row.position.x + POS_W
	var club_w := row.size.x - POS_W - float(numeric(FULL_COLS)) * (NUM_W + NUM_GAP)
	var out := {"pos_x": pos_x, "club_x": club_x, "club_w": club_w, "cols": []}
	var x := club_x + club_w
	for col in FULL_COLS:
		if bool(col["num"]):
			out["cols"].append({"key": str(col["key"]), "label": str(col["label"]),
				"right": x + NUM_W, "w": NUM_W, "group": str(col.get("group", ""))})
			x += NUM_W + NUM_GAP
	return out


func _tabs(comps: Array, vp: Vector2) -> Array:
	var items: Array = []
	var current := _current_tab(comps)
	var gap := 8.0
	var w: float = minf(180.0,
		(vp.x - 48.0 - gap * float(comps.size() - 1)) / float(maxi(comps.size(), 1)))
	var x := 24.0
	for comp in comps:
		var cid := str((comp as Dictionary).get("id", ""))
		var on := cid == current
		items.append({"id": "tbl:league:" + cid, "kind": "chip",
			"label": str((comp as Dictionary).get("short", cid)),
			"selected": on, "rect": Rect2(x, LeagueChrome.HEADER + 2.0, w, 24.0)})
		x += w + gap
	return items


func _current_tab(comps: Array) -> String:
	for comp in comps:
		if str((comp as Dictionary).get("id", "")) == league_tab:
			return league_tab
	return str((comps[0] as Dictionary).get("id", "")) if not comps.is_empty() else ""


func press(id: String, save: LeagueSave) -> bool:
	if id.begins_with("tbl:league:"):
		var tab := id.substr(11)
		if tab == league_tab:
			return false
		league_tab = tab
		return true
	if id.begins_with("tbl:sort:"):
		return order.press(id.substr(9), save)
	if not id.begins_with("tbl:mode:"):
		return false
	var wanted := id.substr(9)
	var current: String = mode if mode != "" else COMPACT
	if not MODES.has(wanted) or wanted == current:
		return false
	mode = wanted
	_store(save, META_MODE, mode)
	return true

func _store(save: LeagueSave, key: String, value: String) -> void:
	if save != null:
		save.put_meta(key, value)

# gd-tools: no cover start


func draw_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		hints: DateHints) -> void:
	LeagueTableChrome.draw(c, vp, fonts, view, hints)

func draw_body(c: CanvasItem, _vp: Vector2, fonts: Dictionary, items: Array,
		_view: Dictionary, strips: InterestNames = null) -> void:
	if strips != null:
		strips.clear()
	for item in items:
		var kind := str(item["kind"])
		if kind == "table_row":
			_draw_row(c, item["rect"], item, fonts, strips)
		elif kind == "head":
			LeagueTableHead.draw(c, item["rect"], item, fonts, mode == COMPACT)
		elif kind == "caption":
			UiChrome.text(c, Vector2((item["rect"] as Rect2).position.x + 2.0,
				(item["rect"] as Rect2).position.y + 8.0), str(item["label"]), 7,
				UiChrome.C_DIM, fonts["bold"])
		elif kind == "chip":
			var on := bool(item.get("selected", false))
			UiChrome.panel(c, cache, item["rect"],
				UiChrome.C_GOLD.darkened(0.1) if on else UiChrome.C_PANEL, 5,
				UiChrome.C_GOLD if on else UiChrome.C_BORDER, 1)
			UiChrome.text_c(c, (item["rect"] as Rect2).get_center().x,
				(item["rect"] as Rect2).position.y + 16.0, str(item["label"]), 10,
				Color(0.06, 0.06, 0.05) if on else UiChrome.C_SOFT, fonts["bold"])


static func club_label(row: Dictionary) -> String:
	return LeagueColumns.club_label(row)

func _draw_row(c: CanvasItem, rect: Rect2, item: Dictionary, fonts: Dictionary,
		strips: InterestNames = null) -> void:
	var row: Dictionary = item["row"]
	var band := str(item["zone"])
	if band != "":
		c.draw_rect(Rect2(rect.position.x, rect.position.y + 2.0, ZONE_BAND_W, rect.size.y - 4.0),
			LeagueChrome.zone_color(band))
	var places: Dictionary = item["places"]
	var y := rect.position.y + rect.size.y * 0.5 + 4.0
	UiChrome.text(c, Vector2(float(places["pos_x"]), y), "%d" % int(row["position"]), 10,
		UiChrome.C_DIM, fonts["med"])


	var size: int = 12 if mode == COMPACT else 11
	var club_x: float = float(places["club_x"])
	var label: String = LeagueColumns.fit_name(club_label(row), fonts["bold"], size,
		float(places["club_w"]))
	UiChrome.text(c, Vector2(club_x, y), label, size,
		UiChrome.C_GOLD if bool(item.get("interested", false)) else UiChrome.C_TEXT, fonts["bold"])
	if strips != null:
		strips.add(InterestNames.strip(fonts["bold"], label, club_x, y, size), str(row["club_id"]))
	for col in places["cols"]:
		var key := str(col["key"])
		var points := key == "points"
		UiChrome.text_r(c, float(col["right"]), y, LeagueColumns.text(row, key), 10 if points else 9,
			UiChrome.C_TEXT if points else UiChrome.C_SOFT, fonts["bold"] if points else fonts["med"])

# gd-tools: no cover end
