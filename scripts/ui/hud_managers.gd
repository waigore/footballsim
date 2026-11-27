class_name HudManagers
extends RefCounted


const HOLD_TACTICS := 7.5
const HOLD_SUB := 6.0
const WIDTH := 332.0
const TOP := 140.0

var card: Dictionary = {}
var hold := 0.0
var ev_id := -1
var box := Rect2()

var panel_col := Color.BLACK
var gold := Color.WHITE
var ink := Color.WHITE
var dim := Color.GRAY
var _bg := StyleBoxFlat.new()

func _init(panel: Color, accent: Color, text_col: Color, muted: Color) -> void:
	panel_col = panel
	gold = accent
	ink = text_col
	dim = muted
	_bg.bg_color = panel
	_bg.set_corner_radius_all(10)
	_bg.set_border_width_all(1)
	_bg.border_color = Color(1, 1, 1, 0.10)

func tick(d: float, engine, game) -> void:
	if engine == null or game == null:
		return
	if not game.paused and hold > 0.0:
		hold = maxf(0.0, hold - d)
	if hold <= 0.0 and not card.is_empty():
		card = {}
	var evs: Array = engine.events
	if evs.is_empty():
		return
	var ev: Dictionary = evs[evs.size() - 1]
	var eid: int = int(ev.get("id", -1))
	if eid == ev_id:
		return
	ev_id = eid
	var kind: String = str(ev.get("type", ""))
	if kind != "tactics" and kind != "substitution":
		return
	card = ev.duplicate(true)
	hold = HOLD_TACTICS if kind == "tactics" else HOLD_SUB

func visible() -> bool:
	return not card.is_empty()

func dismiss() -> void:
	hold = 0.0
	card = {}


func button_at(p: Vector2) -> bool:
	return visible() and box.has_point(p)

func _lines(engine) -> Array:
	var out := []
	var kind: String = str(card.get("type", ""))
	if kind == "tactics":
		var changes: Array = card.get("changes", [])
		for i in range(mini(3, changes.size())):
			out.append(str(changes[i]))
		out.append("now %s · %s" % [str(card.get("formation", "")), str(card.get("mentality", "")).replace("_", " ")])
	else:
		out.append(str(card.get("text", "")))
		out.append("%d/%d changes · window %d/%d" % [
			int(engine.teams[int(card.get("team", 0))]["subs_made"]), MatchEngine.SUB_LIMIT,
			int(card.get("window", 0)), MatchEngine.SUB_WINDOWS])
	return out

func draw(c: CanvasItem, vp: Vector2, f_bold: Font, f_med: Font, engine) -> void:
	if not visible() or engine == null:
		box = Rect2()
		return
	var lines: Array = _lines(engine)
	var w := minf(WIDTH, vp.x - 48.0)
	var h := 70.0 + float(lines.size()) * 16.0
	box = Rect2(24.0, TOP, w, h)
	var team: int = int(card.get("team", 0))
	var team_col: Color = engine.teams[team]["data"]["color"]
	c.draw_style_box(_bg, box)
	c.draw_rect(Rect2(box.position.x + 1, box.position.y + 8, 3, box.size.y - 16), team_col)
	var short: String = str(engine.teams[team]["data"]["short"])
	var minute: int = int(card.get("minute", 0))
	var kind: String = "TACTICS" if str(card.get("type", "")) == "tactics" else "CHANGE"
	_label(c, Vector2(box.position.x + 16, box.position.y + 20), "%s  ·  %d'  ·  %s" % [short, minute, kind], 10, gold, f_bold)
	_label(c, Vector2(box.position.x + 16, box.position.y + 38), str(card.get("manager", "")).to_upper(), 15, ink, f_bold)
	var y := box.position.y + 56.0
	for i in range(lines.size()):
		var txt := str(lines[i])
		if txt.length() > 44:
			txt = txt.substr(0, 43) + "…"
		_label(c, Vector2(box.position.x + 16, y), txt, 12, ink if i < lines.size() - 1 else dim, f_med)
		y += 16.0
	_label(c, Vector2(box.position.x + 16, box.position.y + h - 8), "TAP TO DISMISS", 9, dim, f_med)

func _label(c: CanvasItem, pos: Vector2, s: String, size: int, color: Color, font: Font) -> void:
	c.draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
