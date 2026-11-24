class_name MatchInput
extends RefCounted

## The play scene's keyboard and pointer routing: which sheet owns the event,
## the zoom wheel, the click table on the overlay bar, and the one-key match
## controls. The scene keeps the state; this module owns the branching. Split
## out of main.gd so the scene stays inside its P3 size budget.

var game = null
## Milliseconds the current press has been down, and the hold that raises the
## interest menu instead of committing a click.
var press_ms := 0
var hold_ms := InterestMenu.HOLD_MS

func _init(host) -> void:
	game = host

## Route one event to whoever owns the screen. Returns true when a sheet over
## the pitch (encyclopedia, menus, fixture picker) swallowed it.
func handle(event: InputEvent) -> bool:
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
	elif event is InputEventMouseButton and (event.pressed or event.button_index == MOUSE_BUTTON_LEFT):
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
			press_ms = Time.get_ticks_msec()
			return
		if game.interest != null and game.interest.open:
			if game.interest.hit(sheet.mouse, sheet.design_vp()) == "interest:toggle":
				game.interest.apply()
			else:
				game.interest.hide()
			return
		if Time.get_ticks_msec() - press_ms >= hold_ms \
				and InterestEntry.show(game, InterestEntry.picker_club(sheet)):
			return
		var sid: String = sheet.button_at(sheet.mouse)
		if sid != "":
			sheet.click(sid)
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
		# A press starts the hold clock; the release either commits the click or
		# raises the interest menu on a team name.
		if event.pressed:
			press_ms = Time.get_ticks_msec()
			return
		var design_vp: Vector2 = game.get_viewport().get_visible_rect().size / maxf(game.hud_scale, 0.001)
		if game.interest != null and game.interest.open:
			if game.interest.hit(game.view.design(event.position), design_vp) == "interest:toggle":
				game.interest.apply()
			else:
				game.interest.hide()
			return
		if Time.get_ticks_msec() - press_ms >= hold_ms \
				and InterestEntry.show(game, InterestEntry.hud_club(game)):
			return
		game._click(event.position)

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
