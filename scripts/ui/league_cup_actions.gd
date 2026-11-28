class_name LeagueCupActions
extends RefCounted


static func view(screen) -> Dictionary:
	var season: LeagueSeason = screen.season
	var state: Dictionary = screen.cups
	var out := {
		"cups": LeagueCupHub.competitions(season),
		"cup": str(state.get("cup", "")),
		"round": str(state.get("round", "")),
		"rounds": [], "ties": [], "cup_name": "", "cup_stage_label": "",
		"interests": season.record.interest.interests() if season != null else [],
		"touch": bool(screen.touch),
	}
	if str(out["cup"]) == "":
		return out
	var cid := str(out["cup"])
	var comp := PLRepository.shared().competition(cid)
	out["cup_name"] = str(comp.get("name", cid))
	var rounds := LeagueCupHub.rounds(cid)
	out["rounds"] = rounds
	var round_id := str(out["round"])
	if round_id == "" and not rounds.is_empty():
		round_id = str((rounds[LeagueCupHub.current_round(rounds)] as Dictionary)["id"])
	out["round"] = round_id
	var stage := LeagueCupState.stage(cid)
	out["cup_stage_label"] = LeagueCupHub.label(cid, stage) if stage != "" else "COMPLETE"
	if season != null and round_id != "":
		out["ties"] = LeagueCupHub.ties(season, cid, round_id)
	return out


static func open(screen) -> void:
	screen.cups = {"cup": "", "round": ""}
	LeagueDoors.go(screen, LeagueScreen.MODE_CUPS)
	screen.refresh()


static func press(screen, id: String) -> bool:
	if not id.begins_with("cup:") and not id.begins_with("round:"):
		return false
	if id.begins_with("cup:"):
		screen.cups = {"cup": id.substr(4), "round": ""}
	else:
		var state: Dictionary = screen.cups
		state["round"] = id.substr(6)
		screen.cups = state
	screen.refresh()
	return true


static func back(screen) -> bool:
	var state: Dictionary = screen.cups
	if str(state.get("round", "")) != "":
		state["round"] = ""
		screen.cups = state
		screen.refresh()
		return true
	if str(state.get("cup", "")) != "":
		screen.cups = {"cup": "", "round": ""}
		screen.refresh()
		return true
	return false
