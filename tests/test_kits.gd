extends GdToolsTest


var club_ids: Array = []
var club_data: Dictionary = {}

func before_all() -> void:
	club_ids = TeamData.team_ids()
	for id in club_ids:
		club_data[str(id)] = TeamData.get_team(str(id))


func _sides(home_id: String, away_id: String) -> Array:
	return [
		{"id": home_id, "data": club_data[home_id]},
		{"id": away_id, "data": club_data[away_id]},
	]

func _shirt(sides: Array, t: int) -> Color:
	var kit: Dictionary = sides[t].get("kit", {})
	if kit.has("shirt"):
		return kit["shirt"]
	return sides[t]["data"]["color"]

func test_no_fixture_clashes() -> void:
	for a in club_ids:
		var home_shirt: Color = club_data[str(a)]["color"]
		for b in club_ids:
			if a == b:
				continue
			var away_shirt: Color = club_data[str(b)]["color"]
			if not Kits.clash(home_shirt, away_shirt):
				continue
			var sides := _sides(str(a), str(b))
			Kits.assign(sides)
			assert_false(Kits.clash(_shirt(sides, 0), _shirt(sides, 1)),
				"%s v %s both wear %s" % [a, b, _shirt(sides, 0).to_html(false)])

func test_home_keeps_first_choice() -> void:
	var eng := MatchEngine.new(1, "ENG-ARS1", "ENG-NFO1")
	assert_eq(eng.kit_color(0), eng.teams[0]["data"]["color"], "home side changed kit")

func test_visitors_change_when_shirts_clash() -> void:
	var eng := MatchEngine.new(1, "ENG-ARS1", "ENG-NFO1")
	assert_ne(eng.kit_color(1), eng.teams[1]["data"]["color"], "Forest kept a red shirt at Arsenal")
	assert_false(Kits.clash(eng.kit_color(0), eng.kit_color(1)), "change kit still clashes")

func test_ink_contrast() -> void:
	assert_lt(Kits.ink(Color.WHITE).get_luminance(), 0.3, "ink on white is not dark")
	assert_gt(Kits.ink(Color.BLACK).get_luminance(), 0.7, "ink on black is not light")
