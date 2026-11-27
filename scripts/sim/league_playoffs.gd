class_name LeaguePlayoffs
extends RefCounted

## The English promotion play-offs (#258/#260): a mini-tournament inside one
## division whose winner takes the last promotion place above it.
##
## Every bracket is settled from the save's own seed with the season's Poisson
## model, so a save settles the same bracket the same way every time — the lane
## the German Relegation already uses. A play-off is not a league fixture:
## nothing here writes a fixture row, moves a table or starts a second season;
## the settled reading rides the season's podium and the membership swap.
##
## The bracket is named by `league_rules.playoff_format` and sized by
## `promotion_playoff_places` (the places it draws from, starting right under the
## automatic promotion places):
##
## | Format | Places | Shape |
## |--------|-------:|-------|
## | `four_two_leg` | 4 | semi-finals 1v4 and 2v3 over two legs, then a one-off final |
## | `six_two_leg` | 6 | one-leg eliminators 3v6 and 4v5, two-leg semis for 1st and 2nd, one-off final |
## | `six_one_leg` | 6 | every round one leg: eliminators 3v6 and 4v5, semis, final |
##
## The higher-placed club hosts a one-leg match and the second leg of a two-leg
## tie. A level tie goes to extra time (half an hour at a third of the fixture's
## own expected goals) and then to penalties, by the shared shootout lane.

## A save settles only a bracket whose tier above is playing too: a play-off
## with nowhere to promote is not worth the games.
##   `season` — the finished season; `competition_id` — the tier that owns the
##   bracket. Empty until the tier and its neighbour are both active and the
##   calendar is played out.
static func runs(season: LeagueSeason, competition_id: String) -> bool:
	if season == null or season.save == null or season.record == null:
		return false
	var actives: Array = season.save.actives
	if not actives.has(competition_id) or LeagueTiers.above(competition_id) == "":
		return false
	if not actives.has(LeagueTiers.above(competition_id)):
		return false
	return season.record.fixtures.unplayed() == 0

## Every bracket this save settles, keyed by the tier that owns it.
static func build_all(season: LeagueSeason) -> Dictionary:
	var out := {}
	if season == null or season.save == null:
		return out
	for cid in season.save.actives:
		var bracket := build(season, str(cid))
		if not bracket.is_empty():
			out[str(cid)] = bracket
	return out

## The bracket's shape: how many places it draws, and how many legs each round
## plays for the formats that play some rounds one-legged.
const FORMATS := {
	"four_two_leg": {"places": 4, "eliminators": false, "semi_legs": 2},
	"six_two_leg": {"places": 6, "eliminators": true, "semi_legs": 2},
	"six_one_leg": {"places": 6, "eliminators": true, "semi_legs": 1},
}

## One tier's bracket, or {} when the save does not settle it.
static func build(season: LeagueSeason, competition_id: String) -> Dictionary:
	if not runs(season, competition_id):
		return {}
	var rules := season.save.rules_for(competition_id)
	var format := str(rules.get("playoff_format", ""))
	if not FORMATS.has(format):
		return {}
	var need := int((FORMATS[format] as Dictionary)["places"])
	var places := int(rules.get("promotion_playoff_places", 0))
	if places < need:
		return {}
	var seeds := _seeds(season, competition_id, int(rules.get("promotion_places", 0)), places)
	if seeds.size() < need:
		return {}
	var rounds: Array = []
	var winner := ""
	if format == "four_two_leg":
		var semis := [
			_tie(season, competition_id, "SEMI-FINAL 1", seeds[0], seeds[3], 2),
			_tie(season, competition_id, "SEMI-FINAL 2", seeds[1], seeds[2], 2),
		]
		rounds.append({"name": "SEMI-FINALS", "ties": semis})
		var final := _tie(season, competition_id, "FINAL",
			_side(seeds, str(semis[0]["winner_club_id"])),
			_side(seeds, str(semis[1]["winner_club_id"])), 1)
		rounds.append({"name": "FINAL", "ties": [final]})
		winner = str(final["winner_club_id"])
	else:
		var semis_legs := 2 if format == "six_two_leg" else 1
		var elims := [
			_tie(season, competition_id, "ELIMINATOR 1", seeds[2], seeds[5], 1),
			_tie(season, competition_id, "ELIMINATOR 2", seeds[3], seeds[4], 1),
		]
		rounds.append({"name": "ELIMINATORS", "ties": elims})
		# The better-placed semi-finalist meets the worse-placed eliminator
		# winner, which is the shape the EFL and the National League both use.
		var semis := [
			_tie(season, competition_id, "SEMI-FINAL 1", seeds[0],
				_side(seeds, str(elims[1]["winner_club_id"])), semis_legs),
			_tie(season, competition_id, "SEMI-FINAL 2", seeds[1],
				_side(seeds, str(elims[0]["winner_club_id"])), semis_legs),
		]
		rounds.append({"name": "SEMI-FINALS", "ties": semis})
		var final := _tie(season, competition_id, "FINAL",
			_side(seeds, str(semis[0]["winner_club_id"])),
			_side(seeds, str(semis[1]["winner_club_id"])), 1)
		rounds.append({"name": "FINAL", "ties": [final]})
		winner = str(final["winner_club_id"])
	var final_tie: Dictionary = (rounds[rounds.size() - 1]["ties"] as Array)[0]
	var loser := str(final_tie["home"]) if str(final_tie["winner_club_id"]) == str(final_tie["away"]) \
		else str(final_tie["away"])
	return {
		"id": "playoffs:" + competition_id,
		"competition": competition_id,
		"format": format,
		"name": "%s — PLAY-OFFS" % PLRepository.shared().competition_name(competition_id),
		"rounds": rounds,
		"winner_club_id": winner,
		"winner_club": _club_name(winner),
		"runner_up_club_id": loser,
		"runner_up_club": _club_name(loser),
		"text": "%s beat %s in the final" % [_club_name(winner), _club_name(loser)],
	}

## The clubs a bracket draws from, best placed first, with the place they
## finished in.
static func _seeds(season: LeagueSeason, competition_id: String, up: int,
		places: int) -> Array:
	var table: Array = season.record.standings.table(competition_id)
	var out: Array = []
	for i in range(up, mini(up + places, table.size())):
		var row: Dictionary = table[i]
		out.append({
			"club_id": str(row["club_id"]), "name": str(row["club_name"]),
			"position": i + 1,
		})
	return out

## A seed by club id, or the last seed when the id is unknown (never expected:
## a bracket only ever meets its own winners).
static func _side(seeds: Array, club_id: String) -> Dictionary:
	for seed in seeds:
		if str((seed as Dictionary)["club_id"]) == club_id:
			return seed
	return seeds[seeds.size() - 1]

## One tie of the bracket: `legs` matches, the higher-placed side listed as
## `home` and hosting the second leg. A level tie is settled by extra time and
## then penalties, and the result carries both.
static func _tie(season: LeagueSeason, competition_id: String, label: String,
		high: Dictionary, low: Dictionary, legs: int) -> Dictionary:
	var seed := _tie_seed(season, competition_id, label, str(high["club_id"]), str(low["club_id"]))
	var played: Array = []
	var high_goals := 0
	var low_goals := 0
	for i in range(legs):
		var high_home := i == 1 or legs == 1
		var home := str(high["club_id"]) if high_home else str(low["club_id"])
		var away := str(low["club_id"]) if high_home else str(high["club_id"])
		var score := _ninety(seed + 1301 + i * 977, home, away)
		var leg := {
			"leg": i + 1, "home": home, "away": away,
			"home_name": _club_name(home), "away_name": _club_name(away),
			"home_goals": score.x, "away_goals": score.y,
		}
		played.append(leg)
		high_goals += score.x if high_home else score.y
		low_goals += score.y if high_home else score.x
	var extra_time := false
	var pens := Vector2i(-1, -1)
	var decided := "aggregate"
	var winner := ""
	if high_goals == low_goals:
		var final_leg: Dictionary = played[played.size() - 1]
		var et := _extra_time(seed + 4177, str(final_leg["home"]), str(final_leg["away"]))
		extra_time = true
		final_leg["home_goals"] = int(final_leg["home_goals"]) + et.x
		final_leg["away_goals"] = int(final_leg["away_goals"]) + et.y
		final_leg["extra_time"] = true
		if str(final_leg["home"]) == str(high["club_id"]):
			high_goals += et.x
			low_goals += et.y
		else:
			low_goals += et.x
			high_goals += et.y
		decided = "extra time"
		if high_goals == low_goals:
			pens = LeagueShootout.settle(seed + 7717, str(high["club_id"]), str(low["club_id"]))
			decided = "penalties"
			winner = str(high["club_id"]) if pens.x > pens.y else str(low["club_id"])
		else:
			winner = str(high["club_id"]) if high_goals > low_goals else str(low["club_id"])
	else:
		winner = str(high["club_id"]) if high_goals > low_goals else str(low["club_id"])
	var loser := str(low["club_id"]) if winner == str(high["club_id"]) else str(high["club_id"])
	return {
		"label": label, "home": str(high["club_id"]), "away": str(low["club_id"]),
		"home_name": str(high["name"]), "away_name": str(low["name"]),
		"home_position": int(high["position"]), "away_position": int(low["position"]),
		"legs": played, "home_goals": high_goals, "away_goals": low_goals,
		"pens_home": pens.x, "pens_away": pens.y, "extra_time": extra_time,
		"decided_by": decided, "winner_club_id": winner, "winner_club": _club_name(winner),
		"loser_club_id": loser,
		"text": _tie_text(high, low, high_goals, low_goals, pens),
	}

## One ninety-minute sample from the season's own model.
static func _ninety(seed: int, home: String, away: String) -> Vector2i:
	return PoissonModel.new(seed, home, away).sample()

## Half an hour of extra time: a third of the fixture's expected goals, so a
## tie decided in extra time reads at the same level as the game it followed.
static func _extra_time(seed: int, home: String, away: String) -> Vector2i:
	var goals := PoissonModel.new(seed, home, away).expected_goals()
	return Vector2i(_poisson_draw(seed + 31, goals.x / 3.0),
		_poisson_draw(seed + 61, goals.y / 3.0))

static func _poisson_draw(seed: int, mean: float) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var u := rng.randf()
	var term := exp(-mean)
	var acc := term
	var k := 0
	while u > acc and k < 8:
		k += 1
		term *= mean / float(k)
		acc += term
	return k

## A tie's seed: the season's own seed folded with the bracket and pairing, so
## the same save settles the same tie and two brackets never share a draw.
static func _tie_seed(season: LeagueSeason, competition_id: String, label: String,
		high_id: String, low_id: String) -> int:
	var key := "%s|%s|%s|%s" % [competition_id, label, high_id, low_id]
	var h := 0
	for i in range(key.length()):
		h = int((h * 31 + key.unicode_at(i)) % 2147483647)
	return int(season.rng.seed) + h

static func _tie_text(high: Dictionary, low: Dictionary, high_goals: int, low_goals: int,
		pens: Vector2i) -> String:
	var line := "%s %d – %d %s" % [str(high["name"]), high_goals, low_goals, str(low["name"])]
	if pens.x >= 0:
		line += " (%d–%d pens)" % [pens.x, pens.y]
	elif high_goals == low_goals:
		line += " (extra time)"
	return line

static func _club_name(club_id: String) -> String:
	return str(PLRepository.shared().club(club_id).get("name", club_id))
