class_name LeagueChrome
extends RefCounted


const HEADER := 58.0


const BAR_H := 52.0

const COMPACT_H := 620.0

const ROW_H := 26.0
const ROW_GAP := 5.0


static func zone_color(band: String) -> Color:
	if band == "ucl":
		return UiChrome.C_GOLD
	if band == "uel":
		return UiChrome.C_LIVE
	if band == "uecl":
		return Color(0.55, 0.72, 0.92)
	if band == "promotion":
		return Color(0.45, 0.85, 0.55)
	if band == "playoff":
		return Color(0.93, 0.68, 0.34)
	if band == "relegation":
		return UiChrome.C_DANGER
	return UiChrome.C_DIM


static func competition_chip_label(row: Dictionary, width: float) -> String:
	var name := str(row.get("short_name", row.get("name", "")))
	if width >= 100.0 or name.length() <= 5:
		return name
	match str(row.get("id", "")):
		"BL":
			return "BL"
		"BL2":
			return "2.BL"
		"PL":
			return "PL"
		"LL":
			return "LL"
		"CH":
			return "CHAMP"
		"L1":
			return "L1"
		"L2":
			return "L2"
		"NL":
			return "NL"
	return name.substr(0, 5)


const WINNER_MODES: Array = [["draw", "ALLOW DRAW"], ["extra", "EXTRA TIME & PENS"]]

const WINNER_H := 24.0
const WINNER_GAP := 14.0

static func winner_rects(vp: Vector2, card_bottom: float) -> Array:
	var w: float = minf(150.0, (vp.x - 48.0) * 0.5)
	var out: Array = []
	for i in range(WINNER_MODES.size()):
		out.append({"id": str(WINNER_MODES[i][0]), "label": str(WINNER_MODES[i][1]),
			"rect": Rect2(vp.x * 0.5 - w - 4.0 + float(i) * (w + 8.0),
				card_bottom + WINNER_GAP, w, WINNER_H)})
	return out


static func winner_bottom(card_bottom: float) -> float:
	return card_bottom + WINNER_GAP + WINNER_H


const PICKER_CHIP_H := 24.0
static func picker_header(vp: Vector2) -> Dictionary:
	var compact: bool = vp.y < COMPACT_H
	var rule_y: float = vp.y * (0.135 if compact else 0.185)
	return {
		"compact": compact,
		"title": not compact,
		"wordmark_y": vp.y * (0.075 if compact else 0.105),
		"rule_y": rule_y,


		"chips_y": vp.y * 0.155 if compact else rule_y - PICKER_CHIP_H - 6.0,
		"title_y": vp.y * (0.195 if compact else 0.235),
		"title_size": 30 if compact else 38,
		"rule_w": 48.0 if compact else 54.0,
	}


static func picker_chips_band(vp: Vector2) -> Rect2:
	return Rect2(24.0, float(picker_header(vp)["chips_y"]), vp.x - 48.0, PICKER_CHIP_H)


const PICKER_CHIP_GAP := 8.0
static func picker_chip_rects(vp: Vector2, count: int) -> Array:
	var out: Array = []
	if count <= 0:
		return out
	var y: float = float(picker_header(vp)["chips_y"])
	var w: float = minf(150.0, (vp.x - 48.0 - PICKER_CHIP_GAP * float(count - 1)) / float(count))
	var x := 24.0
	for i in range(count):
		out.append(Rect2(x, y, w, PICKER_CHIP_H))
		x += w + PICKER_CHIP_GAP
	return out


static func picker_doors(vp: Vector2, card_bottom: float) -> Array:


	var bw: float = minf(190.0, (vp.x - 32.0) * 0.5 - 4.0)
	var bh := 50.0
	var lowest: float = winner_bottom(card_bottom) + 10.0
	var highest: float = maxf(vp.y - bh - 8.0, lowest)
	var by: float = clampf(card_bottom + 54.0, lowest, highest)
	return [
		{"id": "confirm", "rect": Rect2(vp.x * 0.5 - bw - 8.0, by, bw, bh)},
		{"id": "random", "rect": Rect2(vp.x * 0.5 + 8.0, by, bw, bh)},
	]

static func winner_control(c: CanvasItem, vp: Vector2, card_bottom: float, mode: String,
		bold: Font) -> void:
	for spec in winner_rects(vp, card_bottom):
		var r: Rect2 = spec["rect"]
		var on := str(spec["id"]) == mode
		c.rect(UiChrome.C_GOLD.darkened(0.1) if on else UiChrome.C_PANEL, r, 6,
			UiChrome.C_GOLD if on else Color(1, 1, 1, 0.10))
		UiChrome.text_c(c, r.get_center().x, r.position.y + 16.0, str(spec["label"]), 10,
			Color(0.06, 0.06, 0.05) if on else UiChrome.C_DIM, bold)
		c._add_button("win:" + str(spec["id"]), r)


static func competition_rows() -> Array:
	var rows: Array = [{"id": "", "short_name": "ALL"}]
	rows.append_array(PLCompetitions.active())
	return rows


static func picker_league_keys(rows: Array) -> String:
	if rows.size() < 2:
		return ""
	var parts: Array = []
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		parts.append("%d  %s" % [i + 1, str(row.get("short_name", row.get("name", "")))])
	return "   ·   ".join(PackedStringArray(parts))


static func league_key_row(code: int, rows: Array) -> Dictionary:
	var pick := code - KEY_1
	if pick < 0 or pick >= rows.size():
		return {}
	return rows[pick]


static func picker_hints(picker, touch: bool, back_to_menu: bool) -> Array:
	var clubs := picker_clubs_line(picker)
	var gold := Color(0.96, 0.78, 0.30, 0.55)
	if touch:
		return [[-44.0, "TAP THE ARROWS TO CHANGE CLUBS  ·  TAP KICK OFF", 11, UiChrome.C_DIM],
			[-24.0, clubs, 10, gold]]


	var keys: String = picker_league_keys(competition_rows())
	var tail := "   ·   ESC  %s" % ("MENU" if back_to_menu else "BACK")
	return [[-64.0, "CLICK THE ARROWS OR USE  ← →  (HOME)   ·   ↑ ↓  (AWAY)", 11, UiChrome.C_DIM],
		[-44.0, (keys + tail) if keys != "" else "ESC  %s" % ("MENU" if back_to_menu else "BACK"),
			10, UiChrome.C_DIM],
		[-24.0, clubs, 10, gold]]


static func picker_clubs_line(picker) -> String:
	if str(picker.league_filter) != "":
		return picker.clubs_line(picker.ids.size(),
			PLRepository.shared().competition_name(str(picker.league_filter)))
	var names: Array = []
	for row in PLCompetitions.active():
		names.append(str(row.get("name", "")))
	if names.size() > 1:
		return picker.clubs_line(picker.ids.size(), " + ".join(PackedStringArray(names)))
	var name := str(TeamData.get_team(str(picker.home_id())).get("competition_name", ""))
	return picker.clubs_line(picker.ids.size(), name)


static func pinned_door(c: CanvasItem, cache: Dictionary, item: Dictionary,
		fonts: Dictionary) -> void:
	var rect: Rect2 = item["rect"]
	if str(item["kind"]) == "chip":
		UiChrome.chip(c, cache, rect, str(item["label"]), fonts["bold"])
	else:
		UiChrome.button(c, cache, rect, str(item["label"]), fonts["bold"],
			bool(item.get("primary", false)), -1, "", not bool(item.get("disabled", false)))


static func compact(vp: Vector2) -> bool:
	return vp.y < COMPACT_H


static func watch_pending(plan: Array) -> bool:
	for fx in plan:
		if int(fx.get("watched", 0)) == 1 and str(fx.get("status", "")) != "played":
			return true
	return false
