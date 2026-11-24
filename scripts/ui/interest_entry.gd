class_name InterestEntry
extends RefCounted

## The team-name surfaces outside the league sheets: the match HUD's two team
## labels and the fixture picker's two cards. A long press on either raises the
## shared interest menu; with no league season open nothing happens, because
## interest belongs to a save.

static func hud_club(game) -> String:
	if LeagueSeason.active == null or game.hud == null or game.engine == null:
		return ""
	var id := str(game.view.button_at(game.mouse))
	if id == "team_0":
		return str(game.engine.teams[0]["id"])
	if id == "team_1":
		return str(game.engine.teams[1]["id"])
	return ""

static func picker_club(selector) -> String:
	if LeagueSeason.active == null or selector == null:
		return ""
	var id := str(selector.button_at(selector.mouse))
	if id == "team_home":
		return selector.home_id()
	if id == "team_away":
		return selector.away_id()
	return ""

## Anchor the menu at the pointer in design space. Returns false when there is
## no club to mark (the caller then falls through to its normal click).
static func show(game, club_id: String) -> bool:
	if club_id == "" or game.interest == null or LeagueSeason.active == null:
		return false
	var club := PLRepository.shared().club(club_id)
	game.interest.show_at(club_id, str(club.get("name", club_id)), game.view.design(game.mouse))
	return true
