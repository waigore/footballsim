class_name MenuMusic
extends Node


const STREAM_PATH := "res://audio/menu_theme.ogg"
const MIN_DB := -80.0

var player: AudioStreamPlayer = null
var volume := 0.7


var wanted := false

func _ready() -> void:
	if player != null:
		return
	player = AudioStreamPlayer.new()
	player.name = "MenuMusicPlayer"
	var stream = load(STREAM_PATH)
	if stream != null:
		if stream is AudioStreamOggVorbis:
			stream.loop = true
		elif stream is AudioStreamWAV:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_end = int(stream.get_length() * stream.mix_rate)
		player.stream = stream
	add_child(player)
	_apply_volume()

func play_menu() -> void:
	wanted = true
	if player != null and player.stream != null and not player.playing:
		player.play()

func stop() -> void:
	wanted = false
	if player != null:
		player.stop()

func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	_apply_volume()

func _apply_volume() -> void:
	if player == null:
		return
	player.volume_db = linear_to_db(volume) if volume > 0.0 else MIN_DB

func is_silent() -> bool:
	return volume <= 0.0
