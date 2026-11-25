class_name FixtureSheet
extends RefCounted

## The fixture picker's scene glue: build the sheet layer, open and close it,
## take the confirmed clubs back into the scene, and read the `--home/--away`
## command-line override. The scene keeps the state; this module owns the
## branching. Split out of main.gd so the scene stays inside its P3 size budget.

var game = null

func _init(host) -> void:
	game = host

func build() -> void:
	if game.selector != null:
		return
	game.sel_layer = CanvasLayer.new()
	game.sel_layer.layer = 20
	game.add_child(game.sel_layer)
	game.selector = Control.new()
	game.selector.set_script(load("res://scripts/ui/team_select.gd"))
	game.selector.set_anchors_preset(Control.PRESET_FULL_RECT)
	game.selector.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.sel_layer.add_child(game.selector)
	game.selector.confirmed.connect(game._on_fixture_confirmed)
	game.selector.cancelled.connect(game._close_select)
	game.selector.browse.connect(game.wiki_host.open_page)
	game.selector.ui_scale = game.hud_scale
	game.selector.touch = game.touch
	game.sel_layer.visible = false

func open(from_menu := false) -> void:
	if game.selector == null:
		return
	game.select_from_menu = from_menu
	game.select_open = true
	game.paused = true
	if from_menu and game.menus != null:
		game.menus.close(true)
	game.selector.back_to_menu = from_menu
	game.selector.setup(game.home_id, game.away_id)
	if game.hud_layer != null:
		game.hud_layer.visible = false
	game.sel_layer.visible = true
	game.selector.visible = true

## Back from the sheet: a sheet opened out of the menu returns to the menu; one
## opened mid-match hands the broadcast back and unpauses.
func close() -> void:
	game.select_open = false
	if game.sel_layer != null:
		game.sel_layer.visible = false
	if game.select_from_menu:
		game.select_from_menu = false
		if game.menus != null:
			game.menus.open_menu()
		return
	if game.hud_layer != null:
		game.hud_layer.visible = true
	game.paused = false

## A confirmed fixture opens the pre-match briefing (#157). Its KICK OFF starts
## the match on a fresh seed; BACK returns to this picker with its clubs, and the
## match never starts.
##
## The picker's match is a friendly (#209): no league fixture behind it, so the
## briefing, the broadcast's fixture card and the team sheet all name one — and
## the same — competition.
func confirm(home: String, away: String) -> void:
	game.home_id = home
	game.away_id = away
	game.select_open = false
	if game.sel_layer != null:
		game.sel_layer.visible = false
	MatchBilling.bind_scene(game, home, {})
	if game.prematch != null:
		var req := PreMatchModel.build(home, away, {}, LeagueSeason.active)
		game.prematch.ask(req, Callable(self, "start_confirmed"), Callable(self, "back_from_briefing"))
		return
	start(home, away)

## The briefing's KICK OFF: the confirmed fixture becomes the next match.
func start_confirmed() -> void:
	start(game.home_id, game.away_id)

## The briefing's BACK: this picker comes back on the same two clubs.
func back_from_briefing() -> void:
	reopen()

## The picker's own start: the confirmed fixture becomes the next match.
func start(home: String, away: String) -> void:
	game.home_id = home
	game.away_id = away
	game.select_open = false
	game.select_from_menu = false
	if game.sel_layer != null:
		game.sel_layer.visible = false
	if game.hud_layer != null:
		game.hud_layer.visible = true
	if game.menus != null:
		game.menus.close()
	game.match_started = true
	game.seeded += randi_range(1, 9999)
	game.new_match(game.seeded)

## BACK from the briefing: the picker comes back on the same two clubs.
func reopen() -> void:
	open(game.select_from_menu)

## `--seed=`, `--home=` and `--away=` from the command line; report whether a
## fixture was named so the menu can stay closed on a scripted run.
func parse_args() -> bool:
	var f := FixtureArgs.parse(OS.get_cmdline_user_args(), TeamData.team_ids(), {"seed": game.seeded, "home": game.home_id, "away": game.away_id})
	game.seeded = int(f["seed"])
	game.home_id = str(f["home"])
	game.away_id = str(f["away"])
	return bool(f["given"])
