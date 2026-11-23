class_name Prefs
extends RefCounted

## Player preferences that must survive a relaunch. Only the menu music volume
## lives here today, under the `bgm_volume` key the feature spec names.
##
## Stored in `user://` so the launcher's `--clear-cache` (which wipes the
## product's userdata folder) resets it exactly like every other local file.

const PATH := "user://prefs.cfg"
const SECTION := "audio"
const KEY_BGM := "bgm_volume"
## Sensible mid-high level: present under the menu chrome, not louder than a
## broadcast sting.
const DEFAULT_BGM := 0.7

static func clamp_volume(v: float) -> float:
	return clampf(v, 0.0, 1.0)

## Missing, unreadable or malformed prefs fall back to the default instead of
## taking the menu down.
static func load_bgm(path: String = PATH) -> float:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return DEFAULT_BGM
	var raw = cfg.get_value(SECTION, KEY_BGM, DEFAULT_BGM)
	if typeof(raw) != TYPE_FLOAT and typeof(raw) != TYPE_INT:
		return DEFAULT_BGM
	return clamp_volume(float(raw))

static func save_bgm(volume: float, path: String = PATH) -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, KEY_BGM, clamp_volume(volume))
	return cfg.save(path) == OK
