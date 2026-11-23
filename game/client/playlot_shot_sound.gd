extends Node

## One gs-audio layered shot (zee's [ZeeShotLayers]) for every rig this client arms, handed to each rig's
## [ZeeShotFx] as its `shot_sound`. Left to itself every ZeeShotFx builds its own on its first shot: a manager,
## an enclosure, a player and 13 stock shots, ~30 ms and ~30 nodes on the first shot of every weapon picked.

const PlaylotZee := preload("../playlot_zee.gd")

## The bus the room tail is sent to, as [member ZeeShotFx.bus].
var bus: StringName = &"Master"

## Shots this played, for a suite.
var played: int = 0

var _layers: Node = null
## False once the layers could not be built: every rig then plays its own sound, as without this node.
var _usable := true
## The room is measured once a shot has been heard, as ZeeShotFx measured it, so an unarmed client pays nothing.
var _heard := false


## Builds the layers now, under the loading cover; otherwise the first shot does. True when they are ready.
func warm() -> bool:
	if _layers != null:
		return bool(_layers.call(&"is_ready"))
	if not _usable or not PlaylotZee.shot_layers_available():
		_usable = false
		return false
	_layers = PlaylotZee.new_shot_layers()
	if _layers == null:
		_usable = false
		return false
	_layers.name = "ShotLayers"
	add_child(_layers)
	if not bool(_layers.call(&"setup", bus)):
		_usable = false
		return false
	return true


func is_ready() -> bool:
	return _layers != null and bool(_layers.call(&"is_ready"))


## Gives [param fx] (a ZeeShotFx) this node's layered shot in place of one of its own.
func attach(fx: Object) -> void:
	if fx != null and _usable and is_inside_tree():
		fx.set(&"shot_sound", _play.bind(fx))


## `ZeeShotFx.shot_sound`, bound to its fx: false for a class with no stock shot, or with layered shots off on the
## fx, leaves the fx's own sound.
func _play(id: StringName, kind: StringName, at: Vector3, _indoors: bool, fx: Object) -> bool:
	var weapon_class := PlaylotZee.sound_class_for(id, kind)
	if PlaylotZee.layer_shot_class(weapon_class) == &"" or not is_inside_tree():
		return false
	if fx == null or not is_instance_valid(fx) or not bool(fx.get(&"layered_shots")) or not warm():
		return false
	var camera := get_viewport().get_camera_3d()
	if not bool(_layers.call(&"fire", weapon_class, at, camera.global_position if camera != null else at)):
		return false
	_heard = true
	played += 1
	fx.emit_signal(&"heard", PlaylotZee.sound_stream_for(id, kind))
	return true


func _process(delta: float) -> void:
	if not _heard or _layers == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		_layers.call(&"probe", delta, camera.global_position, camera.get_world_3d().direct_space_state)
