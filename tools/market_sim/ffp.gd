extends RefCounted

## The ffp verb: the rolling three-year measure, the embargo and the points
## deduction on a fixed clock. No deal engine, no AI and no UI is loaded; the
## finance ledger and the FFP measure are the whole world.
##
##   godot --headless --path . --script res://tools/market_sim.gd -- ffp \
##     --seasons 3 --clubs 20 --revenue 100m --wages 80m
##
## --inject  none | embargo | deduction


static func run(options: Dictionary) -> Dictionary:
	var seed_value := int(options.get("seed", "9311"))
	var season := LeagueSeason.create("FFP Sandbox", "generated", "fixture_days", seed_value,
		["PL"], false)
	if season == null:
		return {"ok": false, "reason": "the save could not be created",
			"detail": LeagueSave.last_error}
	var club_id := str(PLDatabase.row(
		"SELECT id FROM club WHERE competition_id = 'PL' ORDER BY id LIMIT 1;").get("id", ""))
	var start := season.save.current_date()
	var index := season.save.season_index()
	print("ffp: %s opens season %d on %s with cash %s" % [club_id, index, start,
		MarketCurrency.format(MarketFinance.cash(club_id))])
	var monitored := MarketFFP.status(club_id, index)
	print("  season one state %s (monitored=%s)" % [str(monitored["state"]),
		str(MarketFFP.monitored(index))])
	_exercise_ledger(club_id, int(options.get("seasons", "3")), start)
	var measured := MarketFFP.measure(club_id, index)
	for key in ["revenue", "wages", "amortisation", "agent", "measure", "allowed", "headroom"]:
		print("  %-13s %s" % [key, MarketCurrency.format_units(int(measured[key]))])
	var inject := str(options.get("inject", "none"))
	var outcome := _case(club_id, season, inject, index)
	print("ffp: inject '%s' -> %s" % [inject, JSON.stringify(outcome)])
	var ok := bool(monitored.get("compliant", false)) and bool(outcome.get("ok", false))
	season.close()
	return {"ok": ok, "club": club_id, "season_index": index, "measure": measured,
		"state": str(monitored["state"]), "injected": inject, "outcome": outcome}


static func _case(club_id: String, season: LeagueSeason, inject: String,
		index: int) -> Dictionary:
	match inject:
		"embargo":
			return _embargo_case(club_id, index)
		"deduction":
			return _deduction_case(club_id, season, index)
	return _measure_case(club_id, index)


static func _measure_case(club_id: String, index: int) -> Dictionary:
	var measured := MarketFFP.measure(club_id, index)
	var terms_ok := int(measured["measure"]) == int(measured["revenue"]) \
		- int(measured["wages"]) - int(measured["amortisation"]) - int(measured["agent"])
	var season_one_safe := MarketFFP.monitored(index) and bool(MarketFFP.status(club_id, index)["compliant"])
	return {"ok": terms_ok and season_one_safe, "terms_ok": terms_ok,
		"season_one_monitored": MarketFFP.monitored(index)}


static func _embargo_case(club_id: String, index: int) -> Dictionary:
	var competition_id := str(PLDatabase.row(
		"SELECT competition_id FROM club WHERE id = ?;", [club_id]).get("competition_id", ""))
	var embargoed := MarketFFP.embargoed(club_id, index + 1)
	var blocked := MarketRegistration.admit(_outsider(club_id), club_id, competition_id)
	var verdict := {
		"ok": not embargoed or str(blocked.get("code", "")) == "ffp",
		"embargoed": embargoed, "registration_code": str(blocked.get("code", "")),
		"headroom": MarketFFP.headroom(club_id, index + 1),
	}
	return verdict


static func _deduction_case(club_id: String, season: LeagueSeason, index: int) -> Dictionary:
	var competition_id := str(PLDatabase.row(
		"SELECT competition_id FROM club WHERE id = ?;", [club_id]).get("competition_id", ""))
	var future := index + 1
	PLDatabase.execute(
		"INSERT INTO league_table (club_id, competition_id, season_index, points) "
		+ "VALUES (?, ?, ?, 40) ON CONFLICT(club_id, competition_id) DO UPDATE SET points = 40;",
		[club_id, competition_id, future])
	var booked := MarketFFP.book(club_id, competition_id, MarketFFP.deduction_points(),
		"breach", season.save.current_date(), future)
	var pending := MarketFFP.pending(club_id, competition_id, future)
	var applied := MarketFFP.apply_at_table_start(competition_id, future)
	var label := season.save.season_label()
	season.save.set_season(future, label)
	season.record.standings.recompute()
	var after := _row_points(club_id, competition_id)
	var again := MarketFFP.apply_at_table_start(competition_id, future)
	season.save.set_season(index, label)
	return {
		"ok": booked and not pending.is_empty() and applied == 1 and again == 0 \
			and after == -MarketFFP.deduction_points(),
		"booked": booked, "pending": not pending.is_empty(), "applied": applied,
		"reapplied": again, "after": after, "points": MarketFFP.deduction_points(),
	}


static func _row_points(club_id: String, competition_id: String) -> int:
	return int(PLDatabase.row(
		"SELECT points FROM league_table WHERE club_id = ? AND competition_id = ?;",
		[club_id, competition_id]).get("points", 0))


static func _exercise_ledger(club_id: String, seasons: int, start: String) -> void:
	for i in range(maxi(seasons, 1)):
		var date := FixtureCalendar.add_years(start, i)
		MarketFinance.post(club_id, date, MarketFinance.KIND_COMMERCIAL,
			MarketFinance.revenue_base(club_id), "commercial")
		MarketFinance.post(club_id, date, MarketFinance.KIND_WAGE,
			-MarketFinance.annual_wages(club_id), "squad")
		MarketFinance.post_amortisation(club_id, date, 40000000, 4, "")


static func _outsider(club_id: String) -> String:
	return str(PLDatabase.row(
		"SELECT id FROM player WHERE club_id <> ? AND club_id <> '' ORDER BY ovr LIMIT 1;",
		[club_id]).get("id", ""))
