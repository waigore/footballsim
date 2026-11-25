class_name MatchInput
extends RefCounted

## The play scene's keyboard and pointer routing: which sheet owns the event,
## the zoom wheel, the click table on the overlay bar, and the one-key match
## controls. The scene keeps the state; this module owns the branching. Split
## out of main.gd so the scene stays inside its P3 size budget.

var game = null
## A press the long-press grammar is watching (#107): the click it held back runs
## on release, when the press turns out to be a short tap.
var held_by = null
var held_at := Vector2(-1, -1)

func _init(host) -> void:
	game = host

## Route one event to whoever owns the screen. Returns true when a sheet over
## the pitch (encyclopedia, menus, fixture picker) swallowed it.
func handle(event: InputEvent) -> bool:
	# The pre-match briefing is the top modal while it is up: it answers every
	# event, and nothing underneath it can start or scroll a match (#157).
	if game.prematch != null and game.prematch.is_open():
		var point: Vector2 = Vector2.ZERO
		if event is InputEventMouse:
			point = game.view.design(event.position, game.chrome_scale)
		game.prematch.handle_input(event, point)
		return true
	if game.wiki_host != null and game.wiki_host.is_open():
		game.wiki_host.handle_input(event)
		return true
	if game.select_open:
		_select(event)
		return true
	if game.menus != null and game.menus.handle_input(event, event.position if event is InputEventMouse else Vector2.ZERO):
		return true
	if event is InputEventMouseMotion:
		game.mouse = event.position
		game.view.hover(game.mouse)
	elif event is InputEventMouseButton:
		_pointer(event)
	elif event is InputEventKey and event.pressed and not event.echo:
		_key(event.keycode)
	return false

## Fixture sheet: hover and taps read in the chrome layer's design space.
func _select(event: InputEvent) -> void:
	var sheet = game.selector
	if event is InputEventMouseMotion:
		game.mouse = event.position
		sheet.mouse = game.view.design(event.position, game.chrome_scale)
		if not game.touch:
			Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if sheet.button_at(sheet.mouse) != "" else Input.CURSOR_ARROW)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		game.mouse = event.position
		sheet.mouse = game.view.design(event.position, game.chrome_scale)
		if event.pressed:
			# A club card is held back until the release says tap or hold (#107).
			if sheet.interest.press_at(sheet.mouse):
				held_by = sheet.interest
				held_at = event.position
				return
			var sid: String = sheet.button_at(sheet.mouse)
			if sid != "":
				sheet.click(sid)
		else:
			_release(event.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		sheet.key(event.keycode)

func _pointer(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		game.zoom_scale = clampf(game.zoom_scale * 1.08, 0.65, 2.4)
		game._apply_camera(true)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		game.zoom_scale = clampf(game.zoom_scale / 1.08, 0.65, 2.4)
		game._apply_camera(true)
	elif event.button_index == MOUSE_BUTTON_LEFT:
		game.mouse = event.position
		if event.pressed:
			# A held club name on the overlay opens the menu instead of the page.
			if game.hud != null and game.hud.interest.press_at(game.view.design(event.position)):
				held_by = game.hud.interest
				held_at = event.position
				return
			game._click(event.position)
		else:
			_release(event.position)

## The release of a press a long-press grammar held back: a short tap still runs
## the click the press would have run, a hold or a menu press is consumed (#107).
func _release(screen_point: Vector2) -> void:
	if held_by == null:
		return
	var hold = held_by
	held_by = null
	var design: Vector2 = game.view.design(screen_point,
		game.chrome_scale if game.select_open else -1.0)
	if hold.release_at(design):
		return
	var sheet = game.selector if game.select_open else null
	if sheet != null:
		var sid: String = sheet.button_at(design)
		if sid != "":
			sheet.click(sid)
		return
	game._click(held_at if held_at.x >= 0.0 else screen_point)

# if/elif rather than match: the coverage injector cannot instrument a match
# statement, and an uninstrumentable main.gd fails the patch gate.
func _key(k: int) -> void:
	if k == KEY_SPACE:
		game.paused = not game.paused
	elif k == KEY_1:
		game.speed = 1.0
	elif k == KEY_2:
		game.speed = 2.0
	elif k == KEY_3:
		game.speed = 4.0
	elif k == KEY_4:
		game.speed = 8.0
	elif k == KEY_H:
		game._toggle_mode()
	elif k == KEY_S:
		game._skip()
	elif k == KEY_R:
		game.new_match(game.seeded + randi_range(0, 9999))
	elif k == KEY_N:
		game.names_visible = not game.names_visible
		game.actors.names_visible = game.names_visible
	elif k == KEY_C:
		game.camera_follow = not game.camera_follow
	elif k == KEY_M:
		game.menus.open_menu()
	elif k == KEY_T:
		game.open_select()
	elif k == KEY_L:
		game.wiki_host.open_page(WikiModel.LEAGUE, "")
	elif k == KEY_ESCAPE:
		if game.focus_id >= 0:
			game.focus_id = -1
		else:
			game.menus.ask_quit()
