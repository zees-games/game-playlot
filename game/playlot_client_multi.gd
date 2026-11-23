extends "playlot_client_net.gd"

## The multi-tool's input and presentation, split out of the client: R held opens the mode selector
## (the wrist device raises its hologram), R tapped keeps its old job; the device is drawn on every
## hand. No `class_name`; the flash half extends this.
##
## [b]Held R owns the keyboard and mouse.[/b] Number keys pick a mode only while it is down; without it
## 1 2 3 and the wheel are the weapon inventory. While down the mouse moves the cursor on the hologram
## rather than the view, and a click confirms.

## Pixels of vertical mouse travel per hologram row.
const MULTI_ROW_PIXELS := 24.0
const MULTI_STICK_DEADZONE := 0.6
const MULTI_RELOAD_TAP := 0.1

var _multi_held := false
var _multi_open := false
var _multi_held_for := 0.0
var _multi_cursor := 0.0
var _multi_stick_armed := true
## A mode was chosen with R down, so releasing is no tap.
var _multi_used := false
## The bracelet built only for the selector while a zee gun owns the hands: worn on the arm that holds the gun.
var _multi_temp: Node3D = null
## Left button down with the multi-tool in hand, for spawn mode's hold-to-repeat offline.
var _spawn_firing := false
## What spawn mode has armed, by name, for the device's screen and hologram.
var _spawn_pick_name := ""


func multi_held() -> bool:
	return _multi_held


func multi_open() -> bool:
	return _multi_open


## The modes the selector lists, in menu order.
func multi_modes() -> Array[StringName]:
	return PlaylotMultitool.available(playlot)


func _multi_hold_seconds() -> float:
	if presentation != null and presentation.settings != null:
		return presentation.settings.get_float(&"multitool_hold_seconds", PlaylotMultitool.HOLD_SECONDS)
	return PlaylotMultitool.HOLD_SECONDS


## Returns true when the event is the multi-tool's and nothing else may act on it.
func _multi_input(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.is_action(PlaylotBindings.RELOAD):
			if key.is_echo():
				return true
			if key.pressed:
				_multi_press()
			else:
				_multi_release()
			return true

	if not _multi_held:
		return false

	if event is InputEventKey:
		var number := _multi_number(event as InputEventKey)
		if number >= 0:
			if (event as InputEventKey).pressed and not (event as InputEventKey).is_echo():
				_multi_pick(number)
			return true
		# Anything else (movement keys, Escape) still works as ever.
		return false

	if event is InputEventMouseMotion:
		if _multi_open:
			_multi_move((event as InputEventMouseMotion).relative.y / MULTI_ROW_PIXELS)
		return true

	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and _multi_open:
			match button.button_index:
				MOUSE_BUTTON_LEFT:
					_multi_commit(_multi_hover())
				MOUSE_BUTTON_WHEEL_UP:
					_multi_move(-1.0)
				MOUSE_BUTTON_WHEEL_DOWN:
					_multi_move(1.0)
		return true

	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if motion.axis == JOY_AXIS_RIGHT_Y and _multi_open:
			if absf(motion.axis_value) < MULTI_STICK_DEADZONE:
				_multi_stick_armed = true
			elif _multi_stick_armed:
				_multi_stick_armed = false
				_multi_move(signf(motion.axis_value))
			return true

	return false


## 1..9 and 0 (top row or keypad) are modes 0..9; -1 for any other key.
static func _multi_number(key: InputEventKey) -> int:
	var code := key.physical_keycode
	if code >= KEY_1 and code <= KEY_9:
		return code - KEY_1
	if code >= KEY_KP_1 and code <= KEY_KP_9:
		return code - KEY_KP_1
	if code == KEY_0 or code == KEY_KP_0:
		return 9
	return -1


func _multi_press() -> void:
	if _multi_held:
		return
	_multi_held = true
	_multi_used = false
	_multi_held_for = 0.0
	# The mouse stops being the trigger while the selector is in prospect.
	_primary_up()
	_secondary_up()
	if _multi_hold_seconds() <= 0.0:
		_multi_open_selector()


## Opens once R has been down for the threshold.
func _multi_tick(delta: float) -> void:
	if _multi_held:
		_multi_held_for += delta
	if _multi_held and _menu_is_open():
		_multi_cancel()
		return
	if _multi_held and not _multi_open and player != null \
			and _multi_held_for >= _multi_hold_seconds():
		_multi_open_selector()
	if tool == &"spawn" and toy_view != null and is_instance_valid(toy_view) \
			and toy_view.call(&"pick_text") != _spawn_pick_name:
		toy_view.call(&"set_pick", _spawn_pick_name)
	if _multi_temp != null and is_instance_valid(_multi_temp) and not _multi_open \
			and float(_multi_temp.call(&"raise_amount")) <= 0.0:
		_multi_temp.queue_free()
		_multi_temp = null


func _multi_open_selector() -> void:
	if _multi_open or player == null:
		return
	_multi_open = true
	var modes := multi_modes()
	_multi_cursor = float(maxi(0, modes.find(tool)))
	var device := _multi_device()
	if device != null:
		device.call(&"set_modes", modes)
		device.call(&"set_mode", tool)
		device.call(&"set_raised", true)
		device.call(&"hover", int(_multi_cursor))
	_multi_raise(true)


## The first-person device: the tool's own, or a temporary one when a zee gun owns the view model.
func _multi_device() -> Node3D:
	if toy_view != null and is_instance_valid(toy_view):
		return toy_view
	if camera == null:
		return null
	if _multi_temp == null or not is_instance_valid(_multi_temp):
		_multi_temp = PlaylotMultiDevice.make(camera, PlaylotViewGrip.available() and view_arms is GSPlayerViewArms)
		_multi_temp.call(&"set_modes", multi_modes())
	return _multi_temp


func _worn_device() -> Node3D:
	var own := super()
	if own == null and _multi_temp != null and is_instance_valid(_multi_temp) and _multi_temp.get(&"on_arms") == true:
		return _multi_temp
	return own


func _multi_raise(up: bool) -> void:
	if player != null:
		player.multi_raised = up
	if bridge != null:
		bridge.ask_multi_raise(up)


func _multi_hover() -> int:
	var count := multi_modes().size()
	return clampi(roundi(_multi_cursor), 0, maxi(0, count - 1))


func _multi_move(rows: float) -> void:
	var count := multi_modes().size()
	_multi_cursor = clampf(_multi_cursor + rows, 0.0, float(maxi(0, count - 1)))
	var device := _multi_device()
	if device != null:
		device.call(&"hover", _multi_hover())


## A number key: that mode, at once, whether or not the selector had opened.
func _multi_pick(index: int) -> void:
	var modes := multi_modes()
	if index >= modes.size():
		if hud != null:
			hud.notice("No mode %d." % (index + 1))
		_multi_used = true
		return
	_multi_open_selector()
	_multi_cursor = float(index)
	_multi_commit(index)


func _multi_commit(index: int) -> void:
	var modes := multi_modes()
	if index < 0 or index >= modes.size():
		return
	_multi_used = true
	var device := _multi_device()
	if device != null:
		device.call(&"hover", index)
	_set_tool(modes[index])
	# `_set_tool` rebuilds the first-person device: the new one is raised too.
	device = _multi_device()
	if device != null and _multi_open:
		device.call(&"set_modes", modes)
		device.call(&"set_raised", true)
		device.call(&"hover", index)


func _multi_release() -> void:
	if not _multi_held:
		return
	_multi_held = false
	if _multi_open:
		if not _multi_used:
			_multi_commit(_multi_hover())
		_multi_close()
		return
	if _multi_used:
		return
	# A tap: what R always did.
	if _zee_rig() != null or tool == TOOLGUN:
		_set_reload(true)
		get_tree().create_timer(MULTI_RELOAD_TAP).timeout.connect(_set_reload.bind(false))
	else:
		_unfreeze_all()


func _multi_close() -> void:
	_multi_open = false
	var device := _multi_device()
	if device != null:
		device.call(&"set_raised", false)
	_multi_raise(false)


func _multi_cancel() -> void:
	_multi_held = false
	if _multi_open:
		_multi_close()


## The hand-mounted devices (everyone else's, and the player's own in third person): mode, raise, kick.
func _multi_present() -> void:
	if playlot == null:
		return
	var modes := multi_modes()
	_multi_feed_view()
	for who: Variant in playlot.players.values():
		var other := who as PlaylotPlayer
		if other == null or not is_instance_valid(other):
			continue
		var mine := other == player
		# Offline there is no server to say which mode: this client's own tool is the answer.
		if mine and bridge == null:
			other.multi_mode = PlaylotMultitool.index_of(tool)
		_multi_mount(other, modes, mine)


var _multi_last_look := Vector2.ZERO


## Drives the first-person device's sway from the player's own motion state.
func _multi_feed_view() -> void:
	if player == null or player.controller == null or toy_view == null or not is_instance_valid(toy_view):
		return
	var st: Variant = player.controller.state
	var yaw: float = st.yaw
	var pitch: float = st.pitch
	var velocity: Vector3 = st.velocity
	var grounded: bool = st.is_grounded()
	var look := Vector2(deg_to_rad(yaw), deg_to_rad(pitch))
	var turn := Vector2(wrapf(look.x - _multi_last_look.x, -PI, PI), look.y - _multi_last_look.y)
	_multi_last_look = look
	var local: Vector3 = Basis(Vector3.UP, deg_to_rad(yaw)).inverse() * velocity
	toy_view.call(&"feed", local, grounded, turn, get_process_delta_time())


func _multi_mount(who: PlaylotPlayer, modes: Array[StringName], mine: bool) -> void:
	var shown := who.multi_mode >= 0 and who.multi_mode < PlaylotMultitool.MODES.size() \
		and (not mine or view_id() != &"fp")
	var device := who.multi_device
	if device == null or not is_instance_valid(device):
		if not shown or who.character == null:
			return
		var figure := who.character.figure()
		if figure == null:
			return
		var mount := PlaylotMultiMount.mount(figure, String(who.name))
		if mount == null:
			return
		device = PlaylotMultiDevice.make(null)
		device.call(&"set_modes", modes)
		mount.add_child(device)
		who.multi_device = device
		who.multi_mount_fire = who.multi_fire

	device.visible = shown
	if not shown:
		return
	var id := PlaylotMultitool.MODES[who.multi_mode]
	if device.call(&"mode") != id:
		device.call(&"set_mode", id)
	device.call(&"set_raised", who.multi_raised)
	if who.multi_fire != who.multi_mount_fire:
		who.multi_mount_fire = who.multi_fire
		device.call(&"kick", who.aim_direction())


func _primary_down() -> void:
	_spawn_firing = true
	super()


func _primary_up() -> void:
	_spawn_firing = false
	super()


## Right click in spawn mode opens the Q menu, pinned, to pick something else.
func _secondary_down() -> void:
	if tool == &"spawn" and _zee_rig() == null and menu != null and screens != null:
		open_spawn_menu()
		return
	super()


func open_spawn_menu() -> void:
	if screens.is_open(menu.screen_id()):
		return
	_primary_up()
	_secondary_up()
	_rotating = false
	menu.selected = selected_prop
	menu.tool = tool
	screens.push(menu.screen_id())
	_menu_pinned = true


## Offline, a held left button repeats spawn mode (online the server reads the held button).
func _physics_process(delta: float) -> void:
	super(delta)
	if link != null or bridge != null or not _spawn_firing or weapon == null or player == null or _covered():
		return
	var again := weapon.held(_space(), player.eye_position(), player.aim_direction(), delta)
	if again == null:
		return
	_report(again)
	if toy_view != null and is_instance_valid(toy_view):
		toy_view.call(&"kick")
	player.multi_fire = (player.multi_fire + 1) & 0xF


## "Spawn with multi-tool" on a Q menu card: spawn mode in hand with [param item_id] armed, menu closed.
func _on_multi_spawn_chosen(kind: String, item_id: StringName) -> void:
	if not PlaylotMultitool.PICK_KINDS.has(kind) or item_id == &"":
		GSLog.warn("playlot.client", "spawn mode was asked for something it cannot put down", {"kind": kind, "id": String(item_id)})
		return
	if kind == "prop":
		selected_prop = item_id
	_set_tool(&"spawn")
	if tool != &"spawn":
		return
	var picked := PlaylotMultitool.pick(kind, String(item_id))
	if bridge != null:
		bridge.ask_multi_spawn(kind, item_id)
	elif weapon != null:
		weapon.armed = picked
	_spawn_pick_name = _pick_name(kind, item_id)
	if toy_view != null and is_instance_valid(toy_view):
		toy_view.call(&"set_pick", _spawn_pick_name)
	if menu != null and screens != null and screens.is_open(menu.screen_id()):
		screens.pop(menu.screen_id())
	_menu_pinned = false


func _pick_name(kind: String, item_id: StringName) -> String:
	match kind:
		"prop":
			var def: GSPropDef = playlot.props.catalogue.get_prop(item_id) if playlot.props.catalogue != null else null
			return def.name_or_id() if def != null else String(item_id)
		"weapon":
			var weapon_def := playlot.weapon_def(item_id)
			return weapon_def.name_or_id() if weapon_def != null else String(item_id)
		"addon":
			for row in (menu.addon_items if menu != null else []):
				if str((row as Dictionary).get("key", "")) == String(item_id):
					return str((row as Dictionary).get("label", item_id))
	return String(item_id)
