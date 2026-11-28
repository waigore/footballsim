class_name SeasonAgeing
extends RefCounted


const RETIRE_FROM := 35
const RETIRE_CERTAIN := 40
const RETIRE_BASE := 0.4
const RETIRE_STEP := 0.15


static func apply(season: LeagueSeason, season_index: int, date: String) -> Dictionary:
	if season == null or season.save == null or not season.save.ensure_open():
		return {"aged": 0, "retired": 0}
	var aged := age_everyone(date)
	var retired := retire(season, season_index, date)
	return {"aged": aged, "retired": retired}


static func age_everyone(date: String) -> int:
	if date == "":
		date = FixtureCalendar.date_from(FixtureCalendar.days_from("2026-07-01"))
	var dated := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM player WHERE date_of_birth IS NOT NULL AND date_of_birth <> '';")
	PLDatabase.execute(
		"UPDATE player SET age = CAST((julianday(?) - julianday(date_of_birth)) / 365.25 AS INTEGER) "
		+ "WHERE date_of_birth IS NOT NULL AND date_of_birth <> '' AND age IS NOT NULL;",
		[date])
	PLDatabase.execute(
		"UPDATE player SET age = age + 1 WHERE age IS NOT NULL "
		+ "AND (date_of_birth IS NULL OR date_of_birth = '');")
	return int(dated.get("n", 0))


static func chance(age: int) -> float:
	if age >= RETIRE_CERTAIN:
		return 1.0
	if age < RETIRE_FROM:
		return 0.0
	return minf(RETIRE_BASE + RETIRE_STEP * float(age - RETIRE_FROM), 1.0)


static func retire(season: LeagueSeason, season_index: int, date: String) -> int:
	var seed := int(str(season.save.meta.get("seed", "0")))
	var count := 0
	for row in PLDatabase.rows(
			"SELECT id, club_id, age FROM player WHERE age >= ? ORDER BY id;", [RETIRE_FROM]):
		var age := int(row.get("age", 0))
		if chance(age) < 1.0 and roll(seed, str(row["id"]), season_index) >= chance(age):
			continue
		count += release(str(row["id"]), str(row["club_id"]), season_index, date)
	return count


static func roll(seed: int, player_id: String, season_index: int) -> float:
	var h := absi(seed) + season_index * 7919
	for i in range(player_id.length()):
		h = int((h * 31 + player_id.unicode_at(i)) % 2147483647)
	var rng := RandomNumberGenerator.new()
	rng.seed = h
	return rng.randf()


static func release(player_id: String, club_id: String, season_index: int, date: String) -> int:
	var competition_id := ""
	var club := PLDatabase.row("SELECT competition_id FROM club WHERE id = ?;", [club_id])
	if not club.is_empty():
		competition_id = str(club.get("competition_id", ""))
	PLDatabase.execute(
		"INSERT OR REPLACE INTO player_history (player_id, season_index, club_id, "
		+ "competition_id, kind, from_date, to_date) VALUES (?, ?, ?, ?, 'retired', '', ?);",
		[player_id, season_index, club_id, competition_id, date])
	for table in ["league_absence", "league_discipline"]:
		PLDatabase.execute("DELETE FROM %s WHERE player_id = ?;" % table, [player_id])
	PLDatabase.execute("DELETE FROM player_contract WHERE player_id = ?;", [player_id])
	PLDatabase.execute("DELETE FROM player_registration WHERE player_id = ?;", [player_id])
	PLDatabase.execute("DELETE FROM player WHERE id = ?;", [player_id])
	return 1
