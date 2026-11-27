extends GdToolsTest


var wiki: Control = null

func before_all() -> void:
	PLDatabase.cache_dir = TestScratch.dir("cache_test_screen")
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	wiki = Control.new()
	wiki.set_script(load("res://scripts/ui/wiki_screen.gd"))
	wiki.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(wiki)
	await get_tree().process_frame
	wiki.ui_scale = 1.0
	wiki.touch = false
	wiki.open(WikiModel.LEAGUE, "")

func after_all() -> void:
	if is_instance_valid(wiki):
		wiki.queue_free()
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func test_the_sheet_opens_on_the_league() -> void:
	assert_true(wiki.is_open(), "the sheet did not open")
	assert_eq(str(wiki.current()["page"]), "league", "the sheet did not land on the league")
	assert_eq(str(wiki.page_data["title"]), "PREMIER LEAGUE", "the league page did not render")
	assert_gte(wiki.body.rows().size(), 20, "the league page laid out no rows")

func test_a_tap_on_a_table_row_opens_that_club() -> void:
	wiki.open(WikiModel.LEAGUE, "")
	var row: Dictionary = _first_data_row()
	var target: Dictionary = row["target"]
	assert_eq(str(target["page"]), "team", "the league table does not link to clubs")
	var point: Vector2 = wiki.body.position + row["rect"].position + Vector2(20.0, 8.0)
	assert_true(wiki.tap(point), "the tap did not hit a row")
	assert_eq(wiki.stack.size(), 2, "the club page was not pushed")
	assert_eq(str(wiki.current()["id"]), str(target["id"]), "the wrong club opened")
	assert_eq(str(wiki.page_data["title"]), str(PLRepository.shared().club(str(target["id"]))["name"]).to_upper(), "the club page did not render")

func test_a_club_row_opens_a_player_and_back_returns() -> void:
	wiki.open(WikiModel.TEAM, "MUN")
	var player_row: Dictionary = _row_with_target("player")
	assert_false(player_row.is_empty(), "the squad has no player links")
	var point: Vector2 = wiki.body.position + player_row["rect"].position + Vector2(20.0, 8.0)
	assert_true(wiki.tap(point), "the squad row did not open a player")
	assert_eq(str(wiki.current()["page"]), "player", "a squad row did not open a player page")
	assert_eq(wiki.stack.size(), 2, "the player page was not pushed")
	assert_eq(wiki.crumb_pages().size(), 1, "the club should be one crumb back")
	wiki.key(KEY_ESCAPE)
	assert_eq(str(wiki.current()["page"]), "team", "escape did not walk back to the club")
	assert_eq(wiki.stack.size(), 1, "the back step popped too far")
	wiki.key(KEY_ESCAPE)
	assert_false(wiki.is_open(), "escape at the root did not close the sheet")

func test_crumbs_walk_back_to_an_earlier_page() -> void:
	wiki.open(WikiModel.LEAGUE, "")
	wiki.push(WikiModel.TEAM, "MUN")
	wiki.push(WikiModel.PLAYER, "MUN-b-fernandes")
	assert_eq(wiki.stack.size(), 3, "the stack did not grow")
	assert_eq(wiki.crumb_pages().size(), 2, "both earlier pages should be crumbs")
	wiki.click("crumb:1")
	assert_eq(wiki.stack.size(), 2, "the club crumb did not truncate the stack")
	assert_eq(str(wiki.current()["page"]), "team", "the crumb walked to the wrong page")
	wiki.click("crumb:0")
	assert_eq(wiki.stack.size(), 1, "the league crumb did not truncate the stack")
	assert_eq(str(wiki.current()["page"]), "league", "the crumb walked to the wrong page")

func test_rows_inside_a_page_stay_inside_the_viewport() -> void:
	wiki.open(WikiModel.TEAM, "MUN")
	var vp: Vector2 = wiki.design_vp()
	var box: Rect2 = wiki.body_rect(vp)
	assert_gte(box.position.y, 60.0, "the body starts inside the header")
	assert_lte(box.end.y, vp.y, "the body runs off the bottom")
	assert_lte(box.end.x, vp.x, "the body runs off the right edge")
	var row: Dictionary = wiki.body.rows()[0]
	assert_gte((row["rect"] as Rect2).size.x, 100.0, "rows have no width")

func test_scrolling_clamps_to_the_content() -> void:


	var body := WikiBody.new()
	body.size = Vector2(800.0, 360.0)
	body.set_page(WikiModel.page(WikiModel.TEAM, "MUN"), true)
	assert_gt(body.max_scroll(), 0.0, "a club page should scroll in a phone window")
	body.scroll_by(-100000.0)
	assert_eq(body.scroll, 0.0, "scrolling above the top did not clamp")
	body.scroll_by(100000.0)
	assert_almost_eq(body.scroll, body.max_scroll(), 0.5, "scrolling past the end did not clamp")
	body.free()
	wiki.open(WikiModel.TEAM, "MUN")
	wiki.key(KEY_DOWN)
	assert_lte(wiki.body.scroll, wiki.body.max_scroll(), "the key scrolled past the end")

func test_a_bad_target_is_ignored() -> void:
	wiki.open(WikiModel.LEAGUE, "")
	wiki.push(WikiModel.PLAYER, "NOPE-x")
	assert_eq(wiki.stack.size(), 1, "a missing player was pushed onto the stack")
	wiki.push(WikiModel.LEAGUE, "")
	assert_eq(wiki.stack.size(), 1, "a repeat page was pushed twice")

func test_the_back_door_and_the_close_door() -> void:
	var closed := [0]
	wiki.closed.connect(func(): closed[0] += 1)
	wiki.open(WikiModel.TEAM, "MCI")
	await get_tree().process_frame
	var back_rect: Rect2 = Rect2()
	for b in wiki.buttons:
		if str(b["id"]) == "back":
			back_rect = b["rect"]
	assert_gt(back_rect.size.x, 44.0, "the back door is too small to tap")
	assert_true(wiki.is_open(), "the sheet was not open before the back door")
	wiki.click("back")
	assert_false(wiki.is_open(), "back at the root did not close the sheet")
	assert_eq(closed[0], 1, "closing did not signal the host")
	wiki.open(WikiModel.LEAGUE, "")
	wiki.click("close")
	assert_false(wiki.is_open(), "the close door did not close the sheet")
	assert_eq(closed[0], 2, "the close door did not signal the host")

func test_a_phone_header_lays_its_doors_for_a_finger() -> void:
	var was: bool = wiki.touch
	wiki.touch = true
	wiki.open(WikiModel.LEAGUE, "")
	await get_tree().process_frame
	var back := Rect2()
	var close := Rect2()
	for b in wiki.buttons:
		if str(b["id"]) == "back":
			back = b["rect"]
		elif str(b["id"]) == "close":
			close = b["rect"]
	assert_gte(back.size.y, UiChrome.TAP_H, "the phone's BACK is under a finger")
	assert_gte(close.size.y, UiChrome.TAP_H, "the phone's close door is under a finger")
	assert_lte(back.end.x, close.position.x, "the phone's header doors overlap")
	wiki.touch = was


func test_the_german_hubs_browse_on_desktop_and_phone() -> void:
	for phone in [false, true]:
		wiki.touch = phone
		wiki.ui_scale = 1.0 if not phone else 2.2
		for pair in [["BL", "BUNDESLIGA", 18], ["BL2", "2. BUNDESLIGA", 18]]:
			wiki.open(WikiModel.LEAGUE, str(pair[0]))
			await get_tree().process_frame
			assert_eq(str(wiki.page_data["title"]), str(pair[1]),
				"the German hub did not open (phone=%s)" % phone)
			assert_true(str(wiki.page_data["subtitle"]).contains("18 CLUBS"),
				"the German hub names the wrong club count (phone=%s)" % phone)
			assert_gte(wiki.body.rows().size(), int(pair[2]),
				"the German hub laid out no table (phone=%s)" % phone)
	wiki.touch = false
	wiki.ui_scale = 1.0
	wiki.open(WikiModel.LEAGUE, "")

func test_a_snapshot_date_reveals_its_weekday_on_hover() -> void:
	wiki.open(WikiModel.LEAGUE, "")
	await get_tree().process_frame
	var zone: Dictionary = {}
	for z in wiki.hints.zones:
		zone = z
	assert_false(zone.is_empty(), "the league page painted no snapshot date")
	wiki.mouse = (zone["rect"] as Rect2).get_center()
	assert_eq(str(wiki.tooltip.zone_at().get("date", "")), str(zone["date"]),
		"a hovered snapshot date did not reach the overlay")


func test_the_touch_footer_names_no_keys() -> void:
	var hint := WikiChrome.footer_hint(true, true, true)
	assert_eq(hint, "TAP A ROW TO OPEN  ·  DRAG TO SCROLL", "the phone footer is not the touch copy")
	for word in ["KEY", "ESC", "WHEEL", "CLICK"]:
		assert_false(hint.contains(word), "the phone footer still says %s" % word)


func test_the_desktop_footer_keeps_its_keys() -> void:
	var hint := WikiChrome.footer_hint(false, true, true)
	assert_eq(hint, "CLICK A ROW TO OPEN  ·  ESC BACK  ·  WHEEL, DRAG OR KEYS SCROLL",
		"the desktop footer lost its own copy")


func test_a_page_with_nothing_to_open_advertises_no_row() -> void:
	var hint := WikiChrome.footer_hint(true, false, true)
	assert_eq(hint, "DRAG TO SCROLL", "a stat-only page still advertises a row to open")
	assert_false(WikiChrome.footer_hint(false, false, true).contains("ROW"),
		"the desktop footer advertises a row a stat-only page does not have")


func test_a_short_page_has_no_scroll_advice() -> void:
	assert_eq(WikiChrome.footer_hint(true, true, false), "TAP A ROW TO OPEN", "a fitting page still says drag")
	assert_eq(WikiChrome.footer_hint(true, false, false), "", "a fitted stat page still paints a footer")
	assert_eq(WikiChrome.footer_hint(false, false, false), "ESC BACK", "the desktop footer lost the escape door")


func test_a_club_page_top_has_no_row_to_open_but_its_squad_has() -> void:
	var body := WikiBody.new()
	body.size = Vector2(800.0, 360.0)
	body.set_page(WikiModel.page(WikiModel.TEAM, "MUN"), true)
	assert_false(body.has_open_row_in_view(), "the club page top advertises a row it does not paint")
	var squad: Rect2 = Rect2()
	for row in body.rows():
		if str(row["k"]) == "trow" and not (row.get("target", {}) as Dictionary).is_empty():
			squad = row["rect"]
			break
	assert_gt(squad.size.y, 0.0, "the club page drew no link row")
	body.scroll_to(squad.position.y)
	assert_true(body.has_open_row_in_view(), "the squad on screen is not read as rows to open")
	body.free()


func test_touch_table_rows_are_finger_sized() -> void:
	var page := WikiModel.page(WikiModel.LEAGUE, "")
	var desk := WikiBody.layout(page["blocks"], 1048.0, true, false)
	var touch := WikiBody.layout(page["blocks"], 1048.0, true, true)
	var desk_rows: Array = []
	var touch_rows: Array = []
	for row in desk["rows"]:
		if str(row["k"]) == "trow":
			desk_rows.append(row["rect"])
	for row in touch["rows"]:
		if str(row["k"]) == "trow":
			touch_rows.append(row)
	assert_eq(touch_rows.size(), desk_rows.size(), "the touch layout lost rows")
	assert_eq(touch_rows.size(), 36, "the league page lost clubs on a phone")
	assert_almost_eq((desk_rows[1] as Rect2).position.y - (desk_rows[0] as Rect2).position.y, 24.0, 0.01,
		"the desktop reading stopped being dense")


	var previous: Dictionary = {}
	for row in touch_rows:
		var r: Rect2 = row["rect"]
		assert_gte(r.size.y, 48.0, "a touch row is shorter than 48 units")
		if not previous.is_empty() and int(row["index"]) == int(previous["index"]) + 1:
			assert_almost_eq(r.position.y - (previous["rect"] as Rect2).position.y, WikiBody.TAP_ROW_H, 0.01,
				"two touch rows in one table do not share the finger pitch")
		previous = row


func test_a_touch_row_answers_a_press_after_scrolling() -> void:
	var body := WikiBody.new()
	body.size = Vector2(1096.0, 493.0)
	body.touch = true
	body.set_page(WikiModel.page(WikiModel.LEAGUE, ""), true)
	var checked := 0
	for row in body.rows():
		if str(row["k"]) != "trow" or (row["target"] as Dictionary).is_empty():
			continue
		var r: Rect2 = row["rect"]
		body.scroll_to(r.position.y - 120.0)
		var p := Vector2(40.0, r.position.y - body.scroll + r.size.y * 0.5)
		if p.y < 0.0 or p.y >= body.size.y:
			continue
		var hit: Dictionary = body.hit(p)
		assert_eq(str(hit.get("id", "")), str((row["target"] as Dictionary).get("id", "")),
			"a press in the middle of a row opened another club")
		checked += 1
	assert_gt(checked, 10, "no scrolled row answered a press")
	body.free()


func test_the_league_table_keeps_the_row_hint() -> void:
	var body := WikiBody.new()
	body.size = Vector2(800.0, 360.0)
	body.set_page(WikiModel.page(WikiModel.LEAGUE, ""), true)
	assert_true(body.has_open_row_in_view(), "the league table's own rows are not read as links")
	body.free()

func test_the_club_page_opens_its_manager() -> void:
	wiki.open(WikiModel.TEAM, "MUN")
	var chip: Dictionary = _chip_with_target("manager")
	assert_false(chip.is_empty(), "the club page has no door to its manager")
	var point: Vector2 = wiki.body.position + (chip["rect"] as Rect2).position + Vector2(20.0, 8.0)
	assert_true(wiki.tap(point), "the manager chip did not answer a tap")
	assert_eq(str(wiki.current()["page"]), "manager", "the manager chip opened another page")
	assert_eq(str(wiki.current()["id"]), "MUN", "the manager chip opened another club's manager")
	assert_eq(str(wiki.page_data["title"]), "R. AMORIM", "the manager page did not render")
	assert_eq(wiki.crumb_pages().size(), 1, "the club should be one crumb back")
	wiki.key(KEY_ESCAPE)
	assert_eq(str(wiki.current()["page"]), "team", "escape did not walk back to the club")

func _first_data_row() -> Dictionary:
	for row in wiki.body.rows():
		if str(row["k"]) == "trow" and row.has("target"):
			return row
	return {}

func _row_with_target(page: String) -> Dictionary:
	for row in wiki.body.rows():
		var target: Dictionary = row.get("target", {})
		if str(row["k"]) == "trow" and str(target.get("page", "")) == page:
			return row
	return {}

func _chip_with_target(page: String) -> Dictionary:
	for row in wiki.body.rows():
		var target: Dictionary = row.get("target", {})
		if str(row["k"]) == "chip" and str(target.get("page", "")) == page:
			return row
	return {}
