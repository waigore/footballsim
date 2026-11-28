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


static func toggle_cups(screen: Variant, country: String) -> void:
	if country == "" or LeagueCup.country_cup_ids(country).is_empty():
		return
	var off: Array = (screen.wizard.get("cup_off", []) as Array).duplicate()
	if off.has(country):
		off.erase(country)
	else:
		off.append(country)
	screen.wizard["cup_off"] = off
	screen.refresh()


static func cups_on(screen: Variant) -> Array:
	return countries(selected(screen), screen.wizard.get("cup_off", []) as Array)


static func countries(competitions: Array, off: Array = []) -> Array:
	var out: Array = []
	for country in LeagueCup.countries_for(competitions):
		if not off.has(country):
			out.append(country)
	return out


static func selected(screen: Variant) -> Array:
	return screen.wizard.get("competitions", ["PL"]) as Array
