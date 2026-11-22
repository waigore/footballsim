extends SceneTree

## Kit selection: no fixture may send both sides out in the same-looking shirt.
##   godot --headless --path . --script tools/test_kits.gd

func _init() -> void:
	var fails := 0
	var ids: Array = TeamData.team_ids()
	for a in ids:
		for b in ids:
			if a == b:
				continue
			var eng := MatchEngine.new(1, str(a), str(b))
			if Kits.clash(eng.kit_color(0), eng.kit_color(1)):
				fails += 1
				print("FAIL clash %s (%s) v %s (%s)" % [a, eng.kit_color(0).to_html(false), b, eng.kit_color(1).to_html(false)])
	var ars := MatchEngine.new(1, "ARS", "NFO")
	var home_keeps: bool = ars.kit_color(0) == ars.teams[0]["data"]["color"]
	var away_changed: bool = ars.kit_color(1) != ars.teams[1]["data"]["color"]
	print("ARS shirt %s v NFO shirt %s" % [ars.kit_color(0).to_html(false), ars.kit_color(1).to_html(false)])
	if fails > 0:
		print("FAIL: %d clashing fixtures" % fails)
	elif not home_keeps:
		print("FAIL: away side changed kit when the home shirt was free")
	elif not away_changed:
		print("FAIL: Arsenal v Forest did not trigger a change kit")
	elif Kits.ink(Color.WHITE).get_luminance() > 0.3:
		print("FAIL: ink on a white shirt is not dark")
	else:
		print("PASS: kits (%d fixtures, Arsenal v Forest split)" % (ids.size() * (ids.size() - 1)))
	quit()
