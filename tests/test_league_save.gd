extends GdToolsTest

## Named league saves: one self-contained SQLite file per season, copied from
## the shipped seed, carrying its own regulations and reading through the game's
## data layer — while single-match mode keeps its cached seed.

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
	assert_eq(int(clubs["n"]), 20, "the save did not copy the clubs")
	var players := PLDatabase.row("SELECT COUNT(*) AS n FROM player;")
	assert_gte(int(players["n"]), 360, "the save did not copy the squads")
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
	var entries := LeagueSave.list()
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
	assert_true(LeagueSave.remove(save.slug), "the save was not deleted")
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
	assert_eq(PLRepository.shared().table().size(), 20, "the seed table did not come back")

# --------------------------------------------------- home/away table (#73) ---

func _columns() -> Dictionary:
	var out := {}
	for row in PLDatabase.rows("PRAGMA table_info(league_table);"):
		out[str(row["name"])] = true
	return out

func test_the_league_table_keeps_home_and_away_aggregates() -> void:
	var save := LeagueSave.create("Side Split", LeagueRules.defaults())
	assert_not_null(save, "the save was not created: %s" % LeagueSave.last_error)
	var columns := _columns()
	assert_true(columns.has("home_played"), "the table has no home record")
	for column in LeagueSave.SIDE_COLUMNS:
		assert_true(columns.has(column), "the table is missing %s" % column)

## A save written before the home/away columns existed gets them on open; the
## season then rebuilds them from the played fixtures, so nothing is lost.
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
	for column in LeagueSave.SIDE_COLUMNS:
		assert_true(upgraded.has(column), "opening an older save did not add %s" % column)
	var row := PLDatabase.row("SELECT home_played, away_ga FROM league_table LIMIT 1;")
	assert_eq(int(row["home_played"]), 0, "a migrated row should start on zero")
	assert_eq(int(row["away_ga"]), 0, "a migrated row should start on zero")

## The table reading belongs to one save: two seasons remember different modes
## and sorts, and a save that was never changed has none.
func test_table_choices_belong_to_their_own_save() -> void:
	var first := LeagueSave.create("Reading One", LeagueRules.defaults())
	assert_true(first.put_meta("table_mode", "full"), "the save took no mode")
	assert_true(first.put_meta("table_sort", "points"), "the save took no sort")
	assert_true(first.put_meta("table_dir", "asc"), "the save took no direction")
	var second := LeagueSave.create("Reading Two", LeagueRules.defaults())
	var view := LeagueTableView.new()
	view.attach(LeagueSave.open(first.slug))
	assert_eq(view.mode, "full", "the first save lost its reading")
	assert_eq(view.sort, "points", "the first save lost its sort")
	assert_eq(view.dir, 1, "the first save lost its direction")
	view.attach(LeagueSave.open(second.slug))
	assert_eq(view.mode, "", "a fresh save borrowed another save's reading")
	assert_eq(view.sort, "", "a fresh save borrowed another save's sort")
	assert_eq(view.dir, -1, "a fresh save borrowed another save's direction")

func test_slugs_are_readable_and_files_stay_in_the_folder() -> void:
	assert_eq(LeagueSave.slugify(""), "", "an empty name should fold to nothing")
	assert_eq(LeagueSave.unique_slug("!!!"), "league", "an empty name has no fallback slug")
	assert_eq(LeagueSave.slugify("  My  Save!! "), "my-save", "punctuation was not folded")
	assert_eq(LeagueSave.slugify("2026/27"), "2026-27", "digits and slashes were mishandled")
	var notes := LeagueSave.dir.path_join("notes.txt")
	var out := FileAccess.open(notes, FileAccess.WRITE)
	out.store_string("not a save")
	out.close()
	for entry in LeagueSave.list():
		assert_ne(str(entry["slug"]), "notes", "a stray file was listed as a save")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(notes))
	assert_false(LeagueSave.remove("no-such-save"), "removing a missing save reported success")

func _clean() -> void:
	for folder in [SAVE_DIR, CACHE_DIR]:
		TestScratch.clear(folder)
