extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_test_prematch")
var CACHE_DIR := TestScratch.dir("cache_test_prematch")
const SEED := 909

var season: LeagueSeason = null


class StubGame extends Node:
	var prematch = null
	var paused := false
	var touch := false
	var chrome_scale := 1.0
	var home_id := "ENG-MUN1"
	var away_id := "ENG-MCI1"
	var select_open := false
	var select_from_menu := false
	var sel_layer = CanvasLayer.new()
	var hud_layer = null
	var menus = null
	var selector = null
	var seeded := 1000
	var match_started := false
	var engine = null
	func new_match(seed: int) -> void:
		seeded = seed
		match_started = true


class StubSelector extends RefCounted:
	var back_to_menu := false
	var visible := true
	var clubs := Vector2.ZERO
	var winner_mode := "draw"
	func setup(home: String, away: String) -> void:
		clubs = Vector2(0, 0)
		back_to_menu = false


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
	var view := PreMatchModel.build("ENG-MUN1", "ENG-MCI1", {}, null)
	assert_eq(str(view["kick"]), "KICK OFF", "a single match does not say KICK OFF")
	assert_eq(str(view["caption"]), MatchBilling.FRIENDLY_CAPTION,
		"a single match is not a league fixture")
	assert_eq((view["home_absences"] as Array).size(), 0, "a friendly has season absences")
	assert_eq(str(view["date_label"]), "", "a friendly carries a league date")

func test_the_briefing_names_who_is_out_and_drops_them_from_the_xi() -> void:
	var club := str(_fixture()["home_club_id"])
	var player: Dictionary = TeamData.get_team(club)["starters"][0]
	var id := str(player["id"])
	SeasonAvailability.suspend(id, club, 2, "red", "2026-08-15")
	var view := PreMatchModel.build(club, "ENG-MCI1", _fixture(), season)
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
	assert_true(PreMatchCopy.derby("ENG-MUN1", "ENG-MCI1"), "a derby is not recognised")
	assert_true(PreMatchCopy.derby("ENG-MCI1", "ENG-MUN1"), "the derby depends on the order")
	assert_false(PreMatchCopy.derby("ENG-MUN1", "ENG-LIV1"), "a non-derby was called a derby")
	var ctx := {"derby": true, "matchday": 4, "home_position": 2, "away_position": 3}
	var news := PreMatchCopy.news(11, TeamData.get_team("ENG-MUN1"), TeamData.get_team("ENG-MCI1"), ctx)
	assert_eq(str(news["title"]), "DERBY DAY", "a derby blurb does not say derby")

func test_every_quote_pack_can_be_reached() -> void:
	var home := TeamData.get_team("ENG-MUN1")
	var away := TeamData.get_team("ENG-MCI1")
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


func _in_pack(pack: Array, line: String, placeholder: String, value: String) -> bool:
	for template in pack:
		var filled := str(template) if placeholder == "" else str(template).replace(placeholder, value)
		if filled == line:
			return true
	return false

func test_every_blurb_pack_can_be_reached() -> void:
	var home := TeamData.get_team("ENG-MUN1")
	var away := TeamData.get_team("ENG-MCI1")
	var top := PreMatchCopy.news(1, home, away, {"home_position": 2, "away_position": 3, "matchday": 9})
	assert_eq(str(top["title"]), "TITLE RACE", "a top-four meeting is not a title-race blurb")
	var bottom := PreMatchCopy.news(1, home, away, {"home_position": 17, "away_position": 19})
	assert_eq(str(bottom["title"]), "SURVIVAL WATCH", "a relegation meeting is not survival watch")
	var plain := PreMatchCopy.news(1, home, away, {"home_position": 9, "away_position": 11, "matchday": 12})
	assert_eq(str(plain["title"]), "MATCHDAY BRIEFING", "an ordinary game is not a briefing")
	assert_true(str(plain["line"]).contains("matchday 12"), "the blurb lost its matchday")


func test_the_doors_lay_out_inside_the_window() -> void:
	var screen := PreMatchScreen.new()
	screen.setup(PreMatchModel.build("ENG-MUN1", "ENG-MCI1", {}, null))
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
	screen.setup(PreMatchModel.build("ENG-MUN1", "ENG-MCI1", {}, null))
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


func test_the_picker_asks_for_a_decided_match_only_when_chosen() -> void:
	var picker = load("res://scripts/ui/team_select.gd").new()
	assert_eq(str(picker.winner_mode), "draw", "a friendly does not default to a draw")
	var mode_ids: Array = []
	for spec in LeagueChrome.winner_rects(Vector2(1280, 720), 500.0):
		mode_ids.append(str(spec["id"]))
		assert_gt((spec["rect"] as Rect2).position.y, 500.0,
			"the winner control covers the club cards")
	assert_eq(mode_ids, ["draw", "extra"], "the winner control is missing a mode")
	picker.click("win:extra")
	assert_eq(str(picker.winner_mode), "extra", "the picker did not take extra time")
	picker.click("win:draw")
	assert_eq(str(picker.winner_mode), "draw", "the picker did not go back to a draw")

	for vp in [Vector2(411, 780), Vector2(914, 411)]:
		var last: Rect2 = LeagueChrome.winner_rects(vp, vp.y * 0.30)[1]["rect"]
		assert_lte(last.end.x, vp.x - 8.0, "the winner control runs off the sheet")
		assert_lte(last.end.y, vp.y - 128.0, "the winner control reaches into the doors")


func test_a_phone_picker_lays_its_chips_and_pills_for_a_finger() -> void:
	var rows: int = 1 + PLCompetitions.active().size()
	for vp in [Vector2(914, 411), Vector2(640, 360), Vector2(411, 914)]:
		var chips: Array = LeagueChrome.picker_chip_rects(vp, rows, true)
		assert_eq(chips.size(), rows, "the phone chip row lost a competition at %s" % vp)
		for i in range(chips.size()):
			var r: Rect2 = chips[i]
			assert_gte(r.size.y, UiChrome.TAP_H, "a phone chip is under a finger at %s" % vp)
			if i > 0:
				assert_gte(r.position.x, (chips[i - 1] as Rect2).end.x,
					"two phone chips overlap at %s" % vp)
		var head: Dictionary = LeagueChrome.picker_header(vp, true)
		var band: Rect2 = LeagueChrome.picker_chips_band(vp, true)
		assert_gt(band.position.y, float(head["wordmark_y"]) + 6.0,
			"the phone chips sit on the wordmark at %s" % vp)
		var back := Rect2(24.0, 12.0, 116.0, 44.0)
		var league := Rect2(vp.x - 24.0 - 138.0, 12.0, 138.0, 44.0)
		assert_false(band.intersects(back), "the MENU door covers the phone chips at %s" % vp)
		assert_false(band.intersects(league), "the LEAGUE door covers the phone chips at %s" % vp)
		var card_top: float = maxf(vp.y * 0.42 - minf(vp.y * 0.32, 250.0) * 0.5,
			float(head["rule_y"]) + 6.0)
		assert_lt(band.end.y, card_top, "the phone chips reach the club cards at %s" % vp)
		var card_bottom: float = card_top + minf(vp.y * 0.32, 250.0)
		var pills: Array = LeagueChrome.winner_rects(vp, card_bottom, true)
		for spec in pills:
			assert_gte((spec["rect"] as Rect2).size.y, UiChrome.TAP_H,
				"the %s pill is under a finger at %s" % [spec["id"], vp])
		var doors: Array = LeagueChrome.picker_doors(vp, card_bottom, true)
		for pill in pills:
			for door in doors:
				assert_false((pill["rect"] as Rect2).intersects(door["rect"] as Rect2),
					"the %s door sits on the %s pill at %s" % [door["id"], pill["id"], vp])
		for door in doors:
			var d: Rect2 = door["rect"]
			assert_gte(d.size.y, UiChrome.TAP_H, "a picker door is under a finger at %s" % vp)
			assert_gte(d.position.y, LeagueChrome.winner_bottom(card_bottom, true),
				"a picker door rose into the pills at %s" % vp)
			assert_lte(d.end.y, vp.y, "a picker door runs off the sheet at %s" % vp)


func test_the_picker_doors_never_cover_the_winner_control() -> void:
	for vp in [Vector2(1600, 900), Vector2(1280, 800), Vector2(1024, 600),
			Vector2(913, 411), Vector2(800, 480), Vector2(640, 360), Vector2(640, 300),
			Vector2(411, 914), Vector2(375, 812)]:
		var card_bottom: float = vp.y * 0.42
		var chips: Array = LeagueChrome.winner_rects(vp, card_bottom)
		var doors: Array = LeagueChrome.picker_doors(vp, card_bottom)
		assert_eq(doors.size(), 2, "the picker lost a door at %s" % vp)
		for chip in chips:
			for door in doors:
				assert_false((chip["rect"] as Rect2).intersects(door["rect"] as Rect2),
					"%s sits under the %s door at %s" % [chip["id"], door["id"], vp])
		for door in doors:
			var r: Rect2 = door["rect"]
			assert_gte(r.size.y, 50.0, "a picker door shrank to fit at %s" % vp)
			assert_gte(r.position.y, LeagueChrome.winner_bottom(card_bottom),
				"a picker door rose into the control at %s" % vp)
			assert_lte(r.end.x, vp.x, "a picker door runs off the sheet at %s" % vp)


func test_the_picker_chips_never_cut_through_the_heading() -> void:
	for vp in [Vector2(1600, 900), Vector2(1280, 720), Vector2(1096, 493),
			Vector2(914, 411), Vector2(640, 360), Vector2(411, 914)]:
		var head: Dictionary = LeagueChrome.picker_header(vp)
		var band: Rect2 = LeagueChrome.picker_chips_band(vp)
		var bold: FontFile = load("res://fonts/BarlowCondensed-SemiBold.ttf")

		if bool(head["title"]):
			var size := int(head["title_size"])
			var ink_h: float = bold.get_ascent(size) - bold.get_ascent(size) * 0.28
			var title_rect := Rect2(0.0, float(head["title_y"]) - ink_h, vp.x, ink_h)
			assert_false(title_rect.intersects(band),
				"the SELECT FIXTURE heading shares a band with the chips at %s" % vp)

		assert_gt(band.position.y, float(head["wordmark_y"]) + 6.0,
			"the chips sit on the wordmark at %s" % vp)
		var card_top: float = vp.y * 0.42 - minf(vp.y * 0.32, 250.0) * 0.5
		assert_lt(band.end.y, card_top, "the chips reach the club cards at %s" % vp)
		assert_eq(band.size.y, LeagueChrome.PICKER_CHIP_H, "the chip band changed height at %s" % vp)


func test_every_painted_chip_answers_a_press() -> void:
	for vp in [Vector2(1600, 900), Vector2(1096, 493), Vector2(914, 411), Vector2(640, 360)]:
		var rows: int = 1 + PLCompetitions.active().size()
		var rects: Array = LeagueChrome.picker_chip_rects(vp, rows)
		assert_eq(rects.size(), rows, "the chip row lost a competition at %s" % vp)
		var band: Rect2 = LeagueChrome.picker_chips_band(vp)
		for i in range(rects.size()):
			var r: Rect2 = rects[i]
			assert_gte(r.position.y, band.position.y - 0.5, "a chip rose out of its band at %s" % vp)
			assert_lte(r.end.y, band.end.y + 0.5, "a chip fell out of its band at %s" % vp)
			assert_gte(r.size.x, 40.0, "a chip shrank below a readable width at %s" % vp)
			assert_lte(r.end.x, vp.x - 24.0 + 0.5, "a chip ran off the sheet at %s" % vp)
			if i > 0:
				assert_gte(r.position.x, (rects[i - 1] as Rect2).end.x,
					"two chips overlap, so one press answers two doors at %s" % vp)

func test_the_picker_hands_a_decided_match_to_the_engine() -> void:
	var game := StubGame.new()
	game.selector = StubSelector.new()
	game.selector.winner_mode = "extra"
	game.engine = StubEngine.new()
	FixtureSheet.new(game).start("ENG-MUN1", "ENG-MCI1")
	assert_true(game.engine.requires_winner, "the picker did not ask the engine for a winner")
	game.selector.winner_mode = "draw"
	game.engine = StubEngine.new()
	FixtureSheet.new(game).start("ENG-MUN1", "ENG-MCI1")
	assert_false(game.engine.requires_winner, "a friendly was forced to a winner")
	game.free()

class StubEngine extends RefCounted:
	var requires_winner := false

func test_the_picker_confirms_into_the_briefing_and_back_reopens_it() -> void:
	var game := StubGame.new()
	game.prematch = StubPreMatch.new()
	game.selector = StubSelector.new()
	var sheet := FixtureSheet.new(game)
	sheet.confirm("ENG-MUN1", "ENG-MCI1")
	assert_false(game.prematch.asked.is_empty(), "KICK OFF skipped the briefing")
	assert_false(game.match_started, "the match started before the briefing")
	assert_eq(str(game.prematch.asked["kick"]), "KICK OFF", "a single match does not say KICK OFF")

	game.prematch.kick.call()
	assert_true(game.match_started, "the briefing's KICK OFF did not start the match")

	game.match_started = false
	sheet.confirm("ENG-MUN1", "ENG-MCI1")
	game.prematch.back.call()
	assert_false(game.match_started, "BACK from the briefing started the match")

	sheet.reopen()
	assert_true(game.select_open, "the picker did not come back")
	sheet.start("ENG-MUN1", "ENG-MCI1")
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
	host.watch.on_match_requested(str(fx["home_club_id"]), str(fx["away_club_id"]), held)
	assert_false(game.prematch.asked.is_empty(), "a league watch skipped the briefing")
	assert_eq(str(game.prematch.asked["kick"]), "CONTINUE", "a league watch does not say CONTINUE")
	assert_false(game.match_started, "the watched match started before the briefing")
	game.prematch.back.call()
	assert_eq(season.watching_fixture, "", "BACK left the season waiting for the fixture")
	assert_false(game.match_started, "BACK started the watched match")
	season.start_watch(held)
	host.watch.on_match_requested(str(fx["home_club_id"]), str(fx["away_club_id"]), held)
	game.prematch.kick.call()
	assert_true(game.match_started, "CONTINUE did not start the watched match")
	game.free()

func test_the_host_shows_and_hides_its_layer() -> void:
	var game := StubGame.new()
	var host := PreMatchHost.new()
	host.attach(game)
	host.build()
	assert_false(host.is_open(), "the briefing opened on its own")
	host.ask(PreMatchModel.build("ENG-MUN1", "ENG-MCI1", {}, null), Callable(), Callable())
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
	host.ask(PreMatchModel.build("ENG-MUN1", "ENG-MCI1", {}, null),
		func(): calls[0] += 1, func(): calls[1] += 1)
	host.sync(Transform2D.IDENTITY, 1.5, true)
	assert_eq(host.screen.ui_scale, 1.5, "the host did not hand its scale to the briefing")
	assert_true(host.screen.touch, "the host did not hand touch to the briefing")
	host.screen.click("kick")
	assert_eq(calls[0], 1, "KICK OFF did not run its callback once")
	assert_false(host.is_open(), "the briefing stayed up after a kick")
	host.ask(PreMatchModel.build("ENG-MUN1", "ENG-MCI1", {}, null),
		func(): calls[0] += 1, func(): calls[1] += 1)
	host.screen.click("back")
	assert_eq(calls[1], 1, "BACK did not run its callback once")
	assert_eq(calls[0], 1, "BACK ran the kick callback")
	game.free()


func _event_key(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	return ev

func _event_motion(at: Vector2) -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	return ev

func _event_click(at: Vector2, pressed: bool) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = at
	return ev

func test_the_host_answers_mouse_and_keys_while_open() -> void:
	var game := StubGame.new()
	var host := PreMatchHost.new()
	host.attach(game)
	host.build()
	var calls := [0, 0]
	host.ask(PreMatchModel.build("ENG-MUN1", "ENG-MCI1", {}, null),
		func(): calls[0] += 1, func(): calls[1] += 1)
	assert_true(host.handle_input(_event_motion(Vector2(10.0, 10.0)), Vector2(10.0, 10.0)),
		"the briefing did not take a hover")
	assert_true(host.handle_input(_event_key(KEY_S), Vector2.ZERO), "the briefing did not take a key")
	assert_true(host.screen.held, "S did not hold the briefing")
	assert_true(host.handle_input(_event_key(KEY_ESCAPE), Vector2.ZERO), "the briefing did not take ESC")
	assert_eq(calls[1], 1, "ESC did not leave the briefing")
	host.ask(PreMatchModel.build("ENG-MUN1", "ENG-MCI1", {}, null),
		func(): calls[0] += 1, func(): calls[1] += 1)
	var kick: Rect2 = (host.screen.layout(host.screen.design_vp())["buttons"][2] as Dictionary)["rect"]
	host.handle_input(_event_click(kick.get_center(), true), kick.get_center())
	host.handle_input(_event_click(kick.get_center(), false), kick.get_center())
	assert_eq(calls[0], 1, "a tap on CONTINUE did not start the match")

	var kicked := [0]
	host.ask({}, func(): kicked[0] += 1, Callable())
	assert_eq(kicked[0], 1, "an empty briefing did not hand straight over")
	assert_false(host.is_open(), "an empty briefing stayed up")
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


func test_a_table_place_reads_as_a_real_ordinal() -> void:
	var want := {
		1: "1st", 2: "2nd", 3: "3rd", 4: "4th", 9: "9th", 10: "10th",
		11: "11th", 12: "12th", 13: "13th", 14: "14th", 20: "20th",
		21: "21st", 22: "22nd", 23: "23rd", 101: "101st", 111: "111th",
	}
	for n in want:
		assert_eq(PreMatchCopy.place(int(n)), str(want[n]), "%d reads wrong" % int(n))
	assert_eq(PreMatchCopy.place(0), "", "an unplaced club was given a place")


	assert_eq(PreMatchScreen.strip_line({"formation": "4-2-3-1"}, 2, "W D L W W"),
		"4-2-3-1 · 2ND · W D L W W", "the club strip lost its ordinal place")
	assert_eq(PreMatchScreen.strip_line({"formation": "4-2-3-1"}, 0, ""), "4-2-3-1",
		"an unplaced club grew a place out of nothing")
	assert_eq(PreMatchScreen.strip_line({}, 11, ""), "11TH", "a place needs its shape to print")


func test_the_briefing_strip_never_prints_a_hard_coded_suffix() -> void:
	for n in [1, 2, 3, 4, 7]:
		var line := PreMatchScreen.strip_line({"formation": "4-2-3-1"}, n, "")
		assert_false(line.ends_with("TH") and n <= 3, "place %d still reads TH" % n)
	assert_eq(PreMatchScreen.strip_line({"formation": "4-2-3-1"}, 1, ""), "4-2-3-1 · 1ST",
		"first place did not read 1ST")
	assert_eq(PreMatchScreen.strip_line({"formation": "4-2-3-1"}, 2, ""), "4-2-3-1 · 2ND",
		"second place did not read 2ND")


func test_a_league_match_names_its_competition_everywhere() -> void:
	var fx := _fixture()
	var view := PreMatchModel.build(str(fx["home_club_id"]), str(fx["away_club_id"]), fx, season)
	var billing := MatchBilling.new()
	billing.bind_fixture(str(fx["home_club_id"]), fx)
	assert_false(billing.friendly, "a league fixture was billed as a friendly")
	assert_eq(str(view["caption"]), "%s · MATCHDAY %d" % [billing.chrome_name(), int(fx["matchday"])],
		"the caption does not name the fixture's own competition and round")
	assert_eq(str(view["competition"]), billing.chrome_name(), "the briefing lost its competition")
	var blurb := str((view["news"] as Dictionary).get("line", ""))
	assert_true(blurb.contains(billing.full_name), "the desk blurb does not name the competition")
	assert_false(blurb.to_lower().contains("friendly"), "a league game was called a friendly")


func test_a_single_match_names_one_competition_on_every_surface() -> void:

	var view := PreMatchModel.build("ENG-MUN1", "ENG-LIV1", {}, null)
	assert_eq(str(view["caption"]), MatchBilling.FRIENDLY_CAPTION, "the caption changed shape")
	assert_eq(str(view["competition"]), MatchBilling.FRIENDLY, "the briefing claims a league")
	assert_eq(int(view["matchday"]), 0, "a friendly was given a matchday")
	assert_true(bool(view["friendly"]), "a single match is not marked a friendly")
	var news: Dictionary = view["news"]
	assert_false(str(news.get("line", "")).contains("matchday"), "a friendly's blurb announces a matchday")
	assert_false(str(news.get("line", "")).contains("Premier League"), "a friendly's blurb names a league")
	assert_eq(str(news.get("title", "")), PreMatchCopy.NEWS_TITLE_FRIENDLY,
		"a friendly's blurb is not filed as a friendly")


func test_a_friendly_derby_promises_no_points() -> void:
	var news := PreMatchCopy.news(5, TeamData.get_team("ENG-MUN1"), TeamData.get_team("ENG-MCI1"),
		{"derby": true, "friendly": true})
	assert_eq(str(news["title"]), PreMatchCopy.NEWS_TITLE_DERBY, "a derby lost its title in a friendly")
	assert_false(str(news["line"]).contains("three points"), "a friendly promised league points")
	assert_true(str(news["line"]).contains("friendly"), "a friendly derby does not say friendly")


func test_a_friendly_briefing_speaks_as_a_friendly() -> void:
	var home := TeamData.get_team("ENG-MUN1")
	var away := TeamData.get_team("ENG-MCI1")
	var view := PreMatchModel.build("ENG-MUN1", "ENG-MCI1", {}, null)
	var quote := str((view["home_quote"] as Dictionary).get("line", ""))
	assert_true(quote != "", "a friendly's manager said nothing")
	assert_false(quote.contains("no friendly"), "a friendly's manager denied it is a friendly")
	assert_true(PreMatchCopy.FRIENDLY_LINES.has(quote), "a friendly took a league quote pack")

	var again := PreMatchCopy.quote(3, home, away, {"friendly": true})
	var twice := PreMatchCopy.quote(3, home, away, {"friendly": true})
	assert_eq(str(again["line"]), str(twice["line"]), "a friendly quote is not seeded")
	assert_eq(str(again["by"]), str(home["manager"]).to_upper(), "a friendly quote is not the manager's")


func test_the_scene_binding_is_the_one_answer_every_surface_reads() -> void:
	var game := StubScene.new()
	assert_eq(game.billing.chrome_name(), MatchBilling.FRIENDLY, "the scene started billed as a league")
	MatchBilling.bind_scene(game, "ENG-MUN1", {"matchday": 5})
	assert_eq(game.billing.chrome_name(), "PREMIER LEAGUE", "the league was not bound")
	assert_eq(game.billing.caption(), "PREMIER LEAGUE · MATCHDAY 5", "the caption lost its round")

	var bare := MatchBilling.bind_scene(null, "ENG-MUN1", {})
	assert_true(bare.friendly, "a bare scene is not a friendly")
	assert_eq(MatchBilling.bind_scene(null, "ENG-MUN1", {"matchday": 2}).matchday, 2,
		"a bare scene dropped its round")


func test_a_league_watch_binds_the_competition_it_plays_in() -> void:
	var fx := _fixture()
	var game := StubScene.new()
	game.prematch = StubPreMatch.new()
	var host := LeagueHost.new()
	host.attach(game)
	host.season = season
	var held := str(fx["id"])
	assert_eq(game.billing.chrome_name(), MatchBilling.FRIENDLY, "the scene started billed as a league")
	host.watch.on_match_requested(str(fx["home_club_id"]), str(fx["away_club_id"]), held)
	assert_false(game.billing.friendly, "a league watch left the match a friendly")
	assert_eq(str(game.prematch.asked["caption"]), game.billing.caption(),
		"the briefing and the scene disagree about the competition")
	assert_eq(str(game.prematch.asked["competition"]), game.billing.chrome_name(),
		"the briefing and the broadcast disagree about the competition")
	game.free()


func test_the_picker_rebinds_the_scene_to_a_friendly() -> void:
	var game := StubScene.new()
	game.prematch = StubPreMatch.new()
	game.selector = StubSelector.new()
	MatchBilling.bind_scene(game, "ENG-MUN1", {"matchday": 7})
	assert_false(game.billing.friendly, "the scene did not start on a league")
	var sheet := FixtureSheet.new(game)
	sheet.confirm("ENG-MUN1", "ENG-MCI1")
	assert_true(game.billing.friendly, "the picker kept the season's competition")
	assert_eq(str(game.prematch.asked["caption"]), MatchBilling.FRIENDLY_CAPTION,
		"the picker's briefing still names a league")
	game.free()


func test_the_picker_footer_names_the_file_s_competition() -> void:
	var picker := load("res://scripts/ui/team_select.gd")
	assert_eq(picker.clubs_line(20, "Premier League"), "20 PREMIER LEAGUE CLUBS",
		"the picker footer lost its league")
	assert_eq(picker.clubs_line(20, ""), "20 CLUBS",
		"a file with no competition still claimed one")
	assert_eq(picker.clubs_line(18, "La Liga"), "18 LA LIGA CLUBS",
		"the picker footer is hard-coded to one league")


func test_the_league_watch_answer_is_the_binding_and_nothing_else() -> void:
	assert_false(MatchBilling.league_watch(null), "a bare scene reads as a league watch")
	var game := StubScene.new()
	assert_false(MatchBilling.league_watch(game), "a fresh scene reads as a league watch")
	MatchBilling.bind_scene(game, "MUN", {"matchday": 5})
	assert_true(MatchBilling.league_watch(game), "a fixture-bound scene does not read as a league watch")
	game.billing.bind_friendly("MUN", "MCI")
	assert_false(MatchBilling.league_watch(game), "a friendly still reads as a league watch")
	assert_false(MatchBilling.league_watch({"paused": false}), "a host with no binding reads as a league watch")
	game.free()


class StubScene extends Node:
	var billing := MatchBilling.new()
	var prematch = null
	var selector = null
	var paused := false
	var select_open := false
	var select_from_menu := false
	var home_id := "ENG-MUN1"
	var away_id := "ENG-MCI1"
	var seeded := 1000
	var match_started := false
	var hud_layer = null
	var sel_layer = null
	var menus = null
	func new_match(seed: int) -> void:
		seeded = seed
		match_started = true
