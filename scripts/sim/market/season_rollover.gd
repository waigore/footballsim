class_name SeasonRollover
extends RefCounted


static func apply(season: LeagueSeason) -> Dictionary:
	if season == null or season.save == null or season.record == null:
		return {"ok": false, "reason": "no_season"}
	if season.save.status() != "complete" or season.record.fixtures.unplayed() > 0:
		return {"ok": false, "reason": "season_open"}
	var played_index := season.save.season_index()
	var index := played_index + 1
	var settled := SeasonSettle.apply(season)
	var archived := SeasonArchive.write(season, played_index)
	var cup_winners := _cup_winners()
	var cup_runners := _cup_runners()
	SeasonCalendar.shift(season, 1)
	var label := SeasonCalendar.next_label(season.save.season_label())
	var start := _start_date(season)
	var ageing := SeasonAgeing.apply(season, index, start)
	var loans := MarketLoans.review(season, start)
	var contracts := MarketContracts.review(season.save, index, start)
	MarketFinanceFlows.tick_gates(season, season.save.current_date())
	MarketFinanceFlows.season_end(season, played_index)
	season.save.put_meta("gates_through", "")
	SeasonArchive.clear_live(season)
	season.save.put_meta(SeasonSettle.LINKED_KEY, "")
	season.record.report.memo.clear()
	season.save.set_season(index, label)
	_reset_cup_pools()
	var entries := LeagueEuropeEntries.regenerate(season, played_index, cup_winners)
	var pools := LeagueCupPools.rebuild(season, played_index, cup_winners, cup_runners)
	var installed := _install_fixtures(season, index)
	MarketFFP.apply_all(season)
	season.record.standings.recompute()
	StrongestXI.apply_all()
	MarketFinanceFlows.roll(season, start)
	var first := season.record.fixtures.next_date("")
	season.save.set_date(first)
	season.save.set_matchday(season.matchday_of(first))
	season.save.set_status("in_progress")
	season.save.reload()
	season.rules_by = season.save.rules_by
	season.rules = season.save.rules
	LeagueCupState.start(season)
	LeagueUefaState.start(season)
	season.record.interest.force_watch()
	season.save.reload()
	season.rules_by = season.save.rules_by
	season.rules = season.save.rules
	MarketTick.invalidate()
	MarketShortlist.reset()
	PLRepository.shared().invalidate()
	return {
		"ok": true, "season_index": index, "season_label": label, "date": first,
		"settled": not settled.is_empty(), "archived": archived, "aged": ageing,
		"loans": loans, "contracts": contracts, "fixtures": installed, "entries": entries,
		"pools": pools,
	}


static func _reset_cup_pools() -> void:
	PLDatabase.execute("DELETE FROM competition_member WHERE role LIKE 'drop:%';")


static func _cup_winners() -> Dictionary:
	var out := {}
	for row in PLDatabase.rows("SELECT DISTINCT competition_id FROM cup_tie;"):
		var competition_id := str(row["competition_id"])
		var winner := LeagueCupState.winner(competition_id)
		if winner != "":
			out[competition_id] = winner
	return out


static func _cup_runners() -> Dictionary:
	var out := {}
	for row in PLDatabase.rows("SELECT DISTINCT competition_id FROM cup_tie;"):
		var competition_id := str(row["competition_id"])
		var runner := LeagueCupState.runner_up(competition_id)
		if runner != "":
			out[competition_id] = runner
	return out


static func _start_date(season: LeagueSeason) -> String:
	if season.save.actives.is_empty():
		return ""
	var rules := season.save.rules_for(str(season.save.actives[0]))
	var start := str(rules.get("season_start", ""))
	return start


static func _install_fixtures(season: LeagueSeason, index: int) -> int:
	var seed := int(str(season.save.meta.get("seed", "0")))
	var done := 0
	for i in range(season.save.actives.size()):
		var cid := str(season.save.actives[i])
		var rules := season.save.rules_for(cid)
		var mode := str(rules.get("calendar_mode", "generated"))
		var built := FixtureCalendar.build(mode, rules, seed + index * 7919 + i * 97, cid)
		if mode == "real":
			for fx in built:
				fx["kickoff"] = FixtureCalendar.add_years(str(fx["kickoff"]), index)
		if not built.is_empty() and season.record.fixtures.install(built, cid, false):
			done += 1
	return done
