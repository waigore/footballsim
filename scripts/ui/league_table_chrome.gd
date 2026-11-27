class_name LeagueTableChrome
extends RefCounted


const BANDS := ["ucl", "uel", "uecl", "relegation"]
const SHORT_LABELS := ["UCL", "UEL", "UECL", "REL"]
const WIDE_LABELS := ["UCL", "UEL", "UECL", "RELEGATION"]


static func bands_for(rules: Dictionary) -> Array:
	if int(rules.get("promotion_places", 0)) <= 0:
		return BANDS.duplicate()
	if int(rules.get("promotion_playoff_places", 0)) > 0:
		return ["promotion", "playoff", "relegation"]
	return ["promotion", "relegation"]


static func labels_for(bands: Array, short: bool) -> Array:
	var out: Array = []
	for band in bands:
		var label := LeagueRules.zone_label(str(band))
		if str(band) == "promotion":
			label = "UP"
		elif str(band) == "playoff":
			label = "PLO"
		elif str(band) == "relegation":
			label = "REL" if short else "RELEGATION"
		out.append(label)
	return out

const NARROW_VP := 620.0

const SENTENCE_VP := 760.0
const GAP := 8.0


static func sentence(touch: bool) -> String:
	return "TAP A COLUMN TO SORT · COLOURED BAND = PLACE" if touch \
		else "CLICK A COLUMN TO SORT · COLOURED BAND = PLACE"


static func narrow(vp: Vector2) -> bool:
	return vp.x < NARROW_VP


static func legend_rect(vp: Vector2) -> Rect2:
	if narrow(vp):
		return Rect2(24.0, 48.0, vp.x - 48.0, 1.0)
	return Rect2(350.0, vp.y - LeagueChrome.BAR_H + 24.0, vp.x - 24.0 - 350.0, 0.0)


static func sentence_rect(vp: Vector2) -> Rect2:
	if narrow(vp):
		return Rect2()
	return Rect2(24.0, vp.y - LeagueChrome.BAR_H + 12.0, vp.x - 48.0, 16.0)


static func caption(view: Dictionary, label: String) -> String:
	var parts: Array = []
	if str(view.get("name", "")) != "":
		parts.append(str(view.get("name", "")))
	if label != "":
		parts.append(label)
	return " · ".join(PackedStringArray(parts))


static func draw(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		hints: DateHints) -> void:
	var date := str(view.get("date", ""))
	var label := FixtureCalendar.day_label(date)
	LeagueExtra.header(c, vp, fonts, "LEAGUE TABLE", caption(view, label))
	if date != "":
		hints.add(DateHints.strip_right(fonts["bold"], label, vp.x - 24.0, 34.0, 10), date)
	var spot := legend_rect(vp)
	var strip := sentence_rect(vp)
	if strip != Rect2():
		UiChrome.text_r(c, vp.x - 24.0, strip.end.y - 4.0, sentence(bool(view.get("touch", false))),
			8, UiChrome.C_DIM, fonts["med"])
	var rules: Dictionary = view.get("rules", {})
	_legend(c, spot, fonts, bands_for(rules))


static func _legend(c: CanvasItem, strip: Rect2, fonts: Dictionary, bands: Array) -> void:
	var phone := strip.size.y > 0.0
	var labels: Array = labels_for(bands, phone)
	var size: int = 8 if phone else 9
	var bold: Font = fonts["bold"]
	var x: float = strip.end.x - legend_width(bold, labels, size) if phone else strip.position.x
	for i in range(labels.size()):
		var label := str(labels[i])
		UiChrome.text(c, Vector2(x, strip.position.y), label, size,
			LeagueChrome.zone_color(str(bands[i])), bold)
		x += bold.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + GAP


static func legend_width(bold: Font, labels: Array, size: int) -> float:
	var total := -GAP
	for label in labels:
		total += bold.get_string_size(str(label), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + GAP
	return total
