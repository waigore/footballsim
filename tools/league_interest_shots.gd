extends SceneTree

## Evidence capture for Teams of Interest (#104).
##
## Boots the real game scene, builds a generated season, follows one club, and
## writes the poses the feature shows: the hub with the followed club's names
## gold and its game marked FOLLOWED, the full table with the same mark, and the
## club's team page carrying its FOLLOWING door. Run it on a display — a headless
## run has no frame to read back.
##
##   godot --path . --script res://tools/league_interest_shots.gd

const SEED := 2030
const CLUB := "MUN"

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	var league: LeagueHost = scene.menus.league
	var season := LeagueSeason.create("Interest Season", "generated", "fixture_days", SEED)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	# Two rounds so the table and the day carry played rows beside the plan.
	season.advance()
	season.advance()
	league.show_season(season)
	# Follow the club, then make sure the day it plays is the day on screen.
	season.set_interest(CLUB, true)
	season.save.set_date(season.record.fixtures(3)[0]["kickoff"])
	season.save.set_matchday(3)
	league.screen.refresh()
	await _shot("interest_hub")
	league.screen.click("table")
	await _shot("interest_table")
	league.screen.click("back")
	league.screen.click("club:" + CLUB)
	await _frames(4)
	await _shot("interest_team_page")
	print("EXIT season=", season.save.slug, " interests=", season.record.interest.interests())
	quit()

func _frames(count: int) -> void:
	for i in range(count):
		await process_frame

func _shot(name: String) -> void:
	await _frames(4)
	var tex: ViewportTexture = scene.get_viewport().get_texture()
	if tex == null:
		print("SHOT %s skipped (no renderer)" % name)
		return
	var img: Image = tex.get_image()
	if img == null:
		print("SHOT %s skipped (no image)" % name)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	img.save_png(ProjectSettings.globalize_path("res://shots/%s.png" % name))
	print("SHOT ", name)
