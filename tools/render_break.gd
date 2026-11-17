extends Node

const PlaylotClient := preload("../game/playlot_client.gd")
const PlaylotConfig := preload("../game/playlot_config.gd")
const PlaylotPresentation := preload("../game/playlot_presentation.gd")

## Renders a crate and a pane breaking in front of the offline client into `screenshots/break/`.
##
## Run: `xvfb-run -a godot --path . --resolution 1280x720 res://tools/render_break.tscn`

const OUT_DIR := "res://screenshots/break"

var _client: PlaylotClient = null


func _ready() -> void:
	PlaylotPresentation.use_scratch_settings("render_break")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_client = PlaylotClient.new()
	_client.name = "Client"
	var config := PlaylotConfig.new()
	config.records_directory = ""
	config.record_replays = false
	_client.config = config
	add_child(_client)
	_run.call_deferred()


## Frame sequence after each still (DOT_SHOT_FRAMES, set by the .sh); see DotShotSeq.
var _seq := DotShotSeq.new()


func _run() -> void:
	await get_tree().create_timer(2.5).timeout
	var cam := _client.camera.global_transform
	var ahead := cam.origin - cam.basis.z * 3.0
	_client.playlot.prop_shattered.emit(ahead + cam.basis.x * -0.8, 1)
	_client.presentation.on_pane_broken(ahead + cam.basis.x * 0.8)
	await get_tree().create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	print("break: %s, bursts %d" % [error_string(image.save_png(ProjectSettings.globalize_path(OUT_DIR + "/break.png"))),
		_client.presentation.break_fx.break_fx.spawned])
	await _seq.record(get_tree(), ProjectSettings.globalize_path(OUT_DIR + "/break.png"))
	get_tree().quit()
