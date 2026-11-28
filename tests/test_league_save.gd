extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_test_issue58")
var CACHE_DIR := TestScratch.dir("cache_test_issue58")

func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	_clean()
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func after_all() -> void:
	LeagueSave.close()
	_clean()
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func test_a_save_is_a_self_contained_copy_of_the_seed() -> void:
	var save := LeagueSave.create("Test Season", LeagueRules.defaults())
	assert_not_null(save, "the save was not created: %s" % LeagueSave.last_error)
	assert_true(FileAccess.file_exists(save.path), "the save file is missing")
	assert_true(save.path.begins_with(SAVE_DIR), "the save escaped its directory")
	assert_eq(PLDatabase.current_path(), save.path, "the connection is not on the save")
	var clubs := PLDatabase.row("SELECT COUNT(*) AS n FROM club;")
	assert_eq(int(clubs["n"]), 314, "the save did not copy every competition's clubs")
	var players := PLDatabase.row("SELECT COUNT(*) AS n FROM player;")
	assert_gte(int(players["n"]), 1000, "the save did not copy the squads")
	for table in ["save_meta", "league_rules", "league_fixture", "league_table", "match_event", "league_player_stat"]:
		var found := PLDatabase.row(
			"SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?;", [table])
		assert_false(found.is_empty(), "the save has no %s table" % table)

func test_name_rules_and_status_round_trip() -> void:
	var rules := LeagueRules.defaults("generated", "every_day")
	rules["ucl_places"] = 3
	var save := LeagueSave.create("Round Trip", rules)
	assert_eq(save.name(), "Round Trip", "the save lost its name")
	assert_eq(str(save.meta["advance_mode"]), "every_day", "the advance mode was not stamped")
	save.set_date("2027-01-02")
	save.set_matchday(23)
	save.set_status("in_progress")
	save.reload()
	assert_eq(save.current_date(), "2027-01-02", "the clock did not persist")
	assert_eq(save.matchday(), 23, "the gameweek did not persist")
	assert_eq(int(save.rules["ucl_places"]), 3, "the save did not keep its own places")
	var stored := LeagueRules.read()
	assert_eq(int(stored["ucl_places"]), 3, "the rules row was not read back")
	assert_eq(str(stored["calendar_mode"]), "generated", "the calendar mode was lost")

func test_a_finished_save_can_be_listed_and_reopened() -> void:
	var save := LeagueSave.create("Listed Season", LeagueRules.defaults())
	save.set_status("complete")
	var entries := LeagueSaveCatalog.list()
	var found := {}
	for entry in entries:
		if str(entry["slug"]) == save.slug:
			found = entry
	assert_false(found.is_empty(), "the save is missing from the list")
	assert_eq(str(found["name"]), "Listed Season", "the list lost the save name")
	assert_eq(str(found["status"]), "complete", "the list lost the status")
	var reopened := LeagueSave.open(save.slug)
	assert_not_null(reopened, "the save did not reopen")
	assert_eq(reopened.path, save.path, "reopening landed on another file")
	assert_eq(PLDatabase.current_path(), save.path, "reopening did not bind the connection")
	assert_eq(reopened.status(), "complete", "the reopened save lost its status")

func test_two_saves_are_separate_files() -> void:
	var a := LeagueSave.create("Alpha", LeagueRules.defaults())
	var b := LeagueSave.create("Alpha", LeagueRules.defaults())
	assert_ne(a.slug, b.slug, "two saves with one name collided")
	assert_ne(a.path, b.path, "two saves share a file")
	a.set_date("2026-12-01")
	b.set_date("2027-02-01")
	assert_eq(LeagueSave.open(a.slug).current_date(), "2026-12-01", "save A lost its clock")
	assert_eq(LeagueSave.open(b.slug).current_date(), "2027-02-01", "save B lost its clock")

func test_deleting_a_save_unbinds_and_removes_it() -> void:
	var save := LeagueSave.create("Doomed", LeagueRules.defaults())
	var file := save.path
	assert_true(LeagueSaveCatalog.remove(save.slug), "the save was not deleted")
	assert_false(FileAccess.file_exists(file), "the save file survived deletion")
	assert_eq(PLDatabase.current_path(), "", "the connection still points at the deleted save")

func test_a_missing_save_does_not_open() -> void:
	LeagueSave.close()
	assert_null(LeagueSave.open("no-such-save"), "a missing save opened")
	assert_eq(PLDatabase.current_path(), "", "a missing save bound the connection")

func test_closing_returns_to_the_single_match_cache() -> void:
	var save := LeagueSave.create("Cache Check", LeagueRules.defaults())
	assert_eq(PLDatabase.current_path(), save.path, "the save was not the live connection")
	LeagueSave.close()
	var cache := PLDatabase.ensure_cache()
	assert_eq(PLDatabase.current_path(), "", "closing kept the save bound")
	var db := PLDatabase.get_db()
	assert_not_null(db, "the cached seed did not reopen")
	assert_eq(PLDatabase.current_path(), cache, "single-match mode is not on the cached seed")
	assert_eq(PLRepository.shared().table("PL").size(), 20, "the seed table did not come back")


func test_quick_save_stamps_the_live_save() -> void:
	var save := LeagueSave.create("Quick Save", LeagueRules.defaults())
	assert_not_null(save, "the save was not created: %s" % LeagueSave.last_error)
	save.set_date("2027-03-04")
	assert_true(save.touch(), "Quick Save did not write")
	var stored := save.read_meta()
	assert_true(str(stored.get("saved_at", "")) != "", "Quick Save did not stamp the save")
	assert_eq(PLDatabase.current_path(), save.path, "Quick Save left the save's own file")
	assert_eq(save.current_date(), "2027-03-04", "Quick Save lost the clock")


func test_save_as_writes_a_named_copy_and_keeps_the_original_live() -> void:
	var save := LeagueSave.create("Origin", LeagueRules.defaults())
	assert_not_null(save, "the save was not created: %s" % LeagueSave.last_error)
	save.set_date("2027-04-05")
	var slug := save.write_copy("Origin Snapshot")
	assert_eq(slug, "origin-snapshot", "Save As did not slug the typed name")
	assert_eq(PLDatabase.current_path(), save.path, "Save As left play on the copy")
	assert_eq(save.current_date(), "2027-04-05", "Save As moved the live season")
	var copy := LeagueSave.open(slug)
	assert_not_null(copy, "the copy did not reopen")
	assert_eq(copy.name(), "Origin Snapshot", "the copy lost its typed name")
	assert_eq(copy.current_date(), "2027-04-05", "the copy did not carry the clock")
	var listed := LeagueSaveCatalog.list()
	var slugs: Array = []
	for entry in listed:
		slugs.append(str(entry["slug"]))
	assert_true(slugs.has(slug), "the copy is not in the load list")
	assert_true(slugs.has(save.slug), "the original left the load list")


	copy.close()
	assert_true(save.ensure_open(), "the original could not be rebound")
	save.set_date("2027-05-06")
	assert_eq(LeagueSave.open(slug).current_date(), "2027-04-05",
		"writing the original changed the snapshot")


func test_save_as_with_the_seasons_own_name_rewrites_in_place() -> void:
	var save := LeagueSave.create("Same Name", LeagueRules.defaults())
	assert_not_null(save, "the save was not created: %s" % LeagueSave.last_error)
	var before := LeagueSaveCatalog.list().size()
	assert_eq(save.write_copy("Same Name"), save.slug, "naming the save did not rewrite it")
	assert_eq(LeagueSaveCatalog.list().size(), before, "naming the save wrote a second file")
	assert_true(str(save.read_meta().get("saved_at", "")) != "", "the rewrite was not stamped")


func test_save_as_refuses_an_empty_name() -> void:
	var save := LeagueSave.create("Refused Copy", LeagueRules.defaults())
	assert_not_null(save, "the save was not created: %s" % LeagueSave.last_error)
	var before := LeagueSaveCatalog.list().size()
	assert_eq(save.write_copy("   "), "", "an empty name was written")
	assert_eq(LeagueSaveCatalog.list().size(), before, "an empty name made a file")


func _columns(table: String = "league_table") -> Dictionary:
	var out := {}
	for row in PLDatabase.rows("PRAGMA table_info(%s);" % table):
		out[str(row["name"])] = true
	return out

func test_the_league_table_keeps_home_and_away_aggregates() -> void:
	var save := LeagueSave.create("Side Split", LeagueRules.defaults())
	assert_not_null(save, "the save was not created: %s" % LeagueSave.last_error)
	var columns := _columns()
	assert_true(columns.has("home_played"), "the table has no home record")
	for column in LeagueSaveSchema.SIDE_COLUMNS:
		assert_true(columns.has(column), "the table is missing %s" % column)


func test_an_older_save_gains_the_side_columns_when_it_opens() -> void:
	var save := LeagueSave.create("Old Table", LeagueRules.defaults())
	PLDatabase.execute("DROP TABLE league_table;")
	PLDatabase.execute(
		"CREATE TABLE league_table (club_id TEXT PRIMARY KEY, "
		+ "played INTEGER NOT NULL DEFAULT 0, won INTEGER NOT NULL DEFAULT 0, "
		+ "drawn INTEGER NOT NULL DEFAULT 0, lost INTEGER NOT NULL DEFAULT 0, "
		+ "gf INTEGER NOT NULL DEFAULT 0, ga INTEGER NOT NULL DEFAULT 0, "
		+ "points INTEGER NOT NULL DEFAULT 0);")
	PLDatabase.execute("INSERT INTO league_table (club_id) SELECT id FROM club;")
	assert_false(_columns().has("home_played"), "the fixture did not start as an older save")
	var reopened := LeagueSave.open(save.slug)
	assert_not_null(reopened, "the older save did not open")
	var upgraded := _columns()
	for column in LeagueSaveSchema.SIDE_COLUMNS:
		assert_true(upgraded.has(column), "opening an older save did not add %s" % column)
	var row := PLDatabase.row("SELECT home_played, away_ga FROM league_table LIMIT 1;")
	assert_eq(int(row["home_played"]), 0, "a migrated row should start on zero")
	assert_eq(int(row["away_ga"]), 0, "a migrated row should start on zero")


func test_a_report_keeps_its_penalty_tag_across_a_reopen() -> void:
	var save := LeagueSave.create("Penalty Tags", LeagueRules.defaults())
	assert_not_null(save, "the save was not created: %s" % LeagueSave.last_error)
	var record := LeagueRecord.new(save)
	record.report.add_events([
		{"fixture_id": "tag-fx", "minute": 12, "kind": "goal", "player_id": "p1",
			"club_id": "ENG-MCI1", "detail": "A. Striker", "penalty": true},
		{"fixture_id": "tag-fx", "minute": 40, "kind": "goal", "player_id": "p2",
			"club_id": "ENG-MCI1", "detail": "B. Winger"},
	])
	LeagueSave.close()
	var reopened := LeagueSave.open(save.slug)
	assert_not_null(reopened, "the save did not reopen")
	var rows := LeagueRecord.new(reopened).report.events("tag-fx")
	assert_eq(rows.size(), 2, "the report lost rows")
	assert_eq(int(rows[0].get("penalty", 0)), 1, "the penalty tag did not survive the save")
	assert_eq(int(rows[1].get("penalty", 0)), 0, "an open-play goal was saved as a penalty")


func test_an_older_save_gains_the_penalty_columns_when_it_opens() -> void:
	var save := LeagueSave.create("Old Events", LeagueRules.defaults())
	PLDatabase.execute("DROP TABLE match_event;")
	PLDatabase.execute(
		"CREATE TABLE match_event (id INTEGER PRIMARY KEY AUTOINCREMENT, "
		+ "fixture_id TEXT NOT NULL, minute INTEGER NOT NULL, kind TEXT NOT NULL, "
		+ "player_id TEXT NOT NULL DEFAULT '', club_id TEXT NOT NULL DEFAULT '', "
		+ "detail TEXT NOT NULL DEFAULT '');")
	PLDatabase.execute("DROP TABLE goal_highlight;")
	PLDatabase.execute(
		"CREATE TABLE goal_highlight (id INTEGER PRIMARY KEY AUTOINCREMENT, "
		+ "fixture_id TEXT NOT NULL, goal_index INTEGER NOT NULL, "
		+ "match_event_id INTEGER NOT NULL DEFAULT 0, minute INTEGER NOT NULL DEFAULT 0, "
		+ "club_id TEXT NOT NULL DEFAULT '', scorer_id TEXT NOT NULL DEFAULT '', "
		+ "scorer_name TEXT NOT NULL DEFAULT '', assist_id TEXT NOT NULL DEFAULT '', "
		+ "assist_name TEXT NOT NULL DEFAULT '', commentary TEXT NOT NULL DEFAULT '', "
		+ "source TEXT NOT NULL DEFAULT 'auto', codec TEXT NOT NULL DEFAULT '', "
		+ "version INTEGER NOT NULL DEFAULT 0, home_club_id TEXT NOT NULL DEFAULT '', "
		+ "away_club_id TEXT NOT NULL DEFAULT '', bytes BLOB, UNIQUE(fixture_id, goal_index));")
	assert_false(_columns("match_event").has("penalty"), "the fixture did not start as an older save")
	var reopened := LeagueSave.open(save.slug)
	assert_not_null(reopened, "the older save did not open")
	assert_true(_columns("match_event").has("penalty"), "opening an older save did not add the tag")
	assert_true(_columns("goal_highlight").has("penalty"), "opening an older save did not add the clip tag")


func test_table_choices_belong_to_their_own_save() -> void:
	var first := LeagueSave.create("Reading One", LeagueRules.defaults())
	assert_true(first.put_meta("table_mode", "full"), "the save took no mode")
	assert_true(first.put_meta("table_sort", "points"), "the save took no sort")
	assert_true(first.put_meta("table_dir", "asc"), "the save took no direction")
	var second := LeagueSave.create("Reading Two", LeagueRules.defaults())
	var view := LeagueTableView.new()
	view.attach(LeagueSave.open(first.slug))
	assert_eq(view.mode, "full", "the first save lost its reading")
	assert_eq(view.order.key, "points", "the first save lost its sort")
	assert_eq(view.order.dir, 1, "the first save lost its direction")
	view.attach(LeagueSave.open(second.slug))
	assert_eq(view.mode, "", "a fresh save borrowed another save's reading")
	assert_eq(view.order.key, "", "a fresh save borrowed another save's sort")
	assert_eq(view.order.dir, -1, "a fresh save borrowed another save's direction")

func test_slugs_are_readable_and_files_stay_in_the_folder() -> void:
	assert_eq(LeagueSaveCatalog.slugify(""), "", "an empty name should fold to nothing")
	assert_eq(LeagueSaveCatalog.unique_slug("!!!"), "league", "an empty name has no fallback slug")
	assert_eq(LeagueSaveCatalog.slugify("  My  Save!! "), "my-save", "punctuation was not folded")
	assert_eq(LeagueSaveCatalog.slugify("2026/27"), "2026-27", "digits and slashes were mishandled")
	var notes := LeagueSave.dir.path_join("notes.txt")
	var out := FileAccess.open(notes, FileAccess.WRITE)
	out.store_string("not a save")
	out.close()
	for entry in LeagueSaveCatalog.list():
		assert_ne(str(entry["slug"]), "notes", "a stray file was listed as a save")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(notes))
	assert_false(LeagueSaveCatalog.remove("no-such-save"), "removing a missing save reported success")

func _clean() -> void:
	for folder in [SAVE_DIR, CACHE_DIR]:
		TestScratch.clear(folder)
