class_name WikiCompetitions
extends RefCounted


const ACCENT := "#f7c948"


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


static func link(competition_id: String) -> Dictionary:
	var comp := PLCompetitions.one(competition_id)
	if comp.is_empty():
		return {"k": "chips", "items": []}
	return {"k": "chips", "items": [{
		"text": str(comp["short_name"]).to_upper(),
		"target": {"page": WikiModel.LEAGUE, "id": str(comp["id"])},
		"accent": ACCENT,
	}]}
