extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_test_italian_pyramid")
var CACHE_DIR := TestScratch.dir("cache_test_italian_pyramid")
const SEED := 7311
const ITALIAN := ["SA", "SB"]
const PRISTINE := "_pristine.sqlite"

var season: LeagueSeason = null
var slug := ""
var expected_bracket: Dictionary = {}
var expected_playout: Dictionary = {}

func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	_clean()
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	season = _finished("Italian Pair", SEED, ITALIAN)
	assert_not_null(season, "the Italian pair season was not created")
	slug = season.save.slug
	expected_bracket = LeaguePlayoffs.build(season, "SB")
	expected_playout = LeagueSerieB.playout(season, "SB", season.save.rules_for("SB"))
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
	var scored := {}
	for i in range(20):
		scored[i] = 40 - i * 2
	for row in PLDatabase.rows(
			"SELECT id, home_club_id, away_club_id, competition_id FROM league_fixture;"):
		var comp := str(row["competition_id"])
		var table: Array = built.record.standings.table(comp)
		var home_place := _place(table, str(row["home_club_id"]), scored)
		var away_place := _place(table, str(row["away_club_id"]), scored)
		var hg := 2 if home_place < away_place else 0
		var ag := 2 if away_place < home_place else 0
		PLDatabase.execute("UPDATE league_fixture SET status = 'played', home_goals = ?, "
			+ "away_goals = ? WHERE id = ?;", [hg, ag, str(row["id"])])
	built.record.standings.recompute()
	if built.record.fixtures.unplayed() == 0:
		built.save.set_status("complete")


func _place(table: Array, club_id: String, scored: Dictionary) -> int:
	for i in range(table.size()):
		if str((table[i] as Dictionary)["club_id"]) == club_id:
			return i
	return 99


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
	assert_true(out != null and not bytes.is_empty(), "the %s Italian save was missing" % name)
	out.store_buffer(bytes)
	out.close()
	season = LeagueSeason.open(slug)
	assert_not_null(season, "the %s Italian save did not reopen" % name)
	return season


func _fresh() -> LeagueSeason:
	return _restore(PRISTINE)


func test_the_seed_ships_the_italian_pair() -> void:
	for cid in ITALIAN:
		assert_true(PLCompetitions.exists(cid), "the seed carries no %s" % cid)
		assert_eq(int(PLCompetitions.clubs(cid)), 20, "%s shipped the wrong club set" % cid)
		for club_id in TeamData.team_ids(cid):
			assert_true(str(club_id).begins_with("ITA-"),
				"%s does not carry its country prefix" % club_id)
			var team := TeamData.get_team(str(club_id))
			assert_eq((team["starters"] as Array).size(), 11, "%s has no XI" % club_id)
			assert_true(str(team.get("stadium", "")) != "", "%s has no ground" % club_id)


func test_the_tier_graph_chains_italy() -> void:
	assert_eq(LeagueTiers.chain("Italy"), ["SA", "SB"], "the Italian chain is not the top flight first")
	assert_eq(LeagueTiers.country_of("SA"), "Italy", "Serie A is not Italian")
	assert_eq(LeagueTiers.country_of("SB"), "Italy", "Serie B is not Italian")
	assert_eq(LeagueTiers.above("SB"), "SA", "Serie B's tier above is wrong")
	assert_eq(LeagueTiers.above("SA"), "", "Serie A has a tier above it")
	assert_eq(LeagueTiers.below("SA"), "SB", "Serie A's tier below is wrong")
	assert_eq(LeagueTiers.below("SB"), "", "Serie B has a tier below it")
	assert_eq(LeagueTiers.close_up(["SB"]), ["SA", "SB"], "Serie B did not close over its chain")
	assert_eq(LeagueTiers.cascading_on([], "SB"), ["SA", "SB"], "Serie B did not bring Serie A")
	assert_eq(LeagueTiers.cascading_off(["SA", "SB"], "SA"), [], "turning Serie A off kept Serie B")
	assert_eq(LeagueTiers.pairs(["SA", "SB"]), [["SA", "SB"]], "the Italian pair is not one link")


func test_every_italian_tier_has_its_own_rules_row() -> void:
	var sa := LeagueRules.template("SA")
	var sb := LeagueRules.template("SB")
	assert_eq(int(sa["clubs"]), 20, "Serie A is not 20 clubs")
	assert_eq(int(sa["matchdays"]), 38, "Serie A is not 38 matchdays")
	assert_eq(int(sa["relegation_places"]), 3, "Serie A drops three")
	assert_eq(int(sa["ucl_places"]), 4, "Serie A's Champions League band changed")
	assert_eq(int(sa["uel_places"]), 1, "Serie A's Europa League band changed")
	assert_eq(int(sa["uecl_places"]), 1, "Serie A's Conference band changed")
	assert_eq(int(sa["promotion_places"]), 0, "Serie A promotes")
	assert_eq(str(sa["playoff_format"]), "", "Serie A plays a bracket")
	assert_eq(int(sb["clubs"]), 20, "Serie B is not 20 clubs")
	assert_eq(int(sb["matchdays"]), 38, "Serie B is not 38 matchdays")
	assert_eq(int(sb["promotion_places"]), 2, "Serie B promotes two directly")
	assert_eq(int(sb["promotion_playoff_places"]), 6, "Serie B's bracket is not six teams")
	assert_eq(int(sb["promotion_skip_gap"]), 14, "the 14-point skip moved")
	assert_eq(str(sb["playoff_format"]), "serie_b_six", "Serie B is not on its own bracket")
	assert_eq(int(sb["relegation_places"]), 3, "Serie B drops three directly")
	assert_eq(int(sb["playout_places"]), 2, "Serie B's play-out is not two places")


func test_the_bands_read_each_italian_tier() -> void:
	var sa := LeagueRules.template("SA")
	assert_eq(LeagueRules.zone(1, sa), "ucl", "the Serie A champion is not in Europe")
	assert_eq(LeagueRules.zone(4, sa), "ucl", "Serie A's fourth is not in the Champions League")
	assert_eq(LeagueRules.zone(5, sa), "uel", "Serie A's fifth is not in the Europa League")
	assert_eq(LeagueRules.zone(6, sa), "uecl", "Serie A's sixth is not in the Conference League")
	assert_eq(LeagueRules.zone(7, sa), "", "a mid-table Serie A place wears a band")
	assert_eq(LeagueRules.zone(18, sa), "relegation", "Serie A's eighteenth does not go down")
	assert_eq(LeagueRules.zone(20, sa), "relegation", "Serie A's twentieth does not go down")
	var sb := LeagueRules.template("SB")
	assert_eq(LeagueRules.zone(1, sb), "promotion", "the Serie B winner does not go up")
	assert_eq(LeagueRules.zone(2, sb), "promotion", "Serie B's second does not go up")
	assert_eq(LeagueRules.zone(3, sb), "playoff", "Serie B's third is not in the bracket")
	assert_eq(LeagueRules.zone(8, sb), "playoff", "Serie B's eighth is not in the bracket")
	assert_eq(LeagueRules.zone(9, sb), "", "a mid-table Serie B place wears a band")
	assert_eq(LeagueRules.zone(16, sb), "playout", "Serie B's sixteenth is not the play-out")
	assert_eq(LeagueRules.zone(17, sb), "playout", "Serie B's seventeenth is not the play-out")
	assert_eq(LeagueRules.zone(18, sb), "relegation", "Serie B's eighteenth does not go down")
	assert_eq(LeagueRules.zone_label("playout"), "PLY", "the play-out band has no label")
	assert_eq(LeagueTableChrome.bands_for(sb), ["promotion", "playoff", "playout", "relegation"],
		"the Serie B legend does not read its four bands")
	assert_eq(LeagueTableChrome.labels_for(["promotion", "playoff", "playout", "relegation"], true),
		["UP", "PLO", "PLY", "REL"], "the phone legend captions are wrong")
	assert_eq(LeagueTableChrome.bands_for(LeagueRules.template("BL")),
		["ucl", "uel", "uecl", "relegation"], "the Bundesliga legend changed")


func test_the_pair_builds_two_full_calendars() -> void:
	var current := _fresh()
	assert_eq(current.save.competition_ids(), ITALIAN, "the save lost a tier")
	assert_eq(int(current.state()["total"]), 760, "the Italian pair is not two full calendars")
	for cid in ITALIAN:
		assert_eq(current.record.fixtures.all(-1, str(cid)).size(), 380,
			"%s did not build its double round robin" % cid)
		assert_eq(current.record.standings.table(str(cid)).size(), 20,
			"%s table is the wrong size" % cid)
		assert_eq(int(current.rules_by[str(cid)]["matchdays"]), 38,
			"%s matchday count is wrong" % cid)
	current.close()


func test_the_bracket_is_the_italian_six() -> void:
	var current := _fresh()
	var bracket := LeaguePlayoffs.build(current, "SB")
	assert_false(bracket.is_empty(), "a finished Serie B has no bracket")
	assert_eq(str(bracket["format"]), "serie_b_six", "Serie B is not on its own bracket")
	assert_false(bool(bracket.get("skipped", false)), "a 14-point gap did not apply")
	var table := current.record.standings.table("SB")
	var seeds: Array = []
	for i in range(2, 8):
		seeds.append(str((table[i] as Dictionary)["club_id"]))
	var rounds: Array = bracket["rounds"]
	assert_eq(rounds.size(), 3, "the Italian bracket is not three rounds")
	assert_eq(str(rounds[0]["name"]), "PRELIMINARIES", "the first round is not the preliminaries")
	var prelims: Array = rounds[0]["ties"]
	assert_eq(str(prelims[0]["home"]), seeds[2], "the first preliminary is not 5 v 8")
	assert_eq(str(prelims[0]["away"]), seeds[5], "the first preliminary is not 5 v 8")
	assert_eq(str(prelims[1]["home"]), seeds[3], "the second preliminary is not 6 v 7")
	assert_eq(str(prelims[1]["away"]), seeds[4], "the second preliminary is not 6 v 7")
	for i in range(2):
		var tie: Dictionary = prelims[i]
		assert_eq((tie["legs"] as Array).size(), 1, "a preliminary is not one leg")
		assert_eq(str((tie["legs"] as Array)[0]["home"]), str(tie["home"]),
			"a preliminary is not at the higher place")
		assert_true(str(tie["decided_by"]) in ["ninety", "extra time", "higher place"],
			"a preliminary was settled by penalties")
	var semis: Array = rounds[1]["ties"]
	assert_eq(str(semis[0]["home"]), seeds[0], "the first semi-final is not the third place")
	assert_eq(str(semis[1]["home"]), seeds[1], "the second semi-final is not the fourth place")
	assert_eq(str(semis[0]["away"]), str(prelims[1]["winner_club_id"]),
		"the third place does not meet the 6 v 7 winner")
	assert_eq(str(semis[1]["away"]), str(prelims[0]["winner_club_id"]),
		"the fourth place does not meet the 5 v 8 winner")
	for tie in semis:
		var legs: Array = (tie as Dictionary)["legs"]
		assert_eq(legs.size(), 2, "a semi-final is not two legs")
		assert_eq(str(legs[1]["home"]), str((tie as Dictionary)["home"]),
			"the higher place does not host the second leg")
		assert_true(str((tie as Dictionary)["decided_by"]) in [
			"points", "goal difference", "higher place"], "a semi-final went to penalties")
	var final: Dictionary = (rounds[2]["ties"] as Array)[0]
	assert_eq((final["legs"] as Array).size(), 2, "the final is not two legs")
	assert_eq(str(final["legs"][1]["home"]), str(final["home"]),
		"the higher place does not host the final's second leg")
	assert_true(str(bracket["winner_club_id"]) != "", "the bracket named no winner")
	assert_eq(str(bracket["winner_club_id"]), str(final["winner_club_id"]),
		"the bracket's winner is not the final's")
	current.close()


func test_one_seed_settles_one_bracket() -> void:
	var again := _fresh()
	var bracket := LeaguePlayoffs.build(again, "SB")
	again.close()
	assert_eq(str(bracket["winner_club_id"]), str(expected_bracket["winner_club_id"]),
		"the bracket's winner moved between runs of one seed")
	assert_eq(bracket["rounds"], expected_bracket["rounds"], "the bracket differs for one seed")


func test_the_playout_is_sixteenth_against_seventeenth() -> void:
	var current := _fresh()
	var rules := current.save.rules_for("SB")
	var tie := LeagueSerieB.playout(current, "SB", rules)
	assert_false(tie.is_empty(), "a finished Serie B has no play-out")
	assert_eq(int(tie["high_position"]), 16, "the play-out is not the sixteenth place")
	assert_eq(int(tie["low_position"]), 17, "the play-out is not the seventeenth place")
	var legs: Array = tie["legs"]
	assert_eq(legs.size(), 2, "the play-out is not two legs")
	assert_eq(str(legs[0]["home"]), str(tie["low_club_id"]),
		"the first leg is not at the seventeenth place")
	assert_eq(str(legs[1]["home"]), str(tie["high_club_id"]),
		"the return is not at the sixteenth place")
	assert_true(str(tie["winner_club_id"]) != "", "the play-out named no survivor")
	assert_true(str(tie["relegated_club_id"]) != str(tie["winner_club_id"]),
		"the play-out named one club twice")
	assert_eq(LeaguePyramid.competition_of(str(tie["relegated_club_id"])), "SB",
		"a play-out loser left Serie B with no Serie C to go to")
	assert_eq(str(tie["relegated_club_id"]), str(expected_playout["relegated_club_id"]),
		"the play-out moved between runs of one seed")
	current.close()


func test_the_playout_marks_one_more_relegated_club() -> void:
	var current := _fresh()
	var summary := current.summary()
	var ties: Dictionary = summary.get("playout", {})
	assert_true(ties.has("SB"), "the podium lost the play-out")
	var tie: Dictionary = ties["SB"]
	var sections: Array = summary["competitions"]
	assert_eq(sections.size(), 2, "the podium is not one section per Italian tier")
	var lower: Dictionary = sections[1]
	assert_eq(str(lower["id"]), "SB", "the podium lost Serie B")
	var relegated: Array = lower["relegated"]
	assert_eq(relegated.size(), 4, "the play-out's loser is not a fourth RELEGATED club")
	var found := false
	for row in relegated:
		if str((row as Dictionary)["club_id"]) == str(tie["relegated_club_id"]):
			found = true
	assert_true(found, "the play-out's loser is missing from the relegated block")
	var top: Dictionary = sections[0]
	assert_eq(str(top["id"]), "SA", "the podium lost Serie A")
	assert_eq((top["europe"] as Array).size(), 6, "Serie A's Europe band is not six")
	assert_eq((top["relegated"] as Array).size(), 3, "Serie A drops three, not four")
	assert_eq((lower["europe"] as Array).size(), 0, "Serie B was given a European band")
	current.close()


func test_the_swap_promotes_three_and_drops_three() -> void:
	var current := _fresh()
	var summary := current.summary()
	var pyramid: Dictionary = summary.get("pyramid", {})
	assert_true(bool(pyramid.get("applied", false)), "the Italian swap was never applied")
	var links: Array = pyramid.get("links", [])
	assert_eq(links.size(), 1, "the Italian pair is not one link")
	var link: Dictionary = links[0]
	assert_eq(str(link["top"]), "SA", "the link's top tier is not Serie A")
	assert_eq(str(link["bottom"]), "SB", "the link's bottom tier is not Serie B")
	assert_eq((link["to_top"] as Array).size(), 3, "Italy promotes fewer than three")
	assert_eq((link["to_bottom"] as Array).size(), 3, "Serie A drops fewer than three")
	for club_id in link["to_top"]:
		assert_eq(LeaguePyramid.competition_of(str(club_id)), "SA", "%s did not go up" % club_id)
	for club_id in link["to_bottom"]:
		assert_eq(LeaguePyramid.competition_of(str(club_id)), "SB", "%s did not go down" % club_id)
	assert_eq(int(PLCompetitions.clubs("SA")), 20, "Serie A changed size in the swap")
	assert_eq(int(PLCompetitions.clubs("SB")), 20, "Serie B changed size in the swap")
	assert_eq(current.save.status(), "complete", "the save is not marked complete")
	var again := current.summary()
	var again_links: Array = (again.get("pyramid", {}) as Dictionary).get("links", [])
	assert_eq(again_links.size(), links.size(), "a second summary settled a different swap")
	assert_eq(str((again_links[0] as Dictionary)["to_top"]), str(link["to_top"]),
		"a second summary settled a different swap")
	assert_eq(str((again_links[0] as Dictionary)["to_bottom"]), str(link["to_bottom"]),
		"a second summary settled a different drop")
	assert_eq(int(PLCompetitions.clubs("SA")), 20, "the swap applied twice")
	current.close()


func test_the_gap_of_fourteen_skips_the_bracket() -> void:
	var current := _fresh()
	var table := current.record.standings.table("SB")
	var rules := current.save.rules_for("SB")
	_set_points(table, [100, 96, 90, 76, 60, 55, 50, 46])
	assert_false(LeagueSerieB.skips(current, "SB", rules), "a 14-point gap skipped the bracket")
	var bracket := LeaguePlayoffs.build(current, "SB")
	assert_false(bool(bracket.get("skipped", false)), "a 14-point gap skipped the bracket")
	_set_points(table, [100, 96, 90, 75, 60, 55, 50, 46])
	assert_true(LeagueSerieB.skips(current, "SB", rules), "a 15-point gap did not skip the bracket")
	var skipped := LeaguePlayoffs.build(current, "SB")
	assert_true(bool(skipped.get("skipped", false)), "the skipped bracket was not stamped")
	assert_eq((skipped["rounds"] as Array).size(), 0, "a skipped bracket still played rounds")
	assert_eq(str(skipped["winner_club_id"]), str(table[2]["club_id"]),
		"the skipped bracket did not promote the third place")
	var movers := LeaguePyramid.movers(current, {"SB": skipped})
	var up: Array = (movers["links"] as Array)[0]["to_top"]
	assert_eq(up.size(), 3, "the skipped bracket did not promote three")
	assert_true(up.has(str(table[2]["club_id"])), "the third place was not promoted by the skip")
	current.close()
	_fresh().close()


func test_a_lone_tier_plays_no_italian_tie() -> void:
	var solo := LeagueSeason.create("Serie B Alone", "generated", "fixture_days", 12, ["SA"])
	assert_not_null(solo, "the lone Serie A season was not created")
	_mark_finished(solo)
	assert_true(LeaguePlayoffs.build(solo, "SB").is_empty(),
		"Serie B played a bracket without Serie A above it")
	assert_true(LeagueSerieB.playout(solo, "SB", solo.save.rules_for("SB")).is_empty(),
		"Serie B played a play-out it was not running")
	solo.close()
	_fresh().close()


func _set_points(table: Array, targets: Array) -> void:
	for i in range(table.size()):
		var row: Dictionary = table[i]
		var points: int = int(targets[i]) if i < targets.size() else mini(int(row["points"]), 40)
		PLDatabase.execute("UPDATE league_table SET points = ? WHERE club_id = ?;",
			[points, str(row["club_id"])])

func test_the_season_without_italy_settles_no_playout() -> void:
	var plain := LeagueSeason.create("Plain", "generated", "fixture_days", 9, ["PL"])
	assert_not_null(plain, "the plain season was not created")
	_mark_finished(plain)
	var summary := plain.summary()
	assert_false(summary.has("playout"), "a Premier League season grew a play-out")
	assert_eq((summary.get("competitions", []) as Array).size(), 1, "the plain podium lost its league")
	plain.close()
	_fresh().close()


func test_the_helpers_settle_every_kind_of_tie() -> void:
	var current := _fresh()
	var rules := current.save.rules_for("SB")
	var table := current.record.standings.table("SB")
	var high := {"club_id": str(table[2]["club_id"]), "name": str(table[2]["club_name"]),
		"position": 3, "points": 60}
	var low := {"club_id": str(table[5]["club_id"]), "name": str(table[5]["club_name"]),
		"position": 6, "points": 50}
	var prelim := {}
	for i in range(30):
		var tie := LeagueSerieB._preliminary(current, "SB", "P%d" % i, high, low)
		prelim[str(tie["decided_by"])] = true
	assert_true(prelim.has("ninety"), "a preliminary never settled in ninety")
	assert_true(prelim.has("extra time"), "no preliminary went to extra time")
	var legs := {}
	for i in range(40):
		var tie := LeagueSerieB._two_legs(current, "SB", rules, "T%d" % i, high, low, i % 2 == 0)
		legs[str(tie["decided_by"])] = true
	assert_true(legs.has("points"), "no two-leg tie settled on points")
	assert_true(legs.has("goal difference") or legs.has("higher place"),
		"no two-leg tie settled past points")
	assert_true(legs.has("penalties") or legs.has("extra time"),
		"no level two-leg tie reached extra time")
	var pens := LeagueSerieB._tie_dict("FINAL", high, low, [], 3, 3, true, "penalties",
		str(high["club_id"]), Vector2i(4, 2))
	assert_true(str(pens["text"]).contains("pens"), "a shootout has no reading")
	var place := LeagueSerieB._tie_dict("FINAL", high, low, [], 2, 2, false, "higher place",
		str(high["club_id"]), Vector2i(-1, -1))
	assert_true(str(place["text"]).contains("higher place"), "a place win has no reading")
	current.close()


func test_the_italian_readings_refuse_what_they_cannot_settle() -> void:
	assert_true(LeagueSerieB.format(LeagueRules.template("SB")),
		"Serie B's format is not recognised")
	assert_false(LeagueSerieB.format(LeagueRules.template("SA")),
		"Serie A was read as the Serie B format")
	var plain := LeagueRules.template("SB")
	plain["promotion_skip_gap"] = 0
	assert_false(LeagueSerieB.skips(null, "SB", plain), "a missing season skipped the bracket")
	assert_true(LeagueSerieB.playout(null, "SB", plain).is_empty(),
		"a missing season played a play-out")
	assert_true(LeagueSerieB.playouts(null).is_empty(), "a missing season listed a play-out")
	var open := _fresh()
	assert_false(LeagueSerieB.skips(open, "SB", plain), "a zero gap skipped the bracket")
	assert_true(LeagueSerieB.playout(open, "PL", plain).is_empty(),
		"a competition outside the save played a play-out")
	var none := plain.duplicate(true)
	none["playout_places"] = 0
	assert_true(LeagueSerieB.playout(open, "SB", none).is_empty(),
		"a tier with no play-out places played one")
	var thin := open.save.rules_for("SB").duplicate(true)
	thin["promotion_playoff_places"] = 2
	LeagueRules.write("SB", thin)
	open.save.rules_by = LeagueRules.read_all()
	assert_true(LeaguePlayoffs.build(open, "SB").is_empty(), "a two-team bracket was played")
	var deep := open.save.rules_for("SB").duplicate(true)
	deep["relegation_places"] = 25
	LeagueRules.write("SB", deep)
	open.save.rules_by = LeagueRules.read_all()
	assert_true(LeagueSerieB.playout(open, "SB", deep).is_empty(),
		"a play-out fell off the bottom of the table")
	open.close()
	var early := LeagueSeason.create("Early", "generated", "fixture_days", 3, ["SA", "SB"])
	assert_not_null(early, "the early season was not created")
	assert_true(LeagueSerieB.playout(early, "SB", plain).is_empty(),
		"an unfinished season played a play-out")
	early.close()
	_fresh().close()


func test_the_ui_names_the_playout() -> void:
	assert_eq(LeagueChrome.zone_color("playout"), Color(0.86, 0.50, 0.36),
		"the play-out band has no colour")
	assert_eq(LeagueTableChrome.labels_for(["playout"], false), ["PLAY-OUT"],
		"the wide legend lost the play-out")
	var sheet := LeaguePodiumSheet.new()
	var summary := {"playoffs": {"SB": {"text": "x"}}, "playout": {"SB": {"text": "y"}},
		"competitions": [{"id": "SB", "rules": LeagueRules.template("SB"), "europe": [],
			"relegated": [], "table": [], "champion": {"club": "a", "points": 1},
			"runner_up": {"club": "b", "points": 2}}]}
	var with_out := sheet.frame_height({"summary": summary})
	summary.erase("playout")
	var without := sheet.frame_height({"summary": summary})
	assert_eq(with_out - without, 22.0, "the podium did not make room for the play-out")
