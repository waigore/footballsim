class_name SeasonCalendar
extends RefCounted


static func next_label(label: String) -> String:
	var parts := label.split("-")
	if parts.size() < 2 or parts[0].length() < 4:
		return label
	var start := int(parts[0]) + 1
	return "%d-%02d" % [start, (start + 1) % 100]


static func shift(season: LeagueSeason, years: int) -> int:
	if season == null or season.save == null or years <= 0:
		return 0
	var label := next_label(season.save.season_label())
	var touched := 0
	for cid in season.save.actives:
		var rules: Dictionary = season.save.rules_for(str(cid)).duplicate(true)
		rules["season_start"] = FixtureCalendar.add_years(str(rules.get("season_start", "")), years)
		rules["season_end"] = FixtureCalendar.add_years(str(rules.get("season_end", "")), years)
		if LeagueRules.write(str(cid), rules):
			touched += 1
		season.save.rules_by[str(cid)] = LeagueRules.normalize(rules)
		PLDatabase.execute("UPDATE competition SET season_label = ? WHERE id = ?;", [label, str(cid)])
	var cups: Array = LeagueCup.active_ids(season.save)
	for cid in LeagueUefa.active_ids(season.save):
		if not cups.has(str(cid)):
			cups.append(str(cid))
	for cid in cups:
		if _shift_competition(str(cid), years, label):
			touched += 1
	if not season.save.actives.is_empty():
		season.save.rules = season.save.rules_for(str(season.save.actives[0]))
	PLRepository.shared().invalidate()
	return touched


static func _shift_competition(competition_id: String, years: int, label: String) -> bool:
	var comp := PLRepository.shared().competition(competition_id)
	var stored: Variant = comp.get("rules", {})
	if not stored is Dictionary or (stored as Dictionary).is_empty():
		return false
	var rules: Dictionary = (stored as Dictionary).duplicate(true)
	for key in ["season_start", "season_end"]:
		if rules.has(key):
			rules[key] = FixtureCalendar.add_years(str(rules[key]), years)
	var rounds: Array = rules.get("rounds", [])
	for row in rounds:
		if not row is Dictionary:
			continue
		for key in ["date", "second_leg"]:
			if (row as Dictionary).has(key):
				(row as Dictionary)[key] = FixtureCalendar.add_years(str((row as Dictionary)[key]), years)
	rules["rounds"] = rounds
	return PLDatabase.execute(
		"UPDATE competition SET season_label = ?, rules = ? WHERE id = ?;",
		[label, JSON.stringify(rules), competition_id])
