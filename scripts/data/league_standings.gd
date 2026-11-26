class_name LeagueStandings
extends RefCounted

## The standings side of the season ledger: the live table, the per-result move
## and the repair path an older save takes when it opens.
##
## Every aggregate a row keeps — the official set plus the home and away splits
## the full table reads (#73) — is listed once here, so the zero row, the single
## result write, the recompute write and its bindings can never drift apart.
## Split out of `LeagueRecord` so the table keeps one concern; both talk to the
## same bound save, minutes after `LeagueFixtures` installed the calendar.
##
## One table per active competition, keyed by `competition_id`. A club belongs to
## exactly one domestic league, so the club id alone finds its row; every league-
## wide read filters on the competition and reads that competition's rules.

const TABLE_FIELDS := [
	"played", "won", "drawn", "lost", "gf", "ga", "points",
	"home_played", "home_won", "home_drawn", "home_lost", "home_gf", "home_ga",
	"away_played", "away_won", "away_drawn", "away_lost", "away_gf", "away_ga",
]

var save: LeagueSave = null

func _init(owner: LeagueSave) -> void:
	save = owner

## Move one club's row by a result. The overall columns and that club's own side
## columns move in the same statement, so a full table and the official order
## are always one ledger (#73).
func apply(club_id: String, goals_for: int, goals_against: int, rules: Dictionary,
		side: String) -> void:
	save.ensure_open()
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
		+ p + "gf = " + p + "gf + ?, " + p + "ga = " + p + "ga + ? WHERE club_id = ?;",
		[
			won, drawn, lost, goals_for, goals_against,
			LeagueRules.points(goals_for, goals_against, rules),
			won, drawn, lost, goals_for, goals_against, club_id,
		],
	)

## Rebuild every live table from every played fixture. The per-match path moves
## rows incrementally; this is the repair/import path and the one an older save
## takes when it opens (#73), so overall and home/away always agree again. Each
## competition is tallied with its own regulations.
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
	for row in PLDatabase.rows("SELECT id, competition_id FROM club;"):
		if not comps.has(str(row["competition_id"])):
			continue
		var zero := {}
		for key in TABLE_FIELDS:
			zero[key] = 0
		acc[str(row["id"])] = zero
	for fx in PLDatabase.rows(
		"SELECT home_club_id, away_club_id, home_goals, away_goals, competition_id "
		+ "FROM league_fixture WHERE status = 'played';"
	):
		var rules: Dictionary = rules_by.get(str(fx.get("competition_id", "")), save.rules)
		_tally(acc, str(fx["home_club_id"]), int(fx["home_goals"]), int(fx["away_goals"]),
			rules, "home")
		_tally(acc, str(fx["away_club_id"]), int(fx["away_goals"]), int(fx["home_goals"]),
			rules, "away")
	PLDatabase.execute("DELETE FROM league_table;")
	PLDatabase.execute(
		"INSERT INTO league_table (club_id, competition_id) SELECT id, competition_id FROM club "
		+ "WHERE competition_id IN (" + ",".join(_placeholders(comps.size())) + ");", comps)
	var sets: Array = []
	for key in TABLE_FIELDS:
		sets.append(key + " = ?")
	var sql := "UPDATE league_table SET " + ", ".join(sets) + " WHERE club_id = ?;"
	for club_id in acc.keys():
		var s: Dictionary = acc[club_id]
		var bindings: Array = []
		for key in TABLE_FIELDS:
			bindings.append(int(s[key]))
		bindings.append(str(club_id))
		PLDatabase.execute(sql, bindings)

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

## Standings with the club labels the table screen draws and a 1-based position.
## One competition's when an id is given; otherwise every active league, each
## numbered from one (the encyclopedia's multi-league index).
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
