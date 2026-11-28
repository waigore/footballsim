class_name MenuScreen
extends RefCounted


const STILL_PATHS := [
	"res://assets/menu/stadium.jpg",
	"res://assets/menu/duel.jpg",
	"res://assets/menu/keeper.jpg",
	"res://assets/menu/trophy.jpg",
	"res://assets/menu/celebrate.jpg",
]

const STILL_COUNT := 5

const SLOT := 11.0
const FADE := 1.8

const FOOT := UiChrome.C_SOFT


const TITLE_AIR := 9.0
const TITLE_GAP := 8.0


const DOOR_MIN := 44.0
const DOOR_MAX := 56.0
const DOOR_GAP_MAX := 12.0


const TAGLINE_DROP := 25.0
const TAGLINE_SIZE := 13
const RULE_DROP := 36.0

const TAGLINE_FOOT := RULE_DROP + 3.0


const SIZES := [96, 72, 64, 56, 48, 40, 32]

var mouse := Vector2(-1000, -1000)
var has_match := false
var _cache := {}


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


static func ken_rect(vp: Vector2, index: int, t: float) -> Rect2:
	var u: float = clampf(fmod(t, SLOT) / SLOT, 0.0, 1.0)
	var zoom: float = lerpf(1.06, 1.16, u)
	var dir: float = 1.0 if index % 2 == 0 else -1.0
	var drift := Vector2(dir * lerpf(-0.02, 0.02, u) * vp.x, lerpf(0.015, -0.015, u) * vp.y)
	var size: Vector2 = vp * zoom
	return Rect2(vp * 0.5 + drift - size * 0.5, size)


static func door_ids(has_match_now: bool) -> Array:
	var ids: Array = []
	if has_match_now:
		ids.append("resume")
	ids.append("start")
	ids.append("new_league")
	ids.append("load_league")
	ids.append("settings")
	ids.append("quit")
	return ids


static func primary_id(has_match_now: bool) -> String:
	if has_match_now:
		return "resume"
	return "start"


static func door_hints(has_match_now: bool) -> Dictionary:
	if has_match_now:
		return {"resume": "ENTER", "start": "T", "new_league": "N", "load_league": "L", "settings": "S", "quit": "ESC"}
	return {"start": "ENTER", "resume": "", "new_league": "N", "load_league": "L", "settings": "S", "quit": "ESC"}


static func footer_hint(has_match_now: bool, touch: bool) -> String:
	if touch:
		return "TAP A DOOR TO BEGIN"
	return "ENTER  %s     ESC  QUIT" % door_label(primary_id(has_match_now))


static func layout(vp: Vector2, has_match_now: bool, font: Font = null) -> Dictionary:
	var compact: bool = vp.y < 620.0
	var mx: float = clampf(vp.x * 0.07, 24.0, 96.0)
	var ids := door_ids(has_match_now)
	var n: float = float(ids.size())
	var w: float = minf(340.0, vp.x - 2.0 * mx)
	var bottom_pad: float = 18.0 if compact else 60.0


	var top: float = clampf(minf(vp.y * (0.40 if compact else 0.50),
		vp.y - bottom_pad - DOOR_MIN * n), 8.0, vp.y)
	var avail: float = maxf(vp.y - top - bottom_pad, 0.0)


	var gap: float = clampf((avail - DOOR_MIN * n) / maxf(n - 1.0, 1.0), 0.0, DOOR_GAP_MAX)
	var h: float = clampf((avail - gap * (n - 1.0)) / n, DOOR_MIN, DOOR_MAX)
	var doors: Array = []
	for i in range(ids.size()):
		doors.append({"id": ids[i], "rect": Rect2(mx, top + float(i) * (h + gap), w, h)})
	return {"doors": doors, "title": title_pose(vp, top, compact, font)}


static func title_pose(vp: Vector2, doors_top: float, compact: bool,
		font: Font = null) -> Dictionary:
	var short: bool = vp.y < 400.0
	var natural_y: float = vp.y * (0.22 if short else (0.28 if compact else 0.335))
	var ideal: int = 48 if short else (64 if compact else 96)


	var bold: Font = font if font != null else UiChrome.fonts()["bold"]
	var room: float = vp.x - 2.0 * clampf(vp.x * 0.07, 24.0, 96.0)
	for candidate in SIZES:
		var size := int(candidate)
		if size > ideal or UiChrome.wordmark_width(size, bold) > room:
			continue
		var wants: Array = [false] if short else [true, false]
		for tagline in wants:
			var foot: float = TAGLINE_FOOT if bool(tagline) else 0.0
			var y: float = minf(natural_y, doors_top - TITLE_GAP - foot)
			if y - float(size) >= TITLE_AIR:
				return {"size": size, "y": y, "tagline": bool(tagline)}
	return {"size": 0, "y": natural_y, "tagline": false}

static func door_rects(vp: Vector2, has_match_now: bool) -> Array:
	return layout(vp, has_match_now)["doors"]


func button_at(p: Vector2, vp: Vector2) -> String:
	for b in door_rects(vp, has_match):
		if (b["rect"] as Rect2).has_point(p):
			return str(b["id"])
	return ""

func click(p: Vector2, vp: Vector2) -> String:
	return button_at(p, vp)


func draw(c: CanvasItem, vp: Vector2, fonts: Dictionary, has_match_now: bool, volume: float = 0.7, touch: bool = false) -> void:
	has_match = has_match_now
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	var compact: bool = vp.y < 620.0
	var mx: float = clampf(vp.x * 0.07, 24.0, 96.0)


	var sheet := layout(vp, has_match_now, bold)
	var title: Dictionary = sheet["title"]
	if int(title["size"]) > 0:
		var ty: float = float(title["y"])
		UiChrome.wordmark(c, Vector2(mx, ty), int(title["size"]), bold)
		if bool(title["tagline"]):
			UiChrome.text(c, Vector2(mx + 2.0, ty + TAGLINE_DROP),
				"PREMIER LEAGUE MATCH SIMULATOR", TAGLINE_SIZE, FOOT, med)
			c.draw_rect(Rect2(mx + 2.0, ty + RULE_DROP, 88.0, 3.0), UiChrome.C_GOLD)
	_draw_doors(c, fonts, touch, sheet["doors"], has_match_now)
	if not compact:
		c.draw_rect(Rect2(mx, vp.y - 62.0, vp.x - 2.0 * mx, 1.0), Color(1, 1, 1, 0.07))
		UiChrome.text(c, Vector2(mx, vp.y - 40.0), footer_hint(has_match_now, touch), 12, FOOT, med)
		UiChrome.text_r(c, vp.x - mx, vp.y - 40.0, "MENU MUSIC  %d%%" % int(round(volume * 100.0)), 12, FOOT, bold)

func _draw_doors(c: CanvasItem, fonts: Dictionary, touch: bool, doors: Array, has_match_now: bool) -> void:
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]


	var primary := primary_id(has_match_now)
	var hints: Dictionary = {} if touch else door_hints(has_match_now)
	for b in doors:
		var r: Rect2 = b["rect"]
		var id: String = str(b["id"])
		var hovered: bool = r.has_point(mouse)
		if id == primary:
			UiChrome.panel(c, _cache, r, UiChrome.C_GOLD.darkened(0.06 if hovered else 0.0), 8, Color(0.96, 0.78, 0.30, 0.85), 1)
			UiChrome.text(c, Vector2(r.position.x + 22.0, r.position.y + r.size.y * 0.5 + 7.0), door_label(id), 20, Color(0.06, 0.06, 0.05), bold)
			_hint(c, r, str(hints.get(id, "")), med, Color(0.20, 0.17, 0.08))
		else:
			var fill: Color = UiChrome.C_PANEL_LIGHT if hovered else UiChrome.C_PANEL
			UiChrome.panel(c, _cache, r, fill, 8, Color(1, 1, 1, 0.14 if hovered else 0.08), 1)
			UiChrome.text(c, Vector2(r.position.x + 22.0, r.position.y + r.size.y * 0.5 + 7.0), door_label(id), 20, UiChrome.C_TEXT, bold)
			_hint(c, r, str(hints.get(id, "")), med, UiChrome.C_DIM)

func _hint(c: CanvasItem, r: Rect2, s: String, font: Font, col: Color) -> void:
	if s == "":
		return
	UiChrome.text_r(c, r.end.x - 20.0, r.position.y + r.size.y * 0.5 + 6.0, s, 10, col, font)

static func door_label(id: String) -> String:
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
