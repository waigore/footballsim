class_name LeagueWizardActions
extends RefCounted


static func toggle_league(screen, competition_id: String) -> void:
	if competition_id == "":
		return
	var chosen: Array = (screen.wizard.get("competitions", ["PL"]) as Array).duplicate()
	var next: Array = LeagueTiers.cascading_off(chosen, competition_id) \
		if chosen.has(competition_id) else LeagueTiers.cascading_on(chosen, competition_id)
	if next.is_empty():
		return
	screen.wizard["competitions"] = next
	screen.refresh()
