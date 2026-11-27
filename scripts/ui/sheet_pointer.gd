class_name SheetPointer
extends RefCounted


const DRAG_SLOP := 8.0


const PAN_STEP := 60.0
const WHEEL_STEP := 110.0

var sheet = null


var hold = null
var pressing := false
var dragged := false
var press_at := Vector2.ZERO
var last_at := Vector2.ZERO

func _init(target) -> void:
	sheet = target


func reset() -> void:
	pressing = false
	dragged = false
	if hold != null:
		hold.clear()
	if sheet != null:
		sheet.holding = false


func handle(event: InputEvent, point: Vector2) -> bool:
	if sheet == null:
		return false
	if event is InputEventMouseMotion:
		_motion(point)
	elif event is InputEventPanGesture:


		sheet.scroll_by(event.delta.y * PAN_STEP, event.delta.x * PAN_STEP)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		sheet.scroll_by(-WHEEL_STEP)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		sheet.scroll_by(WHEEL_STEP)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_down(point)
		else:
			_up()
	elif event is InputEventKey and event.pressed and not event.echo:


		if not (sheet.has_method("text_key") and sheet.text_key(event.keycode, event.unicode)):
			sheet.key(event.keycode)
	else:
		return false
	return true

func _down(p: Vector2) -> void:
	pressing = true
	dragged = false
	press_at = p
	last_at = p
	sheet.mouse = p
	sheet.holding = true
	if hold != null:
		hold.press_at(p)


func _motion(p: Vector2) -> void:
	sheet.mouse = p

	if hold != null and hold.is_open():
		return
	if not pressing:
		if not sheet.touch:
			Input.set_default_cursor_shape(
				Input.CURSOR_POINTING_HAND if sheet.button_at(p) != "" else Input.CURSOR_ARROW)
		return
	if not dragged:
		if p.distance_to(press_at) < DRAG_SLOP:
			return
		dragged = true
		sheet.holding = false
	if hold != null:
		hold.move(p)
	sheet.scroll_by(last_at.y - p.y, last_at.x - p.x)
	last_at = p

func _up() -> void:
	if not pressing:
		return
	pressing = false
	sheet.holding = false

	if hold != null and hold.release_at(press_at):
		return
	if dragged:
		return
	var id: String = sheet.button_at(press_at)
	if id != "":
		sheet.click(id)
	elif sheet.has_method("tap"):
		sheet.tap(press_at)
