class_name LeagueCupHub
extends RefCounted


const ROUND_H := 26.0
const GAP := 6.0


static func competitions(season: LeagueSeason) -> Array:
	var out: Array = []
	if season == null or season.save == null:
		return out
	for cid in LeagueCup.active_ids(season.save):
		var comp := PLRepository.shared().competition(str(cid))
		out.append({
			"id": str(cid),
			"name": str(comp.get("name", str(cid))),
			"short": str(comp.get("short_name", str(cid))),
			"kind": LeagueCup.kind(str(cid)),
			"stage": LeagueCupState.stage(str(cid)),
			"winner": LeagueCupState.winner(str(cid)),
			"runner_up": LeagueCupState.runner_up(str(cid)),
			"score": _score_text(str(cid)),
			"alive": _alive(str(cid)),
			"next": _next_night(season, str(cid)),
		})
	return out


static func _score_text(competition_id: String) -> String:
	var tie := LeagueCupState.final(competition_id)
	if tie.is_empty() or str(tie.get("winner_club_id", "")) == "":
		return ""
	var home := str(tie.get("home_club_id", ""))
	var away := str(tie.get("away_club_id", ""))
	var home_goals := int(tie.get("home_goals", 0))
	var away_goals := int(tie.get("away_goals", 0))
	var line := "%d–%d" % [home_goals, away_goals]
	if home_goals < away_goals:
		line = "%d–%d" % [away_goals, home_goals]
	if int(tie.get("pens_home", -1)) >= 0:
		var pens_home := int(tie.get("pens_home", 0))
		var pens_away := int(tie.get("pens_away", 0))
		var winner_pens := pens_home if str(tie.get("winner_club_id", "")) == home else pens_away
		var loser_pens := pens_away if str(tie.get("winner_club_id", "")) == home else pens_home
		line += "  %d–%d PENS" % [winner_pens, loser_pens]
	return line


static func _alive(competition_id: String) -> int:
	var stage := LeagueCup.stage_of(competition_id)
	if stage == "":
		return 0
	var row := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM (SELECT home_club_id AS c FROM cup_tie "
		+ "WHERE competition_id = ? AND round_id = ? UNION SELECT away_club_id FROM cup_tie "
		+ "WHERE competition_id = ? AND round_id = ?);",
		[competition_id, stage, competition_id, stage])
	return int(row.get("n", 0))


static func _next_night(season: LeagueSeason, competition_id: String) -> String:
	var date := season.save.current_date()
	for fx in season.record.fixtures.all(-1, competition_id):
		if str(fx.get("status", "")) == "played":
			continue
		if str(fx.get("kickoff", "")) >= date:
			return str(fx.get("kickoff", ""))
	return ""


static func rounds(competition_id: String) -> Array:
	var out: Array = []
	for round_row in LeagueCupState.bracket(competition_id):
		var ties: Array = round_row.get("ties", [])
		out.append({
			"id": str(round_row.get("id", "")), "name": str(round_row.get("name", "")),
			"date": str(round_row.get("date", "")), "legs": int(round_row.get("legs", 1)),
			"complete": bool(round_row.get("complete", false)),
			"ties": ties.size(), "done": _done_count(ties),
		})
	return out


static func _done_count(ties: Array) -> int:
	var done := 0
	for tie in ties:
		if bool((tie as Dictionary).get("played", false)):
			done += 1
	return done


static func ties(season: LeagueSeason, competition_id: String, round_id: String) -> Array:
	var out: Array = []
	for fx in season.record.fixtures.all(-1, competition_id):
		if str(fx.get("stage", "")) != round_id:
			continue
		out.append(fx)
	return out


static func label(competition_id: String, round_id: String) -> String:
	var rule := LeagueCup.round_rule(competition_id, round_id)
	return str(rule.get("name", round_id))


static func current_round(rounds: Array) -> int:
	var last_open := 0
	for i in range(rounds.size()):
		var row: Dictionary = rounds[i]
		if int(row.get("ties", 0)) == 0:
			continue
		last_open = i
		if not bool(row.get("complete", false)):
			return i
	return last_open

