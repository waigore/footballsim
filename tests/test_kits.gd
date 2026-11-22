extends GdToolsTest

## Kit selection: no fixture may send both sides out in the same-looking shirt.

func test_no_fixture_clashes() -> void:
	var ids: Array = TeamData.team_ids()
	for a in ids:
		for b in ids:
			if a == b:
				continue
			var eng := MatchEngine.new(1, str(a), str(b))
			assert_false(Kits.clash(eng.kit_color(0), eng.kit_color(1)),
				"%s v %s both wear %s" % [a, b, eng.kit_color(0).to_html(false)])

func test_home_keeps_first_choice() -> void:
	var eng := MatchEngine.new(1, "ARS", "NFO")
	assert_eq(eng.kit_color(0), eng.teams[0]["data"]["color"], "home side changed kit")

func test_visitors_change_when_shirts_clash() -> void:
	var eng := MatchEngine.new(1, "ARS", "NFO")
	assert_ne(eng.kit_color(1), eng.teams[1]["data"]["color"], "Forest kept a red shirt at Arsenal")
	assert_false(Kits.clash(eng.kit_color(0), eng.kit_color(1)), "change kit still clashes")

func test_ink_contrast() -> void:
	assert_lt(Kits.ink(Color.WHITE).get_luminance(), 0.3, "ink on white is not dark")
	assert_gt(Kits.ink(Color.BLACK).get_luminance(), 0.7, "ink on black is not light")
