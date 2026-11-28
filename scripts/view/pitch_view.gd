extends Node2D


# gd-tools: no cover start

var grass_font: FontFile
var rng := RandomNumberGenerator.new()
var grass_noise: NoiseTexture2D
var stadium_tex: ImageTexture


func _ready() -> void:
	z_index = -20
	rng.seed = 90210
	grass_font = load("res://fonts/BarlowCondensed-SemiBold.ttf")
	stadium_tex = PitchStadium.bake(1600, 1200, rng)
	if OS.get_cmdline_user_args().has("--dumpstadium"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
		stadium_tex.get_image().save_png(ProjectSettings.globalize_path("res://shots/stadium.png"))
	var n := FastNoiseLite.new()
	n.seed = 7
	n.frequency = 0.05
	n.fractal_octaves = 3
	grass_noise = NoiseTexture2D.new()
	grass_noise.width = 512
	grass_noise.height = 512
	grass_noise.seamless = true
	grass_noise.noise = n
	queue_redraw()


func _draw() -> void:
	PitchPaint.draw_stadium(self, stadium_tex)
	PitchPaint.draw_frame(self, grass_noise)


# gd-tools: no cover end
