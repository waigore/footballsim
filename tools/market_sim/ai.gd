extends RefCounted

## The ai verb: play a world season with the market AI on, then print the deal
## transcript. No UI and no scenes load; the deal engine, finance, contracts and
## the AI modules are the whole world.
##
##   godot --headless --path . --script res://tools/market_sim.gd -- ai \
##     --clubs 172 --days 365 --mode fixture_days
##
## --mode  fixture_days | every_day  (both must print the same transcript)
## --json  the printed line is the whole transcript


const ALL := ["PL", "CH", "L1", "L2", "NL", "LL", "LL2", "BL", "BL2", "SA", "SB"]


static func run(options: Dictionary) -> Dictionary:
	var seed_value := int(options.get("seed", "9101"))
	var mode := str(options.get("mode", "fixture_days"))
	if not LeagueRules.ADVANCE_MODES.has(mode):
		mode = "fixture_days"
	var comps := competitions(int(options.get("clubs", "172")))
	var season := LeagueSeason.create("AI Sandbox", "generated", mode, seed_value, comps, false)
	if season == null:
		return {"ok": false, "reason": "the save could not be created",
			"detail": LeagueSave.last_error}
	var clubs := int(PLDatabase.row("SELECT COUNT(*) AS n FROM club_finance;").get("n", 0))
	var days := maxi(int(options.get("days", "365")), 1)
	var start := season.save.current_date()
	var deadline := FixtureCalendar.add_days(start, days)
	var guard := 0
	while guard < 900 and season.save.status() != "complete" \
			and season.save.current_date() < deadline:
		season.advance()
		guard += 1
	var transcript := deals(season)
	var signed := 0
	var reasons := {}
	var spread := {}
	for entry in transcript:
		if str(entry.get("state", "")) == MarketDealRecords.SIGNED:
			signed = int(signed) + 1
		else:
			var reason := str(entry.get("reason", ""))
			reasons[reason] = int(reasons.get(reason, 0)) + 1
		var band := _band(int(entry.get("value", 0)))
		spread[band] = int(spread.get(band, 0)) + 1
	var fingerprint := str(JSON.stringify(transcript).hash())
	var stranded := stranded_clubs()
	var ok := signed > 0 and stranded.is_empty()
	print("ai: %d clubs, %d days, %d deals signed, fingerprint %s" % [
		clubs, days, signed, fingerprint])
	print("  spread %s" % spread)
	if not stranded.is_empty():
		print("  stranded %s" % stranded)
	for entry in transcript.slice(0, 12):
		print("  %s %s -> %s  %s  %s" % [str(entry.get("date", "")),
			str(entry.get("from", "")), str(entry.get("to", "")),
			MarketCurrency.format(int(entry.get("fee", 0))), str(entry.get("state", ""))])
	season.close()
	return {
		"ok": ok, "mode": mode, "clubs": clubs, "days": days, "signed": signed,
		"fingerprint": fingerprint, "spread": spread, "reasons": reasons,
		"stranded": stranded, "deals": transcript,
	}


static func competitions(clubs: int) -> Array:
	var out: Array = []
	var running := 0
	for cid in ALL:
		if running >= clubs and not out.is_empty():
			break
		out.append(cid)
		running += int(PLDatabase.row(
			"SELECT COUNT(*) AS n FROM club WHERE competition_id = ? AND stub = 0;",
			[cid]).get("n", 0))
	return out if not out.is_empty() else ["PL"]


static func deals(season: LeagueSeason) -> Array:
	var out: Array = []
	for row in PLDatabase.rows(
			"SELECT * FROM deal ORDER BY opened_on, id;"):
		var player := PLRepository.shared().player(str(row.get("player_id", "")))
		var contract := MarketDealRecords.active_contract(str(row.get("player_id", "")))
		out.append({
			"id": str(row.get("id", "")), "date": str(row.get("opened_on", "")),
			"state": str(row.get("state", "")), "reason": str(row.get("reason", "")),
			"from": str(row.get("from_club_id", "")), "to": str(row.get("to_club_id", "")),
			"player": str(row.get("player_id", "")), "fee": int(row.get("fee", 0)),
			"wage": int(row.get("wage", 0)), "years": int(row.get("years", 0)),
			"value": MarketValuation.value(player, contract, season.save.current_date()),
		})
	return out


static func stranded_clubs() -> Array:
	var out: Array = []
	for row in PLDatabase.rows(
			"SELECT c.id, COUNT(p.id) AS n FROM club c LEFT JOIN player p ON p.club_id = c.id "
			+ "WHERE c.stub = 0 GROUP BY c.id HAVING n < 11 ORDER BY c.id;"):
		out.append({"club": str(row.get("id", "")), "players": int(row.get("n", 0))})
	return out


static func _band(value_amount: int) -> String:
	if value_amount >= 45_000_000:
		return "90m+"
	if value_amount >= 22_000_000:
		return "22-45m"
	if value_amount >= 10_000_000:
		return "10-22m"
	if value_amount >= 4_500_000:
		return "4.5-10m"
	return "below 4.5m"
