class_name SheetPointer
extends RefCounted

## The pointer grammar every modal sheet shares: hover is free, a press that
## travels past `DRAG_SLOP` turns into a scroll drag, and a press that lifts in
## place is a click (or a tap when the sheet hit-tests its own rows). Trackpad
## pans and wheel notches move the body too.
##
## The sheet keeps its own state and paint and exposes `button_at`, `click`,
## `scroll_by`, `key`, `mouse`, `holding` and `touch`; `tap` is optional. Hosts
## only convert the event into the sheet's design space and hand it here, so the
## league and the encyclopedia cannot drift apart on drag behaviour.

## Pointer travel that separates a click from a drag. Below it the press is still
## a tap, so a shaky hand never turns a row click into a scroll.
const DRAG_SLOP := 8.0
## A trackpad pan arrives in tiny unnamed units; this turns one into the same
## handful of design units a wheel notch moves.
const PAN_STEP := 60.0
const WHEEL_STEP := 110.0

var sheet = null
## Optional long-press handler (#107): while it watches a press the sheet's click
## waits for the release, so a club name can be held instead of pressed.
var hold = null
var pressing := false
var dragged := false
var press_at := Vector2.ZERO
var last_at := Vector2.ZERO

func _init(target) -> void:
	sheet = target

## A fresh page starts with no pointer history: a press belongs to the sheet that
## was on screen when it happened.
func reset() -> void:
	pressing = false
	dragged = false
	if hold != null:
		hold.clear()
	if sheet != null:
		sheet.holding = false

## Forward one event already converted into the sheet's design space. True when
## this grammar owned the event.
func handle(event: InputEvent, point: Vector2) -> bool:
	if sheet == null:
		return false
	if event is InputEventMouseMotion:
		_motion(point)
	elif event is InputEventPanGesture:
		# A trackpad scrolls with pan gestures rather than wheel buttons, so a
		# sheet that only listened for wheels read as frozen on a laptop.
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
		# A soft keyboard sends the character it types, often with no keycode at
		# all; a sheet with a text field reads that first (#201) and the key map
		# takes whatever it does not.
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

## Hover is free; holding the button turns the pointer into a scroll drag, and
## the travel since the last frame is charged to the body in one step.
func _motion(p: Vector2) -> void:
	sheet.mouse = p
	# The menu is modal: a pointer over it never reaches the sheet underneath.
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
	# A long press (or the menu it raised) owns the gesture: no click, no tap.
	if hold != null and hold.release_at(press_at):
		return
	if dragged:
		return
	var id: String = sheet.button_at(press_at)
	if id != "":
		sheet.click(id)
	elif sheet.has_method("tap"):
		sheet.tap(press_at)
