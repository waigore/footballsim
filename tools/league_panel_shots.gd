extends SceneTree

## Evidence capture for Teams of Interest, the left panel and System (#103).
##
## Boots the real game scene, builds a generated season with eight rounds played,
## then walks the panel, the interest list and its search, a long-press context
## menu, Stats and System, writing a PNG per pose into `res://shots/`. Run on a
## display — a headless run has no frame to read back.
##
##   xvfb-run -a godot --path . --resolution 1600x900 \
##     --script res://tools/league_panel_shots.gd

const SEED := 2033

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	var league: LeagueHost = scene.menus.league
	var season := LeagueSeason.create("Panel Evidence", "generated", "fixture_days", SEED)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	var guard := 0
	while season.record.fixtures.completed_matchdays() < 8 and guard < 20:
		season.advance()
		guard += 1
	league.show_season(season)
	await _shot("league_panel_closed")
	# Mid-slide and settled: the panel's own clock, not a jump cut (#110).
	league.screen.panel.open()
	league.screen.panel.update(0.09)
	# Hold the panel where the clock left it so the shot lands mid-slide.
	league.screen.panel.target = league.screen.panel.slide
	await _shot("league_panel_sliding")
	league.screen.panel.open()
	league.screen.panel.settle()
	league.screen.refresh()
	await _shot("league_panel")
	league.screen.click("nav:interest")
	league.screen.panel.settle()
	await _shot("league_interest")
	for code in [KEY_A, KEY_R, KEY_S]:
		league.screen.key(code)
	await _shot("league_interest_search")
	league.screen.click("interest:add:ARS")
	league.screen.click("interest:add:LIV")
	await _shot("league_interest_marked")
	league.screen.click("back")
	league.screen.panel.settle()
	# A hold on a club name: the shortlist's own door, over the hub (#107).
	var zone := _name(league.screen)
	if not zone.is_empty():
		var at: Vector2 = (zone["rect"] as Rect2).get_center()
		league.screen.interest.press_at(at)
		league.screen.interest.tick(InterestPress.HOLD + 0.01)
		league.screen.refresh()
		await _shot("league_interest_menu")
		league.screen.interest.close()
		league.screen.refresh()
	var plan: Array = season.plan()
	var home := str(plan[0]["home_club_id"])
	season.record.interest.set_interest(home, true)
	league.screen.refresh()
	await _shot("league_hub_marked")
	league.screen.click("nav:stats")
	league.screen.panel.settle()
	await _shot("league_stats")
	league.screen.click("nav:system")
	league.screen.panel.settle()
	await _shot("league_system")
	league.screen.click("sys:save")
	await _shot("league_save")
	# A finished season's Stats carries the Podium door (#108).
	league.screen.click("sys:cancel")
	season.save.set_status("complete")
	season.save.reload()
	league.screen.panel.open()
	league.screen.panel.settle()
	league.screen.click("nav:stats")
	league.screen.panel.settle()
	league.screen.refresh()
	await _shot("league_stats_podium")
	print("EXIT interest=", season.record.interest.interests(), " slug=", season.save.slug)
	quit()

## The first club name the hub painted, in design space.
func _name(screen: LeagueScreen) -> Dictionary:
	if screen.rows_names == null:
		return {}
	for zone in screen.rows_names.zones:
		return zone
	return {}

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
