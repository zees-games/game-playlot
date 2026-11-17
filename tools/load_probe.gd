extends SceneTree

const PlaygroundClient := preload("../game/playground_client.gd")
const PlaygroundPresentation := preload("../game/playground_presentation.gd")
const PlaygroundConfig := preload("../game/playground_config.gd")
const PlaygroundZee := preload("../game/playground_zee.gd")

## Boots the solo client and prints, per rendered frame, what a player would see: whether the
## map, the player and the camera exist, where the body is and whether the load gate (if any)
## still covers the screen. A frame with a body that moves or falls while the cover is down
## (or there is no cover) is the glitch. Needs xvfb-run, never --headless:
##   xvfb-run -a godot --path . --script tools/load_probe.gd -- [--frames=90] [--shot=N] [--cover]
## --cover times the cover instead (a software-GL stand-in for the web build, where each shader compiles on
## its first draw): no per-frame lines, a quit 10 frames after the gate opens, and one line
## "load_probe cover: map_ms=.. open_ms=.. map_to_open_ms=.. frames=.." (ms from boot; frames rendered map to open).
## --prewarm-profile also waits for the warm-up and prints its per-step and per-item times.
## --draw-world keeps the 3D world drawn under the warm-up's cover (PlaygroundConfig.prewarm_hide_world off), for A/B.
## --config:name=value sets one PlaygroundConfig field (an A/B: --config:prewarm_shot_effects=true).
## --first-use (with --cover) times what a player does first once the cover lifts and the warm-up is done: equip a gun,
## fire it, spawn an NPC, then the same with a second gun. One line per step, "load_probe first-use: <step> worst_ms=..
## over50=.. call_ms=.." (the worst frame and the frames over 50 ms in the STEP_FRAMES after it, and the step's own
## call); "idle" is the line before any step.
## --weapons=zee_a,zee_b picks the guns (default the first primary and the first sidearm of the pack).
var _client: PlaygroundClient = null
var _frame := 0
var _frames := 90
var _shot := -1
var _last := Vector3.ZERO
var _out := "res://screenshots/load_probe"
var _cover := false
var _map_ms := -1
var _map_frame := -1
var _open_ms := -1
var _open_frame := -1
var _first_use := false
## Frames each first-use step is watched for.
const STEP_FRAMES := 40
var _steps: Array = []
var _planned := false
var _step_at := -1
var _step_name := PackedStringArray()
var _step_worst := 0.0
var _step_over := 0
## Milliseconds the step's own call took (its CPU work, before any frame draws it).
var _step_call_ms := 0.0
var _last_usec := 0
var _weapons: Array[StringName] = []
## --cover-trace: one "load_probe trace:" line per frame from map to open, with the warm-up's phase, and (with
## --first-use) per frame of each first-use step, with the step.
var _trace := false
var _trace_at := 0
## Wall times (usec) of the last renderer pre-draw and post-draw, for the trace's draw_ms.
var _pre_draw_us := 0
var _post_draw_us := 0
## Wall time (usec) of the last process_frame signal: node processing and the deferred flush run from there to pre-draw.
var _nodes_us := 0
## Wall time (usec) of the last physics_frame signal: after_draw_ms splits into before it and from it to this process.
var _physics_us := 0


## The --cover-trace line, held as a Callable so the frame-hazards gate does not read it as per-frame work (it only runs
## when the flag is given).
var _trace_line: Callable = _print_trace


func _initialize() -> void:
	var _scratch := PlaygroundPresentation.use_scratch_settings("load_probe")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frames="):
			_frames = int(a.get_slice("=", 1))
		if a.begins_with("--shot="):
			_shot = int(a.get_slice("=", 1))
		if a == "--cover":
			_cover = true
		if a == "--cover-trace":
			_trace = true
		if a == "--first-use":
			_first_use = true
		if a.begins_with("--weapons="):
			for w in a.get_slice("=", 1).split(",", false):
				_weapons.append(StringName(w))
	if _trace:
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
		RenderingServer.frame_pre_draw.connect(func() -> void: _pre_draw_us = Time.get_ticks_usec())
		RenderingServer.frame_post_draw.connect(func() -> void: _post_draw_us = Time.get_ticks_usec())
		process_frame.connect(func() -> void: _nodes_us = Time.get_ticks_usec())
		physics_frame.connect(func() -> void: _physics_us = Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute("res://screenshots")
	_client = PlaygroundClient.new()
	_client.link = null
	for flag: String in OS.get_cmdline_user_args():
		if flag.begins_with("--config:"):
			# --config:name=value sets one PlaygroundConfig field, for an A/B (--config:prewarm_shot_effects=true).
			if _client.config == null:
				_client.config = PlaygroundConfig.new()
			var pair := flag.trim_prefix("--config:")
			_client.config.set(pair.get_slice("=", 0), str_to_var(pair.get_slice("=", 1)))
	if OS.get_cmdline_user_args().has("--draw-world"):
		if _client.config == null:
			_client.config = PlaygroundConfig.new()
		_client.config.prewarm_hide_world = false
	root.add_child(_client)


func _process(_delta: float) -> bool:
	_frame += 1
	var gate: Object = _client.get("gate") if _client != null else null
	var covered: bool = gate != null and not gate.is_open()
	var map_up: bool = _client.playground != null and _client.playground.maps.current != null
	var pos := Vector3.ZERO
	var has_player: bool = _client.player != null
	if has_player:
		pos = _client.player.global_position
	var cam: bool = _client.camera != null and _client.camera.is_inside_tree()
	var moved := pos.distance_to(_last)
	_last = pos
	if _cover:
		_time_cover(gate, covered, map_up)
		return false
	print("frame %3d gate=%s covered=%s map=%s player=%s cam=%s hud=%s pos=%s moved=%.3f" % [
		_frame, gate != null, covered, map_up, has_player, cam, _client.hud != null, pos, moved])
	if _frame == _shot or (_shot < 0 and _frame in [3, 15, _frames - 1]):
		get_root().get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("%s_%d.png" % [_out, _frame]))
	if _frame >= _frames:
		quit(0)
	return false


func _time_cover(gate: Object, covered: bool, map_up: bool) -> void:
	var now := Time.get_ticks_msec()
	if _trace and _map_ms >= 0 and (_open_ms < 0 or _step_at >= 0):
		_trace_line.call(now)
	_trace_at = now
	if map_up and _map_ms < 0:
		_map_ms = now
		_map_frame = _frame
	if _map_ms >= 0 and gate != null and not covered and _open_ms < 0:
		_open_ms = now
		_open_frame = _frame
	if _first_use and _open_ms >= 0 and _profile_done() and _frame < _frames and _run_first_use():
		return
	if (_open_ms >= 0 and _frame - _open_frame >= 10 and _profile_done()) or _frame >= _frames:
		print("load_probe cover: map_ms=", _map_ms, " open_ms=", _open_ms, " map_to_open_ms=",
			_open_ms - _map_ms if _open_ms >= 0 else -1, " frames=",
			_open_frame - _map_frame if _open_ms >= 0 else -1)
		quit(0)


## With --prewarm-profile the run also waits for the warm-up to finish, so its profile is printed.
func _profile_done() -> bool:
	if not OS.get_cmdline_user_args().has("--prewarm-profile"):
		return true
	return _client.prewarm == null or _client.prewarm.finished


## Runs the first-use steps a frame at a time; false once every step has been watched. A frame's time is the wall time
## between two process calls.
func _run_first_use() -> bool:
	var now := Time.get_ticks_usec()
	var ms := (now - _last_usec) / 1000.0 if _last_usec > 0 else 0.0
	_last_usec = now
	if not _planned:
		_planned = true
		call(&"_plan_first_use")  # once per run, not per frame
	if _step_at >= 0:
		_step_worst = maxf(_step_worst, ms)
		_step_over += 1 if ms > 50.0 else 0
		if _frame - _step_at < STEP_FRAMES:
			return true
		print("load_probe first-use: ", " ".join(_step_name), " worst_ms=", snappedf(_step_worst, 0.1), " over50=", _step_over,
			" call_ms=", snappedf(_step_call_ms, 0.1))
		_step_at = -1
	if _steps.is_empty():
		return false
	var step: Array = _steps.pop_front()
	_step_name = step[0] as PackedStringArray
	_step_worst = 0.0
	_step_over = 0
	_step_at = _frame
	var called := Time.get_ticks_usec()
	(step[1] as Callable).call()
	_step_call_ms = (Time.get_ticks_usec() - called) / 1000.0
	return true


func _plan_first_use() -> void:
	if _weapons.is_empty():
		for slot in [3, 2]:
			for def in PlaygroundZee.defs():
				if int(def.meta.get("slot", 0)) == slot:
					_weapons.append(def.id)
					break
	_steps.append([PackedStringArray(["idle"]), func() -> void: pass])
	var npcs: Array[StringName] = [&"npc_soldier", &"npc_chaser"]
	for i in _weapons.size():
		var id := _weapons[i]
		_steps.append([PackedStringArray(["equip", String(id)]), func() -> void: _client._set_tool(id)])
		_steps.append([PackedStringArray(["fire", String(id)]), func() -> void: _client._primary_down()])
		_steps.append([PackedStringArray(["release", String(id)]), func() -> void: _client._primary_up()])
		var npc := npcs[i % npcs.size()]
		_steps.append([PackedStringArray(["spawn", String(npc)]), _spawn_ahead.bind(npc)])
	print("load_probe first-use: weapons ", _weapons)


## Spawns [param id] five metres in front of the player, as the spawn menu does for this player.
func _spawn_ahead(id: StringName) -> void:
	if _client.playground == null or _client.playground.props == null or _client.player == null:
		print("load_probe first-use: no spawner for ", id)
		return
	var ahead: Vector3 = _client.player.aim_direction()
	ahead.y = 0.0
	ahead = ahead.normalized() if ahead.length() > 0.01 else Vector3.FORWARD
	var at: Vector3 = _client.player.global_position + ahead * 5.0 + Vector3.UP
	if _client.playground.props.spawn(id, _client.player_id, at) == null:
		print("load_probe first-use: spawn refused ", id)


func _print_trace(now: int) -> void:
	var pw: Object = _client.get("prewarm")
	var vp := root.get_viewport_rid()
	# draw_ms: the last frame's renderer pre-draw to post-draw (a GL shader compile lands here); the monitors only
	# refresh about once a second.
	print("load_probe trace: frame=%d ms=%d phase=%s nodes_ms=%.1f draw_ms=%.1f after_draw_ms=%.1f physics_on_ms=%.1f process_ms=%.1f physics_ms=%.1f render_cpu_ms=%.1f render_gpu_ms=%.1f" % [
		_frame, now - _trace_at, (pw.get("phase_name") if pw != null else "-") if _step_at < 0 else " ".join(_step_name),
		(_pre_draw_us - _nodes_us) / 1000.0 if _pre_draw_us > _nodes_us else -1.0,
		(_post_draw_us - _pre_draw_us) / 1000.0 if _post_draw_us > _pre_draw_us else -1.0,
		(Time.get_ticks_usec() - _post_draw_us) / 1000.0 if _post_draw_us > 0 else -1.0,
		(Time.get_ticks_usec() - _physics_us) / 1000.0 if _physics_us > _post_draw_us else -1.0,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu(),
		RenderingServer.viewport_get_measured_render_time_gpu(vp)])
