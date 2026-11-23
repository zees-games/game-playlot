extends Node

const PlaylotClient := preload("../game/playlot_client.gd")
const PlaylotConfig := preload("../game/playlot_config.gd")
const PlaylotPresentation := preload("../game/playlot_presentation.gd")
const PlaylotFigure := preload("../game/playlot_figure.gd")
const PlaylotMultiMount := preload("../game/playlot_multi_mount.gd")
const PlaylotMultiDevice := preload("../game/playlot_multi_device.gd")
const PlaylotMultitool := preload("../game/playlot_multitool.gd")

## Renders the multi-tool on the offline client: the bracelet in first person at rest and walking mid-stride, the R-hold watch pose with the hologram open, a beam from the palm emitter, the third-person view, and a remote player's wrist with a different mode's icon.
##
## Run: `xvfb-run -a godot --path . --resolution 1280x720 res://tools/render_multitool.tscn -- <out dir> [skin letter list]`

var _client: PlaylotClient = null
var _out := "/tmp"


func _ready() -> void:
	PlaylotPresentation.use_scratch_settings("render_multitool")
	_client = PlaylotClient.new()
	_client.name = "Client"
	_client.fetch_content = false
	var config := PlaylotConfig.new()
	config.records_directory = ""
	config.record_replays = false
	_client.config = config
	add_child(_client)
	_run.call_deferred()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [_out, name]
	print("%s -> %s" % [name, error_string(get_viewport().get_texture().get_image().save_png(path))])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _key(code: Key, down: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = down
	return e


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	var waited := 0.0
	while _client.gate != null and not _client.gate.is_open() and waited < 90.0:
		await _wait(0.5)
		waited += 0.5
	print("gate open after %.1f s: %s" % [waited, _client.gate.is_open()])
	await _wait(1.0)
	_client.mouse_capture_override = true
	_client._set_tool(&"phys")
	await _wait(0.8)
	var device: Node3D = _client.toy_view
	print("device: %s" % [device.call(&"describe") if device != null else "MISSING"])
	await _shot("1_fp_rest")

	# Walking: hold forward until mid-stride.
	var forward: StringName = _client.player.sampler.actions["forward"]
	Input.action_press(forward)
	await _wait(0.9)
	await _shot("2_fp_walking")
	Input.action_release(forward)
	await _wait(0.4)

	# R held: the watch pose with the hologram open.
	_client._unhandled_input(_key(KEY_R, true))
	await _wait(0.6)
	print("selector open: %s" % _client.multi_open())
	await _shot("3_fp_selector")
	_client._unhandled_input(_key(KEY_3, true))
	_client._unhandled_input(_key(KEY_3, false))
	_client._unhandled_input(_key(KEY_R, false))
	await _wait(0.6)
	await _shot("4_fp_impulse_mode")

	# A beam from the emitter.
	_client._set_tool(&"impulse")
	_client.player.controller.state.pitch = -12.0
	await _wait(0.5)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	Input.parse_input_event(press)
	await _wait(0.5)
	await _shot("5_fp_beam")
	press.pressed = false
	Input.parse_input_event(press)
	await _wait(0.3)

	# Third person.
	_client._unhandled_input(_key(KEY_F5, true))
	await _wait(1.0)
	await _shot("6_third_person")
	_client._unhandled_input(_key(KEY_R, true))
	await _wait(0.7)
	await _shot("7_third_person_raised")
	_client._unhandled_input(_key(KEY_R, false))
	await _wait(0.3)

	# Selfie: the camera in front of the player, both wrists in view.
	_client._unhandled_input(_key(KEY_F5, true))
	await _wait(1.0)
	await _shot("8_selfie")

	# The local player's own wrist, close, from a camera of this tool's own.
	var mine: Node3D = _client.player.multi_device
	print("own device: %s" % [mine.call(&"describe") if mine != null else "MISSING"])
	if mine != null:
		_client._set_tool(&"launcher")
		_client._multi_raise(true)
		await _wait(0.8)
		await _close_up(mine, "9_third_person_wrist_close")
		_client._multi_raise(false)

	# Remote players: three library figures stand in front, each with another mode on the wrist.
	var rig := Node3D.new()
	rig.name = "RemoteRig"
	add_child(rig)
	var origin: Vector3 = _client.player.global_position + Vector3(0.0, 0.0, 0.0)
	var skins := [PackedInt32Array([0, 0, 0]), PackedInt32Array([5, 9, 12]), PackedInt32Array([16, 3, 7])]
	var modes := [&"phys", &"launcher", &"toolgun"]
	var devices: Array[Node3D] = []
	for i in 3:
		var figure := PlaylotFigure.build(1.8, skins[i], "remote%d" % i) as Node3D
		rig.add_child(figure)
		figure.global_position = origin + Vector3(-1.4 + 1.4 * i, 0.0, -4.0)
		figure.rotation_degrees.y = 180.0
		var mount := PlaylotMultiMount.mount(figure, "remote%d" % i)
		var worn := PlaylotMultiDevice.make(null)
		worn.call(&"set_modes", _client.multi_modes())
		mount.add_child(worn)
		worn.call(&"set_mode", modes[i])
		worn.call(&"set_raised", i == 1)
		devices.append(worn)
	await _wait(1.2)
	await _close_up_group(devices, "10_remote_players")
	get_tree().quit(0)


## A camera of this tool's own, [param distance] from [param node], looking at it.
func _close_up(node: Node3D, name: String, distance := 1.1) -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 50.0
	cam.global_position = node.global_position + Vector3(0.0, 0.5, 0.9).normalized() * distance
	cam.look_at(node.global_position, Vector3.UP)
	cam.make_current()
	await _wait(0.3)
	await _shot(name)
	cam.queue_free()


func _close_up_group(nodes: Array[Node3D], name: String) -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 45.0
	var mid := Vector3.ZERO
	for n in nodes:
		mid += n.global_position
	mid /= float(nodes.size())
	cam.global_position = mid + Vector3(0.0, 0.2, 3.4)
	cam.look_at(mid + Vector3(0.0, 0.1, 0.0), Vector3.UP)
	cam.make_current()
	await _wait(0.3)
	await _shot(name)
	cam.queue_free()
