class_name SoftKeyboard
extends RefCounted

## The platform's on-screen keyboard, for the game's own text fields (#201).
##
## Every name field in the game — the New League wizard, the System dialog's
## Save As, the Teams of Interest search — is painted text on a sheet rather
## than a `LineEdit`, so Godot has no edit view to attach and no keyboard to
## raise on its own. A touch player therefore tapped a field whose border lit up
## and then nothing happened. A sheet that takes a text field asks this module
## for the keyboard while the field has focus and puts it away when the field no
## longer does.
##
## The platform query and the DisplayServer calls live here so no sheet branches
## on the OS or the display backend itself (RUB-P3-05). On a build with no
## keyboard — a desktop, a headless run — every call is a no-op and the sheet's
## own key grammar remains the only way text arrives.
##
## `on_show` / `on_hide` are the seam a headless suite stands in: a run with no
## display can prove which field asked for a keyboard, on what text, and when it
## was put away, without a device.

## Called instead of the platform when set: `(text, frame, max_length)`.
static var on_show: Callable = Callable()
## Called instead of the platform when set.
static var on_hide: Callable = Callable()
## Called instead of the platform when set: true while the keyboard is up.
static var on_shown: Callable = Callable()

## True when the platform can raise an on-screen keyboard at all.
static func available() -> bool:
	return DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD)

## True while the keyboard is up. A player can put it away without the game
## hearing about it — Android's own back key does — so a field that is pressed
## again asks the platform rather than trusting its own bookkeeping.
static func shown() -> bool:
	if on_shown.is_valid():
		return bool(on_shown.call())
	return available() and DisplayServer.virtual_keyboard_get_height() > 0

## Raise the keyboard for a field holding `text`. `frame` is the field's rect in
## screen pixels (the platform uses it only as a placement hint) and `max_length`
## is what the field accepts, so the IME stops where the field's grammar does.
## Returns true when a keyboard was asked for.
static func show_field(text: String, frame: Rect2, max_length: int) -> bool:
	if on_show.is_valid():
		on_show.call(text, frame, max_length)
		return true
	if not available():
		return false
	DisplayServer.virtual_keyboard_show(text, frame, DisplayServer.KEYBOARD_TYPE_DEFAULT,
		max_length, text.length(), text.length())
	return true

## Put the keyboard away. Safe to call when it was never raised.
static func hide() -> void:
	if on_hide.is_valid():
		on_hide.call()
		return
	if available():
		DisplayServer.virtual_keyboard_hide()

## The field's frame in screen pixels: a design-space rect scaled by the layer
## the sheet is drawn on, which is how every other pointer conversion works.
static func frame_of(rect: Rect2, scale: float) -> Rect2:
	return Rect2(rect.position * scale, rect.size * scale)
