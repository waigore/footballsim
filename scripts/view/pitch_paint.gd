class_name PitchPaint
extends RefCounted


const L := 105.0
const W := 68.0
const GOAL_W := 7.32
const GOAL_D := 2.1
const BOX_D := 16.5
const BOX_W := 40.32
const SIX_D := 5.5
const SIX_W := 18.32
const PEN_D := 11.0


static func draw_frame(c: CanvasItem, grass_noise: NoiseTexture2D) -> void:
	draw_ads(c)
	draw_apron(c)
	draw_benches(c)
	draw_turf(c, grass_noise)
	draw_chalk(c)
	draw_goal(c, Vector2(0, W * 0.5), -1.0)
	draw_goal(c, Vector2(L, W * 0.5), 1.0)
	draw_corner_flags(c)


static func draw_stadium(c: CanvasItem, stadium_tex: ImageTexture) -> void:
	c.draw_rect(PitchStadium.WORLD, Color("#070d12"))
	if stadium_tex != null:
		c.draw_texture_rect(stadium_tex, PitchStadium.WORLD, false)
	for i in range(6):
		c.draw_rect(Rect2(-46, -46 + i * 3.0, 197, 3.0), Color(0, 0, 0, 0.10 - i * 0.012))


static func draw_ads(c: CanvasItem) -> void:
	draw_ad_strip(c, Rect2(-9.4, -7.4, 123.8, 1.5), 0)
	draw_ad_strip(c, Rect2(-9.4, W + 5.9, 123.8, 1.5), 1)
	draw_ad_strip_v(c, Rect2(-9.6, -6.0, 1.5, 80.0), 0)
	draw_ad_strip_v(c, Rect2(L + 8.1, -6.0, 1.5, 80.0), 1)


static func draw_apron(c: CanvasItem) -> void:
	c.draw_rect(Rect2(-6.6, -6.6, L + 13.2, W + 13.2), Color("#0f3523"))
	c.draw_rect(Rect2(-6.6, -6.6, L + 13.2, 0.35), Color(1, 1, 1, 0.10))


static func draw_benches(c: CanvasItem) -> void:
	c.draw_rect(Rect2(26.0, 68.6, 18.0, 4.4), Color(0.03, 0.08, 0.055, 0.75))
	c.draw_rect(Rect2(61.0, 68.6, 18.0, 4.4), Color(0.03, 0.08, 0.055, 0.75))
	c.draw_rect(Rect2(26.0, 68.6, 18.0, 0.18), Color(1, 1, 1, 0.22))
	c.draw_rect(Rect2(61.0, 68.6, 18.0, 0.18), Color(1, 1, 1, 0.22))
	for i in range(5):
		c.draw_rect(Rect2(27.0 + i * 3.4, 69.2, 2.4, 1.6), Color(0.10, 0.16, 0.14, 0.85))
		c.draw_rect(Rect2(62.0 + i * 3.4, 69.2, 2.4, 1.6), Color(0.10, 0.16, 0.14, 0.85))
	c.draw_rect(Rect2(25.6, 68.3, 18.8, 0.5), Color(0, 0, 0, 0.35))
	c.draw_rect(Rect2(60.6, 68.3, 18.8, 0.5), Color(0, 0, 0, 0.35))


static func draw_turf(c: CanvasItem, grass_noise: NoiseTexture2D) -> void:
	c.draw_rect(Rect2(0, 0, L, W), Color("#1d6238"))
	var stripe_w := L / 16.0
	for i in range(16):
		var col := Color("#2a7a46") if i % 2 == 0 else Color("#206437")
		c.draw_rect(Rect2(i * stripe_w, 0, stripe_w, W), col)
	for i in range(8):
		var y := i * (W / 8.0)
		c.draw_rect(Rect2(0, y, L, W / 16.0), Color(1, 1, 1, 0.018))
	if grass_noise != null:
		c.draw_texture_rect(grass_noise, Rect2(0, 0, L, W), true, Color(0.05, 0.14, 0.08, 0.38))
	for i in range(10):
		var a := 0.026 - i * 0.002
		c.draw_circle(Vector2(L * 0.5, W * 0.5), 52.0 - i * 4.2, Color(1.0, 0.99, 0.86, a))
	c.draw_rect(Rect2(0, 0, L, 7), Color(0, 0, 0, 0.10))
	c.draw_rect(Rect2(0, W - 10, L, 10), Color(0, 0, 0, 0.13))
	for pt in [Vector2(6, 34), Vector2(52.5, 34), Vector2(99, 34), Vector2(52.5, 10), Vector2(52.5, 58)]:
		c.draw_circle(pt, 2.4, Color(0.62, 0.55, 0.30, 0.06))
	c.draw_rect(Rect2(0, W - 9, L, 9), Color(0, 0, 0, 0.10))
	c.draw_rect(Rect2(0, 0, L, 6), Color(0, 0, 0, 0.06))


static func draw_chalk(c: CanvasItem) -> void:
	var chalk := Color(0.97, 0.99, 0.96, 0.95)
	var lw := 0.13
	c.draw_rect(Rect2(0, 0, L, W), chalk, false, lw)
	c.draw_line(Vector2(L * 0.5, 0), Vector2(L * 0.5, W), chalk, lw)
	c.draw_arc(Vector2(L * 0.5, W * 0.5), 9.15, 0, TAU, 96, chalk, lw, true)
	c.draw_circle(Vector2(L * 0.5, W * 0.5), 0.16, chalk)
	for side in [0, 1]:
		var gx: float = 0.0 if side == 0 else L
		var dir: float = 1.0 if side == 0 else -1.0
		c.draw_rect(Rect2(minf(gx, gx + dir * BOX_D), W * 0.5 - BOX_W * 0.5, BOX_D, BOX_W),
			chalk, false, lw)
		c.draw_rect(Rect2(minf(gx, gx + dir * SIX_D), W * 0.5 - SIX_W * 0.5, SIX_D, SIX_W),
			chalk, false, lw)
		c.draw_circle(Vector2(gx + dir * PEN_D, W * 0.5), 0.14, chalk)
		var start_ang := -0.93 if side == 0 else PI - 0.93
		var end_ang := 0.93 if side == 0 else PI + 0.93
		c.draw_arc(Vector2(gx + dir * PEN_D, W * 0.5), 9.15, start_ang, end_ang, 48, chalk, lw, true)
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
			c.draw_arc(Vector2(px, py), 1.0, a0, a0 + PI * 0.5, 16, chalk, lw, true)


static func draw_goal(c: CanvasItem, base: Vector2, dir: float) -> void:
	var half := GOAL_W * 0.5
	var post := Color(0.99, 1.0, 1.0)
	var back_x := base.x + dir * GOAL_D
	c.draw_rect(Rect2(minf(base.x, back_x), base.y - half - 0.2, GOAL_D, GOAL_W + 0.4),
		Color(0, 0, 0, 0.18))
	var net := Color(0.88, 0.93, 0.95, 0.34)
	for i in range(9):
		var y := -half + (GOAL_W / 8.0) * i
		c.draw_line(Vector2(base.x, base.y + y), Vector2(back_x, base.y + y), net, 0.025)
	for i in range(7):
		var x := base.x + dir * (GOAL_D / 6.0) * i
		c.draw_line(Vector2(x, base.y - half), Vector2(x, base.y + half), net, 0.025)
	c.draw_line(Vector2(back_x, base.y - half), Vector2(back_x, base.y + half),
		Color(0.9, 0.95, 0.97, 0.45), 0.04)
	c.draw_line(Vector2(base.x, base.y - half), Vector2(base.x, base.y + half), post, 0.16)
	c.draw_line(Vector2(base.x, base.y - half), Vector2(back_x, base.y - half), post, 0.10)
	c.draw_line(Vector2(base.x, base.y + half), Vector2(back_x, base.y + half), post, 0.10)
	c.draw_line(Vector2(back_x, base.y - half), Vector2(back_x, base.y + half), post, 0.08)
	for i in range(3):
		var px := base.x + dir * (GOAL_D / 3.0) * (i + 1)
		c.draw_line(Vector2(px, base.y - half), Vector2(px, base.y - half + 0.3), post, 0.06)


static func draw_corner_flags(c: CanvasItem) -> void:
	for px in [0.0, L]:
		for py in [0.0, W]:
			c.draw_line(Vector2(px, py), Vector2(px, py) + Vector2(0, -1.7),
				Color(0.92, 0.92, 0.92, 0.85), 0.06)
			c.draw_rect(Rect2(Vector2(px, py) + Vector2(0, -1.7), Vector2(0.62, 0.38)), Color("#e8e04a"))


static func draw_ad_strip(c: CanvasItem, rect: Rect2, variant: int) -> void:
	var col := Color("#0e1a24") if variant == 0 else Color("#101d26")
	c.draw_rect(rect, col)
	c.draw_line(rect.position, rect.position + Vector2(rect.size.x, 0), Color(1, 1, 1, 0.10), 0.06)
	var per := rect.size.x / 3.0
	for i in range(3):
		var x := rect.position.x + per * i + per * 0.5
		var brand := Color("#da291c") if (i + variant) % 2 == 0 else Color("#6cabdd")
		c.draw_rect(Rect2(x - 2.2, rect.position.y + 0.45, 4.4, 0.10), brand)
		c.draw_rect(Rect2(x - 1.5, rect.position.y + 0.72, 3.0, 0.05), Color(1, 1, 1, 0.35))


static func draw_ad_strip_v(c: CanvasItem, rect: Rect2, variant: int) -> void:
	c.draw_rect(rect, Color("#0e1a24"))
	for i in range(4):
		var y := rect.position.y + rect.size.y / 4.0 * (i + 0.5)
		var brand := Color("#da291c") if (i + variant) % 2 == 0 else Color("#6cabdd")
		c.draw_circle(Vector2(rect.position.x + rect.size.x * 0.5, y - 0.55), 0.14, brand)
		c.draw_line(Vector2(rect.position.x + 0.3, y), Vector2(rect.position.x + rect.size.x - 0.3, y),
			Color(1, 1, 1, 0.10), 0.04)
