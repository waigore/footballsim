class_name MenuScreen
extends RefCounted

## Cold-start entry: product wordmark, the four doors, and the Ken Burns still
## track behind them. The stills themselves are owned (and drawn) by AppShell;
## this sheet only positions chrome and answers hit-tests, so a headless test
## can check every rect without a renderer.
##
## Motion is decorative: the still track never covers a door and never eats
## input, because nothing here is animated except the backdrop rectangles.

const STILL_PATHS := [
	"res://assets/menu/stadium.jpg",
	"res://assets/menu/duel.jpg",
	"res://assets/menu/keeper.jpg",
	"res://assets/menu/trophy.jpg",
	"res://assets/menu/celebrate.jpg",
]

const STILL_COUNT := 5
## Seconds each still holds the screen, including its crossfade tail.
const SLOT := 11.0
const FADE := 1.8
## Footer copy sits on the stills, so it gets a lighter tone than panel dim.
const FOOT := Color(0.66, 0.73, 0.77)

var mouse := Vector2(-1000, -1000)
var has_match := false
var _cache := {}

# ------------------------------------------------------------- still track --

## Crossfade weight of the incoming still at time `t` (0 = fully the current
## one, 1 = fully the next).
static func fade_alpha(t: float) -> float:
	var local: float = fmod(t, SLOT)
	var start: float = SLOT - FADE
	if local <= start:
		return 0.0
	var u: float = clampf((local - start) / FADE, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)

static func current_still(t: float) -> int:
	return posmod(int(floor(t / SLOT)), STILL_COUNT)

static func next_still(t: float) -> int:
	return posmod(current_still(t) + 1, STILL_COUNT)

## Ken Burns rect for one still. Always covers the whole viewport so a pan can
## never expose an edge; the zoom only grows, the drift only a couple of per
## cent, and the direction alternates so the loop does not pump.
static func ken_rect(vp: Vector2, index: int, t: float) -> Rect2:
	var u: float = clampf(fmod(t, SLOT) / SLOT, 0.0, 1.0)
	var zoom: float = lerpf(1.06, 1.16, u)
	var dir: float = 1.0 if index % 2 == 0 else -1.0
	var drift := Vector2(dir * lerpf(-0.02, 0.02, u) * vp.x, lerpf(0.015, -0.015, u) * vp.y)
	var size: Vector2 = vp * zoom
	return Rect2(vp * 0.5 + drift - size * 0.5, size)

# ----------------------------------------------------------------- layout ---

## Doors on the menu, in reading order: Start Sim is always primary; Resume only
## exists while a match is waiting behind the menu; the two league doors open
## the god-mode season surfaces.
static func door_ids(has_match_now: bool) -> Array:
	var ids: Array = ["start"]
	if has_match_now:
		ids.append("resume")
	ids.append("new_league")
	ids.append("load_league")
	ids.append("settings")
	ids.append("quit")
	return ids

static func door_rects(vp: Vector2, has_match_now: bool) -> Array:
	var compact: bool = vp.y < 620.0
	var mx: float = clampf(vp.x * 0.07, 24.0, 96.0)
	var ids := door_ids(has_match_now)
	var n: float = float(ids.size())
	var w: float = minf(340.0, vp.x - 2.0 * mx)
	var bottom_pad: float = 18.0 if compact else 60.0
	var top: float = vp.y * (0.40 if compact else 0.50)
	# Never trade a door for the title: on a short design viewport (a 720p
	# handset) the column slides up until every door stays on screen at tap size.
	var stacked: float = 44.0 * n + 10.0 * (n - 1.0)
	if compact:
		top = clampf(minf(top, vp.y - bottom_pad - stacked), 8.0, vp.y)
	var avail: float = maxf(vp.y - top - bottom_pad, 0.0)
	# Gaps take what is left after the minimum tap height, never a fixed guess:
	# six doors must still fit a landscape phone.
	var gap: float = clampf((avail - 44.0 * n) / maxf(n - 1.0, 1.0), 0.0, 12.0)
	var h: float = clampf((avail - gap * (n - 1.0)) / n, 44.0, 56.0)
	var out: Array = []
	for i in range(ids.size()):
		out.append({"id": ids[i], "rect": Rect2(mx, top + float(i) * (h + gap), w, h)})
	return out

# ------------------------------------------------------------------ input ---

## Hit-tests read the same rects the draw pass uses, so a headless test can
## press a door without a renderer.
func button_at(p: Vector2, vp: Vector2) -> String:
	for b in door_rects(vp, has_match):
		if (b["rect"] as Rect2).has_point(p):
			return str(b["id"])
	return ""

func click(p: Vector2, vp: Vector2) -> String:
	return button_at(p, vp)

# ----------------------------------------------------------------- drawing --

func draw(c: CanvasItem, vp: Vector2, fonts: Dictionary, has_match_now: bool, volume: float = 0.7, touch: bool = false) -> void:
	has_match = has_match_now
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	var compact: bool = vp.y < 620.0
	var mx: float = clampf(vp.x * 0.07, 24.0, 96.0)
	var short: bool = vp.y < 400.0
	var title_size: int = 48 if short else (64 if compact else 96)
	var y: float = vp.y * (0.22 if short else (0.28 if compact else 0.335))
	UiChrome.wordmark(c, Vector2(mx, y), title_size, bold)
	if not short:
		UiChrome.text(c, Vector2(mx + 2.0, y + 25.0), "PREMIER LEAGUE MATCH SIMULATOR", 13, FOOT, med)
		c.draw_rect(Rect2(mx + 2.0, y + 36.0, 88.0, 3.0), UiChrome.C_GOLD)
	_draw_doors(c, vp, fonts, has_match_now, touch)
	if not compact:
		c.draw_rect(Rect2(mx, vp.y - 62.0, vp.x - 2.0 * mx, 1.0), Color(1, 1, 1, 0.07))
		var hint := "TAP A DOOR TO BEGIN" if touch else "ENTER  START SIM     ESC  QUIT"
		UiChrome.text(c, Vector2(mx, vp.y - 40.0), hint, 12, FOOT, med)
		UiChrome.text_r(c, vp.x - mx, vp.y - 40.0, "MENU MUSIC  %d%%" % int(round(volume * 100.0)), 12, FOOT, bold)

func _draw_doors(c: CanvasItem, vp: Vector2, fonts: Dictionary, has_match_now: bool, touch: bool) -> void:
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	var hints := {"start": "", "resume": "", "new_league": "", "load_league": "", "settings": "", "quit": ""}
	if not touch:
		hints = {"start": "ENTER", "resume": "", "new_league": "N", "load_league": "L", "settings": "S", "quit": "ESC"}
	for b in door_rects(vp, has_match_now):
		var r: Rect2 = b["rect"]
		var id: String = str(b["id"])
		var hovered: bool = r.has_point(mouse)
		if id == "start":
			UiChrome.panel(c, _cache, r, UiChrome.C_GOLD.darkened(0.06 if hovered else 0.0), 8, Color(0.96, 0.78, 0.30, 0.85), 1)
			UiChrome.text(c, Vector2(r.position.x + 22.0, r.position.y + r.size.y * 0.5 + 7.0), "START SIM", 20, Color(0.06, 0.06, 0.05), bold)
			_hint(c, r, str(hints[id]), med, Color(0.20, 0.17, 0.08))
		else:
			var fill: Color = UiChrome.C_PANEL_LIGHT if hovered else UiChrome.C_PANEL
			UiChrome.panel(c, _cache, r, fill, 8, Color(1, 1, 1, 0.14 if hovered else 0.08), 1)
			UiChrome.text(c, Vector2(r.position.x + 22.0, r.position.y + r.size.y * 0.5 + 7.0), _label(id), 20, UiChrome.C_TEXT, bold)
			_hint(c, r, str(hints[id]), med, UiChrome.C_DIM)

func _hint(c: CanvasItem, r: Rect2, s: String, font: Font, col: Color) -> void:
	if s == "":
		return
	UiChrome.text_r(c, r.end.x - 20.0, r.position.y + r.size.y * 0.5 + 6.0, s, 10, col, font)

func _label(id: String) -> String:
	if id == "resume":
		return "RESUME MATCH"
	if id == "new_league":
		return "NEW LEAGUE"
	if id == "load_league":
		return "LOAD LEAGUE"
	if id == "settings":
		return "SETTINGS"
	if id == "quit":
		return "QUIT"
	return "START SIM"
