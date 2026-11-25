class_name TestBriefing
extends RefCounted

## Drive the pre-match briefing from a suite the way a player does (#157).
##
## Every watched league fixture and every single-match KICK OFF raises the
## briefing first, so a suite that wants the sim running kicks it off here rather
## than assuming the old straight-to-pitch hand-off. The press goes through the
## scene's own input router, so the routing is exercised too.

## True while the briefing is the top surface.
static func is_open(game) -> bool:
	return game != null and game.prematch != null and game.prematch.is_open()

## Press the briefing's primary door (CONTINUE / KICK OFF). False when no
## briefing was up, so a flow can assert it opened.
static func kick(game) -> bool:
	return _press(game, "kick")

## Press BACK on the briefing: leave without starting.
static func back(game) -> bool:
	return _press(game, "back")

static func _press(game, id: String) -> bool:
	if not is_open(game):
		return false
	var vp: Vector2 = game.prematch.screen.design_vp()
	for item in game.prematch.screen.layout(vp)["buttons"]:
		if str(item["id"]) != id:
			continue
		var point: Vector2 = (item["rect"] as Rect2).get_center() * game.chrome_scale
		var down := InputEventMouseButton.new()
		down.button_index = MOUSE_BUTTON_LEFT
		down.pressed = true
		down.position = point
		game._input(down)
		var up := InputEventMouseButton.new()
		up.button_index = MOUSE_BUTTON_LEFT
		up.pressed = false
		up.position = point
		game._input(up)
		return true
	return false
