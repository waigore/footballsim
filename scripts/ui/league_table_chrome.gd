class_name LeagueTableChrome
extends RefCounted

## The league table's own band: its title line, the weekday hint on the date,
## and the zone legend that names the coloured bands every row carries.
##
## It sits beside `LeagueTableView` and owns the half of it that is the sheet's
## chrome rather than its rows and columns: the table still owns the reading,
## the sort, the press and the row paint; this module only says what rides
## above the band and how it is painted, and it answers to the same two poses
## the rest of the table does — a wide sheet and a phone sheet.
##
## The legend is the reason the split exists: on a wide sheet it shares the
## bottom bar with the reading doors and prints the sort sentence beside it; a
## phone sheet has no room there, so the legend moves up beside the title and
## drops the sentence altogether.

## The legend's bands, in paint order: the three European places and the drop.
## A tier below the top flight paints its own promotion picture instead and
## reads it from `bands_for()`.
const BANDS := ["ucl", "uel", "uecl", "relegation"]
const SHORT_LABELS := ["UCL", "UEL", "UECL", "REL"]
const WIDE_LABELS := ["UCL", "UEL", "UECL", "RELEGATION"]

## The bands one competition's table paints, from its own regulations: a
## promoting tier shows promotion and its play-off band, a top flight the
## European places. The drop is always the last mark (#258).
static func bands_for(rules: Dictionary) -> Array:
	if int(rules.get("promotion_places", 0)) <= 0:
		return BANDS.duplicate()
	if int(rules.get("promotion_playoff_places", 0)) > 0:
		return ["promotion", "playoff", "relegation"]
	return ["promotion", "relegation"]

## The legend captions for those bands, in the short reading a phone uses and
## the wide one a desktop prints.
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
## Below this the reading doors and the legend cannot share the bottom bar.
const NARROW_VP := 620.0
## The sort sentence only rides the legend when the sheet is wide enough for both.
const SENTENCE_VP := 760.0
const GAP := 8.0

## The sort sentence under the legend: the pointer's verb on a desktop sheet and
## the finger's on a touch one (#278), the same split the fixture picker's footer
## already makes.
static func sentence(touch: bool) -> String:
	return "TAP A COLUMN TO SORT · COLOURED BAND = PLACE" if touch \
		else "CLICK A COLUMN TO SORT · COLOURED BAND = PLACE"

## A phone sheet: the legend moves up beside the title, the doors keep the bar.
static func narrow(vp: Vector2) -> bool:
	return vp.x < NARROW_VP

## The strip the legend runs in: right up against the sheet's edge above the
## band on a phone sheet, left of the sort sentence on the bottom bar wide.
## A strip's height tells which of the two it is.
static func legend_rect(vp: Vector2) -> Rect2:
	if narrow(vp):
		return Rect2(24.0, 48.0, vp.x - 48.0, 1.0)
	return Rect2(350.0, vp.y - LeagueChrome.BAR_H + 24.0, vp.x - 24.0 - 350.0, 0.0)

## Where the sort sentence runs: the bottom bar on a wide sheet, nothing on a
## phone, so a press there is never promised a column it cannot see.
static func sentence_rect(vp: Vector2) -> Rect2:
	if narrow(vp):
		return Rect2()
	return Rect2(24.0, vp.y - LeagueChrome.BAR_H + 12.0, vp.x - 48.0, 16.0)

## The caption under the title: the season's name and the day, when there is one.
static func caption(view: Dictionary, label: String) -> String:
	var parts: Array = []
	if str(view.get("name", "")) != "":
		parts.append(str(view.get("name", "")))
	if label != "":
		parts.append(label)
	return " · ".join(PackedStringArray(parts))

# gd-tools: no cover start

## Title and caption, the date hint, then the legend and its sentence.
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

## The band legend: one coloured glyph per place rule, right-aligned against the
## strip's end on a phone sheet and left-aligned at its start on a wide one. The
## bands are the league's own, so a promoting tier's legend names its promotion
## and play-off places rather than European ones it does not have.
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

# gd-tools: no cover end

## The legend's total width at one type size, gaps included between its glyphs
## but not after the last.
static func legend_width(bold: Font, labels: Array, size: int) -> float:
	var total := -GAP
	for label in labels:
		total += bold.get_string_size(str(label), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + GAP
	return total
