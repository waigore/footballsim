class_name LeagueTransferSheet
extends RefCounted


const HEADER := LeagueExtra.HEADER
const ROW_H := LeagueExtra.ROW_H
const GAP := LeagueExtra.GAP

var cache := {}

var hints := DateHints.new()


func layout(vp: Vector2, view: Dictionary) -> Array:
	var touch := bool(view.get("touch", false))
	var items: Array = []
	items.append(LeagueExtra.back_item(touch))
	var row_h: float = UiChrome.tap_h(ROW_H, touch)
	var y := HEADER + 12.0
	items.append({"id": "", "kind": "caption", "label": "WINDOWS",
		"rect": Rect2(24.0, y, vp.x - 48.0, 20.0)})
	y += 24.0
	var windows: Array = view.get("windows", [])
	for window in windows:
		var row: Dictionary = window
		items.append({"id": "transfer:window:" + str(row.get("country", "")), "kind": "window",
			"window": row, "rect": Rect2(24.0, y, vp.x - 48.0, row_h)})
		y += row_h + GAP
	if not bool(view.get("any_open", false)) and not windows.is_empty():
		items.append({"id": "", "kind": "note", "label": _closed_line(windows),
			"rect": Rect2(24.0, y, vp.x - 48.0, 22.0)})
		y += 26.0
	y += 6.0
	items.append({"id": "", "kind": "caption", "label": "NEWS",
		"rect": Rect2(24.0, y, vp.x - 48.0, 20.0)})
	items.append({"id": "transfer:news", "kind": "button", "label": "OPEN FEED",
		"primary": false, "rect": Rect2(vp.x - 24.0 - 140.0, y - 4.0, 140.0,
			UiChrome.tap_h(28.0, touch))})
	y += 26.0
	var news: Array = view.get("news", [])
	if news.is_empty():
		items.append({"id": "", "kind": "note",
			"label": "The window has not moved yet.",
			"rect": Rect2(24.0, y, vp.x - 48.0, 22.0)})
		y += 26.0
	for item in news:
		var row: Dictionary = item
		items.append({"id": "deal:" + str(row.get("deal_id", "")), "kind": "market_row",
			"row": row, "rect": Rect2(24.0, y, vp.x - 48.0, row_h)})
		y += row_h + GAP
	y += 6.0
	items.append({"id": "", "kind": "caption", "label": "FREE AGENTS",
		"rect": Rect2(24.0, y, vp.x - 48.0, 20.0)})
	y += 24.0
	for item in view.get("free_agents", []):
		var row: Dictionary = item
		items.append({"id": "player:" + str(row.get("id", "")), "kind": "free_agent",
			"row": row, "rect": Rect2(24.0, y, vp.x - 48.0, row_h)})
		y += row_h + GAP
	y += 6.0
	items.append({"id": "", "kind": "caption", "label": "TOP MOVERS",
		"rect": Rect2(24.0, y, vp.x - 48.0, 20.0)})
	y += 24.0
	for item in view.get("movers", []):
		var row: Dictionary = item
		items.append({"id": "deal:" + str(row.get("id", "")), "kind": "mover",
			"row": row, "rect": Rect2(24.0, y, vp.x - 48.0, row_h)})
		y += row_h + GAP
	return items


static func _closed_line(windows: Array) -> String:
	var opens := ""
	for window in windows:
		var when := str((window as Dictionary).get("opens_on", ""))
		if when != "" and (opens == "" or when < opens):
			opens = when
	if opens == "":
		return "THE WINDOW IS CLOSED"
	return "THE WINDOW IS CLOSED · OPENS %s" % opens

# gd-tools: no cover start

func draw_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		_hints: DateHints) -> void:
	LeagueExtra.header(c, vp, fonts, "TRANSFERS", str(view.get("date", "")), 0.0, true,
		bool(view.get("touch", false)))

func draw_body(c: CanvasItem, _vp: Vector2, fonts: Dictionary, items: Array,
		_view: Dictionary) -> void:
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	for item in items:
		var rect: Rect2 = item["rect"]
		var kind := str(item["kind"])
		if kind == "caption":
			UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 14.0), str(item["label"]), 10,
				UiChrome.C_DIM, bold)
		elif kind == "note":
			UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 14.0), str(item["label"]), 10,
				UiChrome.C_SOFT, med)
		elif kind == "button":
			UiChrome.button(c, cache, rect, str(item["label"]), bold, bool(item.get("primary", false)))
		elif kind == "window":
			var window: Dictionary = item["window"]
			var open := bool(window.get("open", false))
			UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 6,
				UiChrome.C_GOLD if open else UiChrome.C_BORDER, 1)
			var name := str(window.get("name", MarketWindows.name(str(window.get("country", "")))))
			UiChrome.text(c, Vector2(rect.position.x + 12.0, rect.position.y + rect.size.y * 0.5
				+ UiChrome.RISE), name.to_upper(), 12, UiChrome.C_TEXT, bold)
			var line: String
			if open:
				line = "OPEN · CLOSES %s" % str(window.get("closes_on", ""))
			else:
				line = "CLOSED · OPENS %s" % str(window.get("opens_on", ""))
			UiChrome.text_r(c, rect.end.x - 12.0, rect.position.y + rect.size.y * 0.5 + UiChrome.RISE,
				line, 9, UiChrome.C_GOLD if open else UiChrome.C_DIM, bold)
		elif kind == "market_row":
			var news: Dictionary = item["row"]
			UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 6)
			UiChrome.text(c, Vector2(rect.position.x + 12.0, rect.position.y + rect.size.y * 0.5
				+ UiChrome.RISE), str(news.get("headline", "")), 11, UiChrome.C_TEXT, bold)
		elif kind == "free_agent":
			var agent: Dictionary = item["row"]
			UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 6)
			UiChrome.text(c, Vector2(rect.position.x + 12.0, rect.position.y + rect.size.y * 0.5
				+ UiChrome.RISE), str(agent.get("name", "")), 12, UiChrome.C_TEXT, bold)
			UiChrome.text_r(c, rect.end.x - 12.0, rect.position.y + rect.size.y * 0.5
				+ UiChrome.RISE, "%s · %s · %s" % [str(agent.get("pos", "")),
					str(agent.get("ovr", "")), str(agent.get("last_club", ""))], 9,
				UiChrome.C_DIM, med)
		elif kind == "mover":
			var mover: Dictionary = item["row"]
			UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 6)
			UiChrome.text(c, Vector2(rect.position.x + 12.0, rect.position.y + rect.size.y * 0.5
				+ UiChrome.RISE), "%s → %s" % [str(mover.get("from_name", "")),
					str(mover.get("to_name", ""))], 11, UiChrome.C_TEXT, bold)
			UiChrome.text_r(c, rect.end.x - 12.0, rect.position.y + rect.size.y * 0.5
				+ UiChrome.RISE, "%s · %s" % [str(mover.get("player_name", "")),
					MarketCurrency.format(int(mover.get("fee", 0)))], 9, UiChrome.C_GOLD, bold)

# gd-tools: no cover end
