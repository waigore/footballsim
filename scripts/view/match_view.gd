class_name MatchView
extends RefCounted


var game = null

func _init(host) -> void:
	game = host


static func default_follow() -> bool:
	return OS.has_feature("mobile")


func overlay_scale(hud_layer: CanvasLayer, dev) -> Dictionary:
	var hud: float = HudLayout.overlay_scale()
	var handheld := false
	if dev != null and dev.ui_scale > 0.0:
		hud = dev.ui_scale
		handheld = true
	var compact: bool = HudLayout.is_compact(game.get_viewport_rect().size / hud)
	if hud_layer != null:
		hud_layer.transform = Transform2D.IDENTITY.scaled(Vector2(hud, hud))
	return {
		"hud": hud,
		"touch": handheld or game.touch,
		"chrome": maxf(hud, ChromeDensity.non_match_scale()),
		"token": 1.5 if compact else 1.0,
	}


func visible_scale() -> float:
	if game.menus != null and game.menus.active():
		return game.chrome_scale
	if game.wiki_host != null and game.wiki_host.is_open():
		return game.chrome_scale
	if game.prematch != null and game.prematch.is_open():
		return game.chrome_scale
	return game.hud_scale


func sync_type_density() -> void:
	TypeDensity.apply(game.get_viewport(), visible_scale())


func sync_overlays(hud_layer: CanvasLayer, dev: DevCapture) -> void:
	var scales: Dictionary = overlay_scale(hud_layer, dev)
	game.hud_scale = float(scales["hud"])
	game.touch = bool(scales["touch"])
	game.chrome_scale = float(scales["chrome"])
	game.token_scale = float(scales["token"])
	game.actors.token_scale = game.token_scale
	game.hud.ui_scale = game.hud_scale
	game.hud.touch = game.touch
	hud_layer.transform = Transform2D.IDENTITY.scaled(Vector2(game.hud_scale, game.hud_scale))
	var frame := Transform2D.IDENTITY.scaled(Vector2(game.chrome_scale, game.chrome_scale))
	if game.sel_layer != null:
		game.sel_layer.transform = frame
		game.selector.ui_scale = game.chrome_scale
		game.selector.touch = game.touch
	if game.wiki_host != null:
		game.wiki_host.sync_scale()
	if game.prematch != null:
		game.prematch.sync(frame, game.chrome_scale, game.touch)
	if game.menus != null:
		game.menus.sync(frame, game.chrome_scale, game.touch)
	if game.camera != null:
		game.camera.fit()
	sync_type_density()


func design(p: Vector2, scale := -1.0) -> Vector2:
	return p / maxf(game.hud_scale if scale < 0.0 else scale, 0.001)

func button_at(p: Vector2) -> String:
	return game.hud.button_at(design(p))


func pick(p: Vector2) -> int:
	var world: Vector2 = game.get_viewport().get_canvas_transform().affine_inverse() * p
	var best = null
	var reach: float = 2.8 if game.touch else 1.7
	var bd := reach * reach
	for q in game.engine.players:
		if q.sent_off:
			continue
		var d: float = q.pos.distance_squared_to(world)
		if d < bd:
			bd = d
			best = q
	return -1 if best == null else best.id


func hover(screen: Vector2) -> void:
	game.hover_id = pick(screen)
	game.actors.hover_id = game.hover_id
	game.hud.mouse = design(screen)
	if not game.touch:
		var over_button: bool = game.hud.button_at(game.hud.mouse) != ""
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if (game.hover_id >= 0 or over_button) else Input.CURSOR_ARROW)


func ticks_this_frame(delta: float) -> int:
	var fast: bool = game.mode != "full" and game.fast_mode
	game.accumulator += delta * 60.0 * (24.0 if fast else game.speed)
	var n: int = int(game.accumulator)
	game.accumulator -= n
	return mini(n, 60 if fast else 120)


func set_mode(next: String) -> void:
	game.mode = Prefs.normalize_mode(next)
	if game.mode == "full":
		game.fast_mode = false
		game.in_highlight = false
		game.highlight_until = -1.0
		game.paused = false
		game.speed = 1.0
		return
	game.fast_mode = not game.in_highlight
	if not game.in_highlight:
		game.highlight_until = -1.0
