extends GdToolsTest

## Encyclopedia page data: every section the issue asked for is present, and
## every cross-link points at a page that exists.

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

func test_every_link_on_the_league_page_resolves() -> void:
	var page := WikiModel.page(WikiModel.LEAGUE, "")
	for target in _targets(page):
		assert_true(WikiModel.has_page(str(target["page"]), str(target["id"])), "dead link %s" % str(target))

func test_the_club_page_shows_the_agreed_sections() -> void:
	var page := WikiModel.page(WikiModel.TEAM, "MUN")
	assert_eq(str(page["title"]), "MANCHESTER UNITED", "the club page lost its title")
	var kinds := _kinds(page)
	assert_has(kinds, "kv", "no season figures on the club page")
	assert_has(kinds, "bars", "no tactical profile on the club page")
	assert_gte(_rows_in(page, "SQUAD"), 18, "the squad list is short")
	assert_gte(_rows_in(page, "RESULTS  ·  SNAPSHOT"), 5, "no club results")
	for target in _targets(page):
		assert_true(WikiModel.has_page(str(target["page"]), str(target["id"])), "dead link %s" % str(target))

func test_the_player_page_shows_ability_real_and_sim_numbers() -> void:
	var page := WikiModel.page(WikiModel.PLAYER, "MUN-b-fernandes")
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

## The empty states on a player page read as player copy, not as notes about the
## data pipeline (#208): no snapshot, dataset, season line or ledger talk.
func test_the_player_page_notes_read_as_player_copy() -> void:
	for p in PLRepository.shared().squad("MUN"):
		var text := _flatten(WikiModel.page(WikiModel.PLAYER, str(p["id"])))
		for word in ["SNAPSHOT", "DATASET", "SEASON LINE", "BEST EFFORT", "LEDGER"]:
			assert_false(text.contains(word), "%s still says %s" % [str(p["id"]), word])
	var empty := WikiModel.page(WikiModel.PLAYER, "MUN-casemiro")
	var notes: Array = []
	for block in empty["blocks"]:
		if str(block["k"]) == "note":
			notes.append(str(block["text"]))
	assert_has(notes, "NO SEASON STATISTICS YET", "the empty season block is not player copy")
	assert_has(notes, "NO CAREER TOTALS YET", "the empty career block is not player copy")

func test_a_goalkeeper_page_shows_keeper_attributes() -> void:
	var page := WikiModel.page(WikiModel.PLAYER, "MUN-s-lammens")
	var bars: Array = []
	for block in page["blocks"]:
		if str(block["k"]) == "bars":
			bars = block["items"]
	assert_eq(bars.size(), 5, "a keeper should show five keeper attributes")
	assert_eq(str(bars[0][0]), "DIVING", "keeper attributes are in the wrong order")

func test_unknown_targets_are_rejected() -> void:
	assert_false(WikiModel.has_page(WikiModel.PLAYER, "NOPE-x"), "a missing player resolved")
	assert_false(WikiModel.has_page(WikiModel.TEAM, "NOPE"), "a missing club resolved")
	assert_false(WikiModel.has_page("banana", ""), "a made-up page kind resolved")
	assert_eq(WikiModel.label(WikiModel.LEAGUE, ""), "PREMIER LEAGUE",
		"the league crumb should name the competition")
	assert_eq(WikiModel.label(WikiModel.TEAM, "MUN"), "MUN", "the club crumb should be the abbreviation")

func test_layout_fits_a_page_into_rows() -> void:
	var page := WikiModel.page(WikiModel.TEAM, "MUN")
	var desktop := WikiBody.layout(page["blocks"], 1112.0, false)
	assert_gte(int(desktop["height"]), 400.0, "a club page is suspiciously short")
	assert_gte(desktop["rows"].size(), 20, "a club page lays out too few rows")
	for row in desktop["rows"]:
		assert_gte((row["rect"] as Rect2).size.x, 0.0, "a row has no width")
	var compact := WikiBody.layout(page["blocks"], 800.0, true)
	assert_gte(float(compact["height"]), float(desktop["height"]) * 0.7, "the phone layout collapsed")

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
