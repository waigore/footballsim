class_name LeaguePanelDoors
extends RefCounted

## The left panel's destinations and the two stats doors: the pose each one
## opens, and the table reading the season's save is bound to.
##
## Split out of `LeagueDoors` (the dispatch table is at its size budget) and
## written like `LeagueCalendar`: static helpers that work on the screen's own
## fields. It owns jump-to-pose only. A door that reaches into the season lives
## in `LeagueSeasonDoors`, a report's clip in `LeagueGoalDoors`, the System
## dialog in `LeagueSystemActions`, so the table keeps routing and nothing else.

## The panel's destinations, and the pose each one opens. The panel is closed on
## the way so the sheet it opens is never covered by its own menu. Each jump is
## one page of the season's history, so BACK undoes it like any other door.
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

## The Stats sheet's own doors: the matchday reports it lists, and the podium
## once the season is complete.
static func stats(screen, id: String) -> void:
	if id == "stats:reports":
		LeagueDoors.go(screen, LeagueScreen.MODE_STATS)
	elif id == "stats:podium":
		LeagueDoors.go(screen, LeagueScreen.MODE_PODIUM)
	screen.refresh()

## The table is the save's: its sort and reading are written through to the same
## save the sheet draws from, and nothing is attached when there is no season.
static func attach_table(screen) -> void:
	screen.book.table.attach(screen.season.save if screen.season != null else null)
