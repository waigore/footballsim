extends GdToolsTest


var CACHE_DIR := TestScratch.dir("cache_test_competitions")

func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func after_all() -> void:
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func test_the_seed_carries_every_competition() -> void:
	var all := PLCompetitions.all()
	assert_eq(all.size(), 10, "the shipped seed should carry the whole pyramid")
	var ids: Array = []
	for comp in all:
		ids.append(str(comp["id"]))
	assert_has(ids, "PL", "the seed's Premier League is missing")
	assert_has(ids, "LL", "the seed's La Liga is missing")
	assert_has(ids, "BL", "the seed's Bundesliga is missing")
	assert_has(ids, "BL2", "the seed's 2. Bundesliga is missing")
	assert_has(ids, "SA", "the seed's Serie A is missing")
	assert_has(ids, "SB", "the seed's Serie B is missing")
	assert_eq(int(PLCompetitions.clubs("SA")), 20, "the Serie A club count is wrong")
	assert_eq(int(PLCompetitions.clubs("SB")), 20, "the Serie B club count is wrong")

	for cid in ["CH", "L1", "L2", "NL"]:
		assert_has(ids, cid, "the seed's English tier %s is missing" % cid)
		assert_eq(int(PLCompetitions.clubs(cid)), 24, "%s club count is wrong" % cid)
	assert_eq(int(PLCompetitions.clubs("PL")), 20, "the Premier League club count is wrong")
	assert_eq(int(PLCompetitions.clubs("LL")), 20, "the La Liga club count is wrong")
	assert_eq(int(PLCompetitions.clubs("BL")), 18, "the Bundesliga club count is wrong")
	assert_eq(int(PLCompetitions.clubs("BL2")), 18, "the 2. Bundesliga club count is wrong")
	assert_eq(PLCompetitions.default_id(), "PL", "the default competition is not the seed's")
	assert_eq(str(PLCompetitions.one("PL").get("season_label", "")), "2026-27", "season label drifted")
	assert_true(PLCompetitions.one("NOPE").is_empty(), "an unknown competition resolved")

func test_the_shipped_hub_names_its_competition() -> void:
	var page := WikiModel.league_page()
	assert_eq(str(page["id"]), "PL", "the hub lost its competition id")
	assert_eq(str(page["title"]), "PREMIER LEAGUE", "the hub title is not the competition's")
	assert_true(str(page["subtitle"]).contains("20 CLUBS"), "the hub's club count is hard-coded")
	var index := _chips(page)
	assert_eq(index.size(), 10, "the competition index should hold every league")
	assert_true(_chip_target(index, "LA LIGA", "LL"),
		"the Premier League hub does not offer La Liga")
	assert_true(_chip_target(index, "BUNDESLIGA", "BL"),
		"the Premier League hub does not offer the Bundesliga")
	assert_true(_chip_target(index, "SERIE A", "SA"),
		"the Premier League hub does not offer Serie A")
	var badge := 0
	for item in index:
		if str(item.get("text", "")) == "PREMIER LEAGUE":
			badge += 1
			assert_true((item as Dictionary).get("target", {}).is_empty(),
				"the league you are reading should be a badge, not a door to itself")
	assert_eq(badge, 1, "the index lost the competition being read")

func test_a_club_and_its_players_point_at_their_competition() -> void:
	var club := WikiModel.page(WikiModel.TEAM, "ENG-MUN1")
	var targets := _targets(club)
	assert_true(_has_target(targets, WikiModel.LEAGUE, "PL"), "a club page does not link its league")
	var player := WikiModel.page(WikiModel.PLAYER, TestSquad.id_of("ENG-MUN1", "B. Fernandes"))
	var player_targets := _targets(player)
	assert_true(_has_target(player_targets, WikiModel.LEAGUE, "PL"),
		"a player page does not link its league")

func test_every_competition_gets_its_own_hub() -> void:
	var all := PLCompetitions.all()
	assert_eq(all.size(), 10, "the competitions were not all read")
	assert_eq(PLCompetitions.default_id(), "PL", "the default competition moved")
	assert_eq(PLCompetitions.clubs("LL"), 20, "La Liga's club count is wrong")

	var theirs := WikiModel.page(WikiModel.LEAGUE, "LL")
	assert_eq(str(theirs["title"]), "LA LIGA", "the second hub is not its own competition")
	assert_true(str(theirs["subtitle"]).contains("20 CLUBS"),
		"the second hub kept the first's club count")
	assert_eq(_rows_in(theirs, "LEAGUE TABLE"), 20, "the second hub shows the wrong table")
	var index := _chips(theirs)
	assert_eq(index.size(), 10, "the index does not list every competition")
	assert_true(_chip_target(index, "PREMIER LEAGUE", "PL"),
		"the second hub does not offer the Premier League")

	var german := WikiModel.page(WikiModel.LEAGUE, "BL")
	assert_eq(str(german["title"]), "BUNDESLIGA", "the German hub is not its own competition")
	assert_true(str(german["subtitle"]).contains("18 CLUBS"),
		"the German hub reads the wrong club count")
	assert_eq(_rows_in(german, "LEAGUE TABLE"), 18, "the German hub shows the wrong table")
	var lower := WikiModel.page(WikiModel.LEAGUE, "BL2")
	assert_eq(str(lower["title"]), "2. BUNDESLIGA", "the second German hub is missing")
	assert_eq(_rows_in(lower, "LEAGUE TABLE"), 18, "the second German hub shows the wrong table")

	var ours := WikiModel.page(WikiModel.LEAGUE, "PL")
	assert_eq(_rows_in(ours, "LEAGUE TABLE"), 20, "the Premier League hub picked up another league")
	assert_true(_chip_target(_chips(ours), "LA LIGA", "LL"),
		"the Premier League hub does not offer the second league")
	assert_true(_chip_target(_chips(ours), "2. BUNDESLIGA", "BL2"),
		"the Premier League hub does not offer the second German tier")

	var club := WikiModel.page(WikiModel.TEAM, "ESP-RMA1")
	assert_eq(str(club["title"]), "REAL MADRID", "the second league's club page is missing")
	var club_targets := _targets(club)
	assert_true(_has_target(club_targets, WikiModel.LEAGUE, "LL"),
		"the club does not link its own league")

func test_an_unknown_competition_is_rejected() -> void:
	assert_false(WikiModel.has_page(WikiModel.LEAGUE, "NOPE"), "a made-up competition resolved")
	assert_eq(WikiModel.label(WikiModel.LEAGUE, ""), "PREMIER LEAGUE",
		"the crumb numbers the wrong league")


func _chips(page: Dictionary) -> Array:
	for block in page.get("blocks", []):
		if str(block.get("k", "")) == "chips":
			return block.get("items", [])
	return []


func _chip_target(items: Array, text: String, id: String) -> bool:
	for item in items:
		if str(item.get("text", "")) != text:
			continue
		var target: Dictionary = item.get("target", {})
		return str(target.get("page", "")) == WikiModel.LEAGUE and str(target.get("id", "")) == id
	return false

func _has_target(targets: Array, page: String, id: String) -> bool:
	for target in targets:
		if str(target.get("page", "")) == page and str(target.get("id", "")) == id:
			return true
	return false

func _targets(page: Dictionary) -> Array:
	var out: Array = []
	for block in page.get("blocks", []):
		for row in block.get("rows", []):
			if row.has("target"):
				out.append(row["target"])
		for item in block.get("items", []):
			if item is Dictionary and item.has("target"):
				out.append(item["target"])
	return out

func _rows_in(page: Dictionary, section: String) -> int:
	var seen := false
	for block in page.get("blocks", []):
		if str(block.get("k")) == "section" and str(block.get("text")) == section:
			seen = true
			continue
		if seen and str(block.get("k")) == "table":
			return block["rows"].size()
		if seen and str(block.get("k")) == "section":
			return 0
		if seen and str(block.get("k")) != "table":
			return 0
	return 0
