class_name SfxBank
extends Node

## Crowd bed and the short stadium stings, extracted from the scene controller
## so main.gd keeps inside its P3 budget. Owns one looping crowd player and a
## small round-robin pool so overlapping whistles do not cut each other off.

const SFX_NAMES := ["kick", "whistle", "goal_roar", "ooh"]
const POOL_SIZE := 6

var crowd: AudioStreamPlayer = null
var pool: Array = []
var streams := {}
var next_player := 0

func _ready() -> void:
	if crowd != null:
		return
	crowd = AudioStreamPlayer.new()
	var cs = load("res://audio/crowd_loop.wav")
	if cs != null:
		cs.loop_mode = AudioStreamWAV.LOOP_FORWARD
		cs.loop_end = int(cs.get_length() * cs.mix_rate)
		crowd.stream = cs
	crowd.volume_db = -21.0
	add_child(crowd)
	crowd.play()
	for n in SFX_NAMES:
		streams[n] = load("res://audio/%s.wav" % n)
	for i in range(POOL_SIZE):
		var pl := AudioStreamPlayer.new()
		pl.volume_db = -8.0
		add_child(pl)
		pool.append(pl)

func play(name: String, vol_db: float = -8.0, pitch: float = 1.0) -> void:
	if not streams.has(name) or streams[name] == null or pool.is_empty():
		return
	var pl: AudioStreamPlayer = pool[next_player % pool.size()]
	next_player += 1
	pl.stream = streams[name]
	pl.volume_db = vol_db
	pl.pitch_scale = pitch
	pl.play()
