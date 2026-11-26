class_name LeagueTiers
extends RefCounted

## The linked-tier graph: which competition sits above which (#258/#260).
##
## A country's competitions are one chain, top flight first. A save may run any
## contiguous run of a chain — the Premier League alone, the whole English
## pyramid, the German pair — because a lower tier only means something when the
## tier above it is playing. Two rules read this graph:
##
## - The New League wizard turns on a lower tier's whole chain above it, and
##   turning a tier off clears it and everything below it (#261).
## - The end of a season swaps clubs only between adjacent *active* tiers, so
##   the deepest active tier's drop has nowhere to go and simply stays (the
##   National League's bottom four read RELEGATED).
##
## The order here is the one every surface publishes: the season's fixture
## order, the hub's league chips, the wizard's country groups. It is the shipped
## pyramid, not a per-save setting, so a save created before a tier shipped
## reads exactly as it did.

const TIERS := {
	"England": ["PL", "CH", "L1", "L2", "NL"],
	"Spain": ["LL"],
	"Germany": ["BL", "BL2"],
}

## Every competition, each country's tiers top-down, in publication order.
static func order() -> Array:
	var out: Array = []
	for country in TIERS.keys():
		out.append_array(TIERS[country])
	return out

## The countries, in the order the wizard lists them.
static func countries() -> Array:
	return TIERS.keys()

## One country's chain, top flight first.
static func chain(country: String) -> Array:
	return (TIERS.get(country, []) as Array).duplicate()

## The country a competition plays in, or "" when the graph does not know it.
static func country_of(competition_id: String) -> String:
	for country in TIERS.keys():
		if (TIERS[country] as Array).has(competition_id):
			return str(country)
	return ""

## The competition's place in its own chain: 0 is the top flight, -1 unknown.
static func tier_of(competition_id: String) -> int:
	var country := country_of(competition_id)
	if country == "":
		return -1
	return (TIERS[country] as Array).find(competition_id)

## The tier directly above a competition, or "" at the top of a chain.
static func above(competition_id: String) -> String:
	var country := country_of(competition_id)
	var tier := tier_of(competition_id)
	if country == "" or tier <= 0:
		return ""
	return str((TIERS[country] as Array)[tier - 1])

## The tier directly below a competition, or "" at the bottom of a chain.
static func below(competition_id: String) -> String:
	var country := country_of(competition_id)
	var tier := tier_of(competition_id)
	if country == "" or tier < 0 or tier + 1 >= (TIERS[country] as Array).size():
		return ""
	return str((TIERS[country] as Array)[tier + 1])

## The asked-for set with every tier above each member turned on as well, in
## publication order: the wizard's "turning a lower tier on" rule, and the rule
## a season creation closes over when a caller names a lower tier by hand.
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

## The adjacent active pairs, top tier first: the only joins a season's
## membership swap may use.
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

## The set a cascade-on leaves: the tier itself plus every tier above it in its
## own country, nothing else changed.
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

## The set a cascade-off leaves: that tier and every tier below it in its own
## country. A tier with no chain (an unknown id) is simply dropped.
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
