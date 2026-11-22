class_name HudPlayerCard
extends RefCounted

## Player dossier shown when a token is tracked. Split out of hud.gd so the
## overlay keeps its P3 size budget, and so the handheld variant can stack the
## same numbers horizontally instead of into a column that no phone has room for.

const W := 286.0
const W_TOUCH := 340.0
const H := 452.0

var panel_col := Color.BLACK
var gold := Color.WHITE
var ink := Color.WHITE
var dim := Color.GRAY
var touch := false
var _bg := StyleBoxFlat.new()

func _init(panel: Color, accent: Color, text_col: Color, muted: Color) -> void:
	panel_col = panel
	gold = accent
	ink = text_col
	dim = muted
	_bg.bg_color = panel
	_bg.set_corner_radius_all(12)
	_bg.set_border_width_all(1)
	_bg.border_color = Color(1, 1, 1, 0.10)

func player(engine, game):
	if game.focus_id < 0 or engine == null:
		return null
	return engine.by_id.get(game.focus_id, null)

## Where the card sits for this viewport. Read by the drawer and by the layout
## test, so a phone build can prove the card stays clear of the ticker and the
## stats panel instead of being judged from a screenshot.
func rect_for(vp: Vector2) -> Rect2:
	if HudLayout.is_compact(vp):
		var w: float = minf(W_TOUCH, vp.x - 48.0)
		var top: float = HudLayout.stats_rect(vp).end.y + 4.0
		var bottom: float = HudLayout.commentary_rect(vp).position.y - 8.0
		var h: float = clampf(bottom - top, 96.0, 132.0)
		return Rect2(vp.x - 12.0 - w, bottom - h, w, h)
	return Rect2(vp.x - 12.0 - W, 176.0, W, H)

func draw(c: CanvasItem, vp: Vector2, f_bold: Font, f_med: Font, engine, game) -> void:
	var p = player(engine, game)
	if p == null:
		return
	if HudLayout.is_compact(vp):
		_draw_compact(c, vp, f_bold, f_med, p, engine)
	else:
		_draw_column(c, vp, f_bold, f_med, p, engine)

# ------------------------------------------------------------- handheld ----

## Horizontal card: header, six attribute bars, four match numbers. Dropped:
## the involvement list, which no phone viewport can carry beside the pitch.
## Its bottom edge parks above the commentary ticker so neither covers the other.
func _draw_compact(c: CanvasItem, vp: Vector2, f_bold: Font, f_med: Font, p, engine) -> void:
	var box := rect_for(vp)
	var w := box.size.x
	var h := box.size.y
	var x := box.position.x
	var y := box.position.y
	var team: Dictionary = engine.teams[p.team]["data"]
	c.draw_style_box(_bg, Rect2(x, y, w, h))
	c.draw_rect(Rect2(x + 1, y + 1, w - 2, 4), team["color"])
	c.draw_rect(Rect2(x + 12, y + 11, 3, 20), gold)
	_label(c, Vector2(x + 22, y + 25), "#%d" % p.number, 13, gold, f_bold)
	_label(c, Vector2(x + 52, y + 26), p.name.to_upper(), 16, ink, f_bold)
	_label(c, Vector2(x + 22, y + 41), "%s  ·  %s" % [team["name"].to_upper(), p.pos_label], 9, dim, f_med)
	_label_right(c, x + w - 14, y + 27, str(p.attr["ovr"]), 20, ink, f_bold)
	_label_right(c, x + w - 14, y + 41, "OVR", 8, dim, f_bold)
	_label(c, Vector2(x + 22, y + 57), "ATTRIBUTES", 8, dim, f_bold)
	var attrs := _attrs(p)
	var cw: float = (w - 34.0) / float(attrs.size())
	for i in range(attrs.size()):
		var ax: float = x + 22.0 + cw * float(i)
		var val: float = _value(p, str(attrs[i][1]))
		_label(c, Vector2(ax, y + 68), str(attrs[i][0]), 8, dim, f_bold)
		c.draw_rect(Rect2(ax, y + 71, cw - 8.0, 4), Color(1, 1, 1, 0.08))
		c.draw_rect(Rect2(ax, y + 71, (cw - 8.0) * val / 100.0, 4), team["color"].lerp(Color.WHITE, 0.10))
		_label(c, Vector2(ax, y + 87), str(int(val)), 10, ink, f_bold)
	if h < 126.0:
		return
	var st: Dictionary = p.stats
	var cells := [
		["PASSES", "%d/%d" % [st["passes_ok"], st["passes"]]],
		["SHOTS", str(st["shots"])],
		["TACKLES", str(st["tackles"])],
		["RATING", "%.1f" % rating(p)],
	]
	var nw: float = (w - 34.0) / float(cells.size())
	for i in range(cells.size()):
		var nx: float = x + 22.0 + nw * float(i)
		_label(c, Vector2(nx, y + 101), str(cells[i][0]), 8, dim, f_bold)
		_label(c, Vector2(nx, y + 116), str(cells[i][1]), 14, ink, f_bold)
	_label(c, Vector2(x + 22, y + h - 5), "TAP THE PITCH TO CLEAR", 8, dim, f_med)

# -------------------------------------------------------------- desktop ----

func _draw_column(c: CanvasItem, vp: Vector2, f_bold: Font, f_med: Font, p, engine) -> void:
	var w := W
	var h := H
	var x: float = vp.x - 12.0 - w
	var y := 176.0
	var team: Dictionary = engine.teams[p.team]["data"]
	c.draw_style_box(_bg, Rect2(x, y, w, h))
	c.draw_rect(Rect2(x + 1, y + 1, w - 2, 4), team["color"])
	_label(c, Vector2(x + 14, y + 27), "#%d" % p.number, 16, gold, f_bold)
	_label(c, Vector2(x + 44, y + 28), p.name.to_upper(), 17, ink, f_bold)
	_label(c, Vector2(x + 14, y + 47), "%s  ·  %s" % [team["name"].to_upper(), p.pos_label], 9, dim, f_med)
	_label_right(c, x + w - 14, y + 29, str(p.attr["ovr"]), 24, ink, f_bold)
	_label_right(c, x + w - 14, y + 45, "OVR", 8, dim, f_bold)
	var attrs := _attrs(p)
	var ay: float = y + 68.0
	_label(c, Vector2(x + 14, ay), "ATTRIBUTES", 9, dim, f_bold)
	ay += 10.0
	for a in attrs:
		var val: float = _value(p, str(a[1]))
		_label(c, Vector2(x + 14, ay + 10), str(a[0]), 9, dim, f_bold)
		c.draw_rect(Rect2(x + 46, ay + 2, 168, 6), Color(1, 1, 1, 0.07))
		c.draw_rect(Rect2(x + 46, ay + 2, 168 * val / 100.0, 6), team["color"].lerp(Color.WHITE, 0.10))
		_label_right(c, x + w - 14, ay + 10, str(int(val)), 10, ink, f_bold)
		ay += 15.0
	ay += 8.0
	c.draw_line(Vector2(x + 16, ay), Vector2(x + w - 16, ay), Color(1, 1, 1, 0.07), 1)
	ay += 14.0
	var st: Dictionary = p.stats
	var cells := [
		["PASSES", "%d/%d" % [st["passes_ok"], st["passes"]]], ["SHOTS", str(st["shots"])],
		["TACKLES", str(st["tackles"])], ["TOUCHES", str(st["touches"])],
		["DIST", "%.1f km" % (st["distance"] / 1000.0)], ["RATING", "%.1f" % rating(p)],
	]
	var cw: float = (w - 28.0) / 3.0
	for i in range(cells.size()):
		var cx: float = x + 14.0 + float(i % 3) * cw
		var cy: float = ay + float(i / 3) * 34.0
		_label(c, Vector2(cx, cy), str(cells[i][0]), 8, dim, f_bold)
		_label(c, Vector2(cx, cy + 16), str(cells[i][1]), 15, ink, f_bold)
	ay += 76.0
	_label(c, Vector2(x + 14, ay), "MATCH INVOLVEMENTS", 9, dim, f_bold)
	ay += 8.0
	var list: Array = p.involvements
	var start := maxi(0, list.size() - 7)
	for i in range(start, list.size()):
		var inv: Dictionary = list[i]
		var ty: float = ay + 16.0 + float(i - start) * 17.0
		_label(c, Vector2(x + 14, ty), "%d'" % int(inv["minute"]), 9, gold, f_bold)
		var txt: String = str(inv["text"])
		if txt.length() > 32:
			txt = txt.substr(0, 31) + "…"
		_label(c, Vector2(x + 40, ty), txt, 9, Color(0.84, 0.89, 0.91), f_med)
	var hint := "TAP THE PITCH TO CLEAR" if touch else "CLICK PLAYER AGAIN TO CLEAR"
	_label(c, Vector2(x + 14, y + h - 12), hint, 8, dim, f_med)

func _attrs(p) -> Array:
	if p.is_gk:
		return [["DIV", "div"], ["HAN", "han"], ["KIC", "kic"], ["REF", "ref"], ["SPD", "spd"]]
	return [["PAC", "pac"], ["SHO", "sho"], ["PAS", "pas"], ["DRI", "dri"], ["DEF", "def"], ["PHY", "phy"]]

func _value(p, key: String) -> float:
	return float(p.gk[key]) if p.is_gk else float(p.attr[key])

func rating(p) -> float:
	var st: Dictionary = p.stats
	var r := 6.0
	r += st["goals"] * 1.2 + st["assists"] * 0.7 + st["shots"] * 0.12
	r += st["passes_ok"] * 0.006 + st["tackles"] * 0.12
	r -= st["fouls"] * 0.05
	return clampf(r, 4.0, 10.0)

func _label(c: CanvasItem, pos: Vector2, s: String, size: int, color: Color, font: Font) -> void:
	c.draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _label_right(c: CanvasItem, right_x: float, y: float, s: String, size: int, color: Color, font: Font) -> void:
	var w: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	c.draw_string(font, Vector2(right_x - w, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
