class_name TestEngineBoot
extends RefCounted

## The engine without the shell it normally rides in.
##
## Every suite that wants a live engine used to instantiate `res://scripts/main.gd`
## — main.gd builds `MatchEngine.new(...)`, which parses and links the whole
## engine class chain (core → pitch → presentation → duels → actions → play →
## rules → clock). The first engine of a process pays that load anyway, so it is
## booted once here from the same twins that engine is built for, and later
## suites build their own engines on the already-linked chain.
##
## `match` is the reliable read: a fresh engine on the same twins as the template
## starts from the identical kick-off shape, so a caller can build it directly.
static var _boot: MatchEngine = null

static func template() -> MatchEngine:
	if _boot == null:
		_boot = MatchEngine.new(1, "MUN", "MCI")
		_boot.verbose = false
	return _boot

## A fresh engine on the twins the boot template links: the same kick-off shape,
## free to tick, with the class chain already parsed for this run.
static func match(seed_in: int) -> MatchEngine:
	var eng := MatchEngine.new(seed_in, "MUN", "MCI")
	eng.verbose = false
	return eng
