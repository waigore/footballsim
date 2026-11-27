class_name LeagueWatch
extends RefCounted


const BUDGET_USEC := 30000

var host = null

var engine = null

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
