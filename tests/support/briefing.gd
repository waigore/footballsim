class_name TestBriefing
extends RefCounted


static func is_open(game) -> bool:
	return game != null and game.prematch != null and game.prematch.is_open()


static func kick(game) -> bool:
	return _press(game, "kick")


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
