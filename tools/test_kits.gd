extends SceneTree

## Kit selection: no fixture may send both sides out in the same-looking shirt.
##   godot --headless --path . --script tools/test_kits.gd
## Pair checks call Kits.assign on team data — not a MatchEngine per fixture.

func _init() -> void:
	var fails := 0
	var ids: Array = TeamData.team_ids()
	var data: Dictionary = {}
	for id in ids:
		data[str(id)] = TeamData.get_team(str(id))
	for a in ids:
		for b in ids:
			if a == b:
				continue
			var sides := [
				{"id": str(a), "data": data[str(a)]},
				{"id": str(b), "data": data[str(b)]},
			]
			Kits.assign(sides)
			var home_shirt: Color = sides[0]["kit"]["shirt"]
			var away_shirt: Color = sides[1]["kit"]["shirt"]
			if Kits.clash(home_shirt, away_shirt):
				fails += 1
				print("FAIL clash %s (%s) v %s (%s)" % [a, home_shirt.to_html(false), b, away_shirt.to_html(false)])
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
