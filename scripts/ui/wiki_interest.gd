class_name WikiInterest
extends RefCounted

## Teams of Interest on the encyclopedia: which club a press landed on, the
## context menu for it, and the toggle that writes through to the open league
## save. With no season open every call is a no-op, so the encyclopedia's pages
## never offer interest the player cannot use.

static func team_at(screen, p: Vector2) -> String:
	if screen == null or screen.body == null or LeagueSeason.active == null:
		return ""
	var top: Dictionary = screen.current()
	if str(top.get("page", "")) == WikiModel.TEAM:
		# The page's own title is a team name even though it is painted chrome.
		var br: Rect2 = screen.body_rect(screen.design_vp())
		if Rect2(0.0, 0.0, br.position.x + br.size.x, br.position.y).has_point(p):
			return str(top.get("id", ""))
	var target: Dictionary = screen.body.hit(p)
	if str(target.get("page", "")) == WikiModel.TEAM:
		return str(target.get("id", ""))
	return ""

## Raise the menu over the club under the press. Returns false when there is no
## club there (the host then treats the press as an ordinary tap).
static func open(screen, p: Vector2) -> bool:
	var club := team_at(screen, p)
	if club == "":
		return false
	screen.menu.show_at(club, str(PLRepository.shared().club(club).get("name", club)), p)
	screen.queue_redraw()
	return true

static func toggle(screen) -> void:
	if screen == null:
		return
	var season := LeagueSeason.active
	if season == null or season.interest == null or str(screen.menu.club_id) == "":
		screen.menu.hide()
		screen.queue_redraw()
		return
	var club := str(screen.menu.club_id)
	season.interest.set_interest(club, not season.interest.has(club))
	season.dirty = true
	screen.menu.hide()
	screen.queue_redraw()
