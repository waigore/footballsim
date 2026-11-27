class_name LeagueTableView
extends RefCounted

## The league table in its two readings (#72/#74/#102): a compact standings
## strip with the whole overall record (#, club, P W D L GF GA GD PTS) and the
## full sheet that adds the home and away splits, sorted by any column.
##
## Sorting never renumbers the league: every row keeps the official `position`
## the save computed, so the `#` column and the zone bands always show the real
## place (the list order is the player's, the numbers are the league's).
##
## The reading lives here; the sorted column and the direction are the save's
## own choices and live in `LeagueTableSort`, so two saves never share them.
## A save that has never been touched opens on the device default: compact on a
## phone, full on a desktop.
##
## Geometry, sorting and paint only: `LeagueBook` keeps the table pose and hands
## geometry and paint here. The sheet's chrome — title, date hint, zone legend —
## lives in `LeagueTableChrome`, so the rows and the band never crowd each other.

const COMPACT := "compact"
const FULL := "full"
const MODES := [COMPACT, FULL]

const META_MODE := "table_mode"
const META_SORT := LeagueTableSort.META_SORT
const META_DIR := LeagueTableSort.META_DIR

const ROW_H := 22.0
## The pitch a touch sheet lays its club rows on: 48 density points of hit area
## plus the one-unit divider every row gives to the sheet. At the desktop pitch a
## finger covers two clubs and the wrong one opens (#204). A desktop sheet keeps
## its dense reading untouched.
const TAP_ROW_H := 49.0
## Room for the place number before the club name: the zone band at the row's
## edge, the air beside it, and then the digits. Both readings share the compact
## strip's indents, so a full-sheet place number never lands on its band (#308).
const POS_W := LeagueColumns.CLUB_INDENT
## The zone band a filled place paints at the row's own left edge. Geometry, not
## just paint: the place number has to clear it (#308).
const ZONE_BAND_W := 4.0
## The club column never collapses; a name wider than it is shortened instead.
const CLUB_MIN := 150.0
## The league tabs above the column band: one chip per active competition.
const TAB_H := 30.0
## One number box and the air between two of them.
const NUM_W := 28.0
const NUM_GAP := 2.0
## Rows start below the group captions of the full sheet (OVERALL / HOME / AWAY)
## and below the header band itself — a desktop caption there, a full tap target
## on a touch sheet (#204).

## `num` boxes sit on a right-aligned rail; `group` names the caption band the
## full sheet paints above them. `position` is never sortable: `#` is the league.
## Compact is the whole overall record on one line (#102); the full sheet adds
## the home and away splits under it.
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

## Reading on screen ("" until the first layout picks one) and the player's sort.
var mode := ""
var order := LeagueTableSort.new()
## Competition tab on screen. Session state: the reading and the sort are the
## save's shared table prefs, the tab is which league is being read right now.
## Empty means the save's primary league.
var league_tab := ""
## Panel style cache for the tab chips.
var cache := {}
## Club names this table painted, with the strip each one occupies (#107): the
## long press reads it, in the same design space the rows are laid out in.
var names := InterestNames.new()

## Take the reading and the sort the save remembers. Called when the table
## opens, so two saves never share one table's choices.
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

# ------------------------------------------------------------------ layout ---

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
		"rect": LeagueExtra.back_rect()})
	# Two doors rather than one toggle: the gold one is the reading on screen,
	# so the player never has to guess what a press will do.
	items.append({"id": "tbl:mode:" + COMPACT, "kind": "button", "label": "COMPACT",
		"pinned": true, "primary": reading == COMPACT,
		"rect": Rect2(24.0, vp.y - LeagueChrome.BAR_H + 6.0, 104.0, LeagueChrome.BAR_H - 14.0)})
	items.append({"id": "tbl:mode:" + FULL, "kind": "button", "label": "FULL",
		"pinned": true, "primary": reading == FULL,
		"rect": Rect2(134.0, vp.y - LeagueChrome.BAR_H + 6.0, 78.0, LeagueChrome.BAR_H - 14.0)})
	return items

## The row pitch this sheet lays: a touch sheet asks for one club per finger,
## a desktop sheet keeps the dense reading (#204). Read from the pose the screen
## built, so the layout and the hit test can never disagree.
static func row_height(view: Dictionary) -> float:
	return TAP_ROW_H if bool(view.get("touch", false)) else ROW_H

## The reading this sheet draws. With no saved choice the device decides once;
## the resolved value is what a mode press flips.
func _reading(vp: Vector2) -> String:
	if mode == "":
		mode = COMPACT if LeagueChrome.compact(vp) else FULL
	return mode

## Rows in the player's chosen order, each keeping its official position. Ties
## fall back to the official place so a re-sort is never arbitrary. A sort on a
## column the current reading does not show is left for the reading that does:
## the compact strip never sorts by a number the player cannot see.
func ordered(rows: Array) -> Array:
	return order.ordered(rows, columns(mode if mode != "" else COMPACT))

## The narrowest row a reading needs. Compact walks the measured rail
## (`LeagueColumns`), which keeps the whole overall record and a readable club
## name inside a phone sheet; the full sheet walks its own 22 columns from the
## club's right edge.
func _min_row_w(reading: String) -> float:
	if reading == COMPACT:
		return LeagueColumns.min_row(COMPACT_COLS)
	return POS_W + CLUB_MIN + float(numeric(FULL_COLS)) * (NUM_W + NUM_GAP)

## Column rails for a row at this width. Compact keeps `LeagueColumns`, the
## measured layout #71 settled; the full sheet walks the columns from the club
## column's right edge so the whole record fits a phone in landscape. Its left
## edge is the compact strip's own: the place number indented clear of the zone
## band the row paints, then the club name after it (#308).
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

## The league tabs above the table: one per active competition, the one being
## read in gold. The shared prefs (reading, sort) do not change as the tab does.
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

## The tab actually on screen: the stored one when the save still carries that
## league, else the first active competition.
func _current_tab(comps: Array) -> String:
	for comp in comps:
		if str((comp as Dictionary).get("id", "")) == league_tab:
			return league_tab
	return str((comps[0] as Dictionary).get("id", "")) if not comps.is_empty() else ""

## The header is part of the scrolling content, so a column stays above its
## numbers when the sheet is panned sideways and its tap target travels with it.
## Its geometry and paint live in `LeagueTableHead`, which is where the touch
## handhold a header needs (#204) is decided.

# ------------------------------------------------------------------- press ---

## A reading or header press. A reading is this sheet's; a header press belongs
## to the save's sort (`LeagueTableSort`). Both write through to the save so the
## choice is the save's, not this run's; true when anything changed.
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

# ------------------------------------------------------------------- paint ---

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

## The table's club label: the abbreviation — the one season pose that keeps it
## (#168) — falling back to the name only for a row that carries no short form.
static func club_label(row: Dictionary) -> String:
	var abbr := str(row.get("club_abbr", ""))
	return abbr if abbr != "" else str(row.get("club_name", ""))

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
	# A followed club's name is gold here too: the shortlist is the season's, and
	# the table is where a club is found (#104). The table is the one pose that
	# keeps abbreviations (#168): it is a grid of numbers, and the short label
	# leaves the record the room it needs. Every other surface prints the name.
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
