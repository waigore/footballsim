class_name LeagueSystemActions
extends RefCounted

## The System sheet's behaviour (#109): Quick Save, Save As, Load, Main Menu and
## Quit, plus the unload that keeps a swapped-in save clean.
##
## Split out of the modal screen (the screen is at its size budget) and written
## like `LeagueCalendar`: static helpers that work on the screen's own fields, so
## the screen and its tests keep reading the same state they always did.

## Open the dialog on a season. A season that is gone has nothing to save, so the
## door falls through to leaving the sheet. In a season the dialog is a page of
## its own: the sheet it covers is left behind it, so BACK returns there (#169).
static func open(screen) -> void:
	if screen.season == null:
		screen.close()
		return
	reset(screen)
	if screen.mode != LeagueScreen.MODE_SYSTEM:
		screen.push_page()
	screen.mode = LeagueScreen.MODE_SYSTEM
	screen.refresh()

static func reset(screen) -> void:
	screen.sys = {"status": "", "error": "", "naming": false, "name": ""}

## What the System sheet paints: the last acknowledgement, a refusal, and the
## Save As field while it is open.
static func view(screen) -> Dictionary:
	var state: Dictionary = screen.season.state() if screen.season != null else {}
	return {
		"status": str(screen.sys["status"]), "error": str(screen.sys["error"]),
		"naming": bool(screen.sys["naming"]), "save_name": str(screen.sys["name"]),
		"name": str(state.get("name", "")), "date": str(state.get("date", "")),
	}

static func act(screen, id: String) -> void:
	match id:
		"sys:quick":
			quick_save(screen)
		"sys:save":
			if bool(screen.sys["naming"]):
				save_as(screen)
			else:
				screen.sys["naming"] = true
				screen.sys["name"] = default_name(screen)
				screen.sys["status"] = ""
				screen.sys["error"] = ""
				screen.refresh()
		"sys:commit":
			save_as(screen)
		"sys:cancel":
			screen.sys["naming"] = false
			screen.refresh()
		"sys:load":
			screen.load_from = "system"
			screen.push_page()
			screen.mode = LeagueScreen.MODE_LOAD
			screen.saves = LeagueSave.list()
			screen.refresh()
		"sys:menu":
			leave(screen)
		"sys:quit":
			screen.quit_requested.emit()
		_:
			refuse(screen, "Unknown action.")

## Keyboard for the Save As field, mirroring the setup wizard's name entry.
static func type_name(screen, code: int) -> bool:
	if not bool(screen.sys["naming"]):
		return false
	if code == KEY_ENTER or code == KEY_KP_ENTER:
		save_as(screen)
		return true
	var typed: Array = LeagueSheet.type_name(str(screen.sys["name"]), code)
	if bool(typed[0]):
		screen.sys["name"] = str(typed[1])
		screen.refresh()
	return bool(typed[0])

static func default_name(screen) -> String:
	var save = screen.season.save if screen.season != null else null
	var base := str(save.name()) if save != null else ""
	return "%s copy" % base if base != "" else "League copy"

## Quick Save: play writes to the save as it goes, so the action stamps the file
## and proves it is still writable. The ack is painted, never modal.
static func quick_save(screen) -> void:
	var save = screen.season.save if screen.season != null else null
	if save == null:
		refuse(screen, "No season is open.")
		return
	if not save.touch():
		refuse(screen, "That save could not be written.")
		return
	screen.sys["error"] = ""
	screen.sys["status"] = "SAVED %s" % Time.get_time_string_from_system(false)
	screen.refresh()

## Save As: write a copy of the save under the typed name. Play carries on with
## the season's own file, so the copy is a named restore point.
static func save_as(screen) -> void:
	var save = screen.season.save if screen.season != null else null
	if save == null:
		refuse(screen, "No season is open.")
		return
	var typed := str(screen.sys["name"]).strip_edges()
	if typed == "":
		refuse(screen, "Give the copy a name.")
		return
	if save.write_copy(typed) == "":
		refuse(screen, "That name could not be written.")
		return
	screen.sys["naming"] = false
	screen.sys["error"] = ""
	screen.sys["status"] = "SAVED AS %s" % typed.to_upper()
	screen.refresh()

static func refuse(screen, reason: String) -> void:
	screen.sys["status"] = ""
	screen.sys["error"] = reason
	screen.refresh()

## Main Menu: close the sheet back to the menu. The season stays loaded as the
## menu's resume point, exactly as the hub's old MENU door left it — only Load
## swaps a save out of memory.
static func leave(screen) -> void:
	screen.close()

## Drop everything the season on screen owns. Nothing that outlives this call may
## still read the save: the next season rebuilds from whichever file is bound.
static func unload(screen) -> void:
	screen.book.table.attach(null)
	screen.nav.clear()
	screen.report = {}
	screen.roundup = []
	screen.day = ""
	screen.day_fixtures = []
	screen.days_cache = {}
	screen.month = str(Time.get_date_dict_from_system()["year"]) + "-" \
		+ "%02d" % int(Time.get_date_dict_from_system()["month"])
	reset(screen)
	if screen.season != null:
		screen.season.close()
		screen.season = null
