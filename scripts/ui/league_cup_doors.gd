class_name LeagueCupDoors
extends RefCounted


static func nav(screen, pose: String) -> bool:
	if pose != "cups":
		return false
	LeagueDoors.go(screen, LeagueScreen.MODE_CUPS)
	screen.refresh()
	return true


static func press(screen, id: String) -> bool:
	if id.begins_with("cup:"):
		open_cup(screen, id.substr(4))
		return true
	if id.begins_with("cupround:"):
		_open_at(screen, id.substr(9), LeagueScreen.MODE_CUP, true)
		return true
	if id.begins_with("cupbracket:"):
		_open_at(screen, id.substr(11), LeagueScreen.MODE_BRACKET, false)
		return true
	if id.begins_with("cupdraw:"):
		open_draw(screen, id.substr(8))
		return true
	if id == "skiptodraw":
		LeagueCupDrawSheet.settle_all(screen)
		screen.refresh()
		return true
	if id.begins_with("cupmatch:"):
		screen.show_report(id.substr(9))
		return true
	return false


static func split(payload: String) -> Array:
	var parts := payload.split(":")
	return [str(parts[0]), str(parts[1]) if parts.size() > 1 else ""]


static func _open_at(screen, payload: String, mode: String, pin: bool) -> void:
	var parts := split(payload)
	if str(parts[0]) == "":
		return
	screen.cup_focus = str(parts[0])
	if pin or str(parts[1]) != "":
		screen.cups_round = str(parts[1])
	screen.draw_state = {"shown": 0, "clock": 0.0}
	LeagueDoors.go(screen, mode)
	screen.refresh()


static func open_cup(screen, competition_id: String) -> void:
	if competition_id == "":
		return
	screen.cup_focus = competition_id
	screen.cups_round = ""
	screen.draw_state = {"shown": 0, "clock": 0.0}
	LeagueDoors.go(screen, LeagueScreen.MODE_CUP)
	screen.refresh()


static func open_draw(screen, payload: String) -> void:
	var parts := split(payload)
	screen.cup_focus = str(parts[0])
	if screen.cup_focus == "":
		return
	screen.cups_round = str(parts[1])
	if str(screen.cups_round) == "":
		screen.cups_round = LeagueCupState.stage(screen.cup_focus)
	var drawn := LeagueCupView.draw(screen.season, screen.cup_focus, screen.cups_round)
	var pairs := (drawn.get("pairs", []) as Array).size()
	screen.draw_state = {"shown": pairs if bool(drawn.get("seen", false)) else 0,
		"clock": 0.0}
	LeagueDoors.go(screen, LeagueScreen.MODE_CUP_DRAW)
	screen.refresh()


static func tick(screen, delta: float) -> bool:
	if screen.mode != LeagueScreen.MODE_CUP_DRAW:
		return false
	if LeagueCupDrawSheet.tick(screen, delta):
		screen.refresh()
		return true
	return false


static func leave_draw(screen) -> void:
	if screen.cup_focus == "":
		return
	LeagueCupDrawSheet.settle_all(screen)
	LeagueCupView.mark_draw_seen(screen.season, screen.cup_focus, str(screen.cups_round))
