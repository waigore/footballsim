extends GdToolsTest


func _table(rows: int = 20) -> Array:
	var out: Array = []
	for i in range(rows):
		out.append({
			"position": i + 1, "club_id": "C%d" % i, "club_abbr": "C%d" % i,
			"club_name": "Club %d" % i, "played": 0, "won": 0, "drawn": 0, "lost": 0,
			"gf": 0, "ga": 0, "points": 0,
			"home_played": 0, "home_won": 0, "home_drawn": 0, "home_lost": 0,
			"home_gf": 0, "home_ga": 0, "away_played": 0, "away_won": 0,
			"away_drawn": 0, "away_lost": 0, "away_gf": 0, "away_ga": 0,
		})
	return out

func test_a_touch_table_lays_finger_sized_rows_and_headers() -> void:
	var view := LeagueTableView.new()
	view.mode = LeagueTableView.COMPACT
	var vp := Vector2(913, 411)
	var items: Array = view.layout(vp, {"table": _table(), "rules": LeagueRules.defaults(),
		"touch": true})
	var rows := 0
	var heads := 0
	for item in items:
		var rect: Rect2 = item["rect"]
		if str(item["kind"]) == "table_row":
			rows += 1
			assert_gte(rect.size.y, 48.0, "a touch table row is shorter than 48 units")
		elif str(item["kind"]) == "head" and str(item["id"]) != "":
			heads += 1
			assert_gte(rect.size.y, 48.0, "a touch sortable header is shorter than 48 units")
	assert_eq(rows, 20, "the touch table lost rows")
	assert_gt(heads, 8, "the touch table lost sortable headers")

	var previous := -1.0
	for item in items:
		if str(item["kind"]) == "table_row":
			var rect: Rect2 = item["rect"]
			assert_gt(rect.position.y, previous, "two touch rows share a pixel")
			previous = rect.end.y

	var body := LeagueBody.new()
	body.set_sheet(items, vp, true)
	assert_gt(body.max_scroll(), 0.0, "the touch table does not scroll its rows")
	body.free()

func test_a_touch_header_press_still_sorts_while_it_sits_above_its_rows() -> void:
	var view := LeagueTableView.new()
	view.mode = LeagueTableView.FULL
	var items: Array = view.layout(Vector2(913, 411), {"table": _table(),
		"rules": LeagueRules.defaults(), "touch": true})
	var head: Dictionary = {}
	var first_row: Dictionary = {}
	for item in items:
		if str(item["id"]) == "tbl:sort:points":
			head = item
		elif str(item["kind"]) == "table_row" and first_row.is_empty():
			first_row = item
	assert_false(head.is_empty(), "the touch table has no points header")
	assert_false(first_row.is_empty(), "the touch table has no rows")
	assert_lte((head["rect"] as Rect2).end.y, (first_row["rect"] as Rect2).position.y,
		"the touch header band overlaps the first row")
	assert_true(view.press("tbl:sort:points", null), "the touch header press did nothing")
	assert_eq(view.order.key, "points", "the touch header press did not sort")

func test_a_desktop_table_keeps_its_dense_pitch() -> void:
	var view := LeagueTableView.new()
	view.mode = LeagueTableView.FULL
	var items: Array = view.layout(Vector2(1600, 900),
		{"table": _table(), "rules": LeagueRules.defaults()})
	var pitches: Array = []
	for item in items:
		if str(item["kind"]) == "table_row":
			pitches.append((item["rect"] as Rect2).position.y)
	assert_almost_eq(float(pitches[1]) - float(pitches[0]), 22.0, 0.01,
		"the desktop table pitch moved: it must stay the dense 22-unit reading")
	assert_almost_eq(LeagueTableHead.height(false), 12.0, 0.01,
		"the desktop header band grew past its one caption line")

	assert_almost_eq(LeagueTableView.row_height({}), 22.0, 0.01,
		"a pose with no touch reading did not default to the desktop pitch")
	assert_gte(LeagueTableView.row_height({"touch": true}), 49.0,
		"a touch pose did not ask for a pitch that clears 48 units of hit area")
	assert_gte(LeagueTableHead.height(true), 48.0,
		"a touch pose did not ask for a finger-sized header band")


func test_the_panel_drawer_door_is_a_finger_sized_header_door() -> void:
	var panel := LeaguePanel.new()
	panel.touch = true
	for vp in [Vector2(411, 914), Vector2(640, 360), Vector2(913, 411)]:
		var door := panel.tab_rect(vp)
		assert_eq(door, LeagueExtra.nav_rect(vp), "the drawer door left the header lane at %s" % vp)
		assert_gte(door.size.x, UiChrome.TAP_H, "the drawer door is narrower than a finger at %s" % vp)
		assert_gte(door.size.y, UiChrome.TAP_H, "the drawer door is shorter than a finger at %s" % vp)
		assert_gte(door.position.x, LeagueExtra.back_rect(true).end.x,
			"the drawer door sits on BACK at %s" % vp)
		assert_lte(door.end.y, LeagueChrome.HEADER, "the drawer door left the header band at %s" % vp)
		assert_lte(door.end.x, LeagueExtra.primary_rect(vp).position.x,
			"the drawer door sits under the primary door at %s" % vp)
		assert_eq(panel.hit(door.get_center(), vp), "panel",
			"the drawer door centre does not open it at %s" % vp)
		assert_eq(panel.hit(Vector2(door.position.x + 40.0, door.get_center().y), vp), "panel",
			"the inboard half of the drawer door does not open it at %s" % vp)
		assert_eq(panel.hit(Vector2(door.end.x + 8.0, door.get_center().y), vp), "",
			"a press beside the drawer door opened the panel at %s" % vp)


func test_a_window_too_narrow_for_the_header_door_keeps_the_edge_plate() -> void:
	var panel := LeaguePanel.new()
	panel.touch = true
	var vp := Vector2(280, 240)
	assert_eq(LeagueExtra.nav_rect(vp), Rect2(), "a narrow window still claims a header lane")
	var door := panel.tab_rect(vp)
	assert_gte(door.size.x, 48.0, "the edge plate is narrower than a finger")
	assert_gte(door.size.y, 48.0, "the edge plate is shorter than a finger")
	assert_gte(door.position.x, 16.0, "the edge plate starts in the system gesture strip")
	assert_eq(panel.hit(door.get_center(), vp), "panel", "the edge plate answers no press")


func test_the_desktop_drawer_door_keeps_its_edge_sliver() -> void:
	var panel := LeaguePanel.new()
	var vp := Vector2(913, 411)
	var door := panel.tab_rect(vp)
	assert_almost_eq(door.position.x, -2.0, 0.01, "the desktop door left the sheet edge")
	assert_almost_eq(door.size.x, 24.0, 0.01, "the desktop door grew into the club rows")
	assert_almost_eq(door.size.y, 104.0, 0.01, "the desktop door lost its tall strip")


	assert_eq(panel.hit(Vector2(6.0, door.get_center().y), vp), "panel",
		"the desktop door no longer answers the edge")
	assert_lte(door.end.x, 24.0, "the desktop door now covers the club rows")


func test_a_touch_full_table_still_pans_to_its_last_column() -> void:
	var view := LeagueTableView.new()
	view.mode = LeagueTableView.FULL
	var vp := Vector2(360.0, 780.0)
	var items: Array = view.layout(vp, {"table": _table(), "rules": LeagueRules.defaults(),
		"touch": true})
	var body := LeagueBody.new()
	body.set_sheet(items, vp, true)
	assert_gt(body.max_hscroll(), 0.0, "the touch full table does not offer a sideways pan")
	body.pan_by(Vector2(1.0e7, 0.0))
	var last: Dictionary = {}
	for item in body.button_rects():
		if str(item["id"]) == "tbl:sort:away_ga":
			last = item
	assert_false(last.is_empty(), "the away goals column has no door")
	assert_lte((last["rect"] as Rect2).end.x, vp.x + 0.5,
		"the last column is still off the window after the pan")
	body.free()
