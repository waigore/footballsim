extends GdToolsTest

## #204: on a handheld the league's targets are finger-sized. The table's rows
## and its sortable headers, and the drawer door that is the only way to the
## season's other readings, all have to answer to a thumb; the desktop table is
## a reading, not a keypad, and keeps its dense pitch.

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
	# The rows never overlap, so two clubs can never answer one press.
	var previous := -1.0
	for item in items:
		if str(item["kind"]) == "table_row":
			var rect: Rect2 = item["rect"]
			assert_gt(rect.position.y, previous, "two touch rows share a pixel")
			previous = rect.end.y
	# And it is still a scrolling page, never a clipped one.
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
	# The pose's device is what picks one of the two readings.
	assert_almost_eq(LeagueTableView.row_height({}), 22.0, 0.01,
		"a pose with no touch reading did not default to the desktop pitch")
	assert_gte(LeagueTableView.row_height({"touch": true}), 49.0,
		"a touch pose did not ask for a pitch that clears 48 units of hit area")
	assert_gte(LeagueTableHead.height(true), 48.0,
		"a touch pose did not ask for a finger-sized header band")

## The door sits inboard of the system gesture strip, because Android eats
## presses in the outermost ~16 density points of the screen edge. A mouse does
## not need that, so the desktop door is unchanged — but it must not have grown
## into the club rows either, or it would eat their presses.
func test_the_panel_drawer_door_is_a_finger_sized_labelled_target() -> void:
	var panel := LeaguePanel.new()
	panel.touch = true
	var vp := Vector2(913, 411)
	var door := panel.tab_rect(vp)
	assert_gte(door.size.x, 48.0, "the drawer door is narrower than a finger")
	assert_gte(door.size.y, 48.0, "the drawer door is shorter than a finger")
	assert_gte(door.position.x, 16.0, "the drawer door starts in the system gesture strip")
	assert_lte(door.end.x, vp.x, "the drawer door runs off the sheet")
	assert_eq(panel.hit(door.get_center(), vp), "panel", "the drawer door centre does not open it")
	assert_eq(panel.hit(Vector2(door.position.x + 40.0, door.get_center().y), vp), "panel",
		"the inboard half of the drawer door does not open it")
	assert_eq(panel.hit(Vector2(door.end.x + 8.0, door.get_center().y), vp), "",
		"a press beside the drawer door opened the panel")


func test_the_desktop_drawer_door_keeps_its_edge_sliver() -> void:
	var panel := LeaguePanel.new()
	var vp := Vector2(913, 411)
	var door := panel.tab_rect(vp)
	assert_almost_eq(door.position.x, -2.0, 0.01, "the desktop door left the sheet edge")
	assert_almost_eq(door.size.x, 24.0, 0.01, "the desktop door grew into the club rows")
	assert_almost_eq(door.size.y, 104.0, 0.01, "the desktop door lost its tall strip")
	# A mouse arrives at the exact strip; the club rows start at x=24 and must
	# keep every pixel of their own width.
	assert_eq(panel.hit(Vector2(6.0, door.get_center().y), vp), "panel",
		"the desktop door no longer answers the edge")
	assert_lte(door.end.x, 24.0, "the desktop door now covers the club rows")

## The full table is wider than a portrait phone; a touch table that grew its
## rows must still be pannable, and the last column still reachable.
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
