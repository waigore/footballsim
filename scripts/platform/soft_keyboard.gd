class_name SoftKeyboard
extends RefCounted


static var on_show: Callable = Callable()

static var on_hide: Callable = Callable()

static var on_shown: Callable = Callable()


static func available() -> bool:
	return DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD)


static func shown() -> bool:
	if on_shown.is_valid():
		return bool(on_shown.call())
	return available() and DisplayServer.virtual_keyboard_get_height() > 0


static func show_field(text: String, frame: Rect2, max_length: int) -> bool:
	if on_show.is_valid():
		on_show.call(text, frame, max_length)
		return true
	if not available():
		return false
	DisplayServer.virtual_keyboard_show(text, frame, DisplayServer.KEYBOARD_TYPE_DEFAULT,
		max_length, text.length(), text.length())
	return true


static func hide() -> void:
	if on_hide.is_valid():
		on_hide.call()
		return
	if available():
		DisplayServer.virtual_keyboard_hide()


static func frame_of(rect: Rect2, scale: float) -> Rect2:
	return Rect2(rect.position * scale, rect.size * scale)
