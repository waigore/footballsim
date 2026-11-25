class_name LeagueTextField
extends RefCounted

## Typing into a one-line name field: the wizard's league name, the System
## dialog's Save As name and the Teams of Interest search. Pure key → text, so
## each sheet keeps its own field state and reads the same editing rule.
##
## It sits beside the sheets rather than on one of them: the hub used to carry
## it, and the System dialog and the shortlist had to borrow the hub's grammar
## for a field on their own pose.
##
## Two paths reach the same rule: a physical key arrives as a keycode, and a soft
## keyboard arrives as the character itself, often with no keycode at all (#201).
## Both end in `type_char`, so neither can drift from the other.

## The most a field accepts; a season name also has to fit a load row.
const MAX_CHARS := 24
## The characters a name may carry: letters, digits and the space between them.
const LETTERS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 "

## True for a character a name may carry. Everything else — punctuation, a
## control code, a key that names no character — is left for the caller.
static func accepts(ch: String) -> bool:
	return ch.length() == 1 and LETTERS.contains(ch)

## The character a physical key prints, or "" for a keycode that names none (a
## cursor key, an escape, a modifier). Guards `char()`, which would otherwise
## hand back a replacement glyph for a keycode far above the codepoint range.
static func char_of(code: int) -> String:
	if code < 32 or code > 126:
		return ""
	return char(code)

## `[handled, name]` for one key: BACKSPACE trims, a letter, digit or space is
## appended (a field's first letter is upper case), and everything else is left
## for the caller. Returning `false` is what lets BACKSPACE on an empty field
## still reach the sheet's BACK door.
static func type_name(name: String, code: int) -> Array:
	if code == KEY_BACKSPACE:
		return [true, name.substr(0, maxi(name.length() - 1, 0))]
	return type_char(name, char_of(code))

## `[handled, name]` for one typed character, from a physical key or from the
## platform's own text.
static func type_char(name: String, ch: String) -> Array:
	if name.length() >= MAX_CHARS or not accepts(ch):
		return [false, name]
	return [true, name + (ch.to_upper() if name == "" else ch)]

## Edit the name inside a sheet's state dictionary. True when the key belonged
## to the field, so the caller only has to repaint.
static func type_name_into(state: Dictionary, code: int) -> bool:
	return _into(state, type_name(str(state.get("name", "")), code))

## The same edit, from a character. True when the field took it.
static func type_char_into(state: Dictionary, ch: String) -> bool:
	return _into(state, type_char(str(state.get("name", "")), ch))

static func _into(state: Dictionary, typed: Array) -> bool:
	if not bool(typed[0]):
		return false
	state["name"] = str(typed[1])
	return true
