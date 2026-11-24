extends GdToolsTest

## The follow door the encyclopedia carries on a team page while a league season
## is open (#104): it names the club, says whether the season follows it, sits
## clear of BACK and ✕, and hands the club id to the host — which owns the rule —
## on a press.

var SAVE_DIR := TestScratch.dir("saves_test_wiki_interest")
var CACHE_DIR := TestScratch.dir("cache_test_wiki_interest")
const SEED := 2029
const CLUB := "MUN"

var season: LeagueSeason = null
var wiki = null

func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	_clean()
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	season = LeagueSeason.create("Follow Pages", "generated", "fixture_days", SEED)
	assert_not_null(season, "the season was not created")
	wiki = Control.new()
	wiki.set_script(load("res://scripts/ui/wiki_screen.gd"))
	wiki.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(wiki)
	await get_tree().process_frame
	wiki.ui_scale = 1.0
	wiki.touch = false


func after_all() -> void:
	if is_instance_valid(wiki):
		wiki.queue_free()
	if season != null:
		season.close()
	_clean()
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func _clean() -> void:
	for folder in [SAVE_DIR, CACHE_DIR]:
		TestScratch.clear(folder)

func _team_page() -> Dictionary:
	return {"page": WikiModel.TEAM, "id": CLUB}

# ------------------------------------------------------------------ target ---

func test_only_a_team_page_in_a_season_carries_the_door() -> void:
	assert_eq(WikiInterest.target(_team_page(), season), CLUB, "the team page has no door")
	assert_eq(WikiInterest.target({"page": WikiModel.LEAGUE, "id": ""}, season), "",
		"the league page carries a door")
	assert_eq(WikiInterest.target(_team_page(), null), "", "a page outside a season carries a door")

func test_the_door_reads_the_season_s_shortlist() -> void:
	season.set_interest(CLUB, false)
	assert_eq(WikiInterest.label(season, CLUB), "FOLLOW", "an unmarked club does not offer FOLLOW")
	assert_false(WikiInterest.followed(season, CLUB), "an unmarked club reads as followed")
	assert_true(season.set_interest(CLUB, true), "the club was not marked")
	assert_eq(WikiInterest.label(season, CLUB), "FOLLOWING", "a marked club does not read FOLLOWING")
	assert_true(WikiInterest.followed(season, CLUB), "a marked club does not read as followed")
	season.set_interest(CLUB, false)

func test_the_door_clears_back_and_the_close_door() -> void:
	var back := Rect2(24.0, 10.0, 104.0, 34.0)
	var close := Rect2(600.0, 10.0, 44.0, 34.0)
	var r := WikiInterest.rect(Vector2(660.0, 400.0), back, close)
	assert_gte(r.position.x, back.end.x + 8.0, "the door crowds BACK")
	assert_lte(r.end.x, close.position.x, "the door covers the close door")
	assert_eq(r.size.y, back.size.y, "the door is not on the header row")
	assert_eq(WikiInterest.rect(Vector2(260.0, 400.0), back, close).size.x, 0.0,
		"a narrow sheet still placed the door")

func test_the_door_carries_the_club_and_its_state() -> void:
	season.set_interest(CLUB, true)
	var d := WikiInterest.door(_team_page(), season, Vector2(660.0, 400.0),
		Rect2(24.0, 10.0, 104.0, 34.0), Rect2(600.0, 10.0, 44.0, 34.0))
	assert_eq(str(d.get("id", "")), "interest:" + CLUB, "the door is not addressed to the club")
	assert_true(bool(d.get("followed", false)), "the door lost the followed state")
	assert_eq(str(d.get("text", "")), "FOLLOWING", "the door lost its wording")
	assert_true(WikiInterest.door({"page": WikiModel.LEAGUE, "id": ""}, season,
		Vector2(660.0, 400.0), Rect2(24.0, 10.0, 104.0, 34.0),
		Rect2(600.0, 10.0, 44.0, 34.0)).is_empty(), "the league page produced a door")
	season.set_interest(CLUB, false)

# ------------------------------------------------------------------ press ---

func test_a_press_names_the_club_to_the_host() -> void:
	# A GDScript lambda captures by value, so the listener is made per press:
	# the box it appends to is this test's own.
	var heard: Array = []
	wiki.interest_toggled.connect(func(club_id: String) -> void: heard.append(club_id))
	wiki.open(WikiModel.TEAM, CLUB)
	wiki.click("interest:" + CLUB)
	assert_eq(heard, [CLUB], "the press did not name the club")
	wiki.interest_toggled.disconnect(wiki.interest_toggled.get_connections()[0]["callable"])

func test_the_host_moves_the_season_s_shortlist() -> void:
	var host := WikiHost.new(null)
	season.set_interest(CLUB, false)
	host._on_interest_toggled(CLUB)
	assert_true(season.record.interest.interests().has(CLUB), "the host did not follow the club")
	host._on_interest_toggled(CLUB)
	assert_false(season.record.interest.interests().has(CLUB), "the host did not unfollow the club")
	host._on_interest_toggled("")
	assert_false(season.record.interest.interests().has(""), "an empty club reached the shortlist")
