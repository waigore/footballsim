extends Control

## Football Manager-style encyclopedia sheet: league, club and player pages with
## a cross-link stack. It is a modal surface over the broadcast — the match is
## paused while it is open, and closing restores the viewer exactly as it was.
## Chrome follows team_select: same palette, same type, same tap targets.

signal closed()

var ui_scale := 1.0
var touch := false
var mouse := Vector2(-1000, -1000)
var buttons: Array = []
var body: WikiBody = null

var stack: Array = []
var page_data: Dictionary = {}

var f_bold: FontFile
var f_med: FontFile
var f_body: FontFile

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	f_bold = load("res://fonts/BarlowCondensed-SemiBold.ttf")
	f_med = load("res://fonts/BarlowCondensed-Medium.ttf")
	f_body = load("res://fonts/Inter-Regular.ttf")
	body = WikiBody.new()
	body.name = "Body"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(body)

# -------------------------------------------------------------------- pages --

func open(page: String = WikiModel.LEAGUE, id: String = "") -> void:
	if not WikiModel.has_page(page, id):
		page = WikiModel.LEAGUE
		id = ""
	stack = [{"page": page, "id": id}]
	_refresh()

func push(page: String, id: String) -> void:
	if not WikiModel.has_page(page, id):
		return
	if not stack.is_empty():
		var top: Dictionary = stack.back()
		if str(top["page"]) == page and str(top["id"]) == id:
			return
	stack.append({"page": page, "id": id})
	_refresh()

func back() -> void:
	if stack.size() > 1:
		stack.pop_back()
		_refresh()
		return
	close()

func close() -> void:
	stack.clear()
	page_data = {}
	closed.emit()

func current() -> Dictionary:
	return stack.back() if not stack.is_empty() else {}

func is_open() -> bool:
	return not stack.is_empty()

## Earlier pages on the stack, oldest first: the clickable crumb trail.
func crumb_pages() -> Array:
	return stack.slice(0, maxi(stack.size() - 1, 0))

func _refresh() -> void:
	var top := current()
	page_data = WikiModel.page(str(top.get("page", WikiModel.LEAGUE)), str(top.get("id", "")))
	if body != null:
		var box := body_rect(design_vp())
		body.touch = touch
		body.position = box.position
		body.size = box.size
		body.set_page(page_data, is_compact())
	queue_redraw()

# -------------------------------------------------------------------- input --

func click(id: String) -> void:
	if id == "back":
		back()
	elif id == "close":
		close()
	elif id.begins_with("crumb:"):
		stack = stack.slice(0, int(id.substr(6)) + 1)
		_refresh()

## A tap anywhere in a table row or chip opens its page.
func tap(p: Vector2) -> bool:
	if body == null:
		return false
	var target: Dictionary = body.hit(p)
	if target.is_empty():
		return false
	push(str(target.get("page", "")), str(target.get("id", "")))
	return true

func wheel(delta: float) -> void:
	if body != null:
		body.scroll_by(delta)

func key(code: int) -> bool:
	if code == KEY_ESCAPE or code == KEY_BACKSPACE or code == KEY_LEFT:
		back()
	elif code == KEY_UP or code == KEY_W:
		wheel(-120.0)
	elif code == KEY_DOWN or code == KEY_S:
		wheel(120.0)
	else:
		return false
	return true

func button_at(p: Vector2) -> String:
	for b in buttons:
		if (b["rect"] as Rect2).has_point(p):
			return str(b["id"])
	return ""

# ----------------------------------------------------------------- geometry --

func design_vp() -> Vector2:
	return get_viewport().get_visible_rect().size / maxf(ui_scale, 0.001)

func is_compact() -> bool:
	return HudLayout.is_compact(design_vp())

## Body window under the header, above the key-hint strip. The header shrinks on
## a phone design space so the league table still gets most of the height.
## The body is a document column: on a wide desktop it stops growing so a
## table row never stretches a short value across half a metre of screen.
func body_rect(vp: Vector2) -> Rect2:
	var header := 150.0 if is_compact() else 168.0
	var w: float = minf(vp.x - 48.0, 1160.0)
	return Rect2((vp.x - w) * 0.5, header, w, vp.y - header - 34.0)

# ------------------------------------------------------------------ drawing --

func _draw() -> void:
	var vp := design_vp()
	buttons.clear()
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.012, 0.020, 0.026, 0.985))
	draw_rect(Rect2(0, 0, vp.x, 3), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(0, vp.y - 3, vp.x, 3), Color(0, 0, 0, 0.5))
	if body != null:
		body.mouse = mouse
	var accent: Color = page_data.get("accent", WikiChrome.GOLD)
	var x := 24.0
	var compact := is_compact()
	var title_y := 92.0 if compact else 108.0
	var back_rect := Rect2(x, 8.0 if compact else 10.0, 104, 30.0 if compact else 34.0)
	var close_rect := Rect2(vp.x - 68.0, back_rect.position.y, 44, back_rect.size.y)
	WikiChrome.button(self, f_bold, back_rect, "‹  BACK", back_rect.has_point(mouse))
	_add("back", back_rect)
	WikiChrome.button(self, f_bold, close_rect, "✕", close_rect.has_point(mouse))
	_add("close", close_rect)
	WikiChrome.label(self, f_bold, Vector2(x, title_y - (32.0 if compact else 38.0)), str(page_data.get("eyebrow", "")), 10, accent.lightened(0.35))
	draw_rect(Rect2(x, title_y - 28.0, 3, 28), accent)
	WikiChrome.label(self, f_bold, Vector2(x + 12, title_y), str(page_data.get("title", "")), 26 if compact else 34)
	WikiChrome.label(self, f_med, Vector2(x + 12, title_y + 18.0), str(page_data.get("subtitle", "")), 9, WikiChrome.DIM)
	_draw_crumbs(body_rect(vp).position.y - 16.0)
	var br := body_rect(vp)
	draw_line(Vector2(br.position.x, br.position.y - 8.0), Vector2(br.position.x + br.size.x, br.position.y - 8.0), Color(1, 1, 1, 0.07), 1)
	_draw_furniture(vp, br)

func _add(id: String, r: Rect2) -> void:
	buttons.append({"id": id, "rect": r})

func _draw_crumbs(y: float) -> void:
	var trail: Array = crumb_pages()
	var x := 24.0
	for i in range(trail.size()):
		var entry: Dictionary = trail[i]
		var label := WikiModel.label(str(entry["page"]), str(entry["id"]))
		var w: float = maxf(46.0, f_bold.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 22.0)
		var r := Rect2(x, y - 18.0, w, 24.0)
		var hovered := r.has_point(mouse)
		WikiChrome.box(self, WikiChrome.PANEL_LIGHT if hovered else WikiChrome.PANEL, r, 6, Color(1, 1, 1, 0.12 if hovered else 0.06))
		WikiChrome.label(self, f_bold, Vector2(x + 11.0, y - 1.0), label, 11, WikiChrome.TEXT if hovered else WikiChrome.DIM)
		_add("crumb:%d" % i, r)
		x += w + 6.0
	if not trail.is_empty():
		WikiChrome.label(self, f_bold, Vector2(x + 2.0, y - 1.0), str(page_data.get("title", "")), 10, WikiChrome.GOLD)

## Scrollbar plus the footer strip: the one place the sheet explains itself.
func _draw_furniture(vp: Vector2, br: Rect2) -> void:
	if body != null and body.max_scroll() > 0.0:
		var track := Rect2(br.position.x + br.size.x + 6.0, br.position.y, 3.0, br.size.y)
		var frac: float = clampf(body.size.y / maxf(body.content_height(), 1.0), 0.06, 1.0)
		var offset: float = body.scroll / maxf(body.content_height(), 1.0)
		var h: float = track.size.y * frac
		draw_rect(track, Color(1, 1, 1, 0.05))
		draw_rect(Rect2(track.position.x, track.position.y + (track.size.y - h) * offset, 3.0, h), Color(1, 1, 1, 0.22))
	var hint := "TAP A ROW TO OPEN  ·  BACK RETURN" if touch else "CLICK A ROW TO OPEN  ·  ESC BACK  ·  WHEEL SCROLLS"
	WikiChrome.label(self, f_med, Vector2(br.position.x, vp.y - 14.0), hint, 9, WikiChrome.DIM)
	var source := "SNAPSHOT %s" % str(WikiModel.repo().meta().get("snapshot_date", "")).to_upper()
	WikiChrome.label_r(self, f_med, br.end.x, vp.y - 14.0, source, 9, Color(0.96, 0.78, 0.30, 0.55))

func _process(_d: float) -> void:
	if body != null:
		var box := body_rect(design_vp())
		body.mouse = mouse
		body.position = box.position
		body.size = box.size
	queue_redraw()
