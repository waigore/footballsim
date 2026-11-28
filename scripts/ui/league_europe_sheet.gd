class_name LeagueEuropeSheet
extends RefCounted


const HEADER := LeagueChrome.HEADER
const CARD_H := 64.0
const CARD_TOUCH_H := 72.0
const CARD_GAP := 8.0
const CAPTION_H := 22.0
const CHIP_H := 28.0

var cache := {}
var hints := DateHints.new()
var names := InterestNames.new()
var plan := LeaguePlanSheet.new()


static func card_h(touch: bool) -> float:
	return CARD_TOUCH_H if touch else CARD_H


static func chip_h(touch: bool) -> float:
	return UiChrome.tap_h(CHIP_H, touch)


func layout(vp: Vector2, view: Dictionary) -> Array:
	var touch := bool(view.get("touch", false))
	var items: Array = []
	var width := vp.x - 48.0
	var y := HEADER + 12.0
	var cards: Array = view.get("cards", [])
	for card in cards:
		items.append({"id": "europe:comp:" + str(card.get("id", "")),
			"kind": "europe_card", "card": card,
			"rect": Rect2(24.0, y, width, card_h(touch))})
		y += card_h(touch) + CARD_GAP
	if cards.is_empty():
		items.append({"id": "", "kind": "note",
			"label": "THIS SAVE DOES NOT RUN THE UEFA CLUB COMPETITIONS",
			"rect": Rect2(24.0, y, width, 20.0)})
		y += 28.0
	var draws: Array = view.get("draws", [])
	if not draws.is_empty():
		items.append({"id": "", "kind": "caption", "label": "DRAW CEREMONY",
			"rect": Rect2(24.0, y, width, 16.0)})
		y += CAPTION_H
		for draw in draws:
			items.append({"id": "europe:draw:%s:%s" % [str(draw.get("competition", "")),
				str(draw.get("round", ""))], "kind": "draw_chip",
				"label": str(draw.get("label", "")),
				"rect": Rect2(24.0, y, minf(width, 320.0), chip_h(touch))})
			y += chip_h(touch) + 6.0
	items.append({"id": "", "kind": "caption", "label": "TONIGHT",
		"rect": Rect2(24.0, y, width, 16.0)})
	y += CAPTION_H
	var interest := LeagueInterestMark.set_of(view.get("interests", []))
	items.append_array(LeaguePlanSheet.layout(view.get("tonight", []), interest,
		24.0, vp.x - 24.0, y, touch))
	items.append(LeagueExtra.back_item(touch))
	items.append({"id": "continue", "kind": "button", "label": "CONTINUE", "primary": true,
		"pinned": true, "rect": LeagueExtra.primary_rect(vp, 140.0, touch)})
	return items

# gd-tools: no cover start


func draw_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		hints_out: DateHints) -> void:
	var touch := bool(view.get("touch", false))
	var right: float = LeagueExtra.primary_rect(vp, 140.0, touch).size.x + 12.0
	var day := str(view.get("day", ""))
	var caption := "CONTINENTAL NIGHTS" if day == "" else day + " · UEFA NIGHTS"
	var band: Dictionary = LeagueExtra.header(c, vp, fonts, "EUROPE", caption, right, true, touch)
	var date := str(view.get("date", ""))
	if date != "" and str(band.get("caption", "")) != "":
		var rect: Rect2 = band["caption_rect"]
		hints_out.add(Rect2(rect.position.x, 24.0, DateHints.width(fonts["bold"],
			FixtureCalendar.day_label(date), 10), 14.0), date)


func draw_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, items: Array,
		view: Dictionary) -> void:
	hints.clear()
	names.clear()
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	var plan_items: Array = []
	for item in items:
		var kind := str(item.get("kind", ""))
		if kind in ["row", "league_head", "chip"]:
			plan_items.append(item)
			continue
		var rect: Rect2 = item["rect"]
		if kind == "europe_card":
			_card(c, rect, item["card"], fonts)
		elif kind == "caption":
			_section(c, rect, str(item["label"]), fonts)
		elif kind == "draw_chip":
			UiChrome.panel(c, cache, rect, UiChrome.C_PANEL_LIGHT, 6, UiChrome.C_GOLD, 1)
			UiChrome.text(c, Vector2(rect.position.x + 10.0,
				rect.position.y + rect.size.y * 0.5 + 4.0),
				"RUN THE DRAW  ·  " + str(item["label"]), 10, UiChrome.C_GOLD, bold)
		elif kind == "note":
			UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 12.0),
				str(item["label"]), 12, UiChrome.C_SOFT, med)
	if (view.get("tonight", []) as Array).is_empty() and not (view.get("cards", []) as Array).is_empty():
		UiChrome.text(c, Vector2(24.0, plan_top(items) + 14.0),
			"No UEFA fixture is due today — CONTINUE moves the clock.", 12, UiChrome.C_SOFT, med)
	plan.draw(c, plan_items, fonts)


static func plan_top(items: Array) -> float:
	for item in items:
		if str(item.get("kind", "")) == "row":
			return (item["rect"] as Rect2).position.y
	return HEADER + 200.0


func _card(c: CanvasItem, rect: Rect2, card: Dictionary, fonts: Dictionary) -> void:
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	var short := str(card.get("short", ""))
	UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 7, UiChrome.C_BORDER, 1)
	c.draw_rect(Rect2(rect.position.x + 1.0, rect.position.y + 8.0, 4.0,
		rect.size.y - 16.0), LeagueChrome.zone_color(_band(short)))
	UiChrome.text(c, Vector2(rect.position.x + 16.0, rect.position.y + 26.0),
		str(card.get("name", short)), 15, UiChrome.C_TEXT, bold)
	UiChrome.text(c, Vector2(rect.position.x + 16.0, rect.position.y + 46.0),
		str(card.get("stage", "")), 11, UiChrome.C_GOLD, med)
	var next := str(card.get("next", ""))
	var tail := "COMPLETE" if bool(card.get("done", false)) else \
		("NEXT " + FixtureCalendar.day_label(next) if next != "" else "NO NIGHT AHEAD")
	UiChrome.text_r(c, rect.end.x - 12.0, rect.position.y + 26.0, tail, 10,
		UiChrome.C_SOFT, bold)
	UiChrome.text_r(c, rect.end.x - 12.0, rect.position.y + 46.0,
		"%d CLUBS STILL IN" % int(card.get("alive", 0)), 10, UiChrome.C_DIM, med)


func _section(c: CanvasItem, rect: Rect2, label: String, fonts: Dictionary) -> void:
	var bold: Font = fonts["bold"]
	UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 11.0), label, 10,
		UiChrome.C_GOLD, bold)
	var width := UiChrome.text_width(bold, label, 10)
	c.draw_rect(Rect2(rect.position.x + width + 8.0, rect.position.y + 7.0,
		maxf(rect.size.x - width - 8.0, 0.0), 1.0), Color(1, 1, 1, 0.10))


static func _band(short: String) -> String:
	match short:
		"CHAMPIONS LEAGUE":
			return "ucl"
		"EUROPA LEAGUE":
			return "uel"
		"CONFERENCE LEAGUE":
			return "uecl"
	return "ucl"

# gd-tools: no cover end
