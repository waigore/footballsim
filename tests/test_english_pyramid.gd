extends GdToolsTest

## The English pyramid (#258/#260): five linked tiers in one save, the 2026/27
## promotion play-offs, and the membership swap that follows them. The suite
## builds finished seasons by hand (every fixture given a result, as the clock
## would leave them) so it can read the brackets and the swap without playing a
## 46-round calendar through the model.

var SAVE_DIR := TestScratch.dir("saves_test_english_pyramid")
var CACHE_DIR := TestScratch.dir("cache_test_english_pyramid")
const SEED := 7301
const ENGLISH := ["PL", "CH", "L1", "L2", "NL"]

var season: LeagueSeason = null
var slug := ""

func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	_clean()
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	season = _finished("English Pyramid", SEED, ENGLISH)
	slug = season.save.slug if season != null else ""

## The shared pyramid season, rebound when another test created a season of its
## own (creating one closes whatever was open, as the game does). Reopening the
## save is the cheap path: a finished save keeps its swap and does not roll on.
func _current() -> LeagueSeason:
	if season == null or LeagueSeason.active != season:
		season = LeagueSeason.open(slug)
	return season

func after_all() -> void:
	if season != null:
		season.close()
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

## A season whose calendar is played out: every fixture given a result from the
## two club ids (so no model run is needed) and the tables rebuilt. No second
## season starts — the save is marked complete, as the clock leaves it.
func _finished(name: String, seed: int, comps: Array) -> LeagueSeason:
	var built := LeagueSeason.create(name, "generated", "fixture_days", seed, comps)
	if built == null:
		return null
	for row in PLDatabase.rows(
			"SELECT id, home_club_id, away_club_id FROM league_fixture;"):
		var home := str(row["home_club_id"])
		var away := str(row["away_club_id"])
		var hg := 2 if home < away else 0
		var ag := 2 if away < home else 0
		PLDatabase.execute(
			"UPDATE league_fixture SET status = 'played', home_goals = ?, away_goals = ? "
			+ "WHERE id = ?;", [hg, ag, str(row["id"])])
	built.record.standings.recompute()
	if built.record.fixtures.unplayed() == 0:
		built.save.set_status("complete")
	return built

# ------------------------------------------------------------------- seed ---

func test_the_seed_ships_the_english_pyramid() -> void:
	for cid in ENGLISH:
		assert_true(PLCompetitions.exists(cid), "the seed carries no %s" % cid)
		assert_eq(int(PLCompetitions.clubs(cid)), 24 if cid != "PL" else 20,
			"%s shipped the wrong club set" % cid)
		for club_id in TeamData.team_ids(cid):
			var team := TeamData.get_team(club_id)
			assert_eq((team["starters"] as Array).size(), 11, "%s has no XI" % club_id)
			assert_true(str(team.get("stadium", "")) != "", "%s has no ground" % club_id)
	assert_eq(TeamData.team_ids("NL").size(), 24, "the National League is not twenty-four clubs")

func test_every_competition_has_its_own_rules_row() -> void:
	var ch := LeagueRules.template("CH")
	var nl := LeagueRules.template("NL")
	assert_eq(int(ch["clubs"]), 24, "the Championship is not 24 clubs")
	assert_eq(int(ch["matchdays"]), 46, "the Championship is not 46 matchdays")
	assert_eq(int(ch["relegation_places"]), 3, "the Championship drops three")
	assert_eq(str(ch["playoff_format"]), "six_two_leg", "the Championship bracket is not the six-team one")
	assert_eq(int(nl["promotion_places"]), 1, "the National League promotes one directly")
	assert_eq(int(nl["relegation_places"]), 4, "the National League reads four RELEGATED")
	assert_eq(str(nl["playoff_format"]), "six_one_leg", "the National League bracket is not the one-leg one")

func test_the_bands_read_each_tier() -> void:
	var ch := LeagueRules.template("CH")
	assert_eq(LeagueRules.zone(1, ch), "promotion", "the Championship winner does not go up")
	assert_eq(LeagueRules.zone(2, ch), "promotion", "the Championship runner-up does not go up")
	assert_eq(LeagueRules.zone(3, ch), "playoff", "the Championship's third is not in the play-offs")
	assert_eq(LeagueRules.zone(8, ch), "playoff", "the Championship's eighth is not in the play-offs")
	assert_eq(LeagueRules.zone(9, ch), "", "a mid-table Championship place wears a band")
	assert_eq(LeagueRules.zone(22, ch), "relegation", "the Championship's 22nd does not go down")
	var l2 := LeagueRules.template("L2")
	assert_eq(LeagueRules.zone(3, l2), "promotion", "League Two promotes only two")
	assert_eq(LeagueRules.zone(4, l2), "playoff", "League Two's fourth is not in the play-offs")
	assert_eq(LeagueRules.zone(7, l2), "playoff", "League Two's seventh is not in the play-offs")
	assert_eq(LeagueRules.zone(23, l2), "relegation", "League Two's 23rd does not go down")
	assert_eq(LeagueRules.zone(20, LeagueRules.template("PL")), "relegation",
		"the Premier League's drop changed")

func test_the_tier_graph_is_one_chain_per_country() -> void:
	assert_eq(LeagueTiers.order(), ["PL", "CH", "L1", "L2", "NL", "LL", "BL", "BL2"],
		"the published competition order moved")
	assert_eq(LeagueSeason.COMPETITION_ORDER, LeagueTiers.order(),
		"the season's fixture order and the tier graph disagree")
	assert_eq(LeagueTiers.above("L2"), "L1", "League Two's tier above is wrong")
	assert_eq(LeagueTiers.below("CH"), "L1", "the Championship's tier below is wrong")
	assert_eq(LeagueTiers.above("PL"), "", "the Premier League has a tier above it")
	assert_eq(LeagueTiers.below("NL"), "", "the National League has a tier below it")
	assert_eq(LeagueTiers.country_of("CH"), "England", "the Championship is not English")
	assert_eq(LeagueTiers.close_up(["CH"]), ["PL", "CH"], "a lower tier did not close over its chain")
	var pairs := LeagueTiers.pairs(["PL", "CH", "L1"])
	assert_eq(pairs.size(), 2, "the active pairs are not the adjacent active tiers")
	assert_eq(pairs[0], ["PL", "CH"], "the first pair is not the top of the chain")

func test_the_pick_cascades_along_the_graph() -> void:
	assert_eq(LeagueTiers.cascading_on(["PL"], "L2"), ["PL", "CH", "L1", "L2"],
		"a lower tier did not bring the chain above it")
	assert_eq(LeagueTiers.cascading_off(["PL", "CH", "L1", "L2", "NL"], "CH"), ["PL"],
		"turning a tier off did not clear the tiers below it")
	assert_eq(LeagueTiers.cascading_off(["LL"], "LL"), [], "Spain did not clear")
	assert_eq(LeagueTiers.cascading_on(["LL"], "NOPE"), ["LL", "NOPE"],
		"an unknown competition was dropped from the pick")
	assert_eq(LeagueTiers.above("NOPE"), "", "an unknown competition has a tier above it")
	assert_eq(LeagueTiers.below("NOPE"), "", "an unknown competition has a tier below it")
	assert_eq(LeagueTiers.country_of("NOPE"), "", "an unknown competition has a country")
	assert_eq(LeaguePyramid.competition_of("NOPE"), "", "an unknown club has a competition")

func test_the_table_legend_reads_the_leagues_own_bands() -> void:
	var top := LeagueTableChrome.bands_for(LeagueRules.template("PL"))
	assert_eq(top, LeagueTableChrome.BANDS, "a top flight lost its European legend")
	var lower := LeagueTableChrome.bands_for(LeagueRules.template("CH"))
	assert_eq(lower, ["promotion", "playoff", "relegation"],
		"the Championship legend does not read promotion and the play-offs")
	assert_eq(LeagueTableChrome.labels_for(lower, true), ["UP", "PLO", "REL"],
		"the phone legend captions are wrong")
	assert_eq(LeagueTableChrome.labels_for(lower, false), ["UP", "PLO", "RELEGATION"],
		"the wide legend captions are wrong")
	var straight := LeagueTableChrome.bands_for({"promotion_places": 2, "promotion_playoff_places": 0})
	assert_eq(straight, ["promotion", "relegation"],
		"a tier with no play-off band still painted one")

# ----------------------------------------------------------------- clock ---

func test_a_five_tier_save_builds_every_calendar() -> void:
	var full := LeagueSeason.create("Pyramid Build", "generated", "fixture_days", 99, ENGLISH)
	assert_not_null(full, "the five-tier save did not build")
	assert_eq(full.save.competition_ids(), ENGLISH, "the save lost a tier")
	for cid in ENGLISH:
		var fixtures := full.record.fixtures.unplayed(str(cid))
		var per_tier := 380 if cid == "PL" else 552
		assert_eq(fixtures, per_tier, "%s did not build its double round robin" % cid)
		assert_eq(full.record.standings.table(str(cid)).size(), 20 if cid == "PL" else 24,
			"%s table is the wrong size" % cid)
	full.close()

# --------------------------------------------------------------- brackets ---

func test_the_bracket_draws_the_places_under_promotion() -> void:
	var current := _current()
	var bracket := LeaguePlayoffs.build(current, "CH")
	assert_false(bracket.is_empty(), "a finished pyramid has no Championship bracket")
	assert_eq(str(bracket["format"]), "six_two_leg", "the Championship bracket changed shape")
	var rounds: Array = bracket["rounds"]
	assert_eq(rounds.size(), 3, "the six-team bracket is not three rounds")
	var table := current.record.standings.table("CH")
	var seeds: Array = []
	for i in range(2, 8):
		seeds.append(str((table[i] as Dictionary)["club_id"]))
	var elims: Array = rounds[0]["ties"]
	assert_eq(str(elims[0]["home"]), seeds[2], "the first eliminator is not 5 v 8")
	assert_eq(str(elims[0]["away"]), seeds[5], "the first eliminator is not 5 v 8")
	assert_eq(str(elims[1]["home"]), seeds[3], "the second eliminator is not 6 v 7")
	var semis: Array = rounds[1]["ties"]
	assert_eq(str(semis[0]["home"]), seeds[0], "the first semi-final is not the third place")
	assert_eq(str(semis[1]["home"]), seeds[1], "the second semi-final is not the fourth place")
	assert_eq((semis[0]["legs"] as Array).size(), 2, "the Championship semis are not two legs")
	assert_eq(str(semis[0]["legs"][1]["home"]), seeds[0], "the higher place does not host the second leg")
	var final_tie: Dictionary = (rounds[2]["ties"] as Array)[0]
	assert_eq((final_tie["legs"] as Array).size(), 1, "the final is not one match")
	assert_true(str(bracket["winner_club_id"]) != "", "the bracket named no winner")

func test_each_tier_plays_its_own_bracket() -> void:
	var current := _current()
	var l1 := LeaguePlayoffs.build(current, "L1")
	assert_eq(str(l1["format"]), "four_two_leg", "League One's bracket changed shape")
	assert_eq((l1["rounds"] as Array).size(), 2, "the four-team bracket is not two rounds")
	assert_eq(((l1["rounds"] as Array)[0]["ties"] as Array).size(), 2, "League One lost a semi-final")
	assert_eq(str(((l1["rounds"] as Array)[0]["ties"] as Array)[0]["home"]),
		str((current.record.standings.table("L1")[2] as Dictionary)["club_id"]),
		"League One's first semi-final is not the third place")
	var nl := LeaguePlayoffs.build(current, "NL")
	assert_eq(str(nl["format"]), "six_one_leg", "the National League bracket changed shape")
	for round in (nl["rounds"] as Array):
		for tie in (round["ties"] as Array):
			assert_eq((tie["legs"] as Array).size(), 1, "a National League round is not one leg")

func test_a_bracket_without_its_tier_above_is_not_played() -> void:
	var pair := _finished("Two Tiers", 42, ["PL", "CH"])
	assert_not_null(pair, "the two-tier save did not build")
	assert_false(LeaguePlayoffs.build(pair, "CH").is_empty(),
		"the Championship's bracket needs the Premier League above it")
	assert_true(LeaguePlayoffs.build(pair, "L1").is_empty(),
		"League One played a bracket with no tier above it")
	pair.close()

func test_one_seed_settles_one_bracket() -> void:
	var a := _finished("Bracket A", SEED, ["PL", "CH"])
	var bracket_a := LeaguePlayoffs.build(a, "CH")
	a.close()
	var b := _finished("Bracket B", SEED, ["PL", "CH"])
	var bracket_b := LeaguePlayoffs.build(b, "CH")
	b.close()
	assert_eq(str(bracket_a["winner_club_id"]), str(bracket_b["winner_club_id"]),
		"the bracket's winner moved between runs of one seed")
	assert_eq(bracket_a["rounds"], bracket_b["rounds"], "the bracket differs for one seed")

func test_a_level_tie_goes_to_extra_time_and_penalties() -> void:
	var first := LeagueShootout.settle(9001, "CH-MID", "CH-STK")
	var again := LeagueShootout.settle(9001, "CH-MID", "CH-STK")
	assert_eq(first, again, "the shootout is not deterministic for a seed")
	assert_ne(first.x, first.y, "a shootout finished level")

# ------------------------------------------------------------------ swap ---

func test_the_swap_keeps_every_tier_its_size() -> void:
	var current := _current()
	var summary := current.summary()
	assert_false(summary.is_empty(), "the finished pyramid has no podium")
	assert_false((summary.get("playoffs", {}) as Dictionary).is_empty(),
		"the podium lost the play-offs")
	var pyramid: Dictionary = summary.get("pyramid", {})
	assert_true(bool(pyramid.get("applied", false)), "the English swap was never applied")
	var sizes := {"PL": 20, "CH": 24, "L1": 24, "L2": 24, "NL": 24}
	for cid in sizes.keys():
		assert_eq(int(PLCompetitions.clubs(str(cid))), int(sizes[cid]),
			"%s changed its club count in the swap" % cid)
	assert_eq(current.save.status(), "complete", "the save is not marked complete (a second season?)")

func test_the_playoff_winner_goes_up_and_the_drop_goes_down() -> void:
	var summary := _current().summary()
	var brackets: Dictionary = summary.get("playoffs", {})
	for cid in brackets.keys():
		var winner := str((brackets[cid] as Dictionary)["winner_club_id"])
		assert_eq(LeaguePyramid.competition_of(winner), LeagueTiers.above(str(cid)),
			"%s's play-off winner did not go up" % cid)
	var links: Array = (summary.get("pyramid", {}) as Dictionary).get("links", [])
	assert_gte(links.size(), 3, "the pyramid swapped fewer pairs than it plays")
	for link in links:
		for club_id in link["to_bottom"]:
			assert_eq(LeaguePyramid.competition_of(str(club_id)), str(link["bottom"]),
				"%s did not go down" % club_id)
		for club_id in link["to_top"]:
			assert_eq(LeaguePyramid.competition_of(str(club_id)), str(link["top"]),
				"%s did not go up" % club_id)

func test_the_national_league_drop_stays_put() -> void:
	# The chain ends at the National League: its bottom four read RELEGATED, and
	# with no tier below there is nowhere to move them.
	var below := LeagueRules.template("NL")
	assert_eq(int(below["relegation_places"]), 4, "the National League drops four")
	assert_eq(LeagueTiers.below("NL"), "", "the National League gained a tier below it")
	var table := _current().record.standings.table("NL")
	for i in range(table.size() - 4, table.size()):
		var club_id := str((table[i] as Dictionary)["club_id"])
		assert_eq(LeaguePyramid.competition_of(club_id), "NL",
			"a National League drop left the competition")

func test_the_swap_is_applied_only_once() -> void:
	var before: Array = []
	for cid in ENGLISH:
		before.append(PLCompetitions.clubs(str(cid)))
	var current := _current()
	var summary := current.summary()
	assert_true((summary.get("pyramid", {}) as Dictionary).has("links"),
		"the podium lost the swap")
	var again := current.summary()
	assert_eq(str((again.get("playoffs", {}) as Dictionary).get("CH", {}).get("winner_club_id", "")),
		str((summary.get("playoffs", {}) as Dictionary).get("CH", {}).get("winner_club_id", "")),
		"a second summary settled a different bracket")
	var after: Array = []
	for cid in ENGLISH:
		after.append(PLCompetitions.clubs(str(cid)))
	assert_eq(after, before, "the club counts moved on a re-apply")
	assert_true(str(current.save.meta.get("linked_end", "")) != "",
		"the end of the season was not stamped in the save")
	var again_apply: Dictionary = summary.get("pyramid", {})
	assert_true(LeaguePyramid.apply(current, again_apply),
		"re-applying the stored swap reported failure")
	assert_false(bool(again_apply.get("applied", true)),
		"re-applying the stored swap moved clubs again")

func test_a_reopened_season_reads_the_same_end() -> void:
	var before := _current().summary()
	var reopened := LeagueSeason.open(slug)
	assert_not_null(reopened, "the finished pyramid did not reopen")
	var after := reopened.summary()
	assert_eq(str((after.get("playoffs", {}) as Dictionary).get("CH", {}).get("winner_club_id", "")),
		str((before.get("playoffs", {}) as Dictionary).get("CH", {}).get("winner_club_id", "")),
		"a reopened season settled a different play-off winner")
	season = reopened

func test_an_unplayed_calendar_settles_nothing() -> void:
	var fresh := LeagueSeason.create("Fresh Calendar", "generated", "fixture_days", 5, ["PL", "CH"])
	assert_not_null(fresh, "the fresh save did not build")
	assert_true(LeaguePlayoffs.build_all(fresh).is_empty(), "an unplayed calendar settled a bracket")
	assert_true(LeaguePyramid.movers(fresh, {}).is_empty(), "an empty bracket set swapped clubs")
	assert_false(LeaguePyramid.apply(fresh, {}), "an empty swap reported success")
	assert_true(LeaguePlayoffs.build(fresh, "PL").is_empty(), "the Premier League played a bracket")
	fresh.close()

func test_a_lone_tier_settles_nothing() -> void:
	var alone := _finished("Premier League Alone", 7, ["PL"])
	assert_not_null(alone, "the single-tier save did not build")
	var summary := alone.summary()
	assert_true((summary.get("playoffs", {}) as Dictionary).is_empty(),
		"a lone Premier League played a play-off")
	assert_true((summary.get("pyramid", {}) as Dictionary).is_empty(),
		"a lone Premier League swapped clubs")
	assert_eq(int(PLCompetitions.clubs("PL")), 20, "the Premier League lost clubs with nowhere to go")
	alone.close()

func test_a_club_finds_its_new_tier_in_the_encyclopedia() -> void:
	var summary := _current().summary()
	var links: Array = (summary.get("pyramid", {}) as Dictionary).get("links", [])
	assert_gte(links.size(), 1, "the swap promoted nobody")
	var promoted := str((links[0]["to_top"] as Array)[0])
	var page := WikiModel.page(WikiModel.TEAM, promoted)
	assert_true(_links_league(page, str(links[0]["top"])),
		"the promoted club's page does not link its new tier")

func _links_league(page: Dictionary, competition_id: String) -> bool:
	for block in page.get("blocks", []):
		for item in block.get("items", []):
			var target: Dictionary = item.get("target", {})
			if str(target.get("page", "")) != WikiModel.LEAGUE:
				continue
			if str(target.get("id", "")) == competition_id:
				return true
	return false
