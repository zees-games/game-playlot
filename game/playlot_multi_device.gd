extends Node3D
## The multi-tool as a worn device: a chunky segmented wrist band in dark metal with glowing inset strips, a
## raised top plate the selector hologram is projected from, and a cylinder emitter on the palm that every
## beam starts at. Procedural: the body is ONE mesh with ONE surface (merged boxes), the glow a second, and the
## hologram six translucent quads with a label each, so a device is a handful of draw calls.
##
## Three kinds, from the same build. On the avatar's arms (`make(camera, true)`) the child `Arm` is only the
## camera-space anchor the arms' right hand reaches for, and [method wear] fits the band (`Arm/Wear`) to the solved
## forearm and the emitter to the palm. Without the arms it keeps its own sleeve and hand block under the lens
## (group `gs_view_model`). The worn kind hangs from a figure's wrist mount for everyone else and third person.

const PlaylotMultitool := preload("playlot_multitool.gd")
const PlaylotMultiIcons := preload("playlot_multi_icons.gd")

## The first-person arm at rest, and raised to read the wrist like a watch. Under the camera, metres.
const FP_LOW_POS := Vector3(0.2, -0.24, -0.42)
const FP_LOW_ROT := Vector3(-6.0, 10.0, -8.0)
const FP_UP_POS := Vector3(0.03, -0.12, -0.36)
const FP_UP_ROT := Vector3(28.0, -48.0, -22.0)
const RAISE_SPEED := 9.0
## The anchor the avatar's hand reaches for, at rest and raised palm-in to read the band, under the camera, metres.
## Rest is the avatar hand's seat the zee guns use (PlaylotClient HAND_SEAT).
const ARMS_LOW_POS := Vector3(0.16, -0.2, -0.36)
const ARMS_LOW_ROT := Vector3(4.0, 6.0, -4.0)
const ARMS_UP_POS := Vector3(0.05, -0.15, -0.31)
const ARMS_UP_ROT := Vector3(24.0, 40.0, 58.0)
## The band's radius over the forearm's length, and how far back from the wrist joint its centre sits (same unit):
## both follow the avatar's own arm, so a long thin arm and a short chibi one wear it alike.
const WRIST_FIT := 0.14
const WRIST_BACK := 0.22
## The palm emitter, in the real hand's frame (life-size metres: +Y to the fingers, +Z out of the palm).
const PALM_AT := Vector3(0.0, 0.045, 0.024)
const BAND_RADIUS := 0.05
const EMITTER_Z := -0.15
const SCREEN_WIDTH := 0.07
const SCREEN_LENGTH := 0.094
const ROW_HEIGHT := 0.034
const ROW_WIDTH := 0.2
## The hologram's rows lie on a cylinder this wide, fanned this many radians apart.
const HOLO_RADIUS := 0.16
const HOLO_STEP := 0.2
## Where the first-person hologram settles, in camera space: right of the crosshair and a little low.
const HOLO_VIEW := Vector3(0.17, -0.05, -0.5)
const HOLO_ON_BAND := Vector3(0.0, BAND_RADIUS + 0.16, -0.02)

const GLOW_NAME := &"Glow"

var first_person := false
## Worn on the avatar's own first-person arms ([method wear]), not on its own sleeve.
var on_arms := false

## Vertical field of view the first-person device is drawn at, set by gs-menu's applier (group
## `gs_view_model`) from `viewmodel_fov`; 0 draws it under the camera's own lens.
var hands_fov := 0.0

var _camera: Camera3D = null
var _arm: Node3D
var _wear: Node3D
var _palm_glow: MeshInstance3D
var _wear_skeleton: Skeleton3D = null
var _wear_hand: Node3D = null
var _wear_bones := PackedInt32Array()
var _holo: Node3D
var _muzzle: Marker3D
var _glow_material: StandardMaterial3D
var _screen: MeshInstance3D
var _screen_material: StandardMaterial3D
var _name_label: Label3D
var _flash := 0.0
var _sway_phase := 0.0
var _sway := Vector3.ZERO
var _turn_lag := Vector2.ZERO
var _dip := 0.0
var _was_airborne := false
var _rows: Array[MeshInstance3D] = []
var _labels: Array[Label3D] = []
var _row_materials: Array[StandardMaterial3D] = []
var _modes: Array[StringName] = []
var _mode: StringName = &""
var _hover := -1
var _raise := 0.0
var _raised := false
var _kick := 0.0
var _time := 0.0


## Builds a device. [param camera] set makes the first-person one, put under it; [param arms] worn by the
## avatar's own view arms (the caller feeds [method wear] each frame after their tick).
static func make(camera: Camera3D = null, arms := false) -> Node3D:
	var device := (load("res://game/playlot_multi_device.gd") as GDScript).new() as Node3D
	device.name = "MultiDevice"
	device.set(&"on_arms", arms and camera != null)
	device.call("_build", camera)
	if camera != null:
		camera.add_child(device)
	return device


func _init() -> void:
	visible = true


## The modes the hologram lists, in menu order.
func set_modes(ids: Array[StringName]) -> void:
	_modes = ids
	for i in _rows.size():
		var shown := i < ids.size()
		_rows[i].visible = shown
		_labels[i].text = "%d  %s" % [i + 1, PlaylotMultitool.label(ids[i])] if shown else ""
	_paint()


func set_mode(id: StringName) -> void:
	if id != _mode and _mode != &"":
		_flash = 1.0
	_mode = id
	_paint()


func mode() -> StringName:
	return _mode


## Arm up and hologram open, or down and closed.
func set_raised(up: bool) -> void:
	_raised = up
	if not up:
		_hover = -1
	_paint()


func is_raised() -> bool:
	return _raised


## The row under the pointer or the stick; -1 for none.
func hover(index: int) -> void:
	if index == _hover:
		return
	_hover = index
	_paint()


## `viewmodel_fov`'s hook, called by gs-menu's applier on every node of the `gs_view_model` group.
func set_hands_fov_at_4_3(horizontal: float) -> void:
	hands_fov = GSViewLens.vertical_from_horizontal_4_3(horizontal)


## Motion for the first-person device, fed each frame by the client from the player's own state:
## [param local_velocity] in the camera's frame (x right, z back), [param grounded], and
## [param turn] the yaw and pitch change this frame in radians. Bob, strafe lean, sprint
## and landing dip and turn lag all come from it.
func feed(local_velocity: Vector3, grounded: bool, turn: Vector2, delta: float) -> void:
	var flat := Vector2(local_velocity.x, local_velocity.z)
	var speed := flat.length()
	if grounded:
		_sway_phase += delta * (4.0 + speed * 1.6)
	var amount := clampf(speed / 6.0, 0.0, 1.5) if grounded else 0.0
	var bob := Vector3(cos(_sway_phase) * 0.006, absf(sin(_sway_phase)) * -0.008, 0.0) * amount
	var strafe := Vector3(-clampf(local_velocity.x, -8.0, 8.0) * 0.0015, 0.0, 0.0)
	if grounded and _was_airborne:
		_dip = 1.0
	_was_airborne = not grounded
	_dip = maxf(0.0, _dip - delta * 4.0)
	var air := 0.0 if grounded else clampf(local_velocity.y * 0.002, -0.02, 0.02)
	_turn_lag = (_turn_lag + turn * 0.5).lerp(Vector2.ZERO, clampf(delta * 8.0, 0.0, 1.0))
	_turn_lag = _turn_lag.clamp(Vector2(-0.06, -0.06), Vector2(0.06, 0.06))
	var breath := Vector3(0.0, sin(_time * 1.4) * 0.0015, 0.0)
	_sway = bob + strafe + breath + Vector3(-_turn_lag.x * 0.2, _turn_lag.y * 0.2 - _dip * 0.03 + air, 0.0)


func kick() -> void:
	_kick = 1.0


## The anchor the avatar's right hand reaches for (the hand's grip is its origin), on the arms.
func anchor() -> Node3D:
	return _arm


## Fits the band to [param arms]' solved right forearm and the emitter to its real palm; called after the arms'
## tick each frame. Bones and hand are looked up once per figure, so a frame allocates nothing.
func wear(arms: Node) -> void:
	if not on_arms or arms == null:
		return
	var figure: Node = arms.call(&"arms")
	var skeleton: Skeleton3D = figure.call(&"skeleton") if figure != null and figure.has_method(&"skeleton") else null
	if skeleton != _wear_skeleton:
		_wear_skeleton = skeleton
		_wear_bones = PackedInt32Array([skeleton.find_bone("LowerArm.R"), skeleton.find_bone("Middle1.R")]) if skeleton != null else PackedInt32Array()
		var hands: Array = arms.call(&"hands")
		_wear_hand = hands[0] if not hands.is_empty() else null
	var shown: bool = arms.get(&"shown") == true
	_wear.visible = shown and skeleton != null and _wear_bones.size() == 2 and _wear_bones[0] >= 0 and _wear_bones[1] >= 0
	if not _wear.visible:
		return
	var to_world := skeleton.global_transform
	var elbow := to_world * GSHumanoidIk.global_pose(skeleton, _wear_bones[0]).origin
	var wrist := to_world * GSHumanoidIk.global_pose(skeleton, _wear_bones[1]).origin
	var along := wrist - elbow
	var length := along.length()
	if length < 0.001:
		return
	var z := -along / length
	var up := _arm.global_basis.y
	var y := (up - z * up.dot(z)).normalized()
	if not y.is_normalized():
		y = Vector3.UP
	var k := WRIST_FIT * length / BAND_RADIUS
	var basis := Basis(y.cross(z), y, z) * Basis.from_scale(Vector3.ONE * k)
	_wear.global_transform = Transform3D(basis, wrist + z * (WRIST_BACK * length))
	var hand_on := _wear_hand != null and is_instance_valid(_wear_hand) and _wear_hand.visible
	_palm_glow.visible = hand_on
	if hand_on:
		var palm := _wear_hand.global_transform * Transform3D(Basis(), PALM_AT)
		_palm_glow.global_transform = palm
		_muzzle.global_position = palm * Vector3(0.0, 0.0, 0.01)
	else:
		_muzzle.global_position = wrist - z * (0.5 * length)
	if _holo.visible:
		_face_holo()


## Where the palm emitter's mouth is, in the world: every beam and effect starts here.
func muzzle_position() -> Vector3:
	return _muzzle.global_position


func muzzle_node() -> Marker3D:
	return _muzzle


func raise_amount() -> float:
	return _raise


func hologram_visible() -> bool:
	return _holo != null and _holo.visible


func describe() -> Dictionary:
	return {
		"mode": _mode, "raised": _raised, "raise": _raise, "hover": _hover,
		"first_person": first_person, "on_arms": on_arms, "rows": _modes.size(),
	}


func _process(delta: float) -> void:
	_time += delta
	_kick = maxf(0.0, _kick - delta * 6.0)
	_raise = move_toward(_raise, 1.0 if _raised else 0.0, delta * RAISE_SPEED)
	var eased := smoothstep(0.0, 1.0, _raise)
	# Squared, so the kick settles into rest instead of stopping on a corner.
	var kick := _kick * _kick

	if on_arms:
		# Eased by the arms' own IK slew; the kick and sway still ride the anchor.
		_arm.position = ARMS_LOW_POS.lerp(ARMS_UP_POS, eased) + Vector3(0.0, 0.0, kick * 0.02) + _sway
		_arm.rotation_degrees = ARMS_LOW_ROT.lerp(ARMS_UP_ROT, eased) + Vector3(kick * 6.0, 0.0, 0.0)
	elif first_person:
		if _camera != null and is_instance_valid(_camera):
			GSViewLens.apply(self, _camera, hands_fov, 1.0, kick * 0.04)
		_arm.position = FP_LOW_POS.lerp(FP_UP_POS, eased) + Vector3(0.0, 0.0, kick * 0.025) + _sway
		_arm.rotation_degrees = FP_LOW_ROT.lerp(FP_UP_ROT, eased) + Vector3(kick * 4.0, 0.0, 0.0)
	else:
		_arm.position = Vector3(0.0, 0.0, kick * 0.02)

	_holo.visible = _raise > 0.02
	if _holo.visible:
		_face_holo()

	_flash = maxf(0.0, _flash - delta * 3.0)
	if _screen_material != null:
		# The screen idles with a slow shimmer; a mode change flashes it white.
		var level := 0.82 + 0.1 * sin(_time * 3.1) + _flash * 0.6
		_screen_material.albedo_color = Color(level, level, level)

	# Idle glow breathes; a shot flares it.
	var idle := 1.6 + 0.4 * sin(_time * 2.2)
	_glow_material.emission_energy_multiplier = idle + kick * 3.0


func _face_holo() -> void:
	var out := 1.0 - pow(1.0 - _raise, 3.0)
	_holo.scale = Vector3.ONE * (0.3 + 0.7 * out)
	if first_person and _camera != null and is_instance_valid(_camera):
		# Rises off the band to a fixed spot in view, so the arm's raise never brings it up to the eye.
		var from := _wear.global_transform * Vector3(0.0, BAND_RADIUS + 0.02, 0.0)
		_holo.global_position = from.lerp(_camera.global_transform * HOLO_VIEW, out)
		var away := _holo.global_position - _camera.global_position
		if away.length_squared() > 0.0001:
			_holo.look_at(_holo.global_position + away, _camera.global_basis.y)
	else:
		_holo.position = HOLO_ON_BAND
		var viewer := get_viewport().get_camera_3d() if is_inside_tree() else null
		if viewer != null:
			var to := viewer.global_position - _holo.global_position
			to.y = 0.0
			if to.length_squared() > 0.0001:
				_holo.look_at(_holo.global_position - to, Vector3.UP)


func _paint() -> void:
	var tint := PlaylotMultitool.colour(_mode)
	if _screen_material != null:
		_screen_material.albedo_texture = PlaylotMultiIcons.texture(_mode, tint)
		_name_label.text = PlaylotMultitool.label(_mode)
		_name_label.modulate = tint.lightened(0.4)
	if _glow_material != null:
		_glow_material.emission = tint
		_glow_material.albedo_color = tint.darkened(0.8)
	for i in _row_materials.size():
		var on := i < _modes.size() and _modes[i] == _mode
		var hovered := i == _hover
		var c := PlaylotMultitool.colour(_modes[i]) if i < _modes.size() else tint
		var m := _row_materials[i]
		# A dark glass plate under white text reads on any sky; the mode's colour lights its fill and edge.
		var fill := c.darkened(0.35) if on else (c.darkened(0.55) if hovered else c.darkened(0.82))
		m.albedo_color = Color(fill.r, fill.g, fill.b, 0.92 if on else (0.86 if hovered else 0.78))
		_labels[i].modulate = Color(1, 1, 1, 1) if (on or hovered) else Color(0.86, 0.92, 1.0, 0.95)
		_labels[i].outline_modulate = Color(0, 0, 0, 0.9) if on else c.darkened(0.85)


# --- Building ---------------------------------------------------------------

func _build(camera: Camera3D) -> void:
	first_person = camera != null
	_camera = camera
	if first_person and not on_arms:
		add_to_group(&"gs_view_model")
	if on_arms:
		# Before the client's frame, which ticks the arms onto this anchor and then calls wear.
		process_priority = -1

	_arm = Node3D.new()
	_arm.name = "Arm"
	add_child(_arm)
	_wear = Node3D.new()
	_wear.name = "Wear"
	_arm.add_child(_wear)

	var body := SurfaceTool.new()
	body.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glow := SurfaceTool.new()
	glow.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sleeve := SurfaceTool.new()
	sleeve.begin(Mesh.PRIMITIVE_TRIANGLES)
	var skin := SurfaceTool.new()
	skin.begin(Mesh.PRIMITIVE_TRIANGLES)

	# The band: eight chunky slabs round the wrist, a gap between each so it reads as segments.
	var segments := 8
	for i in segments:
		var angle := TAU * float(i) / float(segments)
		var around := Basis(Vector3.FORWARD, angle)
		var at := around * Vector3(0.0, BAND_RADIUS, 0.0)
		var slab := Transform3D(around, at)
		_box(body, slab, Vector3(0.036, 0.016, 0.062))
		# A thin lit line inset in each slab's outer face, and a lit ring each side.
		_box(glow, Transform3D(around, around * Vector3(0.0, BAND_RADIUS + 0.0085, 0.0)), Vector3(0.026, 0.003, 0.008))
	for z in [-0.034, 0.034]:
		_ring(body, Vector3(0.0, 0.0, z), BAND_RADIUS + 0.004, 0.008, 16)
	# The top plate: a raised block with a lit rim and a lit emblem bar, where the hologram comes from.
	_box(body, Transform3D(Basis(), Vector3(0.0, BAND_RADIUS + 0.018, 0.0)), Vector3(0.09, 0.02, 0.118))
	_box(body, Transform3D(Basis(), Vector3(0.0, BAND_RADIUS + 0.03, 0.0)), Vector3(0.076, 0.006, 0.104))
	var rim_y := BAND_RADIUS + 0.0335
	_box(glow, Transform3D(Basis(), Vector3(0.0, rim_y, -0.05)), Vector3(0.076, 0.002, 0.003))
	_box(glow, Transform3D(Basis(), Vector3(0.0, rim_y, 0.05)), Vector3(0.076, 0.002, 0.003))
	_box(glow, Transform3D(Basis(), Vector3(-0.0375, rim_y, 0.0)), Vector3(0.003, 0.002, 0.1))
	_box(glow, Transform3D(Basis(), Vector3(0.0375, rim_y, 0.0)), Vector3(0.003, 0.002, 0.1))
	# The palm emitter: a body cylinder along -Z with a lit ring on its mouth. On the arms the real palm carries it.
	if not on_arms:
		_cylinder_z(body, Vector3(0.0, 0.0, EMITTER_Z + 0.012), 0.022, 0.034, 14)
		_cylinder_z(glow, Vector3(0.0, 0.0, EMITTER_Z - 0.003), 0.016, 0.005, 14)
	if first_person and not on_arms:
		# A sleeve back toward the camera and a hand block, so the band sits on an arm.
		_cylinder_z(sleeve, Vector3(0.0, 0.0, 0.2), 0.041, 0.28, 14)
		_box(skin, Transform3D(Basis(), Vector3(0.0, 0.0, -0.09)), Vector3(0.07, 0.042, 0.1))

	var body_mesh := MeshInstance3D.new()
	body_mesh.name = "Body"
	body_mesh.mesh = body.commit()
	var plating := StandardMaterial3D.new()
	plating.albedo_color = Color(0.34, 0.37, 0.44)
	plating.metallic = 0.35
	plating.roughness = 0.45
	plating.cull_mode = BaseMaterial3D.CULL_DISABLED
	body_mesh.material_override = plating
	body_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wear.add_child(body_mesh)

	if first_person and not on_arms:
		_wear.add_child(_part("Sleeve", sleeve, Color(0.74, 0.8, 0.9), 0.85))
		_wear.add_child(_part("Hand", skin, Color(0.93, 0.76, 0.64), 0.7))

	var glow_mesh := MeshInstance3D.new()
	glow_mesh.name = String(GLOW_NAME)
	glow_mesh.mesh = glow.commit()
	_glow_material = StandardMaterial3D.new()
	_glow_material.emission_enabled = true
	_glow_material.emission_energy_multiplier = 1.8
	_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mesh.material_override = _glow_material
	glow_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wear.add_child(glow_mesh)

	_muzzle = Marker3D.new()
	_muzzle.name = "Muzzle"
	_muzzle.position = Vector3(0.0, 0.0, EMITTER_Z - 0.008)
	_wear.add_child(_muzzle)
	if on_arms:
		# A lit lens on the real palm (its own frame, life-size metres), sharing the glow's material.
		var lens := SurfaceTool.new()
		lens.begin(Mesh.PRIMITIVE_TRIANGLES)
		_cylinder_z(lens, Vector3.ZERO, 0.013, 0.004, 14)
		_palm_glow = MeshInstance3D.new()
		_palm_glow.name = "PalmGlow"
		_palm_glow.mesh = lens.commit()
		_palm_glow.material_override = _glow_material
		_palm_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_palm_glow.top_level = true
		_wear.add_child(_palm_glow)

	_build_screen()
	_build_hologram()
	_paint()


## A lit-fabric part (the sleeve, the hand) of the first-person arm.
func _part(part_name: String, st: SurfaceTool, colour: Color, roughness: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = part_name
	node.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = roughness
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.material_override = m
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## The display on the top plate: one quad showing the mode's icon, and the mode's name small beneath it.
func _build_screen() -> void:
	_screen = MeshInstance3D.new()
	_screen.name = "Screen"
	var quad := QuadMesh.new()
	quad.size = Vector2(SCREEN_WIDTH, SCREEN_LENGTH)
	_screen.mesh = quad
	_screen_material = StandardMaterial3D.new()
	_screen_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_screen_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_screen.material_override = _screen_material
	_screen.position = Vector3(0.0, BAND_RADIUS + 0.0345, 0.012)
	_screen.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wear.add_child(_screen)
	_name_label = Label3D.new()
	_name_label.pixel_size = 0.00035
	_name_label.font_size = 28
	_name_label.outline_size = 6
	_name_label.outline_modulate = Color(0, 0, 0, 0.85)
	_name_label.shaded = false
	_name_label.double_sided = false
	_name_label.position = Vector3(0.0, -SCREEN_LENGTH * 0.5 + 0.009, 0.001)
	_name_label.render_priority = 1
	_screen.add_child(_name_label)


func _build_hologram() -> void:
	_holo = Node3D.new()
	_holo.name = "Hologram"
	_holo.position = HOLO_ON_BAND
	_holo.visible = false
	_wear.add_child(_holo)

	var count := PlaylotMultitool.MODES.size()
	for i in count:
		var row := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(ROW_WIDTH, ROW_HEIGHT * 0.88)
		row.mesh = quad
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.no_depth_test = true
		row.material_override = m
		var a := (float(count - 1) * 0.5 - float(i)) * HOLO_STEP
		row.position = Vector3(0.0, sin(a) * HOLO_RADIUS, (1.0 - cos(a)) * HOLO_RADIUS)
		row.rotation.x = a
		row.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_holo.add_child(row)
		var label := Label3D.new()
		label.pixel_size = 0.0008
		label.font_size = 28
		label.outline_size = 8
		label.shaded = false
		label.no_depth_test = true
		label.double_sided = true
		label.position = Vector3(0.0, 0.0, 0.002)
		label.render_priority = 2
		row.add_child(label)
		_rows.append(row)
		_labels.append(label)
		_row_materials.append(m)
		m.render_priority = 1


# --- Geometry: boxes and cylinders merged into one surface ------------------

static func _box(st: SurfaceTool, xf: Transform3D, size: Vector3) -> void:
	if size.x <= 0.0:
		return
	var h := size * 0.5
	var faces := [
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
		[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
		[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var c := n * h
		var corners := [
			c - u * h - v * h, c + u * h - v * h, c + u * h + v * h, c - u * h + v * h,
		]
		var wn := (xf.basis * n).normalized()
		for idx in [0, 2, 1, 0, 3, 2]:
			st.set_normal(wn)
			st.add_vertex(xf * (corners[idx] as Vector3))


## A solid cylinder along Z, centred at [param at].
static func _cylinder_z(st: SurfaceTool, at: Vector3, radius: float, length: float, sides: int) -> void:
	var half := length * 0.5
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var p0 := Vector3(cos(a0) * radius, sin(a0) * radius, 0.0)
		var p1 := Vector3(cos(a1) * radius, sin(a1) * radius, 0.0)
		var n0 := Vector3(cos(a0), sin(a0), 0.0)
		var n1 := Vector3(cos(a1), sin(a1), 0.0)
		var zf := Vector3(0, 0, half)
		var zb := Vector3(0, 0, -half)
		for q in [[p0 + zf, n0], [p1 + zf, n1], [p1 + zb, n1], [p0 + zf, n0], [p1 + zb, n1], [p0 + zb, n0]]:
			st.set_normal(q[1])
			st.add_vertex(at + (q[0] as Vector3))
		for cap in [[half, Vector3(0, 0, 1)], [-half, Vector3(0, 0, -1)]]:
			var z: float = cap[0]
			var order: Array = [Vector3.ZERO, p0, p1] if z > 0.0 else [Vector3.ZERO, p1, p0]
			for p in order:
				st.set_normal(cap[1])
				st.add_vertex(at + (p as Vector3) + Vector3(0, 0, z))


## A flat ring (a short hollow cylinder wall) round Z, for the band's edges.
static func _ring(st: SurfaceTool, at: Vector3, outer: float, length: float, sides: int) -> void:
	var half := length * 0.5
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var d0 := Vector3(cos(a0), sin(a0), 0.0)
		var d1 := Vector3(cos(a1), sin(a1), 0.0)
		var zf := Vector3(0, 0, half)
		var zb := Vector3(0, 0, -half)
		for q in [[d0 * outer + zf, d0], [d1 * outer + zf, d1], [d1 * outer + zb, d1],
				[d0 * outer + zf, d0], [d1 * outer + zb, d1], [d0 * outer + zb, d0]]:
			st.set_normal(q[1])
			st.add_vertex(at + (q[0] as Vector3))
