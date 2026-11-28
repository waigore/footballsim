class_name LeagueEurope
extends RefCounted


const KO_ROUNDS := ["KOPO", "R16", "QF", "SF", "F"]

const BADGE := {
	"Q1": "Q1", "Q2CH": "Q2", "Q2LP": "Q2", "Q2MP": "Q2",
	"Q3CH": "Q3", "Q3LP": "Q3", "Q3MP": "Q3", "PO": "PLAY-OFF",
	"POCH": "PLAY-OFF", "POLP": "PLAY-OFF", "POMP": "PLAY-OFF",
	"LP": "LEAGUE PHASE", "KOPO": "KO PLAY-OFF", "R16": "R16",
	"QF": "QUARTER-FINAL", "SF": "SEMI-FINAL", "F": "FINAL",
}


static func active_ids(save: LeagueSave) -> Array:
	return LeagueUefa.active_ids(save)


static func available() -> bool:
	return not PLRepository.shared().continentals().is_empty()


static func runs(save: LeagueSave) -> bool:
	return not active_ids(save).is_empty()


static func badge(round_id: String) -> String:
	return str(BADGE.get(round_id, round_id))


static func round_title(competition_id: String, round_id: String) -> String:
	var rule := LeagueUefa.round_rule(competition_id, round_id)
	var name := str(rule.get("name", badge(round_id))).to_upper()
	var path := str(rule.get("path", ""))
	if path == "CH":
		return name + " · CHAMPIONS PATH"
	if path == "LP" or path == "MP":
		return name + " · LEAGUE PATH"
	return name


static func stage_of(competition_id: String) -> String:
	var out := ""
	for rid in LeagueUefa.round_ids(competition_id):
		if LeagueUefa.has_stage(competition_id, str(rid)):
			out = str(rid)
	return out


static func stage_label(competition_id: String) -> String:
	var stage := stage_of(competition_id)
	if stage == "":
		return "NOT DRAWN"
	var complete := LeagueUefa.stage_complete(competition_id, stage)
	if stage == LeagueUefa.LEAGUE_STAGE:
		if complete:
			return "LEAGUE PHASE COMPLETE"
		return "LEAGUE PHASE MD %d" % league_matchday(competition_id)
	if KO_ROUNDS.has(stage):
		if complete:
			return badge(stage) + " · COMPLETE"
		return badge(stage)
	if complete:
		return "QUALIFYING %s · COMPLETE" % badge(stage)
	return "QUALIFYING %s" % badge(stage)


static func league_matchday(competition_id: String) -> int:
	var row := PLDatabase.row(
		"SELECT MIN(matchday) AS n FROM league_fixture WHERE competition_id = ? "
		+ "AND stage = ? AND status <> 'played';", [competition_id, LeagueUefa.LEAGUE_STAGE])
	if row.get("n", null) != null:
		return int(row["n"])
	var last := PLDatabase.row(
		"SELECT MAX(matchday) AS n FROM league_fixture WHERE competition_id = ? AND stage = ?;",
		[competition_id, LeagueUefa.LEAGUE_STAGE])
	return int(last.get("n", 0))


static func alive(competition_id: String) -> int:
	var stage := stage_of(competition_id)
	if stage == "":
		return 0
	if stage == LeagueUefa.LEAGUE_STAGE:
		var row := PLDatabase.row(
			"SELECT COUNT(*) AS n FROM league_table WHERE competition_id = ?;", [competition_id])
		return int(row.get("n", 0))
	var ties := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM (SELECT home_club_id AS c FROM cup_tie "
		+ "WHERE competition_id = ? AND round_id = ? UNION SELECT away_club_id FROM cup_tie "
		+ "WHERE competition_id = ? AND round_id = ?);",
		[competition_id, stage, competition_id, stage])
	return int(ties.get("n", 0))


static func next_night(save: LeagueSave, competition_id: String = "") -> String:
	if save == null:
		return ""
	var sql := "SELECT MIN(kickoff) AS d FROM league_fixture WHERE status <> 'played'"
	var bindings: Array = []
	if competition_id != "":
		sql += " AND competition_id = ?"
		bindings.append(competition_id)
	var row := PLDatabase.row(sql + ";", bindings)
	if row.get("d", null) == null:
		return ""
	return str(row["d"])


static func card(save: LeagueSave, competition_id: String) -> Dictionary:
	var comp := PLRepository.shared().competition(competition_id)
	var stage := stage_of(competition_id)
	return {
		"id": competition_id,
		"name": str(comp.get("name", competition_id)),
		"short": str(comp.get("short_name", competition_id)),
		"stage": stage_label(competition_id),
		"alive": alive(competition_id),
		"next": next_night(save, competition_id),
		"done": stage != "" and LeagueUefa.stage_complete(competition_id, stage),
		"entry": LeagueEuropeEntries.summary(save, competition_id),
	}


static func tonight(save: LeagueSave) -> Array:
	if save == null:
		return []
	var out: Array = []
	for cid in active_ids(save):
		for fx in PLDatabase.rows(
				"SELECT f.*, h.name AS home_name, h.abbr AS home_abbr, a.name AS away_name, "
				+ "a.abbr AS away_abbr FROM league_fixture f JOIN club h ON h.id = f.home_club_id "
				+ "JOIN club a ON a.id = f.away_club_id WHERE f.competition_id = ? AND f.kickoff = ? "
				+ "ORDER BY f.kickoff_time, f.id;", [str(cid), save.current_date()]):
			out.append(fx)
	return out


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
	for cid in active_ids(save):
		for rid in LeagueUefa.round_ids(cid):
			var round_id := str(rid)
			if not LeagueUefa.has_stage(str(cid), round_id):
				continue
			if not drawn(str(cid), round_id):
				continue
			if seen(save, str(cid), round_id):
				continue
			out.append({"competition": str(cid), "round": round_id,
				"label": "%s · %s" % [str(cid), badge(round_id)]})
	return out


static func draw_data(save: LeagueSave, competition_id: String, round_id: String) -> Dictionary:
	var comp := PLRepository.shared().competition(competition_id)
	return {
		"competition": competition_id,
		"short": str(comp.get("short_name", competition_id)),
		"name": str(comp.get("name", competition_id)),
		"round": round_id,
		"title": round_title(competition_id, round_id) + " DRAW",
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


static func honours(save: LeagueSave) -> Array:
	var out: Array = []
	for cid in active_ids(save):
		var competition_id := str(cid)
		var tie := LeagueCupState.final(competition_id)
		if tie.is_empty() or str(tie.get("winner_club_id", "")) == "":
			continue
		var winner := str(tie["winner_club_id"])
		var home := str(tie.get("home_club_id", ""))
		var runner := str(tie.get("away_club_id", "")) if winner == home \
			else str(tie.get("home_club_id", ""))
		var comp := PLRepository.shared().competition(competition_id)
		out.append({"id": competition_id,
			"name": str(comp.get("name", competition_id)),
			"short": str(comp.get("short_name", competition_id)),
			"winner": winner, "winner_name": LeagueUefa.club_name(winner),
			"runner_up": runner, "runner_up_name": LeagueUefa.club_name(runner),
			"home_goals": int(tie.get("home_goals", 0)), "away_goals": int(tie.get("away_goals", 0)),
			"pens_home": int(tie.get("pens_home", -1)), "pens_away": int(tie.get("pens_away", -1)),
			"extra_time": int(tie.get("extra_time", 0)) == 1,
			"winner_home": winner == home})
	return out


static func score_line(honour: Dictionary) -> String:
	var home := int(honour.get("home_goals", 0))
	var away := int(honour.get("away_goals", 0))
	var winner_home := bool(honour.get("winner_home", true))
	var line := "%d–%d" % [home, away]
	if not winner_home:
		line = "%d–%d" % [away, home]
	if int(honour.get("pens_home", -1)) >= 0:
		var pens_home := int(honour.get("pens_home", 0))
		var pens_away := int(honour.get("pens_away", 0))
		var won: int = pens_home if winner_home else pens_away
		var lost: int = pens_away if winner_home else pens_home
		line += " · %d–%d PENS" % [won, lost]
	elif bool(honour.get("extra_time", false)):
		line += " · AET"
	return line
