class_name LeagueEuropeActions
extends RefCounted


static func open(screen: LeagueScreen) -> void:
	LeagueDoors.go(screen, LeagueScreen.MODE_EUROPE)
	screen.refresh()


static func stage(screen: LeagueScreen, competition_id: String) -> void:
	if screen.season == null:
		return
	if not LeagueEurope.active(screen.season.save).has(competition_id):
		return
	screen.europe_comp = competition_id
	screen.europe_round = LeagueEurope.stage_of(competition_id)
	LeagueDoors.go(screen, LeagueScreen.MODE_EUROPE_STAGE)
	screen.refresh()


static func hub(screen: LeagueScreen) -> void:
	LeagueDoors.go(screen, LeagueScreen.MODE_EUROPE)
	screen.refresh()


static func round_of(screen: LeagueScreen) -> String:
	var competition_id := str(screen.europe_comp)
	var round_id := str(screen.europe_round)
	if round_id != "" and LeagueUefa.has_stage(competition_id, round_id):
		return round_id
	return LeagueEurope.stage_of(competition_id)


static func pick_round(screen: LeagueScreen, round_id: String) -> void:
	if round_id == "":
		return
	screen.europe_round = round_id
	screen.refresh()


static func press(screen: LeagueScreen, id: String) -> bool:
	if id.begins_with("europe:"):
		stage(screen, id.substr(7))
		return true
	if id.begins_with("europeround:"):
		pick_round(screen, id.substr(12))
		return true
	if id == "europehub":
		hub(screen)
		return true
	return false
