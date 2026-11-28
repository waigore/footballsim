class_name UiTheme
extends RefCounted


const PATH := "res://ui/themes/footballsim.tres"

const FALLBACK := {
	&"bg": Color(0.012, 0.020, 0.026),
	&"panel": Color(0.035, 0.055, 0.070, 0.96),
	&"panel_light": Color(0.075, 0.105, 0.125, 0.96),
	&"border": Color(1, 1, 1, 0.085),
	&"text": Color(0.92, 0.95, 0.96),
	&"dim": Color(0.55, 0.64, 0.69),
	&"soft": Color(0.66, 0.73, 0.77),
	&"gold": Color(0.96, 0.78, 0.30),
	&"live": Color(0.62, 0.88, 0.66),
	&"danger": Color(0.78, 0.26, 0.22),
	&"scrim": Color(0, 0, 0, 0.55),
	&"ink": Color(0.06, 0.06, 0.05),
	&"uecl": Color(0.55, 0.72, 0.92),
}

static var _theme: Theme = null
static var _loaded := false
static var _path := PATH


static func theme() -> Theme:
	if _loaded:
		return _theme
	_loaded = true
	if ResourceLoader.exists(_path):
		_theme = load(_path) as Theme
	return _theme


static func has_theme() -> bool:
	return theme() != null


static func color(key: StringName) -> Color:
	var loaded := theme()
	if loaded != null and loaded.has_color(key, &"Colors"):
		return loaded.get_color(key, &"Colors")
	return FALLBACK.get(key, Color.MAGENTA)


static func has_color(key: StringName) -> bool:
	var loaded := theme()
	return loaded != null and loaded.has_color(key, &"Colors")


static func style(theme_type: StringName, style_name: StringName) -> StyleBox:
	var loaded := theme()
	if loaded == null:
		return null
	var box: StyleBox = loaded.get_stylebox(style_name, theme_type)
	if box == null:
		return null
	return box.duplicate() as StyleBox


static func box(theme_type: StringName, style_name: StringName) -> StyleBoxFlat:
	var found := style(theme_type, style_name)
	if found is StyleBoxFlat:
		return found as StyleBoxFlat
	return null


static func font(theme_type: StringName = &"Body") -> Font:
	var loaded := theme()
	if loaded == null:
		return null
	return loaded.get_font(&"font", theme_type)


static func font_size(theme_type: StringName = &"Body") -> int:
	var loaded := theme()
	if loaded == null:
		return 0
	return loaded.get_font_size(&"font_size", theme_type)


static func bold() -> Font:
	return font(&"Band")


static func medium() -> Font:
	return font(&"Body")


static func body() -> Font:
	if theme() == null:
		return null
	return theme().default_font


static func fonts() -> Dictionary:
	return {"bold": bold(), "med": medium(), "body": body()}


static func roles() -> PackedStringArray:
	return PackedStringArray([&"Title", &"Band", &"Body", &"Dim", &"Caption", &"Gold"])


static func color_keys() -> PackedStringArray:
	return PackedStringArray(FALLBACK.keys())


static func use_path_for_tests(path: String) -> void:
	_path = path
	_theme = null
	_loaded = false


static func reset_for_tests() -> void:
	_path = PATH
	_theme = null
	_loaded = false
