class_name DateOverlay
extends Control


var screen = null

var body = null


var rows_local := false
var cache := {}


static func attach(sheet, window, local_rows: bool) -> DateOverlay:
	var out := DateOverlay.new()
	out.screen = sheet
	out.body = window
	out.rows_local = local_rows
	sheet.add_child(out)
	return out

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func showing() -> bool:
	return screen != null and (not bool(screen.touch) or bool(screen.holding))


func zone_at() -> Dictionary:
	if screen == null:
		return {}
	var p: Vector2 = screen.mouse
	var zone: Dictionary = screen.hints.at(p)
	if not zone.is_empty() or body == null or screen.rows_hints == null:
		return zone
	if not Rect2(body.position, body.size).has_point(p):
		return zone
	var origin: Vector2 = body.position if rows_local else Vector2.ZERO
	var offset := Vector2(0.0, body.scroll)
	if not rows_local:
		offset = Vector2(body.hscroll, body.scroll)
	return screen.rows_hints.at(p - origin + offset)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not showing():
		return
	var zone := zone_at()
	if zone.is_empty():
		return
	DateHints.paint(self, cache, zone, screen.design_vp(), UiChrome.fonts())


