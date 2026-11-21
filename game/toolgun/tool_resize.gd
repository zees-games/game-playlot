extends "playlot_tool.gd"

## Inflate and deflate: left click grows a prop, right click shrinks it, reload puts it back.
##
## By a factor rather than by a step in metres, so a die and a boulder both grow in a few
## clicks; and from the definition each time (`PlaylotProp.set_size_scale`), so ten
## inflates and ten deflates land exactly where they started.


func _init() -> void:
	id = &"resize"
	display_name = "Inflate / deflate"
	description = "Makes a prop bigger or smaller. Mass goes with the size."
	help_primary = "inflate"
	help_secondary = "deflate"
	help_reload = "back to its own size"
	super()


func schema() -> Array[Dictionary]:
	return [{
		"key": "step", "label": "Step", "type": "float",
		"default": 0.25, "min": 0.05, "max": 1.0, "step": 0.05,
	}]


func primary(_gun: Object, hit: Dictionary) -> GSResult:
	return _scale(hit, 1.0 + float(setting("step")))


func secondary(_gun: Object, hit: Dictionary) -> GSResult:
	return _scale(hit, 1.0 / (1.0 + float(setting("step"))))


func reload(_gun: Object, hit: Dictionary) -> GSResult:
	var body := prop_body(hit)

	if body == null:
		return nothing_there()

	return GSResult.success(body.call("set_size_scale", 1.0))


func _scale(hit: Dictionary, by: float) -> GSResult:
	var body := prop_body(hit)

	if body == null:
		return nothing_there()

	var before := float(body.get("size_scale"))
	var after := float(body.call("set_size_scale", before * by))

	if is_equal_approx(before, after):
		return GSResult.fail(
			GSError.CODE_STATE,
			"That is as %s as it goes." % ("big" if by > 1.0 else "small")
		)

	return GSResult.success(after)
