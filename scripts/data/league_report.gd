class_name LeagueReport
extends RefCounted


var save: LeagueSave = null

var clips: LeagueClips = null


var memo := {}

func _init(owner: LeagueSave) -> void:
	save = owner
	clips = LeagueClips.new(owner)


func save_result(fixture_id: String, home_goals: int, away_goals: int,
		home_club_id: String = "", away_club_id: String = "",
		standings: LeagueStandings = null, competition_id: String = "") -> bool:
	save.ensure_open()
	var home := home_club_id
	var away := away_club_id
	var comp := competition_id
	if home == "" or away == "" or comp == "":
		var row := PLDatabase.row(
			"SELECT home_club_id, away_club_id, competition_id FROM league_fixture WHERE id = ?;",
			[fixture_id])
		if row.is_empty():
			return false
		home = str(row["home_club_id"])
		away = str(row["away_club_id"])
		comp = str(row.get("competition_id", comp))
	if not PLDatabase.execute(
		"UPDATE league_fixture SET home_goals = ?, away_goals = ?, status = 'played' WHERE id = ?;",
		[home_goals, away_goals, fixture_id],
	):
		return false
	if standings == null:
		return true
	var rules := save.rules_for(comp)
	standings.apply(home, home_goals, away_goals, rules, "home", comp)
	standings.apply(away, away_goals, home_goals, rules, "away", comp)
	return true

func add_events(rows: Array) -> void:
	save.ensure_open()
	if rows.is_empty():
		return
	memo.clear()
	var values: Array = []
	var bindings: Array = []
	for e in rows:
		values.append("(?, ?, ?, ?, ?, ?, ?)")
		bindings.append_array([
			str(e.get("fixture_id", "")), int(e.get("minute", 0)), str(e.get("kind", "")),
			str(e.get("player_id", "")), str(e.get("club_id", "")), str(e.get("detail", "")),
			1 if bool(e.get("penalty", false)) else 0,
		])
	PLDatabase.execute(
		"INSERT INTO match_event (fixture_id, minute, kind, player_id, club_id, detail, penalty) "
		+ "VALUES " + ", ".join(values) + ";",
		bindings,
	)

func events(fixture_id: String) -> Array:
	save.ensure_open()
	if memo.has(fixture_id):
		return memo[fixture_id]
	var rows := PLDatabase.rows(
		"SELECT e.*, p.name AS player_name FROM match_event e "
		+ "LEFT JOIN player p ON p.id = e.player_id WHERE e.fixture_id = ? "
		+ "ORDER BY e.minute, e.id;",
		[fixture_id],
	)

	memo[fixture_id] = rows
	return rows


func add_player_line(player_id: String, club_id: String, line: Dictionary) -> void:
	add_player_lines([{"player_id": player_id, "club_id": club_id, "line": line}])


func add_player_lines(rows: Array) -> void:
	save.ensure_open()
	var values: Array = []
	var bindings: Array = []
	var comp_of := {}
	for row in rows:
		var player_id := str(row.get("player_id", ""))
		var club_id := str(row.get("club_id", ""))
		if player_id == "" or club_id == "":
			continue
		if not comp_of.has(club_id):
			var club := PLDatabase.row("SELECT competition_id FROM club WHERE id = ?;", [club_id])
			comp_of[club_id] = str(club.get("competition_id", ""))
		var line: Dictionary = row.get("line", {})
		values.append("(?, ?, ?, ?, ?, ?, ?, ?)")
		bindings.append_array([
			player_id, str(comp_of[club_id]), club_id, int(line.get("apps", 1)),
			int(line.get("goals", 0)), int(line.get("assists", 0)),
			int(line.get("yellow", 0)), int(line.get("red", 0)),
		])
	if values.is_empty():
		return
	PLDatabase.execute(
		"INSERT INTO league_player_stat (player_id, competition_id, club_id, apps, goals, "
		+ "assists, yellow, red) VALUES " + ", ".join(values)
		+ " ON CONFLICT(player_id) DO UPDATE SET "
		+ "apps = apps + excluded.apps, goals = goals + excluded.goals, "
		+ "assists = assists + excluded.assists, yellow = yellow + excluded.yellow, "
		+ "red = red + excluded.red;",
		bindings,
	)

func top_scorers(limit: int = 5, competition_id: String = "") -> Array:
	save.ensure_open()
	var sql := (
		"SELECT s.goals, s.assists, s.apps, p.name, p.id AS player_id, c.abbr, "
		+ "c.name AS club_name "
		+ "FROM league_player_stat s JOIN player p ON p.id = s.player_id "
		+ "JOIN club c ON c.id = s.club_id WHERE s.goals > 0"
	)
	var bindings: Array = []
	if competition_id != "":
		sql += " AND s.competition_id = ?"
		bindings.append(competition_id)
	sql += " ORDER BY s.goals DESC, s.assists DESC, p.name LIMIT ?;"
	bindings.append(limit)
	return PLDatabase.rows(sql, bindings)
