class_name PreMatchScreen
extends Control


signal kick_off
signal cancelled

const HEADER := 58.0
const BAR := 52.0
const NEWS_H := 42.0
const ROW := 15.0
const QUOTE_H := 46.0

var view: Dictionary = {}
var ui_scale := 1.0
var touch := false
var mouse := Vector2(-1000, -1000)

var auto_left := 0.0

var held := false
var buttons: Array = []
var rects: Dictionary = {}
var cache := {}
var f_bold: Font
var f_med: Font

# gd-tools: no cover start
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	f_bold = load("res://fonts/BarlowCondensed-SemiBold.ttf")
	f_med = load("res://fonts/BarlowCondensed-Medium.ttf")
	resized.connect(queue_redraw)

# gd-tools: no cover end

func setup(v: Dictionary) -> void:
	view = v
	held = false
	auto_left = float(v.get("auto_seconds", 10.0))
	queue_redraw()

func is_open() -> bool:
	return visible and not view.is_empty()

# gd-tools: no cover start
func design_vp() -> Vector2:
	var vp: Vector2 = size / maxf(ui_scale, 0.001)
	if (vp.x <= 0.0 or vp.y <= 0.0) and is_inside_tree():
		vp = get_viewport().get_visible_rect().size / maxf(ui_scale, 0.001)
	return vp

# gd-tools: no cover end


func _process(delta: float) -> void:
	if not is_open() or held or auto_left <= 0.0:
		return
	auto_left = maxf(0.0, auto_left - delta)
	queue_redraw()
	if auto_left <= 0.0:
		kick_off.emit()


func layout(vp: Vector2) -> Dictionary:
	var compact := vp.y < 620.0 or vp.x < 860.0
	var top := HEADER + 8.0
	var col_w := (vp.x - 72.0) * 0.5
	var news_y := vp.y - 12.0 - BAR - NEWS_H - 8.0
	var rows := 3 if compact else 4


	var room: float = news_y - top - 26.0 - 16.0 - rows * ROW - 10.0 - QUOTE_H - 4.0
	var pitch_h := clampf(minf(col_w * 0.56, room), 76.0, 268.0)
	var pitch_y := top + 26.0
	var out_y := pitch_y + pitch_h + 16.0
	var quote_y: float = out_y + rows * ROW + 10.0
	var out := {
		"compact": compact,
		"home_pitch": Rect2(24.0, pitch_y, col_w, pitch_h),
		"away_pitch": Rect2(24.0 + col_w + 24.0, pitch_y, col_w, pitch_h),
		"home_out": Rect2(24.0, out_y, col_w, rows * ROW),
		"away_out": Rect2(24.0 + col_w + 24.0, out_y, col_w, rows * ROW),
		"home_quote": Rect2(24.0, quote_y, col_w, QUOTE_H),
		"away_quote": Rect2(24.0 + col_w + 24.0, quote_y, col_w, QUOTE_H),
		"news": Rect2(24.0, news_y, vp.x - 48.0, NEWS_H),
		"rows": rows,
		"buttons": [],
	}
	var kick := LeagueExtra.primary_rect(vp, kick_width(vp), touch)
	var skip := Rect2(vp.x - 24.0 - 118.0, vp.y - 12.0 - BAR, 118.0, BAR)
	out["buttons"] = [
		{"id": "back", "rect": LeagueExtra.back_rect(touch)},
		{"id": "skip", "rect": skip},
		{"id": "kick", "rect": kick},
	]
	return out


static func kick_width(vp: Vector2) -> float:
	return clampf(vp.x * 0.28, 132.0, 210.0)


func button_at(p: Vector2) -> String:
	for b in layout(design_vp())["buttons"]:
		if (b["rect"] as Rect2).has_point(p):
			return str(b["id"])
	return ""


func click(id: String) -> void:
	if id == "kick":
		kick_off.emit()
	elif id == "skip":
		hold()
	elif id == "back":
		cancelled.emit()


func hold() -> void:
	held = true
	auto_left = 0.0
	queue_redraw()

func key(code: int) -> bool:
	if code == KEY_ENTER or code == KEY_KP_ENTER or code == KEY_SPACE:
		kick_off.emit()
	elif code == KEY_ESCAPE or code == KEY_BACKSPACE:
		cancelled.emit()
	elif code == KEY_S:
		hold()
	else:
		return false
	return true


# gd-tools: no cover start

func _draw() -> void:
	var vp := design_vp()
	if vp.x <= 1.0 or vp.y <= 1.0:
		return
	var fonts := {"bold": f_bold, "med": f_med}
	rects = layout(vp)
	buttons = rects["buttons"]
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.008, 0.014, 0.018, 0.97))
	_draw_header(vp, fonts)
	_draw_side(rects["home_pitch"], rects["home_out"], rects["home_quote"],
		view.get("home", {}), view.get("home_xi", []), str(view.get("home_captain", "")),
		view.get("home_absences", []), view.get("home_quote", {}),
		_view_text("home_form"), int(view.get("home_position", 0)), fonts, false)
	_draw_side(rects["away_pitch"], rects["away_out"], rects["away_quote"],
		view.get("away", {}), view.get("away_xi", []), str(view.get("away_captain", "")),
		view.get("away_absences", []), view.get("away_quote", {}),
		_view_text("away_form"), int(view.get("away_position", 0)), fonts, true)
	_draw_news(rects["news"], fonts)
	_draw_doors(vp, fonts)

func _view_text(key: String) -> String:
	return str(view.get(key, ""))


func _draw_header(vp: Vector2, fonts: Dictionary) -> void:
	var bold: Font = fonts["bold"]
	var caption := str(view.get("caption", ""))
	var when := str(view.get("date_label", ""))
	if str(view.get("time", "")) != "":
		when = when + " · " + str(view["time"]) if when != "" else str(view["time"])
	var kicker := caption if when == "" else (caption + " · " + when)
	var right: float = kick_width(vp) + 12.0
	var title_end: float = 136.0 + UiChrome.text_width(bold, "PRE-MATCH", 16)
	var room: float = (vp.x - 24.0 - right) - title_end - 12.0
	var line := ""
	if room >= 60.0:
		line = LeagueColumns.fit_name(kicker, bold, 10, room)
	LeagueExtra.header(self, vp, fonts, "PRE-MATCH", line, right, true, touch, false)


static func strip_line(team: Dictionary, position: int, form: String) -> String:
	var parts: Array = []
	var shape := str(team.get("formation", ""))
	if shape != "":
		parts.append(shape)
	if position > 0:
		parts.append(PreMatchCopy.place(position).to_upper())
	if form != "":
		parts.append(form)
	return " · ".join(PackedStringArray(parts))


func _draw_side(pitch: Rect2, out_rect: Rect2, quote: Rect2, team: Dictionary,
		xi: Array, captain: String, absences: Array, quote_data: Dictionary,
		form: String, position: int, fonts: Dictionary, mirror: bool) -> void:
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	var colour: Color = team.get("color", UiChrome.C_GOLD)
	draw_rect(Rect2(pitch.position.x, pitch.position.y - 20.0, 3.0, 16.0), colour)
	UiChrome.text(self, Vector2(pitch.position.x + 10.0, pitch.position.y - 6.0),
		str(team.get("abbr", "")), 20, UiChrome.C_TEXT, bold)
	var name_x := pitch.position.x + 10.0 + UiChrome.text_width(bold, str(team.get("abbr", "")), 20) + 10.0
	UiChrome.text(self, Vector2(name_x, pitch.position.y - 7.0),
		str(team.get("name", "")).to_upper(), 11, UiChrome.C_DIM, med)

	var right := strip_line(team, position, form)
	if right != "":
		UiChrome.text_r(self, pitch.end.x, pitch.position.y - 7.0, right, 10, UiChrome.C_GOLD, bold)
	PreMatchPitch.draw(self, pitch, team, xi, captain, fonts, mirror)

	UiChrome.text(self, Vector2(out_rect.position.x, out_rect.position.y + 2.0),
		"OUT · %d" % absences.size(), 10, UiChrome.C_DIM, bold)
	var shown := mini(absences.size(), int(rects.get("rows", 4)))
	for i in range(shown):
		var row: Dictionary = absences[i]
		var y := out_rect.position.y + ROW + 6.0 + float(i) * ROW
		var tag := "INJ" if str(row.get("kind", "")) == "injury" else "BAN"
		UiChrome.text(self, Vector2(out_rect.position.x, y),
			"%s  %s" % [tag, str(row.get("name", "")).to_upper()], 10,
			UiChrome.C_DANGER if tag == "BAN" else UiChrome.C_SOFT, med)
		UiChrome.text_r(self, out_rect.end.x, y, str(row.get("label", "")), 10, UiChrome.C_DIM, bold)
	if absences.size() > shown:
		UiChrome.text(self, Vector2(out_rect.position.x, out_rect.position.y + ROW * (shown + 1) + 6.0),
			"+%d MORE" % (absences.size() - shown), 10, UiChrome.C_DIM, bold)
	if absences.is_empty():
		UiChrome.text(self, Vector2(out_rect.position.x, out_rect.position.y + ROW + 6.0),
			"NO ABSENCES", 10, UiChrome.C_DIM, med)

	UiChrome.panel(self, cache, quote, UiChrome.C_PANEL, 6, Color(0.96, 0.78, 0.30, 0.22), 1)
	UiChrome.text(self, Vector2(quote.position.x + 10.0, quote.position.y + 16.0),
		str(quote_data.get("by", "")), 10, UiChrome.C_GOLD, bold)
	var lines := _wrap(str(quote_data.get("line", "")), quote.size.x - 20.0, 2)
	for i in range(lines.size()):
		UiChrome.text(self, Vector2(quote.position.x + 10.0, quote.position.y + 30.0 + float(i) * 13.0),
			str(lines[i]), 11, UiChrome.C_SOFT, med)

func _draw_news(rect: Rect2, fonts: Dictionary) -> void:
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	var news: Dictionary = view.get("news", {})
	UiChrome.panel(self, cache, rect, UiChrome.C_PANEL_LIGHT, 6, Color(1, 1, 1, 0.10), 1)
	UiChrome.text(self, Vector2(rect.position.x + 12.0, rect.position.y + 16.0),
		"◈ " + str(news.get("title", "")), 10, UiChrome.C_GOLD, bold)
	var line := _wrap(str(news.get("line", "")), rect.size.x - 190.0, 2)
	for i in range(line.size()):
		UiChrome.text(self, Vector2(rect.position.x + 118.0, rect.position.y + 16.0 + float(i) * 14.0),
			str(line[i]), 11, UiChrome.C_TEXT, med)

func _draw_doors(vp: Vector2, fonts: Dictionary) -> void:
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	var kick_label := str(view.get("kick", "KICK OFF"))
	for b in buttons:
		var rect: Rect2 = b["rect"]
		var id := str(b["id"])
		if id == "kick":


			UiChrome.button(self, cache, rect, kick_label, bold, true, 16)
		elif id == "skip":
			UiChrome.button(self, cache, rect, "SKIP", bold, false)
		else:
			UiChrome.panel(self, cache, rect, UiChrome.C_PANEL_LIGHT, 7)
			UiChrome.text_c(self, rect.get_center().x, rect.position.y + 21.0, "BACK", 12,
				UiChrome.C_TEXT, bold)
	var caption := ""
	var bar_y: float = vp.y - 12.0 - BAR
	if held:
		caption = "BRIEFING HELD · %s WHEN READY" % kick_label
	elif auto_left > 0.0:
		caption = "%s IN %d s · SKIP HOLDS THE BRIEFING" % [kick_label, int(ceil(auto_left))]
	if caption != "":
		var room: float = vp.x - 24.0 - 118.0 - 36.0
		caption = LeagueColumns.fit_name(caption, bold, 10, maxf(room, 60.0))
	UiChrome.text(self, Vector2(24.0, bar_y + 22.0), caption, 10, UiChrome.C_DIM, bold)
	if not touch:
		UiChrome.text(self, Vector2(24.0, bar_y + 38.0),
			"ENTER  %s   ·   ESC  BACK" % kick_label, 10, UiChrome.C_DIM, med)


func _wrap(text: String, width: float, max_lines: int) -> Array:
	var out: Array = []
	var line := ""
	for word in text.split(" ", false):
		var trial := word if line == "" else line + " " + word
		if UiChrome.text_width(f_med, trial, 11) <= width:
			line = trial
			continue
		out.append(line)
		line = word
		if out.size() >= max_lines:
			break
	if out.size() < max_lines and line != "":
		out.append(line)
	return out

# gd-tools: no cover end
