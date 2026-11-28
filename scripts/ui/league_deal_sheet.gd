class_name LeagueDealSheet
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
	if bool(view.get("empty", true)):
		items.append({"id": "", "kind": "note", "label": "That deal is no longer in the book.",
			"rect": Rect2(24.0, y, vp.x - 48.0, 22.0)})
		return items
	var deal: Dictionary = view.get("deal", {})
	items.append({"id": "", "kind": "title", "label": str(ViewCopy.player(view)),
		"rect": Rect2(24.0, y, vp.x - 48.0, 24.0)})
	y += 30.0
	items.append({"id": "", "kind": "note", "label": "%s · %s · %s" % [
		MarketDealCopy.state(str(view.get("state", ""))),
		MarketDealCopy.reason(str(view.get("reason", ""))) if str(view.get("reason", "")) != "" else "NO REFUSAL",
		str(view.get("date", ""))], "rect": Rect2(24.0, y, vp.x - 48.0, 20.0)})
	y += 26.0
	items.append({"id": "", "kind": "caption", "label": "TERMS",
		"rect": Rect2(24.0, y, vp.x - 48.0, 20.0)})
	y += 24.0
	for pair in view.get("terms", []):
		var row: Array = pair
		items.append({"id": "", "kind": "term", "label": str(row[0]), "value": str(row[1]),
			"rect": Rect2(24.0, y, vp.x - 48.0, row_h)})
		y += row_h + 2.0
	y += 8.0
	items.append({"id": "", "kind": "caption", "label": "VALIDATION",
		"rect": Rect2(24.0, y, vp.x - 48.0, 20.0)})
	y += 24.0
	for check in view.get("checks", []):
		var row: Dictionary = check
		items.append({"id": "", "kind": "check", "row": row,
			"rect": Rect2(24.0, y, vp.x - 48.0, row_h)})
		y += row_h + 2.0
	y += 8.0
	items.append({"id": "", "kind": "caption", "label": "TIMELINE",
		"rect": Rect2(24.0, y, vp.x - 48.0, 20.0)})
	y += 24.0
	for step in view.get("timeline", []):
		var row: Dictionary = step
		items.append({"id": "", "kind": "step", "row": row,
			"rect": Rect2(24.0, y, vp.x - 48.0, row_h)})
		y += row_h + 2.0
	y += 10.0
	var can_act := bool(view.get("can_act", false))
	if not can_act and str(view.get("state", "")) != MarketDealRecords.SIGNED:
		var window: Dictionary = view.get("window", {})
		var line := "THE WINDOW IS CLOSED · OPENS %s" % str(window.get("opens_on", ""))
		if bool(view.get("free_agent", false)):
			line = "A FREE AGENT MAY STILL SIGN"
		items.append({"id": "", "kind": "note", "label": line,
			"rect": Rect2(24.0, y, vp.x - 48.0, 22.0)})
		y += 28.0
	var doors := [
		{"id": "god:force:" + str(view.get("deal_id", "")), "label": "FORCE", "primary": true},
		{"id": "god:block:" + str(view.get("deal_id", "")), "label": "BLOCK", "primary": false},
		{"id": "god:rewrite:" + str(view.get("deal_id", "")), "label": "REWRITE", "primary": false},
	]
	var door_h: float = UiChrome.tap_h(40.0, touch)
	var door_w: float = minf(140.0, (vp.x - 48.0 - 16.0) / 3.0)
	for i in range(doors.size()):
		var door: Dictionary = doors[i]
		door["kind"] = "button"
		door["disabled"] = not can_act
		door["rect"] = Rect2(24.0 + float(i) * (door_w + 8.0), y, door_w, door_h)
		items.append(door)
	return items

# gd-tools: no cover start

func draw_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		_hints: DateHints) -> void:
	LeagueExtra.header(c, vp, fonts, "DEAL", str(view.get("date", "")), 0.0, true,
		bool(view.get("touch", false)))

func draw_body(c: CanvasItem, _vp: Vector2, fonts: Dictionary, items: Array,
		_view: Dictionary) -> void:
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	for item in items:
		var rect: Rect2 = item["rect"]
		var kind := str(item["kind"])
		if kind == "title":
			UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 16.0), str(item["label"]),
				16, UiChrome.C_GOLD, bold)
		elif kind == "caption":
			UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 14.0), str(item["label"]), 10,
				UiChrome.C_DIM, bold)
		elif kind == "note":
			UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 14.0), str(item["label"]), 10,
				UiChrome.C_SOFT, med)
		elif kind == "button":
			var disabled := bool(item.get("disabled", false))
			UiChrome.button(c, cache, rect, str(item["label"]), bold,
				bool(item.get("primary", false)) and not disabled)
		elif kind == "term":
			UiChrome.text(c, Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5
				+ UiChrome.RISE), str(item["label"]), 10, UiChrome.C_DIM, med)
			UiChrome.text_r(c, rect.end.x, rect.position.y + rect.size.y * 0.5 + UiChrome.RISE,
				str(item["value"]), 11, UiChrome.C_TEXT, bold)
		elif kind == "check":
			var row: Dictionary = item["row"]
			var ink: Color = UiChrome.C_GOLD if bool(row.get("ok", false)) else UiChrome.C_DANGER
			UiChrome.text(c, Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5
				+ UiChrome.RISE), str(row.get("name", "")).to_upper(), 10, ink, bold)
			UiChrome.text_r(c, rect.end.x, rect.position.y + rect.size.y * 0.5 + UiChrome.RISE,
				str(row.get("code", "")) if not bool(row.get("ok", false)) else "OK", 10, ink, med)
		elif kind == "step":
			var row: Dictionary = item["row"]
			UiChrome.text(c, Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5
				+ UiChrome.RISE), "%s  %s" % [str(row.get("date", "")),
					MarketDealCopy.state(str(row.get("state", "")))], 10, UiChrome.C_SOFT, med)
			if str(row.get("reason", "")) != "":
				UiChrome.text_r(c, rect.end.x, rect.position.y + rect.size.y * 0.5 + UiChrome.RISE,
					MarketDealCopy.reason(str(row.get("reason", ""))), 9, UiChrome.C_DIM, med)

# gd-tools: no cover end


class ViewCopy:
	static func player(view: Dictionary) -> String:
		var deal: Dictionary = view.get("deal", {})
		return LeagueMarketView.player_name(str(deal.get("player_id", "")))
