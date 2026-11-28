class_name LeaguePanelDoors
extends RefCounted


static func nav(screen, pose: String) -> void:
	screen.panel.close()
	if pose == "system":
		LeagueSystemActions.open(screen)
		return
	if pose == "interest":
		screen.interest_query = ""
		LeagueDoors.go(screen, LeagueScreen.MODE_INTEREST)
	elif pose == "fixtures":
		LeagueDoors.go(screen, LeagueScreen.MODE_HUB)
	elif pose == "europe":
		LeagueEuropeActions.open(screen)
		return
	elif pose == "table":
		LeagueDoors.go(screen, LeagueScreen.MODE_TABLE)
		attach_table(screen)
	elif pose == "calendar":
		LeagueDoors.go(screen, LeagueScreen.MODE_CALENDAR)
		LeagueCalendar.open(screen)
		return
	elif pose == "stats":
		LeagueDoors.go(screen, LeagueScreen.MODE_STATS)
	screen.refresh()


static func stats(screen, id: String) -> void:
	if id == "stats:reports":
		LeagueDoors.go(screen, LeagueScreen.MODE_STATS)
	elif id == "stats:podium":
		LeagueDoors.go(screen, LeagueScreen.MODE_PODIUM)
	screen.refresh()


static func attach_table(screen) -> void:
	screen.book.table.attach(screen.season.save if screen.season != null else null)
