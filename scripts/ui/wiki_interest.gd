class_name WikiInterest
extends RefCounted

## The follow door a team page carries while a league season is open (#104):
## marking a club there is how the player puts that club's games on Watch from
## the page they were already reading. Interest is the season's own shortlist, so
## this module only names the door, places it and paints it; the season owns the
## rule. Kept out of the screen script, which is at its method budget.

## Width of the door; it sits left of the sheet's ✕ on the header row.
const W := 132.0
const GAP := 8.0

## The club whose page would carry the door, or "" when there is none: only a
## team page inside a loaded season names a club the shortlist can hold.
static func target(top: Dictionary, season) -> String:
	if season == null or season.record == null:
		return ""
	if str(top.get("page", "")) != WikiModel.TEAM:
		return ""
	return str(top.get("id", ""))

static func followed(season, club_id: String) -> bool:
	if season == null or season.record == null or club_id == "":
		return false
	return season.record.interest.is_interested(club_id)

## "FOLLOW" before the club is marked, "FOLLOWING" while it is.
static func label(season, club_id: String) -> String:
	return "FOLLOWING" if followed(season, club_id) else "FOLLOW"

## The door's rect on the header row, left of the sheet's ✕. Empty when the
## window is too narrow for it to clear BACK: the sheet keeps BACK and ✕ rather
## than putting two tap targets on top of one another.
static func rect(vp: Vector2, back_rect: Rect2, close_rect: Rect2) -> Rect2:
	var r := Rect2(close_rect.position.x - W - GAP, back_rect.position.y, W, back_rect.size.y)
	if r.position.x < back_rect.end.x + GAP or r.end.x > vp.x:
		return Rect2()
	return r

## Gold while the club is followed — the same interest mark its name carries on
## the season's lists — and the quiet sheet door before that.
static func draw(c: CanvasItem, font: Font, r: Rect2, text: String, followed: bool,
		hovered: bool) -> void:
	if followed:
		WikiChrome.box(c, Color(0.96, 0.78, 0.30, 0.16), r, 8, Color(0.96, 0.78, 0.30, 0.55))
		WikiChrome.label_c(c, font, r.get_center().x, r.position.y + r.size.y * 0.66, text, 13,
			WikiChrome.GOLD)
		return
	WikiChrome.button(c, font, r, text, hovered)

## The door a page carries — its id, rect, wording and whether the season follows
## the club — or {} when the page carries none. Pure, so the sheet's paint and the
## suite read the same answer, and the screen only places what this decides.
static func door(top: Dictionary, season, vp: Vector2, back_rect: Rect2,
		close_rect: Rect2) -> Dictionary:
	var club_id := target(top, season)
	if club_id == "":
		return {}
	var r := rect(vp, back_rect, close_rect)
	if r.size.x <= 0.0:
		return {}
	return {"id": "interest:" + club_id, "club_id": club_id, "rect": r,
		"text": label(season, club_id), "followed": followed(season, club_id)}
