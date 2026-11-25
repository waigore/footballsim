class_name LeagueSheet
extends RefCounted

## The season hub pose: today's plan beside the table, with CONTINUE.
##
## The hub is pure: `hub_layout()` turns the season state into rows and chips
## with rects (so a headless test can press them), and `draw_hub_*()` paints
## exactly those rects. No sim calls happen here. Doors that must not move (the
## bottom bar and BACK) are tagged `pinned`; everything else scrolls inside
## LeagueBody.
##
## The hub owns the pose, not the rows: `LeaguePlanSheet` lays and paints the
## plan, `LeagueSideTable` the side standings, and `LeagueChrome` the bars every
## league sheet shares (header, bottom bar, compact breakpoint, zone colours).
## The New League wizard and the Load library are the menu-level front door, not
## the hub: they live in `LeagueStartSheet`.

const ROW_H := LeagueChrome.ROW_H
const ROW_GAP := LeagueChrome.ROW_GAP
const BAR_H := LeagueChrome.BAR_H
const HEADER := LeagueChrome.HEADER

var cache := {}
## Dates this sheet painted, with the strip each one occupies (#99): the screen's
## overlay paints the weekday for the one under the pointer.
var hints := DateHints.new()
## Club names the plan and the side table painted, with the strip each one
## occupies (#107): a long press on one raises the Teams of Interest menu.
## Design space, like `hints`.
var names := InterestNames.new()
## The plan's rows and their own name registry, and the side standings.
var plan := LeaguePlanSheet.new()
var side := LeagueSideTable.new()

func _init() -> void:
	# One registry, so a long press reads every club strip the hub painted.
	plan.names = names

static func zone_color(band: String) -> Color:
	return LeagueChrome.zone_color(band)

static func compact(vp: Vector2) -> bool:
	return LeagueChrome.compact(vp)

static func watch_pending(plan_state: Array) -> bool:
	return LeagueChrome.watch_pending(plan_state)

# ------------------------------------------------------------------- hub ---

## The shortlist's mark per club, as the plan rows carry it (#104): the hub's
## state names the clubs, the mark answers what each one's ink is.
static func interest_view(state: Dictionary) -> Dictionary:
	return LeagueInterestMark.set_of(state.get("interests", []))

## The plan's left edge, its right edge, and where its first row starts.
func _plan_lane(vp: Vector2) -> Dictionary:
	var top: float = HEADER + (14.0 if not compact(vp) else 8.0)
	var wide := vp.x >= 760.0 and not compact(vp)
	var right: float = (vp.x - 72.0) * 0.58 + 24.0 if wide else vp.x - 24.0
	return {"left": 24.0, "right": right, "top": top + 24.0, "chrome_top": top}

## The lane the wide hub's side table occupies, beside the fixture list.
func _hub_table_box(vp: Vector2) -> Rect2:
	return LeagueSideTable.box(vp, float(_plan_lane(vp)["right"]))

## The side table's column rail: the same compact set the TABLE sheet paints,
## spread across the whole lane so the numbers fill it (a club abbreviation needs
## far less room than a club name).
func _hub_table_places(box: Rect2) -> Dictionary:
	return LeagueSideTable.places(box)

func hub_layout(vp: Vector2, state: Dictionary) -> Array:
	var lane := _plan_lane(vp)
	var top := float(lane["chrome_top"])
	var interest := interest_view(state)
	var items: Array = LeaguePlanSheet.layout(state.get("plan", []), interest,
		float(lane["left"]), float(lane["right"]), float(lane["top"]))
	if vp.x >= 760.0 and not compact(vp):
		items.append_array(LeagueSideTable.layout(state.get("table", []),
			state.get("rules", {}), interest, _hub_table_box(vp), float(lane["top"])))
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
	var parts: Array = []
	for comp in state.get("competitions", []):
		parts.append("%s GW %d" % [str(comp.get("short", comp.get("id", ""))), int(comp.get("matchday", 1))])
	if parts.is_empty():
		parts.append("GW %d" % int(state.get("matchday", 1)))
	parts.append("%d OF %d PLAYED" % [int(state.get("played", 0)), int(state.get("total", 0))])
	var rest := " · " + " · ".join(PackedStringArray(parts))
	# A left-behind watch is still being played out: the result lands on its own.
	if bool(state.get("settling", false)):
		rest += " · FINISHING THE WATCHED MATCH"
	var bold: Font = fonts["bold"]
	var name := str(state.get("name", "LEAGUE"))
	# CONTINUE owns the top-right corner, so the title and the caption are fitted
	# inside the lane it leaves (#163, #180).
	var right: float = LeagueExtra.primary_rect(vp).size.x + 12.0
	var band := LeagueExtra.header(c, vp, fonts, name, label + rest, right)
	if date != "" and str(band["caption"]) != "":
		var rect: Rect2 = band["caption_rect"]
		hints_out.add(Rect2(rect.position.x, 24.0, DateHints.width(bold, label, 10), 14.0), date)

func draw_hub_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, items: Array,
		state: Dictionary) -> void:
	hints.clear()
	names.clear()
	var lane := _plan_lane(vp)
	# The body hands back only the rows that scroll; the pinned doors are painted
	# by the screen itself. Split them by the grammar that owns them.
	var plan_items: Array = []
	var table_items: Array = []
	var suggest: Dictionary = {}
	for item in items:
		if str(item.get("id", "")) == "suggest":
			suggest = item
			continue
		match str(item.get("kind", "")):
			"row", "chip", "league_head":
				plan_items.append(item)
			"table_row":
				table_items.append(item)
	## The plan hint rides the caption: the first fixture row starts right under
	## it, so a second line would print through the row. A day that still holds
	## watches says what CONTINUE does with them (#100); a played row never
	## counts, whatever flag it was left with (#124).
	var hint := " · TAP A GAME TO SWITCH AUTO / WATCH" if bool(state.get("can_suggest", false)) else ""
	if watch_pending(state.get("plan", [])):
		hint = " · CONTINUE OPENS THE NEXT WATCH"
	UiChrome.text(c, Vector2(24.0, HEADER + 18.0), "TODAY'S FIXTURES" + hint, 11,
		UiChrome.C_DIM, fonts["bold"])
	if vp.x >= 760.0 and not compact(vp):
		side.draw_head(c, _hub_table_box(vp), float(lane["chrome_top"]), fonts)
	if (state.get("plan", []) as Array).is_empty():
		UiChrome.text(c, Vector2(24.0, HEADER + 44.0),
			"No fixtures on this day — CONTINUE moves the clock.", 12, UiChrome.C_SOFT, fonts["med"])
	plan.draw(c, plan_items, fonts)
	if not suggest.is_empty():
		var rect: Rect2 = suggest["rect"]
		UiChrome.panel(c, cache, rect, UiChrome.C_PANEL_LIGHT, 6, UiChrome.C_GOLD, 1)
		UiChrome.text_c(c, rect.get_center().x, rect.position.y + rect.size.y * 0.5 + 4.0,
			"SUGGEST WATCHES", 10, UiChrome.C_GOLD, fonts["bold"])
	side.draw(c, table_items, fonts, names)

# gd-tools: no cover end
