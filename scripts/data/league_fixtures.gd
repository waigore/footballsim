class_name LeagueFixtures
extends RefCounted

## The calendar side of the season ledger: which fixtures are due, which are
## played, and the watch and suggestion flags the planner writes on them.
##
## One fixture table per save, read by the season clock, the calendar screen and
## the planner. Split out of `LeagueRecord` so the calendar and the standings
## keep one concern each; every reader talks to the same bound save, so a fixture
## moved here is still the one a result lands on.

const SELECT := (
	"SELECT f.*, h.name AS home_name, h.abbr AS home_abbr, h.color AS home_color, "
	+ "a.name AS away_name, a.abbr AS away_abbr, a.color AS away_color "
	+ "FROM league_fixture f JOIN club h ON h.id = f.home_club_id "
	+ "JOIN club a ON a.id = f.away_club_id "
)

var save: LeagueSave = null

func _init(owner: LeagueSave) -> void:
	save = owner

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
	PLDatabase.execute("DELETE FROM goal_highlight;")
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
func all(matchday: int = -1) -> Array:
	save.ensure_open()
	if matchday < 1:
		return PLDatabase.rows(SELECT + "ORDER BY f.kickoff, f.kickoff_time, f.id;")
	return PLDatabase.rows(SELECT + "WHERE f.matchday = ? ORDER BY f.kickoff_time, f.id;", [matchday])

func one(fixture_id: String) -> Dictionary:
	save.ensure_open()
	var rows := PLDatabase.rows(SELECT + "WHERE f.id = ?;", [fixture_id])
	return rows[0] if not rows.is_empty() else {}

func on(date: String) -> Array:
	save.ensure_open()
	return PLDatabase.rows(SELECT + "WHERE f.kickoff = ? ORDER BY f.kickoff_time, f.id;", [date])

## Unplayed fixtures due on or before `date`: the season clock never runs past
## a watched fixture waiting for its match.
func pending_upto(date: String) -> Array:
	save.ensure_open()
	return PLDatabase.rows(
		SELECT + "WHERE f.status <> 'played' AND f.kickoff <= ? "
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
