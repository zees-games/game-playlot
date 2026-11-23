extends "playlot_client_ui.gd"


## The held weapon's and the worn tool's first-person view: arming, seating the hands, disarming.

func _zee_rig() -> ZeeWeaponRig:
	if player == null or not is_instance_valid(player):
		return null
	var rig: Variant = player.zee_rig
	if rig is ZeeWeaponRig and is_instance_valid(rig):
		return rig as ZeeWeaponRig
	return null


## Builds the hands under the camera and a rig to drive them. The rig has the authority only
## offline; connected, the server holds the deciding rig (`PlaylotNetBridge._give_weapon`)
## and this one is the gun that moves.
func _arm_zee(def: PlaylotWeaponDef) -> bool:
	if player == null or camera == null:
		return false

	zee_view = ZeeViewModel.new()
	zee_view.name = "ZeeViewModel"
	var own_hands := PlaylotViewGrip.available() and view_arms is GSPlayerViewArms
	(zee_view as ZeeViewModel).show_arms = not own_hands
	if own_hands:
		(zee_view as ZeeViewModel).hands_reached.connect(_on_hands_reached)
	camera.add_child(zee_view)
	if own_hands:
		# The viewmodel_fov lens scales the weapon 2.5x and pushes it past the arms' reach.
		zee_view.remove_from_group(&"gs_view_model")
		(zee_view as ZeeViewModel).hands_fov = 0.0
		# Before this client's frame, which then moves it to the avatar's hand (its lens resets the position each frame).
		zee_view.process_priority = -1

	var rig := PlaylotZee.arm(
		player, def, ZeeWeaponRig.Role.LOCAL, bridge == null,
		playlot.tick_rate, Engine.get_physics_frames(), zee_view, playlot.ads_rules
	)

	if rig == null:
		_disarm_zee()
		return false

	if shot_sound != null:
		shot_sound.attach(rig.shot_fx())

	# Connected, the server's WEAPON event draws it (`PlaylotNetBridge`); offline nobody
	# sends one, and the gun still belongs in the hands a third-person camera shows.
	if bridge == null:
		PlaylotZee.show_held(player, def)

	return true


## The weapon's own measured grip and fore-end, onto the arms.
func _on_hands_reached(anchor: Node3D, grip: Vector3, fore: Vector3, pose: StringName) -> void:
	var hands := zee_view as ZeeViewModel
	if hands != null and hands.equipped() != _seated_for and hands.aim_fraction() <= 0.0:
		# At the hip the grip is the art's rest grip in the view model's own space.
		_seated_for = hands.equipped()
		hand_seat_offset = HAND_SEAT - grip
	var made := PlaylotViewGrip.update(held_grip, anchor, grip, fore, pose)
	if made != held_grip:
		held_grip = made
		(view_arms as GSPlayerViewArms).set_held(held_grip)


func _disarm_zee() -> void:
	if player != null and is_instance_valid(player):
		PlaylotZee.disarm(player)
		if bridge == null:
			PlaylotZee.show_held(player, null)

	if zee_view != null and is_instance_valid(zee_view):
		# queue_free is deferred: the dying model would emit once more and re-seat the arms.
		if (zee_view as ZeeViewModel).hands_reached.is_connected(_on_hands_reached):
			(zee_view as ZeeViewModel).hands_reached.disconnect(_on_hands_reached)
		zee_view.queue_free()
	zee_view = null
	_seated_for = &""
	hand_seat_offset = Vector3.ZERO
	# The bracelet's wrist grip outlives a mode change (_arm_toy_view drops it if the bracelet goes): letting go
	# and re-gripping in one frame hid the real hand for a frame.
	var on_bracelet := held_grip != null and held_grip.anchor != null and toy_view != null \
		and is_instance_valid(toy_view) and toy_view.is_ancestor_of(held_grip.anchor)
	if not on_bracelet:
		held_grip = null
		if view_arms is GSPlayerViewArms:
			(view_arms as GSPlayerViewArms).set_held(null)

	_zee_buttons = 0
	_net_buttons &= ~GSFpsCommand.BUTTON_USER_2


## Builds the first-person model for a toy or tool, after [method _disarm_zee] cleared the last.
func _arm_toy_view(id: StringName) -> void:
	var own_hands := PlaylotViewGrip.available() and view_arms is GSPlayerViewArms
	var kept := toy_view != null and is_instance_valid(toy_view) and not toy_view.is_queued_for_deletion()
	if kept and zee_view == null and camera != null and id != &"" and toy_view.get(&"on_arms") == own_hands:
		# A mode change keeps the bracelet on the arm: its screen flashes, the arm does not drop and re-reach.
		toy_view.call(&"set_modes", PlaylotMultitool.available(playlot))
		toy_view.call(&"set_mode", id)
		if own_hands and held_grip == null:
			held_grip = PlaylotViewGrip.wrist(toy_view.call(&"anchor"))
			(view_arms as GSPlayerViewArms).set_held(held_grip)
		return
	if toy_view != null and is_instance_valid(toy_view):
		if held_grip != null and held_grip.anchor != null and toy_view.is_ancestor_of(held_grip.anchor):
			held_grip = null
			(view_arms as GSPlayerViewArms).set_held(null)
		toy_view.queue_free()
	toy_view = null
	if zee_view != null or camera == null or id == &"":
		return
	# Every sandbox tool is a mode of the one bracelet: the mode's glow, the same device, on the avatar's own arm.
	var device := PlaylotMultiDevice.make(camera, own_hands)
	device.call(&"set_modes", PlaylotMultitool.available(playlot))
	device.call(&"set_mode", id)
	toy_view = device
	if own_hands:
		PlaylotViewGrip.add_poses(view_arms)
		held_grip = PlaylotViewGrip.wrist(device.call(&"anchor"))
		(view_arms as GSPlayerViewArms).set_held(held_grip)
