class_name WikiInterest
extends RefCounted


const W := 132.0
const GAP := 8.0


static func target(top: Dictionary, season) -> String:
	if season == null or season.record == null:
		return ""
	if str(top.get("page", "")) != WikiModel.TEAM:
		return ""
	return str(top.get("id", ""))


static func followed_set(season) -> Dictionary:
	if season == null:
		return {}
	return LeagueInterestMark.set_of(season.state().get("interests", []))

static func followed(season, club_id: String) -> bool:
	if season == null or season.record == null or club_id == "":
		return false
	return season.record.interest.is_interested(club_id)


static func label(season, club_id: String) -> String:
	return "FOLLOWING" if followed(season, club_id) else "FOLLOW"


static func rect(vp: Vector2, back_rect: Rect2, close_rect: Rect2) -> Rect2:
	var r := Rect2(close_rect.position.x - W - GAP, back_rect.position.y, W, back_rect.size.y)
	if r.position.x < back_rect.end.x + GAP or r.end.x > vp.x:
		return Rect2()
	return r


static func draw(c: CanvasItem, font: Font, r: Rect2, text: String, followed: bool,
		hovered: bool) -> void:
	if followed:
		WikiChrome.box(c, Color(0.96, 0.78, 0.30, 0.16), r, 8, Color(0.96, 0.78, 0.30, 0.55))
		WikiChrome.label_c(c, font, r.get_center().x, r.position.y + r.size.y * 0.66, text, 13,
			WikiChrome.GOLD)
		return
	WikiChrome.button(c, font, r, text, hovered)


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
