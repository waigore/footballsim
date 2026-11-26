class_name LeagueChrome
extends RefCounted

## The chrome every league sheet shares: the header band's height, the bottom
## action bar, the compact reading's breakpoint, the zone colours and the one
## pending-watch test CONTINUE's caption reads.
##
## These bars used to be constants of `LeagueSheet`, the season hub, so every
## other pose — the front door, the table, the report, the body's own scroll
## window — imported the hub to learn where the header ends. The hub now reads
## them from here like everyone else: one module owns the shared bars, and no
## sheet depends on another's payload to find its own geometry.

## Air above a sheet's content: the header band, with BACK and the primary door.
const HEADER := 58.0
## The bottom action bar under the content (the table's reading doors, the
## podium's exits).
const BAR_H := 52.0
## Below this height the sheets take their compact reading.
const COMPACT_H := 620.0
## The planner's row pitch: the tightest a plan row gets, and the air under it.
const ROW_H := 26.0
const ROW_GAP := 5.0

## The zone band a league place falls in, in the table's own colours.
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

## A competition chip's caption: its short name when the chip can hold one,
## otherwise the competition's own code. Four leagues make five chips on a
## phone, where "2. BUNDESLIGA" would overflow a sixty-unit chip (#242).
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

## The picker's winner control (#249): a friendly is level at full time unless
## the player asks for a cup finish, which reuses the engine's own extra time and
## shootout path (#238). Two chips, the draw as the default, drawn under the
## cards so they never grow the sheet's fixed doors.
const WINNER_MODES: Array = [["draw", "ALLOW DRAW"], ["extra", "EXTRA TIME & PENS"]]
## The chip row's own height, and the air between it and the club cards.
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

## The lowest pixel the chip row reaches. The picker's fixed doors sit below it,
## so a short sheet places them against the control rather than over it: at
## 640x360 and 640x300 the doors used to cover both chips.
static func winner_bottom(card_bottom: float) -> float:
	return card_bottom + WINNER_GAP + WINNER_H

## The picker's KICK OFF and RANDOM doors, always below the winner control. They
## keep their own height and their air under them; what a short design space
## takes away is how far they rise, never the control they would cover.
static func picker_doors(vp: Vector2, card_bottom: float) -> Array:
	# A portrait handset is narrower than two 190-unit doors and the air between
	# them, so the pair is clamped to the sheet instead of running off it.
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

## The picker's footer captions, so the sheet's own script keeps its lines for
## layout and the words live in one place. Each entry is [dy, text, size, ink].
static func picker_hints(picker, touch: bool, back_to_menu: bool) -> Array:
	var clubs := picker_clubs_line(picker)
	var gold := Color(0.96, 0.78, 0.30, 0.55)
	if touch:
		return [[-44.0, "TAP THE ARROWS TO CHANGE CLUBS  ·  TAP KICK OFF", 11, UiChrome.C_DIM],
			[-24.0, clubs, 10, gold]]
	return [[-64.0, "CLICK THE ARROWS OR USE  ← →  (HOME)   ·   ↑ ↓  (AWAY)", 11, UiChrome.C_DIM],
		[-44.0, "ENTER  KICK OFF   ·   TAB  RANDOM   ·   1/2/3  LEAGUE   ·   ESC  %s"
			% ("MENU" if back_to_menu else "BACK"), 10, UiChrome.C_DIM],
		[-24.0, clubs, 10, gold]]

## "n clubs · league" for the footer, reading the picker's own filter.
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

## Paint one of the doors a sheet pinning in place (BACK, the primary door, the
## month chips, the table's reading doors). They are not part of the scrolling
## rows, so the body draws them itself with the host's paint grammar — button
## with the sheet's style cache, chip plain — above the content it clips.
static func pinned_door(c: CanvasItem, cache: Dictionary, item: Dictionary,
		fonts: Dictionary) -> void:
	var rect: Rect2 = item["rect"]
	if str(item["kind"]) == "chip":
		UiChrome.chip(c, cache, rect, str(item["label"]), fonts["bold"])
	else:
		UiChrome.button(c, cache, rect, str(item["label"]), fonts["bold"],
			bool(item.get("primary", false)), -1, "", not bool(item.get("disabled", false)))

## True on a window short enough for the sheets' compact reading (a landscape
## phone), where rows tighten and the hub drops its side table.
static func compact(vp: Vector2) -> bool:
	return vp.y < COMPACT_H

## True when today's plan still holds an unplayed watch, which is exactly when
## CONTINUE's caption has something to promise (#100). A played fixture stops
## counting the moment its result lands, whatever watch flag it kept (#124).
static func watch_pending(plan: Array) -> bool:
	for fx in plan:
		if int(fx.get("watched", 0)) == 1 and str(fx.get("status", "")) != "played":
			return true
	return false
