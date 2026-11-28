extends Control


var C_PANEL: Color = UiChrome.C_PANEL
var C_TEXT: Color = UiChrome.C_TEXT
var C_DIM: Color = UiChrome.C_DIM
var C_GOLD: Color = UiChrome.C_GOLD

var game = null
var engine = null

var f_bold: FontFile
var f_med: FontFile
var f_body: FontFile


var interest := InterestHold.new()

var menu_layer: InterestLayer = null


var followed := {}
var followed_of = null


var _followed_bound = null


var buttons: Array:
	get:
		return chrome.buttons
var mouse := Vector2.ZERO
var hover_button := -1


var ui_scale := 1.0
var touch := false


var hud_visible := true
var slide := 1.0
var on_hud_changed = null


var ticker: HudCommentary = null
var manager_card: HudManagers = null
var card: HudPlayerCard = null


var chrome := HudChrome.new()
var top_band := HudTopBand.new()
var roster_band := HudRosterBand.new()
var controls_band := HudControlsBand.new()
var banners_band := HudBannersBand.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	f_bold = UiTheme.bold()
	f_med = UiTheme.medium()
	f_body = UiTheme.body()
	ticker = HudCommentary.new(C_PANEL, C_GOLD, C_TEXT, C_DIM)
	manager_card = HudManagers.new(C_PANEL, C_GOLD, C_TEXT, C_DIM)
	card = HudPlayerCard.new(C_PANEL, C_GOLD, C_TEXT, C_DIM)


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


	var target: float = 1.0 if hud_visible else 0.0
	if slide != target:
		slide = move_toward(slide, target, d / HudLayout.HUD_SLIDE_SECONDS)
	queue_redraw()


func set_hud_visible(on: bool, from_pref := false) -> void:
	hud_visible = on
	if from_pref:
		slide = 1.0 if on else 0.0
	queue_redraw()
	if not from_pref and on_hud_changed != null:
		on_hud_changed.call(on)

func toggle_hud() -> void:
	set_hud_visible(not hud_visible)


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


	var held: bool = str(engine.phase) == "full_time" and bool(game.result_hold)
	if not held:
		chrome.add_button("hud", HudLayout.hud_toggle_rect(vp, touch), toggle_label(), "U")
	p.followed = followed
	roster_band.ui_scale = ui_scale
	roster_band.touch = touch
	roster_band.mouse = mouse
	banners_band.touch = touch


	banners_band.chrome_hidden = not hud_visible and slide <= 0.0
	var lift: float = 1.0 - slide
	roster_band.world_labels(p, self, engine, game, f_bold)
	if lift < 1.0:


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


		if hud_visible and card != null:
			card.touch = touch
			card.mode = Prefs.load_attrs()
			card.draw(self, vp, f_bold, f_med, engine, game)
			if card.player(engine, game) != null:
				chrome.add_button("profile", card.profile_rect(vp), "PROFILE", "")
				var door: Rect2 = card.attrs_rect(vp)
				if HudLayout.is_compact(vp):
					chrome.add_button("attrs:sheet", door, "FULL SHEET", "")
				else:
					var half: float = (door.size.x - 6.0) * 0.5
					chrome.add_button("attrs:SIMPLIFIED",
						Rect2(door.position, Vector2(half, door.size.y)), "SIMPLE", "")
					chrome.add_button("attrs:FULL",
						Rect2(door.position + Vector2(half + 6.0, 0.0), Vector2(half, door.size.y)),
						"FULL", "")
			roster_band.tooltip(p, self, engine, game, f_bold, f_med)
		draw_set_transform(Vector2.ZERO)


	top_band.scoreboard(p, self, engine, game, f_bold, f_med)
	top_band.flags(p, self, game, touch, f_bold, str(engine.phase))
	banners_band.events(p, self, engine, game, f_bold, f_med)
	banners_band.intro(p, self, engine, game, f_bold, f_med)
	banners_band.paused(p, self, engine, game, f_bold, f_med)
	banners_band.vignette(p, self)
	_draw_toggle(p, vp, held)


	if held:
		chrome.buttons.clear()


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


func button_at(p: Vector2) -> String:

	if interest.is_open():
		return interest.menu.hit(p, design_vp())
	if hud_visible and manager_card != null and manager_card.button_at(p):
		return "manager_card"
	return chrome.button_at(p)
