extends GSGameWorkbenchSuite

## game-playlot: the workbench over the config binder, one edit per profile set, the export and its cfg round trip.
## Run: godot --headless --path . res://examples/headless_workbench.tscn

const PlaylotConfig := preload("../game/playlot_config.gd")


func _make_config() -> GSConfig:
	return PlaylotConfig.new()


func _make_binder(config: GSConfig) -> GSGameConfigBinder:
	return PlaylotConfig.make_binder(config)
