class_name LeagueRecord
extends RefCounted

## The season ledger inside one save: fixtures, results, match events, the live
## table and season player totals.
##
## Everything here talks to whichever database PLDatabase is bound to — the save
## — so the planner, the table screen and the encyclopedia all read one source.
## Writes are batched: one statement per fixture for the result, one for its
## events and one for the twenty-two player lines, with the table moved by the
## same statement that stores the score. A whole matchday therefore costs a
## handful of round trips, not hundreds.

var save: LeagueSave = null

const FIXTURE_SELECT := (
	"SELECT f.*, h.name AS home_name, h.abbr AS home_abbr, h.color AS home_color, "
	+ "a.name AS away_name, a.abbr AS away_abbr, a.color AS away_color "
	+ "FROM league_fixture f JOIN club h ON h.id = f.home_club_id "
	+ "JOIN club a ON a.id = f.away_club_id "
)

func _init(owner: LeagueSave) -> void:
	save = owner

# --------------------------------------------------------------- fixtures ---

## Fill an empty save: every fixture pending, every club on zero, the clock on
## the first fixture date.
func install(fixtures: Array) -> bool:
	if save == null or fixtures.is_empty():
		return false
	if not save.ensure_open():
		return false
	PLDatabase.transaction("BEGIN TRANSACTION;")
	PLDatabase.execute("DELETE FROM league_fixture;")
	PLDatabase.execute("DELETE FROM league_table;")
	PLDatabase.execute("DELETE FROM match_event;")
	PLDatabase.execute("DELETE FROM league_player_stat;")
	var values: Array = []
	var bindings: Array = []
	for fx in fixtures:
		values.append("(?, ?, ?, ?, ?, ?, 'pending')")
		bindings.append_array([
			str(fx["id"]), int(fx["matchday"]), str(fx["kickoff"]),
			str(fx.get("kickoff_time", "")), str(fx["home"]), str(fx["away"]),
		])
	PLDatabase.execute(
		"INSERT INTO league_fixture (id, matchday, kickoff, kickoff_time, home_club_id, "
		+ "away_club_id, status) VALUES " + ", ".join(values) + ";",
		bindings,
	)
	PLDatabase.execute("INSERT INTO league_table (club_id) SELECT id FROM club;")
	save.set_date(str(fixtures[0]["kickoff"]))
	save.set_matchday(int(fixtures[0]["matchday"]))
	save.set_status("in_progress")
	PLDatabase.transaction("COMMIT;")
	return true

## Fixture rows with club labels. `matchday` < 1 returns the whole calendar.
func fixtures(matchday: int = -1) -> Array:
	save.ensure_open()
	if matchday < 1:
		return PLDatabase.rows(FIXTURE_SELECT + "ORDER BY f.kickoff, f.kickoff_time, f.id;")
	return PLDatabase.rows(
		FIXTURE_SELECT + "WHERE f.matchday = ? ORDER BY f.kickoff_time, f.id;", [matchday])

func fixture(fixture_id: String) -> Dictionary:
	save.ensure_open()
	var rows := PLDatabase.rows(FIXTURE_SELECT + "WHERE f.id = ?;", [fixture_id])
	return rows[0] if not rows.is_empty() else {}

func fixtures_on(date: String) -> Array:
	save.ensure_open()
	return PLDatabase.rows(
		FIXTURE_SELECT + "WHERE f.kickoff = ? ORDER BY f.kickoff_time, f.id;", [date])

## Unplayed fixtures due on or before `date`: the season clock never runs past
## a watched fixture waiting for its match.
func pending_upto(date: String) -> Array:
	save.ensure_open()
	return PLDatabase.rows(
		FIXTURE_SELECT + "WHERE f.status <> 'played' AND f.kickoff <= ? "
		+ "ORDER BY f.kickoff, f.kickoff_time, f.id;", [date])

func dates() -> Array:
	save.ensure_open()
	var out: Array = []
	for row in PLDatabase.rows("SELECT DISTINCT kickoff FROM league_fixture ORDER BY kickoff;"):
		out.append(str(row["kickoff"]))
	return out

func unplayed() -> int:
	save.ensure_open()
	var row := PLDatabase.row("SELECT COUNT(*) AS n FROM league_fixture WHERE status <> 'played';")
	return int(row.get("n", 0))

func played() -> int:
	save.ensure_open()
	var row := PLDatabase.row("SELECT COUNT(*) AS n FROM league_fixture WHERE status = 'played';")
	return int(row.get("n", 0))

## The next date with a pending fixture, strictly after `after`.
func next_date(after: String) -> String:
	save.ensure_open()
	var row := PLDatabase.row(
		"SELECT MIN(kickoff) AS d FROM league_fixture WHERE status <> 'played' AND kickoff > ?;",
		[after],
	)
	if row.get("d", null) == null:
		return ""
	return str(row["d"])

func set_watch(fixture_id: String, watch: bool) -> bool:
	save.ensure_open()
	return PLDatabase.execute(
		"UPDATE league_fixture SET watched = ? WHERE id = ?;",
		[1 if watch else 0, fixture_id],
	)

func clear_suggestions() -> void:
	save.ensure_open()
	PLDatabase.execute("UPDATE league_fixture SET suggested = 0;")

func suggest(fixture_ids: Array) -> void:
	clear_suggestions()
	for id in fixture_ids:
		PLDatabase.execute("UPDATE league_fixture SET suggested = 1 WHERE id = ?;", [str(id)])

# ---------------------------------------------------------------- results ---

## Store one result and move both table rows by the same delta. Callers that
## already hold the fixture pass the two club ids and skip the lookup: a played
## matchday settles ten fixtures in a handful of round trips.
func save_result(fixture_id: String, home_goals: int, away_goals: int,
		home_club_id: String = "", away_club_id: String = "") -> bool:
	save.ensure_open()
	var home := home_club_id
	var away := away_club_id
	if home == "" or away == "":
		var fx := fixture(fixture_id)
		if fx.is_empty():
			return false
		home = str(fx["home_club_id"])
		away = str(fx["away_club_id"])
	if not PLDatabase.execute(
		"UPDATE league_fixture SET home_goals = ?, away_goals = ?, status = 'played' WHERE id = ?;",
		[home_goals, away_goals, fixture_id],
	):
		return false
	_apply_table(home, home_goals, away_goals, save.rules)
	_apply_table(away, away_goals, home_goals, save.rules)
	return true

func _apply_table(club_id: String, goals_for: int, goals_against: int, rules: Dictionary) -> void:
	var won := 1 if goals_for > goals_against else 0
	var drawn := 1 if goals_for == goals_against else 0
	var lost := 1 if goals_for < goals_against else 0
	PLDatabase.execute(
		"UPDATE league_table SET played = played + 1, won = won + ?, drawn = drawn + ?, "
		+ "lost = lost + ?, gf = gf + ?, ga = ga + ?, points = points + ? WHERE club_id = ?;",
		[
			won, drawn, lost, goals_for, goals_against,
			LeagueRules.points(goals_for, goals_against, rules), club_id,
		],
	)

func add_events(rows: Array) -> void:
	save.ensure_open()
	if rows.is_empty():
		return
	var values: Array = []
	var bindings: Array = []
	for e in rows:
		values.append("(?, ?, ?, ?, ?, ?)")
		bindings.append_array([
			str(e.get("fixture_id", "")), int(e.get("minute", 0)), str(e.get("kind", "")),
			str(e.get("player_id", "")), str(e.get("club_id", "")), str(e.get("detail", "")),
		])
	PLDatabase.execute(
		"INSERT INTO match_event (fixture_id, minute, kind, player_id, club_id, detail) "
		+ "VALUES " + ", ".join(values) + ";",
		bindings,
	)

func events(fixture_id: String) -> Array:
	save.ensure_open()
	return PLDatabase.rows(
		"SELECT e.*, p.name AS player_name FROM match_event e "
		+ "LEFT JOIN player p ON p.id = e.player_id WHERE e.fixture_id = ? "
		+ "ORDER BY e.minute, e.id;",
		[fixture_id],
	)

## Add one player's match line to the season totals (apps, goals, assists,
## cards). Called for the XI of an auto-simmed side and for every player a
## watched match actually used.
func add_player_line(player_id: String, club_id: String, line: Dictionary) -> void:
	add_player_lines([{"player_id": player_id, "club_id": club_id, "line": line}])

## One statement for a whole squad's match lines.
func add_player_lines(rows: Array) -> void:
	save.ensure_open()
	var values: Array = []
	var bindings: Array = []
	for row in rows:
		var player_id := str(row.get("player_id", ""))
		var club_id := str(row.get("club_id", ""))
		if player_id == "" or club_id == "":
			continue
		var line: Dictionary = row.get("line", {})
		values.append("(?, ?, ?, ?, ?, ?, ?)")
		bindings.append_array([
			player_id, club_id, int(line.get("apps", 1)), int(line.get("goals", 0)),
			int(line.get("assists", 0)), int(line.get("yellow", 0)), int(line.get("red", 0)),
		])
	if values.is_empty():
		return
	PLDatabase.execute(
		"INSERT INTO league_player_stat (player_id, club_id, apps, goals, assists, yellow, red) "
		+ "VALUES " + ", ".join(values) + " ON CONFLICT(player_id) DO UPDATE SET "
		+ "apps = apps + excluded.apps, goals = goals + excluded.goals, "
		+ "assists = assists + excluded.assists, yellow = yellow + excluded.yellow, "
		+ "red = red + excluded.red;",
		bindings,
	)

# ------------------------------------------------------------------ table ---

## Rebuild the live table from every played fixture. The per-match path moves
## rows incrementally; this is the repair/import path.
func recompute_table() -> void:
	save.ensure_open()
	var acc := {}
	for row in PLDatabase.rows("SELECT id FROM club;"):
		acc[str(row["id"])] = {"played": 0, "won": 0, "drawn": 0, "lost": 0, "gf": 0, "ga": 0, "points": 0}
	var rules := save.rules
	for fx in PLDatabase.rows(
		"SELECT home_club_id, away_club_id, home_goals, away_goals FROM league_fixture "
		+ "WHERE status = 'played';"
	):
		_apply(acc, str(fx["home_club_id"]), int(fx["home_goals"]), int(fx["away_goals"]), rules)
		_apply(acc, str(fx["away_club_id"]), int(fx["away_goals"]), int(fx["home_goals"]), rules)
	PLDatabase.execute("DELETE FROM league_table;")
	PLDatabase.execute("INSERT INTO league_table (club_id) SELECT id FROM club;")
	for club_id in acc.keys():
		var s: Dictionary = acc[club_id]
		PLDatabase.execute(
			"UPDATE league_table SET played = ?, won = ?, drawn = ?, lost = ?, "
			+ "gf = ?, ga = ?, points = ? WHERE club_id = ?;",
			[
				int(s["played"]), int(s["won"]), int(s["drawn"]), int(s["lost"]),
				int(s["gf"]), int(s["ga"]), int(s["points"]), str(club_id),
			],
		)

func _apply(acc: Dictionary, club_id: String, goals_for: int, goals_against: int, rules: Dictionary) -> void:
	if not acc.has(club_id):
		return
	var s: Dictionary = acc[club_id]
	s["played"] += 1
	s["gf"] += goals_for
	s["ga"] += goals_against
	s["points"] += LeagueRules.points(goals_for, goals_against, rules)
	if goals_for > goals_against:
		s["won"] += 1
	elif goals_for == goals_against:
		s["drawn"] += 1
	else:
		s["lost"] += 1

## Standings with the club labels the table screen draws and a 1-based position.
func table() -> Array:
	save.ensure_open()
	var rows := PLDatabase.rows(
		"SELECT t.*, c.name AS club_name, c.abbr AS club_abbr, c.color AS club_color "
		+ "FROM league_table t JOIN club c ON c.id = t.club_id "
		+ "ORDER BY t.points DESC, (t.gf - t.ga) DESC, t.gf DESC, c.name ASC;"
	)
	for i in range(rows.size()):
		rows[i]["position"] = i + 1
	return rows

## How many gameweeks are fully played: the "after five rounds" trigger for
## suggested watches. Rounds never complete out of order, so the first round
## with a pending fixture ends the streak.
func completed_matchdays() -> int:
	save.ensure_open()
	var row := PLDatabase.row(
		"SELECT MIN(matchday) AS r FROM league_fixture WHERE status <> 'played';")
	if row.get("r", null) == null:
		var total := PLDatabase.row("SELECT MAX(matchday) AS r FROM league_fixture;")
		return int(total.get("r", 0))
	return maxi(int(row["r"]) - 1, 0)

func top_scorers(limit: int = 5) -> Array:
	save.ensure_open()
	return PLDatabase.rows(
		"SELECT s.goals, s.assists, s.apps, p.name, p.id AS player_id, c.abbr "
		+ "FROM league_player_stat s JOIN player p ON p.id = s.player_id "
		+ "JOIN club c ON c.id = s.club_id WHERE s.goals > 0 "
		+ "ORDER BY s.goals DESC, s.assists DESC, p.name LIMIT ?;",
		[limit],
	)
