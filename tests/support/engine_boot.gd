class_name TestEngineBoot
extends RefCounted


static var _boot: MatchEngine = null

static func template() -> MatchEngine:
	if _boot == null:
		_boot = MatchEngine.new(1, "ENG-MUN1", "ENG-MCI1")
		_boot.verbose = false
	return _boot


static func match(seed_in: int) -> MatchEngine:
	var eng := MatchEngine.new(seed_in, "ENG-MUN1", "ENG-MCI1")
	eng.verbose = false
	return eng
