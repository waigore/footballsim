class_name MatchInput
extends RefCounted


var game = null


var held_by = null
var held_at := Vector2(-1, -1)

func _init(host) -> void:
	game = host


func handle(event: InputEvent) -> bool:


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

			if game.hud != null and game.hud.interest.press_at(game.view.design(event.position)):
				held_by = game.hud.interest
				held_at = event.position
				return


			if game.view.button_at(event.position) == "hud":
				game.hud.toggle_hud()
				return
			click(event.position)
		else:
			_release(event.position)


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
	click(held_at if held_at.x >= 0.0 else screen_point)


func click(p: Vector2) -> void:
	var b: String = game.view.button_at(p)
	if b == "pause":
		game.paused = not game.paused
	elif b == "speed":
		_cycle_speed()
	elif b == "mode":
		game._toggle_mode()
	elif b == "skip":
		game._skip()
	elif b == "camera":
		game.camera_follow = not game.camera_follow
	elif b == "teams":
		if not MatchBilling.league_watch(game):
			game.open_select()
	elif b == "menu":
		game.menus.open_menu()
	elif b == "league":
		game.wiki_host.open_page(WikiModel.LEAGUE, "")
	elif b == "team_0":
		game.wiki_host.open_page(WikiModel.TEAM, str(game.engine.teams[0]["id"]))
	elif b == "team_1":
		game.wiki_host.open_page(WikiModel.TEAM, str(game.engine.teams[1]["id"]))
	elif b == "profile":
		var tracked = game.engine.by_id.get(game.focus_id, null)
		if tracked != null and str(tracked.key) != "":
			game.wiki_host.open_page(WikiModel.PLAYER, str(tracked.key))
	elif b == "manager_card":
		game.hud.manager_card.dismiss()
	elif b == "restart":
		if not MatchBilling.league_watch(game):
			game.new_match(game.seeded + randi_range(0, 9999))
	if b != "":
		return

	game.hover_id = game.view.pick(p)
	game.focus_id = -1 if game.hover_id < 0 or game.focus_id == game.hover_id else game.hover_id
	game.actors.focus_id = game.focus_id

func _cycle_speed() -> void:
	var opts := [1.0, 2.0, 4.0, 8.0]
	var idx := opts.find(game.speed)
	game.speed = opts[(idx + 1) % opts.size()]


func _key(k: int) -> void:


	var over: bool = game.engine != null and str(game.engine.phase) == "full_time"
	if over and k in [KEY_SPACE, KEY_1, KEY_2, KEY_3, KEY_4, KEY_S]:
		return
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
		if not MatchBilling.league_watch(game):
			game.new_match(game.seeded + randi_range(0, 9999))
	elif k == KEY_N:
		game.names_visible = not game.names_visible
		game.actors.names_visible = game.names_visible
	elif k == KEY_C:
		game.camera_follow = not game.camera_follow
	elif k == KEY_U:
		game.hud.toggle_hud()
	elif k == KEY_M:
		game.menus.open_menu()
	elif k == KEY_T:
		if not MatchBilling.league_watch(game):
			game.open_select()
	elif k == KEY_L:
		game.wiki_host.open_page(WikiModel.LEAGUE, "")
	elif k == KEY_ESCAPE:
		if game.focus_id >= 0:
			game.focus_id = -1
		else:
			game.menus.ask_quit()
