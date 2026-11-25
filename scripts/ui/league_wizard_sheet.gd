class_name LeagueWizardSheet
extends RefCounted

## The new-season wizard: the save-name field, the fixture and advance choices,
## and the CREATE SEASON door. Geometry and paint only; the screen owns the
## wizard state and `LeagueDoors` edits it.

const HEADER := LeagueSheet.HEADER

var cache := {}
## Dates this sheet painted, read by the screen's weekday overlay (#99).
var hints := DateHints.new()

func wizard_layout(vp: Vector2, view: Dictionary) -> Array:
	var items: Array = []
	var w := minf(520.0, vp.x - 48.0)
	var y := HEADER + 30.0
	items.append({"id": "name", "kind": "field", "label": "NAME",
		"rect": Rect2(24.0, y, w, 38.0), "value": str(view.get("name", ""))})
	y += 66.0
	items.append({"id": "mode:real", "kind": "choice", "label": "REAL FIXTURES",
		"rect": Rect2(24.0, y, w * 0.48, 40.0), "selected": str(view.get("calendar_mode", "")) == "real"})
	items.append({"id": "mode:generated", "kind": "choice", "label": "GENERATED",
		"rect": Rect2(24.0 + w * 0.52, y, w * 0.48, 40.0), "selected": str(view.get("calendar_mode", "")) == "generated"})
	y += 52.0
	items.append({"id": "adv:fixture_days", "kind": "choice", "label": "FIXTURE DAYS",
		"rect": Rect2(24.0, y, w * 0.48, 40.0), "selected": str(view.get("advance_mode", "")) == "fixture_days"})
	items.append({"id": "adv:every_day", "kind": "choice", "label": "EVERY DAY",
		"rect": Rect2(24.0 + w * 0.52, y, w * 0.48, 40.0), "selected": str(view.get("advance_mode", "")) == "every_day"})
	y += 54.0
	items.append({"id": "create", "kind": "button", "label": "CREATE SEASON",
		"rect": Rect2(24.0, y, minf(240.0, w), 46.0), "primary": true})
	items.append(LeagueExtra.back_item())
	return items

# gd-tools: no cover start

func draw_wizard_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		_hints: DateHints) -> void:
	LeagueSheet.heading(c, vp, fonts, "NEW LEAGUE", "GOD-MODE SEASON SETUP")
	if str(view.get("error", "")) != "":
		UiChrome.text(c, Vector2(24.0, vp.y - LeagueSheet.BAR_H - 10.0), str(view["error"]), 12,
			UiChrome.C_DANGER, fonts["med"])

func draw_wizard_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, items: Array, _view: Dictionary) -> void:
	hints.clear()
	var bold: Font = fonts["bold"]
	for item in items:
		var rect: Rect2 = item["rect"]
		var kind := str(item["kind"])
		var id := str(item["id"])
		if id == "mode:real":
			UiChrome.text(c, Vector2(rect.position.x, rect.position.y - 8.0), "FIXTURES", 10, UiChrome.C_DIM, bold)
		elif id == "adv:fixture_days":
			UiChrome.text(c, Vector2(rect.position.x, rect.position.y - 8.0), "ADVANCE", 10, UiChrome.C_DIM, bold)
		if kind == "field":
			UiChrome.text(c, Vector2(rect.position.x, rect.position.y - 8.0), "SAVE NAME", 10, UiChrome.C_DIM, bold)
			UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 6, UiChrome.C_GOLD, 1)
			UiChrome.text(c, Vector2(rect.position.x + 10.0, rect.position.y + 25.0),
				str(item["value"]) if str(item["value"]) != "" else "League 1", 15, UiChrome.C_TEXT, bold)
		elif kind == "choice":
			var chosen := bool(item["selected"])
			UiChrome.panel(c, cache, rect,
				UiChrome.C_GOLD.darkened(0.1) if chosen else UiChrome.C_PANEL, 6,
				UiChrome.C_GOLD if chosen else UiChrome.C_BORDER, 1)
			UiChrome.text_c(c, rect.get_center().x, rect.position.y + 25.0, str(item["label"]), 12,
				Color(0.06, 0.06, 0.05) if chosen else UiChrome.C_TEXT, bold)
		elif kind == "button":
			LeagueSheet.draw_button(c, cache, rect, str(item["label"]), bold,
				bool(item.get("primary", false)))

# gd-tools: no cover end
