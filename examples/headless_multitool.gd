extends GSGameCheckSuite

const PlaylotMultitool := preload("../game/playlot_multitool.gd")
const PlaylotMultiDevice := preload("../game/playlot_multi_device.gd")
const PlaylotMultiIcons := preload("../game/playlot_multi_icons.gd")
const PlaylotConfig := preload("../game/playlot_config.gd")
const PlaylotClient := preload("../game/playlot_client.gd")
const PlaylotMultiMount := preload("../game/playlot_multi_mount.gd")
const PlaylotFigure := preload("../game/playlot_figure.gd")
const PlaylotProp := preload("../game/playlot_prop.gd")

## The multi-tool: its modes, the R tap and hold, the number keys that mean modes only while R is
## held, the bracelet's palm emitter and screen.
## Run: godot --headless --path . res://examples/headless_multitool.tscn

const SECTIONS := 8
const CHECKS := 90

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
	await _effects()
	await _tap_and_hold()
	await _numbers()
	await _switching()
	await _spawn_mode()
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


## Every mode has its own burst from the palm on a kick, and a held prop spins the palm ring and colours the beam.
func _effects() -> void:
	_entered += 1
	print("  ", "the palm's effect per mode")
	var device: Node3D = PlaylotMultiDevice.make(null)
	add_child(device)
	device.call(&"set_modes", PlaylotMultitool.MODES)
	var fx: Node3D = device.call(&"effects")
	for id in PlaylotMultitool.MODES:
		device.call(&"set_mode", id)
		device.call(&"kick", Vector3.FORWARD)
		await get_tree().process_frame
		var seen: Dictionary = fx.call(&"describe")
		_check(seen["fired"] == id and seen["bursting"], "a %s shot bursts from the palm" % id, str(seen))
	for _i in range(40):
		await get_tree().process_frame
	_check(not fx.call(&"describe")["bursting"], "and the burst is gone a moment later")
	device.call(&"hold_to", Vector3(0, 0, -3))
	await get_tree().process_frame
	_check(fx.call(&"describe")["holding"], "a held prop spins the palm ring")
	var beam: Node3D = _client.presentation.on_tool_beam_from(Vector3.ZERO, Vector3(0, 0, -5), 8)
	_client.presentation.tint_beam(beam, PlaylotMultitool.colour(&"grav"))
	var glow := beam.get_node(^"Glow") as MeshInstance3D
	var tinted := glow.material_override as StandardMaterial3D
	_check(tinted != null and tinted.albedo_color.r > 0.9 and tinted.albedo_color.b < 0.3,
		"a gravity-gun carry's beam is drawn orange", str(tinted.albedo_color if tinted != null else null))
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


## Spawn mode from the Q menu: a card's right click, the aimed spawn, the held repeat and a refusal.
func _spawn_mode() -> void:
	_entered += 1
	print("  ", "spawn mode: Q menu right click, aimed spawns, repeat, limits")
	var menu = _client.menu
	var popup: PopupMenu = menu.open_context("prop", &"crate", false, Vector2i(40, 40))
	_check(popup != null and popup.item_count == 1 and popup.get_item_text(0) == "Spawn with multi-tool",
		"a prop card's right click offers 'Spawn with multi-tool'", str(popup.item_count if popup != null else -1))
	popup = menu.open_context("weapon", &"pistol", true, Vector2i(40, 40))
	_check(popup.item_count == 2, "a weapon card's also offers dropping one, as its right click did")
	popup.hide()
	_client._set_tool(&"phys")
	_client.open_spawn_menu()
	_check(_client.screens.is_open(menu.screen_id()), "the Q menu is open")
	menu.open_context("prop", &"crate", false, Vector2i(40, 40))
	menu.choose_context(0)
	_check(_client.tool == &"spawn" and _client.weapon != null and _client.weapon.armed == &"prop:crate",
		"choosing it equips the multi-tool in spawn mode with the crate armed",
		"%s %s" % [_client.tool, _client.weapon.armed if _client.weapon != null else &"-"])
	_check(not _client.screens.is_open(menu.screen_id()) and _client._spawn_pick_name != "",
		"and closes the menu, the screen naming the item", _client._spawn_pick_name)
	var device: Node3D = PlaylotMultiDevice.make(null)
	add_child(device)
	device.call(&"set_modes", PlaylotMultitool.MODES)
	device.call(&"set_mode", &"spawn")
	device.call(&"set_pick", "Crate")
	_check(device.call(&"pick_text") == "Crate", "the bracelet's screen carries the picked item")
	device.queue_free()

	var weapon = _client.weapon
	var spawner: GSPropSpawner = weapon.spawner
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(500, -50.5, 500)
	add_child(floor_body)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space: PhysicsDirectSpaceState3D = (_client.player as Node3D).get_world_3d().direct_space_state
	var from := Vector3(500, -45, 500)
	var placed: GSResult = weapon.place(space, from, Vector3.DOWN)
	var prop: GSPropInstance = placed.value if placed.ok else null
	var bottom := 0.0
	if prop != null:
		bottom = (prop.node as Node3D).global_position.y - PlaylotProp.extent_of(prop.def).y * 0.5
	_check(prop != null and absf(bottom - (-50.0)) < 0.05 and Vector2(prop.node.global_position.x, prop.node.global_position.z).distance_to(Vector2(500, 500)) < 0.05,
		"a click puts it down at the aimed point, resting on the surface", "bottom %.3f" % bottom)

	var config = weapon.game.config
	var every: float = config.multi_spawn_repeat
	config.multi_spawn_repeat = 0.1
	# The spawner's own anti-spam interval runs on simulated time, which this check does not advance.
	var interval: float = spawner.limits.spawn_interval
	spawner.limits.spawn_interval = 0.0
	weapon.primary(space, from, Vector3.DOWN)
	var early = weapon.held(space, from, Vector3.DOWN, 0.05)
	var due = weapon.held(space, from, Vector3.DOWN, 0.06)
	_check(early == null and due != null and due.ok, "held, the next one waits for the repeat interval",
		str(due.error.message if due != null and not due.ok else due))
	config.multi_spawn_repeat = 0.0
	var each := 0
	for _i in 3:
		var again = weapon.held(space, from, Vector3.DOWN, 0.0)
		each += 1 if again != null and again.ok else 0
	_check(each == 3, "a repeat of 0 puts one down every tick", str(each))
	config.multi_spawn_repeat = every
	var close: GSResult = weapon.place(space, Vector3(503, -49.2, 503), Vector3.DOWN)
	_check(not close.ok, "nothing is put down inside the player who aims at their own feet")
	spawner.limits.spawn_interval = interval

	var budget: int = spawner.limits.world_budget
	spawner.limits.world_budget = maxi(1, spawner.world_cost())
	var told: Array[String] = []
	var on_refused := func(_pid: StringName, _prop: StringName, reason: String) -> void: told.append(reason)
	spawner.refused.connect(on_refused)
	var refused: GSResult = weapon.place(space, from, Vector3.DOWN)
	spawner.refused.disconnect(on_refused)
	spawner.limits.world_budget = budget
	_check(not refused.ok and refused.error.code == GSError.CODE_FORBIDDEN and not told.is_empty(),
		"over the budget it is refused, with the spawner's reason", str(told))
	spawner.clear_player(weapon.wielder, GSPropSpawner.REASON_ADMIN)
	floor_body.queue_free()

	_client._secondary_down()
	_check(_client.screens.is_open(menu.screen_id()), "right click in spawn mode opens the Q menu to pick again")
	_client.screens.pop(menu.screen_id())
	_client._menu_pinned = false
	_client._set_tool(&"phys")
	_completed += 1

## The band sits at the wrist: the family's hand bone is at the knuckles, so the band is within 12 cm
## (scaled to the person) of it, in the hand-side third of the forearm, and nearer it than the elbow.
func _wrist_check(skeleton: Skeleton3D, mount: Node3D, scale: float, tag: String) -> void:
	var hand := skeleton.find_bone("Middle1.R")
	var elbow := skeleton.find_bone("LowerArm.R")
	if not _check(hand >= 0 and elbow >= 0, "%s: the rig has a right hand and forearm" % tag):
		return
	var at := mount.global_position
	var to_hand := at.distance_to(skeleton.global_transform * skeleton.get_bone_global_pose(hand).origin)
	var to_elbow := at.distance_to(skeleton.global_transform * skeleton.get_bone_global_pose(elbow).origin)
	var forearm := (skeleton.get_bone_global_pose(hand).origin - skeleton.get_bone_global_pose(elbow).origin).length() * skeleton.global_transform.basis.get_scale().x
	_check(to_hand < 0.12 * scale, "%s: the band is at the wrist, %.3f m from the hand" % [tag, to_hand], str(to_hand))
	_check(to_hand < forearm / 3.0, "%s: the band is in the hand-side third of the forearm" % tag, "%.3f of %.3f" % [to_hand, forearm])
	_check(to_hand < to_elbow, "%s: the band is nearer the hand than the elbow" % tag, "%.3f vs %.3f" % [to_hand, to_elbow])


## A skeleton of [name, parent, global rest origin] bones, unrotated.
func _placed_rig(bones: Array) -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	for b in bones:
		var i := skeleton.add_bone(b[0])
		skeleton.set_bone_parent(i, b[1])
	for i in bones.size():
		var origin: Vector3 = bones[i][2]
		var parent_origin: Vector3 = bones[bones[i][1]][2] if bones[i][1] >= 0 else Vector3.ZERO
		skeleton.set_bone_rest(i, Transform3D(Basis.IDENTITY, origin - parent_origin))
	return skeleton


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

	# A forearm bone starts at the elbow: its wrist is the hand's start. A hand's elbow skips a twist bone.
	var chain := _placed_rig([["UpperArm.R", -1, Vector3(0.2, 1.4, 0)], ["LowerArm.R", 0, Vector3(0.48, 1.4, 0)], ["Middle1.R", 1, Vector3(0.74, 1.4, 0)]])
	var ends := PlaylotMultiMount.arm_ends(chain, chain.find_bone("LowerArm.R"))
	_check(ends[0].distance_to(Vector3(0.74, 1.4, 0)) < 0.001 and ends[1].distance_to(Vector3(0.48, 1.4, 0)) < 0.001,
		"a forearm bone's wrist is its hand's start, not the elbow", str(ends))
	chain.free()
	var twist := _placed_rig([["RightArm", -1, Vector3(0.2, 1.4, 0)], ["RightForeArm", 0, Vector3(0.48, 1.4, 0)], ["RightForeArmTwist", 1, Vector3(0.68, 1.4, 0)], ["RightHand", 2, Vector3(0.74, 1.4, 0)]])
	ends = PlaylotMultiMount.arm_ends(twist, twist.find_bone("RightHand"))
	_check(ends[1].distance_to(Vector3(0.48, 1.4, 0)) < 0.001, "a hand's elbow skips the twist bone", str(ends))
	twist.free()

	# Real people: the stock look and two from the library of skins, one of them short.
	for look in [[1.8, PackedInt32Array([0, 0, 0])], [1.8, PackedInt32Array([5, 9, 12])], [1.2, PackedInt32Array([3, 2, 7])]]:
		var skins: PackedInt32Array = look[1]
		var tag := "skins %s" % [skins]
		var figure := PlaylotFigure.build(look[0], skins, "mount")
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
			var skeleton: Skeleton3D = figure.call(&"skeleton")
			_check(skeleton != null, "%s: the person has a skeleton to follow" % tag)
			if skeleton != null:
				_wrist_check(skeleton, mount, look[0] / 1.8, tag)
		figure.queue_free()
	_check(PlaylotMultiMount.mount(null, "nobody") == null, "no figure gives no mount, and says so")
	_completed += 1
