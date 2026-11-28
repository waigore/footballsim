class_name MarketContracts
extends RefCounted


const TABLE := "player_contract"
const ACTIVE := "active"
const EXPIRED := "expired"
const RENEWED := "renewed"

static var _ready_path := ""
static var _ready := false
static var _medians := {}


static func bootstrap(save: LeagueSave, start_date: String = "") -> Dictionary:
	if save == null or not save.ensure_open() or not available():
		return {"ok": false, "reason": "no_save", "contracts": 0}
	var existing := active_count()
	if existing > 0:
		return {"ok": true, "skipped": true, "contracts": existing, "clubs": 0}
	var start := start_date
	if start == "":
		start = save.current_date()
	if start == "":
		start = str(save.rules.get("season_start", ""))
	if start == "":
		start = "2026-08-15"
	var seed := int(str(save.meta.get("seed", "0")))
	var clubs := PLDatabase.rows("SELECT id, competition_id, capacity FROM club ORDER BY id;")
	var count := 0
	var filled := 0
	PLDatabase.transaction("BEGIN TRANSACTION;")
	for club in clubs:
		var club_id := str(club["id"])
		var squad := PLDatabase.rows(
			"SELECT id, ovr FROM player WHERE club_id = ? ORDER BY id;", [club_id])
		if squad.is_empty():
			continue
		var wages := MarketWages.allocate(squad, MarketWages.wage_budget(club))
		count += _insert_squad(club_id, squad, wages, seed, start)
		filled += 1
	PLDatabase.transaction("COMMIT;")
	MarketFinance.invalidate()
	return {"ok": true, "skipped": false, "contracts": count, "clubs": filled, "start": start}


static func review(save: LeagueSave, season_index: int, date: String) -> Dictionary:
	var out := {"expired": 0, "exercised": 0, "renewed": 0, "forgotten": 0}
	if save == null or not save.ensure_open() or not available() or date == "":
		return out
	_medians.clear()
	out["forgotten"] = _forget_missing()
	var rows := PLDatabase.rows(
		"SELECT c.player_id, c.club_id, c.start_date, c.end_date, c.wage, c.option_years, "
		+ "c.declined, p.ovr FROM player_contract c JOIN player p ON p.id = c.player_id "
		+ "WHERE c.status = 'active' AND c.end_date <> '' AND c.end_date < ? "
		+ "AND p.club_id = c.club_id ORDER BY c.club_id, p.ovr DESC, c.player_id;", [date])
	if rows.is_empty():
		return out
	var by_club := {}
	for row in rows:
		var club_id := str(row["club_id"])
		if not by_club.has(club_id):
			by_club[club_id] = []
		(by_club[club_id] as Array).append(row)
	PLDatabase.transaction("BEGIN TRANSACTION;")
	for club_id in by_club:
		var counts := _review_club(str(club_id), by_club[club_id], season_index, date)
		for key in counts:
			out[key] = int(out.get(key, 0)) + int(counts[key])
	PLDatabase.transaction("COMMIT;")
	MarketFinance.invalidate()
	return out


static func decline_option(player_id: String) -> bool:
	if not available():
		return false
	return PLDatabase.execute(
		"UPDATE player_contract SET declined = 1 WHERE player_id = ? AND status = 'active';",
		[player_id])


static func exercise_option(player_id: String) -> bool:
	if not available():
		return false
	return PLDatabase.execute(
		"UPDATE player_contract SET option_years = MAX(option_years, 1) "
		+ "WHERE player_id = ? AND status = 'active';", [player_id])


static func rehome(player_id: String, club_id: String) -> int:
	if player_id == "" or club_id == "" or not available():
		return 0
	var moved := 0
	for table in ["league_absence", "league_discipline"]:
		moved += PLDatabase.rows("SELECT player_id FROM %s WHERE player_id = ?;" % table,
			[player_id]).size()
		PLDatabase.execute("UPDATE %s SET club_id = ? WHERE player_id = ?;" % table,
			[club_id, player_id])
	return moved


static func of_player(player_id: String) -> Dictionary:
	if player_id == "" or not available():
		return {}
	var row := PLDatabase.row(
		"SELECT * FROM player_contract WHERE player_id = ? AND status = 'active' "
		+ "ORDER BY start_date DESC LIMIT 1;", [player_id])
	if not row.is_empty():
		return row
	return PLDatabase.row(
		"SELECT * FROM player_contract WHERE player_id = ? "
		+ "ORDER BY end_date DESC, start_date DESC LIMIT 1;", [player_id])


static func active_count(club_id: String = "") -> int:
	if not available():
		return 0
	var sql := "SELECT COUNT(*) AS n FROM player_contract WHERE status = 'active';"
	var bindings: Array = []
	if club_id != "":
		sql = "SELECT COUNT(*) AS n FROM player_contract WHERE status = 'active' AND club_id = ?;"
		bindings = [club_id]
	return int(PLDatabase.row(sql, bindings).get("n", 0))


static func wage_bill(club_id: String) -> int:
	if not available():
		return 0
	return int(PLDatabase.row(
		"SELECT COALESCE(SUM(wage), 0) AS n FROM player_contract "
		+ "WHERE status = 'active' AND club_id = ?;", [club_id]).get("n", 0))


static func free_agents(limit: int = 40) -> Array:
	if not available():
		return []
	return PLDatabase.rows(
		"SELECT p.id, p.club_id, p.name, p.pos, p.ovr FROM player p "
		+ "WHERE NOT EXISTS (SELECT 1 FROM player_contract c "
		+ "WHERE c.player_id = p.id AND c.status = 'active') ORDER BY p.ovr DESC LIMIT ?;",
		[maxi(limit, 1)])


static func free_agent_count() -> int:
	if not available():
		return 0
	return int(PLDatabase.row(
		"SELECT COUNT(*) AS n FROM player p WHERE NOT EXISTS (SELECT 1 FROM player_contract c "
		+ "WHERE c.player_id = p.id AND c.status = 'active');").get("n", 0))


static func available() -> bool:
	var path := PLDatabase.current_path()
	if path == _ready_path:
		return _ready
	_ready_path = path
	_ready = not PLDatabase.row(
		"SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'player_contract';").is_empty()
	return _ready


static func _insert_squad(club_id: String, squad: Array, wages: Dictionary, seed: int,
		start: String) -> int:
	var marks: Array = []
	var values: Array = []
	var years_min := maxi(MarketRules.count("contract", "years_min", 1), 1)
	var years_span := maxi(MarketRules.count("contract", "years_max", 4) - years_min + 1, 1)
	var option_share := MarketRules.number("contract", "option_share", 0.34)
	var clause_years := MarketRules.count("contract", "clause_years", 2)
	var ends := {}
	for years in range(years_min, years_min + years_span):
		ends[years] = FixtureCalendar.add_days(FixtureCalendar.add_years(start, years), -1)
	for player in squad:
		var id := str(player["id"])
		var wage := int(wages.get(id, 0))
		var years := years_min + MarketSeed.mix(seed, id, 0) % years_span
		years = clampi(years, years_min, years_min + years_span - 1)
		var option := 1 if MarketSeed.unit(seed, id, 1) < option_share else 0
		marks.append("(?, ?, 0, ?, ?, ?, 0, 0, ?, ?, 'active', '', 0)")
		values.append_array([id, club_id, start, str(ends[years]), wage,
			wage * 52 * clause_years, option])
	if marks.is_empty():
		return 0
	PLDatabase.execute(
		"INSERT INTO player_contract (player_id, club_id, season_index, start_date, end_date, "
		+ "wage, signing_bonus, agent_fee, release_clause, option_years, status, deal_id, declined) "
		+ "VALUES " + ", ".join(PackedStringArray(marks)) + ";", values)
	return squad.size()


static func _review_club(club_id: String, expiring: Array, season_index: int,
		date: String) -> Dictionary:
	var out := {"expired": 0, "exercised": 0, "renewed": 0}
	var club := PLDatabase.row("SELECT id, competition_id FROM club WHERE id = ?;", [club_id])
	var median := _median(str(club.get("competition_id", "")))
	var xi := _xi_ids(club_id)
	for row in expiring:
		var player_id := str(row["player_id"])
		var wanted := xi.has(player_id) or int(row["ovr"]) >= median
		if int(row["declined"]) == 1:
			_expire(row, season_index)
			out["expired"] = int(out["expired"]) + 1
			continue
		if wanted and int(row["option_years"]) > 0:
			_exercise(row)
			out["exercised"] = int(out["exercised"]) + 1
			continue
		if wanted:
			_renew(row, season_index, date)
			out["renewed"] = int(out["renewed"]) + 1
			continue
		_expire(row, season_index)
		out["expired"] = int(out["expired"]) + 1
	return out


static func _exercise(row: Dictionary) -> void:
	var wage := int(row["wage"])
	var step := MarketRules.number("contract", "option_step", 0.1)
	PLDatabase.execute(
		"UPDATE player_contract SET end_date = ?, wage = ?, option_years = MAX(option_years - 1, 0) "
		+ "WHERE player_id = ? AND start_date = ?;",
		[FixtureCalendar.add_years(str(row["end_date"]), 1),
			int(round(float(wage) * (1.0 + step))), str(row["player_id"]), str(row["start_date"])])


static func _renew(row: Dictionary, season_index: int, date: String) -> void:
	var player_id := str(row["player_id"])
	var club_id := str(row["club_id"])
	var years := maxi(MarketRules.count("contract", "renewal_years", 2), 1)
	var end := FixtureCalendar.add_days(FixtureCalendar.add_years(date, years), -1)
	PLDatabase.execute(
		"UPDATE player_contract SET status = 'renewed' WHERE player_id = ? AND start_date = ?;",
		[player_id, str(row["start_date"])])
	PLDatabase.execute(
		"INSERT INTO player_contract (player_id, club_id, season_index, start_date, end_date, "
		+ "wage, signing_bonus, agent_fee, release_clause, option_years, status, deal_id, declined) "
		+ "VALUES (?, ?, ?, ?, ?, ?, 0, 0, ?, 0, 'active', '', 0);",
		[player_id, club_id, season_index, date, end, int(row["wage"]),
			int(row["wage"]) * 52 * MarketRules.count("contract", "clause_years", 2)])


static func _expire(row: Dictionary, season_index: int) -> void:
	var player_id := str(row["player_id"])
	var club_id := str(row["club_id"])
	var competition_id := ""
	var club := PLDatabase.row("SELECT competition_id FROM club WHERE id = ?;", [club_id])
	if not club.is_empty():
		competition_id = str(club.get("competition_id", ""))
	PLDatabase.execute(
		"UPDATE player_contract SET status = 'expired' WHERE player_id = ? AND start_date = ?;",
		[player_id, str(row["start_date"])])
	PLDatabase.execute("UPDATE player SET club_id = '' WHERE id = ? AND club_id = ?;",
		[player_id, club_id])
	PLDatabase.execute(
		"INSERT OR REPLACE INTO player_history (player_id, season_index, club_id, competition_id, "
		+ "kind, from_date, to_date) VALUES (?, ?, ?, ?, 'spell', ?, ?);",
		[player_id, season_index, club_id, competition_id, str(row["start_date"]),
			str(row["end_date"])])
	for table in ["league_absence", "league_discipline"]:
		PLDatabase.execute("DELETE FROM %s WHERE player_id = ?;" % table, [player_id])


static func _forget_missing() -> int:
	if not available():
		return 0
	var doomed := int(PLDatabase.row(
		"SELECT COUNT(*) AS n FROM player_contract "
		+ "WHERE player_id NOT IN (SELECT id FROM player);").get("n", 0))
	if doomed <= 0:
		return 0
	PLDatabase.execute(
		"DELETE FROM player_contract WHERE player_id NOT IN (SELECT id FROM player);")
	return doomed


static func _median(competition_id: String) -> int:
	if competition_id == "":
		return 0
	var key := "%s|%s" % [PLDatabase.current_path(), competition_id]
	if _medians.has(key):
		return int(_medians[key])
	var rows := PLDatabase.rows(
		"SELECT p.ovr FROM player p JOIN club cl ON cl.id = p.club_id "
		+ "WHERE cl.competition_id = ? ORDER BY p.ovr;", [competition_id])
	var value := 0
	if not rows.is_empty():
		value = int(rows[int(rows.size() / 2)].get("ovr", 0))
	_medians[key] = value
	return value


static func _xi_ids(club_id: String) -> Array:
	var out: Array = []
	for row in PLDatabase.rows(
			"SELECT id FROM player WHERE club_id = ? ORDER BY ovr DESC, id LIMIT 11;", [club_id]):
		out.append(str(row["id"]))
	return out
