class_name LeagueCupSheet
extends RefCounted


const HEADER := LeagueChrome.HEADER
const BAR_H := LeagueChrome.BAR_H
const ROW_H := 40.0
const GAP := 8.0
const CARD_H := 78.0

var cache := {}

var hints := DateHints.new()

func layout(vp: Vector2, view: Dictionary) -> Array:
	var touch := bool(view.get("touch", false))
	var items: Array = []
	var row_h: float = UiChrome.tap_h(ROW_H, touch)
	var open := str(view.get("cup", ""))
	if open == "":
		items.append({"id": "", "kind": "extent",
			"rect": Rect2(24.0, HEADER, vp.x - 48.0, _hub_extent(vp, view, touch))})
		var cups: Array = view.get("cups", [])
		var y := HEADER + 26.0
		for i in range(cups.size()):
			var cup: Dictionary = cups[i]
			items.append({"id": "cup:" + str(cup["id"]), "kind": "card", "cup": cup,
				"rect": Rect2(24.0, y + float(i) * (CARD_H + GAP), vp.x - 48.0, CARD_H)})
	else:
		items.append({"id": "", "kind": "extent",
			"rect": Rect2(24.0, HEADER, vp.x - 48.0, _page_extent(vp, view, touch))})
		var y := HEADER + 26.0
		items.append({"id": "", "kind": "caption", "label": "ROUNDS",
			"rect": Rect2(24.0, y, vp.x - 48.0, 18.0)})
		y += 22.0
		var rounds: Array = view.get("rounds", [])
		for i in range(rounds.size()):
			var round_row: Dictionary = rounds[i]
			items.append({"id": "round:" + str(round_row["id"]), "kind": "round",
				"round": round_row, "selected": str(round_row["id"]) == str(view.get("round", "")),
				"rect": Rect2(24.0, y + float(i) * (row_h + GAP), vp.x - 48.0, row_h)})
		y += float(rounds.size()) * (row_h + GAP) + 10.0
		var ties: Array = view.get("ties", [])
		if ties.is_empty():
			items.append({"id": "", "kind": "note",
				"label": "This round is not drawn yet — CONTINUE runs the draw.",
				"rect": Rect2(24.0, y, vp.x - 48.0, 24.0)})
		for i in range(ties.size()):
			var fx: Dictionary = ties[i]
			var h: float = maxf(row_h, LeagueBlock.height(fx))
			items.append({"id": "fixture:" + str(fx["id"]), "kind": "tie", "fixture": fx,
				"rect": Rect2(24.0, y + float(i) * (h + GAP), vp.x - 48.0, h)})
	items.append(LeagueExtra.back_item(touch))
	items.append({"id": "continue", "kind": "button", "label": "CONTINUE", "primary": true,
		"pinned": true, "rect": LeagueExtra.primary_rect(vp, 140.0, touch)})
	return items


func _hub_extent(_vp: Vector2, view: Dictionary, _touch: bool) -> float:
	return float((view.get("cups", []) as Array).size()) * (CARD_H + GAP) + 34.0


func _page_extent(_vp: Vector2, view: Dictionary, touch: bool) -> float:
	var row_h: float = UiChrome.tap_h(ROW_H, touch)
	var rounds: Array = view.get("rounds", [])
	var ties: Array = view.get("ties", [])
	return 34.0 + float(rounds.size()) * (row_h + GAP) + 10.0 \
		+ float(maxi(ties.size(), 1)) * (row_h + GAP) + 40.0

# gd-tools: no cover start

func draw_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		_hints: DateHints) -> void:
	var open := str(view.get("cup", ""))
	var title := "DOMESTIC CUPS"
	var caption := "%d COMPETITIONS" % (view.get("cups", []) as Array).size()
	if open != "":
		title = str(view.get("cup_name", open))
		caption = str(view.get("cup_stage_label", ""))
	var right: float = LeagueExtra.primary_rect(vp, 140.0, bool(view.get("touch", false))).size.x + 12.0
	LeagueExtra.header(c, vp, fonts, title, caption, right, true, bool(view.get("touch", false)))

func draw_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, items: Array,
		view: Dictionary) -> void:
	hints.clear()
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	for item in items:
		var rect: Rect2 = item["rect"]
		match str(item.get("kind", "")):
			"card":
				_paint_card(c, rect, item["cup"], bold, med)
			"caption":
				UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 14.0),
					str(item["label"]), 10, UiChrome.C_DIM, bold)
			"note":
				UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 15.0),
					str(item["label"]), 11, UiChrome.C_SOFT, med)
			"round":
				_paint_round(c, rect, item, bold, med)
			"tie":
				_paint_tie(c, rect, item["fixture"], bold, med)

func _paint_card(c: CanvasItem, rect: Rect2, cup: Dictionary, bold: Font, med: Font) -> void:
	var done := str(cup.get("winner", "")) != ""
	UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 7,
		UiChrome.C_GOLD if done else UiChrome.C_BORDER, 1)
	UiChrome.text(c, Vector2(rect.position.x + 14.0, rect.position.y + 22.0),
		str(cup["name"]).to_upper(), 14, UiChrome.C_TEXT, bold)
	var stage := str(cup.get("stage", ""))
	var stage_label := "COMPLETE" if done else LeagueCupHub.label(str(cup["id"]), stage)
	UiChrome.text(c, Vector2(rect.position.x + 14.0, rect.position.y + 42.0),
		stage_label.to_upper(), 10, UiChrome.C_GOLD, bold)
	var alive := int(cup.get("alive", 0))
	var tail := "%d CLUBS IN" % alive if alive > 0 and not done else "SETTLED"
	if done:
		tail = "%s BEAT %s" % [LeagueCup.name_of(str(cup["winner"])),
			LeagueCup.name_of(str(cup.get("runner_up", "")))]
	UiChrome.text(c, Vector2(rect.position.x + 14.0, rect.position.y + 60.0),
		tail, 10, UiChrome.C_DIM, med)
	var next := str(cup.get("next", ""))
	if next != "":
		UiChrome.text_r(c, rect.end.x - 14.0, rect.position.y + 22.0,
			FixtureCalendar.day_label(next), 10, UiChrome.C_SOFT, bold)
	if done:
		UiChrome.text_r(c, rect.end.x - 14.0, rect.position.y + 60.0,
			str(cup.get("score", "")), 11, UiChrome.C_GOLD, bold)

func _paint_round(c: CanvasItem, rect: Rect2, item: Dictionary, bold: Font, med: Font) -> void:
	var round_row: Dictionary = item["round"]
	var on := bool(item.get("selected", false))
	UiChrome.panel(c, cache, rect, Color(0.96, 0.78, 0.30, 0.14) if on else UiChrome.C_PANEL, 6,
		UiChrome.C_GOLD if on else UiChrome.C_BORDER, 1)
	UiChrome.text(c, Vector2(rect.position.x + 12.0, rect.position.y + rect.size.y * 0.5 + 4.0),
		str(round_row.get("name", round_row.get("id", ""))).to_upper(), 12,
		UiChrome.C_GOLD if on else UiChrome.C_TEXT, bold)
	var done := int(round_row.get("done", 0))
	var total := int(round_row.get("ties", 0))
	UiChrome.text_r(c, rect.end.x - 12.0, rect.position.y + rect.size.y * 0.5 + 4.0,
		"%d OF %d" % [done, total], 10, UiChrome.C_SOFT if done < total else UiChrome.C_DIM, med)

func _paint_tie(c: CanvasItem, rect: Rect2, fx: Dictionary, bold: Font, med: Font) -> void:
	var played := str(fx.get("status", "")) == "played"
	UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 6)
	UiChrome.text(c, Vector2(rect.position.x + 12.0, rect.position.y + rect.size.y * 0.5 + 5.0),
		str(fx.get("home_name", fx.get("home_club_id", ""))), 12, UiChrome.C_TEXT, bold)
	UiChrome.text_r(c, rect.end.x - 12.0, rect.position.y + rect.size.y * 0.5 + 5.0,
		str(fx.get("away_name", fx.get("away_club_id", ""))), 12, UiChrome.C_TEXT, bold)
	var mid := rect.get_center().x
	if played:
		UiChrome.text_c(c, mid, rect.position.y + rect.size.y * 0.5 + 5.0,
			"%d–%d" % [int(fx.get("home_goals", 0)), int(fx.get("away_goals", 0))], 13,
			UiChrome.C_GOLD, bold)
	else:
		UiChrome.text_c(c, mid, rect.position.y + rect.size.y * 0.5 + 4.0,
			str(fx.get("kickoff_time", "15:00")), 10, UiChrome.C_DIM, med)

# gd-tools: no cover end
