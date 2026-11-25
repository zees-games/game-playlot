extends Node

const PlaylotClient := preload("../game/playlot_client.gd")
const PlaylotConfig := preload("../game/playlot_config.gd")
const PlaylotPresentation := preload("../game/playlot_presentation.gd")
const PlaylotFigure := preload("../game/playlot_figure.gd")
const PlaylotMultiMount := preload("../game/playlot_multi_mount.gd")
const PlaylotMultiDevice := preload("../game/playlot_multi_device.gd")
const PlaylotMultitool := preload("../game/playlot_multitool.gd")

## Renders the multi-tool on the offline client as filmstrip sheets (frames left to right, top to bottom), once per avatar: the stock figure and two library avatars of other proportions. Per avatar: rest, walk, sprint, jump and land, R-hold raise / mode-change flash / lower, the hologram open on every mode, every mode's burst from the palm and the gravity carry, viewmodel_fov narrow to wide, third person rest and raised; then animated remote figures wearing it in several modes, and spawn mode from the Q menu's right click.
## Run: `tools/render_multitool.sh [out dir]` (GPU box via gpu.sh), or `xvfb-run -a godot --path . --resolution 1280x720 res://tools/render_multitool.tscn -- <out dir>`

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


func _secondary(down: bool) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = down
	Input.parse_input_event(press)


## A crate on the aim line, three metres out, for the physics and gravity guns to take.
func _crate_ahead() -> void:
	_client.playlot.props.spawn(&"crate", _client.player_id, \
		_client.player.eye_position() + _client.player.aim_direction() * 3.0)
	await get_tree().physics_frame


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
	var count := AVATARS.size() if args.size() < 2 or args[1] == "perf" else clampi(int(args[1]), 1, AVATARS.size())
	DirAccess.make_dir_recursive_absolute(_out)
	var waited := 0.0
	while _client.gate != null and not _client.gate.is_open() and waited < 90.0:
		await _wait(0.5)
		waited += 0.5
	print("gate open after %.1f s: %s" % [waited, _client.gate.is_open()])
	await _wait(1.0)
	_client.mouse_capture_override = true
	if args.has("perf"):
		await _perf()
		get_tree().quit(0)
		return
	if args.has("spawn"):
		await _spawn_mode()
		get_tree().quit(0)
		return
	for a in count:
		await _avatar(a)
	await _spawn_mode()
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

	await _avatar_walk(tag)

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

	await _avatar_beams(tag)

	# viewmodel_fov: the arms and the bracelet on them scale together, narrow, Playlot's default and wide.
	_client._unhandled_input(_key(KEY_R, true))
	for fov in [40.0, 54.0, 75.0]:
		get_tree().call_group(&"gs_view_model", &"set_hands_fov_at_4_3", fov)
		await _wait(0.5)
		await _grab()
	get_tree().call_group(&"gs_view_model", &"set_hands_fov_at_4_3", 54.0)
	_client._unhandled_input(_key(KEY_R, false))
	await _wait(0.5)
	await _sheet("%s_9_viewmodel_fov" % tag)

	await _avatar_third_person(tag)


## Walk, sprint and jump-land, each a contact sheet.
func _avatar_walk(tag: String) -> void:
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


## Every mode's burst, then the gravity gun's carry.
func _avatar_beams(tag: String) -> void:
	# Every mode's own burst from the palm, looking a little down at the floor so the aim point is in view:
	# one frame early in the burst, one at its end (the physics gun's held beam, the others gone).
	_client.player.controller.state.pitch = -14.0
	for id: StringName in PlaylotMultitool.MODES:
		_client._set_tool(id)
		await _wait(0.4)
		if id == &"phys":
			await _crate_ahead()
		_fire(true)
		await _wait(0.06)
		await _grab()
		await _wait(0.3)
		await _grab()
		_fire(false)
		await _wait(0.25)
	# The gravity gun's carry: the right button pulls a crate in and holds it, beam and palm ring orange.
	_client._set_tool(&"grav")
	await _crate_ahead()
	_secondary(true)
	await _wait(0.6)
	await _grab()
	_secondary(false)
	await _wait(0.3)
	await _sheet("%s_7_beams" % tag)
	_client.player.controller.state.pitch = 0.0
	# The crates and launched props would otherwise fill the next avatar's view.
	_client.playlot.props.clear_player(_client.player_id, GSPropSpawner.REASON_CLEANUP)
	await _wait(0.2)


## The third-person camera with the device raised, then back to first person.
func _avatar_third_person(tag: String) -> void:
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
		# From ahead of the player on the wrist's side: the screen normal puts the list over the device.
		await _close_up(mine, 1.3, Callable(), _client.player, 0.6)
	_client._multi_raise(false)
	await _sheet("%s_8_third_person" % tag)
	# F5 cycles third person and the selfie view back to first.
	_client._unhandled_input(_key(KEY_F5, true))
	await _wait(0.5)
	_client._unhandled_input(_key(KEY_F5, true))
	await _wait(0.8)


## Spawn mode from the Q menu: the card's right-click menu, then the item armed (screen and hologram)
## and a held left button putting barrels down where the player looks.
func _spawn_mode() -> void:
	_client.player.set_skins(AVATARS[0])
	_client._set_tool(&"phys")
	_client.player.controller.state.pitch = -18.0
	await _wait(0.6)
	_client.open_spawn_menu()
	await _wait(0.6)
	var card: Button = _client.menu.card_for(&"barrel")
	var at := Vector2i(card.get_global_rect().get_center()) if card != null else Vector2i(560, 300)
	_client.menu.open_context("prop", &"barrel", false, at)
	await _wait(0.3)
	await _grab("s_1_context_menu")
	_client.menu.choose_context(0)
	await _wait(0.6)
	await _grab("s_2_armed")
	_client._unhandled_input(_key(KEY_R, true))
	await _wait(0.7)
	await _grab("s_3_hologram")
	_client._unhandled_input(_key(KEY_R, false))
	await _wait(0.5)
	_fire(true)
	await _roll(6, 0.2)
	_fire(false)
	await _wait(0.4)
	await _grab()
	await _sheet("s_4_spam_spawn")
	_client.player.controller.state.pitch = 0.0

## Library figures in front of the camera, animated as the client animates a remote player (idle, walking
## on the spot), each in another mode, the arm raised (the gun hold) or not; then every one raised and firing.
func _remotes() -> void:
	var rig := Node3D.new()
	rig.name = "RemoteRig"
	add_child(rig)
	# Off to the side of the crates the beam shots left on the aim line.
	var origin: Vector3 = _client.player.global_position + Vector3(8.0, 0.0, 0.0)
	var modes := [&"phys", &"spawn", &"toolgun"]
	var speeds := [0.0, 0.0, 1.6]
	var devices: Array[Node3D] = []
	var bodies: Array[Node3D] = []
	var people: Array[GSHumanoidFigure] = []
	for i in 3:
		var figure := PlaylotFigure.build(1.8, AVATARS[i], "remote%d" % i) as Node3D
		rig.add_child(figure)
		figure.global_position = origin + Vector3(-2.6 + 2.6 * i, 0.0, -4.0)
		figure.rotation_degrees.y = 160.0
		var person := PlaylotFigure.person_of(figure)
		people.append(person)
		if i == 1 and person != null:
			person.set_hold(GSHumanoidFigure.Hold.GUN)
		var mount := PlaylotMultiMount.mount(figure, "remote%d" % i)
		if mount == null:
			continue
		var worn := PlaylotMultiDevice.make(null)
		worn.call(&"set_modes", _client.multi_modes())
		mount.add_child(worn)
		worn.call(&"set_mode", modes[i])
		worn.call(&"set_raised", i == 1)
		devices.append(worn)
		bodies.append(figure)
	var drive := func() -> void:
		var delta := get_process_delta_time()
		for i in people.size():
			if people[i] != null:
				var speed: float = speeds[i]
				people[i].set_motion({"speed": speed, "vertical": 0.0, "on_floor": true, "crouched": false})
				people[i].animate(speed, delta)
	get_tree().process_frame.connect(drive)
	await _wait(1.2)
	await _close_up_group(devices)
	for i in devices.size():
		# A hanging arm's screen faces out to the side: seen from there, not from the front.
		await _close_up(devices[i], 1.0, Callable(), bodies[i], 0.25)
	# Every one raised, then a shot each: the burst leaves each wrist's palm in its own mode's look.
	for i in people.size():
		if people[i] != null:
			people[i].set_hold(GSHumanoidFigure.Hold.GUN)
	for d in devices:
		d.call(&"set_raised", true)
	await _wait(0.8)
	await _close_up_group(devices)
	# Each fires forward and out past its own wrist, so the burst crosses the frame rather than the lens.
	var shoot := func(targets: Array, owners: Array) -> void:
		for i in targets.size():
			(targets[i] as Node3D).call(&"kick", _outward(targets[i], owners[i], 0.0, 0.25))
	await _close_up_group(devices, shoot.bind(devices, bodies))
	for i in devices.size():
		await _close_up(devices[i], 1.6, shoot.bind([devices[i]], [bodies[i]]), bodies[i])
	get_tree().process_frame.disconnect(drive)
	await _sheet("r_remotes")


## The device's cost per frame on this box: GPU and CPU render time, process time and draw calls,
## averaged over [param frames] frames worn at rest, raised (hologram open) and taken off and stopped.
func _perf(frames := 300) -> void:
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	_client._set_tool(&"phys")
	var rows := {}
	# The first frames after loading pay for shader compiles: wait them out before any case.
	await _wait(2.0)
	for case in ["worn", "raised", "without"]:
		# Raised as a player raises it (R held); "without" puts the tool away, so no device is built at all.
		if case == "raised":
			_client._unhandled_input(_key(KEY_R, true))
		elif case == "without":
			_client._unhandled_input(_key(KEY_R, false))
			_client._set_tool(&"")
		await _wait(1.0)
		var sum := {"gpu_ms": 0.0, "cpu_ms": 0.0, "process_ms": 0.0, "draws": 0.0, "objects": 0.0, "device_meshes": 0.0}
		for i in frames:
			await get_tree().process_frame
			sum["gpu_ms"] += RenderingServer.viewport_get_measured_render_time_gpu(vp)
			sum["cpu_ms"] += RenderingServer.viewport_get_measured_render_time_cpu(vp)
			sum["process_ms"] += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			# The global monitors, not the viewport's render info: that read the same 24 with the device hidden.
			sum["draws"] += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			sum["objects"] += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
			var device: Node3D = _client.toy_view
			sum["device_meshes"] += _shown_meshes(device) if device != null and is_instance_valid(device) else 0
		for k in sum:
			sum[k] = snappedf(sum[k] / frames, 0.001)
		rows[case] = sum
		print("perf %s: %s" % [case, sum])
	_client._set_tool(&"phys")
	var file := FileAccess.open(_out.path_join("perf.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"frames": frames, "gpu": RenderingServer.get_video_adapter_name(), "cases": rows}, "\t"))


## How many of [param node]'s geometry instances (itself included) are drawn this frame.
static func _shown_meshes(node: Node) -> int:
	var n := 1 if node is GeometryInstance3D and (node as GeometryInstance3D).is_visible_in_tree() else 0
	for child in node.get_children():
		n += _shown_meshes(child)
	return n


## A camera of this tool's own, [param distance] from [param node], looking at it: in front of its screen,
## or with a [param body], from ahead of that body on the wrist's side, so the body never blocks the view.
## [param before] runs just before the shot, so a burst is caught in flight.
func _close_up(node: Node3D, distance := 0.6, before := Callable(), body: Node3D = null, ahead := 0.9) -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 50.0
	var screen := node.find_child("Screen", true, false) as Node3D
	var out := Vector3(0.0, 0.5, 0.9).normalized()
	if body != null:
		out = _outward(node, body, 0.35, ahead)
	elif screen != null:
		out = (screen.global_basis.z.normalized() + Vector3(0.0, 0.35, 0.0)).normalized()
	cam.global_position = node.global_position + out * distance
	cam.look_at(node.global_position, Vector3.UP if absf(out.y) < 0.98 else Vector3.FORWARD)
	cam.make_current()
	await _wait(0.3)
	await _shoot(before)
	cam.queue_free()


## [param ahead] of [param body]'s front and the rest out to [param node]'s side of it, lifted by [param up].
func _outward(node: Node3D, body: Node3D, up: float, ahead := 0.9) -> Vector3:
	var side := node.global_position - body.global_position
	side.y = 0.0
	var front := -body.global_basis.z
	front.y = 0.0
	return (front.normalized() * ahead + side.normalized() * (1.0 - ahead) + Vector3(0.0, up, 0.0)).normalized()


func _close_up_group(nodes: Array[Node3D], before := Callable()) -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 45.0
	var mid := Vector3.ZERO
	for n in nodes:
		mid += n.global_position
	mid /= float(nodes.size())
	cam.global_position = mid + Vector3(0.0, 0.4, 5.2)
	cam.look_at(mid + Vector3(0.0, 0.1, 0.0), Vector3.UP)
	cam.make_current()
	await _wait(0.3)
	await _shoot(before)
	cam.queue_free()


func _shoot(before: Callable) -> void:
	if before.is_valid():
		before.call()
		await _wait(0.07)
	await _grab()
