extends GdToolsTest

## Multi-league saves (#185/#188): one file, one clock, two active competitions.
## The suite creates a Premier League + La Liga season, walks a day, and reads
## every league-scoped surface back: fixtures, tables, leaders, the advance-mode
## edit, the completion gate, and the old PL-only save's migration path.

var SAVE_DIR := TestScratch.dir("saves_test_multi_league")
var CACHE_DIR := TestScratch.dir("cache_test_multi_league")
const SEED := 4242

var season: LeagueSeason = null

func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	_clean()
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	season = LeagueSeason.create("Two Leagues", "generated", "fixture_days", SEED, ["PL", "LL"])

func after_all() -> void:
	if season != null:
		season.close()
	_clean()
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func test_the_save_runs_both_competitions() -> void:
	assert_not_null(season, "the multi-league season was not created")
	assert_eq(season.save.competition_ids(), ["PL", "LL"], "the save lost an active competition")
	var state := season.state()
	assert_eq(int(state["total"]), 760, "two leagues are not two full calendars")
	assert_eq((state["competitions"] as Array).size(), 2, "the state lists one competition")
	assert_eq((state["tables"] as Dictionary)["PL"].size(), 20, "the PL table is short")
	assert_eq((state["tables"] as Dictionary)["LL"].size(), 20, "the La Liga table is short")
	var per_comp := {"PL": 0, "LL": 0}
	for fx in season.record.fixtures.all():
		var cid := str(fx["competition_id"])
		per_comp[cid] = int(per_comp.get(cid, 0)) + 1
	assert_eq(int(per_comp["PL"]), 380, "the Premier League calendar is short")
	assert_eq(int(per_comp["LL"]), 380, "the La Liga calendar is short")
	var ids := {}
	for fx in season.record.fixtures.all():
		assert_false(ids.has(str(fx["id"])), "two fixtures share an id across leagues")
		ids[str(fx["id"])] = true

func test_same_day_fixtures_are_grouped_by_league() -> void:
	var plan := season.plan()
	assert_eq(plan.size(), 20, "both leagues should play on the opening day")
	var seen := ""
	var switches := 0
	for fx in plan:
		var cid := str(fx["competition_id"])
		if cid != seen:
			switches += 1
			seen = cid
	assert_eq(switches, 2, "the day is not grouped into two league blocks")

func test_continue_sims_every_league_on_the_shared_clock() -> void:
	var before := season.state()
	var result := season.advance()
	assert_eq((result["played"] as Array).size(), 20, "Continue did not sim both leagues")
	assert_eq((result["pending"] as Array).size(), 0, "a mixed day left a match waiting")
	assert_false(bool(result["complete"]), "the season finished in August")
	var after := season.state()
	assert_eq(int(after["played"]), int(before["played"]) + 20, "the ledger lost a league's day")
	assert_true(str(after["date"]) > str(before["date"]), "the shared clock did not move")
	for cid in ["PL", "LL"]:
		var points := 0
		for row in (after["tables"] as Dictionary)[cid]:
			assert_eq(int(row["played"]), 1, "%s did not count its first gameweek" % row["club_id"])
			points += int(row["points"])
		assert_gte(points, 20, "%s paid no points" % cid)

func test_leaders_are_competition_correct() -> void:
	for cid in ["PL", "LL"]:
		var rows: Array = season.record.report.top_scorers(5, str(cid))
		assert_gte(rows.size(), 1, "%s has no scorer" % cid)
		var leaders: Array = PLRepository.shared().sim_leaders(5, str(cid))
		assert_gte(leaders.size(), 1, "%s has no leader chart" % cid)
		for row in leaders:
			assert_eq(str(row["competition_id"]), str(cid), "the leader chart mixed competitions")

func test_the_advance_mode_can_change_mid_season() -> void:
	assert_eq(season.save.advance_mode(), "fixture_days", "the save opened on another clock")
	assert_true(season.set_advance_mode("every_day"), "the mid-season change did not stick")
	assert_eq(season.save.advance_mode(), "every_day", "the save kept the old policy")
	season.save.reload()
	assert_eq(season.save.advance_mode(), "every_day", "the policy did not survive a reload")
	assert_true(season.set_advance_mode("fixture_days"), "the change back did not stick")

func test_the_summary_waits_for_every_active_league() -> void:
	# Not finished yet: the podium must stay empty while any league has a fixture
	# left. Then mark both calendars played and read the two champion blocks.
	var slug := str(season.save.slug)
	assert_true(season.summary().is_empty(), "an unfinished multi-league season had a podium")
	PLDatabase.execute("UPDATE league_fixture SET status = 'played', home_goals = 1, away_goals = 0;")
	season.record.standings.recompute()
	assert_eq(season.record.fixtures.unplayed(), 0, "the completion gate is not on every league")
	var summary := season.summary()
	assert_false(summary.is_empty(), "a finished multi-league season has no summary")
	var sections: Array = summary.get("competitions", [])
	assert_eq(sections.size(), 2, "the podium is not one section per league")
	assert_eq(str(sections[0]["id"]), "PL", "the podium lost the league order")
	assert_eq(str(sections[1]["id"]), "LL", "the podium lost the league order")
	assert_eq((sections[1]["table"] as Array).size(), 20, "a podium section has no table")
	# The save is left on disk; the relaunch test reopens it.
	assert_true(str(slug) != "", "the save has no slug")

func test_a_pl_only_save_still_opens_as_pl_active() -> void:
	var single := LeagueSeason.create("Old World", "generated", "fixture_days", SEED + 1)
	assert_not_null(single, "the single-league save was not created")
	assert_eq(single.save.competition_ids(), ["PL"], "a default save is not PL-only")
	assert_eq(int(single.state()["total"]), 380, "a PL-only save is not one calendar")
	var slug := str(single.save.slug)
	single.close()
	var reopened := LeagueSeason.open(slug)
	assert_not_null(reopened, "the PL-only save did not reopen")
	assert_eq(reopened.save.competition_ids(), ["PL"], "an old save opened with the wrong actives")
	assert_eq(PLRepository.shared().table("LL").size(), 0, "a PL-only save exposes La Liga")
	reopened.close()

func test_the_per_competition_rules_are_templates() -> void:
	var pl := LeagueRules.template("PL")
	var ll := LeagueRules.template("LL")
	assert_eq(int(pl["matchdays"]), 38, "the PL template lost its rounds")
	assert_eq(int(ll["relegation_places"]), 3, "La Liga lost its drop")
	assert_eq(int(ll["ucl_places"]), 4, "La Liga lost its European places")
	assert_ne(int(pl["midweek_matchdays"]), int(ll["midweek_matchdays"]),
		"the two competitions share one calendar template")

func test_a_pre_multi_save_is_migrated_on_open() -> void:
	var season := LeagueSeason.create("Legacy World", "generated", "fixture_days", SEED + 2)
	assert_not_null(season, "the legacy save was not created")
	var save: LeagueSave = season.save
	var slug := str(save.slug)
	# A save written before multi-league has no active-competition table and no
	# competition column on its match rows.
	PLDatabase.execute("DROP TABLE save_competition;")
	PLDatabase.execute("DELETE FROM save_meta WHERE key = 'competitions';")
	PLDatabase.execute("DROP INDEX IF EXISTS league_fixture_comp_idx;")
	for table in ["league_fixture", "league_table", "league_player_stat"]:
		PLDatabase.execute("ALTER TABLE %s DROP COLUMN competition_id;" % table)
	season.close()
	var reopened := LeagueSave.open(slug)
	assert_not_null(reopened, "the legacy save did not open")
	assert_eq(reopened.competition_ids(), ["PL"], "the legacy save did not open as PL-active")
	var rows := PLDatabase.rows(
		"SELECT COUNT(*) AS n FROM league_fixture WHERE competition_id = 'PL';")
	assert_eq(int(rows[0]["n"]), 380, "the migration did not stamp the legacy fixtures")
	assert_false(PLDatabase.row(
		"SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'save_competition';").is_empty(),
		"the migration did not recreate the active-competition table")
	reopened.close()

func _clean() -> void:
	for folder in [SAVE_DIR, CACHE_DIR]:
		TestScratch.clear(folder)
