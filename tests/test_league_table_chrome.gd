extends GdToolsTest

## The table sheet's own band: columns on a phone and a desktop pose, the header
## captions and their sorts, the two reading doors, and the pan a narrow sheet
## needs to reach its last column. Split out of the sheet suite with
## `LeagueTableView`'s chrome, which paints the title and the zone legend.

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

## #72/#74: the full reading is the compact strip plus the overall, home and
## away columns. On the phone landscape design space (`--ui-scale` on a 1080p
## handset) every one of them has to sit inside the row.
func test_the_full_table_shows_every_column_on_a_phone_landscape() -> void:
	for vp in [Vector2(913, 411), Vector2(873, 393)]:
		var view := LeagueTableView.new()
		view.mode = LeagueTableView.FULL
		var items: Array = view.layout(vp, {"table": _table(), "rules": LeagueRules.defaults()})
		var rows := 0
		var heads := []
		var widest := 0.0
		for item in items:
			if str(item["kind"]) == "table_row":
				rows += 1
				widest = maxf(widest, (item["rect"] as Rect2).end.x)
			elif str(item["kind"]) == "head":
				heads.append(str(item["id"]))
		assert_eq(rows, 20, "the full table lost rows at %s" % vp)
		assert_eq(heads.size(), 22, "the full header lost a column at %s" % vp)
		assert_true(heads.has("tbl:sort:points"), "PTS is not sortable at %s" % vp)
		assert_true(heads.has("tbl:sort:home_gf"), "the home goals are not sortable at %s" % vp)
		assert_true(heads.has("tbl:sort:away_ga"), "the away goals against are missing at %s" % vp)
		assert_lte(widest, vp.x - 24.0, "the full table runs off a phone landscape sheet at %s" % vp)

func test_the_full_header_names_its_three_groups() -> void:
	var view := LeagueTableView.new()
	view.mode = LeagueTableView.FULL
	var captions: Array = []
	for item in view.layout(Vector2(913, 411), {"table": _table(), "rules": LeagueRules.defaults()}):
		if str(item["kind"]) == "caption":
			captions.append(str(item["label"]))
	assert_eq(captions, ["OVERALL", "HOME", "AWAY"], "the full header lost a group caption")

func test_the_table_defaults_to_compact_on_a_phone_and_full_on_desktop() -> void:
	var phone := LeagueTableView.new()
	var heads: Array = []
	for item in phone.layout(Vector2(913, 411), {"table": _table(), "rules": LeagueRules.defaults()}):
		if str(item["kind"]) == "head":
			heads.append(str(item["id"]))
	assert_eq(phone.mode, LeagueTableView.COMPACT, "a phone did not open the compact table")
	assert_eq(heads.size(), 10, "the compact header should be #, club and the whole overall record")
	for key in ["played", "won", "drawn", "lost", "gf", "ga", "gd", "points"]:
		assert_true(heads.has("tbl:sort:" + key),
			"compact does not offer a %s column to sort by (#102)" % key)
	var desktop := LeagueTableView.new()
	desktop.layout(Vector2(1600, 900), {"table": _table(), "rules": LeagueRules.defaults()})
	assert_eq(desktop.mode, LeagueTableView.FULL, "a desktop did not open the full table")

## #102: a column Compact now shows is a column Compact sorts by — the whole
## overall record behaves like any other visible field.
func test_the_compact_strip_sorts_by_the_overall_columns_it_shows() -> void:
	var rows: Array = _table()
	rows[0]["gf"] = 3
	rows[1]["gf"] = 30
	rows[2]["gf"] = 10
	var view := LeagueTableView.new()
	view.mode = LeagueTableView.COMPACT
	for key in ["won", "drawn", "lost", "gf", "ga"]:
		assert_true(view.press("tbl:sort:" + key, null), "compact did not take a %s sort" % key)
	view.order.key = "gf"
	view.order.dir = -1
	var goals: Array = []
	for item in view.layout(Vector2(913, 411), {"table": rows, "rules": LeagueRules.defaults()}):
		if str(item["kind"]) == "table_row":
			goals.append(int((item["row"] as Dictionary)["gf"]))
	assert_eq(goals[0], 30, "the compact strip did not sort by goals scored")

## A full table is wider than a portrait phone: the body offers the sideways
## pan and every column is reachable by dragging.
## The chrome's own split: the title caption joins the season's name and the day,
## and the band legend names one place rule per colour, phone labels included.
func test_the_caption_and_the_legend_name_every_band() -> void:
	assert_eq(LeagueTableChrome.caption({}, ""), "", "an empty sheet grew a caption")
	assert_eq(LeagueTableChrome.caption({"name": "S"}, ""), "S", "the season name left the caption")
	assert_eq(LeagueTableChrome.caption({}, "15 AUG"), "15 AUG", "the day left the caption")
	assert_eq(LeagueTableChrome.caption({"name": "S"}, "15 AUG"), "S · 15 AUG",
		"the caption lost its separator")
	assert_eq(LeagueTableChrome.BANDS.size(), LeagueTableChrome.SHORT_LABELS.size(),
		"a legend band has no label")
	assert_eq(LeagueTableChrome.BANDS.size(), LeagueTableChrome.WIDE_LABELS.size(),
		"the wide legend lost a label")
	assert_eq(str(LeagueTableChrome.BANDS[LeagueTableChrome.BANDS.size() - 1]), "relegation",
		"the legend no longer ends on the drop")
	for band in LeagueTableChrome.BANDS:
		assert_true(LeagueChrome.zone_color(band).a > 0.0, "legend band %s paints nothing" % band)

## #278: the sentence names the pointer the player is holding — CLICK for a mouse
## on a desktop sheet, TAP for a finger on a touch one.
func test_the_sort_sentence_names_the_pointer() -> void:
	var desk := LeagueTableChrome.sentence(false)
	var phone := LeagueTableChrome.sentence(true)
	assert_true(desk.begins_with("CLICK"), "a desktop sheet tells a mouse user to tap: %s" % desk)
	assert_true(phone.begins_with("TAP"), "a touch sheet tells a finger to click: %s" % phone)
	assert_false(desk.contains("TAP"), "the desktop sentence still says TAP: %s" % desk)
	assert_eq(desk.replace("CLICK", "TAP"), phone, "the two readings say different sentences")

## A phone sheet has no room for the legend in the bottom bar, so it moves up
## beside the title; a wide sheet keeps it on the bar and prints the sentence.
func test_the_legend_moves_up_on_a_phone_sheet() -> void:
	assert_true(LeagueTableChrome.narrow(Vector2(360, 780)), "a portrait phone is not narrow")
	assert_false(LeagueTableChrome.narrow(Vector2(1600, 900)), "a desktop sheet was called narrow")
	assert_lte(float(LeagueTableChrome.NARROW_VP), float(LeagueTableChrome.SENTENCE_VP),
		"the sort sentence outlives the bar it rides")
	for vp in [Vector2(360, 300), Vector2(300, 280)]:
		assert_gt(LeagueTableChrome.legend_rect(vp).position.y, 0.0,
			"a phone legend left the sheet at %s" % vp)
		assert_lte(LeagueTableChrome.legend_rect(vp).end.x, vp.x - 24.0 + 0.01,
			"a phone legend runs off the sheet at %s" % vp)
		assert_eq(LeagueTableChrome.sentence_rect(vp), Rect2(),
			"a phone sheet still promises the sort sentence at %s" % vp)
	for vp in [Vector2(760, 640), Vector2(1600, 900)]:
		var strip := LeagueTableChrome.legend_rect(vp)
		assert_almost_eq(strip.end.y, vp.y - LeagueChrome.BAR_H + 24.0, 0.01,
			"the wide legend left the bottom bar at %s" % vp)
		var sentence := LeagueTableChrome.sentence_rect(vp)
		assert_almost_eq(sentence.end.x, vp.x - 24.0, 0.01, "the sentence left the sheet at %s" % vp)
	# And a narrow legend is the shorter one, measured really.
	var bold: Font = load("res://fonts/BarlowCondensed-SemiBold.ttf")
	var short_w := LeagueTableChrome.legend_width(bold, LeagueTableChrome.SHORT_LABELS, 8)
	var wide_w := LeagueTableChrome.legend_width(bold, LeagueTableChrome.WIDE_LABELS, 9)
	assert_gt(short_w, 0.0, "the legend measured nothing")
	assert_gt(wide_w, short_w, "the wide legend is not wider than the phone one")
	assert_lte(short_w, 360.0 - 24.0, "the legend cannot fit beside a phone title")

## The reading doors are this sheet's; a header press belongs to the save's sort,
## and both write the choice through to the save that is open.
func test_a_mode_press_flips_the_reading_and_a_header_press_sorts() -> void:
	var view := LeagueTableView.new()
	view.mode = LeagueTableView.FULL
	assert_true(view.press("tbl:mode:compact", null), "the compact door did nothing")
	assert_eq(view.mode, LeagueTableView.COMPACT, "the compact door did not take")
	assert_false(view.press("tbl:mode:compact", null), "the reading already on screen was taken again")
	assert_true(view.press("tbl:mode:full", null), "the full door did nothing")
	assert_eq(view.mode, LeagueTableView.FULL, "the full door did not take")
	assert_false(view.press("tbl:mode:sideways", null), "an unknown reading was taken")
	assert_true(view.press("tbl:sort:points", null), "a header press did nothing")
	assert_eq(view.order.key, "points", "the header press did not sort")
	assert_eq(view.order.dir, -1, "a numeric column should start on the high side")
	view.press("tbl:sort:points", null)
	assert_eq(view.order.dir, 1, "a second tap did not reverse")
	view.press("tbl:sort:club", null)
	assert_eq(view.order.dir, 1, "the club column should start A-Z")
	assert_false(view.press("tbl:sort:position", null), "the place column is not sortable")
	assert_false(view.press("nope", null), "an unknown door was taken")

func test_the_full_table_pans_sideways_on_a_portrait_phone() -> void:
	var view := LeagueTableView.new()
	view.mode = LeagueTableView.FULL
	var vp := Vector2(360.0, 780.0)
	var items: Array = view.layout(vp, {"table": _table(), "rules": LeagueRules.defaults()})
	var body := LeagueBody.new()
	body.set_sheet(items, vp, true)
	assert_gt(body.max_hscroll(), 0.0, "the full table does not offer a sideways pan")
	body.pan_by(Vector2(1000.0, 0.0))
	assert_almost_eq(body.hscroll, body.max_hscroll(), 0.5, "the pan did not reach the last column")
	var last: Dictionary = {}
	for item in body.button_rects():
		if str(item["id"]) == "tbl:sort:away_ga":
			last = item
	assert_false(last.is_empty(), "the away goals column has no door")
	var rect: Rect2 = last["rect"]
	assert_lte(rect.end.x, vp.x + 0.5, "the last column is still off the window after the pan")
	body.pan_by(Vector2(-1.0e7, 0.0))
	assert_eq(body.hscroll, 0.0, "the pan ran past the first column")
	body.free()

## #308: both readings paint a zone band at the row's own left edge, so the place
## number has to start on the panel beside it — never on top of it. Ranks 1–6 are
## the rows a player reads first, and the full sheet is where they read them.
func test_the_place_number_clears_the_zone_band_in_the_full_reading() -> void:
	var med: Font = load("res://fonts/BarlowCondensed-Medium.ttf")
	var digit_w: float = med.get_string_size("20", HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	for vp in [Vector2(1600, 900), Vector2(3024, 1648), Vector2(913, 411),
			Vector2(873, 393), Vector2(360, 780)]:
		var view := LeagueTableView.new()
		view.mode = LeagueTableView.FULL
		var banded := 0
		for item in view.layout(vp, {"table": _table(), "rules": LeagueRules.defaults()}):
			if str(item["kind"]) != "table_row":
				continue
			var rect: Rect2 = item["rect"]
			var places: Dictionary = item["places"]
			var band_w: float = LeagueTableView.ZONE_BAND_W
			# The band is painted at the row's left edge whatever the reading: the
			# place ink starts after it, and the digits still fit before the club.
			assert_gte(float(places["pos_x"]), rect.position.x + band_w,
				"the place number lands on the zone band at %s" % vp)
			assert_lte(float(places["pos_x"]) + digit_w, float(places["club_x"]),
				"the place number runs into the club name at %s" % vp)
			if str(item["zone"]) != "":
				banded += 1
		assert_gte(banded, 6, "the zone bands left the full table at %s" % vp)
		# The header `#` caption and its door stay on the digits' rail, and clear of
		# the `CLUB` cell it sits beside.
		var hash_cell := {}
		var club_cell := {}
		for item in view.layout(vp, {"table": _table(), "rules": LeagueRules.defaults()}):
			if str(item["kind"]) != "head":
				continue
			if str(item["label"]) == "#":
				hash_cell = item
			elif str(item["label"]) == "CLUB":
				club_cell = item
		assert_false(hash_cell.is_empty(), "the full table lost its place caption at %s" % vp)
		assert_lte((hash_cell["rect"] as Rect2).end.x, (club_cell["rect"] as Rect2).position.x,
			"the place caption runs over the club caption at %s" % vp)
