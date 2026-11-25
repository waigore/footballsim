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
	if band == "relegation":
		return UiChrome.C_DANGER
	return UiChrome.C_DIM

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
