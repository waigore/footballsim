extends Node2D

## Static broadcast stadium set: a generic top-tier ground seen from the main stand.
## Everything is drawn in pitch metres; the camera maps metres to pixels.
##
## Not covered by tests: every line here is Image/CanvasItem painting that only
## runs when a frame is rendered, and the suite runs headless with no renderer.
## The screenshot playtest (tools/ and the launch-game skill) is what exercises
## this file. The block below keeps it out of the coverage plan instead of
## letting a painter the tests can never reach drag the overall gate down.
# gd-tools: no cover start

const L := 105.0
const W := 68.0
const GOAL_W := 7.32
const GOAL_D := 2.1
const BOX_D := 16.5
const BOX_W := 40.32
const SIX_D := 5.5
const SIX_W := 18.32
const PEN_D := 11.0
const CORNER := 1.0

var grass_font: FontFile
var rng := RandomNumberGenerator.new()
var crowd_tex: ImageTexture
var grass_noise: NoiseTexture2D

var stadium_tex: ImageTexture
const STAD_WORLD := Rect2(-36, -36, 182, 132)

func _ready() -> void:
	z_index = -20
	rng.seed = 90210
	grass_font = load("res://fonts/BarlowCondensed-SemiBold.ttf")
	stadium_tex = _make_stadium_texture(1600, 1200)
	if OS.get_cmdline_user_args().has("--dumpstadium"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
		stadium_tex.get_image().save_png(ProjectSettings.globalize_path("res://shots/stadium.png"))
	var n := FastNoiseLite.new()
	n.seed = 7
	n.frequency = 0.05
	n.fractal_octaves = 3
	grass_noise = NoiseTexture2D.new()
	grass_noise.width = 512
	grass_noise.height = 512
	grass_noise.seamless = true
	grass_noise.noise = n
	queue_redraw()

func _make_stadium_texture(w: int, h: int) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color("#070d12"))
	var sx: float = float(w) / STAD_WORLD.size.x
	var sy: float = float(h) / STAD_WORLD.size.y
	# side stands first (the ends), then the two long stands between them
	var stands := [
		[Rect2(-31, -21.5, 22.0, 110.0), 2, Color("#c24338")],
		[Rect2(115.0, -21.5, 22.0, 110.0), 3, Color("#4f9cc6")],
		[Rect2(-9.5, -21.5, 125.0, 14.4), 0, Color("#c9c3b6")],
		[Rect2(-9.5, 75.2, 125.0, 14.8), 1, Color("#9aa6b0")],
	]
	for st in stands:
		var r: Rect2 = st[0]
		var tint: Color = st[2]
		var ix := int((r.position.x - STAD_WORLD.position.x) * sx)
		var iy := int((r.position.y - STAD_WORLD.position.y) * sy)
		var iw := int(r.size.x * sx)
		var ih := int(r.size.y * sy)
		img.fill_rect(Rect2i(ix, iy, iw, ih), Color("#0b141b"))
		var rows := 12
		var row_h := float(ih) / rows
		for rr in range(rows):
			var depth_f: float = 1.0 - float(rr) / rows
			var base := Color("#1a2833").lerp(Color("#2b3c48"), depth_f * 0.65)
			img.fill_rect(Rect2i(ix, iy + int(rr * row_h), iw, maxi(1, int(row_h) - 1)), base)
		# spectators seated in rows
		var row_step := 1.55
		var seat_step := 0.95
		var n_rows := int(r.size.y / row_step) if st[1] in [0, 1] else int(r.size.x / row_step)
		var n_seats := int(r.size.x / seat_step) if st[1] in [0, 1] else int(r.size.y / seat_step)
		for rr in range(n_rows):
			var row_pos: float = (rr + 0.5) * row_step
			# walkway every fourth row
			if rr % 4 == 3:
				continue
			for ss in range(n_seats):
				if rng.randf() < 0.12:
					continue
				var seat_pos: float = (ss + 0.5) * seat_step + rng.randf_range(-0.18, 0.18)
				var wx: float
				var wy: float
				if st[1] in [0, 1]:
					wx = r.position.x + seat_pos
					wy = r.position.y + row_pos
				else:
					wx = r.position.x + row_pos
					wy = r.position.y + seat_pos
				var px := int((wx - STAD_WORLD.position.x) * sx)
				var py := int((wy - STAD_WORLD.position.y) * sy)
				var c := tint
				var roll := rng.randf()
				if roll < 0.46:
					c = Color("#efe6d6")
				elif roll < 0.62:
					c = Color("#394b57")
				c = c.darkened(rng.randf_range(0.0, 0.28))
				for ox in range(3):
					for oy in range(2):
						if px + ox < w and py + oy < h:
							img.set_pixel(px + ox, py + oy, c)
				if rng.randf() < 0.25:
					var c2 := c.darkened(0.35)
					if px + 3 < w and py + 2 < h:
						img.set_pixel(px + 3, py + 2, c2)
		# aisles, subtle
		if st[1] in [0, 1]:
			var aisles := int(r.size.x / 10.0)
			for a in range(aisles):
				var ax := ix + int(a * 10.0 * sx)
				for yy in range(iy, iy + ih, 2):
					if ax < w:
						img.set_pixel(ax, yy, Color(0.03, 0.05, 0.07, 1))
		else:
			var aisles2 := int(r.size.y / 10.0)
			for a in range(aisles2):
				var ay := iy + int(a * 10.0 * sy)
				for xx in range(ix, ix + iw, 2):
					if ay < h:
						img.set_pixel(xx, ay, Color(0.03, 0.05, 0.07, 1))
		# tier line
		if st[1] in [0, 1]:
			img.fill_rect(Rect2i(ix, iy + int(ih * 0.52), iw, 2), Color(0.12, 0.17, 0.21, 1))
		else:
			img.fill_rect(Rect2i(ix + int(iw * 0.52), iy, 2, ih), Color(0.12, 0.17, 0.21, 1))
		# roof shadow on the outer edge
		for k in range(22):
			var a2 := 0.055 * (1.0 - k / 22.0)
			if st[1] == 0:
				img.fill_rect(Rect2i(ix, iy + k, iw, 1), Color(0, 0, 0, a2))
			elif st[1] == 1:
				img.fill_rect(Rect2i(ix, iy + ih - 1 - k, iw, 1), Color(0, 0, 0, a2))
			elif st[1] == 2:
				img.fill_rect(Rect2i(ix + k, iy, 1, ih), Color(0, 0, 0, a2))
			else:
				img.fill_rect(Rect2i(ix + iw - 1 - k, iy, 1, ih), Color(0, 0, 0, a2))
		# front rail
		if st[1] == 0:
			img.fill_rect(Rect2i(ix, iy + ih - 2, iw, 2), Color(0.55, 0.62, 0.68, 1))
		elif st[1] == 1:
			img.fill_rect(Rect2i(ix, iy, iw, 2), Color(0.55, 0.62, 0.68, 1))
		elif st[1] == 2:
			img.fill_rect(Rect2i(ix + iw - 2, iy, 2, ih), Color(0.55, 0.62, 0.68, 1))
		else:
			img.fill_rect(Rect2i(ix, iy, 2, ih), Color(0.55, 0.62, 0.68, 1))
	# roof overhangs with floodlights
	var roof := Color("#050a0e")
	img.fill_rect(Rect2i(0, 0, w, int(6.0 * sy)), roof)
	img.fill_rect(Rect2i(0, h - int(6.0 * sy), w, int(6.0 * sy)), roof)
	img.fill_rect(Rect2i(0, 0, int(6.0 * sx), h), roof)
	img.fill_rect(Rect2i(w - int(6.0 * sx), 0, int(6.0 * sx), h), roof)
	var lamp := Color(1.0, 0.97, 0.86, 1.0)
	for i in range(11):
		var lx := int((i + 0.5) * w / 11.0)
		img.fill_rect(Rect2i(lx - 3, int(1.2 * sy), 7, 3), lamp)
		img.fill_rect(Rect2i(lx - 1, int(2.4 * sy), 3, 2), Color(1, 1, 0.9, 0.5))
	for i in range(7):
		var ly := int((i + 0.5) * h / 7.0)
		img.fill_rect(Rect2i(int(1.2 * sx), ly - 3, 3, 7), lamp)
		img.fill_rect(Rect2i(w - int(2.4 * sx), ly - 3, 3, 7), lamp)
	# concourse
	var cx := int((-11.0 - STAD_WORLD.position.x) * sx)
	var cy := int((-11.0 - STAD_WORLD.position.y) * sy)
	img.fill_rect(Rect2i(cx, cy, int(127.0 * sx), int(90.0 * sy)), Color("#0a141b"))
	for i in range(2):
		img.fill_rect(Rect2i(cx, cy + int(i * 3.2 * sy), int(127.0 * sx), maxi(1, int(0.8 * sy))), Color(0, 0, 0, 0.2))
	
	return ImageTexture.create_from_image(img)

func _make_crowd_texture(w: int, h: int) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color("#0a1219"))
	var palette := [
		Color("#c9483c"), Color("#e8e2d8"), Color("#8b2c25"), Color("#3c4a55"),
		Color("#7fb2c9"), Color("#f0c9a0"), Color("#20262d"), Color("#d9d2c4"),
	]
	for i in range(int(w * h * 0.34)):
		var x := rng.randi_range(0, w - 1)
		var y := rng.randi_range(0, h - 1)
		var c: Color = palette[rng.randi_range(0, palette.size() - 1)]
		c.a = rng.randf_range(0.45, 1.0)
		img.set_pixel(x, y, c)
		if rng.randf() < 0.3 and x + 1 < w:
			img.set_pixel(x + 1, y, c.darkened(0.25))
	return ImageTexture.create_from_image(img)

func _draw() -> void:
	# --- stadium bowl -------------------------------------------------------
	draw_rect(STAD_WORLD, Color("#070d12"))
	if stadium_tex != null:
		draw_texture_rect(stadium_tex, STAD_WORLD, false)
	# roof shadows at the top of the frame
	for i in range(6):
		draw_rect(Rect2(-46, -46 + i * 3.0, 197, 3.0), Color(0, 0, 0, 0.10 - i * 0.012))
	# --- ad boards ----------------------------------------------------------
	_draw_ad_strip(Rect2(-9.4, -7.4, 123.8, 1.5), 0)
	_draw_ad_strip(Rect2(-9.4, W + 5.9, 123.8, 1.5), 1)
	_draw_ad_strip_v(Rect2(-9.6, -6.0, 1.5, 80.0), 0)
	_draw_ad_strip_v(Rect2(L + 8.1, -6.0, 1.5, 80.0), 1)

	# --- pitch surround -----------------------------------------------------
	draw_rect(Rect2(-6.6, -6.6, L + 13.2, W + 13.2), Color("#0f3523"))
	draw_rect(Rect2(-6.6, -6.6, L + 13.2, 0.35), Color(1, 1, 1, 0.10))
	# technical areas
	draw_rect(Rect2(26.0, 68.6, 18.0, 4.4), Color(0.03, 0.08, 0.055, 0.75))
	draw_rect(Rect2(61.0, 68.6, 18.0, 4.4), Color(0.03, 0.08, 0.055, 0.75))
	draw_rect(Rect2(26.0, 68.6, 18.0, 0.18), Color(1, 1, 1, 0.22))
	draw_rect(Rect2(61.0, 68.6, 18.0, 0.18), Color(1, 1, 1, 0.22))
	for i in range(5):
		draw_rect(Rect2(27.0 + i * 3.4, 69.2, 2.4, 1.6), Color(0.10, 0.16, 0.14, 0.85))
		draw_rect(Rect2(62.0 + i * 3.4, 69.2, 2.4, 1.6), Color(0.10, 0.16, 0.14, 0.85))
	# dugout roofs
	draw_rect(Rect2(25.6, 68.3, 18.8, 0.5), Color(0, 0, 0, 0.35))
	draw_rect(Rect2(60.6, 68.3, 18.8, 0.5), Color(0, 0, 0, 0.35))

	# --- grass --------------------------------------------------------------
	draw_rect(Rect2(0, 0, L, W), Color("#1d6238"))
	var stripe_w := L / 16.0
	for i in range(16):
		var c := Color("#2a7a46") if i % 2 == 0 else Color("#206437")
		draw_rect(Rect2(i * stripe_w, 0, stripe_w, W), c)
	# mown cross-bands
	for i in range(8):
		var y := i * (W / 8.0)
		draw_rect(Rect2(0, y, L, W / 16.0), Color(1, 1, 1, 0.018))
	# grass grain
	if grass_noise != null:
		draw_texture_rect(grass_noise, Rect2(0, 0, L, W), true, Color(0.05, 0.14, 0.08, 0.38))
	# floodlit pool of light in the centre
	for i in range(10):
		var a := 0.026 - i * 0.002
		draw_circle(Vector2(L * 0.5, W * 0.5), 52.0 - i * 4.2, Color(1.0, 0.99, 0.86, a))
	draw_rect(Rect2(0, 0, L, 7), Color(0, 0, 0, 0.10))
	draw_rect(Rect2(0, W - 10, L, 10), Color(0, 0, 0, 0.13))
	# wear patches
	for pt in [Vector2(6, 34), Vector2(52.5, 34), Vector2(99, 34), Vector2(52.5, 10), Vector2(52.5, 58)]:
		draw_circle(pt, 2.4, Color(0.62, 0.55, 0.30, 0.06))
	# stand shadow across the near touchline
	draw_rect(Rect2(0, W - 9, L, 9), Color(0, 0, 0, 0.10))
	draw_rect(Rect2(0, 0, L, 6), Color(0, 0, 0, 0.06))

	# --- markings -----------------------------------------------------------
	var chalk := Color(0.97, 0.99, 0.96, 0.95)
	var lw := 0.13
	draw_rect(Rect2(0, 0, L, W), chalk, false, lw)
	draw_line(Vector2(L * 0.5, 0), Vector2(L * 0.5, W), chalk, lw)
	draw_arc(Vector2(L * 0.5, W * 0.5), 9.15, 0, TAU, 96, chalk, lw, true)
	draw_circle(Vector2(L * 0.5, W * 0.5), 0.16, chalk)
	for side in [0, 1]:
		var gx: float = 0.0 if side == 0 else L
		var dir: float = 1.0 if side == 0 else -1.0
		draw_rect(Rect2(minf(gx, gx + dir * BOX_D), W * 0.5 - BOX_W * 0.5, BOX_D, BOX_W), chalk, false, lw)
		draw_rect(Rect2(minf(gx, gx + dir * SIX_D), W * 0.5 - SIX_W * 0.5, SIX_D, SIX_W), chalk, false, lw)
		draw_circle(Vector2(gx + dir * PEN_D, W * 0.5), 0.14, chalk)
		var start_ang := -0.93 if side == 0 else PI - 0.93
		var end_ang := 0.93 if side == 0 else PI + 0.93
		draw_arc(Vector2(gx + dir * PEN_D, W * 0.5), 9.15, start_ang, end_ang, 48, chalk, lw, true)
	for px in [0.0, L]:
		for py in [0.0, W]:
			var a0 := 0.0
			if px == 0.0 and py == 0.0:
				a0 = 0.0
			elif px == L and py == 0.0:
				a0 = PI * 0.5
			elif px == L and py == W:
				a0 = PI
			else:
				a0 = PI * 1.5
			draw_arc(Vector2(px, py), 1.0, a0, a0 + PI * 0.5, 16, chalk, lw, true)

	# --- goals --------------------------------------------------------------
	_draw_goal(Vector2(0, W * 0.5), -1.0)
	_draw_goal(Vector2(L, W * 0.5), 1.0)

	# --- corner flags -------------------------------------------------------
	for px in [0.0, L]:
		for py in [0.0, W]:
			draw_line(Vector2(px, py), Vector2(px, py) + Vector2(0, -1.7), Color(0.92, 0.92, 0.92, 0.85), 0.06)
			draw_rect(Rect2(Vector2(px, py) + Vector2(0, -1.7), Vector2(0.62, 0.38)), Color("#e8e04a"))

func _draw_goal(base: Vector2, dir: float) -> void:
	var half := GOAL_W * 0.5
	var post := Color(0.99, 1.0, 1.0)
	var back_x := base.x + dir * GOAL_D
	# shadow under the goal
	draw_rect(Rect2(minf(base.x, back_x), base.y - half - 0.2, GOAL_D, GOAL_W + 0.4), Color(0, 0, 0, 0.18))
	# net mesh
	var net := Color(0.88, 0.93, 0.95, 0.34)
	for i in range(9):
		var y := -half + (GOAL_W / 8.0) * i
		draw_line(Vector2(base.x, base.y + y), Vector2(back_x, base.y + y), net, 0.025)
	for i in range(7):
		var x := base.x + dir * (GOAL_D / 6.0) * i
		draw_line(Vector2(x, base.y - half), Vector2(x, base.y + half), net, 0.025)
	# side netting
	draw_line(Vector2(back_x, base.y - half), Vector2(back_x, base.y + half), Color(0.9, 0.95, 0.97, 0.45), 0.04)
	# frame
	draw_line(Vector2(base.x, base.y - half), Vector2(base.x, base.y + half), post, 0.16)
	draw_line(Vector2(base.x, base.y - half), Vector2(back_x, base.y - half), post, 0.10)
	draw_line(Vector2(base.x, base.y + half), Vector2(back_x, base.y + half), post, 0.10)
	draw_line(Vector2(back_x, base.y - half), Vector2(back_x, base.y + half), post, 0.08)
	for i in range(3):
		var px := base.x + dir * (GOAL_D / 3.0) * (i + 1)
		draw_line(Vector2(px, base.y - half), Vector2(px, base.y - half + 0.3), post, 0.06)

func _draw_stand(rect: Rect2, brightness: float, side: int) -> void:
	draw_rect(rect, Color("#0d1820"))
	var rows := 9
	var row_h := rect.size.y / rows
	for r in range(rows):
		var shade := 0.055 + (0.016 if r % 2 == 0 else 0.0)
		var base := Color(0.62 * brightness, 0.68 * brightness, 0.74 * brightness, shade)
		draw_rect(Rect2(rect.position.x, rect.position.y + r * row_h, rect.size.x, row_h - 0.12), base)
	# crowd texture over the seats
	if crowd_tex != null:
		var tint := Color(0.72, 0.76, 0.80, 0.85)
		draw_texture_rect(crowd_tex, rect, true, tint)
	# team-coloured ends
	if side == 0:
		draw_rect(rect, Color(0.85, 0.18, 0.12, 0.10))
	elif side == 1:
		draw_rect(rect, Color(0.42, 0.67, 0.87, 0.10))
	# aisles
	var count := int(rect.size.x / 8.0)
	for i in range(count):
		var x := rect.position.x + i * 8.0 + 3.0
		draw_rect(Rect2(x, rect.position.y, 1.5, rect.size.y), Color(0.03, 0.05, 0.07, 0.75))
	# roof shadow
	draw_rect(Rect2(rect.position.x, rect.position.y, rect.size.x, 3.0), Color(0, 0, 0, 0.45))
	# front rail
	draw_line(Vector2(rect.position.x, rect.position.y + rect.size.y - 0.4), Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y - 0.4), Color(0.7, 0.78, 0.84, 0.20), 0.4)

func _draw_ad_strip(rect: Rect2, variant: int) -> void:
	var c := Color("#0e1a24") if variant == 0 else Color("#101d26")
	draw_rect(rect, c)
	draw_line(rect.position, rect.position + Vector2(rect.size.x, 0), Color(1, 1, 1, 0.10), 0.06)
	var per := rect.size.x / 3.0
	for i in range(3):
		var x := rect.position.x + per * i + per * 0.5
		var col := Color("#da291c") if (i + variant) % 2 == 0 else Color("#6cabdd")
		draw_rect(Rect2(x - 2.2, rect.position.y + 0.45, 4.4, 0.10), col)
		draw_rect(Rect2(x - 1.5, rect.position.y + 0.72, 3.0, 0.05), Color(1, 1, 1, 0.35))

func _draw_ad_strip_v(rect: Rect2, variant: int) -> void:
	draw_rect(rect, Color("#0e1a24"))
	for i in range(4):
		var y := rect.position.y + rect.size.y / 4.0 * (i + 0.5)
		var col := Color("#da291c") if (i + variant) % 2 == 0 else Color("#6cabdd")
		draw_circle(Vector2(rect.position.x + rect.size.x * 0.5, y - 0.55), 0.14, col)
		draw_line(Vector2(rect.position.x + 0.3, y), Vector2(rect.position.x + rect.size.x - 0.3, y), Color(1, 1, 1, 0.10), 0.04)


# gd-tools: no cover end
