extends Control

## Broadcast overlay: composes the HUD bands (top, roster, controls, banners),
## the commentary ticker, manager card and player dossier. Each band is its own
## module; this node owns the shared state, one paint scope per frame and the
## tap order.
##
## The palette aliases only feed the ticker, manager card and dossier, which are
## constructed here.

const C_PANEL := UiChrome.C_PANEL
const C_TEXT := UiChrome.C_TEXT
const C_DIM := UiChrome.C_DIM
const C_GOLD := UiChrome.C_GOLD

var game = null
var engine = null

var f_bold: FontFile
var f_med: FontFile
var f_body: FontFile

## The long press on a club's scoreboard name (#107).
var interest := InterestHold.new()
## The layer that paints the menu above every band.
var menu_layer: InterestLayer = null
## The followed club ids as a set, and the season it was read from: the overlay
## paints every frame, so the shortlist is read when it moves, not per name.
var followed := {}
var followed_of = null
## The season whose `state_changed` this overlay listens to, so a shortlist that
## moves outside the menu (a save loaded, a club followed elsewhere) repaints.
var _followed_bound = null

## Every door painted this frame, in draw order (`id`, `rect`, `label`, `hint`).
var buttons: Array:
	get:
		return chrome.buttons
var mouse := Vector2.ZERO
var hover_button := -1

## Design-space multiplier: on handhelds main.gd scales this layer up by the
## same value, so every design unit below is read in the units the desktop
## overlay was drawn in. `touch` swaps keyboard-only affordances for tap copy.
var ui_scale := 1.0
var touch := false

# Commentary ticker state lives in HudCommentary; the HUD only forwards time
# and draws it.
var ticker: HudCommentary = null
var manager_card: HudManagers = null
var card: HudPlayerCard = null

## One drawing surface per overlay, cleared at each frame's draw.
var chrome := HudChrome.new()
var top_band := HudTopBand.new()
var roster_band := HudRosterBand.new()
var controls_band := HudControlsBand.new()
var banners_band := HudBannersBand.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	f_bold = load("res://fonts/BarlowCondensed-SemiBold.ttf")
	f_med = load("res://fonts/BarlowCondensed-Medium.ttf")
	f_body = load("res://fonts/Inter-Regular.ttf")
	ticker = HudCommentary.new(C_PANEL, C_GOLD, C_TEXT, C_DIM)
	manager_card = HudManagers.new(C_PANEL, C_GOLD, C_TEXT, C_DIM)
	card = HudPlayerCard.new(C_PANEL, C_GOLD, C_TEXT, C_DIM)
	# A held club name opens the Teams of Interest menu (#107); the scoreboard
	# doors are already the club's own, so the hold reads them back.
	interest.club_at = func(p: Vector2) -> String:
		if engine == null:
			return ""
		var id := button_at(p)
		if id == "team_0":
			return str(engine.teams[0]["id"])
		if id == "team_1":
			return str(engine.teams[1]["id"])
		return ""
	interest.season_of = func(): return LeagueSeason.active
	interest.on_changed = func():
		_read_followed()
		queue_redraw()
	menu_layer = InterestLayer.new()
	menu_layer.hold = interest
	menu_layer.screen = self
	add_child(menu_layer)

## The logical viewport is the stretched one (1600x900 and friends); the overlay
## draws in the smaller design space that main.gd scales back up.
func design_vp() -> Vector2:
	return get_viewport().get_visible_rect().size / maxf(ui_scale, 0.001)

func _process(d: float) -> void:
	if ticker != null:
		ticker.tick(d, engine, game)
	if manager_card != null:
		manager_card.tick(d, engine, game)
	if interest.tick(d):
		queue_redraw()
	if LeagueSeason.active != followed_of:
		_read_followed()
	queue_redraw()

## Re-read the shortlist when the season under the broadcast opens or closes, and
## after anything writes it (#107): the overlay paints every frame, so it reads
## the set once and listens to the season instead of querying per name.
func _read_followed() -> void:
	var season = LeagueSeason.active
	if _followed_bound != season:
		if _followed_bound != null and is_instance_valid(_followed_bound) \
				and _followed_bound.state_changed.is_connected(_read_followed):
			_followed_bound.state_changed.disconnect(_read_followed)
		_followed_bound = season
		if season != null and not season.state_changed.is_connected(_read_followed):
			season.state_changed.connect(_read_followed)
	followed_of = season
	followed = LeagueInterestMark.set_of(season.state().get("interests", [])) \
		if season != null else {}
	queue_redraw()

func _draw() -> void:
	if game == null or engine == null:
		return
	chrome.buttons.clear()
	var vp := design_vp()
	var p := HudPaint.new(chrome, vp)
	p.followed = followed
	roster_band.ui_scale = ui_scale
	roster_band.touch = touch
	roster_band.mouse = mouse
	banners_band.touch = touch
	roster_band.world_labels(p, self, engine, game, f_bold)
	top_band.scoreboard(p, self, engine, game, f_bold, f_med)
	top_band.flags(p, self, game, touch, f_bold)
	top_band.meta(p, self, engine, touch, mouse, f_bold, f_med)
	roster_band.stats(p, self, engine, f_bold, f_med)
	controls_band.controls(p, self, game, touch, mouse, f_bold, f_med)
	if ticker != null:
		ticker.draw(self, vp, f_bold, f_med, game)
	if manager_card != null:
		manager_card.draw(self, vp, f_bold, f_med, engine)
	roster_band.status(p, self, game, controls_band.speed_label(game), f_bold, f_med)
	if card != null:
		card.touch = touch
		card.draw(self, vp, f_bold, f_med, engine, game)
		if card.player(engine, game) != null:
			chrome.add_button("profile", card.profile_rect(vp), "PROFILE", "")
	roster_band.tooltip(p, self, engine, game, f_bold, f_med)
	banners_band.events(p, self, engine, game, f_bold, f_med)
	banners_band.intro(p, self, engine, game, f_bold, f_med)
	banners_band.paused(p, self, engine, game, f_bold, f_med)
	banners_band.vignette(p, self)

## The manager card is a whole-card dismiss target and sits in front of the bar.
func button_at(p: Vector2) -> String:
	# The open menu answers every press itself (#107).
	if interest.is_open():
		return interest.menu.hit(p, design_vp())
	if manager_card != null and manager_card.button_at(p):
		return "manager_card"
	return chrome.button_at(p)
