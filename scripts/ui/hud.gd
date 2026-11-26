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

## The player's HUD choice (#158): the chrome is on until they turn it off, and
## the choice is remembered by the scene. `slide` is what is painted, eased
## toward the choice each frame so the bands glide rather than pop; the one door
## that never moves is the toggle itself. `on_hud_changed` is the scene's hook to
## persist the choice — the overlay never touches the prefs file itself.
var hud_visible := true
var slide := 1.0
var on_hud_changed = null


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
	# The bands ease toward the player's choice; the sim keeps running either
	# way, because nothing here waits on the animation (#158).
	var target: float = 1.0 if hud_visible else 0.0
	if slide != target:
		slide = move_toward(slide, target, d / HudLayout.HUD_SLIDE_SECONDS)
	queue_redraw()

## The player hid or showed the chrome. `from_pref` is the restore at launch: the
## bands start where they belong instead of gliding out of a default nobody
## chose, and the pref is not written back.
func set_hud_visible(on: bool, from_pref := false) -> void:
	hud_visible = on
	if from_pref:
		slide = 1.0 if on else 0.0
	queue_redraw()
	if not from_pref and on_hud_changed != null:
		on_hud_changed.call(on)

func toggle_hud() -> void:
	set_hud_visible(not hud_visible)

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
	# The pill never hides (#158), so its press is read before any band's: a card
	# that grows into its corner can never take the door back (#202). A held
	# league result is the one exception: the card swallows every press, so the
	# pill cannot answer and must not print a `U` that does nothing (#311).
	var held: bool = str(engine.phase) == "full_time" and bool(game.result_hold)
	if not held:
		chrome.add_button("hud", HudLayout.hud_toggle_rect(vp, touch), toggle_label(), "U")
	p.followed = followed
	roster_band.ui_scale = ui_scale
	roster_band.touch = touch
	roster_band.mouse = mouse
	banners_band.touch = touch
	# The chrome is gone only once it has finished sliding: until then its doors
	# still answer, and a card promising its own press would be a second door.
	banners_band.chrome_hidden = not hud_visible and slide <= 0.0
	var lift: float = 1.0 - slide
	# The token numbers belong to the players, not to a band: they fade with the
	# chrome instead of sliding off with it.
	if slide > 0.0:
		chrome.alpha = slide
		roster_band.world_labels(p, self, engine, game, f_bold)
		chrome.alpha = 1.0
	if lift < 1.0:
		# The chrome leaves in two directions (#158): the top row lifts, the
		# bottom strip drops, and neither waits on the other.
		draw_set_transform(Vector2(0.0, -HudLayout.HUD_SLIDE_TOP * lift))
		top_band.meta(p, self, engine, game, touch, mouse, f_bold, f_med)
		roster_band.stats(p, self, engine, f_bold, f_med)
		if manager_card != null:
			manager_card.draw(self, vp, f_bold, f_med, engine)
		draw_set_transform(Vector2(0.0, HudLayout.HUD_SLIDE_BOTTOM * lift))
		controls_band.controls(p, self, game, touch, mouse, f_bold, f_med, str(engine.phase))
		if ticker != null:
			ticker.draw(self, vp, f_bold, f_med, game)
		roster_band.status(p, self, game, controls_band.speed_label(game), f_bold, f_med, str(engine.phase))
		# The dossier and the hover card are the player's own picks, not bands:
		# they leave at once rather than half-off the screen.
		if hud_visible and card != null:
			card.touch = touch
			card.draw(self, vp, f_bold, f_med, engine, game)
			if card.player(engine, game) != null:
				chrome.add_button("profile", card.profile_rect(vp), "PROFILE", "")
			roster_band.tooltip(p, self, engine, game, f_bold, f_med)
		draw_set_transform(Vector2.ZERO)
	# The match's own events stay painted whatever the chrome does: the score,
	# the goal and whistle cards, the intro and the paused banner.
	top_band.scoreboard(p, self, engine, game, f_bold, f_med)
	top_band.flags(p, self, game, touch, f_bold, str(engine.phase))
	banners_band.events(p, self, engine, game, f_bold, f_med)
	banners_band.intro(p, self, engine, game, f_bold, f_med)
	banners_band.paused(p, self, engine, game, f_bold, f_med)
	banners_band.vignette(p, self)
	_draw_toggle(p, vp, held)
	# While the season holds a result the card owns every press and every key:
	# whatever the bands registered cannot answer, so the overlay answers nothing
	# rather than offering doors the card will swallow (#311).
	if held:
		chrome.buttons.clear()

## The one door that never hides: a discreet pill above the ticker, labelled with
## what the press does, and the key that does the same on a keyboard (#158). Its
## press is registered before the bands paint, so the paint here only draws it.
## While a held league result owns the screen it is painted dead instead of
## removed: the strip keeps its shape, and the pill stops promising a key the
## card swallows (#311).
func toggle_label() -> String:
	return "HIDE HUD" if hud_visible else "SHOW HUD"

func _draw_toggle(p: HudPaint, vp: Vector2, dead: bool = false) -> void:
	var r: Rect2 = HudLayout.hud_toggle_rect(vp, touch)
	var hovered := not dead and r.has_point(mouse)
	var label := toggle_label()
	p.panel(self, Color(0.02, 0.03, 0.04, 0.92 if hovered else 0.62), r, 8,
		Color(1, 1, 1, 0.18 if hovered else 0.10))
	var size := 11
	var x: float = r.position.x + 12.0
	var ink: Color = UiChrome.C_TEXT if hovered or not hud_visible else UiChrome.C_DIM
	if dead:
		ink = Color(UiChrome.C_DIM.r, UiChrome.C_DIM.g, UiChrome.C_DIM.b, 0.55)
	p.text(self, Vector2(x, r.position.y + r.size.y * 0.5 + float(size) * 0.36), label, size,
		ink, f_bold)
	if not touch and not dead:
		p.text_r(self, r.end.x - 12.0, r.position.y + r.size.y * 0.5 + 4.0, "U", 10, UiChrome.C_DIM, f_med)

## The manager card is a whole-card dismiss target and sits in front of the bar.
func button_at(p: Vector2) -> String:
	# The open menu answers every press itself (#107).
	if interest.is_open():
		return interest.menu.hit(p, design_vp())
	if hud_visible and manager_card != null and manager_card.button_at(p):
		return "manager_card"
	return chrome.button_at(p)
