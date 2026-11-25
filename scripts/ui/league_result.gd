class_name LeagueResult
extends RefCounted

## A watched fixture's whistle (#124): the season already has the result, the
## broadcast keeps its FULL TIME card, and the hub is one tap behind it.
##
## The host owns the sheet, the layer and the season; this owns the moment
## between the whistle and the hub — who holds the broadcast, which events end
## it, and the reveal that puts the season back on the day it just played.

var host = null
## True while the finished broadcast waits for the player to read its card.
var holding := false

func _init(owner) -> void:
	host = owner

## Take the whistle when the viewer still shows the match that was recorded.
## Returns true when this is the held card, so the host leaves the screen alone.
func take(report: Dictionary) -> bool:
	if not _viewer_on(report):
		return false
	holding = true
	var game = host.game
	if game.hud_layer != null:
		game.hud_layer.visible = true
	game.result_hold = true
	# The match is over: no fast-forward chip and no highlight may point at a
	# chance that cannot come.
	game.fast_mode = false
	game.in_highlight = false
	game.highlight_until = -1.0
	return true

## One event while the card is up. A tap, or the keys a player reaches for, hand
## the screen to the season; everything else is swallowed, so no match control
## (restart included) can touch a game that is already in the ledger.
func input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		dismiss()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
			dismiss()
	return true

## The player dismissed the card: the season sheet takes the screen back on the
## day that was just played, result and all.
func dismiss() -> void:
	if not holding:
		return
	holding = false
	if host.game != null:
		host.game.result_hold = false
	reveal()

## Pause the broadcast, hand the layer back and open the season on its own pose.
## A hub that belongs behind the main menu stays behind it — a leftover watch
## finishing must not pop the season over the menu.
func reveal() -> void:
	if host == null or host.layer == null or host.screen == null:
		return
	var game = host.game
	game.paused = true
	if game.hud_layer != null:
		game.hud_layer.visible = false
	if game.menus == null or game.menus.shell == null or not game.menus.shell.active():
		host.layer.visible = true
	host.screen.open_season(host.season)
	host.screen.refresh()

## Forget a held card without opening anything (the season was detached).
func clear() -> void:
	if not holding:
		return
	holding = false
	if host != null and host.game != null:
		host.game.result_hold = false

## The viewer is still on the pitch showing the whistle of the fixture that was
## just recorded: the HUD is up, no sheet owns the screen, and the engine on it
## is that match.
func _viewer_on(report: Dictionary) -> bool:
	var game = host.game
	if host.is_open() or game == null or game.engine == null:
		return false
	if game.hud_layer == null or not game.hud_layer.visible:
		return false
	if game.menus != null and game.menus.shell != null and game.menus.shell.active():
		return false
	var fx: Dictionary = report.get("fixture", {})
	return str(fx.get("home_club_id", "")) == str(game.home_id) \
		and str(fx.get("away_club_id", "")) == str(game.away_id) \
		and str(game.engine.phase) == "full_time"
