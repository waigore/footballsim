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


func test_sorting_orders_the_rows_but_keeps_the_official_place() -> void:
	var rows: Array = _table()
	rows[0]["points"] = 10
	rows[1]["points"] = 30
	rows[2]["points"] = 20
	var view := LeagueTableView.new()
	view.mode = LeagueTableView.FULL
	view.order.key = "points"
	view.order.dir = -1
	var items: Array = view.layout(Vector2(1600, 900),
		{"table": rows, "rules": LeagueRules.defaults()})
	var points: Array = []
	var by_position := {}
	for item in items:
		if str(item["kind"]) == "table_row":
			var row: Dictionary = item["row"]
			points.append(int(row["points"]))
			by_position[int(row["position"])] = str(item["zone"])
	assert_eq(points[0], 30, "the high side did not come first")
	assert_eq(points[1], 20, "the rows are not sorted by points")
	assert_eq(points[2], 10, "the rows are not sorted by points")
	assert_eq(by_position[1], "ucl", "the champion's band left its place")
	assert_eq(by_position[20], "relegation", "the drop lost its band")
	view.order.dir = 1
	var ascending: Array = []
	for item in view.layout(Vector2(1600, 900), {"table": rows, "rules": LeagueRules.defaults()}):
		if str(item["kind"]) == "table_row":
			ascending.append(int((item["row"] as Dictionary)["points"]))
	assert_eq(ascending[0], 0, "the low side did not come first when reversed")


func test_a_hidden_sort_column_leaves_the_compact_strip_in_place() -> void:
	var rows: Array = _table()
	rows[0]["home_gf"] = 3
	rows[1]["home_gf"] = 30
	rows[2]["home_gf"] = 10
	var view := LeagueTableView.new()
	view.mode = LeagueTableView.COMPACT
	view.order.key = "home_gf"
	view.order.dir = -1
	var positions: Array = []
	for item in view.layout(Vector2(913, 411), {"table": rows, "rules": LeagueRules.defaults()}):
		if str(item["kind"]) == "table_row":
			positions.append(int((item["row"] as Dictionary)["position"]))
	assert_eq(positions[0], 1, "the compact strip sorted by a column it does not show")
	view.mode = LeagueTableView.FULL
	var by_home: Array = []
	for item in view.layout(Vector2(1600, 900), {"table": rows, "rules": LeagueRules.defaults()}):
		if str(item["kind"]) == "table_row":
			by_home.append(int((item["row"] as Dictionary)["home_gf"]))
	assert_eq(by_home[0], 30, "the full reading lost the sort it was given")

func test_attach_clears_a_reading_without_a_save() -> void:
	var view := LeagueTableView.new()
	view.mode = LeagueTableView.FULL
	view.order.key = "points"
	view.order.dir = 1
	view.attach(null)
	assert_eq(view.mode, "", "a table with no save kept a reading")
	assert_eq(view.order.key, "", "a table with no save kept a sort")
	assert_eq(view.order.dir, -1, "a table with no save kept a direction")

	var order := LeagueTableSort.new()
	order.attach(null)
	order.press("points", null)
	var one: Array = [{"position": 1, "points": 3}]
	assert_eq(order.ordered(one, LeagueTableView.COMPACT_COLS), one,
		"a one-row table was sorted")
	var two: Array = [{"position": 2, "points": 1, "club_name": "B"},
		{"position": 1, "points": 2, "club_name": "A"}]
	assert_eq(int(order.ordered(two, LeagueTableView.COMPACT_COLS)[0]["position"]), 1,
		"the higher points did not sort first")
	order.key = "club"
	order.dir = 1
	var names: Array = order.ordered(two, LeagueTableView.COMPACT_COLS)
	assert_eq(str(names[0]["club_name"]), "A", "the club column did not sort A-Z")
	assert_eq(LeagueTableSort.sortable("gd"), true, "goal difference cannot be sorted by")
	assert_false(LeagueTableSort.sortable(""), "the official order can be sorted by")
	assert_eq(LeagueTableSort.cell({"gf": 5, "ga": 2}, "gd"), 3, "goal difference is not derived")
	assert_eq(LeagueTableSort.cell({"points": 7}, "points"), 7, "a saved count was not read")
	assert_eq(LeagueTableView.columns(LeagueTableView.FULL), LeagueTableView.FULL_COLS,
		"the full reading lost its columns")
	assert_eq(LeagueTableLayout.columns(LeagueTableLayout.FORM), LeagueFormColumns.FORM_COLS,
		"the form reading lost its columns")
	assert_eq(LeagueTableView.FULL_COLS, LeagueColumns.FULL_COLS,
		"the full columns left the shared rail")


func test_full_places_keep_the_home_and_away_groups() -> void:
	var places := LeagueColumns.full_of(Rect2(24.0, 0.0, 900.0, 22.0), 150.0)
	var groups: Array = []
	for col in places["cols"]:
		var group := str(col.get("group", ""))
		if group != "" and (groups.is_empty() or groups[groups.size() - 1] != group):
			groups.append(group)
	assert_eq(groups, ["OVERALL", "HOME", "AWAY"],
		"the full rail lost its home and away groups")
	assert_gt(float(places["club_w"]), 0.0, "the club lane has no width")
	assert_eq(LeagueColumns.numeric(LeagueColumns.FULL_COLS), (places["cols"] as Array).size(),
		"the full rail dropped a numeric column")


func test_mode_bar_marks_the_active_reading() -> void:
	var items: Array = LeagueTableLayout.mode_bar(LeagueTableLayout.FORM, Vector2(800.0, 600.0),
		false)
	var labels: Array = []
	var primary := ""
	for item in items:
		labels.append(str(item["label"]))
		if bool(item.get("primary", false)):
			primary = str(item["label"])
	assert_eq(labels, ["COMPACT", "FULL", "FORM"], "the mode doors left the bar")
	assert_eq(primary, "FORM", "the form door is not the active reading")
