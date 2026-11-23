extends GdToolsTest

## Attribute mapping: the one table that turns EA FC ratings into simulation
## quantities. Every mapping is asserted at both ends of the scale so a tuning
## change cannot silently invert a curve.

class Stub:
	var attr := {}
	var gk := {}
	func _init(a: Dictionary, g: Dictionary = {}) -> void:
		attr = a
		gk = g

func _p(pac: int, sho: int, pas: int, dri: int, def: int, phy: int, height: int = 180) -> Stub:
	return Stub.new({"ovr": 70, "pac": pac, "sho": sho, "pas": pas, "dri": dri,
		"def": def, "phy": phy, "height": height})

func _keeper(div: int, han: int, kic: int, ref: int, spd: int) -> Stub:
	return Stub.new({"ovr": 70, "pac": 50, "sho": 20, "pas": 50, "dri": 40, "def": 20,
		"phy": 60, "height": 190}, {"div": div, "han": han, "kic": kic, "ref": ref, "spd": spd})

func test_pace_drives_speed_and_acceleration() -> void:
	var slow := _p(40, 50, 50, 50, 50, 50)
	var fast := _p(95, 50, 50, 50, 50, 50)
	assert_lt(Attrs.max_speed(slow), Attrs.max_speed(fast), "pace does not raise top speed")
	assert_lt(Attrs.accel(slow), Attrs.accel(fast), "pace does not raise acceleration")
	assert_almost_eq(Attrs.max_speed(fast), 5.0 + pow(0.95, 2.0) * 4.0, 0.001)
	assert_almost_eq(Attrs.accel(fast), 3.0 + 0.95 * 3.4, 0.001)

func test_physicality_drives_deceleration_and_strength() -> void:
	var light := _p(50, 50, 50, 50, 50, 30)
	var heavy := _p(50, 50, 50, 50, 50, 90)
	assert_lt(Attrs.decel(light), Attrs.decel(heavy), "strength does not slow a body down")
	assert_lt(Attrs.strength(light), Attrs.strength(heavy), "physicality does not raise strength")
	assert_almost_eq(Attrs.decel(heavy), 6.5 + 90.0 * 0.02, 0.001)

func test_dribbling_raises_touch_control_and_carry_speed() -> void:
	var clumsy := _p(60, 50, 50, 30, 50, 50)
	var silky := _p(60, 50, 50, 95, 50, 50)
	assert_lt(Attrs.dribble_speed(clumsy), Attrs.dribble_speed(silky), "dribbling does not raise carry speed")
	assert_lt(Attrs.control_radius(clumsy), Attrs.control_radius(silky), "dribbling does not widen control")
	assert_lt(Attrs.first_touch_quality(clumsy), Attrs.first_touch_quality(silky), "dribbling does not improve the first touch")
	assert_gt(Attrs.dribble_speed(silky), 0.0, "carry speed must be positive")

func test_passing_accuracy_and_pace() -> void:
	var poor := _p(50, 50, 30, 50, 50, 50)
	var elite := _p(50, 50, 95, 50, 50, 50)
	assert_gt(Attrs.pass_sigma_deg(poor, 20.0, 0.0), Attrs.pass_sigma_deg(elite, 20.0, 0.0),
		"a weaker passer is not less accurate")
	assert_gt(Attrs.pass_sigma_deg(elite, 40.0, 0.0), Attrs.pass_sigma_deg(elite, 10.0, 0.0),
		"distance does not widen the pass cone")
	assert_gt(Attrs.pass_sigma_deg(elite, 20.0, 0.8), Attrs.pass_sigma_deg(elite, 20.0, 0.0),
		"pressure does not widen the pass cone")
	assert_gt(Attrs.pass_speed_for(elite, 30.0), Attrs.pass_speed_for(elite, 5.0),
		"a longer pass is not hit harder")

func test_shooting_accuracy_and_power() -> void:
	var blunt := _p(50, 30, 50, 50, 50, 50)
	var lethal := _p(50, 95, 50, 50, 50, 50)
	assert_gt(Attrs.shot_sigma_deg(blunt, 18.0, 0.0), Attrs.shot_sigma_deg(lethal, 18.0, 0.0),
		"a weaker shooter is not less accurate")
	assert_gt(Attrs.shot_sigma_deg(lethal, 18.0, 0.7), Attrs.shot_sigma_deg(lethal, 18.0, 0.0),
		"pressure does not widen the shot cone")
	assert_gt(Attrs.shot_speed(lethal), Attrs.shot_speed(blunt), "shooting does not raise shot speed")
	assert_gt(Attrs.shot_speed(lethal, 1.2), Attrs.shot_speed(lethal, 1.0), "power does not raise shot speed")

func test_defending_and_aerial_duels() -> void:
	var weak := _p(50, 50, 50, 50, 20, 40, 170)
	var tower := _p(50, 50, 50, 50, 90, 90, 195)
	assert_lt(Attrs.tackle_skill(weak), Attrs.tackle_skill(tower), "defending does not raise tackle skill")
	assert_lt(Attrs.aerial(weak), Attrs.aerial(tower), "height and strength do not win headers")
	assert_lte(Attrs.aerial(tower), 1.0, "aerial rating must stay in 0..1")
	assert_gte(Attrs.aerial(weak), 0.0, "aerial rating must stay in 0..1")

func test_stamina_drain_follows_effort_and_physicality() -> void:
	var fit := _p(80, 50, 50, 50, 50, 95)
	var tired := _p(80, 50, 50, 50, 50, 30)
	var jog: float = Attrs.stamina_drain(fit, 2.0, 1.0)
	var sprint: float = Attrs.stamina_drain(fit, 9.0, 1.0)
	assert_gt(sprint, jog, "sprinting does not cost more than jogging")
	assert_lt(Attrs.stamina_drain(fit, 9.0, 1.0), Attrs.stamina_drain(tired, 9.0, 1.0),
		"a stronger player drains as fast as a weak one")

func test_keeper_ratings_map_to_reach_reaction_and_hands() -> void:
	var poor := _keeper(30, 30, 40, 30, 60)
	var elite := _keeper(95, 95, 90, 95, 70)
	assert_lt(Attrs.gk_reach(poor), Attrs.gk_reach(elite), "reflexes do not raise reach")
	assert_lt(Attrs.gk_dive_reach(poor), Attrs.gk_dive_reach(elite), "diving does not raise dive reach")
	assert_gt(Attrs.gk_reaction(poor), Attrs.gk_reaction(elite), "a better keeper does not react sooner")
	assert_lt(Attrs.gk_handling(poor), Attrs.gk_handling(elite), "handling does not raise catch chance")
	assert_gte(Attrs.gk_reaction(elite), 0.10, "reaction time must stay positive")

func test_role_helpers_classify_every_line() -> void:
	for role in ["RB", "LB", "CB", "RCB", "LCB", "RWB", "LWB"]:
		assert_true(Attrs.is_defender(role), role + " is not read as a defender")
	for role in ["CDM", "RDM", "LDM", "CM", "RM", "LM", "CAM"]:
		assert_true(Attrs.is_mid(role), role + " is not read as a midfielder")
	for role in ["RW", "LW", "ST", "CF"]:
		assert_true(Attrs.is_forward(role), role + " is not read as a forward")
	for role in ["RB", "LB", "RWB", "LWB", "RW", "LW", "RM", "LM"]:
		assert_true(Attrs.is_wide(role), role + " is not read as a wide player")
	assert_true(Attrs.is_gk("GK"), "GK is not read as a keeper")
	assert_false(Attrs.is_gk("CB"), "a centre-back is read as a keeper")
	assert_false(Attrs.is_forward("CB"), "a centre-back is read as a forward")

func test_role_push_orders_the_attacking_weight() -> void:
	assert_gt(Attrs.role_push("ST"), Attrs.role_push("CAM"), "a striker does not push higher than a 10")
	assert_gt(Attrs.role_push("CAM"), Attrs.role_push("CM"), "a 10 does not push higher than a centre-mid")
	assert_gt(Attrs.role_push("CM"), Attrs.role_push("CB"), "a centre-mid does not push higher than a centre-back")
	assert_almost_eq(Attrs.role_push("ST"), 1.0, 0.001)
	assert_almost_eq(Attrs.role_push("CB"), 0.05, 0.001)
	assert_almost_eq(Attrs.role_push("UNKNOWN"), 0.3, 0.001)
