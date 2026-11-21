extends "playlot_tool.gd"

## Wires a button or a lever to a door: left click what says something, then what hears it.
## Right click takes every wire off a prop. dot-props' [GSPropIO] keeps the wires; what an
## input does is [Playlot]'s.
##
## [b]Which input is a setting, not a third click.[/b] A door has three (open, close,
## toggle), and a button wired to "toggle" is what almost everybody means, so that is the
## default; a pair of buttons, one to open and one to close, is the setting changed once.


func _init() -> void:
	id = &"wire"
	display_name = "Wire"
	description = "Wires a button or a lever to a door. Press the button with F."
	help_primary = "what says it, then what hears it"
	help_secondary = "take every wire off a prop"
	super()


func schema() -> Array[Dictionary]:
	return [
		{"key": "input", "label": "What it does", "type": "choice", "default": "toggle",
			"options": ["toggle", "open", "close"]},
	]


func primary(gun: Object, hit: Dictionary) -> GSResult:
	var prop: GSPropInstance = hit.get("prop")

	if prop == null:
		return nothing_there()

	var io: GSPropIO = gun.get("game").get("io") if gun.get("game") != null else null

	if io == null:
		return GSResult.fail(GSError.CODE_STATE, "Wiring is not available here.")

	if pending.is_empty():
		var outputs := GSPropIO.outputs_of(prop.def)

		if outputs.is_empty():
			return GSResult.fail(GSError.CODE_INVALID, "%s has nothing to say. Start at a button or a lever." % prop.def.name_or_id())

		pending = {"from": prop.instance_id, "output": outputs[0]}
		return GSResult.success("first")

	var from := int(pending["from"])
	var output := StringName(str(pending["output"]))
	pending = {}

	var inputs := GSPropIO.inputs_of(prop.def)
	var wanted := str(setting("input"))
	var input := wanted if inputs.has(wanted) else (inputs[0] if not inputs.is_empty() else "")

	if input == "":
		return GSResult.fail(GSError.CODE_INVALID, "%s hears nothing. End at a door." % prop.def.name_or_id())

	return io.link(from, output, prop.instance_id, StringName(input))


func secondary(gun: Object, hit: Dictionary) -> GSResult:
	var prop: GSPropInstance = hit.get("prop")

	if prop == null:
		return nothing_there()

	var io: GSPropIO = gun.get("game").get("io") if gun.get("game") != null else null
	return GSResult.success(io.unlink_all(prop.instance_id) if io != null else 0)
