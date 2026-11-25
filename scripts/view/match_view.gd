class_name MatchView
extends RefCounted

## The play scene's presentation face: which overlay widget a pointer is over,
## the design-space conversion the overlay and the fixture sheet expect, which
## token a click or hover picks, and how many ticks a frame may run. The scene
## keeps the state; this module owns the arithmetic between screen and design
## space. Split out of main.gd so the scene stays inside its P3 size budget.

var game = null

func _init(host) -> void:
	game = host

## A phone opens a match already tracking the ball; the desktop broadcast starts
## wide (#158). Read once, when the scene initialises its camera state.
static func default_follow() -> bool:
	return OS.has_feature("mobile")

## Handhelds read the match overlay at one density point per design unit; the
## non-match chrome (menus, settings, league and encyclopedia sheets) has its
## own scale. `dev` may force the handheld overlay on desktop builds.
func overlay_scale(hud_layer: CanvasLayer, dev) -> Dictionary:
	var hud: float = HudLayout.overlay_scale()
	var handheld := false
	if dev != null and dev.ui_scale > 0.0:
		hud = dev.ui_scale
		handheld = true
	var compact: bool = HudLayout.is_compact(game.get_viewport_rect().size / hud)
	if hud_layer != null:
		hud_layer.transform = Transform2D.IDENTITY.scaled(Vector2(hud, hud))
	return {
		"hud": hud,
		"touch": handheld or game.touch,
		"chrome": maxf(hud, ChromeDensity.non_match_scale()),
		"token": 1.5 if compact else 1.0,
	}

## Overlay widgets read pointers in design space; a non-match sheet passes its
## own reading scale because the chrome layer is scaled separately.
func design(p: Vector2, scale := -1.0) -> Vector2:
	return p / maxf(game.hud_scale if scale < 0.0 else scale, 0.001)

func button_at(p: Vector2) -> String:
	return game.hud.button_at(design(p))

## Nearest player to a screen-space point, within a radius a finger can hit.
func pick(p: Vector2) -> int:
	var world: Vector2 = game.get_viewport().get_canvas_transform().affine_inverse() * p
	var best = null
	var reach: float = 2.8 if game.touch else 1.7
	var bd := reach * reach
	for q in game.engine.players:
		if q.sent_off:
			continue
		var d: float = q.pos.distance_squared_to(world)
		if d < bd:
			bd = d
			best = q
	return -1 if best == null else best.id

## Push the hovered token and the overlay pointer for one pointer position.
func hover(screen: Vector2) -> void:
	game.hover_id = pick(screen)
	game.actors.hover_id = game.hover_id
	game.hud.mouse = design(screen)
	if not game.touch:
		var over_button: bool = game.hud.button_at(game.hud.mouse) != ""
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if (game.hover_id >= 0 or over_button) else Input.CURSOR_ARROW)

## Ticks this frame may run: the two replay modes lean on the director's
## fast-forward, the full match follows the chosen speed. Both capped so a slow
## frame cannot stall the loop.
func ticks_this_frame(delta: float) -> int:
	var fast: bool = game.mode != "full" and game.fast_mode
	game.accumulator += delta * 60.0 * (24.0 if fast else game.speed)
	var n: int = int(game.accumulator)
	game.accumulator -= n
	return mini(n, 60 if fast else 120)

## Switch the live view and put the broadcast flags in the state it asks for
## (#164). The full match runs at the player's pace; the two replay modes
## fast-forward between the moments the director picks, and a view swapped while
## a replay is open keeps that replay running.
func set_mode(next: String) -> void:
	game.mode = Prefs.normalize_mode(next)
	if game.mode == "full":
		game.fast_mode = false
		game.in_highlight = false
		game.highlight_until = -1.0
		game.paused = false
		game.speed = 1.0
		return
	game.fast_mode = not game.in_highlight
	if not game.in_highlight:
		game.highlight_until = -1.0
