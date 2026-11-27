extends GdToolsTest


func before_all() -> void:
	PLDatabase.cache_dir = TestScratch.dir("cache_test_rules_migration")
	PLDatabase.reset()

func after_all() -> void:
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()

func test_a_single_row_rules_table_is_lifted_per_competition() -> void:

	PLDatabase.execute("DROP TABLE IF EXISTS league_rules;")
	PLDatabase.execute(
		"CREATE TABLE league_rules (id INTEGER PRIMARY KEY, win_points INTEGER NOT NULL, "
		+ "draw_points INTEGER NOT NULL, relegation_places INTEGER NOT NULL, "
		+ "ucl_places INTEGER NOT NULL, uel_places INTEGER NOT NULL, "
		+ "uecl_places INTEGER NOT NULL, matchdays INTEGER NOT NULL, "
		+ "season_start TEXT NOT NULL, season_end TEXT NOT NULL, weekend_bias REAL NOT NULL, "
		+ "midweek_matchdays INTEGER NOT NULL, advance_mode TEXT NOT NULL, "
		+ "calendar_mode TEXT NOT NULL);")
	PLDatabase.execute(
		"INSERT INTO league_rules (id, win_points, draw_points, relegation_places, "
		+ "ucl_places, uel_places, uecl_places, matchdays, season_start, season_end, "
		+ "weekend_bias, midweek_matchdays, advance_mode, calendar_mode) "
		+ "VALUES (1, 3, 1, 3, 4, 1, 1, 38, '2026-08-15', '2027-05-23', 0.9, 4, "
		+ "'every_day', 'real');")
	LeagueRules.migrate("LL")
	var columns := {}
	for row in PLDatabase.rows("PRAGMA table_info(league_rules);"):
		columns[str(row["name"])] = true
	assert_true(columns.has("competition_id"), "the migrated table has no competition column")
	assert_false(columns.has("id"), "the legacy id column survived the migration")
	var lifted := LeagueRules.read("LL")
	assert_eq(int(lifted["midweek_matchdays"]), 4, "the save's own rule row was not copied")
	assert_eq(str(lifted["advance_mode"]), "every_day", "the saved clock policy was not copied")
	assert_eq(str(lifted["calendar_mode"]), "real", "the saved calendar mode was not copied")
	assert_eq(PLDatabase.rows("SELECT * FROM league_rules;").size(), 1,
		"the migration invented a second competition")
