class_name LeagueInterestMark
extends RefCounted


static func set_of(ids: Array) -> Dictionary:
	var out := {}
	for id in ids:
		out[str(id)] = true
	return out


static func ink(interest: Dictionary, club_id: String) -> Color:
	return UiChrome.C_GOLD if interest.has(club_id) else UiChrome.C_TEXT


static func follows(interest: Dictionary, fx: Dictionary) -> bool:
	return interest.has(str(fx.get("home_club_id", ""))) or interest.has(str(fx.get("away_club_id", "")))

# gd-tools: no cover start


static func chip(c: CanvasItem, cache: Dictionary, rect: Rect2, bold: Font) -> void:
	UiChrome.panel(c, cache, rect, UiChrome.C_GOLD.darkened(0.15), 5, UiChrome.C_GOLD, 1)
	UiChrome.text_c(c, rect.get_center().x, rect.position.y + 14.0, "FOLLOWED", 9,
		Color(0.06, 0.06, 0.05), bold)

# gd-tools: no cover end
