class_name LeagueActions
extends RefCounted

## Every press and key the league surface can receive, kept out of
## `LeagueScreen` so the screen stays inside its P3 size and method ratchets.
## The screen owns state; this module only changes it in response to a door.

var screen = null

func _init(owner) -> void:
	screen = owner

# ------------------------------------------------------------------- press ---

func click(id: String) -> void:
	if id == "":
		return
	if id.begins_with("match:"):
		screen.show_report(id.substr(6))
	elif id.begins_with("goal:"):
		screen.play_goal(int(id.substr(5)))
	elif id.begins_with("club:"):
		screen.club_requested.emit(id.substr(5))
	elif id == "back":
		back()
	elif id == "panel":
		screen.panel.open()
		screen.queue_redraw()
	elif id == "panel:close":
		screen.panel.close()
		screen.queue_redraw()
	elif id.begins_with("nav:"):
		nav(id.substr(4))
	elif id.begins_with("sys:"):
		LeagueSystemActions.act(screen, id)
	elif id == "system":
		LeagueSystemActions.open(screen)
	elif id.begins_with("interest:"):
		interest(id)
	elif id.begins_with("stats:"):
		stats(id)
	elif id.begins_with("statsday:"):
		open_day(id.substr(9))
	elif id.begins_with("toggle:"):
		toggle(id.substr(7))
	elif id.begins_with("fixture:"):
		press_fixture(id.substr(8))
	elif id.begins_with("open:"):
		open_save(id.substr(5))
	elif id.begins_with("delete:"):
		delete_save(id.substr(7))
	elif id.begins_with("mode:"):
		screen.wizard["calendar_mode"] = id.substr(5)
		screen.refresh()
	elif id.begins_with("adv:"):
		screen.wizard["advance_mode"] = id.substr(4)
		screen.refresh()
	elif id.begins_with("day:"):
		LeagueCalendar.pick(screen, id.substr(4))
	elif id.begins_with("month:"):
		LeagueCalendar.shift(screen, int(id.substr(6)))
	elif id.begins_with("tbl:"):
		if screen.season != null and screen.book.table.press(id, screen.season.save):
			screen.refresh()
	elif id == "continue":
		continue_season()
	elif id == "suggest":
		if screen.season != null:
			screen.season.suggest()
		screen.refresh()
	elif id == "table":
		open_table()
	elif id == "calendar":
		screen.mode = LeagueScreen.MODE_CALENDAR
		LeagueCalendar.open(screen)
	elif id == "podium":
		screen.mode = LeagueScreen.MODE_PODIUM
		screen.refresh()
	elif id == "create":
		create()
	elif id == "name":
		screen.refresh()

## The left panel's destinations, and the pose each one opens.
func nav(pose: String) -> void:
	screen.panel.close()
	if pose == "fixtures":
		screen.mode = LeagueScreen.MODE_HUB
	elif pose == "table":
		open_table()
	elif pose == "calendar":
		screen.mode = LeagueScreen.MODE_CALENDAR
		LeagueCalendar.open(screen)
	elif pose == "interest":
		screen.interest_query = ""
		screen.mode = LeagueScreen.MODE_INTEREST
	elif pose == "stats":
		screen.mode = LeagueScreen.MODE_STATS
	elif pose == "system":
		LeagueSystemActions.open(screen)
		return
	screen.refresh()

func back() -> void:
	if screen.panel.is_open():
		screen.panel.close()
		screen.queue_redraw()
		return
	if screen.menu.open:
		screen.menu.hide()
		screen.queue_redraw()
		return
	if LeagueSystemActions.back(screen):
		return
	var mode := str(screen.mode)
	if mode == LeagueScreen.MODE_HUB or mode == LeagueScreen.MODE_WIZARD:
		screen.close()
	elif mode == LeagueScreen.MODE_LOAD:
		if str(screen.load_from) == "system":
			screen.load_from = "menu"
			screen.mode = LeagueScreen.MODE_SYSTEM
			screen.refresh()
			return
		screen.close()
	else:
		screen.mode = str(screen.report_back) if mode == LeagueScreen.MODE_REPORT else LeagueScreen.MODE_HUB
		screen.report_back = LeagueScreen.MODE_HUB
		screen.refresh()

# ------------------------------------------------------------------- keys ---

func key(code: int) -> bool:
	if screen.mode == LeagueScreen.MODE_WIZARD and LeagueSheet.type_name_into(screen.wizard, code):
		screen.refresh()
		return true
	if screen.mode == LeagueScreen.MODE_SYSTEM and LeagueSystemActions.type_name(screen, code):
		return true
	if screen.mode == LeagueScreen.MODE_INTEREST and type_query(code):
		return true
	if screen.mode == LeagueScreen.MODE_REPORT and code >= KEY_1 and code <= KEY_9:
		var want := code - KEY_1
		if screen.has_clip(want):
			screen.play_goal(want)
			return true
	if code == KEY_ESCAPE or code == KEY_BACKSPACE:
		back()
		return true
	if screen.mode == LeagueScreen.MODE_HUB and (code == KEY_ENTER or code == KEY_KP_ENTER):
		continue_season()
		return true
	if code == KEY_UP or code == KEY_W:
		screen.scroll_by(-120.0)
	elif code == KEY_DOWN or code == KEY_S:
		screen.scroll_by(120.0)
	elif code == KEY_PAGEUP:
		screen.scroll_by(-screen.body.size.y * 0.9)
	elif code == KEY_PAGEDOWN:
		screen.scroll_by(screen.body.size.y * 0.9)
	elif code == KEY_HOME:
		screen.scroll_by(-1.0e7)
	elif code == KEY_END:
		screen.scroll_by(1.0e7)
	else:
		return false
	return true

func type_query(code: int) -> bool:
	var typed: Array = type_into(str(screen.interest_query), code, 20)
	if bool(typed[0]):
		screen.interest_query = str(typed[1]).to_lower()
		screen.refresh()
	return bool(typed[0])

## A printable key either edits the field or stays for the sheet. Returns
## `[handled, text]`, the same shape the wizard's name field uses.
static func type_into(current: String, code: int, limit: int) -> Array:
	if code == KEY_BACKSPACE:
		return [true, current.substr(0, maxi(current.length() - 1, 0))]
	if current.length() >= limit:
		return [false, current]
	var printable: bool = (code >= KEY_A and code <= KEY_Z) or (code >= KEY_0 and code <= KEY_9)
	if printable or code == KEY_SPACE:
		return [true, current + char(code)]
	return [false, current]

# ------------------------------------------------------------------ season ---

func open_table() -> void:
	screen.mode = LeagueScreen.MODE_TABLE
	screen.book.table.attach(screen.season.save if screen.season != null else null)
	screen.refresh()

func continue_season() -> void:
	if screen.season == null or screen.season.finishing:
		screen.refresh()
		return
	var result: Dictionary = screen.season.advance()
	var played: Array = result.get("played", [])
	if bool(result.get("complete", false)):
		screen.mode = LeagueScreen.MODE_PODIUM
		screen.month = LeagueBook.state_month(screen.season, screen.month)
		screen.refresh()
		return
	# A watch the player left early is finished by Continue, not skipped (#100).
	var pending: Array = result.get("pending", [])
	if not pending.is_empty():
		var watch: Dictionary = screen.season.start_watch(str(pending[0]["id"]))
		if not watch.is_empty():
			screen.match_requested.emit(str(watch["home"]), str(watch["away"]), str(watch["fixture_id"]))
			return
	if not played.is_empty():
		screen.show_roundup(played)
		return
	screen.month = LeagueBook.state_month(screen.season, screen.month)
	screen.refresh()

func toggle(fixture_id: String) -> void:
	if screen.season == null:
		return
	var fx: Dictionary = screen.season.record.fixture(fixture_id)
	if fx.is_empty() or str(fx["status"]) == "played":
		return
	screen.season.set_watch(fixture_id, not bool(screen.season.plan_watch(fixture_id)))
	screen.refresh()

func press_fixture(fixture_id: String) -> void:
	if screen.season == null:
		return
	var fx: Dictionary = screen.season.record.fixture(fixture_id)
	if fx.is_empty():
		return
	if str(fx["status"]) == "played":
		screen.show_report(fixture_id)
	elif screen.season.plan_watch(fixture_id):
		var watch: Dictionary = screen.season.start_watch(fixture_id)
		if not watch.is_empty():
			screen.match_requested.emit(str(watch["home"]), str(watch["away"]), str(watch["fixture_id"]))
	else:
		toggle(fixture_id)

func create() -> void:
	var created := LeagueSeason.create(str(screen.wizard["name"]), str(screen.wizard["calendar_mode"]),
		str(screen.wizard["advance_mode"]), 0)
	if created == null:
		screen.wizard["error"] = "The season could not be created."
		screen.refresh()
		return
	screen.season = created
	screen.season_opened.emit(created)
	screen.mode = LeagueScreen.MODE_HUB
	screen.month = LeagueBook.state_month(screen.season, screen.month)
	screen.refresh()

func open_save(slug: String) -> void:
	if screen.season != null:
		# A season is already in memory: the host tears it down completely
		# before the chosen save opens.
		screen.open_save_now(slug)
		return
	screen.open_save_now(slug)

func delete_save(slug: String) -> void:
	if screen.season != null and screen.season.save.slug == slug:
		LeagueSystemActions.unload(screen)
	screen.menu.hide()
	screen.panel.close()
	LeagueSave.remove(slug)
	screen.saves = LeagueSave.list()
	screen.mode = LeagueScreen.MODE_LOAD
	screen.refresh()

# ------------------------------------------------------------------ extras ---

func open_day(date: String) -> void:
	if screen.season == null:
		return
	screen.roundup = screen.season.report_day(date)
	screen.report = {}
	screen.report_back = LeagueScreen.MODE_STATS
	screen.mode = LeagueScreen.MODE_REPORT
	screen.refresh()

func stats(id: String) -> void:
	if id == "stats:reports":
		screen.mode = LeagueScreen.MODE_STATS
	elif id == "stats:podium":
		screen.mode = LeagueScreen.MODE_PODIUM
	screen.refresh()

# --------------------------------------------------------------- interest ---

func interest(id: String) -> void:
	if id.begins_with("interest:add:"):
		add_interest(id.substr(13))
	elif id.begins_with("interest:remove:"):
		add_interest(id.substr(16), true)
	elif id == "interest:close":
		screen.menu.hide()
		screen.queue_redraw()
	elif id == "interest:toggle":
		toggle_interest_menu()

func add_interest(club_id: String, remove: bool = false) -> void:
	if screen.season == null or club_id == "":
		return
	var wanted: bool = not remove and not bool(screen.season.interest.has(club_id))
	screen.season.interest.set_interest(club_id, wanted)
	screen.season.dirty = true
	if wanted:
		screen.interest_query = ""
	screen.refresh()

func toggle_interest_menu() -> void:
	if screen.season == null or screen.menu.club_id == "":
		screen.menu.hide()
		screen.queue_redraw()
		return
	var club := str(screen.menu.club_id)
	screen.season.interest.set_interest(club, not screen.season.interest.has(club))
	screen.season.dirty = true
	screen.menu.hide()
	screen.refresh()
