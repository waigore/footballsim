class_name LeagueEuropeDraws
extends RefCounted


static func seen(save: LeagueSave, competition_id: String, round_id: String) -> bool:
	return str(save.meta.get(_marker(competition_id, round_id), "")) == "1"


static func mark_seen(save: LeagueSave, competition_id: String, round_id: String) -> void:
	if save != null:
		save.put_meta(_marker(competition_id, round_id), "1")


static func _marker(competition_id: String, round_id: String) -> String:
	return "uefa_draw:%s:%s" % [competition_id, round_id]


static func drawn(competition_id: String, round_id: String) -> bool:
	if round_id == LeagueUefa.LEAGUE_STAGE:
		var phase := PLDatabase.row(
			"SELECT 1 AS n FROM league_fixture WHERE competition_id = ? AND stage = ? LIMIT 1;",
			[competition_id, round_id])
		return not phase.is_empty()
	var ties := PLDatabase.row(
		"SELECT 1 AS n FROM cup_tie WHERE competition_id = ? AND round_id = ? LIMIT 1;",
		[competition_id, round_id])
	return not ties.is_empty()


static func pending_draws(save: LeagueSave) -> Array:
	var out: Array = []
	for cid in LeagueEurope.active_ids(save):
		for rid in LeagueUefa.round_ids(cid):
			var round_id := str(rid)
			if not LeagueUefa.has_stage(str(cid), round_id):
				continue
			if not drawn(str(cid), round_id):
				continue
			if seen(save, str(cid), round_id):
				continue
			out.append({"competition": str(cid), "round": round_id,
				"label": "%s · %s" % [str(cid), LeagueEurope.badge(round_id)]})
	return out


static func draw_data(save: LeagueSave, competition_id: String, round_id: String) -> Dictionary:
	var comp := PLRepository.shared().competition(competition_id)
	return {
		"competition": competition_id,
		"short": str(comp.get("short_name", competition_id)),
		"name": str(comp.get("name", competition_id)),
		"round": round_id,
		"title": LeagueEurope.round_title(competition_id, round_id) + " DRAW",
		"date": str(LeagueUefa.round_rule(competition_id, round_id).get("date", "")),
		"pots": pots(save, competition_id, round_id),
		"fixtures": pairs(competition_id, round_id),
	}


static func pots(save: LeagueSave, competition_id: String, round_id: String) -> Array:
	if round_id != LeagueUefa.LEAGUE_STAGE:
		var entrants: Array = []
		for tie in LeagueEuropeTies.rows(competition_id, round_id, {}, {}):
			for key in ["home", "away"]:
				if not entrants.has(str(tie[key])):
					entrants.append(str(tie[key]))
		return [pot(entrants)]
	var ranked := ranked_clubs(save, competition_id)
	var out: Array = []
	var each := int(ceil(float(ranked.size()) / float(maxi(LeagueUefa.pots(competition_id), 1))))
	for i in range(LeagueUefa.pots(competition_id)):
		var start := i * each
		if start >= ranked.size():
			break
		out.append(pot(ranked.slice(start, mini(start + each, ranked.size()))))
	return out


static func pot(club_ids: Array) -> Array:
	var out: Array = []
	for club_id in club_ids:
		var club := PLRepository.shared().club(str(club_id))
		out.append({"id": str(club_id), "name": str(club.get("name", club_id)),
			"short": str(club.get("short", club.get("abbr", club_id))),
			"country": str(club.get("country", ""))})
	return out


static func ranked_clubs(save: LeagueSave, competition_id: String) -> Array:
	var clubs: Array = []
	for row in PLDatabase.rows(
			"SELECT club_id FROM league_table WHERE competition_id = ?;", [competition_id]):
		clubs.append(str(row["club_id"]))
	return LeagueUefaBands.ranked(LeagueUefaBands.ensure_bands(save, competition_id, clubs), clubs)


static func pairs(competition_id: String, round_id: String) -> Array:
	if round_id == LeagueUefa.LEAGUE_STAGE:
		var out: Array = []
		for fx in PLDatabase.rows(
				"SELECT f.*, h.name AS home_name, a.name AS away_name FROM league_fixture f "
				+ "JOIN club h ON h.id = f.home_club_id JOIN club a ON a.id = f.away_club_id "
				+ "WHERE f.competition_id = ? AND f.stage = ? ORDER BY f.matchday, f.kickoff, f.id;",
				[competition_id, round_id]):
			out.append({"home": str(fx["home_club_id"]), "away": str(fx["away_club_id"]),
				"home_name": str(fx["home_name"]), "away_name": str(fx["away_name"]),
				"date": str(fx["kickoff"]), "matchday": int(fx["matchday"])})
		return out
	var ties: Array = []
	for tie in LeagueEuropeTies.rows(competition_id, round_id, {}, {}):
		ties.append({"home": str(tie["home"]), "away": str(tie["away"]),
			"home_name": str(tie["home_name"]), "away_name": str(tie["away_name"]),
			"date": str(LeagueUefa.round_rule(competition_id, round_id).get("date", "")),
			"matchday": 0})
	return ties
