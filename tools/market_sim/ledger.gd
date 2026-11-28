extends RefCounted

## The ledger verb: a fixed clock, no deals. Posts a season's commercial lines,
## wage lines, a fee's amortisation and the end-of-season prize curve, then
## prints the kinds the ledger holds and what the club page would read.


static func run(options: Dictionary) -> Dictionary:
	var seed_value := int(options.get("seed", "7311"))
	var clubs := maxi(int(options.get("clubs", "20")), 2)
	var currency := str(options.get("currency", "GBP"))
	var competitions := ["PL"]
	if clubs > 20:
		competitions.append("CH")
	var season := LeagueSeason.create("Ledger Sandbox", "generated", "fixture_days", seed_value,
		competitions, false)
	if season == null:
		return {"ok": false, "reason": "the save could not be created", "detail": LeagueSave.last_error}
	var club_id := str(PLDatabase.row(
		"SELECT id FROM club WHERE competition_id = 'PL' ORDER BY name LIMIT 1;").get("id", ""))
	var start := season.save.current_date()
	var finance := MarketFinance.club(club_id)
	print("ledger: %s opens on %s with %d finance rows" % [
		club_id, start, int(PLDatabase.row(
			"SELECT COUNT(*) AS n FROM club_finance;").get("n", 0))])
	print("won: cash %s, wage bill %s, budget %s, ffp %s" % [
		MarketCurrency.format(int(finance.get("cash", 0)), currency),
		MarketCurrency.format(MarketFinance.annual_wages(club_id), currency),
		MarketCurrency.format(int(finance.get("wage_budget", 0)), currency),
		MarketCurrency.format(MarketFinance.ffp_headroom(club_id), currency)])
	for i in range(12):
		MarketFinance.month(FixtureCalendar.add_days(start, 30 * (i + 1)))
	var posted := MarketFinance.post_amortisation(club_id, start, 40000000, 4, "")
	LeagueSeasonSim.fixture(season, season.record.fixtures.all(1)[0])
	MarketFinance.tick_gates(season, start)
	PLDatabase.transaction("BEGIN TRANSACTION;")
	PLDatabase.execute("UPDATE league_fixture SET status = 'played', home_goals = 2, "
		+ "away_goals = 1 WHERE status <> 'played';")
	PLDatabase.transaction("COMMIT;")
	season.record.standings.recompute()
	season.save.set_status("complete")
	var paid := MarketFinance.season_end(season, season.save.season_index())
	var kinds: Array = []
	for row in PLDatabase.rows("SELECT DISTINCT kind FROM club_ledger ORDER BY kind;"):
		kinds.append(str(row["kind"]))
	var rows := int(PLDatabase.row("SELECT COUNT(*) AS n FROM club_ledger;").get("n", 0))
	var tail := MarketFinance.ledger_tail(club_id, 6)
	print("amortisation %s a season; prize paid to %d clubs; %d ledger rows" % [
		MarketCurrency.format(posted, currency), paid, rows])
	for line in tail:
		print("  %s  %-14s %s" % [str(line.get("date", "")),
			str(line.get("kind", "")).to_upper(),
			MarketCurrency.format_units(int(line.get("amount", 0)), currency)])
	var ok := posted > 0 and paid > 0 \
		and kinds.has(MarketFinance.KIND_WAGE) and kinds.has(MarketFinance.KIND_PRIZE) \
		and kinds.has(MarketFinance.KIND_AMORTISATION)
	var cash := MarketFinance.cash(club_id)
	season.close()
	return {
		"ok": ok,
		"currency": currency,
		"rows": rows,
		"kinds": kinds,
		"amortisation": posted,
		"prize_clubs": paid,
		"cash": cash,
	}
