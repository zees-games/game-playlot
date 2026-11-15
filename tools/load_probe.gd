extends SceneTree

const PlaygroundClient := preload("../game/playground_client.gd")
const PlaygroundPresentation := preload("../game/playground_presentation.gd")
const PlaygroundConfig := preload("../game/playground_config.gd")

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


func _initialize() -> void:
	var _scratch := PlaygroundPresentation.use_scratch_settings("load_probe")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frames="):
			_frames = int(a.get_slice("=", 1))
		if a.begins_with("--shot="):
			_shot = int(a.get_slice("=", 1))
		if a == "--cover":
			_cover = true
	DirAccess.make_dir_recursive_absolute("res://screenshots")
	_client = PlaygroundClient.new()
	_client.link = null
	if OS.get_cmdline_user_args().has("--draw-world"):
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
	if (_open_ms >= 0 and _frame - _open_frame >= 10 and _profile_done()) or _frame >= _frames:
		print("load_probe cover: map_ms=%d open_ms=%d map_to_open_ms=%d frames=%d" % [
			_map_ms, _open_ms, _open_ms - _map_ms if _open_ms >= 0 else -1,
			_open_frame - _map_frame if _open_ms >= 0 else -1])
		quit(0)


## With --prewarm-profile the run also waits for the warm-up to finish, so its profile is printed.
func _profile_done() -> bool:
	if not OS.get_cmdline_user_args().has("--prewarm-profile"):
		return true
	return _client.prewarm == null or _client.prewarm.finished
