class_name LeagueWatch
extends RefCounted

## A watched fixture the player walked out of (#100): the viewer's engine is
## played out at max speed while the hub paints, then the result is saved
## through the same path a watched full time takes.
##
## The host owns the season sheet; this owns the leftover match. A slice of
## engine work runs each frame so the sheet stays responsive, and the fixture
## lands in the save on its own — the player never has to do anything else.

## Engine work per frame: enough to outrun the match clock without freezing the
## hub, about two desktop frames' worth.
const BUDGET_USEC := 30000

var host = null
## The viewer's engine being played out, or null when nothing is pending.
var engine = null

func _init(owner) -> void:
	host = owner

func settling() -> bool:
	return engine != null

## Take the viewer's engine off the match scene and hand the hub back. Its
## events are unhooked first: the leftover goals must not cut clips or replay
## the broadcast behind the season sheet.
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

## One frame of the leftover match. At full time the result goes through
## `PLSimStats`, the same path a watched full time takes.
func tick() -> void:
	if host == null:
		return
	var season: LeagueSeason = host.season
	if engine == null:
		return
	if season == null or not season.finishing:
		# The season was closed or replaced under the leftover match: drop it
		# rather than let it land somewhere it does not belong.
		engine = null
		return
	if not engine.run_to_full_time(BUDGET_USEC):
		return
	var done = engine
	engine = null
	if not host.game.result_recorded:
		host.game.result_recorded = PLSimStats.record_match(done)

## Forget the leftover match without saving it (a new match took the scene).
func clear() -> void:
	engine = null
