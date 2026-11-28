class_name LeagueExtra
extends RefCounted


const HEADER := 58.0
const ROW_H := 34.0
const GAP := 6.0
const FIELD_H := 38.0


const TITLE_X := 136.0
const TITLE_SIZE := 16


const CAPTION_MIN := 160.0

const NAV_DOOR := 44.0
const NAV_GAP := 8.0
const TOUCH_PRIMARY_W := 96.0
const TOUCH_TIGHT_W := 560.0
const TITLE_FLOOR := 40.0

static var header_cache := {}


static func back_rect(touch := false) -> Rect2:
	if touch:
		return Rect2(24.0, 6.0, 96.0, UiChrome.TAP_H)
	return Rect2(24.0, 12.0, 96.0, 32.0)


static func nav_rect(vp: Vector2) -> Rect2:
	var back: Rect2 = back_rect(true)
	var lane_end: float = vp.x - 24.0 - primary_width(vp, 140.0, true)
	if back.end.x + NAV_GAP + NAV_DOOR + NAV_GAP > lane_end:
		return Rect2()
	return Rect2(back.end.x + NAV_GAP, back.position.y, NAV_DOOR, NAV_DOOR)


static func title_x(vp: Vector2, touch := false, nav := true) -> float:
	if not touch or not nav:
		return TITLE_X
	var door: Rect2 = nav_rect(vp)
	if door.size.x <= 0.0:
		return TITLE_X
	return door.end.x + 12.0


static func back_item(touch := false) -> Dictionary:
	return {"id": "back", "kind": "button", "label": "BACK", "pinned": true,
		"rect": back_rect(touch)}


static func primary_width(vp: Vector2, width: float, touch: bool) -> float:
	if touch and vp.x < TOUCH_TIGHT_W:
		return minf(width, TOUCH_PRIMARY_W)
	return width


static func primary_rect(vp: Vector2, width: float = 140.0, touch := false) -> Rect2:
	var w: float = primary_width(vp, width, touch)
	if touch:
		return Rect2(vp.x - 24.0 - w, 6.0, w, UiChrome.TAP_H)
	return Rect2(vp.x - 24.0 - w, 12.0, w, 32.0)


static func row_h(touch: bool) -> float:
	return UiChrome.tap_h(ROW_H, touch)


static func header_band(vp: Vector2, bold: Font, title: String, caption: String = "",
		right: float = 0.0, caps: bool = true, touch: bool = false,
		nav: bool = true) -> Dictionary:
	var lane_end: float = vp.x - 24.0 - right
	var label: String = title.to_upper() if caps else title
	var left: float = title_x(vp, touch, nav)
	var room: float = lane_end - left
	var floor_w: float = TITLE_FLOOR if touch else 0.0
	var shown: String = "" if room <= 0.0 or room < floor_w \
		else LeagueColumns.fit_name(label, bold, TITLE_SIZE, room)
	var title_w: float = UiChrome.text_width(bold, shown, TITLE_SIZE)
	var out := {"title": shown, "title_rect": Rect2(left, 20.0, title_w, 16.0),
		"caption": "", "caption_rect": Rect2()}
	if caption == "":
		return out


	var space: float = lane_end - (left + title_w + 12.0)
	if space < CAPTION_MIN:
		return out
	var fit: String = LeagueColumns.fit_name(caption, bold, 10, space)
	var caption_w: float = UiChrome.text_width(bold, fit, 10)
	out["caption"] = fit
	out["caption_rect"] = Rect2(lane_end - caption_w, 24.0, caption_w, 14.0)
	return out


static func header(c: CanvasItem, vp: Vector2, fonts: Dictionary, title: String,
		caption: String = "", right: float = 0.0, caps: bool = true,
		touch: bool = false, nav: bool = true) -> Dictionary:
	var bold: Font = fonts["bold"]
	var rect := back_rect(touch)
	UiChrome.panel(c, header_cache, rect, UiChrome.C_PANEL_LIGHT, 7)
	UiChrome.text_c(c, rect.get_center().x, rect.position.y + rect.size.y * 0.5 + 5.0,
		"BACK", 12, UiChrome.C_TEXT, bold)
	var band := header_band(vp, bold, title, caption, right, caps, touch, nav)
	var title_rect: Rect2 = band["title_rect"]
	UiChrome.text(c, Vector2(title_rect.position.x, 36.0), str(band["title"]), TITLE_SIZE,
		UiChrome.C_GOLD, bold)
	if str(band["caption"]) != "":
		UiChrome.text_r(c, vp.x - 24.0 - right, 34.0, str(band["caption"]), 10, UiChrome.C_DIM, bold)
	c.draw_rect(Rect2(24.0, HEADER - 8.0, vp.x - 48.0, 1.0), Color(1, 1, 1, 0.08))
	return band


static func draw_league_head(c: CanvasItem, rect: Rect2, competition_id: String,
		matchday: int, fonts: Dictionary, stage: String = "") -> void:
	var name: String = PLRepository.shared().competition_name(competition_id)
	var text := "%s  ·  GW %d" % [name, matchday]
	if LeagueCup.is_cup(competition_id):
		text = "%s  ·  %s" % [name, LeagueCupView.stage_name(competition_id, stage)]
	if LeagueUefa.is_continental(competition_id):
		text = "UEFA NIGHT  ·  %s  ·  %s" % [name, LeagueEurope.badge(stage)]
	UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 12.0),
		text, 10, UiChrome.C_GOLD, fonts["bold"])
	var width := UiChrome.text_width(fonts["bold"], text, 10)
	c.draw_rect(Rect2(rect.position.x + width + 10.0, rect.position.y + 8.0,
		maxf(rect.size.x - width - 10.0, 0.0), 1.0), Color(1, 1, 1, 0.10))


static func distinct_competitions(fixtures: Array) -> int:
	var ids := {}
	for fx in fixtures:
		ids[str(fx.get("competition_id", ""))] = true
	return ids.size()
