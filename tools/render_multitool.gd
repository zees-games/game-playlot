extends Node

const PlaylotClient := preload("../game/playlot_client.gd")
const PlaylotConfig := preload("../game/playlot_config.gd")
const PlaylotPresentation := preload("../game/playlot_presentation.gd")
const PlaylotFigure := preload("../game/playlot_figure.gd")
const PlaylotMultiMount := preload("../game/playlot_multi_mount.gd")
const PlaylotMultiDevice := preload("../game/playlot_multi_device.gd")
const PlaylotMultitool := preload("../game/playlot_multitool.gd")

## Renders the multi-tool on the offline client as filmstrip sheets (frames left to right, top to bottom), once per
## avatar: the stock figure and two library avatars of other proportions. Per avatar: rest, walk, sprint, jump and
## land, R-hold raise / mode-change flash / lower, the hologram open on every mode, every mode's beam from the palm,
## third person rest and raised; then remote figures wearing it in several modes, raised and not.
##
## Run: `tools/render_multitool.sh [out dir]` (GPU box via gpu.sh), or
## `xvfb-run -a godot --path . --resolution 1280x720 res://tools/render_multitool.tscn -- <out dir>`

var AVATARS := [PackedInt32Array(), PackedInt32Array([5, 9, 12]), PackedInt32Array([16, 3, 7])]
const CELL := Vector2i(640, 360)

var _client: PlaylotClient = null
var _out := "/tmp"
var _frames: Array[Image] = []


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


## One frame into the open strip (or saved alone when [param name] is set), the loading toast hidden.
func _grab(name := "") -> void:
	var busy := GSBusyIndicator.current()
	if busy != null:
		busy.visible = false
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if name != "":
		print("%s -> %s" % [name, error_string(image.save_png("%s/%s.png" % [_out, name]))])
		return
	image.resize(CELL.x, CELL.y, Image.INTERPOLATE_BILINEAR)
	_frames.append(image)


## [param count] frames [param step] seconds apart into the open strip.
func _roll(count: int, step: float) -> void:
	for i in count:
		await _grab()
		await _wait(step)


## Saves the open strip as one sheet, three frames a row.
func _sheet(name: String) -> void:
	var cols := mini(3, _frames.size())
	var rows := ceili(float(_frames.size()) / float(maxi(cols, 1)))
	var sheet := Image.create(CELL.x * cols, CELL.y * rows, false, Image.FORMAT_RGBA8)
	for i in _frames.size():
		var frame := _frames[i]
		frame.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(frame, Rect2i(Vector2i.ZERO, CELL), Vector2i((i % cols) * CELL.x, floori(float(i) / float(cols)) * CELL.y))
	print("%s (%d frames) -> %s" % [name, _frames.size(), error_string(sheet.save_png("%s/%s.png" % [_out, name]))])
	_frames.clear()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _key(code: Key, down: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = down
	return e


func _tap(code: Key) -> void:
	_client._unhandled_input(_key(code, true))
	_client._unhandled_input(_key(code, false))


func _fire(down: bool) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = down
	Input.parse_input_event(press)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	# A second argument renders only that many avatars (and no remotes): a quick pass.
	var count := AVATARS.size() if args.size() < 2 else clampi(int(args[1]), 1, AVATARS.size())
	DirAccess.make_dir_recursive_absolute(_out)
	var waited := 0.0
	while _client.gate != null and not _client.gate.is_open() and waited < 90.0:
		await _wait(0.5)
		waited += 0.5
	print("gate open after %.1f s: %s" % [waited, _client.gate.is_open()])
	await _wait(1.0)
	_client.mouse_capture_override = true
	for a in count:
		await _avatar(a)
	if count == AVATARS.size():
		await _remotes()
	get_tree().quit(0)


func _avatar(a: int) -> void:
	var tag := "a%d" % a
	_client.player.set_skins(AVATARS[a])
	_client._set_tool(&"phys")
	_client.player.controller.state.pitch = 0.0
	await _wait(1.0)
	var device: Node3D = _client.toy_view
	print("%s device: %s" % [tag, device.call(&"describe") if device != null else "MISSING"])
	await _grab("%s_1_rest" % tag)

	var actions: Dictionary = _client.player.sampler.actions
	Input.action_press(actions["forward"])
	await _wait(0.3)
	await _roll(6, 0.11)
	await _sheet("%s_2_walk" % tag)
	Input.action_press(actions["sprint"])
	await _wait(0.4)
	await _roll(6, 0.09)
	await _sheet("%s_3_sprint" % tag)
	Input.action_release(actions["sprint"])
	Input.action_press(actions["jump"])
	await _wait(0.05)
	Input.action_release(actions["jump"])
	await _roll(9, 0.1)
	await _sheet("%s_4_jump_land" % tag)
	Input.action_release(actions["forward"])
	await _wait(0.6)

	# R held: raise, a mode change's flash, then release to lower.
	_client._unhandled_input(_key(KEY_R, true))
	await _roll(6, 0.05)
	_tap(KEY_3)
	await _roll(3, 0.04)
	_client._unhandled_input(_key(KEY_R, false))
	await _roll(6, 0.05)
	await _sheet("%s_5_raise_flash_lower" % tag)

	# The hologram open on each mode.
	_client._unhandled_input(_key(KEY_R, true))
	await _wait(0.6)
	for m in PlaylotMultitool.MODES.size():
		_tap((KEY_1 + m) as Key)
		await _wait(0.25)
		await _grab()
	_client._unhandled_input(_key(KEY_R, false))
	await _wait(0.4)
	await _sheet("%s_6_holo_modes" % tag)

	# Every mode's beam from the palm, looking a little down at the floor so the aim point is in view.
	_client.player.controller.state.pitch = -14.0
	for id: StringName in PlaylotMultitool.MODES:
		_client._set_tool(id)
		await _wait(0.4)
		# Only the physics gun draws a beam, to what it holds: a crate on the aim line to grab.
		if id == &"phys":
			var _crate: Variant = _client.playlot.props.spawn(&"crate", _client.player_id, \
				_client.player.eye_position() + _client.player.aim_direction() * 3.0)
			await get_tree().physics_frame
		_fire(true)
		await _wait(0.35)
		await _grab()
		_fire(false)
		await _wait(0.25)
	await _sheet("%s_7_beams" % tag)
	_client.player.controller.state.pitch = 0.0

	_client._set_tool(&"phys")
	_client._unhandled_input(_key(KEY_F5, true))
	await _wait(1.0)
	var cam := get_viewport().get_camera_3d()
	print("%s third person: camera %.1f m from the player" % [tag, cam.global_position.distance_to(_client.player.global_position)])
	await _grab()
	_client._multi_raise(true)
	await _wait(0.7)
	await _grab()
	var mine: Node3D = _client.player.multi_device
	if mine != null:
		await _close_up(mine)
	_client._multi_raise(false)
	await _sheet("%s_8_third_person" % tag)
	# F5 cycles third person and the selfie view back to first.
	_client._unhandled_input(_key(KEY_F5, true))
	await _wait(0.5)
	_client._unhandled_input(_key(KEY_F5, true))
	await _wait(0.8)


## Library figures in front of the camera, each with another mode, raised (the gun hold) or not.
func _remotes() -> void:
	var rig := Node3D.new()
	rig.name = "RemoteRig"
	add_child(rig)
	var origin: Vector3 = _client.player.global_position
	var modes := [&"phys", &"launcher", &"toolgun"]
	var devices: Array[Node3D] = []
	for i in 3:
		var figure := PlaylotFigure.build(1.8, AVATARS[i], "remote%d" % i) as Node3D
		rig.add_child(figure)
		figure.global_position = origin + Vector3(-1.4 + 1.4 * i, 0.0, -4.0)
		figure.rotation_degrees.y = 160.0
		if i == 1 and figure.has_method(&"set_hold"):
			figure.call(&"set_hold", GSHumanoidFigure.Hold.GUN)
		var mount := PlaylotMultiMount.mount(figure, "remote%d" % i)
		if mount == null:
			continue
		var worn := PlaylotMultiDevice.make(null)
		worn.call(&"set_modes", _client.multi_modes())
		mount.add_child(worn)
		worn.call(&"set_mode", modes[i])
		worn.call(&"set_raised", i == 1)
		devices.append(worn)
	await _wait(1.2)
	await _close_up_group(devices)
	for d in devices:
		await _close_up(d, 0.8)
	await _sheet("r_remotes")


## A camera of this tool's own, [param distance] from [param node], looking at it.
func _close_up(node: Node3D, distance := 1.1) -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 50.0
	cam.global_position = node.global_position + Vector3(0.0, 0.5, 0.9).normalized() * distance
	cam.look_at(node.global_position, Vector3.UP)
	cam.make_current()
	await _wait(0.3)
	await _grab()
	cam.queue_free()


func _close_up_group(nodes: Array[Node3D]) -> void:
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
	await _grab()
	cam.queue_free()

