class_name LeaguePlanSheet
extends RefCounted

## Today's plan: the fixture list the season hub prints, each row a result block
## once played and the planner's line while pending.
##
## It was half of `LeagueSheet`'s body — three row grammars sharing one paint
## method behind a kind switch, and the live file in the league UI. Split out,
## this sheet owns the plan and its rows, and the hub keeps the pose: the chrome,
## the chips and the doors. On a mixed day the rows group under a league heading
## (#189), so two leagues never read as one interleaved list.
##
## Same contract as the other sheets: `layout()` turns the plan into rows with
## rects, `draw()` paints exactly those rects. Geometry is the hub's payload, so
## it stays in the hub; nothing here calls the sim.

var cache := {}
## Club names this sheet painted, with the strip each one occupies (#107): the
## screen's long press reads them. Design space, like the rows.
var names := InterestNames.new()

## Lay today's plan down one column from `left` to `right`, starting at `top`,
## marking the clubs on the shortlist `interest`.
## The plan's rows carry the shortlist's mark on a followed club's game (#104),
## so a headless test reads it from the row itself.
static func layout(plan: Array, interest: Dictionary, left: float, right: float,
		top: float) -> Array:
	var items: Array = []
	var y := top
	var last_comp := ""
	var multi := _leagues(plan) > 1
	for fx in plan:
		# A new league on a mixed day opens its own group: the hub reads one
		# league's fixtures, then the other's, never one interleaved list.
		var comp := str(fx.get("competition_id", ""))
		if multi and comp != last_comp:
			last_comp = comp
			items.append({"id": "", "kind": "league_head",
				"rect": Rect2(left, y, right - left, 18.0),
				"competition": comp, "matchday": int(fx.get("matchday", 1))})
			y += 18.0 + LeagueChrome.ROW_GAP
		# A played row is a result block: the score line, both full names and
		# each side's events under its own name (#168). A pending row keeps the
		# planner's one line.
		var h: float = maxf(LeagueChrome.ROW_H, LeagueBlock.height(fx))
		var row := Rect2(left, y, right - left, h)
		items.append({"id": "fixture:" + str(fx["id"]), "kind": "row", "rect": row,
			"fixture": fx,
			"home_ink": LeagueInterestMark.ink(interest, str(fx.get("home_club_id", ""))),
			"away_ink": LeagueInterestMark.ink(interest, str(fx.get("away_club_id", "")))})
		# A played row is a result, not a plan: no chip to press, the score takes
		# the chip's place and a tap opens the report (#124).
		if str(fx.get("status", "")) != "played":
			var chip := Rect2(row.end.x - 72.0, y + 2.0, 68.0, LeagueChrome.ROW_H - 4.0)
			# A followed club's game is on Watch because of the shortlist, not
			# because of this chip: it states the rule and carries no door of its
			# own, so a press falls through to the row and opens the match (#104).
			var followed := LeagueInterestMark.follows(interest, fx)
			items.append({"id": "" if followed else "toggle:" + str(fx["id"]), "kind": "chip",
				"rect": chip, "fixture": fx, "followed": followed})
		y += h + LeagueChrome.ROW_GAP
	return items

## How many competitions a day's plan spans: a heading is only worth its line
## when the list really holds two leagues.
static func _leagues(plan: Array) -> int:
	var ids := {}
	for fx in plan:
		ids[str((fx as Dictionary).get("competition_id", ""))] = true
	return ids.size()

# gd-tools: no cover start

## Paint the plan rows this sheet laid out.
func draw(c: CanvasItem, items: Array, fonts: Dictionary) -> void:
	names.clear()
	var bold: Font = fonts["bold"]
	for item in items:
		var rect: Rect2 = item["rect"]
		var kind := str(item["kind"])
		if kind == "league_head":
			LeagueExtra.draw_league_head(c, rect, str(item.get("competition", "")),
				int(item.get("matchday", 1)), fonts)
		elif kind == "row":
			LeaguePlanRows.paint_fixture(c, rect, item["fixture"], fonts, cache, names,
				item["home_ink"], item["away_ink"])
		elif kind == "chip" and item.get("fixture") is Dictionary:
			# Only a planned fixture's chip draws here: the pinned SUGGEST WATCHES
			# chip is the hub's own chrome.
			if bool(item.get("followed", false)):
				LeagueInterestMark.chip(c, cache, rect, bold)
			else:
				LeaguePlanRows.paint_toggle(c, rect, item["fixture"], cache, bold)

# gd-tools: no cover end
