class_name LeagueFixtures
extends RefCounted


const SELECT := (
	"SELECT f.*, h.name AS home_name, h.abbr AS home_abbr, h.color AS home_color, "
	+ "a.name AS away_name, a.abbr AS away_abbr, a.color AS away_color "
	+ "FROM league_fixture f JOIN club h ON h.id = f.home_club_id "
	+ "JOIN club a ON a.id = f.away_club_id "
)

var save: LeagueSave = null

func _init(owner: LeagueSave) -> void:
	save = owner


func install(fixtures: Array, competition_id: String, set_clock: bool = true) -> bool:
	if save == null or fixtures.is_empty() or competition_id == "":
		return false
	if not save.ensure_open():
		return false
	PLDatabase.transaction("BEGIN TRANSACTION;")
	PLDatabase.execute("DELETE FROM league_fixture WHERE competition_id = ?;", [competition_id])
	PLDatabase.execute("DELETE FROM league_table WHERE competition_id = ?;", [competition_id])
	var values: Array = []
	var bindings: Array = []
	for fx in fixtures:
		values.append("(?, ?, ?, ?, ?, ?, ?, 'pending', 0, 0, '', 0)")
		bindings.append_array([
			str(fx["id"]), competition_id, int(fx["matchday"]), str(fx["kickoff"]),
			str(fx.get("kickoff_time", "")), str(fx["home"]), str(fx["away"]),
		])
	PLDatabase.execute(
		"INSERT INTO league_fixture (id, competition_id, matchday, kickoff, kickoff_time, "
		+ "home_club_id, away_club_id, status, watched, suggested, stage, leg) VALUES "
		+ ", ".join(values) + ";",
		bindings,
	)
	if not LeagueCup.is_cup(competition_id):
		PLDatabase.execute(
			"INSERT INTO league_table (club_id, competition_id) SELECT id, competition_id "
			+ "FROM club WHERE competition_id = ?;", [competition_id])
	if set_clock:
		save.set_date(str(fixtures[0]["kickoff"]))
		save.set_matchday(int(fixtures[0]["matchday"]))
		save.set_status("in_progress")
	PLDatabase.transaction("COMMIT;")
	return true


func clear() -> void:
	if save == null or not save.ensure_open():
		return
	PLDatabase.transaction("BEGIN TRANSACTION;")
	for table in ["league_fixture", "league_table", "match_event", "league_player_stat",
			"league_absence", "league_discipline", "goal_highlight"]:
		PLDatabase.execute("DELETE FROM %s;" % table)
	PLDatabase.transaction("COMMIT;")


func all(matchday: int = -1, competition_id: String = "") -> Array:
	save.ensure_open()
	var sql := SELECT
	var bindings: Array = []
	var where: Array = []
	if competition_id != "":
		where.append("f.competition_id = ?")
		bindings.append(competition_id)
	if matchday >= 1:
		where.append("f.matchday = ?")
		bindings.append(matchday)
	if not where.is_empty():
		sql += "WHERE " + " AND ".join(where) + " "
	return PLDatabase.rows(
		sql + "ORDER BY f.competition_id, f.kickoff, f.kickoff_time, f.id;", bindings)

func one(fixture_id: String) -> Dictionary:
	save.ensure_open()
	var rows := PLDatabase.rows(SELECT + "WHERE f.id = ?;", [fixture_id])
	return rows[0] if not rows.is_empty() else {}


func on(date: String, competition_id: String = "") -> Array:
	save.ensure_open()
	var sql := SELECT + "WHERE f.kickoff = ?"
	var bindings: Array = [date]
	if competition_id != "":
		sql += " AND f.competition_id = ?"
		bindings.append(competition_id)
	sql += " ORDER BY f.competition_id, f.kickoff_time, f.id;"
	var rows := PLDatabase.rows(sql, bindings)
	return _in_save_order(rows)


func _in_save_order(rows: Array) -> Array:
	if save == null or save.actives.is_empty():
		return rows
	var order := {}
	for i in range(save.actives.size()):
		order[str(save.actives[i])] = i
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ca := int(order.get(str(a.get("competition_id", "")), 99))
		var cb := int(order.get(str(b.get("competition_id", "")), 99))
		if ca != cb:
			return ca < cb
		var da := str(a.get("kickoff", ""))
		var db := str(b.get("kickoff", ""))
		if da != db:
			return da < db
		var ta := str(a.get("kickoff_time", ""))
		var tb := str(b.get("kickoff_time", ""))
		if ta != tb:
			return ta < tb
		return str(a.get("id", "")) < str(b.get("id", ""))
	)
	return rows


func recent(club_id: String, limit: int = 5) -> Array:
	save.ensure_open()
	if club_id == "":
		return []
	return PLDatabase.rows(
		SELECT + "WHERE f.status = 'played' AND (f.home_club_id = ? OR f.away_club_id = ?) "
		+ "ORDER BY f.kickoff DESC, f.kickoff_time DESC LIMIT ?;", [club_id, club_id, limit])


func pending_upto(date: String, competition_id: String = "") -> Array:
	save.ensure_open()
	var sql := SELECT + "WHERE f.status <> 'played' AND f.kickoff <= ?"
	var bindings: Array = [date]
	if competition_id != "":
		sql += " AND f.competition_id = ?"
		bindings.append(competition_id)
	sql += " ORDER BY f.competition_id, f.kickoff, f.kickoff_time, f.id;"
	return _in_save_order(PLDatabase.rows(sql, bindings))

func dates(competition_id: String = "") -> Array:
	save.ensure_open()
	var out: Array = []
	var sql := "SELECT DISTINCT kickoff FROM league_fixture"
	if competition_id != "":
		sql += " WHERE competition_id = ?"
		sql += " ORDER BY kickoff;"
		for row in PLDatabase.rows(sql, [competition_id]):
			out.append(str(row["kickoff"]))
		return out
	for row in PLDatabase.rows(sql + " ORDER BY kickoff;"):
		out.append(str(row["kickoff"]))
	return out

func unplayed(competition_id: String = "") -> int:
	save.ensure_open()
	var row := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM league_fixture WHERE status <> 'played'"
		+ _comp_suffix(competition_id) + ";", _comp_bindings(competition_id))
	return int(row.get("n", 0))

func played(competition_id: String = "") -> int:
	save.ensure_open()
	var row := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM league_fixture WHERE status = 'played'"
		+ _comp_suffix(competition_id) + ";", _comp_bindings(competition_id))
	return int(row.get("n", 0))

static func _comp_suffix(competition_id: String) -> String:
	return "" if competition_id == "" else " AND competition_id = ?"

static func _comp_bindings(competition_id: String) -> Array:
	return [] if competition_id == "" else [competition_id]


func next_date(after: String, competition_id: String = "") -> String:
	save.ensure_open()
	var row := PLDatabase.row(
		"SELECT MIN(kickoff) AS d FROM league_fixture WHERE status <> 'played' AND kickoff > ?"
		+ _comp_suffix(competition_id) + ";",
		[after] + _comp_bindings(competition_id),
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


func competition_ids() -> Array:
	save.ensure_open()
	var out: Array = []
	for row in PLDatabase.rows("SELECT DISTINCT competition_id FROM league_fixture;"):
		out.append(str(row["competition_id"]))
	out.sort_custom(func(a, b):
		return save.actives.find(a) < save.actives.find(b)
	)
	return out


func completed_matchdays(competition_id: String = "") -> int:
	save.ensure_open()
	var row := PLDatabase.row(
		"SELECT MIN(matchday) AS r FROM league_fixture WHERE status <> 'played'"
		+ _comp_suffix(competition_id) + ";", _comp_bindings(competition_id))
	if row.get("r", null) == null:
		var total := PLDatabase.row(
			"SELECT MAX(matchday) AS r FROM league_fixture"
			+ (" WHERE competition_id = ?" if competition_id != "" else "") + ";",
			_comp_bindings(competition_id))
		return int(total.get("r", 0))
	return maxi(int(row["r"]) - 1, 0)
