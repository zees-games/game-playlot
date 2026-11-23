extends Node3D
## What leaves the multi-tool's palm emitter, one look per mode: the physics gun's grab flare, the gravity
## gun's punt shock ring, push's double pulse, spawn's orb, the remover's red lance and the tool
## gun's thin trace; and while a prop is held, a ring spinning round the palm. Owned by the device and drawn in
## world space from its muzzle, so it is the same on the player's own arms, on everyone else's wrist and in
## third person. Driven only by replicated state: a mode, the fire counter's kick and the server's held list.
## Five nodes built once and reused, so a burst allocates nothing.

const PlaylotMultitool := preload("playlot_multitool.gd")

## How long each mode's burst lasts, seconds.
const LIFE := {&"phys": 0.16, &"grav": 0.26, &"impulse": 0.36, &"spawn": 0.32, &"remover": 0.24, &"toolgun": 0.14}
## How far each mode's burst reaches, metres.
const REACH := {&"phys": 0.9, &"grav": 1.6, &"impulse": 2.4, &"spawn": 2.0, &"remover": 5.0, &"toolgun": 8.0}
const HOLD_LINGER := 0.12

## The emitter's mouth: every burst and the hold ring follow it, read after the client's frame placed it.
var muzzle: Node3D = null

var _rings: Array[MeshInstance3D] = []
var _tracer: MeshInstance3D
var _orb: MeshInstance3D
var _hold_ring: MeshInstance3D
var _mode: StringName = &""
var _age := 1.0
var _from := Vector3.ZERO
var _aim := Vector3.FORWARD
var _hold := 0.0
var _hold_at := Transform3D.IDENTITY
var _spin := 0.0
var _last_fired: StringName = &""


func _init() -> void:
	name = "Effects"
	top_level = true
	process_priority = 100
	for i in 2:
		_rings.append(_part("Ring%d" % i, _torus()))
	var line := CylinderMesh.new()
	line.top_radius = 1.0
	line.bottom_radius = 1.0
	line.height = 1.0
	line.radial_segments = 8
	line.rings = 1
	line.cap_top = false
	line.cap_bottom = false
	_tracer = _part("Tracer", line)
	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	ball.radial_segments = 12
	ball.rings = 6
	_orb = _part("Orb", ball)
	_hold_ring = _part("HoldRing", _torus())


## A burst of [param mode]'s effect from [param from] along [param aim] (world space).
func fire(mode: StringName, from: Vector3, aim: Vector3) -> void:
	_mode = mode
	_last_fired = mode
	_from = from
	_aim = aim.normalized() if aim.length_squared() > 0.0001 else Vector3.FORWARD
	_age = 0.0
	var colour: Color = PlaylotMultitool.COLOURS.get(mode, Color.WHITE)
	for part in [_rings[0], _rings[1], _tracer, _orb]:
		(part.material_override as StandardMaterial3D).albedo_color = colour


## A prop held this frame by [param mode] from [param from]: the palm ring spins while it lasts.
func hold(mode: StringName, from: Vector3, aim: Vector3) -> void:
	_hold = HOLD_LINGER
	_hold_at = _facing(from, aim)
	var colour: Color = PlaylotMultitool.COLOURS.get(mode, Color.WHITE)
	(_hold_ring.material_override as StandardMaterial3D).albedo_color = colour


## The mode of the last burst, and whether one or a hold is showing: for the suites.
func describe() -> Dictionary:
	return {"fired": _last_fired, "bursting": _tracer.visible or _orb.visible or _rings[0].visible, "holding": _hold_ring.visible}


func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if muzzle != null and is_instance_valid(muzzle) and muzzle.is_inside_tree():
		_from = muzzle.global_position
		_hold_at.origin = _from
	_age += delta
	_spin += delta * 9.0
	_hold = maxf(0.0, _hold - delta)
	_hold_ring.visible = _hold > 0.0
	if _hold_ring.visible:
		var pulse := 0.022 + 0.004 * sin(_spin * 2.0)
		_hold_ring.global_transform = Transform3D(_hold_at.basis * Basis(Vector3.BACK, _spin) * _flat(pulse), _hold_at.origin)
		_fade(_hold_ring, 0.75)
	var life: float = LIFE.get(_mode, 0.2)
	var t := _age / life
	var on := t < 1.0
	for part in [_rings[0], _rings[1], _tracer, _orb]:
		part.visible = false
	if not on:
		return
	var reach: float = REACH.get(_mode, 1.0)
	var out := 1.0 - pow(1.0 - t, 2.0)
	var fade := 1.0 - t
	match _mode:
		&"phys":
			_line(0.9 * reach * out, 0.004, fade)
			_ball(_from, 0.018 + 0.012 * out, fade)
		&"grav":
			_ring(_rings[0], reach * out, 0.04 + 0.3 * out, fade)
			_ball(_from, 0.03 * (1.0 - t) + 0.01, fade)
		&"impulse":
			_ring(_rings[0], reach * out, 0.06 + 0.7 * out, fade)
			var late := clampf((t - 0.2) / 0.8, 0.0, 1.0)
			if late > 0.0:
				var late_out := 1.0 - pow(1.0 - late, 2.0)
				_ring(_rings[1], reach * 0.7 * late_out, 0.05 + 0.5 * late_out, 1.0 - late)
		&"spawn":
			_ball(_from + _aim * reach * out, 0.02 + 0.08 * out * out, fade)
			_ring(_rings[0], 0.03, 0.03 + 0.05 * out, fade)
		&"remover":
			var wobble := 0.004 * sin(_age * 90.0)
			_line(reach * minf(1.0, t * 4.0), 0.007 + wobble, fade)
			_ball(_from, 0.02, fade)
		_:
			_line(reach * minf(1.0, t * 6.0), 0.0025, fade)
			_ball(_from, 0.012, fade)


func _line(length: float, radius: float, alpha: float) -> void:
	if length <= 0.001:
		return
	var t := _facing(_from + _aim * (0.5 * length), _aim)
	# The cylinder runs along Y: turned onto -Z, stretched to length.
	t.basis = t.basis * Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(radius, length, radius))
	_tracer.global_transform = t
	_tracer.visible = true
	_fade(_tracer, alpha)


func _ball(at: Vector3, radius: float, alpha: float) -> void:
	_orb.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * radius), at)
	_orb.visible = true
	_fade(_orb, alpha)


func _ring(part: MeshInstance3D, along: float, radius: float, alpha: float) -> void:
	var t := _facing(_from + _aim * along, _aim)
	t.basis = t.basis * _flat(radius)
	part.global_transform = t
	part.visible = true
	_fade(part, alpha)


static func _fade(part: MeshInstance3D, alpha: float) -> void:
	var material := part.material_override as StandardMaterial3D
	material.albedo_color.a = clampf(alpha, 0.0, 1.0) * 0.85


## A transform at [param at] whose -Z is [param direction]; the torus is turned so its hole faces along it.
static func _facing(at: Vector3, direction: Vector3) -> Transform3D:
	var forward := direction.normalized() if direction.length_squared() > 0.0 else Vector3.FORWARD
	var up := Vector3.RIGHT if absf(forward.dot(Vector3.UP)) > 0.99 else Vector3.UP
	return Transform3D(Basis.looking_at(forward, up), at)


## The torus (hole along Y) turned to face -Z at [param radius], its tube half as thick.
static func _flat(radius: float) -> Basis:
	return Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(radius, radius * 0.5, radius))


static func _torus() -> TorusMesh:
	var ring := TorusMesh.new()
	ring.inner_radius = 0.86
	ring.outer_radius = 1.0
	ring.rings = 24
	ring.ring_segments = 6
	return ring


func _part(part_name: String, mesh: Mesh) -> MeshInstance3D:
	var made := MeshInstance3D.new()
	made.name = part_name
	made.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Mixed, not added: added over sky and grass the orange ring and the yellow one read the same.
	material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	made.material_override = material
	made.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	made.visible = false
	add_child(made)
	return made
