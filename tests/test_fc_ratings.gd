extends GdToolsTest


const PL_CARD := {
	"acceleration": 92, "sprint_speed": 95, "agility": 88, "balance": 70, "reactions": 90,
	"ball_control": 88, "dribbling": 90, "composure": 80, "crossing": 78, "curve": 76,
	"fk_accuracy": 62, "finishing": 88, "heading_accuracy": 60, "long_shots": 74,
	"long_passing": 66, "short_passing": 80, "shot_power": 80, "volleys": 72,
	"aggression": 55, "interceptions": 40, "positioning": 90, "vision": 82,
	"penalties": 74, "jumping": 62, "stamina": 78, "strength": 60,
	"marking_awareness": 30, "standing_tackle": 34, "sliding_tackle": 30,
	"gk_diving": 12, "gk_handling": 10, "gk_kicking": 14, "gk_positioning": 8, "gk_reflexes": 16,
}

const CB_CARD := {
	"acceleration": 62, "sprint_speed": 66, "agility": 54, "balance": 60, "reactions": 74,
	"ball_control": 62, "dribbling": 56, "composure": 74, "crossing": 48, "curve": 40,
	"fk_accuracy": 32, "finishing": 30, "heading_accuracy": 80, "long_shots": 40,
	"long_passing": 62, "short_passing": 68, "shot_power": 62, "volleys": 34,
	"aggression": 84, "interceptions": 84, "positioning": 76, "vision": 62,
	"penalties": 40, "jumping": 82, "stamina": 76, "strength": 86,
	"marking_awareness": 86, "standing_tackle": 88, "sliding_tackle": 82,
	"gk_diving": 10, "gk_handling": 12, "gk_kicking": 16, "gk_positioning": 9, "gk_reflexes": 11,
}


func test_the_model_ships_its_source_and_every_sub_stat() -> void:
	var book := FCRatings.model()
	assert_false(book.is_empty(), "the ratings model did not load")
	assert_true(str(book.get("source", "")).length() > 0, "the model carries no source")
	assert_eq(FCRatings.sub_stat_keys().size(), 34, "the sub-stat list is not the 34 FC fields")


func test_pace_is_fifty_five_sprint_and_forty_five_acceleration() -> void:
	var face := FCRatings.face_stats(PL_CARD)
	assert_eq(int(face["pace"]), 94, "pace is not the FC sprint/accel blend")
	var flat := PL_CARD.duplicate()
	flat["sprint_speed"] = 80
	flat["acceleration"] = 80
	assert_eq(int(FCRatings.face_stats(flat)["pace"]), 80, "equal sprint and accel did not derive to that value")


func test_every_face_bar_derives_from_the_pinned_weights() -> void:
	var face := FCRatings.face_stats(CB_CARD)
	for name in ["pace", "shooting", "passing", "dribbling", "defending", "physic"]:
		assert_true(face.has(name), "%s has no derivation" % name)
		assert_between(int(face[name]), 1, 99, "%s fell outside a card range" % name)


func test_overall_reads_the_position_not_the_label() -> void:
	var striker := FCRatings.overall(PL_CARD, "ST", 1)
	var centre_back := FCRatings.overall(CB_CARD, "LCB", 1)
	assert_gt(striker, centre_back, "a striker's sheet scored lower than a centre-back's")
	assert_gt(striker, 80, "an elite forward derived under 80")
	assert_gt(centre_back, 74, "a first-choice centre-back derived under 75")


func test_the_same_sheet_reads_differently_in_a_different_role() -> void:
	var as_keeper := FCRatings.overall(PL_CARD, "GK", 1)
	assert_lt(as_keeper, FCRatings.overall(PL_CARD, "ST", 1), "a keeper read the same as a striker")


func test_international_reputation_adds_one_at_four_and_above() -> void:
	var base := FCRatings.overall(CB_CARD, "CB", 1)
	assert_eq(FCRatings.overall(CB_CARD, "CB", 3), base, "reputation paid out below four")
	assert_eq(FCRatings.overall(CB_CARD, "CB", 4), base + 1, "reputation did not pay at four")
	assert_eq(FCRatings.overall(CB_CARD, "CB", 5), base + 1, "reputation paid more than once")


func test_the_keeper_face_bars_are_the_five_glove_stats_plus_pace() -> void:
	var glove := FCRatings.keeper_stats(CB_CARD)
	for key in ["div", "han", "kic", "ref", "spd"]:
		assert_true(glove.has(key), "the keeper card is missing %s" % key)
	assert_eq(int(glove["div"]), int(CB_CARD["gk_diving"]), "diving is not the glove stat")
	assert_eq(int(glove["ref"]), int(CB_CARD["gk_reflexes"]), "reflexes are not the glove stat")
	assert_eq(int(glove["spd"]), int(FCRatings.face_stats(CB_CARD)["pace"]), "keeper speed is not pace")


func test_synthesis_lands_near_the_club_baseline_and_stays_in_range() -> void:
	var strong := FCRatings.synthesize(82.0, "CM", 0)
	var weak := FCRatings.synthesize(64.0, "CM", 0)
	assert_gt(FCRatings.overall(strong, "CM", 1), FCRatings.overall(weak, "CM", 1),
		"a stronger club baseline did not synthesize a stronger card")
	for key in FCRatings.sub_stat_keys():
		assert_between(int(strong.get(key, 0)), 1, 99, "%s synthesized outside a card range" % key)


func test_synthesis_is_deterministic_for_a_given_name_wobble() -> void:
	var a := FCRatings.synthesize(74.0, "RW", 3)
	var b := FCRatings.synthesize(74.0, "RW", 3)
	assert_eq(a, b, "the same baseline and wobble synthesized two different sheets")


func test_a_keeper_synthesis_keeps_the_outfield_bars_low() -> void:
	var keeper := FCRatings.synthesize(74.0, "GK", 0)
	assert_lt(int(keeper["finishing"]), 45, "a synthesized keeper can finish")
	assert_gt(int(keeper["gk_reflexes"]), 60, "a synthesized keeper cannot save")
