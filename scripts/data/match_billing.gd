class_name MatchBilling
extends RefCounted


const FRIENDLY := "FRIENDLY"

const FRIENDLY_CAPTION := "FRIENDLY · SINGLE MATCH"


var competition_id := ""

var short_name := ""
var full_name := ""

var matchday := 0
var friendly := true


var home_short := ""
var away_short := ""


func bind_fixture(home_id: String, fixture: Dictionary, away_id: String = "") -> void:
	if fixture.is_empty():
		bind_friendly(home_id, away_id)
		return
	var club := TeamData.get_team(home_id)
	if club.is_empty():
		bind_friendly(home_id, away_id)
		return
	friendly = false
	competition_id = str(club.get("competition", ""))
	short_name = str(club.get("competition_short", competition_id))
	full_name = str(club.get("competition_name", short_name))
	matchday = maxi(int(fixture.get("matchday", 1)), 1)
	home_short = short_name
	away_short = ""


func bind_friendly(home_id: String = "", away_id: String = "") -> void:
	friendly = true
	competition_id = ""
	short_name = ""
	full_name = ""
	matchday = 0
	home_short = str(TeamData.get_team(home_id).get("competition_short", ""))
	away_short = str(TeamData.get_team(away_id).get("competition_short", ""))


func chrome_name() -> String:
	return FRIENDLY if friendly else short_name


func prose_name() -> String:
	return "a friendly" if friendly else "the " + full_name


func caption() -> String:
	if not friendly:
		return "%s · MATCHDAY %d" % [short_name, matchday]
	if home_short != "" and away_short != "" and home_short != away_short:
		return "FRIENDLY · %s v %s" % [home_short, away_short]
	return FRIENDLY_CAPTION


static func bind_scene(scene, home_id: String, fixture: Dictionary,
		away_id: String = "") -> MatchBilling:
	var binding = scene.get("billing") if scene != null else null
	if binding is MatchBilling:
		(binding as MatchBilling).bind_fixture(home_id, fixture, away_id)
		return binding as MatchBilling


	var made := MatchBilling.new()
	made.bind_fixture(home_id, fixture, away_id)
	return made


static func league_watch(scene) -> bool:
	var binding = scene.get("billing") if scene != null else null
	return binding is MatchBilling and not (binding as MatchBilling).friendly
