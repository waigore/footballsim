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

static var header_cache := {}

## One header for every league season sheet: BACK top-left, the sheet's title
## in the gold kicker position, and an optional right-hand caption. Continue is
## the only control that ever shares the row, and the hub adds it itself.
## `right` reserves room for a door in the corner so a caption never runs under it.
static func header(c: CanvasItem, vp: Vector2, fonts: Dictionary, title: String,
		caption: String = "", right: float = 0.0) -> void:
	var bold: Font = fonts["bold"]
	var rect := back_rect()
	UiChrome.panel(c, header_cache, rect, UiChrome.C_PANEL_LIGHT, 7)
	UiChrome.text_c(c, rect.get_center().x, rect.position.y + 21.0, "BACK", 12, UiChrome.C_TEXT, bold)
	UiChrome.text(c, Vector2(136.0, 36.0), title.to_upper(), 16, UiChrome.C_GOLD, bold)
	if caption != "":
		UiChrome.text_r(c, vp.x - 24.0 - right, 34.0, caption, 10, UiChrome.C_DIM, bold)
	c.draw_rect(Rect2(24.0, HEADER - 8.0, vp.x - 48.0, 1.0), Color(1, 1, 1, 0.08))

# ------------------------------------------------------------------- stats ---

func stats_layout(vp: Vector2, view: Dictionary) -> Array:
	var items: Array = []
	items.append(back_item())
	var y := HEADER + 14.0
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
		items.append({"id": "", "kind": "note", "label": "No matchdays played yet.",
			"rect": Rect2(24.0, y, vp.x - 48.0, 24.0)})
	for i in range(reports.size()):
		var row: Dictionary = reports[i]
		items.append({"id": "statsday:" + str(row["date"]), "kind": "day", "row": row,
			"rect": Rect2(24.0, y + float(i) * (ROW_H + GAP), vp.x - 48.0, ROW_H)})
	return items

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
			LeagueSheet.draw_button(c, cache, rect, str(item["label"]), bold, bool(item["primary"]))
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
			UiChrome.text_r(c, rect.end.x - 10.0, rect.position.y + 16.0,
				"%d RESULTS" % int(row.get("played", 0)), 9, UiChrome.C_GOLD, bold)

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
		_view: Dictionary) -> void:
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	for item in items:
		var rect: Rect2 = item["rect"]
		var kind := str(item["kind"])
		if kind == "field":
			UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 6, UiChrome.C_GOLD, 1)
			var typed := str(item["value"])
			UiChrome.text(c, Vector2(rect.position.x + 12.0, rect.position.y + 25.0),
				typed if typed != "" else "SEARCH CLUBS", 14,
				UiChrome.C_TEXT if typed != "" else UiChrome.C_DIM, bold)
			c.draw_rect(Rect2(rect.position.x + 14.0 + float(typed.length()) * 8.0, rect.position.y + 10.0,
				2.0, 20.0), UiChrome.C_GOLD)
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
