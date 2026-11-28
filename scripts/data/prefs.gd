class_name Prefs
extends RefCounted


const PATH := "user://prefs.cfg"
const SECTION := "audio"
const KEY_BGM := "bgm_volume"


const DEFAULT_BGM := 0.7


const SECTION_UI := "ui"
const KEY_HUD := "hud_visible"

const DEFAULT_HUD := true


const MODES := ["highlights", "goals", "full"]
const DEFAULT_MODE := "highlights"
const KEY_MODE := "match_mode"

const MODE_LABELS := {
	"highlights": "HIGHLIGHTS",
	"goals": "GOALS ONLY",
	"full": "FULL MATCH",
}

static func clamp_volume(v: float) -> float:
	return clampf(v, 0.0, 1.0)


static func load_bgm(path: String = PATH) -> float:
	var raw = _read(path).get_value(SECTION, KEY_BGM, DEFAULT_BGM)
	if typeof(raw) != TYPE_FLOAT and typeof(raw) != TYPE_INT:
		return DEFAULT_BGM
	return clamp_volume(float(raw))

static func save_bgm(volume: float, path: String = PATH) -> bool:
	var cfg := _read(path)
	cfg.set_value(SECTION, KEY_BGM, clamp_volume(volume))
	return cfg.save(path) == OK


static func load_hud(path: String = PATH) -> bool:
	var raw = _read(path).get_value(SECTION_UI, KEY_HUD, DEFAULT_HUD)
	if typeof(raw) != TYPE_BOOL:
		return DEFAULT_HUD
	return bool(raw)

static func save_hud(on: bool, path: String = PATH) -> bool:
	var cfg := _read(path)
	cfg.set_value(SECTION_UI, KEY_HUD, bool(on))
	return cfg.save(path) == OK


static func normalize_mode(mode: String) -> String:
	return mode if MODES.has(mode) else DEFAULT_MODE


static func next_mode(mode: String) -> String:
	return str(MODES[(MODES.find(normalize_mode(mode)) + 1) % MODES.size()])

static func mode_label(mode: String) -> String:
	return str(MODE_LABELS.get(normalize_mode(mode), MODE_LABELS[DEFAULT_MODE]))


static func load_mode(path: String = PATH) -> String:
	var raw = _read(path).get_value(SECTION_UI, KEY_MODE, DEFAULT_MODE)
	if typeof(raw) != TYPE_STRING:
		return DEFAULT_MODE
	return normalize_mode(str(raw))

static func save_mode(mode: String, path: String = PATH) -> bool:
	var cfg := _read(path)
	cfg.set_value(SECTION_UI, KEY_MODE, normalize_mode(mode))
	return cfg.save(path) == OK


const KEY_ATTRS := "attribute_view"
const ATTR_MODES := ["SIMPLIFIED", "FULL"]
const DEFAULT_ATTRS := "SIMPLIFIED"

static var _attrs_cache := ""

static func normalize_attrs(mode: String) -> String:
	return "FULL" if mode == "FULL" else DEFAULT_ATTRS

static func load_attrs(path: String = PATH) -> String:
	if path == PATH and _attrs_cache != "":
		return _attrs_cache
	var raw = _read(path).get_value(SECTION_UI, KEY_ATTRS, DEFAULT_ATTRS)
	if typeof(raw) != TYPE_STRING:
		return DEFAULT_ATTRS
	var mode := normalize_attrs(str(raw))
	if path == PATH:
		_attrs_cache = mode
	return mode

static func save_attrs(mode: String, path: String = PATH) -> bool:
	var cfg := _read(path)
	var value := normalize_attrs(mode)
	cfg.set_value(SECTION_UI, KEY_ATTRS, value)
	if path == PATH:
		_attrs_cache = value
	return cfg.save(path) == OK


static func _read(path: String) -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(path)
	return cfg
