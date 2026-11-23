extends GSGameCheckSuite

const PlaylotMultitool := preload("../game/playlot_multitool.gd")
const PlaylotMultiDevice := preload("../game/playlot_multi_device.gd")
const PlaylotMultiIcons := preload("../game/playlot_multi_icons.gd")
const PlaylotConfig := preload("../game/playlot_config.gd")
const PlaylotClient := preload("../game/playlot_client.gd")
const PlaylotMultiMount := preload("../game/playlot_multi_mount.gd")
const PlaylotFigure := preload("../game/playlot_figure.gd")

## The multi-tool: its modes, the R tap and hold, the number keys that mean modes only while R is
## held, the bracelet's palm emitter and screen.
## Run: godot --headless --path . res://examples/headless_multitool.tscn

const SECTIONS := 6
const CHECKS := 50

var _entered := 0
var _completed := 0
var _client = null


func _ready() -> void:
	GSLog.set_level(GSLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("game-playlot: multi-tool")
	await _boot()
	_modes_and_wire()
	await _device()
	await _tap_and_hold()
	await _numbers()
	await _switching()
	await _mounts()
	_report_sections(_entered, _completed, SECTIONS, CHECKS)


func _boot() -> void:
	_client = PlaylotClient.new()
	_client.name = "Client"
	_client.fetch_content = false
	var config := PlaylotConfig.new()
	config.records_directory = ""
	config.record_replays = false
	_client.config = config
	add_child(_client)
	for _i in range(180):
		await get_tree().process_frame
		if _client.player != null:
			break
	for _i in range(10):
		await get_tree().process_frame


func _key(code: Key, down: bool) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = down
	return ev


func _reload_key(down: bool) -> InputEventKey:
	var ev := _key(KEY_R, down)
	return ev


func _modes_and_wire() -> void:
	_entered += 1
	print("  ", "modes and the replicated word")
	_check(PlaylotMultitool.MODES.size() >= 6, "the multi-tool has the sandbox tools as modes")
	for id in PlaylotMultitool.MODES:
		_check(PlaylotMultitool.has_mode(id) and PlaylotMultitool.label(id) != "", "mode %s has a label" % id)
	_check(not PlaylotMultitool.has_mode(&"bogus"), "a made-up mode is not one")
	var back := PlaylotMultitool.unpack(PlaylotMultitool.pack(true, 3, 9))
	_check(back["raised"] == true and back["mode_index"] == 3 and back["fire"] == 9,
		"raised, mode and fire count survive the wire word", str(back))
	_check(PlaylotMultitool.unpack(PlaylotMultitool.pack(false, -1, 0))["mode_index"] == -1,
		"no mode (a zee gun in hand) is -1")
	_check(PlaylotMultiIcons.texture(&"phys", Color.CYAN) == PlaylotMultiIcons.texture(&"phys", Color.RED),
		"a mode's icon is drawn once and cached")
	_completed += 1


func _device() -> void:
	_entered += 1
	print("  ", "the bracelet: palm emitter, screen, hologram")
	var device: Node3D = PlaylotMultiDevice.make(null)
	add_child(device)
	device.call(&"set_modes", PlaylotMultitool.MODES)
	device.call(&"set_mode", &"grav")
	await get_tree().process_frame
	var muzzle: Marker3D = device.call(&"muzzle_node")
	_check(muzzle != null and muzzle.is_inside_tree(), "the palm emitter has a muzzle marker")
	_check(device.call(&"muzzle_position").is_equal_approx(muzzle.global_position),
		"the muzzle position is the marker's: beams start there")
	_check(device.get_node_or_null("Arm/Screen") != null or device.find_child("Screen", true, false) != null,
		"the bracelet has a screen")
	_check(not device.call(&"hologram_visible"), "the hologram is closed at rest")
	device.call(&"set_raised", true)
	for _i in range(60):
		await get_tree().process_frame
	_check(device.call(&"hologram_visible") and device.call(&"raise_amount") > 0.99,
		"raising the arm opens the hologram")
	device.call(&"set_raised", false)
	for _i in range(60):
		await get_tree().process_frame
	_check(not device.call(&"hologram_visible"), "lowering it closes the hologram")

	# A beam drawn from the emitter starts at the emitter.
	var shown: Node3D = _client.presentation.on_tool_beam_from(device.call(&"muzzle_position"), Vector3(0, 0, -5), 7)
	_check(shown != null, "a beam can be drawn from the emitter")
	device.queue_free()
	_completed += 1


func _tap_and_hold() -> void:
	_entered += 1
	print("  ", "R: a tap is the old R, a hold is the selector")
	_client.presentation.settings.set_value(&"multitool_hold_seconds", 0.25)
	_client._unhandled_input(_reload_key(true))
	_check(_client.multi_held() and not _client.multi_open(), "R down: held, selector not yet open")
	_client._unhandled_input(_reload_key(false))
	_check(not _client.multi_held() and not _client.multi_open(), "a quick tap never opens the selector")

	_client._unhandled_input(_reload_key(true))
	_client._multi_tick(0.3)
	_check(_client.multi_open(), "held past the threshold the selector opens")
	_client._unhandled_input(_reload_key(false))
	_check(not _client.multi_open() and not _client.multi_held(), "releasing R closes it")

	_client.presentation.settings.set_value(&"multitool_hold_seconds", 0.0)
	_client._unhandled_input(_reload_key(true))
	_client._multi_tick(0.0)
	_check(_client.multi_open(), "with the hold at 0 it opens at once")
	_client._unhandled_input(_reload_key(false))
	_client.presentation.settings.set_value(&"multitool_hold_seconds", 0.25)
	_completed += 1


func _numbers() -> void:
	_entered += 1
	print("  ", "number keys: modes only while R is held")
	_client._set_tool(&"phys")
	var modes: Array = _client.multi_modes()
	_client._unhandled_input(_reload_key(true))
	_client._unhandled_input(_key(KEY_3, true))
	_client._unhandled_input(_key(KEY_3, false))
	_check(_client.tool == modes[2], "3 with R held picks mode 3 (%s)" % modes[2], str(_client.tool))
	_client._unhandled_input(_reload_key(false))
	_check(_client.tool == modes[2], "releasing R keeps the picked mode")

	# Without R the multi-tool leaves 1 2 3 and the wheel to the weapon inventory: it does not
	# handle the event, opens nothing and picks nothing.
	_client._set_tool(&"phys")
	var passed_on: bool = not _client._multi_input(_key(KEY_2, true))
	_check(passed_on and not _client.multi_open() and _client.tool == &"phys",
		"2 without R is not the multi-tool's: it passes on to the inventory", str(_client.tool))
	_completed += 1


func _switching() -> void:
	_entered += 1
	print("  ", "switching modes")
	_client._set_tool(&"phys")
	var modes: Array = _client.multi_modes()
	for id in modes:
		_client._set_tool(id)
		_check(_client.tool == id, "switching to %s" % id)
	_client._set_tool(&"phys")
	# A bad id from the player's own hand is refused by the client's tool list as well.
	_check(not PlaylotMultitool.has_mode(&"nope"), "an unknown mode id is not offered")
	_completed += 1


## A skeleton with only the named bones, to read the wrist lookup against rigs this build does not ship.
func _rig(names: Array) -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	for n in names:
		skeleton.add_bone(String(n))
	return skeleton


func _mounts() -> void:
	_entered += 1
	print("  ", "the wrist, on every rig")
	var rigs := {
		"mixamo": ["mixamorig_Hips", "mixamorig_LeftArm", "mixamorig_LeftForeArm", "mixamorig_LeftHand", "mixamorig_LeftHandIndex1", "mixamorig_RightHand"],
		"unreal": ["pelvis", "upperarm_l", "lowerarm_l", "hand_l", "index_01_l", "hand_r"],
		"blender": ["Hips", "UpperArm.L", "LowerArm.L", "Hand.L", "Hand.R"],
		"forearm only": ["Hips", "Shoulder_Right", "Forearm_Right", "Chest"],
	}
	var expect := {"mixamo": "mixamorig_RightHand", "unreal": "hand_r", "blender": "Hand.R", "forearm only": "Forearm_Right"}
	for key in rigs:
		var skeleton := _rig(rigs[key])
		_check(PlaylotMultiMount.wrist_bone(skeleton) == expect[key],
			"the right wrist of a %s rig is %s" % [key, expect[key]], PlaylotMultiMount.wrist_bone(skeleton))
		skeleton.free()
	var bare := _rig(["Hips", "Spine", "LeftHand"])
	_check(PlaylotMultiMount.wrist_bone(bare) == "", "a rig with no right arm has no wrist")
	bare.free()
	_check(PlaylotMultiMount.wrist_bone(null) == "", "no skeleton, no wrist")

	# Two real people: the stock look and another from the library of skins.
	for skins in [PackedInt32Array([0, 0, 0]), PackedInt32Array([5, 9, 12])]:
		var tag := "skins %s" % [skins]
		var figure := PlaylotFigure.build(1.8, skins, "mount")
		_check(figure != null, "%s: the person is built" % tag)
		if figure == null:
			continue
		add_child(figure)
		var mount := PlaylotMultiMount.mount(figure, tag)
		_check(mount != null and mount.is_inside_tree(), "%s: the bracelet has a mount" % tag)
		if mount != null:
			var device := PlaylotMultiDevice.make(null)
			mount.add_child(device)
			var up := mount.global_basis * Vector3.UP
			_check(up.dot(Vector3.UP) > 0.5, "%s: the mount stands upright at rest" % tag, str(up))
			_check(device.muzzle_position().distance_to(figure.global_position + Vector3.UP * 1.0) < 1.5,
				"%s: the muzzle is on the body, not at the origin or off in space" % tag, str(device.muzzle_position()))
			var near := figure.call(&"skeleton") != null
			_check(near, "%s: the person has a skeleton to follow" % tag)
		figure.queue_free()
	_check(PlaylotMultiMount.mount(null, "nobody") == null, "no figure gives no mount, and says so")
	_completed += 1
