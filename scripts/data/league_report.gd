class_name LeagueReport
extends RefCounted

## The report side of the season ledger: the score a fixture carries and the
## event rows, player lines and top-scorer chart a match leaves behind.
##
## Split out of `LeagueRecord` so results and their readings keep one concern.
## Writes are batched — one statement per fixture for its events and one for the
## twenty-two player lines — so a whole matchday costs a handful of round trips,
## not hundreds, and re-settling a fixture cannot stack a second set of events.

var save: LeagueSave = null
## The goal clips stored beside the ledger's reports (see `LeagueClips`).
var clips: LeagueClips = null

func _init(owner: LeagueSave) -> void:
	save = owner
	clips = LeagueClips.new(owner)

## Store one result. Callers that already hold the fixture pass the two club ids
## so the statement needs no lookup; the table rows then move by the same delta.
func save_result(fixture_id: String, home_goals: int, away_goals: int,
		home_club_id: String = "", away_club_id: String = "",
		standings: LeagueStandings = null) -> bool:
	save.ensure_open()
	var home := home_club_id
	var away := away_club_id
	if home == "" or away == "":
		var row := PLDatabase.row(
			"SELECT home_club_id, away_club_id FROM league_fixture WHERE id = ?;", [fixture_id])
		if row.is_empty():
			return false
		home = str(row["home_club_id"])
		away = str(row["away_club_id"])
	if not PLDatabase.execute(
		"UPDATE league_fixture SET home_goals = ?, away_goals = ?, status = 'played' WHERE id = ?;",
		[home_goals, away_goals, fixture_id],
	):
		return false
	if standings == null:
		return true
	standings.apply(home, home_goals, away_goals, save.rules, "home")
	standings.apply(away, away_goals, home_goals, save.rules, "away")
	return true

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

func top_scorers(limit: int = 5) -> Array:
	save.ensure_open()
	return PLDatabase.rows(
		"SELECT s.goals, s.assists, s.apps, p.name, p.id AS player_id, c.abbr "
		+ "FROM league_player_stat s JOIN player p ON p.id = s.player_id "
		+ "JOIN club c ON c.id = s.club_id WHERE s.goals > 0 "
		+ "ORDER BY s.goals DESC, s.assists DESC, p.name LIMIT ?;",
		[limit],
	)
