extends GdToolsTest

## The pre-match briefing (#157): what it reads, what it draws room for, and
## every way in and out of it — league Watch, single-match KICK OFF, SKIP, the
## ten second auto-advance and BACK.

var SAVE_DIR := TestScratch.dir("saves_test_prematch")
var CACHE_DIR := TestScratch.dir("cache_test_prematch")
const SEED := 909

var season: LeagueSeason = null

## A play scene stand-in: the briefing host and the picker only touch these.
class StubGame extends Node:
	var prematch = null
	var paused := false
	var touch := false
	var chrome_scale := 1.0
	var home_id := "MUN"
	var away_id := "MCI"
	var select_open := false
	var select_from_menu := false
	var sel_layer = CanvasLayer.new()
	var hud_layer = null
	var menus = null
	var selector = null
	var seeded := 1000
	var match_started := false
	func new_match(seed: int) -> void:
		seeded = seed
		match_started = true

## The picker's own sheet, reduced to the two fields `FixtureSheet.open` writes.
class StubSelector extends RefCounted:
	var back_to_menu := false
	var visible := true
	var clubs := Vector2.ZERO
	func setup(home: String, away: String) -> void:
		clubs = Vector2(0, 0)
		back_to_menu = false

## Records the request and both callbacks the way `PreMatchHost.ask` would.
class StubPreMatch extends RefCounted:
	var asked: Dictionary = {}
	var kick := Callable()
	var back := Callable()
	func ask(req: Dictionary, on_kick: Callable, on_back: Callable) -> void:
		asked = req
		kick = on_kick
		back = on_back

func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	TestScratch.clear(SAVE_DIR)
	TestScratch.clear(CACHE_DIR)
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	season = LeagueSeason.create("Briefing Season", "generated", "fixture_days", SEED)

func after_all() -> void:
	if season != null:
		season.close()
	TestScratch.clear(SAVE_DIR)
	TestScratch.clear(CACHE_DIR)
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func _fixture() -> Dictionary:
	var rows := season.plan()
	return rows[0] if not rows.is_empty() else {}

# -------------------------------------------------------------------- model ---

func test_a_league_briefing_reads_the_fixture_and_the_season() -> void:
	var fx := _fixture()
	var view := PreMatchModel.build(str(fx["home_club_id"]), str(fx["away_club_id"]), fx, season)
	assert_false(view.is_empty(), "the briefing came back empty")
	assert_eq((view["home_xi"] as Array).size(), 11, "the home XI is not eleven")
	assert_eq((view["away_xi"] as Array).size(), 11, "the away XI is not eleven")
	assert_eq(str(view["kick"]), "CONTINUE", "a league watch does not say CONTINUE")
	assert_true(str(view["caption"]).begins_with("PREMIER LEAGUE"), "the caption lost the competition")
	assert_true(str(view["date_label"]) != "", "the briefing has no date")
	assert_true(str((view["home_quote"] as Dictionary).get("line", "")) != "", "no home quote")
	assert_true(str((view["news"] as Dictionary).get("line", "")) != "", "no desk blurb")
	assert_true(str(view["home_captain"]) != "", "no captain was marked")

func test_a_single_match_briefing_says_kick_off_and_has_no_absences() -> void:
	var view := PreMatchModel.build("MUN", "MCI", {}, null)
	assert_eq(str(view["kick"]), "KICK OFF", "a single match does not say KICK OFF")
	assert_eq(str(view["caption"]), "FRIENDLY · SINGLE MATCH", "a single match is not a friendly")
	assert_eq((view["home_absences"] as Array).size(), 0, "a friendly has season absences")
	assert_eq(str(view["date_label"]), "", "a friendly carries a league date")

func test_the_briefing_names_who_is_out_and_drops_them_from_the_xi() -> void:
	var club := str(_fixture()["home_club_id"])
	var player: Dictionary = TeamData.get_team(club)["starters"][0]
	var id := str(player["id"])
	SeasonAvailability.suspend(id, club, 2, "red", "2026-08-15")
	var view := PreMatchModel.build(club, "MCI", _fixture(), season)
	var absences: Array = view["home_absences"]
	assert_eq(absences.size(), 1, "the briefing did not list the suspension")
	assert_eq(str((absences[0] as Dictionary)["label"]), "2 MATCHES", "the ban reads wrong")
	for p in view["home_xi"]:
		assert_ne(str(p["id"]), id, "a suspended player was named in the XI")
	PLDatabase.execute("DELETE FROM league_absence;")

func test_the_quotes_and_blurb_are_seeded_from_the_fixture() -> void:
	var fx := _fixture()
	var one := PreMatchModel.build(str(fx["home_club_id"]), str(fx["away_club_id"]), fx, season)
	var two := PreMatchModel.build(str(fx["home_club_id"]), str(fx["away_club_id"]), fx, season)
	assert_eq(str((one["home_quote"] as Dictionary)["line"]), str((two["home_quote"] as Dictionary)["line"]),
		"the same fixture read two different quotes")
	assert_eq(str((one["news"] as Dictionary)["line"]), str((two["news"] as Dictionary)["line"]),
		"the same fixture read two different blurbs")

func test_a_derby_reads_as_one() -> void:
	assert_true(PreMatchCopy.derby("MUN", "MCI"), "a derby is not recognised")
	assert_true(PreMatchCopy.derby("MCI", "MUN"), "the derby depends on the order")
	assert_false(PreMatchCopy.derby("MUN", "LIV"), "a non-derby was called a derby")
	var ctx := {"derby": true, "matchday": 4, "home_position": 2, "away_position": 3}
	var news := PreMatchCopy.news(11, TeamData.get_team("MUN"), TeamData.get_team("MCI"), ctx)
	assert_eq(str(news["title"]), "DERBY DAY", "a derby blurb does not say derby")

func test_every_quote_pack_can_be_reached() -> void:
	var home := TeamData.get_team("MUN")
	var away := TeamData.get_team("MCI")
	var derby := PreMatchCopy.quote(3, home, away, {"derby": true, "form": "WWWWW", "position": 1})
	assert_true(str(derby["line"]) != "", "a derby quote is empty")
	var good := PreMatchCopy.quote(3, home, away, {"form": "WWWDW", "position": 2})
	assert_true(_in_pack(PreMatchCopy.FORM_GOOD_LINES, str(good["line"]), "{wins}", "4"),
		"a winning run did not read as form")
	var poor := PreMatchCopy.quote(3, home, away, {"form": "LLDLL", "position": 8})
	assert_true(_in_pack(PreMatchCopy.FORM_POOR_LINES, str(poor["line"]), "", ""),
		"a losing run did not read as a bad run")
	var pressure := PreMatchCopy.quote(3, home, away, {"form": "WDDWD", "position": 18})
	assert_true(_in_pack(PreMatchCopy.PRESSURE_LINES, str(pressure["line"]), "{position}", "18"),
		"table pressure did not name the place")
	var plain := PreMatchCopy.quote(3, home, away, {"form": "WDDWD", "position": 7})
	assert_true(_in_pack(PreMatchCopy.PLAIN_LINES, str(plain["line"]), "{opponent}", str(away["name"])),
		"the plain quote is empty")
	assert_eq(str(good["by"]), str(home["manager"]).to_upper(), "the quote is not the manager's")

## True when `line` is one of `pack`'s templates with its placeholder filled.
func _in_pack(pack: Array, line: String, placeholder: String, value: String) -> bool:
	for template in pack:
		var filled := str(template) if placeholder == "" else str(template).replace(placeholder, value)
		if filled == line:
			return true
	return false

func test_every_blurb_pack_can_be_reached() -> void:
	var home := TeamData.get_team("MUN")
	var away := TeamData.get_team("MCI")
	var top := PreMatchCopy.news(1, home, away, {"home_position": 2, "away_position": 3, "matchday": 9})
	assert_eq(str(top["title"]), "TITLE RACE", "a top-four meeting is not a title-race blurb")
	var bottom := PreMatchCopy.news(1, home, away, {"home_position": 17, "away_position": 19})
	assert_eq(str(bottom["title"]), "SURVIVAL WATCH", "a relegation meeting is not survival watch")
	var plain := PreMatchCopy.news(1, home, away, {"home_position": 9, "away_position": 11, "matchday": 12})
	assert_eq(str(plain["title"]), "MATCHDAY BRIEFING", "an ordinary game is not a briefing")
	assert_true(str(plain["line"]).contains("matchday 12"), "the blurb lost its matchday")

# ------------------------------------------------------------------- screen ---

func test_the_doors_lay_out_inside_the_window() -> void:
	var screen := PreMatchScreen.new()
	screen.setup(PreMatchModel.build("MUN", "MCI", {}, null))
	for vp in [Vector2(1280.0, 720.0), Vector2(390.0, 780.0), Vector2(1024.0, 600.0)]:
		var rects := screen.layout(vp)
		var buttons: Array = rects["buttons"]
		assert_eq(buttons.size(), 3, "the briefing is missing a door")
		for b in buttons:
			var r: Rect2 = b["rect"]
			assert_gte(r.position.x, 0.0, "a door left the window")
			assert_lte(r.end.x, vp.x + 0.01, "a door ran past the right edge")
			assert_lte(r.end.y, vp.y + 0.01, "a door ran past the bottom edge")
		var kick: Rect2 = (buttons[2] as Dictionary)["rect"]
		var skip: Rect2 = (buttons[1] as Dictionary)["rect"]
		assert_false(kick.intersects(skip), "CONTINUE and SKIP overlap")
		var pitch: Rect2 = rects["home_pitch"]
		assert_gt(pitch.size.y, 40.0, "the pitch has no room on a small window")
		assert_lte(pitch.end.y, (rects["home_out"] as Rect2).position.y,
			"the pitch runs into the OUT list")
		assert_lte((rects["home_out"] as Rect2).end.y, (rects["home_quote"] as Rect2).position.y,
			"the OUT list runs into the quote")
		assert_lte((rects["home_quote"] as Rect2).end.y, (rects["news"] as Rect2).position.y,
			"the quote runs into the news strip")
	screen.free()

func test_a_press_reaches_its_door() -> void:
	var screen := PreMatchScreen.new()
	screen.setup(PreMatchModel.build("MUN", "MCI", {}, null))
	screen.size = Vector2(1280.0, 720.0)
	var rects := screen.layout(Vector2(1280.0, 720.0))
	screen.buttons = rects["buttons"]
	for b in rects["buttons"]:
		var r: Rect2 = b["rect"]
		assert_eq(screen.button_at(r.get_center()), str(b["id"]), "a door is not under its own centre")
	assert_eq(screen.button_at(Vector2(4.0, 4.0)), "", "empty space answered a press")
	screen.free()

func test_skip_holds_the_briefing_and_never_starts_the_match() -> void:
	var screen := PreMatchScreen.new()
	screen.setup({"auto_seconds": 10.0, "kick": "KICK OFF"})
	var kicked := [0]
	screen.kick_off.connect(func(): kicked[0] += 1)
	screen.click("skip")
	assert_true(screen.held, "SKIP did not hold the briefing")
	assert_eq(screen.auto_left, 0.0, "SKIP left the clock running")
	screen._process(30.0)
	assert_eq(kicked[0], 0, "a held briefing started the match anyway")
	assert_false(screen.key(KEY_ENTER) == false, "ENTER was not taken")
	assert_eq(kicked[0], 1, "ENTER did not start the match")
	screen.free()

func test_the_briefing_advances_itself_after_ten_seconds() -> void:
	var screen := PreMatchScreen.new()
	screen.setup({"auto_seconds": 10.0, "kick": "KICK OFF"})
	var kicked := [0]
	screen.kick_off.connect(func(): kicked[0] += 1)
	screen._process(4.0)
	assert_eq(kicked[0], 0, "the briefing advanced early")
	screen._process(7.0)
	assert_eq(kicked[0], 1, "the briefing never advanced")
	screen.free()

func test_back_leaves_without_starting() -> void:
	var screen := PreMatchScreen.new()
	screen.setup({"auto_seconds": 10.0, "kick": "KICK OFF"})
	var left := [0]
	screen.cancelled.connect(func(): left[0] += 1)
	assert_true(screen.key(KEY_ESCAPE), "ESC was not taken")
	assert_eq(left[0], 1, "ESC did not leave the briefing")
	screen.click("back")
	assert_eq(left[0], 2, "BACK did not leave the briefing")
	screen.free()

func test_the_short_name_is_the_last_word() -> void:
	assert_eq(PreMatchPitch.short_name("Bruno Fernandes"), "FERNANDES", "the pitch name is not the last word")
	assert_eq(PreMatchPitch.short_name("Rasmus"), "RASMUS", "a one-word name was cut")

# -------------------------------------------------------------------- hosts ---

func test_the_picker_confirms_into_the_briefing_and_back_reopens_it() -> void:
	var game := StubGame.new()
	game.prematch = StubPreMatch.new()
	game.selector = StubSelector.new()
	var sheet := FixtureSheet.new(game)
	sheet.confirm("MUN", "MCI")
	assert_false(game.prematch.asked.is_empty(), "KICK OFF skipped the briefing")
	assert_false(game.match_started, "the match started before the briefing")
	assert_eq(str(game.prematch.asked["kick"]), "KICK OFF", "a single match does not say KICK OFF")
	# KICK OFF on the briefing starts the match.
	game.prematch.kick.call()
	assert_true(game.match_started, "the briefing's KICK OFF did not start the match")
	# BACK returns to the picker, not to a match.
	game.match_started = false
	sheet.confirm("MUN", "MCI")
	game.prematch.back.call()
	assert_false(game.match_started, "BACK from the briefing started the match")
	# The picker's own doors still start a match and come back on their clubs.
	sheet.reopen()
	assert_true(game.select_open, "the picker did not come back")
	sheet.start("MUN", "MCI")
	assert_true(game.match_started, "the picker's start did not start the match")
	assert_false(game.select_open, "the picker stayed open over a match")
	game.free()

func test_a_league_watch_opens_the_briefing_first() -> void:
	var fx := _fixture()
	var game := StubGame.new()
	game.prematch = StubPreMatch.new()
	var host := LeagueHost.new()
	host.attach(game)
	host.season = season
	var held := str(fx["id"])
	season.set_watch(held, true)
	season.advance()
	season.start_watch(held)
	host._on_match_requested(str(fx["home_club_id"]), str(fx["away_club_id"]), held)
	assert_false(game.prematch.asked.is_empty(), "a league watch skipped the briefing")
	assert_eq(str(game.prematch.asked["kick"]), "CONTINUE", "a league watch does not say CONTINUE")
	assert_false(game.match_started, "the watched match started before the briefing")
	game.prematch.back.call()
	assert_eq(season.watching_fixture, "", "BACK left the season waiting for the fixture")
	assert_false(game.match_started, "BACK started the watched match")
	season.start_watch(held)
	host._on_match_requested(str(fx["home_club_id"]), str(fx["away_club_id"]), held)
	game.prematch.kick.call()
	assert_true(game.match_started, "CONTINUE did not start the watched match")
	game.free()

func test_the_host_shows_and_hides_its_layer() -> void:
	var game := StubGame.new()
	var host := PreMatchHost.new()
	host.attach(game)
	host.build()
	assert_false(host.is_open(), "the briefing opened on its own")
	host.ask(PreMatchModel.build("MUN", "MCI", {}, null), Callable(), Callable())
	assert_true(host.is_open(), "the briefing did not open")
	assert_true(game.paused, "the scene was not paused under the briefing")
	host.close()
	assert_false(host.is_open(), "the briefing did not close")
	assert_false(host.handle_input(InputEventKey.new(), Vector2.ZERO), "a closed briefing took an event")
	game.free()

func test_the_host_runs_one_callback_per_press() -> void:
	var game := StubGame.new()
	var host := PreMatchHost.new()
	host.attach(game)
	host.build()
	var calls := [0, 0]
	host.ask(PreMatchModel.build("MUN", "MCI", {}, null),
		func(): calls[0] += 1, func(): calls[1] += 1)
	host.sync(Transform2D.IDENTITY, 1.5, true)
	assert_eq(host.screen.ui_scale, 1.5, "the host did not hand its scale to the briefing")
	assert_true(host.screen.touch, "the host did not hand touch to the briefing")
	host.screen.click("kick")
	assert_eq(calls[0], 1, "KICK OFF did not run its callback once")
	assert_false(host.is_open(), "the briefing stayed up after a kick")
	host.ask(PreMatchModel.build("MUN", "MCI", {}, null),
		func(): calls[0] += 1, func(): calls[1] += 1)
	host.screen.click("back")
	assert_eq(calls[1], 1, "BACK did not run its callback once")
	assert_eq(calls[0], 1, "BACK ran the kick callback")
	game.free()

func test_the_briefing_reads_form_and_places_once_results_are_in() -> void:
	var played: Dictionary = {}
	for fx in season.record.fixtures.all():
		if str(fx["status"]) == "played":
			played = fx
			break
	assert_false(played.is_empty(), "no fixture was played to read form from")
	var view := PreMatchModel.build(str(played["home_club_id"]), str(played["away_club_id"]), {}, season)
	assert_true(str(view["home_form"]).length() > 0, "the briefing has no form line")
	assert_gte(int(view["home_position"]), 1, "the home place is missing")
	assert_lte(int(view["home_position"]), 20, "the home place is out of the table")
