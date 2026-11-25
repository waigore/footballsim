class_name LeaguePanel
extends RefCounted

## The league season's left slide panel: navigation and system actions that
## used to be a row of doors across the bottom of the hub.
##
## Geometry, motion, paint and hit-testing live together here so a headless
## test can open, settle and press a row without a renderer. The panel owns no
## league state: `active` is the destination id the screen says is on screen.

## Destinations, in reading order. `icon` names a PNG under assets/ui/league.
const ITEMS := [
	{"id": "nav:fixtures", "label": "TODAY'S FIXTURES", "icon": "fixtures", "pose": "hub"},
	{"id": "nav:table", "label": "TABLES", "icon": "table", "pose": "table"},
	{"id": "nav:calendar", "label": "CALENDAR", "icon": "calendar", "pose": "calendar"},
	{"id": "nav:interest", "label": "TEAMS OF INTEREST", "icon": "interest", "pose": "interest"},
	{"id": "nav:stats", "label": "STATS", "icon": "stats", "pose": "stats"},
	{"id": "nav:system", "label": "SYSTEM", "icon": "system", "pose": "system"},
]

const HEAD := 84.0
const ROW_H := 46.0
const ROW_GAP := 4.0
const TAB_W := 24.0
const TAB_H := 104.0
## Seconds the slide takes end to end; a settled panel never blocks input.
const SLIDE := 0.22

## 0 = closed, 1 = fully out. `target` is where the animation is heading.
var slide := 0.0
var target := 0.0
## Destination id on screen, supplied by the screen each refresh.
var active := "nav:fixtures"
var cache := {}
var icons := {}

func open() -> void:
	target = 1.0

func close() -> void:
	target = 0.0

func toggle() -> void:
	target = 0.0 if target > 0.5 else 1.0

func is_open() -> bool:
	return slide > 0.02 or target > 0.5

func settled() -> bool:
	return is_equal_approx(slide, target)

## Advance the slide. Returns true while the panel is still moving, so the
## screen can repaint; once settled it costs nothing and eats no input.
func update(delta: float) -> bool:
	if settled():
		return false
	slide = move_toward(slide, target, delta / SLIDE)
	return true

## Snap the slide where it was heading (a test or a pose switch needs no wait).
func settle() -> void:
	slide = target

static func eased(u: float) -> float:
	return u * u * (3.0 - 2.0 * u)

func width(vp: Vector2) -> float:
	return minf(300.0, vp.x * 0.84)

func panel_rect(vp: Vector2) -> Rect2:
	var w := width(vp)
	return Rect2(-w + w * eased(slide), 0.0, w, vp.y)

## The always-available tab on the left edge that opens the panel. It rides
## above the panel when that is settled open, so closing is never a hunt.
func tab_rect(vp: Vector2) -> Rect2:
	return Rect2(-2.0, vp.y * 0.5 - TAB_H * 0.5, TAB_W, TAB_H)

func item_rect(vp: Vector2, index: int) -> Rect2:
	return Rect2(panel_rect(vp).position.x + 12.0, HEAD + float(index) * (ROW_H + ROW_GAP),
		width(vp) - 24.0, ROW_H)

## What a press lands on. Closed: only the edge tab. Open: a nav row, or the
## scrim that dismisses the panel; the rest of the sheet is not reachable while
## the panel is out, so a stray tap can never press a row underneath it.
func hit(p: Vector2, vp: Vector2) -> String:
	if slide <= 0.02:
		return "panel" if tab_rect(vp).has_point(p) and target <= 0.5 else ""
	var rect := panel_rect(vp)
	if not rect.has_point(p):
		return "panel:close"
	for i in range(ITEMS.size()):
		if item_rect(vp, i).has_point(p):
			return str(ITEMS[i]["id"])
	# Inside the panel but between rows (its header and footer): no action, and
	# certainly not a dismissal.
	return ""

# ------------------------------------------------------------------ paint ---

# gd-tools: no cover start

func draw(c: CanvasItem, vp: Vector2, fonts: Dictionary, active_pose: String) -> void:
	if slide <= 0.01:
		_draw_tab(c, vp, fonts)
		return
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	c.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.0, 0.0, 0.0, 0.42 * eased(slide)))
	var rect := panel_rect(vp)
	UiChrome.panel(c, cache, rect, UiChrome.C_BG.lerp(Color(0.02, 0.03, 0.04), 0.5), 0,
		Color(0.96, 0.78, 0.30, 0.35), 1)
	c.draw_rect(Rect2(rect.position.x + rect.size.x - 3.0, 0.0, 3.0, vp.y), UiChrome.C_GOLD)
	UiChrome.text(c, Vector2(rect.position.x + 22.0, 34.0), "LEAGUE", 12, UiChrome.C_GOLD, bold)
	UiChrome.text(c, Vector2(rect.position.x + 22.0, 54.0), "NAVIGATION", 10, UiChrome.C_DIM, med)
	c.draw_rect(Rect2(rect.position.x + 22.0, 66.0, rect.size.x - 46.0, 1.0), UiChrome.C_BORDER)
	for i in range(ITEMS.size()):
		_draw_item(c, vp, i, active_pose, fonts)
	UiChrome.text(c, Vector2(rect.position.x + 22.0, vp.y - 18.0),
		"LONG-PRESS A TEAM NAME TO MARK IT", 8, UiChrome.C_DIM, med)

func _draw_item(c: CanvasItem, vp: Vector2, index: int, active_pose: String, fonts: Dictionary) -> void:
	var item: Dictionary = ITEMS[index]
	var rect := item_rect(vp, index)
	var on := str(item["pose"]) == active_pose
	if on:
		UiChrome.panel(c, cache, rect, Color(0.96, 0.78, 0.30, 0.16), 6, Color(0.96, 0.78, 0.30, 0.55), 1)
		c.draw_rect(Rect2(rect.position.x + 1.0, rect.position.y + 8.0, 3.0, rect.size.y - 16.0), UiChrome.C_GOLD)
	var ink: Color = UiChrome.C_GOLD if on else UiChrome.C_SOFT
	_draw_icon(c, str(item["icon"]), Rect2(rect.position.x + 16.0, rect.position.y + 12.0, 22.0, 22.0), ink)
	UiChrome.text(c, Vector2(rect.position.x + 50.0, rect.position.y + 29.0), str(item["label"]), 12,
		UiChrome.C_TEXT if on else UiChrome.C_SOFT, fonts["bold"])

func _draw_icon(c: CanvasItem, name: String, rect: Rect2, ink: Color) -> void:
	var tex: Texture2D = icons.get(name, null)
	if tex == null:
		tex = load("res://assets/ui/league/%s.png" % name)
		icons[name] = tex
	if tex != null:
		c.draw_texture_rect(tex, rect, false, ink)

## Closed state: a thin pull tab on the left edge. Two rules read as a menu at
## any size and are tinted gold, matching the sheet's accents.
func _draw_tab(c: CanvasItem, vp: Vector2, _fonts: Dictionary) -> void:
	var rect := tab_rect(vp)
	UiChrome.panel(c, cache, Rect2(rect.position.x, rect.position.y, rect.size.x + 6.0, rect.size.y),
		UiChrome.C_PANEL_LIGHT, 6, Color(0.96, 0.78, 0.30, 0.35), 1)
	for i in range(3):
		c.draw_rect(Rect2(rect.position.x + 7.0, rect.position.y + 44.0 + float(i) * 7.0, 10.0, 2.0),
			UiChrome.C_GOLD)

# gd-tools: no cover end
