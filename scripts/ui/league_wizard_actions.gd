class_name LeagueWizardActions
extends RefCounted

## The New League wizard's one stateful rule: toggle a league on or off, with at
## least one always on. The German pair is one control (#241): it turns both
## tiers on together, because a save that runs one German tier cannot settle a
## Relegation.

static func toggle_league(screen, competition_id: String) -> void:
	if competition_id == "":
		return
	var members: Array = ["BL", "BL2"] if competition_id == "DE" else [competition_id]
	var comps: Array = screen.wizard.get("competitions", ["PL"]).duplicate()
	var all_on := true
	for cid in members:
		if not comps.has(cid):
			all_on = false
	if all_on:
		if comps.size() <= members.size():
			return
		for cid in members:
			comps.erase(cid)
	else:
		for cid in members:
			if not comps.has(cid):
				comps.append(cid)
	screen.wizard["competitions"] = comps
	screen.refresh()
