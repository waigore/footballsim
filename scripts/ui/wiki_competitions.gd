class_name WikiCompetitions
extends RefCounted

## The competition blocks the encyclopedia draws as chips: the index of every
## competition one file carries, and the single chip that ties a club or player
## to the competition they play in.
##
## Kept out of `WikiModel` so the page data stays one concern per module: a
## competition query and its block shape live here, and the pages only ask for
## the block they need. Nothing here is hard-coded to a league.

const ACCENT := "#f7c948"

## The index: one chip per competition. The page's own competition is the badge
## it is reading (accented, no target: a press there would open the page under
## the press); every other chip is the door to that competition's hub. With the
## shipped seed it is a single badge; a two-league seed (PL + La Liga) turns it
## into the encyclopedia's league index.
static func index(active_id: String) -> Dictionary:
	var items: Array = []
	for comp in PLCompetitions.all():
		var id := str(comp["id"])
		var item := {
			"text": str(comp["short_name"]).to_upper(),
			"accent": ACCENT if id == active_id else "",
		}
		if id != active_id:
			item["target"] = {"page": WikiModel.LEAGUE, "id": id}
		items.append(item)
	return {"k": "chips", "items": items}

## The link a club or player page carries: "this is the competition I play in".
## Empty (no items, no height) when the file carries no such competition.
static func link(competition_id: String) -> Dictionary:
	var comp := PLCompetitions.one(competition_id)
	if comp.is_empty():
		return {"k": "chips", "items": []}
	return {"k": "chips", "items": [{
		"text": str(comp["short_name"]).to_upper(),
		"target": {"page": WikiModel.LEAGUE, "id": str(comp["id"])},
		"accent": ACCENT,
	}]}
