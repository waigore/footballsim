class_name WikiScreen
extends Control


signal closed()


signal interest_toggled(club_id: String)

var ui_scale := 1.0
var touch := false
var mouse := Vector2(-1000, -1000)


var holding := false
var buttons: Array = []
var body: WikiBody = null


var hints := DateHints.new()
var rows_hints: DateHints = null
var tooltip: DateOverlay = null


var names := InterestNames.new()

var interest := InterestHold.new()

var menu_layer: InterestLayer = null

var nav := WikiNav.new()
var page_data: Dictionary = {}

var f_bold: FontFile
var f_med: FontFile
var f_body: FontFile

var stack: Array:
	get:
		return nav.entries
	set(value):
		nav.entries = value

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	f_bold = load("res://fonts/BarlowCondensed-SemiBold.ttf")
	f_med = load("res://fonts/BarlowCondensed-Medium.ttf")
	f_body = load("res://fonts/Inter-Regular.ttf")
	body = WikiBody.new()
	body.name = "Body"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(body)
	rows_hints = body.hints
	tooltip = DateOverlay.attach(self, body, true)


	interest.club_at = func(p: Vector2) -> String:
		var own := names.at(p)
		if own != "":
			return own
		return body.club_at(p) if body != null else ""
	interest.season_of = func(): return LeagueSeason.active
	interest.on_changed = func():
		body.followed = WikiInterest.followed_set(LeagueSeason.active)
		body.queue_redraw()
		queue_redraw()
	menu_layer = InterestLayer.new()
	menu_layer.hold = interest
	menu_layer.screen = self
	add_child(menu_layer)


func open(page: String = WikiModel.LEAGUE, id: String = "") -> void:
	nav.open(page, id)
	_refresh()

func push(page: String, id: String) -> void:
	if nav.push(page, id):
		_refresh()

func back() -> void:
	if nav.back():
		_refresh()
		return
	close()

func close() -> void:
	nav.close()
	page_data = {}
	closed.emit()

func current() -> Dictionary:
	return nav.current()

func is_open() -> bool:
	return nav.is_open()


func crumb_pages() -> Array:
	return nav.crumb_pages()

func _refresh() -> void:
	var top := current()
	page_data = WikiModel.page(str(top.get("page", WikiModel.LEAGUE)), str(top.get("id", "")))
	if body != null:
		var box := body_rect(design_vp())
		body.touch = touch
		body.position = box.position
		body.size = box.size
		body.set_page(page_data, is_compact())
		body.followed = WikiInterest.followed_set(LeagueSeason.active)
	queue_redraw()


func click(id: String) -> void:
	if interest.click(id):
		return
	if id == "back":
		back()
	elif id == "close":
		close()
	elif id.begins_with("crumb:"):
		nav.truncate_to(int(id.substr(6)))
		_refresh()
	elif id.begins_with("interest:"):
		interest_toggled.emit(id.substr(9))


func tap(p: Vector2) -> bool:
	if body == null:
		return false
	var target: Dictionary = body.hit(p)
	if target.is_empty():
		return false
	push(str(target.get("page", "")), str(target.get("id", "")))
	return true


func scroll_by(delta: float, _dx: float = 0.0) -> void:
	if body != null:
		body.scroll_by(delta)


func key(code: int) -> bool:
	if interest.is_open() and (code == KEY_ESCAPE or code == KEY_BACKSPACE):
		interest.close()
		queue_redraw()
		return true
	if code == KEY_ESCAPE or code == KEY_BACKSPACE or code == KEY_LEFT:
		back()
	elif code == KEY_UP or code == KEY_W:
		scroll_by(-120.0)
	elif code == KEY_DOWN or code == KEY_S:
		scroll_by(120.0)
	elif code == KEY_PAGEUP:
		scroll_page(-1.0)
	elif code == KEY_PAGEDOWN:
		scroll_page(1.0)
	elif code == KEY_HOME:
		scroll_to(0.0)
	elif code == KEY_END:
		scroll_to(INF)
	else:
		return false
	return true

func scroll_page(direction: float) -> void:
	if body != null:
		body.scroll_by(direction * body.size.y * 0.9)

func scroll_to(at: float) -> void:
	if body != null:
		body.scroll_to(at)

func button_at(p: Vector2) -> String:
	for b in buttons:
		if (b["rect"] as Rect2).has_point(p):
			return str(b["id"])
	return ""


func design_vp() -> Vector2:
	return get_viewport().get_visible_rect().size / maxf(ui_scale, 0.001)

func is_compact() -> bool:
	return HudLayout.is_compact(design_vp())


func body_rect(vp: Vector2) -> Rect2:
	return WikiHeader.body_rect(vp, is_compact())


func _draw() -> void:
	WikiHeader.paint(self)

func _add(id: String, r: Rect2) -> void:
	buttons.append({"id": id, "rect": r})

func _process(d: float) -> void:
	if interest.tick(d):
		queue_redraw()
	if body != null:
		var box := body_rect(design_vp())
		body.mouse = mouse
		body.position = box.position
		body.size = box.size
	queue_redraw()
