extends RefCounted

## The contracts verb: bootstrap a save's contracts, cross a contract year, and
## print what the review expired, renewed and exercised. No deal engine, no UI.


static func run(options: Dictionary) -> Dictionary:
	var seed_value := int(options.get("seed", "7041"))
	var clubs := maxi(int(options.get("clubs", "20")), 2)
	var days := maxi(int(options.get("days", "400")), 1)
	var expire := str(options.get("expire", "0")) != "0"
	var competitions := ["PL"]
	if clubs > 20:
		competitions.append("CH")
	var season := LeagueSeason.create("Contracts Sandbox", "generated", "fixture_days", seed_value,
		competitions, false)
	if season == null:
		return {"ok": false, "reason": "the save could not be created", "detail": LeagueSave.last_error}
	var start := season.save.current_date()
	var players := int(PLDatabase.row("SELECT COUNT(*) AS n FROM player;").get("n", 0))
	var contracted := MarketContracts.active_count()
	var covered := int(PLDatabase.row(
		"SELECT COUNT(DISTINCT club_id) AS n FROM player_contract WHERE status = 'active';").get("n", 0))
	if expire:
		PLDatabase.execute("UPDATE player_contract SET end_date = ? WHERE status = 'active';", [start])
	var target := FixtureCalendar.add_days(start, days)
	LeagueClock.move(season, start, target)
	var review := MarketContracts.review(season.save, season.save.season_index() + 1, target)
	var free := MarketContracts.free_agent_count()
	var sample := _sample()
	print("contracts: %d players, %d contracts over %d clubs from %s" % [
		players, contracted, covered, start])
	print("review at %s: expired %d, renewed %d, exercised %d, free agents %d" % [
		target, int(review.get("expired", 0)), int(review.get("renewed", 0)),
		int(review.get("exercised", 0)), free])
	season.close()
	var moved := int(review.get("expired", 0)) + int(review.get("renewed", 0)) \
		+ int(review.get("exercised", 0))
	var ok := contracted == players and (moved > 0 or not expire)
	return {
		"ok": ok, "players": players, "contracts": contracted, "clubs": covered,
		"start": start, "date": target, "expired": int(review.get("expired", 0)),
		"renewed": int(review.get("renewed", 0)), "exercised": int(review.get("exercised", 0)),
		"free_agents": free, "sample": sample,
	}


static func _sample() -> Array:
	var out: Array = []
	var row := PLDatabase.row(
		"SELECT player_id, club_id, wage, end_date, status FROM player_contract "
		+ "WHERE status = 'active' ORDER BY player_id LIMIT 1;")
	if not row.is_empty():
		out.append(row)
	var agent := PLDatabase.row(
		"SELECT id, club_id, name FROM player WHERE NOT EXISTS (SELECT 1 FROM player_contract c "
		+ "WHERE c.player_id = player.id AND c.status = 'active') ORDER BY ovr DESC LIMIT 1;")
	if not agent.is_empty():
		out.append(agent)
	return out
