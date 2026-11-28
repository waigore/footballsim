extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_test_form_guide")
var CACHE_DIR := TestScratch.dir("cache_test_form_guide")
const SEED := 20261212

var season: LeagueSeason = null


func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	TestScratch.clear(SAVE_DIR)
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	season = LeagueSeason.create("Form Guide", "generated", "fixture_days", SEED)
	if season != null:
		season.advance()
		season.advance()


func after_all() -> void:
	if season != null:
		season.close()
	TestScratch.clear(SAVE_DIR)
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()


func test_fold_reads_each_result_and_keeps_the_newest_five() -> void:
	var rows: Array = [
		_fixture("A", "B", 2, 0), _fixture("A", "C", 1, 1), _fixture("C", "A", 3, 1),
		_fixture("A", "D", 0, 1), _fixture("A", "E", 4, 2), _fixture("A", "F", 2, 2),
	]
	var forms := LeagueFormGuide.fold(rows)
	assert_eq(LeagueFormGuide.label(forms["A"]), "D L L W D",
		"the guide did not read six results as the newest five")
	assert_eq(LeagueFormGuide.label(forms["B"]), "L", "the away side kept no mark")
	assert_eq(LeagueFormGuide.label(LeagueFormGuide.fold(rows, 3)["A"]), "L W D",
		"the limit did not trim to the newest three")


func test_fold_counts_a_home_result_once_per_side() -> void:
	var forms := LeagueFormGuide.fold([_fixture("H", "V", 0, 3)])
	assert_eq(LeagueFormGuide.label(forms["H"]), "L", "the home loss read as something else")
	assert_eq(LeagueFormGuide.label(forms["V"]), "W", "the away win read as something else")
	assert_eq(LeagueFormGuide.label(LeagueFormGuide.fold([_fixture("X", "Y", 1, 1)])["X"]), "D",
		"a level match is not a draw")


func test_fold_ignores_a_club_it_cannot_name() -> void:
	var forms := LeagueFormGuide.fold([{"home_club_id": "S", "home_goals": 1}])
	assert_eq(LeagueFormGuide.label(forms.get("S", [])), "W",
		"a row without an away side lost its own result")
	assert_eq(forms.size(), 1, "the guide invented a club")
	assert_true(LeagueFormGuide.fold([]).is_empty(), "an empty ledger read a form")
	assert_true(LeagueFormGuide.map_for("").is_empty(), "an unnamed competition read a form")


func test_the_guide_reads_the_save_oldest_first() -> void:
	var forms := LeagueFormGuide.map_for("PL")
	assert_eq(forms.size(), 20, "the guide did not read every club of the league")
	var state := season.state()
	var keys: Array = []
	for row in state["table"]:
		var club := str(row["club_id"])
		var marks: Array = row.get("form", [])
		assert_eq(marks.size(), 2, "%s played two matchdays and reads %d marks" % [club, marks.size()])
		assert_eq(LeagueFormGuide.label(marks), _ledger_label(club),
			"%s's form left the ledger it is read from" % club)
		keys.append(club)
	assert_eq(keys.size(), 20, "the decorated table lost a club")


func test_a_league_with_nothing_played_reads_no_form() -> void:
	assert_true(LeagueFormGuide.map_for("LL").is_empty(),
		"a competition with no played fixture read a form")
	var rows: Array = LeagueFormGuide.decorate([{"club_id": "PL-ARS", "position": 1}], "LL")
	assert_eq((rows[0]["form"] as Array).size(), 0, "a club outside the ledger kept a form")
	assert_eq(rows.size(), 1, "the decoration dropped a row")


func test_the_form_reading_lays_the_pips_and_the_points() -> void:
	var view := LeagueTableView.new()
	view.mode = LeagueTableView.FORM
	var items: Array = view.layout(Vector2(1600, 900), _view(_rows()))
	var heads: Array = []
	var captions: Array = []
	var marks := 0
	var doors: Array = []
	var points := 0
	for item in items:
		match str(item["kind"]):
			"head":
				heads.append(str(item["label"]))
			"caption":
				captions.append(str(item["label"]))
			"table_row":
				marks = maxi(marks, (item["form"] as Array).size())
				points = maxi(points, int((item["row"] as Dictionary).get("points", 0)))
			"button":
				doors.append(str(item["label"]))
	assert_eq(heads, ["#", "CLUB", "FORM", "PTS"], "the form reading does not name its columns")
	assert_eq(captions, [LeagueTableView.FORM_CAPTION], "the reading lost its order caption")
	assert_eq(marks, 5, "the rows do not carry five marks")
	assert_eq(points, 9, "the points column left the reading")
	assert_has(doors, "FORM", "the reading has no door of its own")
	assert_has(doors, "COMPACT", "the form reading dropped the compact door")


func test_the_form_door_switches_the_reading_and_form_never_sorts() -> void:
	var view := LeagueTableView.new()
	view.attach(null)
	assert_true(view.press("tbl:mode:form", null), "the form door did not switch the reading")
	assert_eq(view.mode, LeagueTableView.FORM, "the reading is not the form one")
	assert_false(view.press("tbl:mode:form", null), "pressing the reading it is on changed it")
	assert_eq(LeagueTableView.columns(LeagueTableView.FORM), LeagueTableView.FORM_COLS,
		"the form reading lost its columns")
	assert_false(LeagueTableSort.sortable("form"), "the form column offers a sort")
	var items: Array = view.layout(Vector2(1600, 900), _view(_rows()))
	for item in items:
		if str(item["kind"]) != "head":
			continue
		var label := str(item["label"])
		if label == "FORM":
			assert_eq(str(item["id"]), "", "the form head carries a sort door")
		elif label == "CLUB" or label == "PTS":
			assert_true(str(item["id"]) != "", "a sortable head lost its door")


func test_a_hidden_sort_leaves_the_form_rows_in_place() -> void:
	var rows: Array = _rows()
	rows[0]["won"] = 0
	rows[1]["won"] = 6
	var view := LeagueTableView.new()
	view.mode = LeagueTableView.FORM
	view.order.key = "won"
	view.order.dir = -1
	var places: Array = []
	for item in view.layout(Vector2(1600, 900), _view(rows)):
		if str(item["kind"]) == "table_row":
			places.append(int((item["row"] as Dictionary)["position"]))
	assert_eq(places[0], 1, "the form reading sorted by a column it does not show")


func test_the_form_reading_fits_a_phone_row() -> void:
	assert_lte(LeagueFormColumns.min_row(), 411.0 - 48.0,
		"the form reading cannot fit a phone row")
	var view := LeagueTableView.new()
	view.mode = LeagueTableView.FORM
	for item in view.layout(Vector2(411, 411), _view(_rows())):
		if str(item["kind"]) == "table_row":
			assert_lte((item["rect"] as Rect2).end.x, 411.0 - 24.0 + 0.01,
				"the form row ran past the phone sheet")


func test_each_mark_carries_its_own_colour() -> void:
	assert_eq(LeagueFormColumns.mark_color(LeagueFormGuide.WIN), UiChrome.C_LIVE,
		"a win is not the live green")
	assert_eq(LeagueFormColumns.mark_color(LeagueFormGuide.DRAW), UiChrome.C_SOFT,
		"a draw is not the soft grey")
	assert_eq(LeagueFormColumns.mark_color(LeagueFormGuide.LOSS), UiChrome.C_DANGER,
		"a loss is not the danger red")
	assert_almost_eq(LeagueFormColumns.lane(5),
		5.0 * LeagueFormColumns.PIP + 4.0 * LeagueFormColumns.GAP, 0.01,
		"the pip lane is not five boxes and four gaps")
	assert_gt(LeagueFormColumns.min_row(), LeagueFormColumns.lane(),
		"the reading has no club column beside its pips")


func test_a_touch_pose_lays_the_reading_doors_at_the_thumb_floor() -> void:
	var view := LeagueTableView.new()
	view.mode = LeagueTableView.FORM
	var touch_view := _view(_rows())
	touch_view["touch"] = true
	var doors := 0
	for item in view.layout(Vector2(913, 411), touch_view):
		if str(item["kind"]) != "button" or not str(item["id"]).begins_with("tbl:mode:"):
			continue
		doors += 1
		assert_gte((item["rect"] as Rect2).size.y, float(UiChrome.TAP_H),
			"%s is under the thumb floor" % str(item["label"]))
	assert_eq(doors, 3, "a touch table lost a reading door")
	for item in view.layout(Vector2(1600, 900), _view(_rows())):
		if str(item["kind"]) == "button" and str(item["id"]) == "tbl:mode:form":
			assert_almost_eq((item["rect"] as Rect2).size.y, LeagueChrome.BAR_H - 14.0, 0.01,
				"the desktop form door left its dense pitch")


func _fixture(home: String, away: String, home_goals: int, away_goals: int) -> Dictionary:
	return {"home_club_id": home, "away_club_id": away,
		"home_goals": home_goals, "away_goals": away_goals}


func _rows() -> Array:
	return [
		{"position": 1, "club_id": "PL-ARS", "club_name": "Arsenal", "club_abbr": "ENG-ARS1",
			"points": 9, "won": 3, "form": ["W", "D", "L", "W", "W"]},
		{"position": 2, "club_id": "PL-MUN", "club_name": "Manchester United",
			"club_abbr": "ENG-MUN1", "points": 4, "won": 1, "form": ["L"]},
		{"position": 3, "club_id": "PL-EVE", "club_name": "Everton", "club_abbr": "ENG-EVE1",
			"points": 0, "won": 0, "form": []},
	]


func _view(rows: Array) -> Dictionary:
	return {"table": rows, "rules": LeagueRules.defaults()}


func _ledger_label(club_id: String) -> String:
	var newest: Array = []
	for fx in LeagueLedger.fixtures(club_id, LeagueFormGuide.LAST, "PL"):
		var home := str(fx["home_club_id"]) == club_id
		var scored := int(fx["home_goals"]) if home else int(fx["away_goals"])
		var conceded := int(fx["away_goals"]) if home else int(fx["home_goals"])
		if scored > conceded:
			newest.append(LeagueFormGuide.WIN)
		elif scored == conceded:
			newest.append(LeagueFormGuide.DRAW)
		else:
			newest.append(LeagueFormGuide.LOSS)
	var out: Array = []
	for i in range(newest.size() - 1, -1, -1):
		out.append(newest[i])
	return LeagueFormGuide.label(out)
