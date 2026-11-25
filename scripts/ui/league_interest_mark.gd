class_name LeagueInterestMark
extends RefCounted

## How a season paints Teams of Interest (#104): a followed club's name is gold
## wherever the sheets list clubs, and the game it plays states the rule in its
## chip instead of offering an AUTO/WATCH switch the shortlist would refuse.
##
## Kept beside the league sheets rather than inside one of them: the hub, its side
## table and the full table all read the same mark, and the sheets are at their
## size budgets.

## The followed ids as a set for one paint pass. The sheets get the ids in their
## view; the mark never reads the save.
static func set_of(ids: Array) -> Dictionary:
	var out := {}
	for id in ids:
		out[str(id)] = true
	return out

## The ink for one club's name: gold while the season follows it.
static func ink(interest: Dictionary, club_id: String) -> Color:
	return UiChrome.C_GOLD if interest.has(club_id) else UiChrome.C_TEXT

## True when either side of a fixture is one the season follows.
static func follows(interest: Dictionary, fx: Dictionary) -> bool:
	return interest.has(str(fx.get("home_club_id", ""))) or interest.has(str(fx.get("away_club_id", "")))

# gd-tools: no cover start

## The chip of a followed club's game: it states the rule rather than pretending
## to be a switch, so the surface never offers a press the rule would undo.
static func chip(c: CanvasItem, cache: Dictionary, rect: Rect2, bold: Font) -> void:
	UiChrome.panel(c, cache, rect, UiChrome.C_GOLD.darkened(0.15), 5, UiChrome.C_GOLD, 1)
	UiChrome.text_c(c, rect.get_center().x, rect.position.y + 14.0, "FOLLOWED", 9,
		Color(0.06, 0.06, 0.05), bold)

# gd-tools: no cover end
