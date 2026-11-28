extends GdToolsTest


class Host extends RefCounted:
	var season: LeagueSeason = null
	var cups := {"cup": "", "round": ""}
	var wizard: Dictionary = {"competitions": ["PL"], "cup_off": []}
	var touch := false
	var redraws := 0

	func refresh() -> void:
		redraws += 1


var SAVE_DIR := TestScratch.dir("saves_test_cups_ui")
var CACHE_DIR := TestScratch.dir("cache_test_cups_ui")
const SEED := 9091

var season: LeagueSeason = null
var host: Host = null

func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	TestScratch.clear(SAVE_DIR)
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	season = LeagueSeason.create("Cup UI", "generated", "fixture_days", SEED, ["PL"], true)

func after_all() -> void:
	if season != null:
		season.close()
	TestScratch.clear(SAVE_DIR)
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func before_each() -> void:
	host = Host.new()
	host.season = season
	host.cups = {"cup": "", "round": ""}

func _wizard(comp: Array, off: Array = []) -> Host:
	var w := Host.new()
	w.wizard = {"competitions": comp, "cup_off": off}
	return w

func test_the_wizard_switches_cups_on_with_the_country_league() -> void:
	assert_eq(LeagueWizardActions.countries(["PL"]), ["England"],
		"a Premier League pick does not offer England's cups")
	assert_eq(LeagueWizardActions.countries(["PL", "LL"]), ["England", "Spain"],
		"two countries did not offer both cup sets")
	assert_eq(LeagueWizardActions.countries(["PL", "LL"], ["England"]), ["Spain"],
		"a switched-off country kept its cups")

func test_the_toggle_drops_a_country_its_league_left_behind() -> void:
	var w := _wizard(["PL", "LL"])
	LeagueWizardActions.toggle_league(w, "PL")
	assert_eq(LeagueWizardActions.countries(LeagueWizardActions.selected(w)), ["Spain"],
		"England's cups survived the loss of the Premier League")
	LeagueWizardActions.toggle_league(w, "PL")
	assert_eq(LeagueWizardActions.countries(LeagueWizardActions.selected(w)),
		["England", "Spain"], "England's cups did not come back with the league")

func test_the_toggle_switches_one_country_off_and_on() -> void:
	var w := _wizard(["PL"])
	LeagueWizardActions.toggle_cups(w, "England")
	assert_eq(LeagueWizardActions.cups_on(w), [],
		"the cup toggle did not switch England off")
	LeagueWizardActions.toggle_cups(w, "England")
	assert_eq(LeagueWizardActions.cups_on(w), ["England"],
		"the cup toggle did not switch England back on")

func test_a_country_without_an_active_league_cannot_switch_its_cups_on() -> void:
	var w := _wizard(["PL"])
	LeagueWizardActions.toggle_cups(w, "Spain")
	assert_eq(LeagueWizardActions.cups_on(w), ["England"],
		"Spain switched its cups on with no Spanish league")
	assert_eq(LeagueWizardActions.countries(["PL"], ["England", "Spain"]), [],
		"a stale off entry survived the filter")

func test_the_wizard_draws_one_cup_toggle_per_country_with_cups() -> void:
	var sheet := LeagueStartSheet.new()
	for pair in [[Vector2(1600, 900), false], [Vector2(913, 411), true]]:
		var vp: Vector2 = pair[0]
		var touch: bool = pair[1]
		var rows: Array = []
		for item in sheet.wizard_layout(vp, {
				"competitions": ["PL"], "cup_off": [], "name": "", "touch": touch,
				"calendar_mode": "generated", "advance_mode": "fixture_days"}):
			if str(item["id"]).begins_with("wcup:"):
				rows.append(item)
		assert_eq(rows.size(), 3, "the wizard drew %d cup toggles, not three at %s"
			% [rows.size(), vp])
		if not touch:
			continue
		for item in rows:
			var rect: Rect2 = item["rect"]
			assert_gte(rect.size.y, 44.0, "the cup toggle is under a 44 tap target at %s" % vp)

func test_a_save_keeps_the_cup_countries_it_was_given() -> void:
	assert_eq(LeagueCup.cup_countries(season.save), ["England"],
		"the save did not record its cup countries")
	assert_eq(LeagueCup.active_ids(season.save), ["FAC", "EFLC", "CS"],
		"the restricted save ran the wrong cups")

func test_the_cup_hub_lists_one_card_per_competition() -> void:
	var cups := LeagueCupHub.competitions(season)
	assert_eq(cups.size(), 3, "the cup hub did not list every cup")
	var ids: Array = []
	for cup in cups:
		ids.append(str(cup["id"]))
		assert_true(str(cup["name"]) != "", "a cup card had no name")
		assert_true(str(cup["stage"]) != "", "a cup card had no stage")
		assert_gt(int(cup["alive"]), 0, "%s shows no clubs in it" % cup["id"])
	assert_eq(ids, ["FAC", "EFLC", "CS"], "the cup hub lost or reordered a cup")

func test_a_cup_page_reads_its_rounds_and_the_open_round() -> void:
	host.cups = {"cup": "FAC", "round": ""}
	var view := LeagueCupActions.view(host)
	assert_eq(str(view["cup_name"]), "FA Cup", "the cup page lost its name")
	assert_eq((view["rounds"] as Array).size(), 8, "the cup page lost a round")
	assert_eq(str(view["round"]), "R1", "the cup page did not open on the open round")
	assert_eq((view["ties"] as Array).size(), 40, "the open round is not forty ties")
	var tie: Dictionary = (view["ties"] as Array)[0]
	assert_true(str(tie.get("home_name", "")) != "", "a tie lost its home club name")

func test_the_round_rail_moves_the_page() -> void:
	host.cups = {"cup": "FAC", "round": ""}
	assert_true(LeagueCupActions.press(host, "round:R3"), "the round rail did not answer")
	assert_eq(str(host.cups["round"]), "R3", "the rail did not move to R3")
	var view := LeagueCupActions.view(host)
	assert_eq((view["ties"] as Array).size(), 0, "an undrawn round invented ties")

func test_back_walks_the_cup_history_before_the_screen_history() -> void:
	host.cups = {"cup": "FAC", "round": "R1"}
	assert_true(LeagueCupActions.back(host), "back left the round")
	assert_eq(str(host.cups["round"]), "", "back kept the round")
	assert_eq(str(host.cups["cup"]), "FAC", "back left the cup as well as the round")
	assert_true(LeagueCupActions.back(host), "back left the cup page")
	assert_eq(str(host.cups["cup"]), "", "back kept the cup page")
	assert_false(LeagueCupActions.back(host), "back invented a page below the cup hub")

func test_the_pose_reads_the_destination() -> void:
	assert_eq(LeagueScreen.MODE_CUPS, "cups", "the cups mode drifted")
	assert_eq(LeagueView.panel_reading(LeagueScreen.MODE_CUPS), "cups",
		"the panel does not light CUPS on the cups page")
	var pose: Array = LeagueView.pose(LeagueScreen.MODE_CUPS)
	assert_eq([str(pose[0]), str(pose[1]), str(pose[2]), str(pose[3])],
		["cups", "layout", "draw_body", "draw_chrome"], "the cups page lost its sheet")

func test_the_panel_carries_a_cups_row_with_its_own_icon() -> void:
	var row: Dictionary = {}
	for item in LeaguePanel.ITEMS:
		if str(item["id"]) == "nav:cups":
			row = item
	assert_false(row.is_empty(), "the panel has no CUPS row")
	assert_eq(str(row["pose"]), "cups", "the CUPS row opens the wrong pose")
	assert_true(FileAccess.file_exists("res://assets/ui/league/cups.png"),
		"the CUPS row has no icon")

func test_the_cup_sheet_lays_out_the_hub_and_the_cup_page() -> void:
	var sheet := LeagueCupSheet.new()
	for pair in [[Vector2(1600, 900), false], [Vector2(913, 411), true]]:
		var vp: Vector2 = pair[0]
		host.touch = bool(pair[1])
		host.cups = {"cup": "", "round": ""}
		var cards := 0
		for item in sheet.layout(vp, LeagueCupActions.view(host)):
			if str(item["kind"]) == "card":
				cards += 1
		assert_eq(cards, 3, "the hub did not draw a card per cup at %s" % vp)
		host.cups = {"cup": "FAC", "round": "R1"}
		var rounds := 0
		for item in sheet.layout(vp, LeagueCupActions.view(host)):
			if str(item["kind"]) == "round":
				rounds += 1
		assert_eq(rounds, 8, "the cup page drew no round rail at %s" % vp)

func test_every_cup_control_is_a_tap_target_on_a_phone() -> void:
	var sheet := LeagueCupSheet.new()
	var vp := Vector2(913, 411)
	host.touch = true
	host.cups = {"cup": "FAC", "round": "R1"}
	var view := LeagueCupActions.view(host)
	var seen := 0
	for item in sheet.layout(vp, view):
		var id := str(item.get("id", ""))
		if id == "":
			continue
		var rect: Rect2 = item["rect"]
		if id == "continue" or str(item["kind"]) == "round":
			assert_gte(rect.size.y, 44.0, "%s is under a 44 tap target" % id)
			seen += 1
	assert_gte(seen, 9, "the phone cup page laid no tap targets")

func test_a_save_without_cups_reads_an_empty_hub() -> void:
	var plain: LeagueSeason = LeagueSeason.create("No Cups", "generated", "fixture_days", SEED + 3,
		["PL"], false)
	assert_not_null(plain, "a cup-less season could not be created")
	assert_eq(LeagueCupHub.competitions(plain), [], "a cup-less season listed cups")
	plain.close()


func test_the_podium_carries_a_domestic_honours_block() -> void:
	var sheet := LeaguePodiumSheet.new()
	var section := {"id": "PL", "name": "Premier League", "rules": LeagueRules.defaults(),
		"champion": {"club": "Arsenal", "points": 90},
		"runner_up": {"club": "Liverpool", "points": 88},
		"europe": [], "relegated": [], "table": [], "top_scorers": []}
	var summary := {"competitions": [section], "cups": [
		{"id": "CS", "name": "Community Shield", "winner_name": "Arsenal",
			"runner_up_name": "Liverpool", "home_goals": 2, "away_goals": 1,
			"pens_home": -1, "pens_away": -1},
	]}
	var with_cups := sheet.frame_height({"summary": summary})
	var without := sheet.frame_height({"summary": {"competitions": [section]}})
	assert_gt(with_cups, without, "the podium did not reserve room for the cup honours")
