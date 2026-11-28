extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_test_spanish_pyramid")
var CACHE_DIR := TestScratch.dir("cache_test_spanish_pyramid")
const SEED := 8123
const SPANISH := ["LL", "LL2"]
const PRISTINE := "_pristine.sqlite"

var season: LeagueSeason = null
var slug := ""
var expected_bracket: Dictionary = {}

func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	_clean()
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	season = _finished("Spanish Pair", SEED, SPANISH)
	assert_not_null(season, "the Spanish pair season was not created")
	slug = season.save.slug
	expected_bracket = LeaguePlayoffs.build(season, "LL2")
	_snapshot_as(PRISTINE)

func after_all() -> void:
	if season != null:
		season.close()
		season = null
	_clean()
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func _clean() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		return
	for name in DirAccess.get_files_at(SAVE_DIR):
		if name.ends_with(".sqlite"):
			DirAccess.remove_absolute(SAVE_DIR.path_join(name))


func _finished(name: String, seed: int, comps: Array) -> LeagueSeason:
	var built := LeagueSeason.create(name, "generated", "fixture_days", seed, comps)
	if built == null:
		return null
	_mark_finished(built)
	return built


func _mark_finished(built: LeagueSeason) -> void:
	var places := {}
	for cid in built.save.actives:
		var table: Array = built.record.standings.table(str(cid))
		for i in range(table.size()):
			places[str((table[i] as Dictionary)["club_id"])] = i
	for row in PLDatabase.rows("SELECT id, home_club_id, away_club_id FROM league_fixture;"):
		var home_place: int = places.get(str(row["home_club_id"]), 99)
		var away_place: int = places.get(str(row["away_club_id"]), 99)
		var hg := 2 if home_place < away_place else 0
		var ag := 2 if away_place < home_place else 0
		PLDatabase.execute("UPDATE league_fixture SET status = 'played', home_goals = ?, "
			+ "away_goals = ? WHERE id = ?;", [hg, ag, str(row["id"])])
	built.record.standings.recompute()
	if built.record.fixtures.unplayed() == 0:
		built.save.set_status("complete")


func _snapshot_as(name: String) -> void:
	if season == null or season.save == null:
		return
	season.save.ensure_open()
	PLDatabase.close()
	var bytes := FileAccess.get_file_as_bytes(season.save.path)
	var out := FileAccess.open(SAVE_DIR.path_join(name), FileAccess.WRITE)
	if out != null and not bytes.is_empty():
		out.store_buffer(bytes)
		out.close()
	season.save.ensure_open()


func _restore(name: String) -> LeagueSeason:
	if season != null:
		season.close()
		season = null
	LeagueSeason.active = null
	PLDatabase.close()
	var bytes := FileAccess.get_file_as_bytes(SAVE_DIR.path_join(name))
	var dest := SAVE_DIR.path_join(slug + LeagueSave.EXT)
	var out := FileAccess.open(dest, FileAccess.WRITE)
	assert_true(out != null and not bytes.is_empty(), "the %s Spanish save was missing" % name)
	out.store_buffer(bytes)
	out.close()
	season = LeagueSeason.open(slug)
	assert_not_null(season, "the %s Spanish save did not reopen" % name)
	return season


func _fresh() -> LeagueSeason:
	return _restore(PRISTINE)


func test_the_seed_ships_the_spanish_pair() -> void:
	for cid in SPANISH:
		assert_true(PLCompetitions.exists(cid), "the seed carries no %s" % cid)
	assert_eq(int(PLCompetitions.clubs("LL2")), 22, "La Liga 2 shipped the wrong club set")
	for club_id in TeamData.team_ids("LL2"):
		var team := TeamData.get_team(str(club_id))
		assert_eq((team["starters"] as Array).size(), 11, "%s has no XI" % club_id)
		assert_true(str(team.get("stadium", "")) != "", "%s has no ground" % club_id)
	var flagged := 0
	for club_id in TeamData.team_ids("LL2"):
		if str(PLRepository.shared().club(str(club_id)).get("reserve_of", "")) != "":
			flagged += 1
	assert_eq(flagged, 2, "the seed lost its reserve sides")


func test_a_reserve_side_names_its_senior_club() -> void:
	var found := 0
	for club_id in TeamData.team_ids("LL2"):
		var club := PLRepository.shared().club(str(club_id))
		var senior := str(club.get("reserve_of", ""))
		if senior == "":
			continue
		found += 1
		assert_eq(str(PLRepository.shared().club(senior)["competition_id"]), "LL",
			"%s names a senior club outside La Liga" % club_id)
		assert_true(str(club["name"]).contains("II") or str(club["name"]).contains("Fortuna"),
			"%s is flagged as a filial but does not read as one" % club_id)
	assert_eq(found, 2, "La Liga 2 does not carry two reserve sides")


func test_the_tier_graph_chains_spain() -> void:
	assert_eq(LeagueTiers.chain("Spain"), ["LL", "LL2"], "the Spanish chain is not the top flight first")
	assert_eq(LeagueTiers.country_of("LL2"), "Spain", "La Liga 2 is not Spanish")
	assert_eq(LeagueTiers.above("LL2"), "LL", "La Liga 2's tier above is wrong")
	assert_eq(LeagueTiers.below("LL"), "LL2", "La Liga's tier below is wrong")
	assert_eq(LeagueTiers.below("LL2"), "", "La Liga 2 has a tier below it")
	assert_eq(LeagueTiers.close_up(["LL2"]), ["LL", "LL2"], "La Liga 2 did not close over its chain")
	assert_eq(LeagueTiers.cascading_on([], "LL2"), ["LL", "LL2"], "La Liga 2 did not bring La Liga")
	assert_eq(LeagueTiers.cascading_off(["LL", "LL2"], "LL"), [], "turning La Liga off kept La Liga 2")
	assert_eq(LeagueTiers.pairs(["LL", "LL2"]), [["LL", "LL2"]], "the Spanish pair is not one link")


func test_every_spanish_tier_has_its_own_rules_row() -> void:
	var ll := LeagueRules.template("LL")
	var ll2 := LeagueRules.template("LL2")
	assert_eq(int(ll["clubs"]), 20, "La Liga changed size")
	assert_eq(int(ll["matchdays"]), 38, "La Liga changed matchdays")
	assert_eq(int(ll["relegation_places"]), 3, "La Liga drops three")
	assert_eq(int(ll["ucl_places"]), 4, "La Liga's Champions League band changed")
	assert_eq(int(ll2["clubs"]), 22, "La Liga 2 is not 22 clubs")
	assert_eq(int(ll2["matchdays"]), 42, "La Liga 2 is not 42 matchdays")
	assert_eq(int(ll2["promotion_places"]), 2, "La Liga 2 promotes two directly")
	assert_eq(int(ll2["promotion_playoff_places"]), 4, "La Liga 2's bracket is not four teams")
	assert_eq(int(ll2["relegation_places"]), 4, "La Liga 2's floor is not four")
	assert_eq(int(ll2["ucl_places"]), 0, "La Liga 2 was given a European band")
	assert_eq(int(ll2["playout_places"]), 0, "La Liga 2 grew a play-out")
	assert_eq(str(ll2["playoff_format"]), "segunda_four_two_leg", "La Liga 2 is not on its own bracket")


func test_the_bands_read_each_spanish_tier() -> void:
	var ll := LeagueRules.template("LL")
	assert_eq(LeagueRules.zone(1, ll), "ucl", "the La Liga champion is not in Europe")
	assert_eq(LeagueRules.zone(6, ll), "uecl", "La Liga's sixth lost its Conference place")
	assert_eq(LeagueRules.zone(7, ll), "", "a mid-table La Liga place wears a band")
	assert_eq(LeagueRules.zone(18, ll), "relegation", "La Liga's eighteenth does not go down")
	assert_eq(LeagueRules.zone(20, ll), "relegation", "La Liga's twentieth does not go down")
	var ll2 := LeagueRules.template("LL2")
	assert_eq(LeagueRules.zone(1, ll2), "promotion", "the Segunda winner does not go up")
	assert_eq(LeagueRules.zone(2, ll2), "promotion", "Segunda's second does not go up")
	assert_eq(LeagueRules.zone(3, ll2), "playoff", "Segunda's third is not in the bracket")
	assert_eq(LeagueRules.zone(6, ll2), "playoff", "Segunda's sixth is not in the bracket")
	assert_eq(LeagueRules.zone(7, ll2), "", "a mid-table Segunda place wears a band")
	assert_eq(LeagueRules.zone(19, ll2), "relegation", "Segunda's nineteenth does not go down")
	assert_eq(LeagueRules.zone(22, ll2), "relegation", "Segunda's twenty-second does not go down")
	assert_eq(LeagueTableChrome.bands_for(ll2), ["promotion", "playoff", "relegation"],
		"the Segunda legend does not read its three bands")
	assert_eq(LeagueTableChrome.labels_for(["promotion", "playoff", "relegation"], true),
		["UP", "PLO", "REL"], "the phone legend captions are wrong")
	assert_eq(LeagueTableChrome.bands_for(ll), ["ucl", "uel", "uecl", "relegation"],
		"La Liga's legend changed")


func test_the_pair_builds_two_full_calendars() -> void:
	var current := _fresh()
	assert_eq(current.save.competition_ids(), SPANISH, "the save lost a tier")
	assert_eq(int(current.state()["total"]), 842, "the Spanish pair is not two full calendars")
	assert_eq(current.record.fixtures.all(-1, "LL").size(), 380, "La Liga is not a double round robin")
	assert_eq(current.record.fixtures.all(-1, "LL2").size(), 462, "La Liga 2 is not a double round robin")
	assert_eq(current.record.standings.table("LL2").size(), 22, "the Segunda table is the wrong size")
	assert_eq(int(current.rules_by["LL2"]["matchdays"]), 42, "the Segunda matchday count is wrong")
	current.close()


func test_the_bracket_is_the_spanish_four() -> void:
	var current := _fresh()
	var bracket := LeaguePlayoffs.build(current, "LL2")
	assert_false(bracket.is_empty(), "a finished Segunda has no bracket")
	assert_eq(str(bracket["format"]), "segunda_four_two_leg", "Segunda is not on its own bracket")
	var table := current.record.standings.table("LL2")
	var seeds: Array = []
	for i in range(2, 6):
		seeds.append(str((table[i] as Dictionary)["club_id"]))
	var rounds: Array = bracket["rounds"]
	assert_eq(rounds.size(), 2, "the Spanish bracket is not two rounds")
	assert_eq(str(rounds[0]["name"]), "SEMI-FINALS", "the first round is not the semi-finals")
	var semis: Array = rounds[0]["ties"]
	assert_eq(str(semis[0]["home"]), seeds[0], "the first semi-final is not 3 v 6")
	assert_eq(str(semis[0]["away"]), seeds[3], "the first semi-final is not 3 v 6")
	assert_eq(str(semis[1]["home"]), seeds[1], "the second semi-final is not 4 v 5")
	assert_eq(str(semis[1]["away"]), seeds[2], "the second semi-final is not 4 v 5")
	for tie in semis:
		var legs: Array = (tie as Dictionary)["legs"]
		assert_eq(legs.size(), 2, "a semi-final is not two legs")
		assert_eq(str(legs[0]["home"]), str((tie as Dictionary)["away"]),
			"the first leg is not at the lower place")
		assert_eq(str(legs[1]["home"]), str((tie as Dictionary)["home"]),
			"the return is not at the higher place")
		assert_true(str((tie as Dictionary)["decided_by"]) in [
			"aggregate", "extra time", "higher place"], "a semi-final went to penalties")
	var final: Dictionary = (rounds[1]["ties"] as Array)[0]
	assert_eq((final["legs"] as Array).size(), 2, "the final is not two legs")
	assert_eq(str(final["legs"][0]["home"]), str(final["away"]),
		"the final's first leg is not at the lower-placed finalist")
	assert_eq(str(final["legs"][1]["home"]), str(final["home"]),
		"the final's return is not at the higher place")
	assert_true(str(final["decided_by"]) in ["aggregate", "extra time", "higher place"],
		"the final went to penalties")
	assert_eq(str(bracket["winner_club_id"]), str(final["winner_club_id"]),
		"the bracket's winner is not the final's")
	current.close()


func test_one_seed_settles_one_bracket() -> void:
	var again := _fresh()
	var bracket := LeaguePlayoffs.build(again, "LL2")
	again.close()
	assert_eq(bracket["rounds"], expected_bracket["rounds"], "the bracket differs for one seed")
	assert_eq(str(bracket["winner_club_id"]), str(expected_bracket["winner_club_id"]),
		"the bracket's winner moved between runs of one seed")


func test_a_level_tie_goes_to_extra_time_and_then_the_higher_place() -> void:
	var current := _fresh()
	var table := current.record.standings.table("LL2")
	var high := {"club_id": str(table[2]["club_id"]), "name": str(table[2]["club_name"]),
		"position": 3, "points": 70}
	var low := {"club_id": str(table[5]["club_id"]), "name": str(table[5]["club_name"]),
		"position": 6, "points": 60}
	var seen := {}
	for i in range(40):
		var tie := LeagueSegunda._tie(current, "LL2", "T%d" % i, high, low)
		seen[str(tie["decided_by"])] = true
		assert_eq(int(tie["pens_home"]), -1, "Spain took penalties")
		assert_eq(int(tie["pens_away"]), -1, "Spain took penalties")
		var legs: Array = tie["legs"]
		assert_eq(str(legs[0]["home"]), str(low["club_id"]), "the first leg is not at the lower place")
		if int(tie["home_goals"]) > int(tie["away_goals"]):
			assert_eq(str(tie["winner_club_id"]), str(high["club_id"]), "the higher place lost")
	assert_true(seen.has("aggregate"), "no Spanish tie settled on aggregate")
	assert_true(seen.has("extra time") or seen.has("higher place"),
		"no Spanish tie reached extra time")
	current.close()


func test_the_swap_promotes_three_and_drops_three() -> void:
	var current := _fresh()
	var summary := current.summary()
	var pyramid: Dictionary = summary.get("pyramid", {})
	assert_true(bool(pyramid.get("applied", false)), "the Spanish swap was never applied")
	var links: Array = pyramid.get("links", [])
	assert_eq(links.size(), 1, "the Spanish pair is not one link")
	var link: Dictionary = links[0]
	assert_eq(str(link["top"]), "LL", "the link's top tier is not La Liga")
	assert_eq(str(link["bottom"]), "LL2", "the link's bottom tier is not La Liga 2")
	assert_eq((link["to_top"] as Array).size(), 3, "Spain promotes fewer than three")
	assert_eq((link["to_bottom"] as Array).size(), 3, "La Liga drops fewer than three")
	for club_id in link["to_top"]:
		assert_eq(LeaguePyramid.competition_of(str(club_id)), "LL", "%s did not go up" % club_id)
	for club_id in link["to_bottom"]:
		assert_eq(LeaguePyramid.competition_of(str(club_id)), "LL2", "%s did not go down" % club_id)
	assert_eq(int(PLCompetitions.clubs("LL")), 20, "La Liga changed size in the swap")
	assert_eq(int(PLCompetitions.clubs("LL2")), 22, "La Liga 2 changed size in the swap")
	assert_eq(current.save.status(), "complete", "the save is not marked complete")
	var again := current.summary()
	var again_links: Array = (again.get("pyramid", {}) as Dictionary).get("links", [])
	assert_eq(str((again_links[0] as Dictionary)["to_top"]), str(link["to_top"]),
		"a second summary settled a different swap")
	current.close()


func test_the_podium_lists_both_spanish_tiers() -> void:
	var current := _fresh()
	var summary := current.summary()
	var sections: Array = summary["competitions"]
	assert_eq(sections.size(), 2, "the podium is not one section per Spanish tier")
	var top: Dictionary = sections[0]
	assert_eq(str(top["id"]), "LL", "the podium lost La Liga")
	assert_eq((top["europe"] as Array).size(), 6, "La Liga's Europe band is not six")
	assert_eq((top["relegated"] as Array).size(), 3, "La Liga drops three, not four")
	var lower: Dictionary = sections[1]
	assert_eq(str(lower["id"]), "LL2", "the podium lost La Liga 2")
	assert_eq((lower["europe"] as Array).size(), 0, "La Liga 2 was given a European band")
	assert_eq((lower["relegated"] as Array).size(), 4, "La Liga 2's floor is not four clubs")
	var ladder: Dictionary = lower.get("promotion", {})
	assert_eq((ladder.get("automatic", []) as Array).size(), 2, "the podium promotes two")
	assert_eq((ladder.get("playoff", []) as Array).size(), 4, "the podium bracket is not four")
	var bracket: Dictionary = (summary["playoffs"] as Dictionary)[str(lower["id"])]
	assert_true(str(bracket.get("text", "")) != "", "the podium does not call out the bracket winner")
	current.close()


func test_a_filial_never_takes_a_promotion_place() -> void:
	var current := _fresh()
	var table := current.record.standings.table("LL2")
	var leader := str(table[0]["club_id"])
	PLDatabase.execute("UPDATE club SET reserve_of = ? WHERE id = ?;",
		[str(table[1]["club_id"]), leader])
	PLRepository.shared().invalidate()
	var lower_rules := current.save.rules_for("LL2")
	var automatic := LeagueSegunda.automatic(current, "LL2", lower_rules)
	assert_eq(automatic.size(), 2, "the filial cost the tier an automatic place")
	assert_false(automatic.has(leader), "a filial went up automatically")
	assert_eq(str(automatic[1]), str(table[2]["club_id"]), "the next eligible club did not take the place")
	var bracket := LeaguePlayoffs.build(current, "LL2")
	var rounds: Array = bracket["rounds"]
	var semis: Array = rounds[0]["ties"]
	var seeds: Array = []
	for tie in semis:
		seeds.append(str((tie as Dictionary)["home"]))
		seeds.append(str((tie as Dictionary)["away"]))
	assert_false(seeds.has(leader), "a filial entered the bracket")
	assert_eq(seeds.size(), 4, "the bracket lost a place to the filial")
	assert_true(seeds.has(str(table[6]["club_id"])), "the seventh place did not take the bracket place")
	var row: Dictionary = current.record.standings.table("LL2")[0]
	assert_true(bool(row["filial"]), "the standings row does not read the filial flag")
	assert_eq(LeagueTableChrome.zone_for(row, lower_rules), "", "a filial still wears a promotion band")
	var dropped: Dictionary = current.record.standings.table("LL2")[21]
	dropped["filial"] = true
	assert_eq(LeagueTableChrome.zone_for(dropped, lower_rules), "relegation",
		"a filial lost its relegation label")
	current.close()


func test_a_lone_tier_plays_no_spanish_tie() -> void:
	var solo := LeagueSeason.create("La Liga Alone", "generated", "fixture_days", 21, ["LL"])
	assert_not_null(solo, "the lone La Liga season was not created")
	_mark_finished(solo)
	assert_true(LeaguePlayoffs.build(solo, "LL2").is_empty(),
		"La Liga 2 played a bracket without La Liga above it")
	solo.close()
	_fresh().close()


func test_the_readings_refuse_what_they_cannot_settle() -> void:
	assert_true(LeagueSegunda.format(LeagueRules.template("LL2")),
		"La Liga 2's format is not recognised")
	assert_false(LeagueSegunda.format(LeagueRules.template("LL")),
		"La Liga was read as the Segunda format")
	assert_true(LeagueSegunda.build(null, "LL2", LeagueRules.template("LL2")).is_empty(),
		"a missing season played a bracket")
	assert_true(LeagueSegunda.automatic(null, "LL2", LeagueRules.template("LL2")).is_empty(),
		"a missing season promoted a club")
	var thin := LeagueRules.template("LL2")
	thin["promotion_playoff_places"] = 2
	var open_season := _fresh()
	assert_true(LeagueSegunda.build(open_season, "LL2", thin).is_empty(),
		"a two-team bracket was played")
	assert_eq(LeagueSegunda.eligible(open_season, "LL2").size(), 20,
		"the Segunda pool is not the twenty senior clubs")
	assert_eq(LeagueSegunda.ladder(open_season, "LL2", LeagueRules.template("LL2"))["automatic"].size(),
		2, "the ladder doesn't promote two")
	open_season.close()
	var early := LeagueSeason.create("Early", "generated", "fixture_days", 5, SPANISH)
	assert_not_null(early, "the early season was not created")
	assert_true(LeagueSegunda.build(early, "LL2", LeagueRules.template("LL2")).is_empty(),
		"an unfinished season played a bracket")
	early.close()
	_fresh().close()


func test_the_phone_table_reads_the_segunda_bands() -> void:
	var rows := []
	var rules := LeagueRules.template("LL2")
	for i in range(22):
		rows.append({"club_id": "ESP-T%d" % i, "club_name": "Club %d" % i, "position": i + 1,
			"played": 6, "won": 3, "drawn": 1, "lost": 2, "gf": 9, "ga": 7, "points": 20 - i,
			"filial": i == 0})
	var items: Array = LeagueTableLayout.rows(rows, LeagueTableLayout.places(
		Rect2(24.0, 60.0, 865.0, 24.0), LeagueTableLayout.COMPACT), {}, {"rules": rules},
		60.0, 22.0, 865.0)
	assert_eq(items.size(), 22, "the phone table dropped a Segunda row")
	assert_eq(str(items[0]["zone"]), "", "a filial's phone row wears a promotion band")
	assert_eq(str(items[1]["zone"]), "promotion", "the phone table lost its first promotion band")
	assert_eq(str(items[3]["zone"]), "playoff", "the phone table lost its bracket band")
	assert_eq(str(items[21]["zone"]), "relegation", "the phone table lost its floor band")
	assert_eq(LeagueTableChrome.labels_for(
		LeagueTableChrome.bands_for(rules), true), ["UP", "PLO", "REL"],
		"the phone legend does not read the Segunda bands")


func test_the_ui_names_the_second_tier() -> void:
	var ll2 := PLRepository.shared().competition("LL2")
	assert_eq(LeagueChrome.competition_chip_label(ll2, 40.0), "LL2",
		"the phone chip does not name La Liga 2")
	assert_eq(str(WikiCompetitions.SHORT.get("LL2", "")), "LA LIGA 2",
		"the encyclopedia chip does not name La Liga 2")
	var sheet := LeaguePodiumSheet.new()
	var section := {"id": "LL2", "rules": LeagueRules.template("LL2"), "europe": [],
		"relegated": [], "table": [], "champion": {"club": "a", "points": 1},
		"runner_up": {"club": "b", "points": 2},
		"promotion": {"automatic": [{"club": "a", "position": 1, "points": 80}],
			"playoff": [{"club": "b", "position": 3, "points": 70}]}}
	var with_ladder := sheet.frame_height({"summary": {"playoffs": {},
		"competitions": [section]}})
	var plain := section.duplicate(true)
	plain.erase("promotion")
	plain["rules"] = {}
	var without := sheet.frame_height({"summary": {"playoffs": {}, "competitions": [plain]}})
	assert_gt(with_ladder, without, "the podium does not make room for the Segunda block")
	var ladder := LeaguePodiumSheet.promotion_rows(section)
	assert_eq((ladder["automatic"] as Array).size(), 1, "the podium lost the automatic place")
	assert_eq((ladder["playoff"] as Array).size(), 1, "the podium lost the bracket place")
