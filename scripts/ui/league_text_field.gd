class_name LeagueTextField
extends RefCounted


const MAX_CHARS := 24

const LETTERS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 "


static func accepts(ch: String) -> bool:
	return ch.length() == 1 and LETTERS.contains(ch)


static func char_of(code: int) -> String:
	if code < 32 or code > 126:
		return ""
	return char(code)


static func type_name(name: String, code: int) -> Array:
	if code == KEY_BACKSPACE:
		return [true, name.substr(0, maxi(name.length() - 1, 0))]
	return type_char(name, char_of(code))


static func type_char(name: String, ch: String) -> Array:
	if name.length() >= MAX_CHARS or not accepts(ch):
		return [false, name]
	return [true, name + (ch.to_upper() if name == "" else ch)]


static func type_name_into(state: Dictionary, code: int) -> bool:
	return _into(state, type_name(str(state.get("name", "")), code))


static func type_char_into(state: Dictionary, ch: String) -> bool:
	return _into(state, type_char(str(state.get("name", "")), ch))

static func _into(state: Dictionary, typed: Array) -> bool:
	if not bool(typed[0]):
		return false
	state["name"] = str(typed[1])
	return true
