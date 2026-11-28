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
var strip := WikiPageStrip.new()
var input: WikiScreenInput = null

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
	input = WikiScreenInput.new(self)


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
	strip.clear()
	closed.emit()

func current() -> Dictionary:
	return nav.current()

func is_open() -> bool:
	return nav.is_open()


func crumb_pages() -> Array:
	return nav.crumb_pages()

func _refresh() -> void:
	var top := current()
	var page := str(top.get("page", WikiModel.LEAGUE))
	var mode := ""
	if page == WikiModel.PLAYER or page == WikiModel.TEAM:
		mode = Prefs.load_attrs()
	page_data = WikiModel.page(page, str(top.get("id", "")), mode if mode != "" else "SIMPLIFIED")
	_strip_sync()
	if body != null:
		var box := body_rect(design_vp())
		body.touch = touch
		body.position = box.position
		body.size = box.size
		body.set_page(page_data, is_compact())
		body.followed = WikiInterest.followed_set(LeagueSeason.active)
	queue_redraw()


func set_attr_view(mode: String) -> bool:
	var page := str(current().get("page", ""))
	if page != WikiModel.PLAYER and page != WikiModel.TEAM:
		return false
	Prefs.save_attrs(mode)
	_refresh()
	return true


func set_currency(code: String) -> bool:
	if not MarketCurrency.currencies().has(code):
		return false
	Prefs.save_currency(code)
	_refresh()
	return true


func _strip_sync() -> void:
	var width: float = float(WikiHeader.metrics(design_vp(), is_compact(), touch, false)["width"])
	strip.rebuild(page_data, f_bold, width)


func click(id: String) -> void:
	if input != null:
		input.click(id)


func tap(p: Vector2) -> bool:
	return input.tap(p) if input != null else false


func scroll_by(delta: float, dx: float = 0.0) -> void:
	if input != null:
		input.scroll_by(delta, dx)


func key(code: int) -> bool:
	return input.key(code) if input != null else false


func button_at(p: Vector2) -> String:
	return input.button_at(p) if input != null else ""


func design_vp() -> Vector2:
	return get_viewport().get_visible_rect().size / maxf(ui_scale, 0.001)

func is_compact() -> bool:
	return HudLayout.is_compact(design_vp())


func body_rect(vp: Vector2) -> Rect2:
	return WikiHeader.body_rect(vp, is_compact(), touch, not strip.chips.is_empty())


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
		var width: float = float(WikiHeader.metrics(design_vp(), is_compact(), touch, false)["width"])
		if strip.stale(page_data, width):
			_strip_sync()
	queue_redraw()
