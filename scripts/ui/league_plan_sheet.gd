class_name LeaguePlanSheet
extends RefCounted


var cache := {}


var names := InterestNames.new()


static func layout(plan: Array, interest: Dictionary, left: float, right: float,
		top: float, touch := false) -> Array:
	var items: Array = []
	var y := top
	var last_comp := ""
	var row_h: float = LeagueChrome.plan_row_h(touch)
	var gap: float = LeagueChrome.plan_row_gap(touch)
	for fx in plan:


		var comp := str(fx.get("competition_id", ""))


		if comp != "" and comp != last_comp:
			last_comp = comp
			items.append({"id": "", "kind": "league_head",
				"rect": Rect2(left, y, right - left, 18.0),
				"competition": comp, "matchday": int(fx.get("matchday", 1))})
			y += 18.0 + gap


		var h: float = maxf(row_h, LeagueBlock.height(fx))
		var row := Rect2(left, y, right - left, h)
		items.append({"id": "fixture:" + str(fx["id"]), "kind": "row", "rect": row,
			"fixture": fx,
			"home_ink": LeagueInterestMark.ink(interest, str(fx.get("home_club_id", ""))),
			"away_ink": LeagueInterestMark.ink(interest, str(fx.get("away_club_id", "")))})


		if str(fx.get("status", "")) != "played":
			var chip := Rect2(row.end.x - 72.0, y + 2.0, 68.0, h - 4.0)


			var followed := LeagueInterestMark.follows(interest, fx)
			items.append({"id": "" if followed else "toggle:" + str(fx["id"]), "kind": "chip",
				"rect": chip, "fixture": fx, "followed": followed})
		y += h + gap
	return items

# gd-tools: no cover start


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


			if bool(item.get("followed", false)):
				LeagueInterestMark.chip(c, cache, rect, bold)
			else:
				LeaguePlanRows.paint_toggle(c, rect, item["fixture"], cache, bold)

# gd-tools: no cover end
