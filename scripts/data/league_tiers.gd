class_name LeagueTiers
extends RefCounted


const TIERS := {
	"England": ["PL", "CH", "L1", "L2", "NL"],
	"Spain": ["LL"],
	"Germany": ["BL", "BL2"],
}


static func order() -> Array:
	var out: Array = []
	for country in TIERS.keys():
		out.append_array(TIERS[country])
	return out


static func countries() -> Array:
	return TIERS.keys()


static func chain(country: String) -> Array:
	return (TIERS.get(country, []) as Array).duplicate()


static func country_of(competition_id: String) -> String:
	for country in TIERS.keys():
		if (TIERS[country] as Array).has(competition_id):
			return str(country)
	return ""


static func tier_of(competition_id: String) -> int:
	var country := country_of(competition_id)
	if country == "":
		return -1
	return (TIERS[country] as Array).find(competition_id)


static func above(competition_id: String) -> String:
	var country := country_of(competition_id)
	var tier := tier_of(competition_id)
	if country == "" or tier <= 0:
		return ""
	return str((TIERS[country] as Array)[tier - 1])


static func below(competition_id: String) -> String:
	var country := country_of(competition_id)
	var tier := tier_of(competition_id)
	if country == "" or tier < 0 or tier + 1 >= (TIERS[country] as Array).size():
		return ""
	return str((TIERS[country] as Array)[tier + 1])


static func close_up(wanted: Array) -> Array:
	var keep := {}
	for entry in wanted:
		var cid := str(entry)
		if country_of(cid) == "":
			keep[cid] = true
			continue
		var chain_ids := chain(country_of(cid))
		for i in range(tier_of(cid) + 1):
			keep[str(chain_ids[i])] = true
	var out: Array = []
	for cid in order():
		if keep.has(cid):
			out.append(cid)
	return out


static func pairs(actives: Array) -> Array:
	var out: Array = []
	for country in TIERS.keys():
		var chain_ids: Array = TIERS[country]
		for i in range(chain_ids.size() - 1):
			var top := str(chain_ids[i])
			var bottom := str(chain_ids[i + 1])
			if actives.has(top) and actives.has(bottom):
				out.append([top, bottom])
	return out


static func cascading_on(chosen: Array, competition_id: String) -> Array:
	var wanted: Array = chosen.duplicate()
	var country := country_of(competition_id)
	if country == "":
		if not wanted.has(competition_id):
			wanted.append(competition_id)
		return wanted
	var chain_ids := chain(country)
	for i in range(tier_of(competition_id) + 1):
		var cid := str(chain_ids[i])
		if not wanted.has(cid):
			wanted.append(cid)
	return wanted


static func cascading_off(chosen: Array, competition_id: String) -> Array:
	var country := country_of(competition_id)
	var doomed := {competition_id: true}
	if country != "":
		for i in range(tier_of(competition_id), chain(country).size()):
			doomed[str(chain(country)[i])] = true
	var out: Array = []
	for entry in chosen:
		if not doomed.has(str(entry)):
			out.append(str(entry))
	return out
