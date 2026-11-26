class_name LeagueWizardActions
extends RefCounted

## The New League wizard's one stateful rule: toggle a league on or off, with at
## least one always on. Split out of `LeagueDoors` so the press table stays
## inside its line budget; it reads and writes the screen's own `wizard` field.

static func toggle_league(screen, competition_id: String) -> void:
	if competition_id == "":
		return
	var comps: Array = screen.wizard.get("competitions", ["PL"]).duplicate()
	if comps.has(competition_id):
		if comps.size() <= 1:
			return
		comps.erase(competition_id)
	else:
		comps.append(competition_id)
	screen.wizard["competitions"] = comps
	screen.refresh()
