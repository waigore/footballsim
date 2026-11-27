class_name MatchAudio
extends RefCounted


const POOL := 6

var parent: Node = null
var crowd: AudioStreamPlayer = null
var sfx_pool: Array = []
var sfx_next := 0
var sfx_streams := {}

func _init(node: Node) -> void:
	parent = node

func setup() -> void:
	crowd = AudioStreamPlayer.new()
	var stream = load("res://audio/crowd_loop.wav")
	if stream != null:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	crowd.stream = stream
	crowd.volume_db = -21.0
	parent.add_child(crowd)
	crowd.play()
	for n in ["kick", "whistle", "goal_roar", "ooh"]:
		sfx_streams[n] = load("res://audio/%s.wav" % n)
	for i in range(POOL):
		var player := AudioStreamPlayer.new()
		player.volume_db = -8.0
		parent.add_child(player)
		sfx_pool.append(player)

func play(name: String, vol_db: float = -8.0, pitch: float = 1.0) -> void:
	if not sfx_streams.has(name) or sfx_streams[name] == null or sfx_pool.is_empty():
		return
	var player: AudioStreamPlayer = sfx_pool[sfx_next % sfx_pool.size()]
	sfx_next += 1
	player.stream = sfx_streams[name]
	player.volume_db = vol_db
	player.pitch_scale = pitch
	player.play()


func ball_kicked(strength: float) -> void:
	play("kick", -10.0 + strength * 4.0, randf_range(0.9, 1.08))
