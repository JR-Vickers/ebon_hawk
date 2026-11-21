extends Node

const ROOT := "res://assets/generated/ship_audio/"
const MANIFEST := ROOT + "manifest.json"
const MASTER_GAIN_DB := -12.0
const MUSIC_GAIN_DB := -10.0
var clips: Dictionary = {}
var emitters: Array[AudioStreamPlayer3D] = []
var ambience: AudioStreamPlayer
var music: AudioStreamPlayer
var music_enabled := false
var ambience_enabled := true
var missing: Array[String] = []
var manifest: Dictionary = {}
var started := false
var hint: Label

func _ready() -> void:
	if not get_parent().has_meta("defer_console_start"):
		start_audio()

func start_audio() -> void:
	if started:
		return
	started = true
	if not FileAccess.file_exists(MANIFEST):
		print("Ship audio unavailable; run tools/extract_ship_audio.py (see docs/assets.md)")
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not data is Dictionary or data.get("version") != 1:
		push_warning("Invalid ship audio manifest")
		return
	manifest = data
	ambience = AudioStreamPlayer.new()
	ambience.name = "ShipAmbience"
	add_child(ambience)
	ambience.stream = _clip(data.ambient, true)
	ambience.volume_db = MASTER_GAIN_DB + _volume_db(data.ambient_volume)
	if ambience.stream != null:
		ambience.play()
	music = AudioStreamPlayer.new()
	music.name = "ShipMusic"
	add_child(music)
	music.stream = _clip(data.music, false)
	music.volume_db = MUSIC_GAIN_DB
	music.finished.connect(_music_finished)
	if music_enabled and music.stream != null:
		music.play()
	else:
		music.stream_paused = true
	for entry: Dictionary in data.emitters:
		_create_emitter(entry)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hint = Label.new()
	hint.position = Vector2(24, 185)
	hint.add_theme_font_size_override("font_size", 16)
	canvas.add_child(hint)
	_update_hint()
	if not missing.is_empty():
		push_warning("Missing ship audio clips: " + ", ".join(missing))

func _clip(name: String, loop: bool) -> AudioStream:
	var key := name + (":loop" if loop else ":once")
	if clips.has(key):
		return clips[key]
	var path := ROOT + name + ".wav"
	if not FileAccess.file_exists(path):
		missing.append(name)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	var bytes := file.get_buffer(file.get_length())
	var clip: AudioStream
	if bytes.slice(0, 4).get_string_from_ascii() == "RIFF":
		clip = AudioStreamWAV.load_from_buffer(bytes)
	else:
		clip = AudioStreamMP3.load_from_buffer(bytes)
	if clip == null:
		missing.append(name)
		return null
	if loop and clip is AudioStreamWAV:
		# Godot's WAV mixer may read the sample at loop_end before wrapping.
		# Supply the beginning of the loop there rather than reading past PCM.
		var bytes_per_frame: int = (2 if clip.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if clip.stereo else 1)
		var pcm: PackedByteArray = clip.data
		var frames := pcm.size() / bytes_per_frame
		var guard_frames := mini(frames, 8)
		if guard_frames > 0:
			pcm.append_array(pcm.slice(0, guard_frames * bytes_per_frame))
			clip.data = pcm
		clip.loop_mode = AudioStreamWAV.LOOP_FORWARD
		clip.loop_begin = 0
		clip.loop_end = frames
	elif loop and clip is AudioStreamMP3:
		clip.loop = true
	clips[key] = clip
	return clip

func _volume_db(volume: int) -> float:
	return linear_to_db(maxf(float(volume) / 127.0, 0.001))

func _create_emitter(entry: Dictionary) -> void:
	var player := AudioStreamPlayer3D.new()
	player.name = entry.template
	var p: Array = entry.position
	player.position = Vector3(p[0], p[1], p[2])
	player.max_distance = maxf(float(entry.max_distance), 0.1)
	player.unit_size = maxf(float(entry.min_distance), 0.2)
	player.volume_db = MASTER_GAIN_DB + _volume_db(entry.volume)
	player.set_meta("base_volume", player.volume_db)
	add_child(player)
	emitters.append(player)
	if entry.sounds.is_empty():
		return
	if entry.loop:
		player.stream = _clip(entry.sounds[0], true)
		if player.stream != null:
			player.play()
	elif entry.continuous:
		_schedule_effect(player, entry)

func _schedule_effect(player: AudioStreamPlayer3D, entry: Dictionary) -> void:
	var timer := Timer.new()
	timer.one_shot = true
	player.add_child(timer)
	timer.timeout.connect(func():
		if not is_instance_valid(player):
			return
		var names: Array = entry.sounds
		var index := randi_range(0, names.size() - 1) if entry.random_pick else 0
		player.stream = _clip(names[index], false)
		if player.stream != null and ambience_enabled:
			var volume_variation := int(entry.volume_variation)
			player.volume_db = MASTER_GAIN_DB + _volume_db(clampi(int(entry.volume) + randi_range(-volume_variation, volume_variation), 1, 127))
			player.play()
		var variation := int(entry.interval_variation_ms)
		var delay := maxi(250, int(entry.interval_ms) + randi_range(-variation, variation))
		timer.start(float(delay) / 1000.0))
	timer.start(randf_range(0.5, maxf(0.5, float(entry.interval_ms) / 1000.0)))

func _music_finished() -> void:
	var timer := Timer.new()
	timer.one_shot = true
	add_child(timer)
	timer.timeout.connect(func():
		if music_enabled and music != null:
			music.play()
		timer.queue_free())
	timer.start(maxf(0.01, float(manifest.music_delay_ms) / 1000.0))

func set_enabled(music_on: bool, ambience_on: bool) -> void:
	music_enabled = music_on
	ambience_enabled = ambience_on
	if music != null:
		music.stream_paused = not music_enabled
		if music_enabled and not music.playing:
			music.play()
	if ambience != null:
		ambience.stream_paused = not ambience_enabled
	for emitter in emitters:
		emitter.stream_paused = not ambience_enabled
	_update_hint()

func _unhandled_input(event: InputEvent) -> void:
	var player = get_parent().get_node_or_null("Player")
	if player == null or player.controls_locked or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_M:
		set_enabled(not music_enabled, ambience_enabled)
	elif event.physical_keycode == KEY_N:
		set_enabled(music_enabled, not ambience_enabled)
	else:
		return
	get_viewport().set_input_as_handled()

func _update_hint() -> void:
	if hint != null:
		hint.text = "M music: %s | N ship sounds: %s" % ["on" if music_enabled else "off", "on" if ambience_enabled else "off"]
