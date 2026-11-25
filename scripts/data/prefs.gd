class_name Prefs
extends RefCounted

## Player preferences that must survive a relaunch: the menu music volume, and
## whether the match HUD's chrome is shown (#158).
##
## Stored in `user://` so the launcher's `--clear-cache` (which wipes the
## product's userdata folder) resets it exactly like every other local file.

const PATH := "user://prefs.cfg"
const SECTION := "audio"
const KEY_BGM := "bgm_volume"
## Sensible mid-high level: present under the menu chrome, not louder than a
## broadcast sting.
const DEFAULT_BGM := 0.7

## The match HUD's choice keeps its own section: each save re-reads the file it
## is editing, so writing one preference never erases the other.
const SECTION_UI := "ui"
const KEY_HUD := "hud_visible"
## Chrome on until the player turns it off.
const DEFAULT_HUD := true

static func clamp_volume(v: float) -> float:
	return clampf(v, 0.0, 1.0)

## Missing, unreadable or malformed prefs fall back to the default instead of
## taking the menu down.
static func load_bgm(path: String = PATH) -> float:
	var raw = _read(path).get_value(SECTION, KEY_BGM, DEFAULT_BGM)
	if typeof(raw) != TYPE_FLOAT and typeof(raw) != TYPE_INT:
		return DEFAULT_BGM
	return clamp_volume(float(raw))

static func save_bgm(volume: float, path: String = PATH) -> bool:
	var cfg := _read(path)
	cfg.set_value(SECTION, KEY_BGM, clamp_volume(volume))
	return cfg.save(path) == OK

## The match HUD choice: a bool and only a bool — a stray value left by an older
## build reads as the default instead of standing in for the player's choice.
static func load_hud(path: String = PATH) -> bool:
	var raw = _read(path).get_value(SECTION_UI, KEY_HUD, DEFAULT_HUD)
	if typeof(raw) != TYPE_BOOL:
		return DEFAULT_HUD
	return bool(raw)

static func save_hud(on: bool, path: String = PATH) -> bool:
	var cfg := _read(path)
	cfg.set_value(SECTION_UI, KEY_HUD, bool(on))
	return cfg.save(path) == OK

## A fresh config, or the one already on disk: the getters above read their
## defaults from an empty file, and a save edits the keys it owns.
static func _read(path: String) -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(path)
	return cfg
