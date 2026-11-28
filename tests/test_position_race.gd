extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_test_position_race")
var CACHE_DIR := TestScratch.dir("cache_test_position_race")
const SEED := 2027

var season: LeagueSeason = null
var snapshot := {}


func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	_clean()
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	snapshot = PositionRace.series("ENG-MUN1")
	season = LeagueSeason.create("Position Race", "generated", "fixture_days", SEED)

func after_all() -> void:
	if season != null:
		season.close()
	_clean()
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()


func test_the_snapshot_race_lands_on_the_shipped_table() -> void:
	assert_false(snapshot.is_empty(), "the shipped season drew no race")
	assert_eq(int(snapshot["clubs"]), 20, "the race lists the wrong club count")
	assert_eq(int(snapshot["place"]), int(PLDatabase.row(
		"SELECT position FROM table_row WHERE club_id = 'ENG-MUN1';").get("position", 0)),
		"the race's last day disagrees with the shipped table")
	var dates := []
	for day in snapshot["days"]:
		dates.append(str(day["date"]))
	assert_gte(dates.size(), 11, "the snapshot race is shorter than its gameweeks")
	var sorted := dates.duplicate()
	sorted.sort()
	assert_eq(dates, sorted, "the race's days are not in calendar order")


func test_a_new_season_has_no_race() -> void:
	assert_not_null(season, "the season was not created")
	assert_true(PositionRace.series("ENG-MUN1").is_empty(), "an unplayed season drew a race")


func test_one_day_is_not_a_race() -> void:
	_play_day()
	assert_true(PositionRace.series("ENG-MUN1").is_empty(), "a single day drew a race")


func test_the_race_reads_a_position_for_every_day_played() -> void:
	_play_day()
	_play_day()
	var race := PositionRace.series("ENG-MUN1")
	assert_false(race.is_empty(), "three played days drew no race")
	assert_eq(int(race["clubs"]), 20, "the race lists the wrong club count")
	assert_eq((race["days"] as Array).size(), 3, "the race lost a played day")
	assert_lte(int(race["best"]), int(race["place"]), "the best place is worse than the last")
	assert_gte(int(race["worst"]), int(race["place"]), "the worst place is better than the last")
	assert_eq(int(race["place"]), int(LeagueLedger.club_record("ENG-MUN1").get("position", 0)),
		"the race disagrees with the club's own table row")


func test_the_table_leader_sits_at_the_top_of_its_race() -> void:
	var leader := str((LeagueLedger.table("PL")[0] as Dictionary)["club_id"])
	var race := PositionRace.series(leader)
	assert_false(race.is_empty(), "the leader drew no race")
	assert_eq(int(race["place"]), 1, "the leader's last day is not first")
	assert_eq(int(race["best"]), 1, "the leader never reached first")


func test_every_club_lands_where_the_table_says() -> void:
	for row in season.state()["table"]:
		var race := PositionRace.series(str(row["club_id"]))
		assert_false(race.is_empty(), "a club with a played day drew no race")
		assert_eq(int(race["place"]), int(row["position"]),
			"the race's last day disagrees with the table")


func _play_day() -> void:
	var rows := PLDatabase.rows(
		"SELECT id, home_club_id, away_club_id, kickoff FROM league_fixture "
		+ "WHERE status <> 'played' ORDER BY kickoff, kickoff_time, id;")
	assert_gt(rows.size(), 0, "the calendar has no fixture left to play")
	var date := str((rows[0] as Dictionary)["kickoff"])
	for row in rows:
		if str(row["kickoff"]) != date:
			break
		var home := str(row["home_club_id"])
		var away := str(row["away_club_id"])
		PLDatabase.execute(
			"UPDATE league_fixture SET status = 'played', home_goals = ?, away_goals = ? "
			+ "WHERE id = ?;", [2 if home < away else 0, 2 if away < home else 0, str(row["id"])])
	season.record.standings.recompute()


func _clean() -> void:
	for folder in [SAVE_DIR, CACHE_DIR]:
		TestScratch.clear(folder)
