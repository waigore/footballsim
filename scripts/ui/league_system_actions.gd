class_name LeagueSystemActions
extends RefCounted


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


static func view(screen) -> Dictionary:
	var state: Dictionary = screen.season.state() if screen.season != null else {}
	return {
		"status": str(screen.sys["status"]), "error": str(screen.sys["error"]),
		"naming": bool(screen.sys["naming"]), "save_name": str(screen.sys["name"]),
		"name": str(state.get("name", "")), "date": str(state.get("date", "")),
		"advance_mode": str(state.get("advance_mode", "fixture_days")),

		"focus": str(screen.focus.kind),


		"touch": bool(screen.touch),
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


				LeagueFieldFocus.press(screen, LeagueFieldFocus.SYSTEM)
		"sys:commit":
			save_as(screen)
		"sys:cancel":
			screen.sys["naming"] = false
			screen.refresh()
		"sys:load":
			screen.load_from = "system"
			screen.push_page()
			screen.mode = LeagueScreen.MODE_LOAD
			screen.saves = LeagueSaveCatalog.list()
			screen.refresh()
		"sys:advance":
			toggle_advance(screen)
		"sys:menu":
			leave(screen)
		"sys:quit":
			screen.quit_requested.emit()
		_:
			refuse(screen, "Unknown action.")


static func type_name(screen, code: int, ch: String = "") -> bool:
	if not bool(screen.sys["naming"]):
		return false
	if code == KEY_ENTER or code == KEY_KP_ENTER:
		save_as(screen)
		return true
	var typed: Array = LeagueTextField.type_char(str(screen.sys["name"]), ch) if ch != "" \
		else LeagueTextField.type_name(str(screen.sys["name"]), code)
	if bool(typed[0]):
		screen.sys["name"] = str(typed[1])
		screen.refresh()
	return bool(typed[0])

static func default_name(screen) -> String:
	var save = screen.season.save if screen.season != null else null
	var base := str(save.name()) if save != null else ""
	return "%s copy" % base if base != "" else "League copy"


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


static func toggle_advance(screen) -> void:
	if screen.season == null:
		refuse(screen, "No season is open.")
		return
	var next := "every_day" if screen.season.save.advance_mode() == "fixture_days" else "fixture_days"
	if not screen.season.set_advance_mode(next):
		refuse(screen, "That change could not be saved.")
		return
	screen.sys["error"] = ""
	screen.sys["status"] = "ADVANCE: %s" % ("EVERY DAY" if next == "every_day" else "FIXTURE DAYS")
	screen.refresh()

static func refuse(screen, reason: String) -> void:
	screen.sys["status"] = ""
	screen.sys["error"] = reason
	screen.refresh()


static func leave(screen) -> void:
	screen.close()


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
