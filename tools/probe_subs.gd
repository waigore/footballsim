extends SceneTree

## Regression probe for substitutions:
##  - a team never fields two keepers (the reported bug)
##  - every team keeps exactly one keeper on the pitch
##  - a substitute fills the slot of the player he replaces
##  - subs_left is spent, and survives a snapshot round-trip
##  - a sent-off keeper is replaced by the bench keeper

func _init() -> void:
	var failures := 0
	for seed_i in [1000]:
		var eng := MatchEngine.new(seed_i)
		var max_ticks := int(60 * 60 * 125)
		var guard := 0
		var two_gk := false
		var no_gk := false
		var slot_mismatch := false
		var sub_bases := {}
		while eng.phase != "full_time" and guard < max_ticks:
			if eng.phase == "half_time":
				eng.begin_second_half()
			eng.tick()
			guard += 1
			if guard % 30 == 0:
				for t in range(2):
					var gks := 0
					for p in eng.players:
						if p.team == t and p.is_gk and not p.sent_off:
							gks += 1
					if gks > 1:
						two_gk = true
					if gks == 0:
						no_gk = true
		# Every substitute must sit in the slot of the man he replaced.
		for p in eng.players:
			if p.id >= 200:
				var want: Vector2 = TeamData.formation_slot(eng.teams[p.team]["data"], p.role)
				if p.base.distance_to(want) > 0.001:
					slot_mismatch = true
		var snap: Dictionary = eng.to_dict()
		var eng2 := MatchEngine.new(seed_i)
		eng2.from_dict(snap)
		var left_ok: bool = eng2.teams[0]["subs_left"] == eng.teams[0]["subs_left"] and eng2.teams[1]["subs_left"] == eng.teams[1]["subs_left"]
		var made_ok: bool = eng2.teams[0]["subs_made"] == eng.teams[0]["subs_made"] and eng2.teams[1]["subs_made"] == eng.teams[1]["subs_made"]
		var gk_names := []
		for t in range(2):
			for p in eng.players:
				if p.team == t and p.is_gk:
					gk_names.append("%s/%s" % [eng.teams[t]["data"]["short"], p.name])
		print("seed %d: two_gk=%s no_gk=%s slot_mismatch=%s subs=%d/%d left=%d/%d snap_ok=%s gks=%s" % [
			seed_i, str(two_gk), str(no_gk), str(slot_mismatch),
			eng.teams[0]["subs_made"], eng.teams[1]["subs_made"],
			eng.teams[0]["subs_left"], eng.teams[1]["subs_left"],
			str(left_ok and made_ok), str(gk_names)])
		if two_gk or no_gk or slot_mismatch or not left_ok or not made_ok:
			failures += 1

	# Sent-off keeper: force one and confirm the bench keeper comes on.
	var e3 := MatchEngine.new(7)
	e3.half = 2
	e3.clock = 60.0 * 60.0
	var gk = e3._gk_of(0)
	gk.sent_off = true
	gk.red = true
	e3._tick_substitutions()
	var gk2 = e3._gk_of(0)
	var replaced: bool = gk2 != null and gk2.name != gk.name
	print("sent-off keeper replaced: %s (now %s)" % [str(replaced), gk2.name if gk2 != null else "NONE"])
	if not replaced:
		failures += 1

	print("FAILURES: %d" % failures)
	quit()
