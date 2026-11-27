class_name LeagueBook
extends RefCounted


var cache := {}


var hints := DateHints.new()


var names := InterestNames.new()


var table := LeagueTableView.new()

var report_sheet := LeagueReportSheet.new()

var calendar := LeagueCalendarView.new()

var podium := LeaguePodiumSheet.new()

func _init() -> void:


	report_sheet.hints = hints
	report_sheet.names = names
	calendar.hints = hints
	calendar.names = names
	calendar.cache = cache
	podium.hints = hints


func table_layout(vp: Vector2, view: Dictionary) -> Array:
	return table.layout(vp, view)


func calendar_layout(vp: Vector2, view: Dictionary) -> Array:
	return calendar.layout(vp, view)


func report_layout(vp: Vector2, view: Dictionary) -> Array:
	return report_sheet.layout(vp, view)

func podium_layout(vp: Vector2, view: Dictionary) -> Array:
	return podium.layout(vp, view)


func frame_height(view: Dictionary) -> float:
	return podium.frame_height(view)


static func _podium_sections(summary: Dictionary) -> Array:
	return LeaguePodiumSheet.sections(summary)

# gd-tools: no cover start

func draw_table_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		hints: DateHints) -> void:
	table.draw_chrome(c, vp, fonts, view, hints)

func draw_table_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, items: Array, view: Dictionary) -> void:
	table.draw_body(c, vp, fonts, items, view, names)


func draw_calendar_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		hints: DateHints) -> void:
	calendar.draw_chrome(c, vp, fonts, view, hints)

func draw_calendar_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, items: Array, view: Dictionary) -> void:
	calendar.draw_body(c, vp, fonts, items, view)


func draw_report_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		hints: DateHints) -> void:
	report_sheet.draw_chrome(c, vp, fonts, view, hints)

func draw_report_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, items: Array, view: Dictionary) -> void:
	report_sheet.draw_body(c, vp, fonts, items, view)


func draw_podium_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		hints: DateHints) -> void:
	podium.draw_chrome(c, vp, fonts, view, hints)

func draw_podium_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, items: Array, view: Dictionary) -> void:
	podium.draw_body(c, vp, fonts, items, view)

# gd-tools: no cover end
