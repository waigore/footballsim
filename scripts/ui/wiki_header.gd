class_name WikiHeader
extends RefCounted


static func body_rect(vp: Vector2, compact: bool) -> Rect2:
	var header := 150.0 if compact else 168.0
	var w: float = minf(vp.x - 48.0, 1160.0)
	return Rect2((vp.x - w) * 0.5, header, w, vp.y - header - 34.0)


static func paint(screen: WikiScreen) -> void:
	var vp: Vector2 = screen.design_vp()
	screen.buttons.clear()
	screen.hints.clear()
	screen.names.clear()
	screen.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.012, 0.020, 0.026, 0.985))
	screen.draw_rect(Rect2(0, 0, vp.x, 3), Color(0, 0, 0, 0.5))
	screen.draw_rect(Rect2(0, vp.y - 3, vp.x, 3), Color(0, 0, 0, 0.5))
	if screen.body != null:
		screen.body.mouse = screen.mouse
	var accent: Color = screen.page_data.get("accent", WikiChrome.GOLD)
	var x := 24.0
	var compact: bool = screen.is_compact()
	var title_y := 92.0 if compact else 108.0
	var back_h: float = 30.0 if compact else 34.0
	var back_y: float = 8.0 if compact else 10.0
	if screen.touch:
		back_h = UiChrome.TAP_H
		back_y = 8.0
	var back_rect := Rect2(x, back_y, 104, back_h)
	var close_rect := Rect2(vp.x - 68.0, back_rect.position.y, maxf(44.0, back_h), back_h)
	WikiChrome.button(screen, screen.f_bold, back_rect, "‹  BACK", back_rect.has_point(screen.mouse))
	screen._add("back", back_rect)
	WikiChrome.button(screen, screen.f_bold, close_rect, "✕", close_rect.has_point(screen.mouse))
	screen._add("close", close_rect)
	var follow := WikiInterest.door(screen.current(), LeagueSeason.active, vp, back_rect, close_rect)
	if not follow.is_empty():
		WikiInterest.draw(screen, screen.f_bold, follow["rect"], str(follow["text"]),
			bool(follow["followed"]), (follow["rect"] as Rect2).has_point(screen.mouse))
		screen._add(str(follow["id"]), follow["rect"])
	WikiChrome.label(screen, screen.f_bold, Vector2(x, title_y - (32.0 if compact else 38.0)),
		str(screen.page_data.get("eyebrow", "")), 10, accent.lightened(0.35))
	screen.draw_rect(Rect2(x, title_y - 28.0, 3, 28), accent)
	var title := str(screen.page_data.get("title", ""))
	var title_size := 26 if compact else 34
	WikiChrome.label(screen, screen.f_bold, Vector2(x + 12, title_y), title, title_size)
	if str(screen.current().get("page", "")) == WikiModel.TEAM:
		screen.names.add(InterestNames.strip(screen.f_bold, title, x + 12.0, title_y, title_size),
			str(screen.current().get("id", "")))
	_subtitle(screen, x + 12.0, title_y + 18.0)
	_crumbs(screen, body_rect(vp, compact).position.y - 16.0)
	var br := body_rect(vp, compact)
	screen.draw_line(Vector2(br.position.x, br.position.y - 8.0),
		Vector2(br.position.x + br.size.x, br.position.y - 8.0), Color(1, 1, 1, 0.07), 1)
	_furniture(screen, vp, br)


static func _subtitle(screen: WikiScreen, sub_x: float, y: float) -> void:
	var sub := str(screen.page_data.get("subtitle", ""))
	WikiChrome.label(screen, screen.f_med, Vector2(sub_x, y), sub, 10, WikiChrome.DIM)
	var snap := str(screen.page_data.get("snapshot", ""))
	if snap == "":
		return
	var label := FixtureCalendar.day_label(snap)
	var at := Vector2(sub_x + DateHints.width(screen.f_med, sub, 10), y)
	WikiChrome.label(screen, screen.f_med, at, label, 10, WikiChrome.DIM)
	screen.hints.add(DateHints.strip(screen.f_med, label, at, 10), snap)


static func _crumbs(screen: WikiScreen, y: float) -> void:
	var trail: Array = screen.crumb_pages()
	var x := 24.0
	for i in range(trail.size()):
		var entry: Dictionary = trail[i]
		var label := WikiModel.label(str(entry["page"]), str(entry["id"]))
		var w: float = maxf(46.0, screen.f_bold.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 22.0)
		var r := Rect2(x, y - 18.0, w, 24.0)
		var hovered := r.has_point(screen.mouse)
		WikiChrome.box(screen, WikiChrome.PANEL_LIGHT if hovered else WikiChrome.PANEL, r, 6,
			Color(1, 1, 1, 0.12 if hovered else 0.06))
		WikiChrome.label(screen, screen.f_bold, Vector2(x + 11.0, y - 1.0), label, 11,
			WikiChrome.TEXT if hovered else WikiChrome.DIM)
		screen._add("crumb:%d" % i, r)
		x += w + 6.0
	if not trail.is_empty():
		WikiChrome.label(screen, screen.f_bold, Vector2(x + 2.0, y - 1.0),
			str(screen.page_data.get("title", "")), 10, WikiChrome.GOLD)


static func _furniture(screen: WikiScreen, vp: Vector2, br: Rect2) -> void:
	var body = screen.body
	var can_scroll := body != null and body.max_scroll() > 0.0
	if can_scroll:
		var track := Rect2(br.position.x + br.size.x + 6.0, br.position.y, 3.0, br.size.y)
		var frac: float = clampf(body.size.y / maxf(body.content_height(), 1.0), 0.06, 1.0)
		var offset: float = clampf(body.scroll / maxf(body.max_scroll(), 0.001), 0.0, 1.0)
		var h: float = track.size.y * frac
		screen.draw_rect(track, Color(1, 1, 1, 0.05))
		screen.draw_rect(Rect2(track.position.x, track.position.y + (track.size.y - h) * offset, 3.0, h),
			Color(1, 1, 1, 0.22))
	var can_open := body != null and body.has_open_row_in_view()
	var hint := WikiChrome.footer_hint(screen.touch, can_open, can_scroll)
	if hint != "":
		WikiChrome.label(screen, screen.f_med, Vector2(br.position.x, vp.y - 14.0), hint, 10, WikiChrome.DIM)
	var snap := str(WikiModel.repo().meta().get("snapshot_date", ""))
	var label := FixtureCalendar.day_label(snap)
	WikiChrome.label_r(screen, screen.f_med, br.end.x, vp.y - 14.0, "DATA  ·  %s" % label, 10,
		Color(0.96, 0.78, 0.30, 0.55))
	if snap != "":
		screen.hints.add(DateHints.strip_right(screen.f_med, label, br.end.x, vp.y - 14.0, 10), snap)
