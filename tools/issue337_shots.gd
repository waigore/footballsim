extends SceneTree

## Evidence capture for #337: type is rasterized at the density it is drawn at
## instead of being magnified by the layer transform.
##
## A `CanvasLayer` transform is not part of a `CanvasItem`'s global transform, so
## the font rasterizer never sees it. On a phone the overlay is scaled 2.19x over
## a window stretch of 1.2, so every glyph atlas was rasterized at 1.2 and the GPU
## magnified it 2.2x; on a desktop a sheet is scaled 1.25–1.6x over a stretch of
## 1.0. Both are the soft type the reporter saw.
##
## Boots the real game scene, poses the match HUD and the main menu at a phone and
## a desktop window, and shoots each twice: with the shipped atlas density (the
## viewport override cleared, exactly what the build did before the fix) and with
## `TypeDensity`. Sharpness is measured in the pixels actually drawn: a sharp
## glyph transitions from ink to background in one device pixel (many strong
## gradients), a magnified atlas smears the same transition over 3–6.
##
##   xvfb-run -a --server-args="-screen 0 2560x1440x24" \
##     godot --path . --resolution 1600x900 --script res://tools/issue337_shots.gd
##
## Writes PNGs into `res://shots/` (git-ignored) and prints the measurements.

var scene = null

## [label, window size, forced overlay scale]
const POSES := [
	["phone", Vector2i(2400, 1080), 2.19],
	["desktop", Vector2i(1600, 900), 1.0],
	["tall_desktop", Vector2i(2560, 1440), 1.0],
]

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	scene.menus.close()
	scene.hud_layer.visible = true
	scene._on_fixture_confirmed("MUN", "MCI")
	if scene.prematch != null and scene.prematch.is_open():
		scene.prematch.screen.click("kick")
		await _frames(2)
	scene.paused = false
	scene.set_process(false)
	scene.engine.clock = 63.0 * 60.0
	scene.engine.score[0] = 2
	scene.engine.score[1] = 1
	scene.view.set_mode("full")
	scene.fast_mode = false
	scene.hud.set_hud_visible(true, true)
	for pose in POSES:
		await _pose_hud(str(pose[0]), pose[1], float(pose[2]))
		await _pose_menu(str(pose[0]), pose[1], float(pose[2]))
	print("EXIT")
	quit()

func _pose_hud(label: String, size: Vector2i, overlay: float) -> void:
	_desktop()
	await _resize(size)
	scene.dev.ui_scale = overlay
	scene._sync_overlay_scale()
	scene.hud.queue_redraw()
	await _frames(4)
	var fixed: float = root.oversampling_override
	var scale: float = scene.hud_scale
	print("POSE %s/hud window=%s design=%s layer=%.2f type_density=%.3f" % [
		label, str(DisplayServer.window_get_size()), str(root.get_visible_rect().size), scale, fixed])
	await _shoot("%s_hud_shipped" % label, 0.0, _text_box(), scale)
	await _shoot("%s_hud_fixed" % label, fixed, _text_box(), scale)

func _pose_menu(label: String, size: Vector2i, overlay: float) -> void:
	_desktop()
	await _resize(size)
	scene.dev.ui_scale = overlay
	scene._sync_overlay_scale()
	scene.menus.open_menu()
	await _frames(4)
	# The scene is frozen for a reproducible pose, so the per-frame density sync
	# is asked for by hand: in the game `_process` does this every frame.
	scene.view.sync_type_density()
	var fixed: float = root.oversampling_override
	print("POSE %s/menu window=%s layer=%.2f type_density=%.3f" % [
		label, str(DisplayServer.window_get_size()), scene.chrome_scale, fixed])
	await _shoot("%s_menu_shipped" % label, 0.0, _menu_box(), scene.chrome_scale)
	await _shoot("%s_menu_fixed" % label, fixed, _menu_box(), scene.chrome_scale)
	scene.menus.close()
	await _frames(2)

func _resize(size: Vector2i) -> void:
	DisplayServer.window_set_size(size)
	root.size = size
	await _frames(4)

func _desktop() -> void:
	scene.dev.ui_scale = 0.0

## The scoreboard's band: two club abbreviations, the score and the clock, all
## painted at design sizes by the overlay.
func _text_box() -> Rect2:
	return _design_box(HudLayout.scoreboard_rect(scene.hud.design_vp()), scene.hud_scale)

## The menu's door column: every wordmark and door caption the shell paints.
func _menu_box() -> Rect2:
	var vp: Vector2 = scene.menus.shell.design_vp()
	var band := Rect2(0.0, vp.y * 0.30, vp.x, vp.y * 0.52)
	return _design_box(band, scene.chrome_scale)

## A design-space rect in window pixels: the layer scale times the window's own
## stretch over the viewport, which is what `get_texture()` hands back.
func _design_box(rect: Rect2, layer_scale: float) -> Rect2:
	var stretch: float = float(DisplayServer.window_get_size().x) / maxf(root.get_visible_rect().size.x, 1.0)
	return Rect2(rect.position * layer_scale * stretch, rect.size * layer_scale * stretch)

## Shoot one frame at a forced atlas density (0.0 = the engine's own stretch
## density, which is what shipped before the fix).
func _shoot(tag: String, density: float, box: Rect2, layer_scale: float) -> void:
	root.oversampling_override = density
	await _frames(4)
	RenderingServer.force_draw(false)
	var tex: ViewportTexture = scene.get_viewport().get_texture()
	if tex == null:
		print("SHOT %s skipped (no renderer)" % tag)
		return
	var img: Image = tex.get_image()
	if img == null:
		print("SHOT %s skipped (no image)" % tag)
		return
	var path := ProjectSettings.globalize_path("res://shots/%s.png" % tag)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	_measure(tag, img, box, density, layer_scale)

## Sharpness read off the drawn pixels. Only glyph strokes count: a pixel whose
## six-pixel neighbourhood jumps by more than 45% is on a stroke edge, which
## keeps the translucent panels and the stadium behind them out of the count.
## `strong` is how many stroke edges make that jump in one pixel — a sharp glyph
## has many, a magnified atlas smears each transition over several pixels and
## has few. `mid` is the share of ink that is only half covered.
func _measure(tag: String, img: Image, box: Rect2, density: float, layer_scale: float) -> void:
	var x0: int = clampi(int(box.position.x), 1, img.get_width() - 2)
	var x1: int = clampi(int(box.end.x), 2, img.get_width() - 1)
	var y0: int = clampi(int(box.position.y), 1, img.get_height() - 2)
	var y1: int = clampi(int(box.end.y), 2, img.get_height() - 1)
	var edges := 0
	var strong := 0
	var ink := 0
	var mid := 0
	for y in range(y0, y1):
		for x in range(x0, x1):
			var l: float = img.get_pixel(x, y).r
			var g: float = absf(l - img.get_pixel(x - 1, y).r) + absf(l - img.get_pixel(x, y - 1).r)
			var lo := l
			var hi := l
			for d in range(1, 7):
				if x - d >= x0:
					var v: float = img.get_pixel(x - d, y).r
					lo = minf(lo, v)
					hi = maxf(hi, v)
			if hi - lo > 0.45:
				edges += 1
				if g > 0.35:
					strong += 1
				if l > 0.10:
					ink += 1
					if l < 0.90:
						mid += 1
	print("SHOT %-20s layer=%.2f density=%.2f stroke_px=%5d strong=%5d strong%%=%.1f mid/ink=%.3f" % [
		tag, layer_scale, density, edges, strong,
		100.0 * float(strong) / maxf(float(edges), 1.0),
		float(mid) / maxf(float(ink), 1.0)])

func _frames(count: int) -> void:
	for i in range(count):
		await process_frame
