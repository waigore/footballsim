class_name MatchScene
extends RefCounted


const W := 68.0
const L := 105.0


static func build(game: Node) -> void:
	game.arena = Node2D.new()
	game.arena.name = "Arena"
	game.add_child(game.arena)
	game.pitch = Node2D.new()
	game.pitch.set_script(load("res://scripts/view/pitch_view.gd"))
	game.arena.add_child(game.pitch)
	game.actors = Node2D.new()
	game.actors.set_script(load("res://scripts/view/actor_layer.gd"))
	game.arena.add_child(game.actors)
	game.cam = Camera2D.new()
	game.cam.position = Vector2(L * 0.5, W * 0.5)
	game.cam.enabled = true
	game.arena.add_child(game.cam)
	game.cam.make_current()
	game.hud_layer = CanvasLayer.new()
	game.hud_layer.layer = 10
	game.add_child(game.hud_layer)
	game.hud = Control.new()
	game.hud.set_script(load("res://scripts/ui/hud.gd"))
	game.hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	game.hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.hud_layer.add_child(game.hud)
	game.hud.game = game
	game.touch = OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
	game.camera = MatchCamera.new(game)
	game.view = MatchView.new(game)
	game.input = MatchInput.new(game)
	game.playback = MatchPlayback.new(game)
	game.fixture = FixtureSheet.new(game)
	game._sync_overlay_scale()
	game.camera.fit()
	game.actors.game = game
