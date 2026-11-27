class_name LeagueBook
extends RefCounted

## The reading surfaces of a season: the full table, the month calendar, match
## reports and roundups, and the final podium. The book keeps the pose names the
## screen already calls; each reading owns its own geometry and paint.
##
## Rows keep a readable height and are allowed to run past the bottom of the
## viewport: LeagueBody clips them and scrolls. Only the bottom doors and the
## month chips are pinned in place.
##
## The month arithmetic (keys, stepping, labels, day counts) lives in
## `LeagueMonth`; this book only hands the calendar view its cells and chips.

var cache := {}
## Dates this book painted, with the strip each one occupies (#99): the screen's
## overlay paints the weekday for the one under the pointer.
var hints := DateHints.new()
## Club names this book painted, with the strip each one occupies (#107): the
## long press reads it, in the same design space the rows are laid out in.
var names := InterestNames.new()
## The table pose's geometry, sorting and paint (compact/full, header sort), in
## its own module because a table is a reading of its own.
var table := LeagueTableView.new()
## The match report pose, with its own two event columns (#168).
var report_sheet := LeagueReportSheet.new()
## The month grid and day fixture list (#99/#126/#168).
var calendar := LeagueCalendarView.new()
## The season-complete podium: champions, Europe / promotion, relegated (#240/#260).
var podium := LeaguePodiumSheet.new()

func _init() -> void:
	# One registry each, so a long press or a weekday bubble on any reading
	# reads the strips that reading really painted.
	report_sheet.hints = hints
	report_sheet.names = names
	calendar.hints = hints
	calendar.names = names
	calendar.cache = cache
	podium.hints = hints

# ----------------------------------------------------------------- table ---

func table_layout(vp: Vector2, view: Dictionary) -> Array:
	return table.layout(vp, view)

## Column geometry for one table row lives in `LeagueTableView`: compact keeps
## `LeagueColumns` (the measured layout #71 settled), the full sheet walks the
## overall, home and away columns from the club's right edge.

func calendar_layout(vp: Vector2, view: Dictionary) -> Array:
	return calendar.layout(vp, view)

## The report pose lives in `LeagueReportSheet`: two columns of events under the
## clubs their score line names (#168). Kept behind the same names the screen
## already calls, so the pose table did not change.
func report_layout(vp: Vector2, view: Dictionary) -> Array:
	return report_sheet.layout(vp, view)

func podium_layout(vp: Vector2, view: Dictionary) -> Array:
	return podium.layout(vp, view)

## How tall the podium summary paints below the header.
func frame_height(view: Dictionary) -> float:
	return podium.frame_height(view)

## The podium's blocks: every active league, or the one league a single-league
## save mirrors at the top. Kept on the book so older tests keep their call site.
static func _podium_sections(summary: Dictionary) -> Array:
	return LeaguePodiumSheet.sections(summary)

# gd-tools: no cover start

func draw_table_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		hints: DateHints) -> void:
	table.draw_chrome(c, vp, fonts, view, hints)

func draw_table_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, items: Array, view: Dictionary) -> void:
	table.draw_body(c, vp, fonts, items, view, names)

# -------------------------------------------------------------- calendar ---

func draw_calendar_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		hints: DateHints) -> void:
	calendar.draw_chrome(c, vp, fonts, view, hints)

func draw_calendar_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, items: Array, view: Dictionary) -> void:
	calendar.draw_body(c, vp, fonts, items, view)

# ---------------------------------------------------------------- report ---

func draw_report_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		hints: DateHints) -> void:
	report_sheet.draw_chrome(c, vp, fonts, view, hints)

func draw_report_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, items: Array, view: Dictionary) -> void:
	report_sheet.draw_body(c, vp, fonts, items, view)

# ---------------------------------------------------------------- podium ---

func draw_podium_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		hints: DateHints) -> void:
	podium.draw_chrome(c, vp, fonts, view, hints)

func draw_podium_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, items: Array, view: Dictionary) -> void:
	podium.draw_body(c, vp, fonts, items, view)

# gd-tools: no cover end
