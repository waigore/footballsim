class_name LeagueMarks
extends RefCounted


const BOX := 10.0
const SIZE := 10

# gd-tools: no cover start


static func icon(c: CanvasItem, kind: String, at: Vector2, own: bool = false) -> void:
	var cx := at.x + BOX * 0.5
	var cy := at.y + BOX * 0.5
	match kind:
		"goal", "own_goal":
			c.draw_circle(Vector2(cx, cy), 3.7, UiChrome.C_GOLD)
			c.draw_circle(Vector2(cx, cy), 1.3, Color(0.06, 0.06, 0.05))
			if own:


				c.draw_line(Vector2(cx - 4.0, cy + 3.4), Vector2(cx + 4.0, cy - 3.4),
					Color(0.06, 0.06, 0.05, 0.9), 1.4)
		"yellow":
			c.draw_rect(Rect2(cx - 2.8, cy - 4.2, 5.6, 8.4), Color(0.92, 0.84, 0.35))
		"red":
			c.draw_rect(Rect2(cx - 2.8, cy - 4.2, 5.6, 8.4), UiChrome.C_DANGER)
		"injury":
			c.draw_rect(Rect2(cx - 1.2, cy - 4.2, 2.4, 8.4), UiChrome.C_SOFT)
			c.draw_rect(Rect2(cx - 4.2, cy - 1.2, 8.4, 2.4), UiChrome.C_SOFT)
		_:
			c.draw_circle(Vector2(cx, cy), 2.4, UiChrome.C_DIM)


static func line(c: CanvasItem, at: Vector2, e: Dictionary, fonts: Dictionary,
		max_w: float, ink: Color = UiChrome.C_TEXT) -> void:
	var kind := str(e.get("kind", ""))
	icon(c, kind, at, LeagueRoundup.is_own_goal(e))
	var med: Font = fonts["med"]
	var bold: Font = fonts["bold"]
	var minute := "%d'" % int(e.get("minute", 0))
	UiChrome.text(c, Vector2(at.x + BOX + 4.0, at.y + BOX - 1.0), minute, SIZE,
		UiChrome.C_DIM, bold)
	var tail := ""
	if LeagueRoundup.is_own_goal(e):
		tail += LeagueRoundup.OG
	elif LeagueRoundup.is_penalty(e):
		tail += LeagueRoundup.PEN
	var assist := str(e.get("assist_name", ""))
	if assist != "":
		tail += " (%s)" % assist
	var prefix := BOX + 4.0 + UiChrome.text_width(bold, minute + " ", SIZE)
	var name := _player(e)
	var room := maxf(max_w - prefix - UiChrome.text_width(med, tail, SIZE), 18.0)
	name = LeagueColumns.fit_name(name, med, SIZE, room)
	UiChrome.text(c, Vector2(at.x + prefix, at.y + BOX - 1.0), name + tail, SIZE, ink, med)

static func _player(e: Dictionary) -> String:
	var raw = e.get("player_name", null)
	var name := "" if raw == null else str(raw)
	if name == "":
		raw = e.get("detail", null)
		name = "" if raw == null else str(raw)
	return name if name != "" else "Unknown"

# gd-tools: no cover end
