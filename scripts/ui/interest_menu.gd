class_name InterestMenu
extends RefCounted

## The small context menu a long-press raises over a team name. One action —
## add the club to Teams of Interest, or remove it — plus a cancel row, anchored
## where the finger pressed and clamped inside the window so it never runs off.
##
## Shared by every surface that paints a team name: the league sheets, the
## encyclopedia, the fixture picker and the match HUD. Pure geometry and paint;
## the host owns the press timing (`HOLD_MS`, `DRAG_SLOP`).

## A press shorter than this is a tap; a press that travels past the slop is a
## scroll and never opens the menu.
const HOLD_MS := 420
const DRAG_SLOP := 8.0

const W := 244.0
const H := 116.0

var club_id := ""
var club_name := ""
var at := Vector2.ZERO
var open := false
var cache := {}

func show_at(id: String, name: String, point: Vector2) -> void:
	if id == "":
		return
	club_id = id
	club_name = name
	at = point
	open = true

func hide() -> void:
	open = false
	club_id = ""
	club_name = ""

## Toggle the club this menu is about and put the menu away. With no league
## season open there is nothing to write, so the menu simply closes.
func apply() -> void:
	var season := LeagueSeason.active
	if open and season != null and season.interest != null and club_id != "":
		season.interest.set_interest(club_id, not season.interest.has(club_id))
		season.dirty = true
	hide()

## The menu's rect, clamped inside the viewport with a small margin.
func rect(vp: Vector2) -> Rect2:
	var w := minf(W, maxf(vp.x - 24.0, 60.0))
	var h := minf(H, maxf(vp.y - 24.0, 60.0))
	return Rect2(clampf(at.x, 12.0, maxf(vp.x - w - 12.0, 12.0)),
		clampf(at.y, 12.0, maxf(vp.y - h - 12.0, 12.0)), w, h)

func action_rect(vp: Vector2) -> Rect2:
	var r := rect(vp)
	return Rect2(r.position.x + 10.0, r.position.y + 46.0, r.size.x - 20.0, 32.0)

func cancel_rect(vp: Vector2) -> Rect2:
	var r := rect(vp)
	return Rect2(r.position.x + 10.0, r.position.y + 82.0, r.size.x - 20.0, 26.0)

func hit(p: Vector2, vp: Vector2) -> String:
	if not open:
		return ""
	if action_rect(vp).has_point(p):
		return "interest:toggle"
	return "interest:close"

# gd-tools: no cover start

func draw(c: CanvasItem, vp: Vector2, fonts: Dictionary, marked: bool) -> void:
	if not open:
		return
	var r := rect(vp)
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	UiChrome.panel(c, cache, r, Color(0.02, 0.03, 0.04, 0.98), 8, Color(0.96, 0.78, 0.30, 0.55), 1)
	UiChrome.text(c, Vector2(r.position.x + 12.0, r.position.y + 20.0), "TEAM OF INTEREST", 9,
		UiChrome.C_DIM, bold)
	UiChrome.text(c, Vector2(r.position.x + 12.0, r.position.y + 38.0), club_name.to_upper(), 13,
		UiChrome.C_GOLD if marked else UiChrome.C_TEXT, bold)
	var action := action_rect(vp)
	UiChrome.panel(c, cache, action, UiChrome.C_GOLD if not marked else UiChrome.C_PANEL_LIGHT, 5,
		UiChrome.C_GOLD, 1)
	UiChrome.text_c(c, action.get_center().x, action.position.y + 21.0,
		"REMOVE FROM INTEREST" if marked else "ADD TO INTEREST", 11,
		Color(0.06, 0.06, 0.05) if not marked else UiChrome.C_GOLD, bold)
	var cancel := cancel_rect(vp)
	UiChrome.text_c(c, cancel.get_center().x, cancel.position.y + 17.0, "CANCEL", 10,
		UiChrome.C_DIM, med)

# gd-tools: no cover end
