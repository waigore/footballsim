class_name LeaguePodiumSheet
extends RefCounted

## The season-complete podium: champions, Europe / promotion places, relegated
## clubs and the inter-league relegation tie. Geometry and paint only —
## `LeagueBook` keeps the pose names the screen already calls.
##
## One block per active competition when the summary carries them; a single-
## league save mirrors its one league at the top.

const HEADER := LeagueChrome.HEADER
const BAR_H := LeagueChrome.BAR_H

## Dates this reading painted (#99). Shared with the book so a weekday bubble
## reads the strips the podium really painted.
var hints := DateHints.new()

func layout(vp: Vector2, view: Dictionary) -> Array:
	var items: Array = []
	## The summary is painted text rather than rows, so a bare extent row carries
	## its height into the scroll window.
	items.append({"id": "", "kind": "extent",
		"rect": Rect2(24.0, HEADER, vp.x - 48.0, frame_height(view))})
	items.append(LeagueExtra.back_item())
	items.append({"id": "table", "kind": "button", "label": "TABLE", "primary": false, "pinned": true,
		"rect": Rect2(24.0, vp.y - BAR_H + 6.0, 130.0, BAR_H - 14.0)})
	items.append({"id": "menu", "kind": "button", "label": "MAIN MENU", "primary": true, "pinned": true,
		"rect": Rect2(24.0 + 142.0, vp.y - BAR_H + 6.0, 170.0, BAR_H - 14.0)})
	return items

## How tall the podium summary paints below the header, so the body can size to
## text that is not made of rows. One block per active competition.
func frame_height(view: Dictionary) -> float:
	var summary: Dictionary = view.get("summary", {})
	if summary.is_empty():
		return 0.0
	var h := 0.0
	var summary_data: Dictionary = view.get("summary", {})
	var brackets: Dictionary = summary_data.get("playoffs", {})
	for section in sections(summary):
		var section_rules: Dictionary = section.get("rules", view.get("rules", {}))
		h += 30.0
		h += 18.0 + 44.0 + 24.0 + 16.0
		h += 16.0 * float(mini((section["europe"] as Array).size(), 6))
		h += 6.0 + 16.0
		h += 16.0 * float((section["relegated"] as Array).size())
		# A promoting tier paints its promotion block — the automatic places and
		# the play-off places they hand to the bracket (#260).
		var up := _promoted_count(section, section_rules)
		if up > 0:
			h += 6.0 + 16.0 + 16.0 * float(up)
		# And its play-off bracket reads as one line in its own block (#260).
		if brackets.has(str(section.get("id", ""))):
			h += 6.0 + 16.0
		h += 12.0
	if not (summary.get("relegation", {}) as Dictionary).is_empty():
		h += 8.0 + 16.0
	return h + 8.0

## The podium's blocks: every active league when the summary carries them, or
## the one league a single-league save mirrors at the top.
static func sections(summary: Dictionary) -> Array:
	var out: Array = summary.get("competitions", [])
	if out.is_empty() and not summary.is_empty():
		out = [summary]
	return out

## How many places a promoting tier paints: its automatic places plus the
## play-off places the bracket draws from, never more than the table holds.
static func _promoted_count(section: Dictionary, rules: Dictionary) -> int:
	var up := int(rules.get("promotion_places", 0)) + int(rules.get("promotion_playoff_places", 0))
	var rows: Array = section.get("table", [])
	return up if rows.is_empty() else mini(up, rows.size())

## Paste `body` into the paint path so the first painted frame reuses the
## `_draw` call already entered (see docs/testing.md).
func _paint_band(c: CanvasItem, body: Callable) -> void:
	body.call(c)

# gd-tools: no cover start

func draw_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		_hints: DateHints) -> void:
	LeagueExtra.header(c, vp, fonts, "SEASON COMPLETE", str(view.get("name", "")))

func draw_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, _items: Array, view: Dictionary) -> void:
	_paint_band(c, _draw_body.bind(vp, fonts, view))

func _draw_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary) -> void:
	hints.clear()
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	var summary: Dictionary = view.get("summary", {})
	var brackets: Dictionary = summary.get("playoffs", {})
	var y := HEADER + 6.0
	if summary.is_empty():
		return
	for section in sections(summary):
		var section_rules: Dictionary = section.get("rules", view.get("rules", {}))
		UiChrome.text(c, Vector2(24.0, y + 12.0), str(section.get("name", section.get("short", ""))).to_upper(),
			12, UiChrome.C_GOLD, bold)
		c.draw_rect(Rect2(24.0, y + 18.0, vp.x - 48.0, 1.0), Color(1, 1, 1, 0.10))
		y += 30.0
		UiChrome.text(c, Vector2(24.0, y), "CHAMPIONS", 10, UiChrome.C_DIM, bold)
		UiChrome.text(c, Vector2(24.0, y + 30.0), str(section["champion"]["club"]), 30, UiChrome.C_GOLD, bold)
		UiChrome.text_r(c, vp.x - 24.0, y + 30.0, "%d PTS" % int(section["champion"]["points"]),
			14, UiChrome.C_TEXT, bold)
		y += 44.0
		UiChrome.text(c, Vector2(24.0, y), "RUNNER-UP  %s · %d PTS" % [str(section["runner_up"]["club"]),
			int(section["runner_up"]["points"])], 12, UiChrome.C_SOFT, bold)
		y += 24.0
		# A second tier has no European places; its band is promotion (#240).
		var section_up := _promoted_count(section, section_rules)
		if (section["europe"] as Array).is_empty() and section_up > 0:
			_paint_promoted(c, vp, section, section_up, y, bold, med)
			y += 16.0 + 16.0 * float(section_up)
		else:
			UiChrome.text(c, Vector2(24.0, y), "EUROPEAN PLACES", 10, UiChrome.C_DIM, bold)
			y += 16.0
			var zone_rows: Array = section["europe"]
			for i in range(mini(zone_rows.size(), 6)):
				var row: Dictionary = zone_rows[i]
				var club := _club_row(section, str(row["zone"]))
				var band := LeagueRules.zone(int(row["position"]), section_rules)
				c.draw_rect(Rect2(24.0, y + 2.0, 3.0, 12.0), LeagueChrome.zone_color(band))
				UiChrome.text(c, Vector2(32.0, y + 12.0), "%d" % int(row["position"]), 10, UiChrome.C_DIM, med)
				UiChrome.text(c, Vector2(54.0, y + 12.0), str(row["club"]), 11, UiChrome.C_TEXT, med)
				UiChrome.text_r(c, vp.x - 24.0, y + 12.0, str(club.get("points", "")), 10, UiChrome.C_SOFT, bold)
				y += 16.0
		# This league's play-off bracket, beside the places it decided (#260).
		var bracket: Dictionary = brackets.get(str(section.get("id", "")), {})
		if not bracket.is_empty():
			y += 6.0
			UiChrome.text(c, Vector2(24.0, y + 12.0), "PLAY-OFFS  %s" % str(bracket.get("text", "")),
				10, UiChrome.C_GOLD, bold)
			y += 16.0
		y += 6.0
		UiChrome.text(c, Vector2(24.0, y), "RELEGATED", 10, UiChrome.C_DIM, bold)
		y += 16.0
		for row in section["relegated"]:
			UiChrome.text(c, Vector2(32.0, y + 12.0), "%d" % int(row["position"]), 10, UiChrome.C_DIM, med)
			UiChrome.text(c, Vector2(54.0, y + 12.0), str(row["club"]), 11, UiChrome.C_DANGER, med)
			y += 16.0
		var scorers: Array = section.get("top_scorers", [])
		if not scorers.is_empty():
			UiChrome.text_r(c, vp.x - 24.0, y + 12.0, "TOP SCORER  %s (%d)" % [str(scorers[0]["name"]),
				int(scorers[0]["goals"])], 11, UiChrome.C_SOFT, bold)
		y += 12.0
	# One Relegation block under both tiers: the tie is one match, not a row of
	# either league's podium.
	var tie: Dictionary = summary.get("relegation", {})
	if not tie.is_empty():
		UiChrome.text(c, Vector2(24.0, y + 8.0), "RELEGATION  %s" % str(tie.get("text", "")),
			10, UiChrome.C_GOLD, bold)
		y += 16.0

## The promoting side of the graph: a second tier's top places, the automatic
## ones and the play-off places under them marked as the bracket (#260).
func _paint_promoted(c: CanvasItem, vp: Vector2, section: Dictionary, up: int,
		y: float, bold: Font, med: Font) -> void:
	UiChrome.text(c, Vector2(24.0, y), "PROMOTION", 10, UiChrome.C_DIM, bold)
	var rows: Array = section.get("table", [])
	var auto := int((section.get("rules", {}) as Dictionary).get("promotion_places", 0))
	for i in range(mini(up, rows.size())):
		var row: Dictionary = rows[i]
		var band := "promotion" if i < auto else "playoff"
		var cy := y + 16.0 + 16.0 * float(i)
		c.draw_rect(Rect2(24.0, cy + 2.0, 3.0, 12.0), LeagueChrome.zone_color(band))
		UiChrome.text(c, Vector2(32.0, cy + 12.0), "%d" % (i + 1), 10, UiChrome.C_DIM, med)
		UiChrome.text(c, Vector2(54.0, cy + 12.0), str(row.get("club_name", "")), 11, UiChrome.C_TEXT, med)
		UiChrome.text_r(c, vp.x - 24.0, cy + 12.0, str(row.get("points", "")), 10, UiChrome.C_SOFT, bold)

func _club_row(section: Dictionary, club_id: String) -> Dictionary:
	for row in section.get("table", []):
		if str(row["club_id"]) == club_id:
			return row
	return {}

# gd-tools: no cover end
