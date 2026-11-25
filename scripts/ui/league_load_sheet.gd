class_name LeagueLoadSheet
extends RefCounted

## The load-league list: one row per recent save with its date and status, an
## X door to delete it, and BACK. Geometry and paint only; the screen owns the
## save list and `LeagueSave` does the file work.

const HEADER := LeagueSheet.HEADER

var cache := {}
## Dates this sheet painted, read by the screen's weekday overlay (#99).
var hints := DateHints.new()

func load_layout(vp: Vector2, view: Dictionary) -> Array:
	var items: Array = []
	var saves: Array = view.get("saves", [])
	var w := minf(620.0, vp.x - 48.0)
	var y := HEADER + 26.0
	for i in range(mini(saves.size(), 7)):
		var save: Dictionary = saves[i]
		var row := Rect2(24.0, y, w, 40.0)
		items.append({"id": "open:" + str(save["slug"]), "kind": "save_row",
			"rect": row, "save": save})
		items.append({"id": "delete:" + str(save["slug"]), "kind": "delete",
			"rect": Rect2(row.end.x - 96.0, row.position.y + 5.0, 34.0, 30.0), "slug": str(save["slug"])})
		y += 46.0
	items.append(LeagueExtra.back_item())
	return items

# gd-tools: no cover start

func draw_load_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, _view: Dictionary,
		_hints: DateHints) -> void:
	LeagueSheet.heading(c, vp, fonts, "LOAD LEAGUE", "NAMED SEASONS")

func draw_load_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, items: Array, view: Dictionary) -> void:
	hints.clear()
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	if (view.get("saves", []) as Array).is_empty():
		UiChrome.text(c, Vector2(24.0, HEADER + 34.0),
			"No saves yet — start a New League from the menu.", 13, UiChrome.C_SOFT, med)
	for item in items:
		var rect: Rect2 = item["rect"]
		if str(item["kind"]) == "save_row":
			var save: Dictionary = item["save"]
			UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 6)
			UiChrome.text(c, Vector2(rect.position.x + 12.0, rect.position.y + 17.0),
				str(save["name"]), 14, UiChrome.C_TEXT, bold)
			var current := str(save.get("current_date", ""))
			var dated: String = FixtureCalendar.day_label(current)
			var line: String = "%s · %s" % [dated, str(save.get("status", ""))] if dated != "" else str(save.get("status", ""))
			UiChrome.text(c, Vector2(rect.position.x + 12.0, rect.position.y + 32.0), line, 10,
				UiChrome.C_DIM, med)
			if current != "":
				hints.add(DateHints.strip(med, dated,
					Vector2(rect.position.x + 12.0, rect.position.y + 32.0), 10), current)
		elif str(item["kind"]) == "delete":
			UiChrome.panel(c, cache, rect, UiChrome.C_DANGER.darkened(0.35), 5, UiChrome.C_DANGER, 1)
			UiChrome.text_c(c, rect.get_center().x, rect.position.y + 21.0, "X", 13, UiChrome.C_TEXT, bold)
		elif str(item["kind"]) == "button":
			LeagueSheet.draw_button(c, cache, rect, str(item["label"]), bold,
				bool(item.get("primary", false)))

# gd-tools: no cover end
