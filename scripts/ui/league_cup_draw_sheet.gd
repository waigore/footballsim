class_name LeagueCupDrawSheet
extends RefCounted


const HEADER := LeagueChrome.HEADER

const REVEAL := 0.28
const ROW_H := 34.0
const ROW_GAP := 4.0
const POT_H := 20.0
const POT_GAP := 6.0
const SKIP_W := 120.0

var cache := {}

var hints := DateHints.new()

var names := InterestNames.new()


static func reveals(screen) -> int:
	return int((screen.draw_state as Dictionary).get("shown", 0))


static func settled(screen, view: Dictionary) -> bool:
	return reveals(screen) >= (view.get("pairs", []) as Array).size()


static func tick(screen, delta: float) -> bool:
	var state: Dictionary = screen.draw_state
	var pairs := (screen.current_view().get("pairs", []) as Array).size()
	if int(state.get("shown", 0)) >= pairs:
		return false
	state["clock"] = float(state.get("clock", 0.0)) + delta
	if float(state["clock"]) < REVEAL:
		return false
	state["clock"] = 0.0
	state["shown"] = int(state.get("shown", 0)) + 1
	return true


static func settle_all(screen) -> void:
	var pairs := (screen.current_view().get("pairs", []) as Array).size()
	screen.draw_state["shown"] = pairs
	screen.draw_state["clock"] = 0.0


static func pots(view: Dictionary, shown: int) -> Array:
	var out: Array = []
	for i in range(mini(shown, (view.get("pairs", []) as Array).size())):
		var pot := str(((view["pairs"] as Array)[i] as Dictionary).get("pot", ""))
		if not out.has(pot):
			out.append(pot)
	return out


static func caption(view: Dictionary) -> String:
	if (view.get("pairs", []) as Array).is_empty():
		return "NOTHING TO DRAW"
	return "%s  ·  %s" % [str(view.get("round_name", "")),
		FixtureCalendar.day_label(str(view.get("date", "")))]


static func regional_note(view: Dictionary) -> String:
	if not bool(view.get("regional", false)):
		return "ONE OPEN POT"
	return "TWO POTS  ·  NORTH AND SOUTH BY THE CLUB'S OWN BAND"


func draw_layout(vp: Vector2, view: Dictionary) -> Array:
	var touch := bool(view.get("touch", false))
	var shown := int(view.get("shown", 0))
	var items: Array = []
	var w := vp.x - 48.0
	var row_h: float = UiChrome.tap_h(ROW_H, touch)
	var pairs: Array = view.get("pairs", [])
	var pot_row: Array = pots(view, shown)
	var y := HEADER + 44.0
	var pot_rect := Rect2(24.0, HEADER + 12.0, w, POT_H)
	items.append({"id": "", "kind": "pots", "pots": pot_row, "rect": pot_rect})
	if pairs.is_empty():
		items.append({"id": "", "kind": "note", "label": "This round has no draw.",
			"rect": Rect2(24.0, y, w, 24.0)})
	for i in range(pairs.size()):
		var pair: Dictionary = pairs[i]
		if i >= shown:
			continue
		items.append({"id": "cupdraw:row:%d" % i, "kind": "pair", "pair": pair, "revealed": i,
			"rect": Rect2(24.0, y + float(i) * (row_h + ROW_GAP), w, row_h)})
	var bottom: float = y + float(mini(shown, pairs.size())) * (row_h + ROW_GAP) + 10.0
	items.append({"id": "", "kind": "extent", "rect": Rect2(24.0, bottom, w, 1.0)})
	items.append(LeagueExtra.back_item(touch))
	items.append({"id": "skiptodraw", "kind": "button", "label": "SKIP", "primary": false,
		"pinned": true, "rect": Rect2(vp.x - 24.0 - SKIP_W, 12.0, SKIP_W, 32.0)})
	return items

# gd-tools: no cover start

func draw_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		hints_out: DateHints) -> void:
	var bold: Font = fonts["bold"]
	var right: float = SKIP_W + 12.0
	var band := LeagueExtra.header(c, vp, fonts, "%s DRAW" % str(view.get("name", "CUP")),
		caption(view), right, true, bool(view.get("touch", false)))
	UiChrome.panel(c, cache, Rect2(vp.x - 24.0 - SKIP_W, 12.0, SKIP_W, 32.0),
		UiChrome.C_PANEL_LIGHT, 7, UiChrome.C_GOLD, 1)
	UiChrome.text_c(c, vp.x - 24.0 - SKIP_W * 0.5, 32.0, "SKIP", 12, UiChrome.C_GOLD, bold)
	UiChrome.text(c, Vector2(24.0, HEADER - 24.0), regional_note(view), 9, UiChrome.C_DIM, bold)
	if str(view.get("date", "")) != "" and str(band.get("caption", "")) != "":
		var rect: Rect2 = band["caption_rect"]
		hints_out.add(Rect2(rect.position.x, 24.0, 110.0, 14.0), str(view["date"]))


func draw_body(c: CanvasItem, _vp: Vector2, fonts: Dictionary, items: Array,
		view: Dictionary) -> void:
	hints.clear()
	names.clear()
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	var shown := int(view.get("shown", 0))
	for item in items:
		var rect: Rect2 = item["rect"]
		match str(item["kind"]):
			"pots":
				_paint_pots(c, rect, item["pots"], bold)
			"note":
				UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 14.0), str(item["label"]),
					11, UiChrome.C_SOFT, med)
			"pair":
				_paint_pair(c, rect, item["pair"], bold, med)
			"extent":
				pass
	if (view.get("pairs", []) as Array).size() > 0 and shown >= (view["pairs"] as Array).size():
		UiChrome.text(c, Vector2(24.0, _vp.y - 22.0),
			"THE DRAW IS SETTLED  ·  BACK RETURNS TO THE CUP", 10, UiChrome.C_GOLD, bold)


func _paint_pots(c: CanvasItem, rect: Rect2, pots: Array, bold: Font) -> void:
	if pots.is_empty():
		UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 13.0), "POTS",
			9, UiChrome.C_DIM, bold)
		return
	var x := rect.position.x
	for pot in pots:
		var label := str(pot)
		var w: float = UiChrome.text_width(bold, label, 9) + 20.0
		UiChrome.panel(c, cache, Rect2(x, rect.position.y, w, rect.size.y),
			UiChrome.C_PANEL_LIGHT, 4, UiChrome.C_BORDER, 1)
		UiChrome.text_c(c, x + w * 0.5, rect.position.y + 13.0, label, 9, UiChrome.C_GOLD, bold)
		x += w + 8.0


func _paint_pair(c: CanvasItem, rect: Rect2, pair: Dictionary, bold: Font, med: Font) -> void:
	UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 5, UiChrome.C_BORDER, 1)
	var pot := str(pair.get("pot", ""))
	var pot_w: float = UiChrome.text_width(med, pot, 8) + 16.0
	UiChrome.text(c, Vector2(rect.position.x + 10.0, rect.position.y + rect.size.y * 0.5 + 4.0),
		pot, 8, UiChrome.C_DIM, med)
	var home_x := rect.position.x + 10.0 + pot_w
	var room := maxf((rect.size.x - pot_w - 60.0) * 0.46, 60.0)
	UiChrome.text(c, Vector2(home_x, rect.position.y + rect.size.y * 0.5 + 5.0),
		LeagueColumns.fit_name(str(pair.get("home_name", "")), bold, 12, room), 12,
		UiChrome.C_TEXT, bold)
	var vs_x := home_x + room + 6.0
	UiChrome.text(c, Vector2(vs_x, rect.position.y + rect.size.y * 0.5 + 4.0), "v", 10,
		UiChrome.C_DIM, med)
	UiChrome.text(c, Vector2(vs_x + 16.0, rect.position.y + rect.size.y * 0.5 + 5.0),
		LeagueColumns.fit_name(str(pair.get("away_name", "")), bold, 12,
			maxf(rect.end.x - 12.0 - (vs_x + 16.0), 60.0)), 12, UiChrome.C_TEXT, bold)

# gd-tools: no cover end
