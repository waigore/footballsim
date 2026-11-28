class_name LeagueWatch
extends RefCounted


const BUDGET_USEC := 30000

var host = null

var engine = null

var briefing: Dictionary = {}

func _init(owner) -> void:
	host = owner

func settling() -> bool:
	return engine != null


func leave() -> bool:
	if host == null:
		return false
	var season: LeagueSeason = host.season
	if engine != null or season == null or season.watching_fixture == "":
		return false
	if host.game == null or host.game.engine == null:
		return false
	engine = host.game.engine
	season.finishing = true
	if engine.event_fired.is_connected(host.game._on_engine_event):
		engine.event_fired.disconnect(host.game._on_engine_event)
	host._activate()
	if host.screen != null:
		host.screen.open_season(season)
	return true


func tick() -> void:
	if host == null:
		return
	var season: LeagueSeason = host.season
	if engine == null:
		return
	if season == null or not season.finishing:


		engine = null
		return
	if not engine.run_to_full_time(BUDGET_USEC):
		return
	var done = engine
	engine = null
	if not host.game.result_recorded:
		host.game.result_recorded = PLSimStats.record_match(done)


func clear() -> void:
	engine = null
	briefing = {}


func on_match_requested(home: String, away: String, fixture_id: String) -> void:
	briefing = {"home": home, "away": away, "fixture": fixture_id}
	var season: LeagueSeason = host.season
	var fx: Dictionary = season.record.fixtures.one(fixture_id) if season != null else {}

	MatchBilling.bind_scene(host.game, home, fx)
	if host.game.prematch != null:
		var req := PreMatchModel.build(home, away, fx, season)
		host.game.prematch.ask(req, Callable(self, "kick_briefing"), Callable(self, "back_from_briefing"))
		return
	start_watch(home, away)


func kick_briefing() -> void:
	start_watch(str(briefing.get("home", "")), str(briefing.get("away", "")))


func back_from_briefing() -> void:
	if host.season != null:
		host.season.cancel_watch()
	briefing = {}
	if host.layer != null:
		host.layer.visible = true
	if host.screen != null:
		host.screen.refresh()
	host.game.paused = true

func start_watch(home: String, away: String) -> void:
	briefing = {}
	if host.layer != null:
		host.layer.visible = false

	if host.screen != null:
		host.screen.focus.blur()
	if host.result != null:
		host.result.clear()
	host.game.home_id = home
	host.game.away_id = away
	host.game.seeded += randi_range(1, 9999)
	host.game.match_started = true
	host.game.new_match(host.game.seeded)
	host.game.paused = false
	if host.game.hud_layer != null:
		host.game.hud_layer.visible = true


func on_goal_highlight(fixture_id: String, goal_index: int) -> void:
	if host.season == null or fixture_id == "":
		return
	var pack: Dictionary = host.season.goal_clip(fixture_id, goal_index)
	if pack.is_empty():
		return
	if host.layer != null:
		host.layer.visible = false
	if host.game.hud_layer != null:
		host.game.hud_layer.visible = true
	host.game.play_goal_clip(pack, on_goal_clip_done)

func on_goal_clip_done() -> void:
	if host == null or host.game == null or host.screen == null:
		return
	host.game.paused = true
	if host.game.hud_layer != null:
		host.game.hud_layer.visible = false
	if host.layer != null:
		host.layer.visible = true
	host.screen.refresh()
