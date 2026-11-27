class_name TestEngineBoot
extends RefCounted


static var _boot: MatchEngine = null

static func template() -> MatchEngine:
	if _boot == null:
		_boot = MatchEngine.new(1, "MUN", "MCI")
		_boot.verbose = false
	return _boot


static func match(seed_in: int) -> MatchEngine:
	var eng := MatchEngine.new(seed_in, "MUN", "MCI")
	eng.verbose = false
	return eng
