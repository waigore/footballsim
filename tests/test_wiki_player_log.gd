extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_test_wiki_player_log")
var CACHE_DIR := TestScratch.dir("cache_test_wiki_player_log")
const SEED := 2031

var season: LeagueSeason = null
var scorer: Dictionary = {}


func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	_clean()
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	season = LeagueSeason.create("Player Log Season", "generated", "fixture_days", SEED)
	assert_not_null(season, "the season was not created")
	season.advance()
	season.advance()
	scorer = season.record.report.top_scorers(1)[0]


func after_all() -> void:
	if season != null:
		season.close()
	_clean()
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()


func test_the_player_page_reads_his_events_fixture_by_fixture() -> void:
	var id := str(scorer["player_id"])
	var club_id := _club_of(id)
	var page := WikiModel.page(WikiModel.PLAYER, id)
	var rows := _log_rows(page)
	assert_gte(rows.size(), 1, "the player page lists no match at all")
	var stored := LeagueLedger.player_events(id, club_id, 20)
	assert_eq(rows.size(), stored.size(), "the page and the save disagree on how many matches he played")
	for i in range(rows.size()):
		var fx: Dictionary = stored[i]
		var cells: Array = rows[i]["cells"]
		assert_eq(cells.size(), 5, "a log row is missing a cell")
		assert_eq(str(cells[0]), FixtureCalendar.day_label(str(fx["kickoff"])),
			"the log row is not on the match's own day")
		assert_eq(str(cells[1]), "GW %d" % int(fx["matchday"]), "the log row lost its gameweek")
		assert_eq(str(cells[2]), "%s (%s)" % [str(fx["opponent_abbr"]), "H" if bool(fx["home"]) else "A"],
			"the log row does not name the opponent and the venue")
		assert_eq(str(cells[3]), "%d – %d" % [int(fx["home_goals"]), int(fx["away_goals"])],
			"the log row does not carry the score")
		assert_eq(str(cells[4]), _parts(str(fx["fixture_id"]), id),
			"the log row does not carry every event he had in that match")
		assert_eq(str((rows[i]["target"] as Dictionary).get("page", "")), WikiModel.TEAM,
			"a log row is not a door")
		assert_eq(str((rows[i]["target"] as Dictionary).get("id", "")), str(fx["opponent_id"]),
			"a log row does not open the club he played")


func test_the_log_lists_the_newest_match_first_and_caps_the_list() -> void:
	var id := str(scorer["player_id"])
	var club_id := _club_of(id)
	var played := LeagueLedger.player_events(id, club_id, 20)
	var last := ""
	for fx in played:
		if last != "":
			assert_lte(str(fx["kickoff"]), last, "the log is not newest first")
		last = str(fx["kickoff"])
	var one := LeagueLedger.player_events(id, club_id, 1)
	assert_eq(one.size(), mini(played.size(), 1), "the list ignores its cap")
	if played.size() > 1:
		assert_eq(str(one[0]["fixture_id"]), str(played[0]["fixture_id"]),
			"the cap does not keep the most recent match")


func test_a_player_with_no_events_says_so() -> void:
	var club_id := str(season.record.fixtures.all(1)[0]["home_club_id"])
	var squad := PLRepository.shared().squad(club_id)
	var quiet := ""
	for p in squad:
		var line := PLRepository.shared().sim_player(str(p["id"]))
		if int(line.get("apps", 0)) > 0 and _log_rows(WikiModel.page(WikiModel.PLAYER, str(p["id"]))).size() == 0:
			quiet = str(p["id"])
			break
	if quiet == "":
		return
	var text := _flatten(WikiModel.page(WikiModel.PLAYER, quiet))
	assert_true(text.contains("IN FOOTBALLSIM  ·  MATCH BY MATCH"),
		"a quiet player lost the log's heading")
	assert_true(text.contains("NO GOALS OR CARDS YET"), "a quiet player has no empty state")


func test_a_capped_log_says_older_matches_are_left_out() -> void:
	var found := PLDatabase.rows(
		"SELECT player_id, club_id, COUNT(DISTINCT fixture_id) AS n FROM match_event "
		+ "GROUP BY player_id HAVING n > 1 LIMIT 1;")
	var id := str(scorer["player_id"])
	var club_id := _club_of(id)
	if not found.is_empty():
		id = str(found[0]["player_id"])
		club_id = str(found[0]["club_id"])
	var all := LeagueLedger.player_events(id, club_id, 20)
	var cap: int = 1 if all.size() > 1 else 0
	var blocks := WikiPlayerLog.blocks(id, club_id, cap)
	var rows: Array = []
	var notes: Array = []
	for block in blocks:
		if str(block["k"]) == "table":
			rows = block["rows"]
		if str(block["k"]) == "note":
			notes.append(str(block["text"]))
	assert_eq(rows.size(), mini(all.size(), cap), "the capped log shows more than its cap")
	assert_eq(not notes.is_empty(), all.size() > cap,
		"a capped log does not say whether it left matches out")


func test_the_part_line_names_every_kind() -> void:
	assert_eq(WikiPlayerLog.parts([
		{"kind": "goal", "penalty": false}, {"kind": "goal", "penalty": true},
		{"kind": "assist", "penalty": false}, {"kind": "yellow", "penalty": false},
	]), "2 GOALS (1 PEN)  ·  1 ASSIST  ·  BOOKED", "a mixed match does not read as one line")
	assert_eq(WikiPlayerLog.parts([{"kind": "red", "penalty": false},
		{"kind": "injury", "penalty": false}]), "SENT OFF  ·  INJURED",
		"a dismissal and an injury lose their names")
	assert_eq(WikiPlayerLog.parts([{"kind": "goal", "penalty": false}]), "1 GOAL",
		"one goal is not singular")
	assert_eq(WikiPlayerLog.parts([]), "", "a match with no events reads as a line")


func test_a_home_fixture_reads_as_home_and_empty_asks_read_nothing() -> void:
	var row := PLDatabase.row(
		"SELECT e.player_id, e.club_id, e.fixture_id FROM match_event e "
		+ "JOIN league_fixture f ON f.id = e.fixture_id "
		+ "WHERE e.club_id = f.home_club_id AND f.status = 'played' LIMIT 1;")
	assert_false(row.is_empty(), "no played fixture had a home event")
	var id := str(row["player_id"])
	var played := LeagueLedger.player_events(id, str(row["club_id"]), 20)
	var at_home := {}
	for fx in played:
		if str(fx["fixture_id"]) == str(row["fixture_id"]):
			at_home = fx
	assert_true(bool(at_home.get("home", false)), "his own fixture does not read as home")
	var hit := ""
	for log_row in _log_rows(WikiModel.page(WikiModel.PLAYER, id)):
		if str(log_row["cells"][0]) == FixtureCalendar.day_label(str(at_home["kickoff"])):
			hit = str(log_row["cells"][2])
	assert_true(hit.ends_with("(H)"), "the page does not mark the match as home")
	assert_eq(LeagueLedger.player_events("", "MUN", 5), [], "a read with no player answered")
	assert_eq(LeagueLedger.player_events(id, "", 5), [], "a read with no club answered")


func test_without_a_season_the_page_keeps_no_log() -> void:
	season.close()
	PLRepository.shared().invalidate()
	var text := _flatten(WikiModel.page(WikiModel.PLAYER, str(scorer["player_id"])))
	assert_false(text.contains("MATCH BY MATCH"), "a closed season still lists its matches")
	season = LeagueSeason.open(LeagueSave.current.slug if LeagueSave.current != null else season.save.slug)
	assert_not_null(season, "the save could not be reopened")


func _club_of(player_id: String) -> String:
	return str(PLRepository.shared().player(player_id).get("club_id", ""))


func _log_rows(page: Dictionary) -> Array:
	var seen := false
	for block in page["blocks"]:
		var kind := str(block["k"])
		if kind == "section":
			if seen:
				return []
			seen = str(block["text"]) == "IN FOOTBALLSIM  ·  MATCH BY MATCH"
			continue
		if seen and kind == "table":
			return block["rows"]
		if seen:
			return []
	return []


func _parts(fixture_id: String, player_id: String) -> String:
	var rows := PLDatabase.rows(
		"SELECT kind, penalty FROM match_event WHERE fixture_id = ? AND player_id = ?;",
		[fixture_id, player_id])
	var goals := 0
	var pens := 0
	var assists := 0
	var yellow := 0
	var red := 0
	var injury := 0
	for row in rows:
		var kind := str(row["kind"])
		if kind == "goal":
			goals += 1
			pens += int(row.get("penalty", 0))
		elif kind == "assist":
			assists += 1
		elif kind == "yellow":
			yellow += 1
		elif kind == "red":
			red += 1
		elif kind == "injury":
			injury += 1
	var out: Array = []
	if goals > 0:
		var text := "%d GOALS" % goals
		if goals == 1:
			text = "1 GOAL"
		if pens > 0:
			text += " (%d PEN)" % pens
		out.append(text)
	if assists > 0:
		var assist_text := "%d ASSISTS" % assists
		if assists == 1:
			assist_text = "1 ASSIST"
		out.append(assist_text)
	if yellow > 0:
		out.append("BOOKED")
	if red > 0:
		out.append("SENT OFF")
	if injury > 0:
		out.append("INJURED")
	return "  ·  ".join(PackedStringArray(out))


func _flatten(page: Dictionary) -> String:
	var text := "%s %s" % [page.get("title", ""), page.get("subtitle", "")]
	for block in page.get("blocks", []):
		text += " " + str(block.get("text", ""))
		for row in block.get("rows", []):
			text += " " + " ".join(PackedStringArray(row.get("cells", [])))
		for item in block.get("items", []):
			text += " " + str(item)
	return text


func _clean() -> void:
	for folder in [SAVE_DIR, CACHE_DIR]:
		TestScratch.clear(folder)
