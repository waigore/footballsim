class_name LeagueCupState
extends RefCounted


static func start(season: LeagueSeason) -> void:
	if season == null or season.save == null:
		return
	for cid in LeagueCup.active_ids(season.save):
		_resume(season, str(cid))


static func _resume(season: LeagueSeason, competition_id: String) -> void:
	var rounds := LeagueCup.rounds(competition_id)
	if rounds.is_empty():
		return
	var first := str((rounds[0] as Dictionary).get("id", ""))
	if not LeagueCup.has_round(competition_id, first):
		draw_round(season, competition_id, first, LeagueCup.entrants(competition_id, first))
		return
	for i in range(rounds.size()):
		var rid := str((rounds[i] as Dictionary).get("id", ""))
		if not LeagueCup.has_round(competition_id, rid):
			continue
		if not LeagueCup.round_complete(competition_id, rid):
			continue
		if i + 1 >= rounds.size():
			continue
		var next := str((rounds[i + 1] as Dictionary).get("id", ""))
		if not LeagueCup.has_round(competition_id, next):
			draw_round(season, competition_id, next,
				LeagueCupTie.winners(competition_id, rid)
				+ LeagueCup.entrants(competition_id, next))


static func draw_round(season: LeagueSeason, competition_id: String, round_id: String,
		pool: Array) -> bool:
	if season == null or season.save == null or pool.size() < 2:
		return false
	var rule := LeagueCup.round_rule(competition_id, round_id)
	var pairs := LeagueCupDraw.settle(season, competition_id, round_id, pool)
	if pairs.is_empty():
		return false
	var position := LeagueCup.round_index(competition_id, round_id) + 1
	LeagueCupTie.install_round(competition_id, round_id, position, pairs, rule, "cup",
		season.save.season_index())
	season.save.set_status("in_progress")
	return true


static func after_played(season: LeagueSeason, fixture: Dictionary) -> void:
	if not LeagueCup.is_cup_fixture(fixture):
		return
	var competition_id := str(fixture.get("competition_id", ""))
	var round_id := str(fixture.get("stage", ""))
	if not LeagueCup.round_complete(competition_id, round_id):
		return
	PLDatabase.execute(
		"UPDATE cup_round SET status = 'complete' WHERE competition_id = ? AND round_id = ?;",
		[competition_id, round_id])
	var next := LeagueCup.next_round(competition_id, round_id)
	if next == "" or LeagueCup.has_round(competition_id, next):
		return
	draw_round(season, competition_id, next,
		LeagueCupTie.winners(competition_id, round_id)
		+ LeagueCup.entrants(competition_id, next))


static func bracket(competition_id: String) -> Array:
	var out: Array = []
	for row in LeagueCup.rounds(competition_id):
		var rule: Dictionary = row
		var round_id := str(rule.get("id", ""))
		var ties: Array = []
		for tie in PLDatabase.rows(
				"SELECT * FROM cup_tie WHERE competition_id = ? AND round_id = ? "
				+ "ORDER BY tie_index;", [competition_id, round_id]):
			ties.append({
				"home": str(tie["home_club_id"]),
				"away": str(tie["away_club_id"]),
				"home_name": LeagueCup.name_of(str(tie["home_club_id"])),
				"away_name": LeagueCup.name_of(str(tie["away_club_id"])),
				"home_goals": int(tie["home_goals"]),
				"away_goals": int(tie["away_goals"]),
				"winner": str(tie["winner_club_id"]),
				"pens_home": int(tie["pens_home"]),
				"pens_away": int(tie["pens_away"]),
				"extra_time": int(tie["extra_time"]) == 1,
				"played": str(tie["winner_club_id"]) != "",
			})
		out.append({
			"id": round_id, "name": str(rule.get("name", round_id)),
			"date": str(rule.get("date", "")), "legs": int(rule.get("legs", 1)),
			"ties": ties, "complete": LeagueCup.round_complete(competition_id, round_id),
		})
	return out


static func winner(competition_id: String) -> String:
	var rounds := LeagueCup.rounds(competition_id)
	if rounds.is_empty():
		return ""
	var last := str((rounds[rounds.size() - 1] as Dictionary).get("id", ""))
	return LeagueCupTie.winner_of(competition_id, last)


static func runner_up(competition_id: String) -> String:
	var rounds := LeagueCup.rounds(competition_id)
	if rounds.is_empty():
		return ""
	var last := str((rounds[rounds.size() - 1] as Dictionary).get("id", ""))
	return LeagueCupTie.runner_up_of(competition_id, last)


static func final(competition_id: String) -> Dictionary:
	var rounds := LeagueCup.rounds(competition_id)
	if rounds.is_empty():
		return {}
	var last := str((rounds[rounds.size() - 1] as Dictionary).get("id", ""))
	return PLDatabase.row(
		"SELECT * FROM cup_tie WHERE competition_id = ? AND round_id = ? ORDER BY tie_index LIMIT 1;",
		[competition_id, last])


static func honours(competition_id: String) -> Dictionary:
	var tie := final(competition_id)
	if tie.is_empty() or str(tie.get("winner_club_id", "")) == "":
		return {}
	var winner := str(tie["winner_club_id"])
	var runner := LeagueCupTie.runner_up_of(competition_id,
		str(tie.get("round_id", "")))
	return {
		"id": competition_id,
		"winner": winner, "winner_name": LeagueCup.name_of(winner),
		"runner_up": runner, "runner_up_name": LeagueCup.name_of(runner),
		"home_goals": int(tie.get("home_goals", 0)),
		"away_goals": int(tie.get("away_goals", 0)),
		"pens_home": int(tie.get("pens_home", -1)),
		"pens_away": int(tie.get("pens_away", -1)),
		"extra_time": int(tie.get("extra_time", 0)) == 1,
		"europe": LeagueCup.rules(competition_id).get("europe", {}),
	}


static func stage(competition_id: String) -> String:
	return LeagueCup.stage_of(competition_id)


static func pending(competition_id: String) -> bool:
	return stage(competition_id) != "" and winner(competition_id) == ""
