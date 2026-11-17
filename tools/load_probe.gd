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
## over50=.." (the worst frame and the frames over 50 ms in the STEP_FRAMES after it); "idle" is the line before
## any step.
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
var _last_usec := 0
var _weapons: Array[StringName] = []


func _initialize() -> void:
	var _scratch := PlaygroundPresentation.use_scratch_settings("load_probe")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frames="):
			_frames = int(a.get_slice("=", 1))
		if a.begins_with("--shot="):
			_shot = int(a.get_slice("=", 1))
		if a == "--cover":
			_cover = true
		if a == "--first-use":
			_first_use = true
		if a.begins_with("--weapons="):
			for w in a.get_slice("=", 1).split(",", false):
				_weapons.append(StringName(w))
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
		print("load_probe first-use: ", " ".join(_step_name), " worst_ms=", snappedf(_step_worst, 0.1), " over50=", _step_over)
		_step_at = -1
	if _steps.is_empty():
		return false
	var step: Array = _steps.pop_front()
	_step_name = step[0] as PackedStringArray
	_step_worst = 0.0
	_step_over = 0
	_step_at = _frame
	(step[1] as Callable).call()
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
