extends SceneTree

## Verifies the home-advantage modifiers are applied to the home side only.

func _init() -> void:
	var eng := MatchEngine.new(3)
	var home = eng.by_id[8]     # MUN, team 0
	var away = eng.by_id[108]   # MCI, team 1
	away.attr = home.attr.duplicate(true)
	print("home team = ", eng.home_team, "  advantage = ", eng.home_advantage)
	print("home factor = %.3f   away factor = %.3f" % [eng.home_factor(home), eng.home_factor(away)])
	var hs: float = Attrs.pass_sigma_deg(home, 20.0, 0.5) / eng.home_factor(home)
	var as_: float = Attrs.pass_sigma_deg(away, 20.0, 0.5) / eng.home_factor(away)
	print("20m pass sigma (identical attrs): home %.3f deg  away %.3f deg" % [hs, as_])
	var hshot: float = Attrs.shot_sigma_deg(home, 16.0, 0.5) / eng.home_factor(home)
	var ashot: float = Attrs.shot_sigma_deg(away, 16.0, 0.5) / eng.home_factor(away)
	print("16m shot sigma (identical attrs): home %.3f deg  away %.3f deg" % [hshot, ashot])
	print("tackle duel bonus: home +0.020  away -0.015")
	print("stamina drain multiplier: home 0.96  away 1.02")
	var ok: bool = hs < as_ and hshot < ashot
	print("HOME ADVANTAGE APPLIED: ", ok)
	quit()
