class_name MenuMusic
extends Node

## Menu/settings background music. One looping stream, one volume knob; the
## match never hears it because the shell stops the player on the way in.
##
## The track is a pre-mastered ~2:40 techno loop (`audio/menu_theme.ogg`): the
## tail was blended into the head at build time, so the loop point has no click
## and no encoder padding to eat the downbeat.

const STREAM_PATH := "res://audio/menu_theme.ogg"
const MIN_DB := -80.0

var player: AudioStreamPlayer = null
var volume := 0.7
## Logical state, so a headless run (no audio device) can still assert that the
## menu asked for music and the match did not.
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
