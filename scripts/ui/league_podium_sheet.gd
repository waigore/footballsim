class_name LeaguePodiumSheet
extends RefCounted


const HEADER := LeagueChrome.HEADER
const BAR_H := LeagueChrome.BAR_H


var hints := DateHints.new()

func layout(vp: Vector2, view: Dictionary) -> Array:
	var items: Array = []


	items.append({"id": "", "kind": "extent",
		"rect": Rect2(24.0, HEADER, vp.x - 48.0, frame_height(view))})
	items.append(LeagueExtra.back_item(bool(view.get("touch", false))))
	items.append({"id": "table", "kind": "button", "label": "TABLE", "primary": false, "pinned": true,
		"rect": Rect2(24.0, vp.y - BAR_H + 6.0, 130.0, BAR_H - 14.0)})
	items.append({"id": "menu", "kind": "button", "label": "MAIN MENU", "primary": true, "pinned": true,
		"rect": Rect2(24.0 + 142.0, vp.y - BAR_H + 6.0, 170.0, BAR_H - 14.0)})
	return items


func frame_height(view: Dictionary) -> float:
	var summary: Dictionary = view.get("summary", {})
	if summary.is_empty():
		return 0.0
	var h := 0.0
	var summary_data: Dictionary = view.get("summary", {})
	var brackets: Dictionary = summary_data.get("playoffs", {})
	for section in sections(summary):
		var section_rules: Dictionary = section.get("rules", view.get("rules", {}))
		h += 30.0
		h += 18.0 + 44.0 + 24.0 + 16.0
		h += 16.0 * float(mini((section["europe"] as Array).size(), 6))
		h += 6.0 + 16.0
		h += 16.0 * float((section["relegated"] as Array).size())


		var up := _promoted_count(section, section_rules)
		if up > 0:
			h += 6.0 + 16.0 + 16.0 * float(up)

		if brackets.has(str(section.get("id", ""))):
			h += 6.0 + 16.0
		var ties: Dictionary = summary_data.get("playout", {})
		if ties.has(str(section.get("id", ""))):
			h += 6.0 + 16.0
		h += 12.0
	h += cups_height(summary)
	if not (summary.get("relegation", {}) as Dictionary).is_empty():
		h += 8.0 + 16.0
	return h + 8.0


static func cups_of(summary: Dictionary) -> Array:
	var list: Variant = summary.get("cups", [])
	return list if list is Array else []


static func cups_height(summary: Dictionary) -> float:
	var cups := cups_of(summary)
	if cups.is_empty():
		return 0.0
	return 26.0 + 18.0 * float(cups.size())


static func sections(summary: Dictionary) -> Array:
	var out: Array = summary.get("competitions", [])
	if out.is_empty() and not summary.is_empty():
		out = [summary]
	return out


static func _promoted_count(section: Dictionary, rules: Dictionary) -> int:
	var up := int(rules.get("promotion_places", 0)) + int(rules.get("promotion_playoff_places", 0))
	var rows: Array = section.get("table", [])
	return up if rows.is_empty() else mini(up, rows.size())


func _paint_band(c: CanvasItem, body: Callable) -> void:
	body.call(c)

# gd-tools: no cover start

func draw_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		_hints: DateHints) -> void:
	LeagueExtra.header(c, vp, fonts, "SEASON COMPLETE", str(view.get("name", "")), 0.0, true,
		bool(view.get("touch", false)))

func draw_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, _items: Array, view: Dictionary) -> void:
	_paint_band(c, _draw_body.bind(vp, fonts, view))

func _draw_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary) -> void:
	hints.clear()
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	var summary: Dictionary = view.get("summary", {})
	var brackets: Dictionary = summary.get("playoffs", {})
	var y := HEADER + 6.0
	if summary.is_empty():
		return
	for section in sections(summary):
		var section_rules: Dictionary = section.get("rules", view.get("rules", {}))
		UiChrome.text(c, Vector2(24.0, y + 12.0), str(section.get("name", section.get("short", ""))).to_upper(),
			12, UiChrome.C_GOLD, bold)
		c.draw_rect(Rect2(24.0, y + 18.0, vp.x - 48.0, 1.0), Color(1, 1, 1, 0.10))
		y += 30.0
		UiChrome.text(c, Vector2(24.0, y), "CHAMPIONS", 10, UiChrome.C_DIM, bold)
		UiChrome.text(c, Vector2(24.0, y + 30.0), str(section["champion"]["club"]), 30, UiChrome.C_GOLD, bold)
		UiChrome.text_r(c, vp.x - 24.0, y + 30.0, "%d PTS" % int(section["champion"]["points"]),
			14, UiChrome.C_TEXT, bold)
		y += 44.0
		UiChrome.text(c, Vector2(24.0, y), "RUNNER-UP  %s · %d PTS" % [str(section["runner_up"]["club"]),
			int(section["runner_up"]["points"])], 12, UiChrome.C_SOFT, bold)
		y += 24.0

		var section_up := _promoted_count(section, section_rules)
		if (section["europe"] as Array).is_empty() and section_up > 0:
			_paint_promoted(c, vp, section, section_up, y, bold, med)
			y += 16.0 + 16.0 * float(section_up)
		else:
			UiChrome.text(c, Vector2(24.0, y), "EUROPEAN PLACES", 10, UiChrome.C_DIM, bold)
			y += 16.0
			var zone_rows: Array = section["europe"]
			for i in range(mini(zone_rows.size(), 6)):
				var row: Dictionary = zone_rows[i]
				var club := _club_row(section, str(row["zone"]))
				var band := LeagueRules.zone(int(row["position"]), section_rules)
				c.draw_rect(Rect2(24.0, y + 2.0, 3.0, 12.0), LeagueChrome.zone_color(band))
				UiChrome.text(c, Vector2(32.0, y + 12.0), "%d" % int(row["position"]), 10, UiChrome.C_DIM, med)
				UiChrome.text(c, Vector2(54.0, y + 12.0), str(row["club"]), 11, UiChrome.C_TEXT, med)
				UiChrome.text_r(c, vp.x - 24.0, y + 12.0, str(club.get("points", "")), 10, UiChrome.C_SOFT, bold)
				y += 16.0

		var bracket: Dictionary = brackets.get(str(section.get("id", "")), {})
		if not bracket.is_empty():
			y += 6.0
			UiChrome.text(c, Vector2(24.0, y + 12.0), "PLAY-OFFS  %s" % str(bracket.get("text", "")),
				10, UiChrome.C_GOLD, bold)
			y += 16.0
		var playout: Dictionary = (summary.get("playout", {}) as Dictionary).get(
			str(section.get("id", "")), {})
		if not playout.is_empty():
			y += 6.0
			UiChrome.text(c, Vector2(24.0, y + 12.0), "PLAY-OUT  %s" % str(playout.get("text", "")),
				10, UiChrome.C_GOLD, bold)
			y += 16.0
		y += 6.0
		UiChrome.text(c, Vector2(24.0, y), "RELEGATED", 10, UiChrome.C_DIM, bold)
		y += 16.0
		for row in section["relegated"]:
			UiChrome.text(c, Vector2(32.0, y + 12.0), "%d" % int(row["position"]), 10, UiChrome.C_DIM, med)
			UiChrome.text(c, Vector2(54.0, y + 12.0), str(row["club"]), 11, UiChrome.C_DANGER, med)
			y += 16.0
		var scorers: Array = section.get("top_scorers", [])
		if not scorers.is_empty():
			UiChrome.text_r(c, vp.x - 24.0, y + 12.0, "TOP SCORER  %s (%d)" % [str(scorers[0]["name"]),
				int(scorers[0]["goals"])], 11, UiChrome.C_SOFT, bold)
		y += 12.0


	var tie: Dictionary = summary.get("relegation", {})
	if not tie.is_empty():
		UiChrome.text(c, Vector2(24.0, y + 8.0), "RELEGATION  %s" % str(tie.get("text", "")),
			10, UiChrome.C_GOLD, bold)
		y += 16.0
	_paint_cups(c, vp, summary, y, bold, med)


static func cups_lines(summary: Dictionary) -> Array:
	var out: Array = []
	for cup in cups_of(summary):
		var row: Dictionary = cup
		var line := "%s  ·  %s" % [str(row.get("short", row.get("id", ""))),
			str(row.get("winner_name", row.get("winner", "")))]
		var runner := str(row.get("runner_up_name", row.get("runner_up", "")))
		if runner != "":
			line += "  beat  %s" % runner
		var score := "%d – %d" % [int(row.get("home_goals", 0)), int(row.get("away_goals", 0))]
		if int(row.get("pens_home", -1)) >= 0:
			score += "  (%d–%d PENS)" % [int(row.get("pens_home", 0)), int(row.get("pens_away", 0))]
		elif bool(row.get("extra_time", false)):
			score += "  AET"
		out.append({"name": str(row.get("name", row.get("id", ""))), "line": line,
			"score": score})
	return out


func _paint_cups(c: CanvasItem, vp: Vector2, summary: Dictionary, y_in: float, bold: Font,
		med: Font) -> void:
	var lines := cups_lines(summary)
	if lines.is_empty():
		return
	var y := y_in + 8.0
	UiChrome.text(c, Vector2(24.0, y), "DOMESTIC HONOURS", 10, UiChrome.C_DIM, bold)
	y += 16.0
	for row in lines:
		var line: Dictionary = row
		UiChrome.text(c, Vector2(24.0, y + 12.0),
			LeagueColumns.fit_name(str(line["line"]), bold, 11, vp.x - 48.0 - 96.0), 11,
			UiChrome.C_TEXT, bold)
		UiChrome.text_r(c, vp.x - 24.0, y + 12.0, str(line["score"]), 10, UiChrome.C_GOLD, bold)
		y += 18.0


func _paint_promoted(c: CanvasItem, vp: Vector2, section: Dictionary, up: int,
		y: float, bold: Font, med: Font) -> void:
	UiChrome.text(c, Vector2(24.0, y), "PROMOTION", 10, UiChrome.C_DIM, bold)
	var rows: Array = section.get("table", [])
	var auto := int((section.get("rules", {}) as Dictionary).get("promotion_places", 0))
	for i in range(mini(up, rows.size())):
		var row: Dictionary = rows[i]
		var band := "promotion" if i < auto else "playoff"
		var cy := y + 16.0 + 16.0 * float(i)
		c.draw_rect(Rect2(24.0, cy + 2.0, 3.0, 12.0), LeagueChrome.zone_color(band))
		UiChrome.text(c, Vector2(32.0, cy + 12.0), "%d" % (i + 1), 10, UiChrome.C_DIM, med)
		UiChrome.text(c, Vector2(54.0, cy + 12.0), str(row.get("club_name", "")), 11, UiChrome.C_TEXT, med)
		UiChrome.text_r(c, vp.x - 24.0, cy + 12.0, str(row.get("points", "")), 10, UiChrome.C_SOFT, bold)

func _club_row(section: Dictionary, club_id: String) -> Dictionary:
	for row in section.get("table", []):
		if str(row["club_id"]) == club_id:
			return row
	return {}

# gd-tools: no cover end
