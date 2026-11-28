class_name WikiTeam
extends RefCounted


const STYLE_LABELS := [
	["possession", "POSSESSION"], ["tempo", "TEMPO"], ["press", "PRESS"],
	["line", "LINE"], ["width", "WIDTH"], ["directness", "DIRECTNESS"],
	["crossing", "CROSSING"], ["aggression", "AGGRESSION"],
]


static func _bars(p: Dictionary) -> Array:
	"""The six face bars a squad row shows in the Full view."""
	if str(p.get("role", "")) == "GK":
		var gk: Dictionary = p.get("gk", {})
		return [int(gk.get("div", 0)), int(gk.get("han", 0)), int(gk.get("kic", 0)),
			int(gk.get("ref", 0)), int(gk.get("spd", 0)), 0]
	return [int(p.get("pac", 0)), int(p.get("sho", 0)), int(p.get("pas", 0)),
		int(p.get("dri", 0)), int(p.get("def", 0)), int(p.get("phy", 0))]


static func page(club_id: String, mode: String = "SIMPLIFIED") -> Dictionary:
	var club := WikiModel.repo().club(club_id)
	if club.is_empty():
		return WikiLeague.page()
	var meta := WikiModel.repo().meta()
	var table: Dictionary = club.get("table", {})
	var out := {
		"page": WikiModel.TEAM,
		"id": club_id,
		"title": str(club["name"]).to_upper(),
		"eyebrow": "%s  ·  %s" % [str(club["abbr"]), str(club["nickname"]).to_upper()],
		"subtitle": "%s  ·  %s  ·  %s" % [str(club["stadium"]).to_upper(), str(club["city"]).to_upper(), str(club["manager"]).to_upper()],
		"accent": club["color"],
		"blocks": [],
	}
	out["blocks"].append(WikiCompetitions.link(str(club.get("competition", ""))))
	out["blocks"].append({"k": "chips", "items": [{
		"text": str(club.get("manager", "The manager")).to_upper(),
		"target": {"page": WikiModel.MANAGER, "id": club_id},
		"accent": WikiModel.hex(club.get("color", Color.WHITE)),
	}]})
	out["blocks"].append({"k": "section", "text": WikiLedger.record_label(str(meta["season_label"]))})
	out["blocks"].append({
		"k": "kv",
		"items": [
			["POSITION", or_dash(table, "position"), true],
			["POINTS", or_dash(table, "points"), true],
			["PLAYED", or_dash(table, "played"), false],
			["WON", or_dash(table, "won"), false],
			["DRAWN", or_dash(table, "drawn"), false],
			["LOST", or_dash(table, "lost"), false],
			["GOALS FOR", or_dash(table, "gf"), false],
			["GOALS AGAINST", or_dash(table, "ga"), false],
			["CAPACITY", thousands(int(club["capacity"])), false],
			["FORMATION", str(club["formation"]), false],
		],
	})
	finance_blocks(out, club_id)
	var race := PositionRace.series(club_id)
	if not race.is_empty():
		out["blocks"].append({"k": "section",
			"text": "POSITION  ·  %d FIXTURE DAYS" % (race["days"] as Array).size()})
		out["blocks"].append({
			"k": "spark", "points": race["days"], "clubs": int(race["clubs"]),
			"place": int(race["place"]), "best": int(race["best"]), "worst": int(race["worst"]),
			"accent": WikiModel.hex(club.get("color", Color.WHITE)),
		})
	out["blocks"].append({"k": "section", "text": "TACTICAL PROFILE"})
	var bars: Array = []
	for pair in STYLE_LABELS:
		bars.append([str(pair[1]), float(club.get("style", {}).get(pair[0], 0.5))])
	out["blocks"].append({"k": "bars", "items": bars})
	out["blocks"].append({"k": "section", "text": "SQUAD"})
	var squad := WikiModel.repo().squad(club_id)
	var absences := WikiAbsence.statuses(club_id)
	var view := AttrView.normalize(mode)
	var full := view == "FULL"
	out["blocks"].append({"k": "door", "items": [
		{"text": "SIMPLIFIED", "id": "attrs:SIMPLIFIED",
			"accent": WikiModel.hex(club.get("color", Color.WHITE)), "on": not full},
		{"text": "FULL", "id": "attrs:FULL",
			"accent": WikiModel.hex(club.get("color", Color.WHITE)), "on": full},
	]})
	var squad_rows: Array = []
	for p in squad:
		var cells: Array = [str(p["number"]), str(p["name"]), str(p["pos"]), str(p["ovr"])]
		if full:
			for bar in _bars(p):
				cells.append(str(bar))
		squad_rows.append({
			"cells": cells,
			"target": {"page": WikiModel.PLAYER, "id": str(p["id"])},
		})
	var squad_head := ["#", "PLAYER", "POS", "OVR"]
	var squad_widths := [0.09, 0.55, 0.19, 0.17]
	var squad_text := [1, 2]
	if full:
		squad_head = ["#", "PLAYER", "POS", "OVR", "PAC", "SHO", "PAS", "DRI", "DEF", "PHY"]
		squad_widths = [0.05, 0.29, 0.09, 0.07, 0.07, 0.07, 0.07, 0.07, 0.07, 0.07]
		squad_text = [1, 2]
	if not absences.is_empty():
		squad_head.append("STATUS")
		squad_widths = [0.07, 0.34, 0.13, 0.10, 0.36]
		squad_text = [1, 2, 4]
		for i in range(squad_rows.size()):
			var row: Dictionary = squad_rows[i]
			row["cells"].append(str(absences.get(str(squad[i]["id"]), "")))
	out["blocks"].append({
		"k": "table", "cols": squad_head,
		"widths": squad_widths, "text_cols": squad_text,
		"rows": squad_rows,
	})
	out["blocks"].append_array(uefa_lists(club_id))
	out["blocks"].append({"k": "section", "text": "RESULTS  ·  %s" % WikiLedger.ledger_label()})
	var results: Array = []
	for fx in WikiModel.repo().fixtures(club_id, 8):
		results.append({
			"cells": [
				FixtureCalendar.day_label(str(fx["kickoff"])),
				"%s %d – %d %s" % [str(fx["home_name"]), int(fx["home_goals"]), int(fx["away_goals"]), str(fx["away_name"])],
			],
			"target": {"page": WikiModel.TEAM, "id": str(fx["away_club_id"] if str(fx["home_club_id"]) == club_id else fx["home_club_id"])},
			"dates": {0: str(fx["kickoff"])},
		})
	if results.is_empty():
		out["blocks"].append({"k": "note", "text": "NO RESULTS YET  ·  PLAY A GAMEWEEK TO START THE RECORD"})
	else:
		out["blocks"].append({
			"k": "table", "cols": ["DATE", "FIXTURE"],
			"widths": [0.16, 0.84], "text_cols": [0, 1],
			"rows": results,
		})
	out["blocks"].append({"k": "section", "text": "NEXT FIXTURES  ·  %s" % WikiLedger.ledger_label()})
	var with_gw := WikiModel.repo().season_active()
	var next: Array = []
	for fx in WikiModel.repo().upcoming(club_id, 6):
		var opponent := str(fx["away_club_id"] if str(fx["home_club_id"]) == club_id else fx["home_club_id"])
		var cells := [FixtureCalendar.day_label(str(fx["kickoff"]))]
		if with_gw:
			cells.append("GW %d" % int(fx["matchday"]))
		cells.append("%s v %s" % [str(fx["home_name"]), str(fx["away_name"])])
		next.append({
			"cells": cells,
			"target": {"page": WikiModel.TEAM, "id": opponent},
			"dates": {0: str(fx["kickoff"])},
		})
	if next.is_empty():
		var done := "NO FIXTURES LEFT  ·  THE SEASON IS COMPLETE" if WikiModel.repo().season_active() \
			else "NO FIXTURES LEFT  ·  THE SNAPSHOT ENDS HERE"
		out["blocks"].append({"k": "note", "text": done})
	elif with_gw:
		out["blocks"].append({
			"k": "table", "cols": ["DATE", "GW", "FIXTURE"],
			"widths": [0.20, 0.14, 0.66], "text_cols": [0, 1, 2],
			"rows": next,
		})
	else:
		out["blocks"].append({
			"k": "table", "cols": ["DATE", "FIXTURE"],
			"widths": [0.20, 0.80], "text_cols": [0, 1],
			"rows": next,
		})
	out["blocks"].append_array(WikiLedger.club_blocks(club_id))
	return out


static func or_dash(table: Dictionary, key: String) -> String:
	if table.is_empty() or table.get(key) == null:
		return "—"
	return str(int(table[key]))


static func thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out


static func currency_doors() -> Array:
	var active := MarketCurrency.code_of()
	var order: Array = [MarketCurrency.default_code()]
	for code in MarketCurrency.currencies():
		if not order.has(code):
			order.append(code)
	var doors: Array = []
	for code in order:
		doors.append({"text": str(code), "id": "currency:" + str(code),
			"on": str(code) == active})
	return doors


static func uefa_lists(club_id: String) -> Array:
	var out: Array = []
	if not SquadList.available():
		return out
	for competition_id in SquadList.entries(club_id):
		var reading := SquadList.reading(club_id, str(competition_id))
		if reading.is_empty():
			continue
		out.append({"k": "section", "text": "%s LIST  ·  %d / %d" % [
			str(reading["name"]).to_upper(), int(reading["slots_used"]), int(reading["slots"])]})
		out.append({"k": "kv", "items": [
			["STATE", str(reading["state"]).to_upper(), true],
			["ASSOCIATION-TRAINED", "%d / %d" % [int(reading["trained"]),
				int(reading["trained_min"])], false],
		]})
		var rows: Array = []
		for player in reading["players"]:
			var state := str(player["state"])
			var cells: Array = [str(player["name"]), str(player["pos"]).to_upper(),
				"YES" if bool(player["trained"]) else "NO",
				"UNDER 21" if bool(player["exempt"]) else state.to_upper()]
			rows.append({"cells": cells,
				"target": {"page": WikiModel.PLAYER, "id": str(player["id"])}})
		out.append({"k": "table", "cols": ["PLAYER", "POS", "TRAINED", "STATE"],
			"widths": [0.44, 0.16, 0.18, 0.22], "text_cols": [0, 1, 2, 3], "rows": rows})
	return out


static func finance_blocks(out: Dictionary, club_id: String) -> void:
	var finance := MarketFinance.club(club_id)
	if finance.is_empty():
		return
	out["blocks"].append({"k": "section", "text": "FINANCES"})
	out["blocks"].append({"k": "kv", "items": [
		["CASH", MarketCurrency.format(int(finance.get("cash", 0))), true],
		["WAGE BILL", MarketCurrency.format(MarketFinance.annual_wages(club_id)) + " / SEASON", false],
		["WAGE BUDGET", MarketCurrency.format(int(finance.get("wage_budget", 0))), false],
		["FFP HEADROOM", MarketCurrency.format(MarketFinance.ffp_headroom(club_id)), false],
		["REPUTATION", str(int(finance.get("reputation", 0))), false],
	]})
	out["blocks"].append({"k": "door", "items": currency_doors()})
	var tail := MarketFinance.ledger_tail(club_id, 5)
	if tail.is_empty():
		return
	var rows: Array = []
	for line in tail:
		rows.append({"cells": [str(line.get("date", "")), str(line.get("kind", "")).to_upper(),
			MarketCurrency.format_units(int(line.get("amount", 0)))]})
	out["blocks"].append({"k": "table", "cols": ["DATE", "KIND", "AMOUNT"],
		"widths": [0.34, 0.30, 0.36], "text_cols": [0, 1, 2], "rows": rows})
