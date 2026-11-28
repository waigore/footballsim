class_name PitchStadium
extends RefCounted


const WORLD := Rect2(-36, -36, 182, 132)


static func bake(w: int, h: int, rng: RandomNumberGenerator) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color("#070d12"))
	var sx: float = float(w) / WORLD.size.x
	var sy: float = float(h) / WORLD.size.y
	var stands := [
		[Rect2(-31, -21.5, 22.0, 110.0), 2, Color("#c24338")],
		[Rect2(115.0, -21.5, 22.0, 110.0), 3, Color("#4f9cc6")],
		[Rect2(-9.5, -21.5, 125.0, 14.4), 0, Color("#c9c3b6")],
		[Rect2(-9.5, 75.2, 125.0, 14.8), 1, Color("#9aa6b0")],
	]
	for st in stands:
		_paint_stand(img, w, h, sx, sy, st[0], int(st[1]), st[2], rng)
	_paint_roof(img, w, h, sx, sy)
	_paint_bowl(img, sx, sy)
	return ImageTexture.create_from_image(img)


static func _paint_stand(img: Image, w: int, h: int, sx: float, sy: float, r: Rect2,
		side: int, tint: Color, rng: RandomNumberGenerator) -> void:
	var ix := int((r.position.x - WORLD.position.x) * sx)
	var iy := int((r.position.y - WORLD.position.y) * sy)
	var iw := int(r.size.x * sx)
	var ih := int(r.size.y * sy)
	img.fill_rect(Rect2i(ix, iy, iw, ih), Color("#0b141b"))
	var rows := 12
	var row_h := float(ih) / rows
	for rr in range(rows):
		var depth_f: float = 1.0 - float(rr) / rows
		var base := Color("#1a2833").lerp(Color("#2b3c48"), depth_f * 0.65)
		img.fill_rect(Rect2i(ix, iy + int(rr * row_h), iw, maxi(1, int(row_h) - 1)), base)

	var row_step := 1.55
	var seat_step := 0.95
	var n_rows := int(r.size.y / row_step) if side in [0, 1] else int(r.size.x / row_step)
	var n_seats := int(r.size.x / seat_step) if side in [0, 1] else int(r.size.y / seat_step)
	for rr in range(n_rows):
		var row_pos: float = (rr + 0.5) * row_step
		if rr % 4 == 3:
			continue
		for ss in range(n_seats):
			if rng.randf() < 0.12:
				continue
			var seat_pos: float = (ss + 0.5) * seat_step + rng.randf_range(-0.18, 0.18)
			var wx: float
			var wy: float
			if side in [0, 1]:
				wx = r.position.x + seat_pos
				wy = r.position.y + row_pos
			else:
				wx = r.position.x + row_pos
				wy = r.position.y + seat_pos
			var px := int((wx - WORLD.position.x) * sx)
			var py := int((wy - WORLD.position.y) * sy)
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

	_paint_aisles(img, w, h, sx, sy, ix, iy, iw, ih, r, side)
	_paint_stand_edge(img, ix, iy, iw, ih, side)


static func _paint_aisles(img: Image, w: int, h: int, sx: float, sy: float, ix: int, iy: int,
		iw: int, ih: int, r: Rect2, side: int) -> void:
	if side in [0, 1]:
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


static func _paint_stand_edge(img: Image, ix: int, iy: int, iw: int, ih: int, side: int) -> void:
	if side in [0, 1]:
		img.fill_rect(Rect2i(ix, iy + int(ih * 0.52), iw, 2), Color(0.12, 0.17, 0.21, 1))
	else:
		img.fill_rect(Rect2i(ix + int(iw * 0.52), iy, 2, ih), Color(0.12, 0.17, 0.21, 1))

	for k in range(22):
		var a2 := 0.055 * (1.0 - k / 22.0)
		if side == 0:
			img.fill_rect(Rect2i(ix, iy + k, iw, 1), Color(0, 0, 0, a2))
		elif side == 1:
			img.fill_rect(Rect2i(ix, iy + ih - 1 - k, iw, 1), Color(0, 0, 0, a2))
		elif side == 2:
			img.fill_rect(Rect2i(ix + k, iy, 1, ih), Color(0, 0, 0, a2))
		else:
			img.fill_rect(Rect2i(ix + iw - 1 - k, iy, 1, ih), Color(0, 0, 0, a2))

	if side == 0:
		img.fill_rect(Rect2i(ix, iy + ih - 2, iw, 2), Color(0.55, 0.62, 0.68, 1))
	elif side == 1:
		img.fill_rect(Rect2i(ix, iy, iw, 2), Color(0.55, 0.62, 0.68, 1))
	elif side == 2:
		img.fill_rect(Rect2i(ix + iw - 2, iy, 2, ih), Color(0.55, 0.62, 0.68, 1))
	else:
		img.fill_rect(Rect2i(ix, iy, 2, ih), Color(0.55, 0.62, 0.68, 1))


static func _paint_roof(img: Image, w: int, h: int, sx: float, sy: float) -> void:
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


static func _paint_bowl(img: Image, sx: float, sy: float) -> void:
	var cx := int((-11.0 - WORLD.position.x) * sx)
	var cy := int((-11.0 - WORLD.position.y) * sy)
	img.fill_rect(Rect2i(cx, cy, int(127.0 * sx), int(90.0 * sy)), Color("#0a141b"))
	for i in range(2):
		img.fill_rect(Rect2i(cx, cy + int(i * 3.2 * sy), int(127.0 * sx), maxi(1, int(0.8 * sy))),
			Color(0, 0, 0, 0.2))
