class_name BackPress
extends RefCounted


const GUARD_MS := 300


static func allowed(previous_ms: int, now_ms: int) -> bool:
	return now_ms - previous_ms >= GUARD_MS


static func escape() -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	return event


static func sheet_open(game: Variant) -> bool:
	if game.prematch != null and game.prematch.is_open():
		return true
	if game.wiki_host != null and game.wiki_host.is_open():
		return true
	if bool(game.select_open):
		return true
	return game.menus != null and game.menus.active()


static func press(game: Variant) -> String:
	if sheet_open(game):
		game.input.handle(escape())
		return "sheet"
	if game.replay != null:
		game._skip()
		return "clip"
	game.menus.open_menu()
	return "menu"
