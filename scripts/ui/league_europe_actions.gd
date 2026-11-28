class_name LeagueEuropeActions
extends RefCounted


const STEP := 0.24


static func ids(screen) -> Array:
	var save: LeagueSave = screen.season.save if screen.season != null else null
	return LeagueEurope.active_ids(save)


static func open(screen) -> void:
	var active := ids(screen)
	if active.is_empty():
		return
	screen.europe = {"comp": str(active[0]), "tab": "", "round": ""}
	LeagueDoors.go(screen, LeagueScreen.MODE_EUROPE)


static func open_stage(screen, competition_id: String = "") -> void:
	var active := ids(screen)
	if active.is_empty():
		return
	var comp := competition_id
	if comp == "" or not active.has(comp):
		comp = str(active[0])
	screen.europe["comp"] = comp
	var stage := LeagueEurope.stage_of(comp)
	if LeagueEurope.KO_ROUNDS.has(stage):
		screen.europe["tab"] = "bracket"
	elif stage == LeagueUefa.LEAGUE_STAGE:
		screen.europe["tab"] = "table"
	else:
		screen.europe["tab"] = "qualifying"
	screen.europe["round"] = ""
	LeagueDoors.go(screen, LeagueScreen.MODE_EUROPE_STAGE)


static func open_draw(screen, competition_id: String, round_id: String) -> void:
	screen.europe_draw = {"competition": competition_id, "round": round_id,
		"revealed": 0, "done": false, "t": 0.0}
	LeagueDoors.go(screen, LeagueScreen.MODE_EUROPE_DRAW)


static func press(screen, id: String) -> bool:
	if id.begins_with("europe:comp:"):
		open_stage(screen, id.substr(12))
		return true
	if id.begins_with("europe:tab:"):
		screen.europe["tab"] = id.substr(11)
		screen.refresh()
		return true
	if id.begins_with("europe:round:"):
		screen.europe["round"] = id.substr(13)
		screen.refresh()
		return true
	if id == "europe:draw:skip":
		finish(screen)
		return true
	if id == "europe:draw:open":
		var comp := str(screen.europe_draw.get("competition", ""))
		finish(screen)
		open_stage(screen, comp)
		return true
	if id.begins_with("europe:draw:"):
		var parts := id.substr(12).split(":")
		if parts.size() >= 2:
			open_draw(screen, str(parts[0]), str(parts[1]))
		return true
	return false


static func finish(screen) -> void:
	var save: LeagueSave = screen.season.save if screen.season != null else null
	var competition_id := str(screen.europe_draw.get("competition", ""))
	var round_id := str(screen.europe_draw.get("round", ""))
	screen.europe_draw["revealed"] = LeagueEurope.pairs(competition_id, round_id).size()
	screen.europe_draw["done"] = true
	LeagueEurope.mark_seen(save, competition_id, round_id)
	screen.refresh()


static func tick(screen, delta: float) -> bool:
	if screen.mode != LeagueScreen.MODE_EUROPE_DRAW:
		return false
	if bool(screen.europe_draw.get("done", false)):
		return false
	var competition_id := str(screen.europe_draw.get("competition", ""))
	var round_id := str(screen.europe_draw.get("round", ""))
	var count := LeagueEurope.pairs(competition_id, round_id).size()
	screen.europe_draw["t"] = float(screen.europe_draw.get("t", 0.0)) + delta
	var step := int(float(screen.europe_draw["t"]) / STEP)
	var revealed := int(screen.europe_draw.get("revealed", 0))
	if step <= revealed and revealed < count:
		return false
	if count == 0:
		screen.europe_draw["done"] = true
		screen.refresh()
		return true
	screen.europe_draw["revealed"] = mini(step, count)
	screen.refresh()
	return true
