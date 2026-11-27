class_name InterestHold
extends RefCounted


var press := InterestPress.new()
var menu := InterestMenu.new()

var vp := Vector2(1600, 900)

var club_at := Callable()

var season_of := Callable()

var on_changed := Callable()


var _menu_press := false


var _own_release := false


func press_at(point: Vector2) -> bool:
	if menu.is_open():
		_menu_press = true
		press.clear()
		return true
	press.press(point, _club(point))
	return press.watching


func move(point: Vector2) -> void:
	press.move(point)


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


func tick(delta: float) -> bool:
	if not press.tick(delta):
		return false
	if not open(press.club, press.at):
		press.clear()
		return false
	_own_release = true
	return true


func open(club: String, point: Vector2) -> bool:
	var season = _season()
	if season == null or club == "" or season.record == null:
		return false
	var looked: Dictionary = PLRepository.shared().club(club)
	menu.show(club, str(looked.get("name", club)), str(looked.get("abbr", club)),
		season.record.interest.is_interested(club), point)
	return true


func click(id: String) -> bool:
	if not menu.is_open():
		return false
	_toggle(id)
	return true


func close() -> void:
	menu.close()
	_menu_press = false
	_own_release = false
	press.clear()

func is_open() -> bool:
	return menu.is_open()


func clear() -> void:
	press.clear()

func _menu_click(point: Vector2) -> void:
	_toggle(menu.hit(point, vp))


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
