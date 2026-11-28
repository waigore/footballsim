class_name WikiModel
extends RefCounted


const LEAGUE := "league"
const TEAM := "team"
const PLAYER := "player"
const MANAGER := "manager"
const CUP := "cup"


static func repo() -> PLRepository:
	return PLRepository.shared()


static func has_page(page: String, id: String) -> bool:
	if page == CUP:
		return id != "" and LeagueCup.is_cup(id)
	if page == LEAGUE:
		return id == "" or PLCompetitions.exists(id)
	if page == TEAM or page == MANAGER:
		return not repo().club(id).is_empty()
	if page == PLAYER:
		return not repo().player(id).is_empty()
	return false


static func page(page: String, id: String, mode: String = "SIMPLIFIED") -> Dictionary:
	if page == CUP:
		return WikiCup.page(id)
	if page == TEAM:
		return team_page(id, mode)
	if page == PLAYER:
		return player_page(id, mode)
	if page == MANAGER:
		return WikiManager.page(id)
	return league_page(id)


static func label(page: String, id: String) -> String:
	if page == TEAM:
		return str(repo().club(id).get("abbr", id))
	if page == PLAYER:
		return str(repo().player(id).get("name", id))
	if page == MANAGER:
		return str(ManagerData.profile(id).get("name", id))
	if page == CUP:
		return str(repo().competition(id).get("short_name", id)).to_upper()
	var comp := PLCompetitions.one(id if id != "" else PLCompetitions.default_id())
	return str(comp.get("short_name", "LEAGUE")).to_upper()


static func league_page(competition_id: String = "") -> Dictionary:
	return WikiLeague.page(competition_id)


static func team_page(club_id: String, mode: String = "SIMPLIFIED") -> Dictionary:
	return WikiTeam.page(club_id, mode)


static func player_page(player_id: String, mode: String = "SIMPLIFIED") -> Dictionary:
	return WikiPlayer.page(player_id, mode)


static func hex(col: Variant) -> String:
	var c: Color = col if col is Color else Color.WHITE
	return c.to_html(false)
