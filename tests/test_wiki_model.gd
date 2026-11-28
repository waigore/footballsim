extends GdToolsTest


func before_all() -> void:
	PLDatabase.cache_dir = TestScratch.dir("cache_test_wiki")
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func after_all() -> void:
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func test_the_league_page_has_every_agreed_section() -> void:
	var page := WikiModel.page(WikiModel.LEAGUE, "")
	assert_eq(page["page"], "league", "wrong page kind")
	assert_eq(str(page["title"]), "PREMIER LEAGUE", "the league page lost its title")
	var kinds := _kinds(page)
	assert_has(kinds, "table", "no table on the league page")
	assert_has(kinds, "chips", "no club index on the league page")
	assert_gte(_rows_in(page, "LEAGUE TABLE"), 20, "the league table is short")
	assert_gte(_rows_in(page, "TOP SCORERS  ·  SNAPSHOT"), 5, "no player leaders")
	assert_gte(_rows_in(page, "LATEST RESULTS  ·  SNAPSHOT"), 5, "no recent results")
	assert_eq(PLRepository.shared().table("PL").size(), 20, "the table behind the page changed size")

func test_the_league_table_names_every_club_in_full() -> void:
	var page := WikiModel.page(WikiModel.LEAGUE, "")
	var names := _club_names("PL")
	var rows := _rows_of(page, "LEAGUE TABLE")
	assert_gte(rows.size(), 20, "the league table is short")
	for row in rows:
		var cell := str((row["cells"] as Array)[1])
		assert_true(names.has(cell), "the league table printed %s, not a club name" % cell)


func test_every_club_column_on_the_league_page_reads_a_full_name() -> void:
	var page := WikiModel.page(WikiModel.LEAGUE, "")
	var names := _club_names("PL")
	var checked := 0
	for block in page["blocks"]:
		if str(block["k"]) != "table":
			continue
		var cols: Array = block["cols"]
		var column := cols.find("CLUB")
		if column < 0:
			continue
		for row in block["rows"]:
			var cell := str((row["cells"] as Array)[column])
			assert_true(cell == "" or names.has(cell),
				"a club column printed %s, not a full club name" % cell)
			checked += 1
	assert_gt(checked, 20, "no club column was checked")


func _club_names(competition_id: String) -> Dictionary:
	var out := {}
	for club in PLRepository.shared().club_ids(competition_id):
		out[str(PLRepository.shared().club(str(club))["name"])] = true
	return out


func _rows_of(page: Dictionary, section: String) -> Array:
	var seen := false
	for block in page["blocks"]:
		var kind := str(block["k"])
		if kind == "section":
			if seen:
				return []
			seen = str(block["text"]) == section
			continue
		if seen and kind == "table":
			return block["rows"]
		if seen:
			return []
	return []


func test_every_link_on_the_league_page_resolves() -> void:
	var page := WikiModel.page(WikiModel.LEAGUE, "")
	for target in _targets(page):
		assert_true(WikiModel.has_page(str(target["page"]), str(target["id"])), "dead link %s" % str(target))

func test_the_club_page_shows_the_agreed_sections() -> void:
	var page := WikiModel.page(WikiModel.TEAM, "ENG-MUN1")
	assert_eq(str(page["title"]), "MANCHESTER UNITED", "the club page lost its title")
	var kinds := _kinds(page)
	assert_has(kinds, "kv", "no season figures on the club page")
	assert_has(kinds, "bars", "no tactical profile on the club page")
	assert_gte(_rows_in(page, "SQUAD"), 18, "the squad list is short")
	assert_gte(_rows_in(page, "RESULTS  ·  SNAPSHOT"), 5, "no club results")
	for target in _targets(page):
		assert_true(WikiModel.has_page(str(target["page"]), str(target["id"])), "dead link %s" % str(target))

func test_the_player_page_shows_ability_real_and_sim_numbers() -> void:
	var page := WikiModel.page(WikiModel.PLAYER, TestSquad.id_of("ENG-MUN1", "B. Fernandes"))
	assert_eq(str(page["title"]), "B. FERNANDES", "the player page lost its name")
	var kinds := _kinds(page)
	assert_has(kinds, "bars", "no attributes on the player page")
	var text := _flatten(page)
	assert_true(text.contains("SEASON"), "no real-world season section")
	assert_true(text.contains("CAREER"), "no career section")
	assert_true(text.contains("IN FOOTBALLSIM"), "no in-sim section")
	var bars: Array = []
	for block in page["blocks"]:
		if str(block["k"]) == "bars":
			bars = block["items"]
	assert_eq(bars.size(), 6, "an outfielder should show six attributes")


func test_the_player_page_notes_read_as_player_copy() -> void:
	for p in PLRepository.shared().squad("ENG-MUN1"):
		var text := _flatten(WikiModel.page(WikiModel.PLAYER, str(p["id"])))
		for word in ["SNAPSHOT", "DATASET", "SEASON LINE", "BEST EFFORT", "LEDGER"]:
			assert_false(text.contains(word), "%s still says %s" % [str(p["id"]), word])
	var empty := WikiModel.page(WikiModel.PLAYER, TestSquad.id_of("ENG-MUN1", "Casemiro"))
	var notes: Array = []
	for block in empty["blocks"]:
		if str(block["k"]) == "note":
			notes.append(str(block["text"]))
	assert_has(notes, "NO SEASON STATISTICS YET", "the empty season block is not player copy")
	assert_has(notes, "NO CAREER TOTALS YET", "the empty career block is not player copy")

func test_a_goalkeeper_page_shows_keeper_attributes() -> void:
	var page := WikiModel.page(WikiModel.PLAYER, TestSquad.id_of("ENG-MUN1", "S. Lammens"))
	var bars: Array = []
	for block in page["blocks"]:
		if str(block["k"]) == "bars":
			bars = block["items"]
	assert_eq(bars.size(), 5, "a keeper should show five keeper attributes")
	assert_eq(str(bars[0][0]), "DIVING", "keeper attributes are in the wrong order")

func test_unknown_targets_are_rejected() -> void:
	assert_false(WikiModel.has_page(WikiModel.PLAYER, TestSquad.none()), "a missing player resolved")
	assert_false(WikiModel.has_page(WikiModel.TEAM, "NOPE"), "a missing club resolved")
	assert_false(WikiModel.has_page(WikiModel.MANAGER, "NOPE"), "a missing manager resolved")
	assert_false(WikiModel.has_page("banana", ""), "a made-up page kind resolved")
	assert_eq(WikiModel.label(WikiModel.LEAGUE, ""), "PREMIER LEAGUE",
		"the league crumb should name the competition")
	assert_eq(WikiModel.label(WikiModel.TEAM, "ENG-MUN1"), "MUN", "the club crumb should be the abbreviation")
	assert_eq(WikiModel.label(WikiModel.MANAGER, "ENG-MUN1"), "R. Amorim", "the manager crumb should name him")


func test_the_manager_page_reads_the_dugout_temperament() -> void:
	var prof := ManagerData.profile("ENG-MUN1")
	var page := WikiModel.page(WikiModel.MANAGER, "ENG-MUN1")
	assert_eq(str(page["title"]), str(prof["name"]).to_upper(), "the manager page lost his name")
	var kinds := _kinds(page)
	assert_has(kinds, "kv", "no club figures on the manager page")
	assert_has(kinds, "bars", "no temperament bars on the manager page")
	var bars: Array = []
	for block in page["blocks"]:
		if str(block["k"]) == "bars":
			bars = block["items"]
	assert_eq(bars.size(), 5, "a persona should read five temperament bars")
	var text := _flatten(page)
	assert_true(text.contains(str(prof["trait"]).to_upper()), "the one-line trait is not on the page")
	assert_true(text.contains("PREFERRED LEVERS"), "the levers have no section")
	for target in _targets(page):
		assert_true(WikiModel.has_page(str(target["page"]), str(target["id"])), "dead link %s" % str(target))


func test_a_snapshot_manager_reads_a_name_and_no_invented_temperament() -> void:
	var page := WikiModel.page(WikiModel.MANAGER, "ESP-BAR1")
	assert_eq(str(page["title"]), "H. FLICK", "the snapshot club lost its manager's name")
	assert_false(_kinds(page).has("bars"), "a club with no authored temperament drew bars")
	var text := _flatten(page)
	assert_true(text.contains("NO TEMPERAMENT RECORDED"), "the missing temperament is not said out loud")
	assert_true(text.contains("BARCELONA"), "the manager page does not name his club")


func test_the_club_page_offers_the_manager() -> void:
	var page := WikiModel.page(WikiModel.TEAM, "ENG-MUN1")
	var found := false
	for target in _targets(page):
		if str(target.get("page", "")) == WikiModel.MANAGER and str(target.get("id", "")) == "ENG-MUN1":
			found = true
	assert_true(found, "the club page has no door to its manager")

func test_the_club_page_draws_its_season_race() -> void:
	var page := WikiModel.page(WikiModel.TEAM, "ENG-MUN1")
	var spark := {}
	for block in page["blocks"]:
		if str(block["k"]) == "spark":
			spark = block
	assert_false(spark.is_empty(), "the club page drew no position race")
	var points: Array = spark["points"]
	assert_gte(points.size(), 11, "the race lost a gameweek into the snapshot")
	assert_eq(int(spark["clubs"]), 20, "the race counts the wrong clubs")
	assert_eq(int(spark["place"]), int((points[points.size() - 1] as Dictionary)["position"]),
		"the gold place is not the last day")
	var spark_row := {}
	for row in WikiBody.layout(page["blocks"], 1112.0, false)["rows"]:
		if str(row["k"]) == "spark":
			spark_row = row
	assert_false(spark_row.is_empty(), "the body laid the race out as nothing")
	assert_eq((spark_row["rect"] as Rect2).size.y, WikiBody.SPARK_H, "the chart is not its own height")
	for row in WikiBody.layout(page["blocks"], 800.0, true)["rows"]:
		if str(row["k"]) == "spark":
			assert_eq((row["rect"] as Rect2).size.y, WikiBody.SPARK_COMPACT_H,
				"a compact body kept the desktop chart height")


func test_layout_fits_a_page_into_rows() -> void:
	var page := WikiModel.page(WikiModel.TEAM, "ENG-MUN1")
	var desktop := WikiBody.layout(page["blocks"], 1112.0, false)
	assert_gte(int(desktop["height"]), 400.0, "a club page is suspiciously short")
	assert_gte(desktop["rows"].size(), 20, "a club page lays out too few rows")
	for row in desktop["rows"]:
		assert_gte((row["rect"] as Rect2).size.x, 0.0, "a row has no width")
	var compact := WikiBody.layout(page["blocks"], 800.0, true)
	assert_gte(float(compact["height"]), float(desktop["height"]) * 0.7, "the phone layout collapsed")

func test_snapshot_pages_carry_no_availability_status() -> void:
	assert_eq(WikiAbsence.statuses("ENG-MUN1").size(), 0, "the snapshot claims an open season")
	var page := WikiModel.page(WikiModel.TEAM, "ENG-MUN1")
	var cols: Array = []
	for block in page["blocks"]:
		if str(block["k"]) == "table" and (block["cols"] as Array).has("OVR"):
			cols = block["cols"]
	assert_false(cols.has("STATUS"), "the snapshot squad carries a status column")
	assert_false(_flatten(WikiModel.page(WikiModel.PLAYER, TestSquad.id_of("ENG-MUN1", "S. Lammens"))).contains("STATUS"),
		"a snapshot player page shows availability")


func _kinds(page: Dictionary) -> Array:
	var out: Array = []
	for block in page["blocks"]:
		out.append(str(block["k"]))
	return out

func _rows_in(page: Dictionary, section: String) -> int:
	var seen := false
	for block in page["blocks"]:
		if str(block["k"]) == "section" and str(block["text"]) == section:
			seen = true
			continue
		if seen and str(block["k"]) == "table":
			return block["rows"].size()
		if seen and str(block["k"]) == "section":
			return 0
		if seen and str(block["k"]) != "table":
			return 0
	return 0

func _targets(page: Dictionary) -> Array:
	var out: Array = []
	for block in page["blocks"]:
		for row in block.get("rows", []):
			if row.has("target"):
				out.append(row["target"])
		for item in block.get("items", []):
			if item is Dictionary and item.has("target"):
				out.append(item["target"])
	return out

func _flatten(page: Dictionary) -> String:
	var text := "%s %s" % [page.get("title", ""), page.get("subtitle", "")]
	for block in page.get("blocks", []):
		text += " " + str(block.get("text", ""))
		for row in block.get("rows", []):
			text += " " + " ".join(PackedStringArray(row.get("cells", [])))
		for item in block.get("items", []):
			text += " " + str(item)
	return text
