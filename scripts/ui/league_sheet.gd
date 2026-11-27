class_name LeagueSheet
extends RefCounted


const ROW_H := LeagueChrome.ROW_H
const ROW_GAP := LeagueChrome.ROW_GAP
const BAR_H := LeagueChrome.BAR_H
const HEADER := LeagueChrome.HEADER


const HUB_TITLE := "Today's Fixtures"

var cache := {}


var hints := DateHints.new()


var names := InterestNames.new()

var plan := LeaguePlanSheet.new()

func _init() -> void:

	plan.names = names

static func zone_color(band: String) -> Color:
	return LeagueChrome.zone_color(band)

static func compact(vp: Vector2) -> bool:
	return LeagueChrome.compact(vp)

static func watch_pending(plan_state: Array) -> bool:
	return LeagueChrome.watch_pending(plan_state)


static func plan_hint(touch: bool) -> String:
	return "TAP A GAME TO SWITCH AUTO / WATCH" if touch \
		else "CLICK A GAME TO SWITCH AUTO / WATCH"


static func body_hint(state: Dictionary) -> String:
	if watch_pending(state.get("plan", [])):
		return "CONTINUE OPENS THE NEXT WATCH"
	if not bool(state.get("can_suggest", false)):
		return ""
	return plan_hint(bool(state.get("touch", false)))


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


static func interest_view(state: Dictionary) -> Dictionary:
	return LeagueInterestMark.set_of(state.get("interests", []))


func _plan_lane(vp: Vector2, touch := false, can_suggest := false) -> Dictionary:
	var top: float = HEADER + (14.0 if not compact(vp) else 8.0)
	var suggest_h: float = UiChrome.tap_h(20.0, touch)
	var drop: float = 24.0
	if touch:
		drop = 2.0 + suggest_h + 8.0 if can_suggest else 16.0
	return {"left": 24.0, "right": vp.x - 24.0, "top": top + drop, "chrome_top": top,
		"suggest_h": suggest_h}

func hub_layout(vp: Vector2, state: Dictionary) -> Array:
	var touch := bool(state.get("touch", false))
	var can_suggest := bool(state.get("can_suggest", false))
	var lane := _plan_lane(vp, touch, can_suggest)
	var top := float(lane["chrome_top"])
	var interest := interest_view(state)
	var items: Array = LeaguePlanSheet.layout(state.get("plan", []), interest,
		float(lane["left"]), float(lane["right"]), float(lane["top"]), touch)
	if can_suggest:
		var left_w: float = float(lane["right"]) - 24.0
		items.append({"id": "suggest", "kind": "chip", "label": "SUGGEST WATCHES",
			"rect": Rect2(24.0 + left_w - 150.0, top + 2.0, 150.0, float(lane["suggest_h"]))})


	items.append(LeagueExtra.back_item(touch))
	items.append({"id": "continue", "kind": "button", "label": "CONTINUE", "primary": true,
		"pinned": true, "rect": LeagueExtra.primary_rect(vp, 140.0, touch)})
	return items

# gd-tools: no cover start

func draw_hub_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, state: Dictionary,
		hints_out: DateHints) -> void:
	var date := str(state.get("date", ""))
	var label: String = FixtureCalendar.day_label(date) if date != "" else str(state.get("day", ""))
	var caption := hub_caption(state)
	var bold: Font = fonts["bold"]


	var right: float = LeagueExtra.primary_rect(vp, 140.0, bool(state.get("touch", false))).size.x + 12.0
	var band := LeagueExtra.header(c, vp, fonts, HUB_TITLE, caption, right, false,
		bool(state.get("touch", false)))
	if date != "" and str(band["caption"]) != "":
		var rect: Rect2 = band["caption_rect"]
		hints_out.add(Rect2(rect.position.x, 24.0, DateHints.width(bold, label, 10), 14.0), date)

func draw_hub_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, items: Array,
		state: Dictionary) -> void:
	hints.clear()
	names.clear()
	var lane := _plan_lane(vp, bool(state.get("touch", false)))


	var plan_items: Array = []
	var suggest: Dictionary = {}
	for item in items:
		if str(item.get("id", "")) == "suggest":
			suggest = item
			continue
		match str(item.get("kind", "")):
			"row", "chip", "league_head":
				plan_items.append(item)


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
