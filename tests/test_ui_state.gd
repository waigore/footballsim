extends GdToolsTest


var game = null
var season: LeagueSeason = null

func before_all() -> void:
	game = Node2D.new()
	game.set_script(load("res://scripts/main.gd"))
	add_child(game)
	await get_tree().process_frame
	season = LeagueSeason.create("UI State Evidence", "generated", "fixture_days", 2026)

func after_all() -> void:
	if is_instance_valid(game):
		game.queue_free()


func test_the_bus_forwards_a_season_change() -> void:
	var bus := UiBus.make()
	var seen: Array = []
	bus.data_changed.connect(func(scope: String) -> void: seen.append(scope))
	bus.bind_season(season)
	season.state_changed.emit()
	assert_in("season", seen, "a season change did not reach the bus")
	assert_eq(bus.season, season, "the bus did not keep the season it bound")


func test_an_unbound_season_cannot_reach_the_bus() -> void:
	var bus := UiBus.make()
	var seen: Array = []
	bus.data_changed.connect(func(scope: String) -> void: seen.append(scope))
	bus.bind_season(season)
	bus.unbind_season()
	seen.clear()
	season.state_changed.emit()
	assert_true(seen.is_empty(), "an unbound season still reached the bus")
	assert_null(bus.season, "the bus kept a season it released")


func test_a_recorded_match_wakes_the_session() -> void:
	var bus := UiBus.make()
	var data: Array = []
	var sessions: Array = []
	bus.data_changed.connect(func(scope: String) -> void: data.append(scope))
	bus.session_changed.connect(func() -> void: sessions.append(1))
	bus.bind_season(season)
	sessions.clear()
	season.match_recorded.emit({})
	assert_in("match", data, "a recorded match did not reach the bus")
	assert_eq(sessions.size(), 1, "the session signal did not fire once")


func test_a_screen_change_is_announced_once() -> void:
	var bus := UiBus.make()
	var screen := LeagueScreen.new()
	screen.bus = bus
	var names: Array = []
	bus.screen_changed.connect(func(name: String) -> void: names.append(name))
	screen.mode = LeagueScreen.MODE_HUB
	screen.mode = LeagueScreen.MODE_HUB
	assert_eq(names, ["league"], "a repeated screen change was announced twice")
	screen.mode = ""
	assert_eq(names, ["league", ""], "leaving the screen was not announced")
	screen.queue_free()


func test_the_league_hub_state_lives_off_the_screen() -> void:
	var screen := LeagueScreen.new()
	add_child(screen)
	screen.mode = LeagueScreen.MODE_TABLE
	assert_eq(screen.state.mode, LeagueScreen.MODE_TABLE, "the mode stayed on the screen")
	screen.stats_filter["team"] = "MUN"
	assert_eq(screen.state.stats_filter["team"], "MUN", "a filter edit missed the state bag")
	screen.wizard["name"] = "Held"
	assert_eq(screen.state.wizard["name"], "Held", "a wizard edit missed the state bag")
	assert_eq(screen.state.day, screen.day, "the day read from a second source")
	screen.queue_free()


func test_the_state_bag_announces_its_own_changes() -> void:
	var state := LeagueUiState.new()
	var scopes: Array = []
	state.changed.connect(func(scope: String) -> void: scopes.append(scope))
	state.set_mode(LeagueScreen.MODE_CALENDAR)
	state.set_mode(LeagueScreen.MODE_CALENDAR)
	state.set_filter("stats", "stat", "assists")
	assert_eq(scopes, ["mode", "stats"], "the state bag announced the wrong scopes")


func test_an_open_hub_follows_the_season() -> void:
	game.menus.league.show_season(season)
	var body: LeagueBody = game.menus.league.screen.body
	var before: Array = body.content
	season.state_changed.emit()
	assert_false(is_same(before, body.content),
		"the open hub did not rebuild when the season moved")
	assert_eq(game.menus.league.bus.season, season, "the hub is not bound to its season")


func test_the_hub_binds_and_releases_its_season() -> void:
	game.menus.league.show_season(season)
	assert_eq(game.menus.league.bus.season, season, "the hub opened without binding the season")
	game.menus.league.detach_season()
	assert_null(game.menus.league.bus.season, "the hub kept a season it detached")


func test_every_forwarded_field_reads_and_writes_the_bag() -> void:
	var screen := LeagueScreen.new()
	var fields := {
		"wizard": {"name": "Held"},
		"saves": [{"slug": "one"}],
		"report": {"fixture": {"id": "a"}},
		"roundup": [{"fixture": {"id": "b"}}],
		"report_filter": {"league": "PL"},
		"month": "2026-08",
		"day": "2026-08-15",
		"day_fixtures": [{"id": "c"}],
		"days_cache": {"2026-08-15": [{"id": "d"}]},
		"europe": {"comp": "UCL"},
		"europe_draw": {"round": "r1"},
		"calendar_filter": "PL",
		"cups_round": "r2",
		"cup_focus": "FA",
		"draw_state": {"shown": 2},
		"interest_query": "ars",
		"stats_filter": {"stat": "assists"},
		"report_back": "hub",
		"sys": {"status": "ok"},
		"load_from": "menu",
	}
	for name in fields.keys():
		screen.set(name, fields[name])
		assert_eq(screen.get(name), fields[name], "the %s forwarder lost its value" % name)
	assert_eq(screen.state.month, "2026-08", "the bag did not take the month")
	screen.queue_free()


func test_the_state_bag_opens_a_wizard_and_sets_both_filters() -> void:
	var state := LeagueUiState.new()
	var scopes: Array = []
	state.changed.connect(func(scope: String) -> void: scopes.append(scope))
	state.open_wizard(true)
	assert_eq(state.mode, "wizard", "the wizard did not open")
	assert_true(bool(state.wizard["uefa"]), "the wizard forgot the available Europe pot")
	state.set_filter("report", "interest", true)
	assert_true(bool(state.report_filter["interest"]), "the report filter did not take")
	state.set_filter("elsewhere", "interest", true)
	assert_eq(scopes, ["wizard", "report"], "a stray scope announced a change")


func test_a_session_change_binds_the_season_once() -> void:
	var screen := LeagueScreen.new()
	screen.bus = UiBus.make()
	screen.season = season
	screen.on_session_changed()
	assert_eq(screen.bus.season, season, "the session change did not bind the season")
	screen.on_session_changed()
	assert_eq(screen.bus.season, season, "a second session change rebound the season")
	screen.bus.unbind_season()
	assert_null(screen.bus.season, "the bus kept the season")
	screen.queue_free()


func test_the_bus_announces_a_selection() -> void:
	var bus := UiBus.make()
	var seen: Array = []
	bus.selection_changed.connect(func(kind: String, id: String) -> void: seen.append([kind, id]))
	bus.announce_selection("club", "ENG-MUN1")
	bus.announce("ledger")
	assert_eq(seen, [["club", "ENG-MUN1"]], "the selection did not reach the bus")
