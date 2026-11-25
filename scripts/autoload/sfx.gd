extends Node
## Sound: one-shot effects (in 3D at a position, or flat), looping ambience,
## and music that crossfades between tracks.
##   Sfx.play("sword_hit", position)   # positional
##   Sfx.play("ui_click")              # flat
##   Sfx.loop("rain_loop", true)       # ambience on / off
##   Sfx.music("music_boss")           # crossfade to a track ("" = silence)
## Sounds live in assets/audio/<name>.wav (made by tools/make_sounds.py).
## Names ending in _loop and music_* loop.

const DIR := "res://assets/audio/"
## Overall levels, in dB.
const SFX_DB := -4.0
const MUSIC_DB := -12.0
const LOOP_DB := -10.0
## Most copies of one sound playing at once (stops pile-ups in big fights).
const MAX_VOICES := 4

var _cache := {}
var _voices := {}
var _loops := {}
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_name := ""
var _music_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music_a = _flat_player(MUSIC_DB)
	_music_b = _flat_player(MUSIC_DB)


## Play a sound once. With a Vector3 `at`, it comes from that spot in the world.
func play(sound: String, at: Variant = null, volume_db := 0.0, pitch_jitter := 0.08) -> void:
	var stream := _stream(sound)
	if stream == null:
		return
	var count: int = _voices.get(sound, 0)
	if count >= MAX_VOICES:
		return
	var scene := get_tree().current_scene
	var player: Node
	if at is Vector3 and scene is Node3D:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = stream
		p3.volume_db = SFX_DB + volume_db
		p3.unit_size = 8.0
		p3.max_distance = 70.0
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
		scene.add_child(p3)
		p3.global_position = at
		p3.play()
		player = p3
	else:
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.volume_db = SFX_DB + volume_db
		p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
		(scene if scene else self).add_child(p)
		p.play()
		player = p
	_voices[sound] = count + 1
	player.connect("finished", func() -> void:
		_voices[sound] = maxi(int(_voices.get(sound, 1)) - 1, 0)
		player.queue_free())
	# If the scene changes first, the player is freed with it.
	player.tree_exiting.connect(func() -> void:
		if player.is_queued_for_deletion():
			return
		_voices[sound] = maxi(int(_voices.get(sound, 1)) - 1, 0))


## Turn a looping ambience on or off, fading over `fade` seconds.
func loop(sound: String, on: bool, volume_db := 0.0, fade := 2.0) -> void:
	var player: AudioStreamPlayer = _loops.get(sound)
	if player == null:
		if not on:
			return
		player = _flat_player(-60.0)
		player.stream = _stream(sound)
		_loops[sound] = player
	var tween := create_tween()
	if on:
		if not player.playing:
			player.play()
		tween.tween_property(player, "volume_db", LOOP_DB + volume_db, fade)
	else:
		tween.tween_property(player, "volume_db", -60.0, fade)
		tween.tween_callback(player.stop)


## Crossfade to a music track ("" fades to silence).
func music(track: String, fade := 2.5) -> void:
	if track == _music_name:
		return
	_music_name = track
	var old := _music_a
	_music_a = _music_b
	_music_b = old
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween().set_parallel(true)
	_music_tween.tween_property(_music_b, "volume_db", -60.0, fade)
	if track != "":
		_music_a.stream = _stream(track)
		_music_a.volume_db = -60.0
		_music_a.play()
		_music_tween.tween_property(_music_a, "volume_db", MUSIC_DB, fade)
	_music_tween.chain().tween_callback(_music_b.stop)


## Stop all ambience (on leaving the level).
func stop_loops(fade := 1.0) -> void:
	for sound in _loops:
		loop(sound, false, 0.0, fade)


## The stream for a sound (looping already set up), for players placed in the world.
func stream(sound: String) -> AudioStream:
	return _stream(sound)


func _stream(sound: String) -> AudioStream:
	if _cache.has(sound):
		return _cache[sound]
	var path := DIR + sound + ".wav"
	if not ResourceLoader.exists(path):
		push_warning("missing sound: " + path)
		_cache[sound] = null
		return null
	var stream := load(path) as AudioStreamWAV
	if stream and (sound.ends_with("_loop") or sound.begins_with("music_")):
		stream = stream.duplicate() as AudioStreamWAV
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	_cache[sound] = stream
	return stream


func _flat_player(volume_db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.volume_db = volume_db
	add_child(p)
	return p
