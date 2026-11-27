class_name InterestMenu
extends RefCounted

## The little context menu a long press raises on a team name (#107): the club,
## the state of the shortlist, and the one door that follows or releases it.
##
## Geometry and paint only — where the menu is shown, which club it names and
## what a press does all live in `InterestHold`. One module paints the same menu
## on the league sheets, the encyclopedia, the fixture picker and the match HUD,
## so the gesture reads the same wherever a club name is printed.

## A press on the door: follow the club, or stop following it.
const TOGGLE := "imenu:toggle"
## A press on the ✕.
const CLOSE := "imenu:close"
## A press anywhere else: dismiss the menu and swallow the press.
const DISMISS := "imenu:dismiss"

const W := 320.0
const H := 122.0
## Air kept from the sheet's own edges, so the menu never hangs off the screen.
const EDGE := 12.0
## The press point sits a little above the menu's top edge.
const DROP := 12.0

var club_id := ""
## Full name on the title line, abbreviation on the door.
var name := ""
var abbr := ""
var followed := false
var at := Vector2.ZERO
## Pointer position in the same design space as `at`, for the door's hover fill.
var mouse := Vector2(-1000, -1000)
## Read on a handset (#310): the footer names the finger's verb, not the mouse's.
var touch := false
var cache := {}

func show(club: String, club_name: String, club_abbr: String, is_followed: bool,
		point: Vector2) -> void:
	club_id = club
	name = club_name
	abbr = club_abbr
	followed = is_followed
	at = point

func close() -> void:
	club_id = ""
	name = ""
	abbr = ""

func is_open() -> bool:
	return club_id != ""

## The card: under the press point when there is room, above it when there is
## not, and always inside the sheet.
func rect(vp: Vector2) -> Rect2:
	var w: float = minf(W, maxf(vp.x - EDGE * 2.0, 120.0))
	var x: float = clampf(at.x - 12.0, EDGE, maxf(vp.x - w - EDGE, EDGE))
	var y: float = at.y + DROP
	if y + H > vp.y - EDGE:
		y = maxf(at.y - H - DROP, EDGE)
	return Rect2(x, y, w, H)

## The follow / stop-following door.
func door_rect(vp: Vector2) -> Rect2:
	var r := rect(vp)
	return Rect2(r.position.x + 14.0, r.position.y + 68.0, r.size.x - 28.0, 38.0)

## The ✕ in the corner.
func close_rect(vp: Vector2) -> Rect2:
	var r := rect(vp)
	return Rect2(r.end.x - 40.0, r.position.y + 10.0, 28.0, 26.0)

## The door a press lands on while the menu is up. Every press is answered: a
## press beside the card dismisses it, and never reaches the sheet underneath.
func hit(p: Vector2, vp: Vector2) -> String:
	if not is_open():
		return ""
	if door_rect(vp).has_point(p):
		return TOGGLE
	if close_rect(vp).has_point(p):
		return CLOSE
	return DISMISS

## What the door says: the action a press performs, not the state it shows.
func door_label() -> String:
	if followed:
		return "STOP FOLLOWING %s" % abbr
	return "FOLLOW %s" % abbr

## The state line under the club name.
func state_line() -> String:
	if followed:
		return "FOLLOWED  ·  ITS GAMES STAY ON WATCH"
	return "NOT FOLLOWED  ·  FOLLOW TO KEEP ITS GAMES ON WATCH"

## The footer's leave hint: a mouse clicks elsewhere, a finger taps (#278, #310).
func close_hint() -> String:
	return "TAP ELSEWHERE TO CLOSE" if touch else "CLICK ELSEWHERE TO CLOSE"

# gd-tools: no cover start

func draw(c: CanvasItem, vp: Vector2, fonts: Dictionary) -> void:
	if not is_open():
		return
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	var r := rect(vp)
	c.draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.30))
	UiChrome.panel(c, cache, r, Color(0.025, 0.038, 0.048, 0.985), 12, Color(0.96, 0.78, 0.30, 0.45))
	c.draw_rect(Rect2(r.position.x + 1.0, r.position.y + 1.0, 4.0, r.size.y - 2.0), UiChrome.C_GOLD)
	UiChrome.text(c, Vector2(r.position.x + 18.0, r.position.y + 22.0), "TEAMS OF INTEREST", 9,
		UiChrome.C_GOLD, bold)
	UiChrome.text(c, Vector2(r.position.x + 18.0, r.position.y + 44.0), name.to_upper(), 17,
		UiChrome.C_TEXT if not followed else UiChrome.C_GOLD, bold)
	UiChrome.text(c, Vector2(r.position.x + 18.0, r.position.y + 60.0), state_line(), 9,
		UiChrome.C_DIM, med)
	var door := door_rect(vp)
	var over := door.has_point(mouse)
	var fill: Color = UiChrome.C_PANEL_LIGHT if followed else UiChrome.C_GOLD.darkened(0.12 if over else 0.0)
	UiChrome.panel(c, cache, door, fill, 7, UiChrome.C_GOLD, 1)
	UiChrome.text_c(c, door.get_center().x, door.position.y + 24.0, door_label(), 13,
		Color(0.06, 0.06, 0.05) if not followed else UiChrome.C_GOLD, bold)
	var close := close_rect(vp)
	if close.has_point(mouse):
		UiChrome.panel(c, cache, close, UiChrome.C_PANEL_LIGHT, 6)
	UiChrome.text_c(c, close.get_center().x, close.position.y + 19.0, "✕", 14,
		UiChrome.C_TEXT if close.has_point(mouse) else UiChrome.C_DIM, bold)
	UiChrome.text(c, Vector2(r.position.x + 18.0, r.end.y - 10.0),
		close_hint(), 8, UiChrome.C_DIM, med)

# gd-tools: no cover end
