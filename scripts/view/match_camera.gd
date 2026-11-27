class_name MatchCamera
extends RefCounted


const L := 105.0
const W := 68.0

var game = null
var target := Vector2(L * 0.5, W * 0.5)

func _init(host) -> void:
	game = host


func update_target() -> void:
	if not game.camera_follow or game.engine == null:
		target = Vector2(L * 0.5, W * 0.5 + game.pitch_shift)
		return
	var ball: Vector2 = game.engine.ball.pos
	var half_w: float = (game.get_viewport_rect().size.x / (game.base_zoom * game.zoom_scale)) * 0.5
	var half_h: float = (game.get_viewport_rect().size.y / (game.base_zoom * game.zoom_scale)) * 0.5
	target = Vector2(
		clampf(ball.x, half_w - 8.0, L - half_w + 8.0),
		clampf(ball.y, half_h - 6.0, W - half_h + 6.0)
	)
	if half_w * 2.0 > L + 20.0:
		target.x = L * 0.5
	if half_h * 2.0 > W + 18.0:
		target.y = W * 0.5

func update(delta: float) -> void:
	update_target()
	if game.cam != null:
		game.cam.position = game.cam.position.lerp(target, clampf(delta * 4.0, 0.0, 1.0))

func apply(snap_zoom: bool) -> void:
	if snap_zoom and game.cam != null:
		game.cam.zoom = Vector2(game.base_zoom * game.zoom_scale, game.base_zoom * game.zoom_scale)


func fit() -> void:
	var geo := HudLayout.pitch_fit(game.get_viewport_rect().size, game.hud_scale, game.touch)
	game.base_zoom = clampf(float(geo["zoom"]), 3.0, 16.0)
	game.pitch_shift = float(geo["offset"])
	if game.cam != null:
		game.cam.zoom = Vector2(game.base_zoom * game.zoom_scale, game.base_zoom * game.zoom_scale)
