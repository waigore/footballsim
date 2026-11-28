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


static func toggle_cups(screen: LeagueScreen, country: String) -> void:
	if country == "" or not cup_country(screen, country):
		return
	var off: Array = (screen.wizard.get("cups_off", []) as Array).duplicate()
	if off.has(country):
		off.erase(country)
	else:
		off.append(country)
	screen.wizard["cups_off"] = off
	screen.refresh()


static func cup_country(screen: LeagueScreen, country: String) -> bool:
	for row in cup_countries(screen):
		if str((row as Dictionary).get("id", "")) == country:
			return true
	return false


static func cup_countries(screen: LeagueScreen) -> Array:
	var out: Array = []
	for country in LeagueCup.countries():
		var active := false
		for cid in screen.wizard.get("competitions", ["PL"]):
			if LeagueTiers.country_of(str(cid)) == str(country):
				active = true
				break
		if not active:
			continue
		out.append({"id": str(country), "label": "DOMESTIC CUPS — %s" % str(country).to_upper()})
	return out


static func cups_on(screen: LeagueScreen) -> Array:
	var out: Array = []
	for row in cup_countries(screen):
		var country := str(row["id"])
		if not (screen.wizard.get("cups_off", []) as Array).has(country):
			out.append(country)
	return out


static func any_cups(screen: LeagueScreen) -> bool:
	return not cups_on(screen).is_empty()
