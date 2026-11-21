extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var ship: Node = load("res://scenes/ship.tscn").instantiate()
	root.add_child(ship)
	var audio = ship.get_node("ShipAudio")
	if audio.manifest.is_empty() or audio.emitters.size() != audio.manifest.emitters.size() or audio.emitters.is_empty():
		push_error("Ship audio manifest or emitters unavailable")
		quit(1)
		return
	for entry: Dictionary in audio.manifest.emitters:
		for name: String in entry.sounds:
			if audio._clip(name, false) == null:
				push_error("Unreadable ship sound: " + name)
				quit(1)
				return
	# Exercise actual WAV playback across multiple short rumble loop boundaries.
	var rumble: AudioStreamWAV = audio._clip("al_low_rumble_04", true)
	var pcm: PackedByteArray = rumble.data
	var loop_byte_end: int = rumble.loop_end * 2
	if loop_byte_end <= 0 or pcm.size() < loop_byte_end + 16 or pcm.slice(loop_byte_end, loop_byte_end + 16) != pcm.slice(0, 16):
		push_error("WAV loop is missing its boundary guard samples")
		quit(1)
		return
	var playback := rumble.instantiate_playback()
	playback.start(0.0)
	var previous := 0.0
	var max_step := 0.0
	for block in 320:
		for frame: Vector2 in playback.mix_audio(1.0, 512):
			max_step = maxf(max_step, absf(frame.x - previous))
			previous = frame.x
	playback.stop()
	if max_step > 0.03:
		push_error("Rumble playback contains a discontinuity: " + str(max_step))
		quit(1)
		return
	if audio.music.stream == null or audio.ambience.stream == null:
		push_error("Ship music or ambient bed unavailable")
		quit(1)
		return
	if audio.music_enabled or audio.music.playing:
		push_error("Music should be off at startup")
		quit(1)
		return
	var event := InputEventKey.new()
	event.pressed = true
	event.physical_keycode = KEY_N
	audio._unhandled_input(event)
	if audio.ambience_enabled or not audio.ambience.stream_paused:
		push_error("Ship sound toggle failed")
		quit(1)
		return
	event.physical_keycode = KEY_M
	audio._unhandled_input(event)
	if not audio.music_enabled or audio.music.stream_paused or not audio.music.playing:
		push_error("Music enable failed")
		quit(1)
		return
	audio._unhandled_input(event)
	if audio.music_enabled or not audio.music.stream_paused:
		push_error("Music disable failed")
		quit(1)
		return
	print("Ship audio checks: PASS (", audio.emitters.size(), " emitters)")
	ship.queue_free()
	await create_timer(0.2).timeout
	quit()
