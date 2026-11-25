class_name LeagueSheet
extends RefCounted

## Shared chrome and helpers for the league season sheets: the header lane,
## bottom bar and row metrics every pose reads, the zone colours, the one
## text-field editor, and the button/chip/play grammar.
##
## Each pose owns its own geometry and paint in a sibling sheet:
## `LeagueHubSheet` (today's fixtures and the side table), `LeagueWizardSheet`
## (new season setup) and `LeagueLoadSheet` (the save list). `LeagueBook`,
## `LeagueExtra` and `LeagueSystemSheet` keep the reading poses. Everything
## here is stateless: a sheet passes its own style cache to the paint helpers.

const ROW_H := 26.0
const ROW_GAP := 5.0
const BAR_H := 52.0
const HEADER := 58.0

static func zone_color(band: String) -> Color:
	if band == "ucl":
		return UiChrome.C_GOLD
	if band == "uel":
		return UiChrome.C_LIVE
	if band == "uecl":
		return Color(0.55, 0.72, 0.92)
	if band == "relegation":
		return UiChrome.C_DANGER
	return UiChrome.C_DIM

static func compact(vp: Vector2) -> bool:
	return vp.y < 620.0

## The wizard's name field: a key either edits the name or is left for the
## screen. Returns `[handled, name]` so the caller never guesses.
static func type_name(name: String, code: int) -> Array:
	if code == KEY_BACKSPACE:
		return [true, name.substr(0, maxi(name.length() - 1, 0))]
	if name.length() >= 24:
		return [false, name]
	var ch := char(code)
	if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == " ":
		return [true, name + (ch.to_upper() if name == "" else ch)]
	return [false, name]

## Edit the name in a wizard/field state dictionary. True when the key belonged
## to the field, so the caller only has to repaint.
static func type_name_into(state: Dictionary, code: int) -> bool:
	var typed: Array = type_name(str(state.get("name", "")), code)
	if not bool(typed[0]):
		return false
	state["name"] = str(typed[1])
	return true

## Bottom action bar: equal-width doors; the first one is the primary. The
## grammar itself is `UiChrome.button`, shared with the menu, the System dialog,
## the fixture picker and the encyclopedia.
static func draw_button(c: CanvasItem, cache: Dictionary, rect: Rect2, label: String,
		bold: Font, primary: bool, disabled: bool = false) -> void:
	UiChrome.button(c, cache, rect, label, bold, primary, -1, "", not disabled)

## The ▶ beside a goal on a match report: a bordered gold chip, sized by the
## caller so the door stays thumb-sized on every platform.
static func draw_play(c: CanvasItem, cache: Dictionary, rect: Rect2, bold: Font) -> void:
	UiChrome.panel(c, cache, rect, UiChrome.C_PANEL_LIGHT, 6, Color(0.96, 0.78, 0.30, 0.55), 1)
	var mid: float = rect.position.y + rect.size.y * 0.5 + UiChrome.RISE
	UiChrome.text_c(c, rect.get_center().x, mid, "▶ PLAY", 10, UiChrome.C_GOLD, bold)

## Small fixed chips on a sheet header (the calendar's month doors).
static func draw_chip(c: CanvasItem, cache: Dictionary, rect: Rect2, label: String,
		bold: Font) -> void:
	UiChrome.chip(c, cache, rect, label, bold)

## One header for every league season sheet: BACK top-left, the title in the
## gold kicker position, and an optional right-hand caption.
static func heading(c: CanvasItem, vp: Vector2, fonts: Dictionary, title: String,
		caption: String, right: float = 0.0) -> void:
	LeagueExtra.header(c, vp, fonts, title, caption, right)
