class_name LeagueExtra
extends RefCounted

## The league sheets that hang off the left panel rather than a season reading:
## Stats (reports and the podium) and Teams of Interest (list + search). The
## season's save/exit dialog is `LeagueSystemSheet`, its own module (#109).
##
## Same contract as the other sheets: `layout()` turns state into rows with
## rects, `draw_*` paints them, and no geometry is invented at paint time.

const HEADER := 58.0
const ROW_H := 34.0
const GAP := 6.0
const FIELD_H := 38.0

var cache := {}
## Dates this sheet painted, read by the screen's weekday overlay (#99).
var hints := DateHints.new()

# ------------------------------------------------------------------ header ---

static func back_rect() -> Rect2:
	return Rect2(24.0, 12.0, 96.0, 32.0)

## The one BACK door in the header lane: every league sheet builds the same row.
static func back_item() -> Dictionary:
	return {"id": "back", "kind": "button", "label": "BACK", "pinned": true,
		"rect": back_rect()}

## The primary door's corner: CONTINUE on the hub, KICK OFF on the pre-match
## briefing. The same header band as BACK, on the other side of it (#163).
static func primary_rect(vp: Vector2, width: float = 140.0) -> Rect2:
	return Rect2(vp.x - 24.0 - width, 12.0, width, 32.0)

## Where a header's title starts: clear of BACK's right edge, so the two never
## share a pixel however long the season's name is.
const TITLE_X := 136.0
const TITLE_SIZE := 16
## The smallest caption the header still paints after the title: a date or kicker
## shortened to less than a line is dropped, not clipped to a stub.
const CAPTION_MIN := 160.0

static var header_cache := {}

## The header band as geometry, so a sheet's title and caption are fitted to the
## lane between BACK and whatever door owns the right corner (#180). A title too
## long for the lane is shortened with an ellipsis; the caption only rides what
## the title leaves, and is dropped when that is too narrow to read.
static func header_band(vp: Vector2, bold: Font, title: String, caption: String = "",
		right: float = 0.0) -> Dictionary:
	var lane_end: float = vp.x - 24.0 - right
	var label: String = title.to_upper()
	var room: float = lane_end - TITLE_X
	var shown: String = "" if room <= 0.0 else LeagueColumns.fit_name(label, bold, TITLE_SIZE, room)
	var title_w: float = UiChrome.text_width(bold, shown, TITLE_SIZE)
	var out := {"title": shown, "title_rect": Rect2(TITLE_X, 20.0, title_w, 16.0),
		"caption": "", "caption_rect": Rect2()}
	if caption == "":
		return out
	# The caption starts only where the title ends, with one gutter between, so
	# neither can be painted through the other.
	var space: float = lane_end - (TITLE_X + title_w + 12.0)
	if space < CAPTION_MIN:
		return out
	var fit: String = LeagueColumns.fit_name(caption, bold, 10, space)
	var caption_w: float = UiChrome.text_width(bold, fit, 10)
	out["caption"] = fit
	out["caption_rect"] = Rect2(lane_end - caption_w, 24.0, caption_w, 14.0)
	return out

## One header for every league season sheet: BACK top-left, the sheet's title
## in the gold kicker position, and an optional right-hand caption. Continue is
## the only control that ever shares the row, and the hub adds it itself.
## `right` reserves room for a door in the corner; the title and caption are
## fitted inside what it leaves (#180). Returns the band it painted, so a date
## caption can register its hint on the strip it really occupies.
static func header(c: CanvasItem, vp: Vector2, fonts: Dictionary, title: String,
		caption: String = "", right: float = 0.0) -> Dictionary:
	var bold: Font = fonts["bold"]
	var rect := back_rect()
	UiChrome.panel(c, header_cache, rect, UiChrome.C_PANEL_LIGHT, 7)
	UiChrome.text_c(c, rect.get_center().x, rect.position.y + 21.0, "BACK", 12, UiChrome.C_TEXT, bold)
	var band := header_band(vp, bold, title, caption, right)
	UiChrome.text(c, Vector2(TITLE_X, 36.0), str(band["title"]), TITLE_SIZE, UiChrome.C_GOLD, bold)
	if str(band["caption"]) != "":
		UiChrome.text_r(c, vp.x - 24.0 - right, 34.0, str(band["caption"]), 10, UiChrome.C_DIM, bold)
	c.draw_rect(Rect2(24.0, HEADER - 8.0, vp.x - 48.0, 1.0), Color(1, 1, 1, 0.08))
	return band

# ------------------------------------------------------------------- stats ---

func stats_layout(vp: Vector2, view: Dictionary) -> Array:
	var items: Array = []
	items.append(back_item())
	var filters: Dictionary = view.get("filters", {})
	var y := HEADER + 10.0
	# Competition filter: ALL, then every active league.
	var chips: Array = [{"id": "", "short": "ALL"}]
	for comp in view.get("competitions", []):
		chips.append({"id": str(comp["id"]), "short": str(comp.get("short", comp["id"]))})
	var gap := 8.0
	var cw: float = minf(150.0, (vp.x - 48.0 - gap * float(chips.size() - 1)) / float(maxf(chips.size(), 1)))
	var x := 24.0
	for chip in chips:
		items.append({"id": "statsleague:" + str(chip["id"]), "kind": "choice",
			"label": str(chip["short"]), "selected": str(filters.get("league", "")) == str(chip["id"]),
			"rect": Rect2(x, y, cw, 30.0)})
		x += cw + gap
	y += 40.0
	# Month filter: the report list narrows to one month, or reads them all.
	items.append({"id": "statsmonth:-1", "kind": "chip", "label": "<",
		"rect": Rect2(24.0, y, 34.0, 28.0)})
	items.append({"id": "", "kind": "caption", "label": _month_label(str(filters.get("month", ""))),
		"rect": Rect2(64.0, y, 130.0, 28.0)})
	items.append({"id": "statsmonth:1", "kind": "chip", "label": ">",
		"rect": Rect2(200.0, y, 34.0, 28.0)})
	# Leader stat door: goals or assists, default all actives.
	items.append({"id": "statsstat:goals", "kind": "chip", "label": "GOALS",
		"selected": str(filters.get("stat", "goals")) == "goals",
		"rect": Rect2(250.0, y, 72.0, 28.0)})
	items.append({"id": "statsstat:assists", "kind": "chip", "label": "ASSISTS",
		"selected": str(filters.get("stat", "goals")) == "assists",
		"rect": Rect2(328.0, y, 78.0, 28.0)})
	y += 38.0
	items.append({"id": "statsteam", "kind": "field", "value": str(filters.get("team", "")),
		"rect": Rect2(24.0, y, vp.x - 48.0, FIELD_H)})
	y += FIELD_H + 12.0
	items.append({"id": "stats:reports", "kind": "door", "label": "MATCHDAY REPORTS", "primary": true,
		"rect": Rect2(24.0, y, minf(300.0, vp.x - 48.0), 44.0)})
	if bool(view.get("complete", false)):
		items.append({"id": "stats:podium", "kind": "door", "label": "PODIUM", "primary": false,
			"rect": Rect2(24.0 + minf(300.0, vp.x - 48.0) + 12.0, y, 160.0, 44.0)})
	y += 58.0
	items.append({"id": "", "kind": "caption", "label": "PLAYED MATCHDAYS",
		"rect": Rect2(24.0, y, vp.x - 48.0, 20.0)})
	y += 26.0
	var reports: Array = view.get("reports", [])
	if reports.is_empty():
		items.append({"id": "", "kind": "note", "label": "No matchdays match these filters.",
			"rect": Rect2(24.0, y, vp.x - 48.0, 24.0)})
	for i in range(reports.size()):
		var row: Dictionary = reports[i]
		items.append({"id": "statsday:" + str(row["date"]), "kind": "day", "row": row,
			"rect": Rect2(24.0, y + float(i) * (ROW_H + GAP), vp.x - 48.0, ROW_H)})
	y += float(reports.size()) * (ROW_H + GAP) + 10.0
	items.append({"id": "", "kind": "caption",
		"label": "LEADERS  ·  %s" % str(filters.get("stat", "goals")).to_upper(),
		"rect": Rect2(24.0, y, vp.x - 48.0, 20.0)})
	y += 24.0
	var leaders: Array = view.get("leaders", [])
	for i in range(leaders.size()):
		items.append({"id": "", "kind": "leader", "row": leaders[i], "rank": i + 1,
			"rect": Rect2(24.0, y + float(i) * 24.0, vp.x - 48.0, 23.0)})
	return items

## A league group's heading on a mixed day: the competition name, its gameweek,
## and a rule line so two groups never blur into one list (#189).
static func draw_league_head(c: CanvasItem, rect: Rect2, competition_id: String,
		matchday: int, fonts: Dictionary) -> void:
	var name: String = PLRepository.shared().competition_name(competition_id)
	var text := "%s  ·  GW %d" % [name, matchday]
	UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 12.0),
		text, 10, UiChrome.C_GOLD, fonts["bold"])
	var width := UiChrome.text_width(fonts["bold"], "%s  ·  GW 00" % name, 10)
	c.draw_rect(Rect2(rect.position.x + width + 10.0, rect.position.y + 8.0,
		maxf(rect.size.x - width - 10.0, 0.0), 1.0), Color(1, 1, 1, 0.10))

## How many competitions a day's fixtures span: a head is only worth its line
## when the list really holds two leagues.
static func distinct_competitions(fixtures: Array) -> int:
	var ids := {}
	for fx in fixtures:
		ids[str(fx.get("competition_id", ""))] = true
	return ids.size()

static func _month_label(month: String) -> String:
	if month == "":
		return "ALL MONTHS"
	return LeagueMonth.label(month)

# gd-tools: no cover start

func draw_stats_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		_hints: DateHints) -> void:
	header(c, vp, fonts, "STATS", str(view.get("name", "")))

func draw_stats_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, items: Array,
		_view: Dictionary) -> void:
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	for item in items:
		var rect: Rect2 = item["rect"]
		var kind := str(item["kind"])
		if kind == "door":
			UiChrome.button(c, cache, rect, str(item["label"]), bold, bool(item["primary"]))
		elif kind == "choice" or kind == "chip":
			var on := bool(item.get("selected", false))
			UiChrome.panel(c, cache, rect,
				UiChrome.C_GOLD.darkened(0.1) if on else UiChrome.C_PANEL, 6,
				UiChrome.C_GOLD if on else UiChrome.C_BORDER, 1)
			UiChrome.text_c(c, rect.get_center().x, rect.position.y + 19.0,
				str(item["label"]), 10, Color(0.06, 0.06, 0.05) if on else UiChrome.C_SOFT, bold)
		elif kind == "field":
			UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 6, UiChrome.C_GOLD, 1)
			var typed := str(item["value"])
			UiChrome.text(c, Vector2(rect.position.x + 12.0, rect.position.y + 25.0),
				typed if typed != "" else "FILTER TEAMS (TYPE A CLUB)", 12,
				UiChrome.C_TEXT if typed != "" else UiChrome.C_DIM, bold)
		elif kind == "caption":
			UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 14.0), str(item["label"]), 10,
				UiChrome.C_DIM, bold)
		elif kind == "note":
			UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 14.0), str(item["label"]), 11,
				UiChrome.C_SOFT, med)
		elif kind == "day":
			var row: Dictionary = item["row"]
			UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 6)
			UiChrome.text(c, Vector2(rect.position.x + 12.0, rect.position.y + 16.0),
				"MATCHDAY %d" % int(row.get("matchday", 1)), 12, UiChrome.C_TEXT, bold)
			UiChrome.text(c, Vector2(rect.position.x + 132.0, rect.position.y + 16.0),
				str(row.get("label", row.get("date", ""))), 10, UiChrome.C_DIM, med)
			var leagues: Array = row.get("leagues", [])
			if not leagues.is_empty():
				UiChrome.text(c, Vector2(rect.position.x + 250.0, rect.position.y + 16.0),
					_league_marks(leagues), 9, UiChrome.C_GOLD, bold)
			UiChrome.text_r(c, rect.end.x - 10.0, rect.position.y + 16.0,
				"%d RESULTS" % int(row.get("played", 0)), 9, UiChrome.C_GOLD, bold)
		elif kind == "leader":
			var leader: Dictionary = item["row"]
			var rank := int(item["rank"])
			UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 15.0), "%d" % rank, 10,
				UiChrome.C_DIM, med)
			UiChrome.text(c, Vector2(rect.position.x + 24.0, rect.position.y + 15.0),
				str(leader.get("name", "")), 11, UiChrome.C_TEXT, bold)
			UiChrome.text(c, Vector2(rect.position.x + 260.0, rect.position.y + 15.0),
				"%s  ·  %s" % [str(leader.get("abbr", "")), _comp_short(str(leader.get("competition_id", "")))],
				9, UiChrome.C_DIM, med)
			UiChrome.text_r(c, rect.end.x - 10.0, rect.position.y + 15.0,
				str(int(leader.get("stat_value", leader.get("goals", 0)))), 11, UiChrome.C_GOLD, bold)

static func _league_marks(leagues: Array) -> String:
	var out: Array = []
	for cid in leagues:
		out.append(_comp_short(str(cid)))
	return "  ·  ".join(PackedStringArray(out))

static func _comp_short(competition_id: String) -> String:
	var row := PLRepository.shared().competition(competition_id)
	return str(row.get("short_name", competition_id))

# gd-tools: no cover end

# ---------------------------------------------------------------- interest ---

func interest_layout(vp: Vector2, view: Dictionary) -> Array:
	var items: Array = []
	items.append(back_item())
	var y := HEADER + 10.0
	items.append({"id": "interest:search", "kind": "field", "value": str(view.get("query", "")),
		"rect": Rect2(24.0, y, vp.x - 48.0, FIELD_H)})
	y += FIELD_H + 8.0
	var results: Array = view.get("results", [])
	for i in range(results.size()):
		var club: Dictionary = results[i]
		items.append({"id": "interest:add:" + str(club["id"]), "kind": "result", "club": club,
			"rect": Rect2(24.0, y + float(i) * (ROW_H + GAP), vp.x - 48.0, ROW_H)})
	if not results.is_empty():
		y += float(results.size()) * (ROW_H + GAP) + 8.0
	items.append({"id": "", "kind": "caption", "label": "YOUR CLUBS",
		"rect": Rect2(24.0, y, vp.x - 48.0, 20.0)})
	y += 24.0
	var clubs: Array = view.get("clubs", [])
	if clubs.is_empty():
		items.append({"id": "", "kind": "note",
			"label": "No teams yet — search above, or long-press a team name anywhere.",
			"rect": Rect2(24.0, y, vp.x - 48.0, 24.0)})
	for i in range(clubs.size()):
		var club: Dictionary = clubs[i]
		var row := Rect2(24.0, y + float(i) * (ROW_H + GAP), vp.x - 48.0, ROW_H)
		items.append({"id": "club:" + str(club["id"]), "kind": "club", "club": club, "rect": row})
		items.append({"id": "interest:remove:" + str(club["id"]), "kind": "remove",
			"rect": Rect2(row.end.x - 96.0, row.position.y + 4.0, 88.0, ROW_H - 8.0)})
	return items

# gd-tools: no cover start

func draw_interest_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		_hints: DateHints) -> void:
	header(c, vp, fonts, "TEAMS OF INTEREST", "%d MARKED" % (view.get("clubs", []) as Array).size())

func draw_interest_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, items: Array,
		view: Dictionary) -> void:
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	var live := str(view.get("focus", "")) == LeagueFieldFocus.INTEREST
	for item in items:
		var rect: Rect2 = item["rect"]
		var kind := str(item["kind"])
		if kind == "field":
			UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 6, UiChrome.C_GOLD, 1)
			var typed := str(item["value"])
			UiChrome.text(c, Vector2(rect.position.x + 12.0, rect.position.y + 25.0),
				typed if typed != "" else "SEARCH CLUBS", 14,
				UiChrome.C_TEXT if typed != "" else UiChrome.C_DIM, bold)
			# The caret is the keyboard's own mark: it shows while the field
			# owns the IME and not a moment longer (#201).
			LeagueFieldFocus.caret(c, rect, typed, bold, 14, live)
		elif kind == "caption":
			UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 14.0), str(item["label"]), 10,
				UiChrome.C_DIM, bold)
		elif kind == "note":
			UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 15.0), str(item["label"]), 11,
				UiChrome.C_SOFT, med)
		elif kind == "result":
			var club: Dictionary = item["club"]
			UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 6, Color(0.96, 0.78, 0.30, 0.35), 1)
			_draw_swatch(c, rect, club)
			UiChrome.text(c, Vector2(rect.position.x + 18.0, rect.position.y + 22.0),
				str(club["name"]), 13, UiChrome.C_TEXT, bold)
			UiChrome.text_r(c, rect.end.x - 12.0, rect.position.y + 21.0, "ADD  +", 10, UiChrome.C_GOLD, bold)
		elif kind == "club":
			var club: Dictionary = item["club"]
			UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 6)
			_draw_swatch(c, rect, club)
			UiChrome.text(c, Vector2(rect.position.x + 18.0, rect.position.y + 22.0),
				str(club["name"]), 13, UiChrome.C_GOLD, bold)
			UiChrome.text(c, Vector2(rect.position.x + 18.0, rect.position.y + 33.0),
				str(club["abbr"]), 8, UiChrome.C_DIM, med)
		elif kind == "remove":
			UiChrome.panel(c, cache, rect, UiChrome.C_PANEL_LIGHT, 5, UiChrome.C_BORDER, 1)
			UiChrome.text_c(c, rect.get_center().x, rect.position.y + 18.0, "REMOVE", 9,
				UiChrome.C_SOFT, bold)

func _draw_swatch(c: CanvasItem, rect: Rect2, club: Dictionary) -> void:
	var colour = club.get("color", UiChrome.C_GOLD)
	c.draw_rect(Rect2(rect.position.x, rect.position.y + 4.0, 3.0, rect.size.y - 8.0), colour)

# gd-tools: no cover end
