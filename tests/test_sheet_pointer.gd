extends GdToolsTest

## The pointer grammar the league and encyclopedia sheets share: a press that
## lifts in place is a click, a press that travels is a scroll drag, and wheel,
## pan and key events reach the sheet without ever firing a click.

class FakeSheet extends RefCounted:
	var mouse := Vector2(-1000, -1000)
	var holding := false
	var touch := true
	var hit := ""
	var clicks: Array = []
	var scrolls: Array = []
	var keys: Array = []

	func button_at(_p: Vector2) -> String:
		return hit

	func click(id: String) -> void:
		clicks.append(id)

	func scroll_by(dy: float, dx: float = 0.0) -> void:
		scrolls.append(Vector2(dx, dy))

	func key(code: int) -> bool:
		keys.append(code)
		return true

class TapSheet extends FakeSheet:
	var taps: Array = []

	func tap(p: Vector2) -> bool:
		taps.append(p)
		return true

func _down(p: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = p
	return ev

func _up(p: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = p
	return ev

func _motion(p: Vector2) -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.position = p
	return ev

func test_a_press_that_lifts_in_place_is_a_click() -> void:
	var sheet := FakeSheet.new()
	sheet.hit = "home_prev"
	var pointer := SheetPointer.new(sheet)
	assert_true(pointer.handle(_down(Vector2(10, 20)), Vector2(10, 20)), "the press was not taken")
	assert_true(sheet.holding, "the press did not claim the sheet")
	assert_eq(sheet.mouse, Vector2(10, 20), "the press did not move the sheet pointer")
	assert_true(pointer.handle(_up(Vector2(10, 20)), Vector2(10, 20)), "the release was not taken")
	assert_false(sheet.holding, "the release left the sheet holding")
	assert_eq(sheet.clicks.size(), 1, "the still press did not click a door")
	assert_eq(str(sheet.clicks[0]), "home_prev", "the press landed on another door")
	assert_eq(sheet.scrolls.size(), 0, "a still press scrolled the sheet")

func test_a_press_that_travels_becomes_a_scroll_and_never_clicks() -> void:
	var sheet := FakeSheet.new()
	sheet.hit = "row"
	var pointer := SheetPointer.new(sheet)
	pointer.handle(_down(Vector2(40, 100)), Vector2(40, 100))
	pointer.handle(_motion(Vector2(40, 60)), Vector2(40, 60))
	assert_false(sheet.holding, "the drag still reads as a tap")
	assert_eq(sheet.scrolls.size(), 1, "the drag did not move the body")
	assert_eq(sheet.scrolls[0], Vector2(0, 40), "the drag charged the wrong travel")
	pointer.handle(_up(Vector2(40, 60)), Vector2(40, 60))
	assert_eq(sheet.clicks.size(), 0, "a drag clicked the row it started on")

func test_a_shaky_hand_still_counts_as_a_click() -> void:
	var sheet := FakeSheet.new()
	sheet.hit = "back"
	var pointer := SheetPointer.new(sheet)
	pointer.handle(_down(Vector2(30, 30)), Vector2(30, 30))
	pointer.handle(_motion(Vector2(33, 31)), Vector2(33, 31))
	assert_eq(sheet.scrolls.size(), 0, "a tiny shake started a scroll")
	pointer.handle(_up(Vector2(33, 31)), Vector2(33, 31))
	assert_eq(sheet.clicks.size(), 1, "a tiny shake lost the click")

func test_a_sheet_with_its_own_rows_receives_a_tap() -> void:
	var sheet := TapSheet.new()
	var pointer := SheetPointer.new(sheet)
	pointer.handle(_down(Vector2(5, 6)), Vector2(5, 6))
	pointer.handle(_up(Vector2(5, 6)), Vector2(5, 6))
	assert_eq(sheet.taps.size(), 1, "the row hit test never saw the tap")
	assert_eq(sheet.taps[0], Vector2(5, 6), "the tap landed on another point")
	assert_eq(sheet.clicks.size(), 0, "a sheet row was also read as a door")
	sheet.hit = "close"
	pointer.handle(_down(Vector2(7, 8)), Vector2(7, 8))
	pointer.handle(_up(Vector2(7, 8)), Vector2(7, 8))
	assert_eq(sheet.clicks.size(), 1, "a drawn door did not take the press")
	assert_eq(sheet.taps.size(), 1, "a door press fell through to the row tap")

func test_wheel_and_trackpad_pan_move_the_body() -> void:
	var sheet := FakeSheet.new()
	var pointer := SheetPointer.new(sheet)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	down.pressed = true
	assert_true(pointer.handle(down, Vector2.ZERO), "the wheel notch was not taken")
	assert_eq(sheet.scrolls.size(), 1, "the wheel notch did not scroll")
	assert_eq(sheet.scrolls[0], Vector2(0, SheetPointer.WHEEL_STEP), "the wheel moved the wrong way")
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_WHEEL_UP
	up.pressed = true
	pointer.handle(up, Vector2.ZERO)
	assert_eq(sheet.scrolls[1], Vector2(0, -SheetPointer.WHEEL_STEP), "the wheel did not scroll back")
	var pan := InputEventPanGesture.new()
	pan.delta = Vector2(2.0, 0.5)
	assert_true(pointer.handle(pan, Vector2.ZERO), "the trackpad pan was not taken")
	assert_eq(sheet.scrolls[2], Vector2(2.0 * SheetPointer.PAN_STEP, 0.5 * SheetPointer.PAN_STEP),
		"the pan lost an axis")

func test_keys_reach_the_sheet_and_repeats_do_not() -> void:
	var sheet := FakeSheet.new()
	var pointer := SheetPointer.new(sheet)
	var key := InputEventKey.new()
	key.keycode = KEY_DOWN
	key.pressed = true
	assert_true(pointer.handle(key, Vector2.ZERO), "the key was not taken")
	assert_eq(sheet.keys.size(), 1, "the sheet never saw the key")
	assert_eq(int(sheet.keys[0]), KEY_DOWN, "the sheet saw another key")
	var echo := InputEventKey.new()
	echo.keycode = KEY_DOWN
	echo.pressed = true
	echo.echo = true
	assert_false(pointer.handle(echo, Vector2.ZERO), "a key repeat was taken")
	assert_eq(sheet.keys.size(), 1, "a key repeat reached the sheet")

func test_hover_never_scrolls_or_clicks() -> void:
	var sheet := FakeSheet.new()
	sheet.touch = false
	var pointer := SheetPointer.new(sheet)
	assert_true(pointer.handle(_motion(Vector2(50, 60)), Vector2(50, 60)), "hover was not taken")
	assert_eq(sheet.mouse, Vector2(50, 60), "hover did not move the sheet pointer")
	assert_false(sheet.holding, "hover held the sheet down")
	assert_eq(sheet.scrolls.size(), 0, "hover scrolled the body")
	assert_eq(sheet.clicks.size(), 0, "hover clicked a door")
	sheet.touch = true
	pointer.handle(_motion(Vector2(70, 80)), Vector2(70, 80))
	assert_eq(sheet.mouse, Vector2(70, 80), "hover on a touch sheet did not move the pointer")

func test_reset_drops_a_press_belonging_to_the_old_page() -> void:
	var sheet := FakeSheet.new()
	sheet.hit = "row"
	var pointer := SheetPointer.new(sheet)
	pointer.handle(_down(Vector2(12, 12)), Vector2(12, 12))
	assert_true(sheet.holding, "the press did not claim the sheet")
	pointer.reset()
	assert_false(sheet.holding, "the old page kept the press")
	pointer.handle(_up(Vector2(12, 12)), Vector2(12, 12))
	assert_eq(sheet.clicks.size(), 0, "a release after the page change clicked through")

func test_an_unrelated_event_is_left_for_the_caller() -> void:
	var sheet := FakeSheet.new()
	var pointer := SheetPointer.new(sheet)
	var touch := InputEventScreenTouch.new()
	assert_false(pointer.handle(touch, Vector2.ZERO), "a touch event was taken as a click")
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	assert_false(pointer.handle(right, Vector2.ZERO), "a right press was taken as a click")
	assert_eq(sheet.clicks.size(), 0, "an unrelated event clicked a door")

func test_a_pointer_without_a_sheet_is_inert() -> void:
	var pointer := SheetPointer.new(null)
	assert_false(pointer.handle(_down(Vector2.ZERO), Vector2.ZERO), "a sheet-less pointer took a press")
	pointer.reset()
