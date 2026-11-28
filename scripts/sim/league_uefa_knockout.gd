class_name LeagueUefaKnockout
extends RefCounted


static func seed(season: LeagueSeason, competition_id: String) -> bool:
	if season == null or season.save == null:
		return false
	var table := LeagueUefaLeaguePhase.table(competition_id)
	if table.size() < 24:
		return false
	var play_off := _ties(table, 8, 24)
	if not _install(competition_id, "KOPO", play_off):
		return false
	return true


static func after_round(season: LeagueSeason, competition_id: String, round_id: String) -> void:
	if season == null or season.save == null:
		return
	if round_id != "KOPO" and round_id != "R16" and round_id != "QF" and round_id != "SF":
		return
	var next := LeagueUefa.after(competition_id, round_id)
	if next == "" or LeagueUefa.has_stage(competition_id, next):
		return
	var table := LeagueUefaLeaguePhase.table(competition_id)
	var winners := _winners(competition_id, round_id)
	if next == "R16":
		var seeded := _top(table, 8)
		var pairs: Array = []
		for i in range(8):
			pairs.append({"home": seeded[i], "away": winners[7 - i] if 7 - i < winners.size()
				else winners[i % maxi(winners.size(), 1)]})
		_install(competition_id, "R16", pairs)
		return
	var pairs: Array = []
	var i := 0
	while i + 1 < winners.size():
		pairs.append({"home": winners[i], "away": winners[i + 1]})
		i += 2
	_install(competition_id, next, pairs)


static func _ties(table: Array, low: int, high: int) -> Array:
	var pairs: Array = []
	var i := low
	var j := high - 1
	while i < j and i < high:
		pairs.append({"home": str((table[j] as Dictionary)["club_id"]),
			"away": str((table[i] as Dictionary)["club_id"])})
		i += 1
		j -= 1
	return pairs


static func _top(table: Array, count: int) -> Array:
	var out: Array = []
	for i in range(mini(count, table.size())):
		out.append(str((table[i] as Dictionary)["club_id"]))
	return out


static func _winners(competition_id: String, round_id: String) -> Array:
	var out: Array = []
	for row in PLDatabase.rows(
			"SELECT winner_club_id FROM cup_tie WHERE competition_id = ? AND round_id = ? "
			+ "AND winner_club_id <> '' ORDER BY tie_index;", [competition_id, round_id]):
		out.append(str(row["winner_club_id"]))
	return out


static func _install(competition_id: String, round_id: String, pairs: Array) -> bool:
	if pairs.is_empty():
		return false
	var rule := LeagueUefa.round_rule(competition_id, round_id)
	if rule.is_empty():
		return false
	PLDatabase.execute(
		"INSERT OR REPLACE INTO cup_round (competition_id, round_id, position, status) "
		+ "VALUES (?, ?, ?, 'open');",
		[competition_id, round_id, LeagueUefa.round_ids(competition_id).find(round_id) + 1])
	var legs := int(rule.get("legs", 2))
	for i in range(pairs.size()):
		var pair: Dictionary = pairs[i]
		var home := str(pair["home"])
		var away := str(pair["away"])
		PLDatabase.execute(
			"INSERT OR REPLACE INTO cup_tie (competition_id, round_id, tie_index, "
			+ "home_club_id, away_club_id, winner_club_id, home_goals, away_goals, "
			+ "pens_home, pens_away, extra_time) VALUES (?, ?, ?, ?, ?, '', 0, 0, -1, -1, 0);",
			[competition_id, round_id, i, home, away])
		for leg in range(1, legs + 1):
			var date := str(rule.get("date", "")) if leg == 1 \
				else str(rule.get("second_leg", FixtureCalendar.add_days(
					str(rule.get("date", "")), 7)))
			var fixture_home := home if leg == 1 else away
			var fixture_away := away if leg == 1 else home
			PLDatabase.execute(
				"INSERT OR REPLACE INTO league_fixture (id, competition_id, matchday, kickoff, "
				+ "kickoff_time, home_club_id, away_club_id, status, watched, suggested, "
				+ "stage, leg) VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', 0, 0, ?, ?);",
				["uefa-%s-%s-%02d-%d" % [competition_id, round_id, i, leg], competition_id,
				 LeagueUefa.round_ids(competition_id).find(round_id) + 1, date,
				 FixtureCalendar.KICKOFF_TIMES[(i + leg) % FixtureCalendar.KICKOFF_TIMES.size()],
				 fixture_home, fixture_away, round_id, leg])
	return true
