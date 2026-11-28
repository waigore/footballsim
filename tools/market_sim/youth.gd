extends RefCounted

## The youth verb: age, retire and run intake for N seasons, then print the
## names and counts. No deal engine, no AI and no UI is loaded.

static func run(options: Dictionary) -> Dictionary:
	var seasons := maxi(int(options.get("seasons", "3")), 1)
	var clubs := maxi(int(options.get("clubs", "20")), 2)
	var seed_value := int(options.get("seed", "7051"))
	var competitions := ["PL"]
	if clubs > 20:
		competitions.append("CH")
	var season := LeagueSeason.create("Youth Sandbox", "generated", "fixture_days", seed_value,
		competitions, false)
	if season == null:
		return {"ok": false, "reason": "the save could not be created",
			"detail": LeagueSave.last_error}
	var log: Array = []
	var start := season.save.current_date()
	for i in range(seasons):
		var index := season.save.season_index() + i
		var date := FixtureCalendar.add_years(start, i)
		var aged := SeasonAgeing.apply(season, index, date)
		var intake := YouthIntake.apply(season.save, index, date)
		var sample := _sample(season, index)
		log.append({
			"season": index, "date": date,
			"retired": int(aged.get("retired", 0)),
			"intake_players": int(intake.get("players", 0)),
			"intake_clubs": int(intake.get("clubs", 0)),
			"sample": sample,
		})
		print("season %d at %s: retired %d, intake %d over %d clubs" % [index, date,
			int(aged.get("retired", 0)), int(intake.get("players", 0)),
			int(intake.get("clubs", 0))])
	var ages := PLDatabase.row("SELECT MIN(age) AS lo, MAX(age) AS hi FROM player;")
	var over := int(PLDatabase.row("SELECT COUNT(*) AS n FROM player WHERE age >= 40;").get("n", 0))
	var names := _names(season)
	season.close()
	var ok := over == 0 and _all_in_range(log)
	return {
		"ok": ok, "seasons": seasons, "clubs": clubs, "seed": seed_value, "log": log,
		"ages": {"min": int(ages.get("lo", 0)), "max": int(ages.get("hi", 0))},
		"over_40": over, "names": names,
	}


static func _all_in_range(log: Array) -> bool:
	for entry in log:
		var made := int((entry as Dictionary).get("intake_players", 0))
		if made <= 0:
			return false
	return true


static func _sample(season: LeagueSeason, index: int) -> Array:
	var out: Array = []
	var rows := PLDatabase.rows(
		"SELECT p.id, p.name, p.age, p.ovr, p.club_id, p.homegrown_club_id, p.nationality "
		+ "FROM player p JOIN player_contract c ON c.player_id = p.id "
		+ "WHERE c.season_index = ? AND c.status = 'active' AND p.id LIKE ? "
		+ "ORDER BY p.id LIMIT 5;", [index, "Y%d-" % index])
	for row in rows:
		out.append(str(row.get("name", "")))
	return out


static func _names(season: LeagueSeason) -> Array:
	var out: Array = []
	for row in PLDatabase.rows(
			"SELECT name FROM player WHERE id LIKE 'Y%-%' ORDER BY id LIMIT 12;"):
		out.append(str(row.get("name", "")))
	return out
