class_name LeagueEuropeSheet
extends RefCounted


const HEADER := LeagueChrome.HEADER
const CARD_H := 86.0
const CARD_GAP := 8.0
const TONIGHT_H := 30.0
const TAP_H := 46.0
const CARD_MIN_W := 320.0


var cache := {}

var hints := DateHints.new()


var names := InterestNames.new()

static func card_height(touch: bool) -> float:
	return maxf(CARD_H, UiChrome.tap_h(CARD_H, touch))


static func row_height(touch: bool) -> float:
	return maxf(TONIGHT_H, UiChrome.tap_h(TAP_H, touch))


static func cards_top() -> float:
	return HEADER + 34.0


func layout(vp: Vector2, view: Dictionary) -> Array:
	var touch := bool(view.get("touch", false))
	var items: Array = []
	var cards: Array = view.get("cards", [])
	var w: float = maxf(vp.x - 48.0, CARD_MIN_W)
	var h: float = card_height(touch)
	var y: float = cards_top()
	for card in cards:
		items.append({"id": "europe:" + str((card as Dictionary).get("id", "")),
			"kind": "europe_card", "card": card, "rect": Rect2(24.0, y, w, h)})
		y += h + CARD_GAP
	var tonight: Array = view.get("tonight", [])
	items.append({"id": "", "kind": "caption", "label": "TONIGHT",
		"rect": Rect2(24.0, y + 10.0, w, 14.0)})
	y += 30.0
	var rh: float = row_height(touch)
	for fx in tonight:
		var fixture: Dictionary = fx
		var played := str(fixture.get("status", "")) == "played"
		var target := ""
		if played:
			target = "match:" + str(fixture.get("id", ""))
		items.append({"id": target, "kind": "tonight", "fixture": fixture,
			"rect": Rect2(24.0, y, w, rh)})
		y += rh + 4.0
	items.append(LeagueExtra.back_item(touch))
	items.append({"id": "continue", "kind": "button", "label": "CONTINUE", "primary": true,
		"pinned": true, "rect": LeagueExtra.primary_rect(vp, 140.0, touch)})
	return items

# gd-tools: no cover start

func draw_hub_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		_hints: DateHints) -> void:
	var cards: Array = view.get("cards", [])
	var caption := "NO CONTINENTAL COMPETITION IN THIS SAVE"
	if not cards.is_empty():
		var alive := 0
		for card in cards:
			alive += int((card as Dictionary).get("alive", 0))
		caption = "%d COMPETITIONS · %d CLUBS STILL IN · UEFA 2026/27" % [cards.size(), alive]
	var right: float = LeagueExtra.primary_rect(vp, 140.0, bool(view.get("touch", false))).size.x + 12.0
	LeagueExtra.header(c, vp, fonts, "EUROPE", caption, right, true,
		bool(view.get("touch", false)))


func draw_hub_body(c: CanvasItem, _vp: Vector2, fonts: Dictionary, items: Array,
		view: Dictionary) -> void:
	hints.clear()
	names.clear()
	if (view.get("cards", []) as Array).is_empty():
		UiChrome.text(c, Vector2(24.0, cards_top() + 16.0),
			"This save does not run the UEFA club competitions.", 13, UiChrome.C_SOFT,
			fonts["med"])
		UiChrome.text(c, Vector2(24.0, cards_top() + 40.0),
			"Turn them on under EUROPE in a New League.", 12, UiChrome.C_DIM, fonts["med"])
	for item in items:
		var rect: Rect2 = item["rect"]
		var kind := str(item["kind"])
		if kind == "europe_card":
			_paint_card(c, rect, item["card"], fonts)
		elif kind == "caption":
			UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 10.0), str(item["label"]),
				10, UiChrome.C_GOLD, fonts["bold"])
			c.draw_rect(Rect2(rect.position.x + 70.0, rect.position.y + 6.0,
				maxf(rect.size.x - 70.0, 0.0), 1.0), Color(1, 1, 1, 0.10))
		elif kind == "tonight":
			_paint_tonight(c, rect, item["fixture"], fonts)


func _paint_card(c: CanvasItem, rect: Rect2, card: Dictionary, fonts: Dictionary) -> void:
	UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 7, UiChrome.C_BORDER, 1)
	c.draw_rect(Rect2(rect.position.x, rect.position.y + 8.0, 3.0,
		rect.size.y - 16.0), UiChrome.C_GOLD)
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	UiChrome.text(c, Vector2(rect.position.x + 18.0, rect.position.y + 26.0),
		str(card.get("short", card.get("id", ""))), 15, UiChrome.C_GOLD, bold)
	UiChrome.text_r(c, rect.end.x - 18.0, rect.position.y + 26.0,
		"%d IN" % int(card.get("alive", 0)), 12, UiChrome.C_TEXT, bold)
	UiChrome.text(c, Vector2(rect.position.x + 18.0, rect.position.y + 46.0),
		str(card.get("stage_label", "")), 11, UiChrome.C_SOFT, med)
	var next := str(card.get("next", ""))
	if next != "":
		UiChrome.text(c, Vector2(rect.position.x + 18.0, rect.position.y + 66.0),
			"NEXT UEFA NIGHT  " + FixtureCalendar.day_label(next), 10, UiChrome.C_DIM, med)
		hints.add(Rect2(rect.position.x + 18.0, rect.position.y + 56.0,
			rect.size.x - 36.0, 14.0), next)
	if str(card.get("winner", "")) != "":
		UiChrome.text(c, Vector2(rect.position.x + 18.0, rect.position.y + 66.0),
			"%s  %s" % [str(card.get("winner_name", "")), str(card.get("score_line", ""))],
			11, UiChrome.C_TEXT, bold)


func _paint_tonight(c: CanvasItem, rect: Rect2, fx: Dictionary, fonts: Dictionary) -> void:
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 5)
	var y := rect.position.y + rect.size.y * 0.5 + 4.0
	var x := rect.position.x + 10.0
	var kick := str(fx.get("kickoff_time", ""))
	UiChrome.text(c, Vector2(x, y), "FT" if str(fx.get("status", "")) == "played" else kick, 10,
		UiChrome.C_GOLD if str(fx.get("status", "")) == "played" else UiChrome.C_DIM, bold)
	x += 38.0
	var home := str(fx.get("home_name", ""))
	var away := str(fx.get("away_name", ""))
	var room: float = maxf((rect.end.x - x - 96.0) * 0.5, 60.0)
	var home_name: String = LeagueColumns.fit_name(home, bold, 11, room)
	var away_name: String = LeagueColumns.fit_name(away, bold, 11, room)
	InterestNames.run(c, names, str(fx.get("home_club_id", "")), home_name,
		Vector2(x, y), 11, UiChrome.C_TEXT, bold)
	x += InterestNames.width(bold, home_name, 11) + 6.0
	UiChrome.text(c, Vector2(x, y), "v", 10, UiChrome.C_DIM, med)
	x += InterestNames.width(med, "v", 10) + 6.0
	InterestNames.run(c, names, str(fx.get("away_club_id", "")), away_name,
		Vector2(x, y), 11, UiChrome.C_TEXT, bold)
	var score := "%d – %d" % [int(fx.get("home_goals", 0)), int(fx.get("away_goals", 0))]
	var played := str(fx.get("status", "")) == "played"
	var tail := "OPEN"
	if played:
		tail = score
	UiChrome.text_r(c, rect.end.x - 10.0, y, tail, 11,
		UiChrome.C_TEXT if played else UiChrome.C_GOLD, bold)

# gd-tools: no cover end
