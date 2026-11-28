class_name LeagueStandings
extends RefCounted


const TABLE_FIELDS := [
	"played", "won", "drawn", "lost", "gf", "ga", "points",
	"home_played", "home_won", "home_drawn", "home_lost", "home_gf", "home_ga",
	"away_played", "away_won", "away_drawn", "away_lost", "away_gf", "away_ga",
]

var save: LeagueSave = null

func _init(owner: LeagueSave) -> void:
	save = owner


func apply(club_id: String, goals_for: int, goals_against: int, rules: Dictionary,
		side: String, competition_id: String = "") -> void:
	save.ensure_open()
	var comp := competition_id
	if comp == "":
		comp = str(rules.get("competition_id", _default_competition()))
	var won := 0
	var drawn := 0
	var lost := 0
	if goals_for > goals_against:
		won = 1
	elif goals_for == goals_against:
		drawn = 1
	else:
		lost = 1
	var p := side + "_"
	PLDatabase.execute(
		"UPDATE league_table SET played = played + 1, won = won + ?, drawn = drawn + ?, "
		+ "lost = lost + ?, gf = gf + ?, ga = ga + ?, points = points + ?, "
		+ p + "played = " + p + "played + 1, " + p + "won = " + p + "won + ?, "
		+ p + "drawn = " + p + "drawn + ?, " + p + "lost = " + p + "lost + ?, "
		+ p + "gf = " + p + "gf + ?, " + p + "ga = " + p + "ga + ? "
		+ "WHERE club_id = ? AND competition_id = ?;",
		[
			won, drawn, lost, goals_for, goals_against,
			LeagueRules.points(goals_for, goals_against, rules),
			won, drawn, lost, goals_for, goals_against, club_id, comp,
		],
	)


static func _default_competition() -> String:
	return "PL"


func recompute() -> void:
	save.ensure_open()
	var rules_by := save.rules_by
	if rules_by.is_empty():
		rules_by = {str(save.actives[0]) if not save.actives.is_empty() else "PL": save.rules}
	var acc := {}
	var comps: Array = []
	for row in PLDatabase.rows("SELECT DISTINCT competition_id FROM league_fixture;"):
		comps.append(str(row["competition_id"]))
	if comps.is_empty():
		return
	for cid in comps:
		for club_id in _table_clubs(str(cid)):
			var key := "%s|%s" % [str(club_id), str(cid)]
			var zero := {}
			for field in TABLE_FIELDS:
				zero[field] = 0
			acc[key] = zero
	for fx in PLDatabase.rows(
		"SELECT home_club_id, away_club_id, home_goals, away_goals, competition_id, stage "
		+ "FROM league_fixture WHERE status = 'played';"
	):
		var comp := str(fx.get("competition_id", ""))
		if LeagueUefa.is_continental(comp) and str(fx.get("stage", "")) != LeagueUefa.LEAGUE_STAGE:
			continue
		var cid_key := str(fx["competition_id"])
		var rules: Dictionary = rules_by.get(cid_key, save.rules)
		_tally(acc, "%s|%s" % [str(fx["home_club_id"]), cid_key],
			int(fx["home_goals"]), int(fx["away_goals"]), rules, "home")
		_tally(acc, "%s|%s" % [str(fx["away_club_id"]), cid_key],
			int(fx["away_goals"]), int(fx["home_goals"]), rules, "away")
	PLDatabase.execute("DELETE FROM league_table;")
	for cid in comps:
		for club_id in _table_clubs(str(cid)):
			PLDatabase.execute(
				"INSERT INTO league_table (club_id, competition_id) VALUES (?, ?);",
				[str(club_id), str(cid)])
	var sets: Array = []
	for key in TABLE_FIELDS:
		sets.append(key + " = ?")
	var sql := ("UPDATE league_table SET " + ", ".join(sets)
		+ " WHERE club_id = ? AND competition_id = ?;")
	for key in acc.keys():
		var parts := str(key).split("|", true, 1)
		var s: Dictionary = acc[key]
		var bindings: Array = []
		for field in TABLE_FIELDS:
			bindings.append(int(s[field]))
		bindings.append(str(parts[0]))
		bindings.append(str(parts[1]) if parts.size() > 1 else "")
		PLDatabase.execute(sql, bindings)


func _table_clubs(competition_id: String) -> Array:
	var out: Array = []
	if LeagueUefa.is_continental(competition_id):
		for row in PLDatabase.rows(
				"SELECT DISTINCT home_club_id AS id FROM league_fixture "
				+ "WHERE competition_id = ? AND stage = ? "
				+ "UNION SELECT DISTINCT away_club_id AS id FROM league_fixture "
				+ "WHERE competition_id = ? AND stage = ? ORDER BY id;",
				[competition_id, LeagueUefa.LEAGUE_STAGE,
				 competition_id, LeagueUefa.LEAGUE_STAGE]):
			out.append(str(row["id"]))
		return out
	for row in PLDatabase.rows(
			"SELECT id FROM club WHERE competition_id = ? ORDER BY id;", [competition_id]):
		out.append(str(row["id"]))
	return out

func _placeholders(count: int) -> PackedStringArray:
	var out := PackedStringArray()
	for i in range(count):
		out.append("?")
	return out

func _tally(acc: Dictionary, club_id: String, goals_for: int, goals_against: int,
		rules: Dictionary, side: String) -> void:
	if not acc.has(club_id):
		return
	var s: Dictionary = acc[club_id]
	var p := side + "_"
	s["played"] += 1
	s["gf"] += goals_for
	s["ga"] += goals_against
	s["points"] += LeagueRules.points(goals_for, goals_against, rules)
	s[p + "played"] += 1
	s[p + "gf"] += goals_for
	s[p + "ga"] += goals_against
	if goals_for > goals_against:
		s["won"] += 1
		s[p + "won"] += 1
	elif goals_for == goals_against:
		s["drawn"] += 1
		s[p + "drawn"] += 1
	else:
		s["lost"] += 1
		s[p + "lost"] += 1


func table(competition_id: String = "") -> Array:
	save.ensure_open()
	var sql := (
		"SELECT t.*, c.name AS club_name, c.abbr AS club_abbr, c.color AS club_color "
		+ "FROM league_table t JOIN club c ON c.id = t.club_id"
	)
	var rows: Array = []
	if competition_id == "":
		rows = PLDatabase.rows(
			sql + " ORDER BY t.competition_id, t.points DESC, (t.gf - t.ga) DESC, "
			+ "t.gf DESC, c.name ASC;")
	else:
		rows = PLDatabase.rows(
			sql + " WHERE t.competition_id = ? ORDER BY t.points DESC, (t.gf - t.ga) DESC, "
			+ "t.gf DESC, c.name ASC;", [competition_id])
	var place := 0
	var last := ""
	for i in range(rows.size()):
		var comp := str(rows[i].get("competition_id", ""))
		place = 1 if comp != last else place + 1
		last = comp
		rows[i]["position"] = place
	return rows
