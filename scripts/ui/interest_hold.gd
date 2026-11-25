class_name InterestHold
extends RefCounted

## The shared long-press handler (#107): it watches one surface's press grammar,
## resolves the club name under the finger, raises `InterestMenu`, and writes the
## shortlist when the menu's door is pressed.
##
## Each surface hosts one and wires three callables — how to name the club under
## a point, which season owns the shortlist, and how to repaint — so the league
## sheets, the encyclopedia, the picker and the match HUD all behave the same and
## the write happens in one place. With no season open there is nothing to
## follow: the press stays an ordinary press and no menu appears.
##
## The whole gesture lives here so a caller only forwards three moments: a press
## went down, the pointer travelled, the press came up. `press_at` and
## `release_at` say whether the handler owns the gesture, which is how the
## surface keeps its ordinary click on a short tap and never fires one under a
## long press or under the menu.

var press := InterestPress.new()
var menu := InterestMenu.new()
## Design viewport of the surface: where the menu may sit and be pressed.
var vp := Vector2(1600, 900)
## (point: Vector2) -> the club id printed under it, or "".
var club_at := Callable()
## () -> the LeagueSeason whose shortlist the menu edits, or null.
var season_of := Callable()
## () -> void: repaint the surface after the shortlist moved.
var on_changed := Callable()

## This press landed on the open menu.
var _menu_press := false
## The menu is opening under the finger that raised it: the release of that same
## press must not dismiss what the press just opened.
var _own_release := false

## A press went down. True when this handler owns the gesture: a club name was
## under the point, or the menu is up. The surface holds its click back until
## the release says what the press was.
func press_at(point: Vector2) -> bool:
	if menu.is_open():
		_menu_press = true
		press.clear()
		return true
	press.press(point, _club(point))
	return press.watching

## The pointer travelled while pressed.
func move(point: Vector2) -> void:
	press.move(point)

## The press came up. True when the handler consumed it, so the surface runs no
## click of its own.
func release_at(point: Vector2) -> bool:
	if _menu_press:
		_menu_press = false
		_menu_click(point)
		return true
	if _own_release:
		_own_release = false
		press.clear()
		return true
	return not press.release_click()

## Advance the hold clock. True the frame the menu opens, so the host repaints.
func tick(delta: float) -> bool:
	if not press.tick(delta):
		return false
	if not open(press.club, press.at):
		press.clear()
		return false
	_own_release = true
	return true

## Raise the menu for one club. False when there is no season (no shortlist to
## edit) or the point named no club.
func open(club: String, point: Vector2) -> bool:
	var season = _season()
	if season == null or club == "" or season.record == null:
		return false
	var looked: Dictionary = PLRepository.shared().club(club)
	menu.show(club, str(looked.get("name", club)), str(looked.get("abbr", club)),
		season.record.interest.is_interested(club), point)
	return true

## A press named by its door id: the league sheet's own press table forwards here
## first, so a direct `click("interest:toggle")` (a suite, a probe) works too.
func click(id: String) -> bool:
	if not menu.is_open():
		return false
	_toggle(id)
	return true

## Close a menu a pose change (or BACK) leaves behind, without a write.
func close() -> void:
	menu.close()
	_menu_press = false
	_own_release = false
	press.clear()

func is_open() -> bool:
	return menu.is_open()

## Forget a press that belonged to the sheet that was on screen when it started.
func clear() -> void:
	press.clear()

func _menu_click(point: Vector2) -> void:
	_toggle(menu.hit(point, vp))

## The door follows or releases the club; every other press just dismisses.
func _toggle(id: String) -> void:
	if id == InterestMenu.TOGGLE:
		var season = _season()
		if season != null:
			season.set_interest(menu.club_id, not menu.followed)
	menu.close()
	if on_changed.is_valid():
		on_changed.call()

func _club(point: Vector2) -> String:
	if _season() == null or not club_at.is_valid():
		return ""
	return str(club_at.call(point))

func _season():
	if not season_of.is_valid():
		return null
	return season_of.call()
