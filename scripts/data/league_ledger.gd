class_name LeagueLedger
extends RefCounted


const TABLE_SELECT := (
	"SELECT t.*, c.name AS club_name, c.abbr AS club_abbr, c.color AS club_color "
	+ "FROM league_table t JOIN club c ON c.id = t.club_id "
)

const FIXTURE_SELECT := (
	"SELECT f.*, h.name AS home_name, h.abbr AS home_abbr, a.name AS away_name, "
	+ "a.abbr AS away_abbr, 1 AS played "
	+ "FROM league_fixture f JOIN club h ON h.id = f.home_club_id "
	+ "JOIN club a ON a.id = f.away_club_id "
)


const UPCOMING_SELECT := (
	"SELECT f.*, h.name AS home_name, h.abbr AS home_abbr, a.name AS away_name, "
	+ "a.abbr AS away_abbr, 0 AS played "
	+ "FROM league_fixture f JOIN club h ON h.id = f.home_club_id "
	+ "JOIN club a ON a.id = f.away_club_id "
)


static var _path := ""
static var _bound := false


static func bound() -> bool:
	var path := PLDatabase.current_path()
	if path == _path:
		return _bound
	_path = path
	_bound = not PLDatabase.row(
		"SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'league_fixture';"
	).is_empty()
	return _bound


static func competition_of(club_id: String) -> String:
	var row := PLDatabase.row("SELECT competition_id FROM club WHERE id = ?;", [club_id])
	return str(row.get("competition_id", ""))


static func competition_ids() -> Array:
	var out: Array = []
	for row in PLDatabase.rows("SELECT DISTINCT competition_id FROM league_fixture;"):
		out.append(str(row["competition_id"]))
	return out


static func club_record(club_id: String) -> Dictionary:
	var comp := competition_of(club_id)
	var rows := table(comp)
	for row in rows:
		if str(row.get("club_id", "")) == club_id:
			return row
	return {}


static func table(competition_id: String = "") -> Array:
	var sql := TABLE_SELECT
	var bindings: Array = []
	if competition_id == "":
		sql += "ORDER BY t.competition_id, t.points DESC, (t.gf - t.ga) DESC, t.gf DESC, c.name ASC;"
	else:
		sql += ("WHERE t.competition_id = ? "
			+ "ORDER BY t.points DESC, (t.gf - t.ga) DESC, t.gf DESC, c.name ASC;")
		bindings.append(competition_id)
	var rows := PLDatabase.rows(sql, bindings)
	var place := 0
	var last := ""
	for i in range(rows.size()):
		var comp := str(rows[i].get("competition_id", ""))
		place = 1 if comp != last else place + 1
		last = comp
		rows[i]["position"] = place
	return rows


static func fixtures(club_id: String = "", limit: int = 8, competition_id: String = "") -> Array:
	var sql := FIXTURE_SELECT + "WHERE f.status = 'played'"
	var bindings: Array = []
	if club_id != "":
		sql += " AND (f.home_club_id = ? OR f.away_club_id = ?)"
		bindings.append_array([club_id, club_id])
	if competition_id != "":
		sql += " AND f.competition_id = ?"
		bindings.append(competition_id)
	sql += " ORDER BY f.kickoff DESC, f.kickoff_time DESC, f.id DESC LIMIT ?;"
	bindings.append(limit)
	return PLDatabase.rows(sql, bindings)


static func upcoming(club_id: String = "", limit: int = 6, competition_id: String = "") -> Array:
	var sql := UPCOMING_SELECT + "WHERE f.status <> 'played'"
	var bindings: Array = []
	if club_id != "":
		sql += " AND (f.home_club_id = ? OR f.away_club_id = ?)"
		bindings.append_array([club_id, club_id])
	if competition_id != "":
		sql += " AND f.competition_id = ?"
		bindings.append(competition_id)
	sql += " ORDER BY f.kickoff ASC, f.kickoff_time ASC, f.id ASC LIMIT ?;"
	bindings.append(limit)
	return PLDatabase.rows(sql, bindings)


static func player_line(player_id: String) -> Dictionary:
	var row := PLDatabase.row(
		"SELECT COALESCE(SUM(apps), 0) AS apps, COALESCE(SUM(goals), 0) AS goals, "
		+ "COALESCE(SUM(assists), 0) AS assists, COALESCE(SUM(yellow), 0) AS yellow, "
		+ "COALESCE(SUM(red), 0) AS red, COUNT(*) AS lines FROM league_player_stat "
		+ "WHERE player_id = ?;", [player_id])
	if row.is_empty() or int(row.get("lines", 0)) <= 0:
		return {}
	return {
		"apps": int(row.get("apps", 0)), "goals": int(row.get("goals", 0)),
		"assists": int(row.get("assists", 0)), "yellow": int(row.get("yellow", 0)),
		"red": int(row.get("red", 0)), "season": true,
	}


static func scorers(club_id: String, limit: int = 5) -> Array:
	return PLDatabase.rows(
		"SELECT SUM(s.goals) AS goals, SUM(s.assists) AS assists, SUM(s.apps) AS apps, "
		+ "p.name, p.id AS player_id "
		+ "FROM league_player_stat s JOIN player p ON p.id = s.player_id "
		+ "WHERE s.club_id = ? AND s.goals > 0 GROUP BY p.id "
		+ "ORDER BY goals DESC, assists DESC, p.name LIMIT ?;", [club_id, limit])


static func leaders(limit: int = 5, competition_id: String = "", stat: String = "goals",
		teams: Array = []) -> Array:
	var column := "assists" if stat == "assists" else "goals"
	var base := (
		"SELECT SUM(s.%s) AS %s, SUM(s.assists) AS assists, SUM(s.apps) AS apps, "
		+ "p.name, p.id AS player_id, MAX(c.abbr) AS abbr, "
		+ "MAX(c.name) AS club_name, MAX(c.id) AS club_id, "
		+ "MAX(s.competition_id) AS competition_id FROM league_player_stat s "
		+ "JOIN player p ON p.id = s.player_id "
		+ "JOIN club c ON c.id = s.club_id WHERE s.%s > 0"
	)
	var sql: String = base % [column, column, column]
	var bindings: Array = []
	if competition_id != "":
		sql += " AND s.competition_id = ?"
		bindings.append(competition_id)
	if not teams.is_empty():
		sql += " AND c.id IN (" + ",".join(_placeholders(teams.size())) + ")"
		bindings.append_array(teams)
	sql += " GROUP BY p.id ORDER BY %s DESC, assists DESC, p.name LIMIT ?;" % column
	bindings.append(limit)
	return PLDatabase.rows(sql, bindings)

static func player_events(player_id: String, club_id: String, limit: int = 10) -> Array:
	if player_id == "" or club_id == "":
		return []
	var rows := PLDatabase.rows(
		"SELECT e.fixture_id, e.minute, e.kind, e.penalty, f.kickoff, f.matchday, "
		+ "f.home_club_id, f.away_club_id, f.home_goals, f.away_goals, "
		+ "h.abbr AS home_abbr, a.abbr AS away_abbr, h.name AS home_name, a.name AS away_name "
		+ "FROM match_event e JOIN league_fixture f ON f.id = e.fixture_id "
		+ "JOIN club h ON h.id = f.home_club_id JOIN club a ON a.id = f.away_club_id "
		+ "WHERE e.player_id = ? AND f.status = 'played' "
		+ "ORDER BY f.kickoff DESC, f.kickoff_time DESC, f.id DESC, e.minute ASC, e.id ASC;",
		[player_id])
	var out: Array = []
	var seen := {}
	for row in rows:
		var fid := str(row["fixture_id"])
		if not seen.has(fid):
			if out.size() >= limit:
				break
			seen[fid] = out.size()
			var home := str(row["home_club_id"]) == club_id
			out.append({
				"fixture_id": fid, "kickoff": str(row["kickoff"]),
				"matchday": int(row.get("matchday", 0)), "home": home,
				"opponent_id": str(row["away_club_id"]) if home else str(row["home_club_id"]),
				"opponent_abbr": str(row["away_abbr"]) if home else str(row["home_abbr"]),
				"opponent_name": str(row["away_name"]) if home else str(row["home_name"]),
				"home_goals": int(row["home_goals"]), "away_goals": int(row["away_goals"]),
				"events": [],
			})
		out[seen[fid]]["events"].append({
			"minute": int(row["minute"]), "kind": str(row["kind"]),
			"penalty": int(row.get("penalty", 0)) > 0,
		})
	return out


static func _placeholders(count: int) -> PackedStringArray:
	var out := PackedStringArray()
	for i in range(count):
		out.append("?")
	return out
