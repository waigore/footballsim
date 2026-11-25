class_name LeagueTextField
extends RefCounted

## Typing into a one-line name field: the wizard's league name, the System
## dialog's Save As name and the Teams of Interest search. Pure key → text, so
## each sheet keeps its own field state and reads the same editing rule.
##
## It sits beside the sheets rather than on one of them: the hub used to carry
## it, and the System dialog and the shortlist had to borrow the hub's grammar
## for a field on their own pose.

## The most a field accepts; a season name also has to fit a load row.
const MAX_CHARS := 24

## `[handled, name]` for one key: BACKSPACE trims, a letter, digit or space is
## appended (a field's first letter is upper case), and everything else is left
## for the caller. Returning `false` is what lets BACKSPACE on an empty field
## still reach the sheet's BACK door.
static func type_name(name: String, code: int) -> Array:
	if code == KEY_BACKSPACE:
		return [true, name.substr(0, maxi(name.length() - 1, 0))]
	if name.length() >= MAX_CHARS:
		return [false, name]
	var ch := char(code)
	if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == " ":
		return [true, name + (ch.to_upper() if name == "" else ch)]
	return [false, name]

## Edit the name inside a sheet's state dictionary. True when the key belonged
## to the field, so the caller only has to repaint.
static func type_name_into(state: Dictionary, code: int) -> bool:
	var typed: Array = type_name(str(state.get("name", "")), code)
	if not bool(typed[0]):
		return false
	state["name"] = str(typed[1])
	return true
