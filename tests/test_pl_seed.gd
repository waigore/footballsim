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
	assert_eq(str(meta.get("value", "")), "2026-27", "the snapshot season drifted")
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
	var ids := TeamData.team_ids("PL")
	assert_eq(ids.size(), 20, "the Premier League should ship twenty clubs")
	for id in ids:
		var team: Dictionary = TeamData.get_team(id)
		assert_eq(team["starters"].size(), 11, "%s does not ship an XI" % id)
		assert_gte(team["bench"].size(), 5, "%s does not ship a bench" % id)
		assert_true(team["color"] is Color, "%s has no kit colour" % id)
		assert_has(team["style"], "possession", "%s has no style profile" % id)
		assert_true(TeamData.FORMATIONS.has(str(team["formation"])), "%s prefers an unknown formation" % id)

## The seed carries more than one competition, and a La Liga club's ids never
## collide with an English one's.
func test_the_seed_ships_two_competitions() -> void:
	var comps: Array = []
	for row in PLRepository.shared().active_competitions():
		comps.append(str(row["id"]))
	assert_true(comps.has("PL"), "the seed has no Premier League")
	assert_true(comps.has("LL"), "the seed has no La Liga")
	var ll := TeamData.team_ids("LL")
	assert_eq(ll.size(), 20, "La Liga should ship twenty clubs")
	var all_ids := TeamData.team_ids()
	assert_eq(all_ids.size(), 40, "the seed should ship forty clubs")
	for id in ll:
		assert_true(str(id).begins_with("LL-"), "%s does not carry its competition namespace" % id)
		assert_false(all_ids.has(str(id).trim_prefix("LL-")), "%s collides across competitions" % id)

## The snapshot is one date in a season, not the season's end: every club has
## played the same number of games and the table is ordered by points.
func test_league_table_is_the_snapshot_reading() -> void:
	var rows := PLRepository.shared().table("PL")
	assert_eq(rows.size(), 20, "the table is short")
	var played := -1
	var points: Array = []
	for i in range(rows.size()):
		assert_eq(int(rows[i]["position"]), i + 1, "the table is not ordered by position")
		if played < 0:
			played = int(rows[i]["played"])
		assert_eq(int(rows[i]["played"]), played, "%s played a different number of games" % rows[i]["club_id"])
		points.append(int(rows[i]["points"]))
	assert_gte(played, 0, "the snapshot table carries no played games")
	var sorted_points := points.duplicate()
	sorted_points.sort()
	sorted_points.reverse()
	assert_eq(points, sorted_points, "the table is not sorted by points")

## The shipped calendar is the whole 2026-27 season; results lag the fixture
## list because the snapshot is taken mid-season.
func test_fixtures_cover_the_season() -> void:
	var all := PLDatabase.rows("SELECT * FROM fixture WHERE competition_id = 'PL';")
	assert_eq(all.size(), 380, "a twenty-club double round robin is 380 fixtures")
	var per_club := {}
	var played_per_club := {}
	var first := ""
	var last := ""
	for fx in all:
		var home := str(fx["home_club_id"])
		var away := str(fx["away_club_id"])
		per_club[home] = int(per_club.get(home, 0)) + 1
		per_club[away] = int(per_club.get(away, 0)) + 1
		if int(fx["played"]) == 1:
			played_per_club[home] = int(played_per_club.get(home, 0)) + 1
			played_per_club[away] = int(played_per_club.get(away, 0)) + 1
		var kickoff := str(fx["kickoff"])
		if first.is_empty() or kickoff < first:
			first = kickoff
		if kickoff > last:
			last = kickoff
	for id in per_club:
		assert_eq(int(per_club[id]), 38, "%s does not have 38 fixtures" % id)
	assert_true(first.begins_with("2026-08"), "the calendar does not open in August 2026 (%s)" % first)
	assert_true(last.begins_with("2027-05"), "the calendar does not close in May 2027 (%s)" % last)
	var played := 0
	for id in played_per_club:
		assert_eq(int(played_per_club[id]), int(played_per_club.values()[0]),
			"%s has a different number of results than the rest of the league" % id)
		played += int(played_per_club[id])
	played = played / 2
	assert_eq(played, PLRepository.shared().fixtures("", 500, "PL").size(),
		"the results list does not match the played fixtures")
	assert_lt(played, 380, "the snapshot claims a finished season")
	assert_eq(played % 10, 0, "results do not come in whole gameweeks")

func test_player_dossier_carries_snapshot_and_career() -> void:
	var p := PLRepository.shared().player("MUN-b-fernandes")
	assert_eq(str(p["club_id"]), "MUN", "the dossier lost its club")
	assert_eq(int(p["ovr"]), 88, "ratings are the game's own dataset and must survive")
	assert_gte(int(p["season"].get("matches", 0)), 1, "no real-world season line")
	assert_gte(int(p["career"].get("matches", 0)), 1, "no career line")
	assert_gte(int(p["age"]), 18, "no identity line from the snapshot")

func test_leaders_are_ordered() -> void:
	var leaders := PLRepository.shared().leaders(6, "goals", "PL")
	assert_eq(leaders.size(), 6, "the scorer chart is short")
	for i in range(1, leaders.size()):
		assert_gte(int(leaders[i - 1]["goals"]), int(leaders[i]["goals"]), "scorers are out of order")

func _clean_cache() -> void:
	PLDatabase.reset()
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	for name in DirAccess.get_files_at(CACHE_DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CACHE_DIR.path_join(name)))
