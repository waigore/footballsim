extends Node2D

## Draws the 22 players and the ball. Shapes only; every label is drawn in the
## HUD so the type stays crisp at any zoom.

var game = null
var engine = null
var ball_trail: Array = []
var ball_trail_t := 0.0
var last_ball_pos := Vector2.ZERO
var hover_id := -1
var focus_id := -1
var names_visible := true
var time := 0.0
var flash := 0.0

func _ready() -> void:
	z_index = -5

func _process(delta: float) -> void:
	time += delta
	if engine == null:
		return
	ball_trail_t += delta
	if ball_trail_t > 0.045:
		ball_trail_t = 0.0
		ball_trail.append({"p": engine.ball.pos, "z": engine.ball.z})
		if ball_trail.size() > 26:
			ball_trail.pop_front()
	if engine.ball.pos.distance_to(last_ball_pos) > 8.0:
		ball_trail.clear()
	last_ball_pos = engine.ball.pos
	flash = maxf(0.0, flash - delta * 1.5)
	queue_redraw()

func _draw() -> void:
	if engine == null:
		return
	# Focused player's full-match movement trail.
	if focus_id >= 0:
		var fp = engine.by_id.get(focus_id, null)
		if fp != null:
			_draw_trail(fp)
	# shadows
	for p in engine.players:
		if p.sent_off:
			continue
		if p.celebrate > 0.0:
			pass
		var off := Vector2(0.26, 0.48)
		draw_circle(p.pos + off, 0.94, Color(0, 0, 0, 0.26))
		draw_circle(p.pos + off * 1.6, 0.86, Color(0, 0, 0, 0.14))
	# bodies, sorted by y so lower players overlap correctly
	var order := []
	for p in engine.players:
		if not p.sent_off:
			order.append(p)
	order.sort_custom(func(a, b): return a.pos.y < b.pos.y)
	var owner = engine.ball_owner()
	for p in order:
		var own_ball: bool = owner != null and owner.id == p.id
		if own_ball:
			draw_arc(p.pos, 1.42, 0, TAU, 44, Color(1, 1, 1, 0.34), 0.12, true)
		_draw_player(p, own_ball)
	# ball (drawn above the players, with its shadow tied to the ground)
	_draw_ball()

func _draw_player(p, own_ball: bool) -> void:
	var team: Dictionary = engine.teams[p.team]["data"]
	var kit: Dictionary = engine.teams[p.team].get("kit", {})
	var base: Color = kit.get("shirt", team["color"])
	var shorts: Color = kit.get("shorts", team["shorts"])
	if p.is_gk:
		base = team["gk_color"]
		shorts = base.darkened(0.45)
	var pos: Vector2 = p.pos - Vector2(0, p.z * 0.55)
	var r := 0.86
	# selected ring
	if p.id == focus_id:
		var pulse := 0.16 + 0.05 * sin(time * 5.0)
		draw_arc(p.pos, 1.30 + pulse, 0, TAU, 44, Color(1.0, 0.86, 0.35, 0.95), 0.14, true)
		draw_arc(p.pos, 1.60 + pulse, 0, TAU, 44, Color(1.0, 0.86, 0.35, 0.22), 0.34, true)
	elif p.id == hover_id:
		draw_arc(p.pos, 1.24, 0, TAU, 40, Color(1, 1, 1, 0.78), 0.10, true)
	# body
	draw_circle(pos, r, base.darkened(0.12))
	draw_circle(pos + Vector2(-0.16, -0.20), r * 0.74, base.lightened(0.18))
	draw_arc(pos, r, 0, TAU, 44, base.darkened(0.62), 0.11, true)
	# shorts hint: a small dark arc at the bottom
	draw_arc(pos, r * 0.86, PI * 0.12, PI * 0.88, 16, Color(shorts.r, shorts.g, shorts.b, 0.95), 0.14, true)
	# direction tick
	var d: Vector2 = p.facing
	if d.length() > 0.1:
		draw_line(pos + d * (r * 0.30), pos + d * (r + 0.34), Color(1, 1, 1, 0.30), 0.08, true)
	# sprint dust
	if p.vel.length() > 6.5 and p.z <= 0.01:
		draw_circle(p.pos - p.vel.normalized() * 0.7, 0.20, Color(1, 1, 1, 0.06))
	# card marker
	if p.yellow > 0:
		draw_rect(Rect2(p.pos + Vector2(0.45, -1.05), Vector2(0.22, 0.32)), Color("#f4d03f"))
	if p.red:
		draw_rect(Rect2(p.pos + Vector2(0.15, -1.05), Vector2(0.22, 0.32)), Color("#d0342c"))

func _draw_ball() -> void:
	var b = engine.ball
	var height: float = b.z
	var lift := height * 0.55
	var sh: Vector2 = b.pos
	var sr := 0.38 / (1.0 + height * 0.10)
	draw_circle(sh, sr, Color(0, 0, 0, 0.34 / (1.0 + height * 0.16)))
	var draw_pos: Vector2 = sh - Vector2(0, lift)
	var r := 0.42 * (1.0 + height * 0.075)
	if height > 0.9:
		draw_line(sh, draw_pos, Color(1, 1, 1, 0.16), 0.035)
	# trail
	for i in range(ball_trail.size()):
		var t: Dictionary = ball_trail[i]
		var a: float = float(i) / float(ball_trail.size())
		var tp: Vector2 = t["p"] - Vector2(0, float(t["z"]) * 0.55)
		draw_circle(tp, 0.12 + 0.06 * a, Color(1, 1, 1, 0.04 + 0.10 * a))
	# ball
	draw_circle(draw_pos, r * 1.85, Color(1.0, 1.0, 1.0, 0.10))
	draw_circle(draw_pos, r * 1.30, Color(0.05, 0.08, 0.05, 0.20))
	draw_circle(draw_pos, r * 1.12, Color(0.98, 0.99, 0.98, 0.55))
	draw_circle(draw_pos, r * 1.18, Color(0.08, 0.10, 0.10, 0.55))
	draw_circle(draw_pos, r, Color("#ffffff"))
	draw_circle(draw_pos + Vector2(0.02, -0.02), r * 0.86, Color("#ffffff"))
	# classic panel spots
	var spin: float = time * (2.2 + b.vel.length() * 0.10)
	draw_circle(draw_pos + Vector2(cos(spin) * r * 0.42, sin(spin) * r * 0.42), r * 0.22, Color("#20262b"))
	draw_circle(draw_pos + Vector2(cos(spin + 2.4) * r * 0.46, sin(spin + 2.4) * r * 0.46), r * 0.16, Color("#20262b"))
	draw_circle(draw_pos + Vector2(cos(spin + 4.2) * r * 0.34, sin(spin + 4.2) * r * 0.34), r * 0.14, Color("#20262b"))

func _draw_trail(p) -> void:
	var trail: Array = p.trail
	if trail.size() < 2:
		return
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var n := trail.size()
	var stride := 1
	if n > 900:
		stride = int(ceil(n / 900.0))
	var i := 0
	while i < n:
		pts.append(trail[i])
		var a: float = float(i) / float(n)
		cols.append(Color(1.0, 0.82, 0.30, 0.12 + a * 0.55))
		i += stride
	draw_polyline_colors(pts, cols, 0.16, true)
	# involvement markers
	for inv in p.involvements:
		var ip: Vector2 = inv["pos"]
		var col := Color(1, 1, 1, 0.5)
		match inv["type"]:
			"goal": col = Color("#ffd54a")
			"shot": col = Color("#ff6a4d")
			"assist", "pass": col = Color("#6fd1ff")
			"tackle": col = Color("#9adf8a")
			"card": col = Color("#ff5a5a")
		draw_circle(ip, 0.16, Color(col.r, col.g, col.b, 0.55))
