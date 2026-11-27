class_name PreMatchPitch
extends RefCounted


const GRASS := Color(0.045, 0.115, 0.068)
const LINE := Color(1, 1, 1, 0.20)


# gd-tools: no cover start
static func draw(c: CanvasItem, rect: Rect2, team: Dictionary, xi: Array,
		captain_id: String, fonts: Dictionary, mirror: bool) -> void:
	if rect.size.x < 8.0 or rect.size.y < 8.0:
		return
	c.draw_rect(rect, GRASS)
	c.draw_rect(rect, LINE, false, 1.0)
	var mid_x := rect.position.x + rect.size.x * 0.5
	var mid_y := rect.get_center().y
	c.draw_line(Vector2(mid_x, rect.position.y), Vector2(mid_x, rect.end.y), LINE, 1.0)
	c.draw_arc(Vector2(mid_x, mid_y), rect.size.y * 0.13, 0.0, TAU, 28, LINE, 1.0)
	var box_w := rect.size.x * 0.15
	var box_h := rect.size.y * 0.52
	c.draw_rect(Rect2(rect.position.x, mid_y - box_h * 0.5, box_w, box_h), LINE, false, 1.0)
	c.draw_rect(Rect2(rect.end.x - box_w, mid_y - box_h * 0.5, box_w, box_h), LINE, false, 1.0)
	var radius := clampf(rect.size.y * 0.034, 4.0, 9.0)
	var named := rect.size.x >= 300.0
	var shirt: Color = team.get("color", UiChrome.C_GOLD)
	var ink := Kits.ink(shirt)
	var bold: Font = fonts["bold"]
	for p in xi:
		var slot := TeamData.formation_slot(team, str(p.get("role", "")))
		var x := 1.0 - slot.x if mirror else slot.x
		var at := Vector2(rect.position.x + x * rect.size.x, rect.position.y + slot.y * rect.size.y)
		at.x = clampf(at.x, rect.position.x + radius, rect.end.x - radius)
		at.y = clampf(at.y, rect.position.y + radius, rect.end.y - radius)
		if str(p.get("id", "")) == captain_id:
			c.draw_circle(at, radius + 2.5, UiChrome.C_GOLD)
		c.draw_circle(at, radius, shirt)
		c.draw_arc(at, radius, 0.0, TAU, 20, Color(0, 0, 0, 0.45), 1.0)
		UiChrome.text_c(c, at.x, at.y + 3.5, str(int(p.get("number", 0))), 10, ink, bold)
		if named:
			var label := short_name(str(p.get("name", "")))
			var room := rect.size.x * 0.21
			UiChrome.text_c(c, at.x, at.y + radius + 11.0,
				LeagueColumns.fit_name(label, bold, 10, room), 10, UiChrome.C_TEXT, bold)

# gd-tools: no cover end


static func short_name(name: String) -> String:
	var parts := name.strip_edges().split(" ", false)
	if parts.size() <= 1:
		return name.strip_edges().to_upper()
	return str(parts[parts.size() - 1]).to_upper()
