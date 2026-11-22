class_name DevCapture
extends RefCounted

## Dev-only harness: the `--shots=` / `--quit=` / `--clock=` / `--focus=` /
## `--hover=` / `--paused` / `--fakegoal` / `--managers` / `--full` /
## `--follow` command-line flags, PNG capture and the forced-hover helper that
## screenshot runs need. Extracted from the scene controller so main.gd keeps
## inside its P3 size budget.

var shot_times: Array = []
var shot_index := 0
var goal_captured := false
var quit_after := -1.0
var hover_force := -1
var elapsed := 0.0
## `--ui-scale=2.2` forces the handheld overlay scale and touch copy on a
## desktop build, so the phone layout can be inspected without a device.
var ui_scale := 0.0

## `args` is injectable so the flag table can be tested; production passes the
## real command line.
func parse(game, args := OS.get_cmdline_user_args()) -> void:
	for a in args:
		if a.begins_with("--shots="):
			for p in a.substr(8).split(","):
				shot_times.append(float(p))
		elif a.begins_with("--quit="):
			quit_after = float(a.substr(7))
		elif a.begins_with("--focus="):
			game.focus_id = int(a.substr(8))
			game.actors.focus_id = game.focus_id
		elif a == "--follow":
			game.camera_follow = true
		elif a.begins_with("--clock="):
			game.engine.clock = float(a.substr(8))
			if game.engine.clock > 2700.0:
				game.engine.half = 2
				game.engine.teams[0]["dir"] = -1
				game.engine.teams[1]["dir"] = 1
				game.engine.setup_kickoff(1, false)
		elif a.begins_with("--hover="):
			hover_force = int(a.substr(8))
		elif a.begins_with("--ui-scale="):
			ui_scale = float(a.substr(11))
		elif a == "--paused":
			game.paused = true
		elif a == "--fakegoal":
			game.engine.score[0] = 2
			game.engine.score[1] = 1
			game.engine.phase = "goal"
			game.engine.goal_timer = 8.0
			game.engine.last_goal = {"team": 0, "conceded_by": 1, "scorer": "B. Šeško", "minute": 63, "own_goal": false}
		elif a == "--managers":
			game.engine.manager.demo()
		elif a == "--full":
			game.mode = "full"
			game.fast_mode = false
			game.speed = 1.0

## Per-frame: capture due screenshots and quit when the clock runs out.
func tick(game, delta: float) -> void:
	elapsed += delta
	if quit_after > 0.0 and elapsed >= quit_after:
		print("EXIT clock=", game.engine.display_clock(), " score=", game.engine.score, " hl=", game.in_highlight, " fast=", game.fast_mode, " events=", game.engine.events.size(), " focus=", game.focus_id)
		game.get_tree().quit()
		return
	shots(game)

func shots(game) -> void:
	if shot_times.is_empty():
		return
	if shot_index < shot_times.size() and elapsed >= float(shot_times[shot_index]):
		_save(game, "res://shots/shot_%02d.png" % shot_index)
		print("saved shot ", shot_index, " t=", snappedf(elapsed, 0.1), " clock=", game.engine.display_clock(), " score=", game.engine.score)
		shot_index += 1
	if not goal_captured and game.engine.phase == "goal":
		goal_captured = true
		_save(game, "res://shots/goal.png")
		print("saved goal banner at clock=", game.engine.display_clock())

## A headless run has no renderer to read back, so the capture degrades to a
## no-op instead of erroring on a null image.
func _save(game, path: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var tex: ViewportTexture = game.get_viewport().get_texture()
	if tex == null:
		return
	var img: Image = tex.get_image()
	if img == null:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	img.save_png(ProjectSettings.globalize_path(path))

## Pin the hover to one player so a screenshot has a dossier on screen.
func apply_hover(game) -> bool:
	if hover_force < 0:
		return false
	var hp = game.engine.by_id.get(hover_force, null)
	if hp == null:
		return false
	game.hover_id = hover_force
	game.actors.hover_id = hover_force
	var screen_pos: Vector2 = game.get_viewport().get_canvas_transform() * hp.pos
	game.hud.mouse = (screen_pos + Vector2(24, 10)) / maxf(game.hud_scale, 0.001)
	return true
