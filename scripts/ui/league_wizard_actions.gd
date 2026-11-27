class_name LeagueWizardActions
extends RefCounted

## The New League wizard's one stateful rule: toggle a league on or off (#261).
##
## The choices cascade along the linked-tier graph, because a lower tier only
## means something with the tiers above it playing:
##
## - turning a league on selects every league above it in its own country
##   (League Two on brings the Premier League, the Championship and League One
##   with it; 2. Bundesliga on brings the Bundesliga);
## - turning a league off clears that league and every league below it (turning
##   the Championship off drops the whole English pyramid under it, while the
##   Premier League can stay on alone);
## - at least one competition always stays selected across the whole wizard.

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
