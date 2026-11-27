class_name LeagueResult
extends RefCounted


var host = null

var holding := false

func _init(owner) -> void:
	host = owner


func take(report: Dictionary) -> bool:
	if not _viewer_on(report):
		return false
	holding = true
	var game = host.game
	if game.hud_layer != null:
		game.hud_layer.visible = true
	game.result_hold = true


	game.fast_mode = false
	game.in_highlight = false
	game.highlight_until = -1.0
	return true


func input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		dismiss()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
			dismiss()
	return true


func dismiss() -> void:
	if not holding:
		return
	holding = false
	if host.game != null:
		host.game.result_hold = false
	reveal()


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


func clear() -> void:
	if not holding:
		return
	holding = false
	if host != null and host.game != null:
		host.game.result_hold = false


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
