class_name LeagueNewsSheet
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
	var feed: Array = view.get("feed", [])
	if feed.is_empty():
		items.append({"id": "", "kind": "note", "label": "The window has not moved yet.",
			"rect": Rect2(24.0, y, vp.x - 48.0, 22.0)})
	for item in feed:
		var row: Dictionary = item
		items.append({"id": "deal:" + str(row.get("deal_id", "")), "kind": "market_row",
			"row": row, "rect": Rect2(24.0, y, vp.x - 48.0, row_h)})
		y += row_h + GAP
	return items

# gd-tools: no cover start

func draw_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		_hints: DateHints) -> void:
	LeagueExtra.header(c, vp, fonts, "MARKET NEWS", "%d ITEMS" % int(view.get("count", 0)),
		0.0, true, bool(view.get("touch", false)))

func draw_body(c: CanvasItem, _vp: Vector2, fonts: Dictionary, items: Array,
		_view: Dictionary) -> void:
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	for item in items:
		var rect: Rect2 = item["rect"]
		var kind := str(item["kind"])
		if kind == "note":
			UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 14.0), str(item["label"]), 11,
				UiChrome.C_SOFT, med)
		elif kind == "market_row":
			var news: Dictionary = item["row"]
			UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 6)
			UiChrome.text(c, Vector2(rect.position.x + 12.0, rect.position.y + rect.size.y * 0.5
				+ UiChrome.RISE), str(news.get("headline", "")), 11, UiChrome.C_TEXT, bold)
			UiChrome.text_r(c, rect.end.x - 12.0, rect.position.y + rect.size.y * 0.5
				+ UiChrome.RISE, str(news.get("kind", "")).to_upper(), 9, UiChrome.C_GOLD, bold)

# gd-tools: no cover end
