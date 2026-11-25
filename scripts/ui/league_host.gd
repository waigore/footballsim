class_name LeagueHost
extends RefCounted

## Owns the league layer for the play scene: the modal screen, the pause and
## chrome dance underneath it, and the hand-off of a watched fixture to the
## match viewer. The season itself lives in LeagueSeason; this class only shows
## it and starts matches.

const LAYER := 32

var game = null
var layer: CanvasLayer = null
var screen: LeagueScreen = null
## The drag/wheel/click grammar the sheet shares with the encyclopedia.
var pointer: SheetPointer = null
var season: LeagueSeason = null
## A watched fixture the player left early: it is played out while the hub paints.
var watch: LeagueWatch = null
## The watched fixture's whistle (#124): the held FULL TIME card between the
## viewer and the hub. See LeagueResult.
var result: LeagueResult = null
## The fixture the briefing is showing, while it is up (#157).
var briefing: Dictionary = {}
var was_paused := false

func attach(host) -> void:
	game = host
	watch = LeagueWatch.new(self)
	result = LeagueResult.new(self)

func build() -> void:
	if layer != null or game == null:
		return
	layer = CanvasLayer.new()
	layer.layer = LAYER
	game.add_child(layer)
	screen = LeagueScreen.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(screen)
	# The body owns the frame while the season sheet paints; a leftover watch
	# takes one engine slice per frame from it (#100).
	if screen.body != null:
		screen.body.host = self
	screen.closed.connect(_on_closed)
	screen.match_requested.connect(_on_match_requested)
	screen.season_opened.connect(_on_season_opened)
	screen.club_requested.connect(_on_club_requested)
	screen.goal_highlight_requested.connect(_on_goal_highlight)
	screen.quit_requested.connect(_on_quit_requested)
	pointer = SheetPointer.new(screen)
	# The same pointer grammar watches for a hold, so a club name can be pressed
	# and held without a second input path (#107).
	pointer.hold = screen.interest
	layer.visible = false

## Open means "the layer is on screen": the hand-off to the match viewer hides
## the layer but keeps the screen around, and the scene must play during it.
func is_open() -> bool:
	return layer != null and layer.visible and screen != null and screen.is_open()

## The broadcast is holding a watched fixture's full-time card and the hub is
## waiting behind it. The scene keeps the pitch on screen; this host still owns
## input, so no match control can restart the finished game (#124).
func is_holding() -> bool:
	return result != null and result.holding

func sync(frame: Transform2D, scale: float, touch: bool) -> void:
	if layer == null:
		return
	layer.transform = frame
	screen.ui_scale = scale
	screen.touch = touch
	screen.queue_redraw()

# ------------------------------------------------------------------ open ---

func open_wizard() -> void:
	_activate()
	screen.open_wizard()

func open_load() -> void:
	_activate()
	screen.open_load()

func open_save(slug: String) -> void:
	_activate()
	screen.open_save(slug)

## Show a season that already exists (a resumed save, a dev/evidence pose).
func show_season(season_in: LeagueSeason, podium: bool = false) -> void:
	_activate()
	screen.open_season(season_in, podium)

func close() -> void:
	if screen != null and screen.is_open():
		screen.close()

func _activate() -> void:
	if layer == null:
		build()
	if screen == null:
		return
	was_paused = bool(game.paused)
	game.paused = true
	game.select_open = false
	if game.menus != null:
		game.menus.close(true)
	if game.hud_layer != null:
		game.hud_layer.visible = false
	if game.sel_layer != null:
		game.sel_layer.visible = false
	layer.visible = true
	screen.ui_scale = game.chrome_scale
	screen.touch = game.touch
	layer.transform = Transform2D.IDENTITY.scaled(Vector2(game.chrome_scale, game.chrome_scale))
	screen.visible = true
	screen.queue_redraw()

## Leaving the league always lands on the main menu it was opened from — never
## on a finished match's HUD.
func _on_closed() -> void:
	if layer != null:
		layer.visible = false
	if screen != null and screen.season == null:
		season = null
	game.paused = true
	if game.hud_layer != null:
		game.hud_layer.visible = false
	if game.menus != null:
		game.menus.open_menu()

## A club row is a look-up, not an exit: the encyclopedia opens over the season
## and hands the season sheet back when it closes.
func _on_club_requested(club_id: String) -> void:
	if game.wiki_host == null:
		return
	game.wiki_host.open_page_over_league(WikiModel.TEAM, club_id)

## Stand the season sheet down while the encyclopedia covers it, then put it
## back on the pose it left — the season object never closes.
func cover_for_wiki(hidden: bool) -> void:
	if layer == null:
		return
	if hidden:
		# The encyclopedia covers the season: no field of it is on screen, so no
		# keyboard may stay up above the page (#201).
		if screen != null:
			screen.focus.blur()
		layer.visible = false
		return
	if screen == null:
		return
	game.paused = true
	layer.visible = true
	screen.queue_redraw()

## Single-match mode owns the cached seed: a friendly started while a league
## save is loaded unbinds the season so its stats cannot land in the save.
func detach_season() -> void:
	if season != null and season.match_recorded.is_connected(_on_recorded):
		season.match_recorded.disconnect(_on_recorded)
	if season != null:
		season.finishing = false
	if result != null:
		result.clear()
	if watch != null:
		watch.clear()
	if screen != null:
		screen.season = null
	season = null
	if LeagueSeason.active != null:
		LeagueSeason.active.close()

func _on_season_opened(opened: LeagueSeason) -> void:
	if season != null and season.match_recorded.is_connected(_on_recorded):
		season.match_recorded.disconnect(_on_recorded)
	season = opened
	if season != null and not season.match_recorded.is_connected(_on_recorded):
		season.match_recorded.connect(_on_recorded)

## Hand the fixture to the viewer — but only after the pre-match briefing (#157).
## The season already remembers it is waiting, so the result finds its way back
## through PLSimStats once the match starts.
func _on_match_requested(home: String, away: String, fixture_id: String) -> void:
	briefing = {"home": home, "away": away, "fixture": fixture_id}
	var fx: Dictionary = season.record.fixtures.one(fixture_id) if season != null else {}
	# One competition for the match, bound before the briefing paints (#209).
	MatchBilling.bind_scene(game, home, fx)
	if game.prematch != null:
		var req := PreMatchModel.build(home, away, fx, season)
		game.prematch.ask(req, Callable(self, "_kick_briefing"), Callable(self, "_back_from_briefing"))
		return
	_start_watch(home, away)

## CONTINUE on the briefing: the season's watch is already held, so the broadcast
## starts exactly as it did before the briefing existed.
func _kick_briefing() -> void:
	_start_watch(str(briefing.get("home", "")), str(briefing.get("away", "")))

## BACK on the briefing: the fixture never kicked off, so the season stops
## waiting and the hub comes back on the same day.
func _back_from_briefing() -> void:
	if season != null:
		season.cancel_watch()
	briefing = {}
	if layer != null:
		layer.visible = true
	if screen != null:
		screen.refresh()
	game.paused = true

func _start_watch(home: String, away: String) -> void:
	briefing = {}
	if layer != null:
		layer.visible = false
	# A keyboard belongs to a field on screen: the broadcast never inherits one.
	if screen != null:
		screen.focus.blur()
	if result != null:
		result.clear()
	game.home_id = home
	game.away_id = away
	game.seeded += randi_range(1, 9999)
	game.match_started = true
	game.new_match(game.seeded)
	game.paused = false
	if game.hud_layer != null:
		game.hud_layer.visible = true

## Quit from the System sheet: the shell owns the quit confirmation, so the
## season sheet asks it rather than closing the game itself.
func _on_quit_requested() -> void:
	if game != null and game.menus != null:
		game.menus.ask_quit()

## A watched match reached full time and the season recorded it. When the
## broadcast is still on that pitch the FULL TIME card stays up until the player
## dismisses it (#124); otherwise pause again and show the hub with the new
## clock. A result that lands while the main menu is open (a left-behind watch
## finishing) stays behind it — the hub is there when the menu closes.
func _on_recorded(report: Dictionary) -> void:
	if screen == null:
		return
	if result.take(report):
		return
	result.reveal()

# ----------------------------------------------------------------- input ---

## The sheet does its own hit testing; pointers arrive in design space and the
## shared pointer grammar turns a press, drag, wheel, pan or key into a scroll or
## a press. A held FULL TIME card owns every event first (#124).
func handle_input(event: InputEvent, design_point: Vector2) -> bool:
	if is_holding():
		return result.input(event)
	if not is_open() or pointer == null:
		return false
	if pointer.handle(event, design_point):
		return true
	return event is InputEventMouse

# ------------------------------------------------------------- goal clips ---

## ▶ on a report: play that goal's stored clip on the broadcast, then put the
## report back on screen. The season stays open throughout, so no state moves.
func _on_goal_highlight(fixture_id: String, goal_index: int) -> void:
	if season == null or fixture_id == "":
		return
	var pack := season.goal_clip(fixture_id, goal_index)
	if pack.is_empty():
		return
	if layer != null:
		layer.visible = false
	if game.hud_layer != null:
		game.hud_layer.visible = true
	game.play_goal_clip(pack, _on_goal_clip_done)

func _on_goal_clip_done() -> void:
	if game == null or screen == null:
		return
	game.paused = true
	if game.hud_layer != null:
		game.hud_layer.visible = false
	if layer != null:
		layer.visible = true
	screen.refresh()
