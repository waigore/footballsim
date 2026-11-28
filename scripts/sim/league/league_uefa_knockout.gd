class_name LeagueUefaKnockout
extends RefCounted


static func seed(season: LeagueSeason, competition_id: String) -> bool:
	if season == null or season.save == null:
		return false
	var table := LeagueUefaLeaguePhase.table(competition_id)
	if table.size() < 24:
		return false
	var play_off := _ties(table, 8, 24)
	if not _install(competition_id, "KOPO", play_off, season.save.season_index()):
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
	var winners := LeagueCupTie.winners(competition_id, round_id)
	if next == "R16":
		var seeded := _top(table, 8)
		var pairs: Array = []
		for i in range(8):
			pairs.append({"home": seeded[i], "away": winners[7 - i] if 7 - i < winners.size()
				else winners[i % maxi(winners.size(), 1)]})
		_install(competition_id, "R16", pairs, season.save.season_index())
		return
	var pairs: Array = []
	var i := 0
	while i + 1 < winners.size():
		pairs.append({"home": winners[i], "away": winners[i + 1]})
		i += 2
	_install(competition_id, next, pairs, season.save.season_index())


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


static func _orient(competition_id: String, pairs: Array, legs: int) -> Array:
	var places := {}
	var table := LeagueUefaLeaguePhase.table(competition_id)
	for i in range(table.size()):
		places[str((table[i] as Dictionary)["club_id"])] = i
	var better_at_home := legs <= 1
	for pair in pairs:
		var home := str(pair["home"])
		var away := str(pair["away"])
		var home_better := int(places.get(home, 999)) < int(places.get(away, 999))
		if home_better != better_at_home:
			pair["home"] = away
			pair["away"] = home
	return pairs


static func _install(competition_id: String, round_id: String, pairs: Array,
		season_index: int) -> bool:
	if pairs.is_empty():
		return false
	var rule := LeagueUefa.round_rule(competition_id, round_id)
	if rule.is_empty():
		return false
	var legs := int(rule.get("legs", 2))
	pairs = _orient(competition_id, pairs, legs)
	var position := LeagueUefa.round_ids(competition_id).find(round_id) + 1
	LeagueCupTie.install_round(competition_id, round_id, position, pairs, rule, "uefa",
		season_index)
	return true
