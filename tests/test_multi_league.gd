extends GdToolsTest


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

func test_the_roundup_groups_by_league() -> void:
	var reports: Array = []
	for fx in season.plan():
		reports.append({"fixture": fx, "events": []})
	var items: Array = LeagueReportSheet.new().layout(Vector2(1000.0, 1400.0), {"roundup": reports})
	var heads: Array = []
	for item in items:
		if str(item.get("kind", "")) == "league_head":
			heads.append(item)
	assert_eq(heads.size(), 2, "a mixed roundup should head each league once")
	assert_eq(str(heads[0]["competition"]), "PL", "the roundup lost the first league's head")
	assert_eq(str(heads[1]["competition"]), "LL", "the roundup lost the second league's head")
	var single: Array = LeagueReportSheet.new().layout(Vector2(1000.0, 800.0),
		{"roundup": [{"fixture": season.plan()[0], "events": []}]})
	var single_heads := 0
	for item in single:
		if str(item.get("kind", "")) == "league_head":
			single_heads += 1
	assert_eq(single_heads, 0, "a one-league roundup does not need a head")

func test_a_mixed_roundup_offers_league_chips() -> void:
	var reports := _day_reports()
	assert_gt(reports.size(), 1, "the opening day has no fixtures")
	var items: Array = LeagueReportSheet.new().layout(Vector2(1000.0, 1400.0),
		{"roundup": reports})
	var chips := _choice_chips(items)
	assert_true(chips.has("resultleague:"), "a mixed roundup has no ALL chip")
	assert_true(chips.has("resultleague:PL"), "a mixed roundup has no PL chip")
	assert_true(chips.has("resultleague:LL"), "a mixed roundup has no LL chip")
	assert_true(bool(chips["resultleague:"]["selected"]), "a fresh roundup did not select ALL")
	assert_false(bool(chips["resultleague:PL"]["selected"]),
		"a fresh roundup pre-selected a league")
	assert_true(bool(chips["resultleague:PL"].get("pinned", false)),
		"a league chip scrolls away with the list")
	for vp in [Vector2(1000.0, 1400.0), Vector2(913.0, 411.0)]:
		var touch_items: Array = LeagueReportSheet.new().layout(vp,
			{"roundup": reports, "touch": true})
		for chip in _choice_chips(touch_items).values():
			var rect: Rect2 = chip["rect"]
			assert_gte(rect.size.y, UiChrome.TAP_H,
				"a result chip is too short for a thumb at %s" % vp)
			assert_lte(rect.end.x, vp.x - 20.0, "a result chip runs off the sheet at %s" % vp)

func test_a_league_chip_cuts_the_roundup() -> void:
	var reports := _day_reports()
	var full: Array = _result_rows(LeagueReportSheet.new().layout(Vector2(1000.0, 4000.0),
		{"roundup": reports}))
	assert_gt(full.size(), 1, "the opening day laid out no result rows")
	var ll: Array = _result_rows(LeagueReportSheet.new().layout(Vector2(1000.0, 4000.0),
		{"roundup": reports, "filters": {"league": "LL"}}))
	assert_eq(ll.size(), full.size() / 2, "the LL chip kept the wrong number of results")
	for row in ll:
		assert_eq(str((row["report"]["fixture"] as Dictionary)["competition_id"]), "LL",
			"the LL chip kept another league's result")
	var restored: Array = _result_rows(LeagueReportSheet.new().layout(Vector2(1000.0, 4000.0),
		{"roundup": reports, "filters": {"league": ""}}))
	assert_eq(restored.size(), full.size(), "ALL did not restore the whole day")

func test_a_single_league_day_hides_the_competition_chips() -> void:
	var one: Array = [{"fixture": season.plan()[0], "events": []}]
	for filters in [{}, {"league": "PL"}]:
		var items: Array = LeagueReportSheet.new().layout(Vector2(1000.0, 800.0),
			{"roundup": one, "filters": filters})
		assert_true(_choice_chips(items).is_empty(),
			"a one-league day drew a competition chip")

func test_the_interest_filter_keeps_only_followed_clubs() -> void:
	var reports := _day_reports()
	var club := ""
	for report in reports:
		var fx: Dictionary = report["fixture"]
		if str(fx["competition_id"]) == "LL":
			club = str(fx["home_club_id"])
			break
	assert_true(club != "", "the opening day has no La Liga fixture")
	var marks := [club]
	var bare: Array = LeagueReportSheet.new().layout(Vector2(1000.0, 4000.0),
		{"roundup": reports})
	assert_false(_choice_chips(bare).has("resultinterest"),
		"the day showed an interest filter for an empty shortlist")
	var chips := _choice_chips(LeagueReportSheet.new().layout(Vector2(1000.0, 4000.0),
		{"roundup": reports, "interests": marks}))
	assert_true(chips.has("resultinterest"), "a followed club raised no interest chip")
	assert_false(bool(chips["resultinterest"]["selected"]), "the interest filter started on")
	var kept: Array = _result_rows(LeagueReportSheet.new().layout(Vector2(1000.0, 4000.0),
		{"roundup": reports, "interests": marks, "filters": {"interest": true}}))
	assert_eq(kept.size(), 1, "the interest filter kept more than the followed match")
	var followed: Dictionary = kept[0]["report"]["fixture"]
	assert_true(str(followed["home_club_id"]) == club or str(followed["away_club_id"]) == club,
		"the interest filter kept a match with no followed club")
	var combined: Array = _result_rows(LeagueReportSheet.new().layout(Vector2(1000.0, 4000.0),
		{"roundup": reports, "interests": marks,
			"filters": {"league": "LL", "interest": true}}))
	assert_eq(combined.size(), 1, "the league and interest filters did not combine")
	var blocked: Array = LeagueReportSheet.new().layout(Vector2(1000.0, 4000.0),
		{"roundup": reports, "interests": marks,
			"filters": {"league": "PL", "interest": true}})
	assert_true(_result_rows(blocked).is_empty(), "a combined filter kept an unfollowed league")
	var notes := 0
	for item in blocked:
		if str(item.get("kind", "")) == "note":
			notes += 1
	assert_eq(notes, 1, "an empty filtered roundup said nothing")

func test_the_screen_presses_the_chips_into_a_short_list() -> void:
	var world := LeagueSeason.create("Chip World", "generated", "fixture_days", SEED + 9,
		["PL", "LL"])
	assert_not_null(world, "the chip season was not created")
	var chip_screen := LeagueScreen.new()
	add_child(chip_screen)
	chip_screen.season = world
	chip_screen.mode = LeagueScreen.MODE_HUB
	chip_screen.visible = true
	chip_screen.refresh()
	chip_screen.click("continue")
	assert_eq(chip_screen.mode, LeagueScreen.MODE_REPORT,
		"a mixed day did not open its roundup")
	var ids := {}
	for item in chip_screen.buttons:
		ids[str(item["id"])] = true
	assert_true(ids.has("resultleague:PL") and ids.has("resultleague:LL"),
		"the live roundup drew no league chips")
	var full: Array = _match_rows(chip_screen.buttons)
	assert_gt(full.size(), 1, "the live roundup laid out no rows")
	chip_screen.click("resultleague:LL")
	assert_eq(str(chip_screen.report_filter["league"]), "LL", "the LL chip was not recorded")
	var ll: Array = _match_rows(chip_screen.buttons)
	assert_eq(ll.size(), full.size() / 2, "the LL chip did not halve the day")
	for fx in ll:
		assert_eq(str(fx["competition_id"]), "LL", "the live roundup kept a PL row")
	chip_screen.click("resultleague:LL")
	assert_eq(str(chip_screen.report_filter["league"]), "", "the LL chip did not toggle back")
	assert_eq(_match_rows(chip_screen.buttons).size(), full.size(),
		"ALL did not restore the live day")

	var club := str((chip_screen.roundup[0]["fixture"] as Dictionary)["home_club_id"])
	assert_true(world.set_interest(club, true), "the shortlist refused a club")
	chip_screen.refresh()
	chip_screen.click("resultinterest")
	assert_eq(_match_rows(chip_screen.buttons).size(), 1,
		"the live interest filter kept more than one match")
	assert_true(world.set_interest(club, false), "the shortlist kept a club")
	chip_screen.refresh()
	chip_screen.click("continue")
	chip_screen.click("continue")
	assert_eq(chip_screen.mode, LeagueScreen.MODE_REPORT,
		"a second Continue did not settle a new day")
	assert_eq(str(chip_screen.report_filter["league"]), "",
		"the new day kept the old league filter")
	assert_false(bool(chip_screen.report_filter["interest"]),
		"the new day kept the old interest filter")
	chip_screen.queue_free()
	world.close()

func _day_reports() -> Array:
	var reports: Array = []
	for fx in season.plan():
		reports.append({"fixture": fx, "events": []})
	return reports

func _choice_chips(items: Array) -> Dictionary:
	var chips := {}
	for item in items:
		if str(item.get("kind", "")) == "choice":
			chips[str(item["id"])] = item
	return chips

func _result_rows(items: Array) -> Array:
	var rows: Array = []
	for item in items:
		if str(item.get("kind", "")) == "result":
			rows.append(item)
	return rows

func _match_rows(items: Array) -> Array:
	var rows: Array = []
	for item in items:
		if str(item.get("id", "")).begins_with("match:"):
			rows.append(item["report"]["fixture"])
	return rows

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

	assert_true(str(slug) != "", "the save has no slug")

func test_the_boot_orders_and_closes_competitions() -> void:


	assert_eq(LeagueSeasonBoot.known_competitions(["LL", "PL"]), ["PL", "LL"],
		"the boot lost the published fixture order")
	assert_eq(LeagueSeasonBoot.known_competitions(["CH"]), ["PL", "CH"],
		"the boot did not close a lower tier over its chain")
	assert_eq(LeagueSeasonBoot.known_competitions([]), ["PL"],
		"an empty pick did not fall back to a known competition")

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


	PLDatabase.execute("DROP TABLE save_competition;")
	PLDatabase.execute("DELETE FROM save_meta WHERE key = 'competitions';")
	PLDatabase.execute("DROP INDEX IF EXISTS league_fixture_comp_idx;")
	PLDatabase.execute("ALTER TABLE league_fixture DROP COLUMN competition_id;")
	PLDatabase.execute("ALTER TABLE league_player_stat RENAME TO league_player_stat_legacy;")
	PLDatabase.execute(
		"CREATE TABLE league_player_stat (player_id TEXT PRIMARY KEY, club_id TEXT NOT NULL, "
		+ "apps INTEGER NOT NULL DEFAULT 0, goals INTEGER NOT NULL DEFAULT 0, "
		+ "assists INTEGER NOT NULL DEFAULT 0, yellow INTEGER NOT NULL DEFAULT 0, "
		+ "red INTEGER NOT NULL DEFAULT 0);")
	PLDatabase.execute(
		"INSERT INTO league_player_stat (player_id, club_id, apps, goals, assists, yellow, red) "
		+ "SELECT player_id, club_id, apps, goals, assists, yellow, red "
		+ "FROM league_player_stat_legacy;")
	PLDatabase.execute("DROP TABLE league_player_stat_legacy;")
	PLDatabase.execute("ALTER TABLE league_table RENAME TO league_table_two;")
	PLDatabase.execute(
		"CREATE TABLE league_table (club_id TEXT PRIMARY KEY, "
		+ "played INTEGER NOT NULL DEFAULT 0, won INTEGER NOT NULL DEFAULT 0, "
		+ "drawn INTEGER NOT NULL DEFAULT 0, lost INTEGER NOT NULL DEFAULT 0, "
		+ "gf INTEGER NOT NULL DEFAULT 0, ga INTEGER NOT NULL DEFAULT 0, "
		+ "points INTEGER NOT NULL DEFAULT 0);")
	PLDatabase.execute(
		"INSERT INTO league_table (club_id, played, won, drawn, lost, gf, ga, points) "
		+ "SELECT club_id, played, won, drawn, lost, gf, ga, points FROM league_table_two;")
	PLDatabase.execute("DROP TABLE league_table_two;")
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
