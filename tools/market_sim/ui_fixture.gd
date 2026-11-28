extends RefCounted

## The ui-fixture verb: write a canned market world to --out so every market UI
## suite opens it instead of playing a season.

static func run(options: Dictionary) -> Dictionary:
	var out := str(options.get("out", "user://market_ui_fixture.sqlite"))
	var season := LeagueSeason.create("UI Fixture", "generated", "fixture_days",
		int(options.get("seed", "7071")), ["PL"], false)
	if season == null:
		return {"ok": false, "reason": "the save could not be created",
			"detail": LeagueSave.last_error}
	var date := "2026-08-20"
	var closed := "2026-12-20"
	var clubs: Array = []
	for row in PLDatabase.rows("SELECT id FROM club WHERE competition_id = 'PL' ORDER BY id;"):
		clubs.append(str(row["id"]))
	var made := 0
	for i in range(maxi(int(options.get("deals", "8")), 1)):
		var from := str(clubs[i % clubs.size()])
		var to := str(clubs[(i + 1) % clubs.size()])
		var player := str(PLDatabase.row(
			"SELECT id FROM player WHERE club_id = ? ORDER BY ovr DESC LIMIT 1;",
			[from]).get("id", ""))
		if player == "":
			continue
		var contract := MarketDealRecords.active_contract(player)
		var terms := {"fee": 5_000_000 + i * 500_000,
			"wage": int(contract.get("wage", 5000)), "years": 3, "agent_fee": 0,
			"signing_bonus": 0, "sell_on": 0.0}
		var deal := str(MarketDeals.propose(season, from, to, player, terms, date).get("deal", ""))
		if deal == "":
			continue
		MarketDeals.negotiate(deal, date)
		if i == 0:
			MarketDeals.block(deal, date, "fixture veto")
		elif i == 3:
			MarketDeals.force(deal, date)
		else:
			MarketDeals.agree(deal, date)
			MarketDeals.seal(deal, date)
		made += 1
	var doomed_player := str(PLDatabase.row(
		"SELECT id FROM player WHERE club_id = ? ORDER BY ovr DESC LIMIT 1;",
		[str(clubs[5 % clubs.size()])]).get("id", ""))
	if doomed_player != "":
		var doomed := str(MarketDeals.propose(season, str(clubs[5 % clubs.size()]),
			str(clubs[0]), doomed_player, {"fee": 6_000_000,
				"wage": int(MarketDealRecords.active_contract(doomed_player).get("wage", 5000)),
				"years": 2, "agent_fee": 0, "signing_bonus": 0, "sell_on": 0.0},
			closed).get("deal", ""))
		MarketDeals.agree(doomed, closed)
	var free := 0
	for row in PLDatabase.rows(
			"SELECT id FROM player WHERE club_id <> '' ORDER BY ovr DESC, id LIMIT 2;"):
		var id := str(row["id"])
		PLDatabase.execute("UPDATE player_contract SET status = 'expired' WHERE player_id = ?;", [id])
		PLDatabase.execute("UPDATE player SET club_id = '' WHERE id = ?;", [id])
		free += 1
	var bytes := FileAccess.get_file_as_bytes(season.save.path)
	var dir := out.get_base_dir()
	if dir != "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var file := FileAccess.open(out, FileAccess.WRITE)
	var written := file != null and not bytes.is_empty()
	if written:
		file.store_buffer(bytes)
		file.close()
	var news := MarketNews.count(season.save.season_index())
	print("ui-fixture: %d deals, %d news, wrote %s" % [made, news, out])
	season.close()
	return {"ok": written, "out": out, "deals": made, "news": news}
