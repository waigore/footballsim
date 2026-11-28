class_name WikiCompetitions
extends RefCounted


const ACCENT := "#f7c948"

const SHORT := {
	"BL": "BL", "BL2": "2.BL", "CH": "CHAMP", "LL": "LA LIGA",
	"L1": "L1", "L2": "L2", "NL": "NL", "PL": "PL", "SA": "SERIE A", "SB": "SERIE B",
	"UCL": "UCL", "UEL": "UEL", "UECL": "UECL",
}


static func index(active_id: String) -> Dictionary:
	var items: Array = []
	for comp in PLCompetitions.all():
		var id := str(comp["id"])
		var item := {
			"text": str(comp["short_name"]).to_upper(),
			"short": str(SHORT.get(id, str(comp["short_name"]).to_upper())),
			"accent": ACCENT if id == active_id else "",
		}
		if id != active_id:
			item["target"] = {"page": WikiModel.LEAGUE, "id": id}
		items.append(item)
	for comp in PLRepository.shared().continentals():
		var id := str(comp.get("id", ""))
		if not PLCompetitions.season_owns(id):
			continue
		var item := {
			"text": str(comp.get("short_name", id)).to_upper(),
			"short": str(SHORT.get(id, id)),
			"accent": ACCENT if id == active_id else "",
		}
		if id != active_id:
			item["target"] = {"page": WikiModel.LEAGUE, "id": id}
		items.append(item)
	for comp in PLRepository.shared().cups():
		var cid := str(comp.get("id", ""))
		if cid == "" or not LeagueCup.is_cup(cid):
			continue
		var cup_item := {
			"text": str(comp.get("short_name", cid)).to_upper(),
			"short": str(SHORT.get(cid, str(comp.get("short_name", cid)).to_upper())),
			"accent": ACCENT if cid == active_id else "",
		}
		if cid != active_id:
			cup_item["target"] = {"page": WikiModel.CUP, "id": cid}
		items.append(cup_item)
	return {"k": "chips", "strip": true, "items": items}


static func link(competition_id: String) -> Dictionary:
	var comp := PLCompetitions.one(competition_id)
	if comp.is_empty():
		return {"k": "chips", "items": []}
	return {"k": "chips", "items": [{
		"text": str(comp["short_name"]).to_upper(),
		"target": {"page": WikiModel.LEAGUE, "id": str(comp["id"])},
		"accent": ACCENT,
	}]}
