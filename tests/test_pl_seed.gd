extends GdToolsTest

## The shipped seed and the cache that carries it: version stamping, flush on a
## version bump, and the repository shapes the engine and the encyclopedia read.

var CACHE_DIR := TestScratch.dir("cache_test_seed")

func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR

func after_all() -> void:
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func test_seed_asset_is_versioned() -> void:
	assert_true(FileAccess.file_exists(PLDatabase.SEED_PATH), "the seed database is not in the repo")
	var version := PLDatabase.seed_version()
	assert_gte(version, 1, "the seed carries no db_version")
	var meta := PLDatabase.row("SELECT value FROM metadata WHERE key = 'season_label';")
	assert_eq(str(meta.get("value", "")), "2025-26", "the snapshot season drifted")
	var source := PLDatabase.row("SELECT value FROM metadata WHERE key = 'source';")
	assert_eq(str(source.get("value", "")), "ESPN", "the snapshot does not name its source")

func test_missing_cache_is_copied_from_the_seed() -> void:
	_clean_cache()
	var path := PLDatabase.ensure_cache()
	assert_true(FileAccess.file_exists(path), "the cache was not created")
	assert_true(path.begins_with(CACHE_DIR), "the cache escaped the user directory")
	var db := PLDatabase.get_db()
	assert_not_null(db, "the cached seed did not open")
	assert_eq(PLDatabase.current_path(), path, "the live connection is not on the cache")

func test_a_seed_version_bump_flushes_the_cache() -> void:
	_clean_cache()
	var stale := CACHE_DIR.path_join("pl_seed_v0.sqlite")
	var out := FileAccess.open(stale, FileAccess.WRITE)
	out.store_string("old cache")
	out.close()
	var path := PLDatabase.ensure_cache()
	assert_false(FileAccess.file_exists(stale), "an older cache copy survived")
	assert_true(FileAccess.file_exists(path), "the current cache copy is missing")

func test_repository_serves_the_engine_shape() -> void:
	var ids := TeamData.team_ids()
	assert_eq(ids.size(), 20, "the league should ship twenty clubs")
	for id in ids:
		var team: Dictionary = TeamData.get_team(id)
		assert_eq(team["starters"].size(), 11, "%s does not ship an XI" % id)
		assert_gte(team["bench"].size(), 5, "%s does not ship a bench" % id)
		assert_true(team["color"] is Color, "%s has no kit colour" % id)
		assert_has(team["style"], "possession", "%s has no style profile" % id)
		assert_true(TeamData.FORMATIONS.has(str(team["formation"])), "%s prefers an unknown formation" % id)

func test_league_table_is_a_finished_season() -> void:
	var rows := PLRepository.shared().table()
	assert_eq(rows.size(), 20, "the table is short")
	var points: Array = []
	for i in range(rows.size()):
		assert_eq(int(rows[i]["position"]), i + 1, "the table is not ordered by position")
		assert_eq(int(rows[i]["played"]), 38, "%s did not play a full season" % rows[i]["club_id"])
		points.append(int(rows[i]["points"]))
	var sorted_points := points.duplicate()
	sorted_points.sort()
	sorted_points.reverse()
	assert_eq(points, sorted_points, "the table is not sorted by points")

func test_fixtures_cover_the_season() -> void:
	var all := PLRepository.shared().fixtures("", 500)
	assert_eq(all.size(), 380, "a twenty-club double round robin is 380 fixtures")
	var per_club := {}
	for fx in all:
		per_club[str(fx["home_club_id"])] = int(per_club.get(str(fx["home_club_id"]), 0)) + 1
		per_club[str(fx["away_club_id"])] = int(per_club.get(str(fx["away_club_id"]), 0)) + 1
	for id in per_club:
		assert_eq(int(per_club[id]), 38, "%s does not have 38 fixtures" % id)

func test_player_dossier_carries_snapshot_and_career() -> void:
	var p := PLRepository.shared().player("MUN-b-fernandes")
	assert_eq(str(p["club_id"]), "MUN", "the dossier lost its club")
	assert_eq(int(p["ovr"]), 88, "ratings are the game's own dataset and must survive")
	assert_gte(int(p["season"].get("matches", 0)), 1, "no real-world season line")
	assert_gte(int(p["career"].get("matches", 0)), 1, "no career line")
	assert_gte(int(p["age"]), 18, "no identity line from the snapshot")

func test_leaders_are_ordered() -> void:
	var leaders := PLRepository.shared().leaders(6)
	assert_eq(leaders.size(), 6, "the scorer chart is short")
	for i in range(1, leaders.size()):
		assert_gte(int(leaders[i - 1]["goals"]), int(leaders[i]["goals"]), "scorers are out of order")

func _clean_cache() -> void:
	PLDatabase.reset()
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	for name in DirAccess.get_files_at(CACHE_DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CACHE_DIR.path_join(name)))
