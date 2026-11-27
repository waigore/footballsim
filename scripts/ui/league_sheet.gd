class_name LeagueSheet
extends RefCounted

## The season hub pose: today's plan across the sheet, with CONTINUE.
##
## The hub is pure: `hub_layout()` turns the season state into rows and chips
## with rects (so a headless test can press them), and `draw_hub_*()` paints
## exactly those rects. No sim calls happen here. Doors that must not move (the
## bottom bar and BACK) are tagged `pinned`; everything else scrolls inside
## LeagueBody.
##
## The hub owns the pose, not the rows: `LeaguePlanSheet` lays and paints the
## plan — each league's fixtures under its own heading, with its gameweek — and
## `LeagueChrome` the bars every league sheet shares (header, bottom bar,
## compact breakpoint, zone colours). The hub keeps no side table: the standings
## live on the TABLES sheet, so the whole width belongs to the day's fixtures.
## The New League wizard and the Load library are the menu-level front door, not
## the hub: they live in `LeagueStartSheet`.
##
## The page names itself, not the save (#323): the title is Today's Fixtures on
## every season, and the caption carries only the day and the ledger, so the hub
## never reads as one competition's page when the day holds another's fixtures.

const ROW_H := LeagueChrome.ROW_H
const ROW_GAP := LeagueChrome.ROW_GAP
const BAR_H := LeagueChrome.BAR_H
const HEADER := LeagueChrome.HEADER

## The hub's own title (#323): the pose, never the save name. The header paints
## it in this title case instead of the kicker's caps, because it is a name and
## not a one-word label.
const HUB_TITLE := "Today's Fixtures"

var cache := {}
## Dates this sheet painted, with the strip each one occupies (#99): the screen's
## overlay paints the weekday for the one under the pointer.
var hints := DateHints.new()
## Club names the plan and the side table painted, with the strip each one
## occupies (#107): a long press on one raises the Teams of Interest menu.
## Design space, like `hints`.
var names := InterestNames.new()
## The plan's rows and their own name registry.
var plan := LeaguePlanSheet.new()

func _init() -> void:
	# One registry, so a long press reads every club strip the hub painted.
	plan.names = names

static func zone_color(band: String) -> Color:
	return LeagueChrome.zone_color(band)

static func compact(vp: Vector2) -> bool:
	return LeagueChrome.compact(vp)

static func watch_pending(plan_state: Array) -> bool:
	return LeagueChrome.watch_pending(plan_state)

## The pointer's verb on a desktop sheet and the finger's on a touch one (#278).
static func plan_hint(touch: bool) -> String:
	return "TAP A GAME TO SWITCH AUTO / WATCH" if touch \
		else "CLICK A GAME TO SWITCH AUTO / WATCH"

## The hub's body line: the pointer's verb on a desktop sheet and the finger's on
## a touch one (#278), or CONTINUE's promise while a watch is still pending
## (#100). The page is named by its header, so the hint never repeats the title
## (#323); a day with no hint paints no line at all.
static func body_hint(state: Dictionary) -> String:
	if watch_pending(state.get("plan", [])):
		return "CONTINUE OPENS THE NEXT WATCH"
	if not bool(state.get("can_suggest", false)):
		return ""
	return plan_hint(bool(state.get("touch", false)))

## The hub's header caption (#323): the day and the ledger, nothing else. Each
## league's gameweek now rides its own heading in the plan, where the fixtures
## it counts actually are, so this line never grows one chip per active league.
## A left-behind watch that is still being played out says so at the end: the
## result lands on its own.
static func hub_caption(state: Dictionary) -> String:
	var date := str(state.get("date", ""))
	var label: String = FixtureCalendar.day_label(date) if date != "" else str(state.get("day", ""))
	var caption := ""
	if label != "":
		caption = label + " · "
	caption += "%d OF %d PLAYED" % [int(state.get("played", 0)), int(state.get("total", 0))]
	if bool(state.get("settling", false)):
		caption += " · FINISHING THE WATCHED MATCH"
	return caption

# ------------------------------------------------------------------- hub ---

## The shortlist's mark per club, as the plan rows carry it (#104): the hub's
## state names the clubs, the mark answers what each one's ink is.
static func interest_view(state: Dictionary) -> Dictionary:
	return LeagueInterestMark.set_of(state.get("interests", []))

## The plan's left edge, its right edge, and where its first row starts.
func _plan_lane(vp: Vector2) -> Dictionary:
	var top: float = HEADER + (14.0 if not compact(vp) else 8.0)
	return {"left": 24.0, "right": vp.x - 24.0, "top": top + 24.0, "chrome_top": top}

func hub_layout(vp: Vector2, state: Dictionary) -> Array:
	var lane := _plan_lane(vp)
	var top := float(lane["chrome_top"])
	var interest := interest_view(state)
	var items: Array = LeaguePlanSheet.layout(state.get("plan", []), interest,
		float(lane["left"]), float(lane["right"]), float(lane["top"]))
	if bool(state.get("can_suggest", false)):
		var left_w: float = float(lane["right"]) - 24.0
		items.append({"id": "suggest", "kind": "chip", "label": "SUGGEST WATCHES",
			"rect": Rect2(24.0 + left_w - 150.0, top + 2.0, 150.0, 20.0)})
	# Chrome: BACK top-left, CONTINUE top-right; every other destination lives in
	# the left panel (#105).
	items.append(LeagueExtra.back_item())
	items.append({"id": "continue", "kind": "button", "label": "CONTINUE", "primary": true,
		"pinned": true, "rect": LeagueExtra.primary_rect(vp)})
	return items

# gd-tools: no cover start

func draw_hub_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, state: Dictionary,
		hints_out: DateHints) -> void:
	var date := str(state.get("date", ""))
	var label: String = FixtureCalendar.day_label(date) if date != "" else str(state.get("day", ""))
	var caption := hub_caption(state)
	var bold: Font = fonts["bold"]
	# CONTINUE owns the top-right corner, so the title and the caption are fitted
	# inside the lane it leaves (#163, #180). The title is the pose's own name,
	# in title case: the sheet's other titles are kickers, this one is a name.
	var right: float = LeagueExtra.primary_rect(vp).size.x + 12.0
	var band := LeagueExtra.header(c, vp, fonts, HUB_TITLE, caption, right, false)
	if date != "" and str(band["caption"]) != "":
		var rect: Rect2 = band["caption_rect"]
		hints_out.add(Rect2(rect.position.x, 24.0, DateHints.width(bold, label, 10), 14.0), date)

func draw_hub_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, items: Array,
		state: Dictionary) -> void:
	hints.clear()
	names.clear()
	var lane := _plan_lane(vp)
	# The body hands back only the rows that scroll; the pinned doors are painted
	# by the screen itself. Split by the grammar that owns them.
	var plan_items: Array = []
	var suggest: Dictionary = {}
	for item in items:
		if str(item.get("id", "")) == "suggest":
			suggest = item
			continue
		match str(item.get("kind", "")):
			"row", "chip", "league_head":
				plan_items.append(item)
	## The body's one line is the hint alone (#323): the page is already named in
	## the header, so repeating `TODAY'S FIXTURES` on it only pushed the hint
	## away from the fixtures it describes. The first fixture row starts right
	## under it, so a second line would print through the row.
	var hint := body_hint(state)
	if hint != "":
		UiChrome.text(c, Vector2(24.0, HEADER + 18.0), hint, 11,
			UiChrome.C_DIM, fonts["bold"])
	if (state.get("plan", []) as Array).is_empty():
		UiChrome.text(c, Vector2(24.0, HEADER + 44.0),
			"No fixtures on this day — CONTINUE moves the clock.", 12, UiChrome.C_SOFT, fonts["med"])
	plan.draw(c, plan_items, fonts)
	if not suggest.is_empty():
		var rect: Rect2 = suggest["rect"]
		UiChrome.panel(c, cache, rect, UiChrome.C_PANEL_LIGHT, 6, UiChrome.C_GOLD, 1)
		UiChrome.text_c(c, rect.get_center().x, rect.position.y + rect.size.y * 0.5 + 4.0,
			"SUGGEST WATCHES", 10, UiChrome.C_GOLD, fonts["bold"])

# gd-tools: no cover end
