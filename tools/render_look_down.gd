extends Node

const PlaylotClient := preload("../game/playlot_client.gd")
const PlaylotConfig := preload("../game/playlot_config.gd")
const PlaylotPresentation := preload("../game/playlot_presentation.gd")

## Renders the offline client's first-person camera pitched steeply down, to `screenshots/look_down.png`: what your own body looks like from inside it.
##
## Run: `xvfb-run -a godot --path . --resolution 1280x720 res://tools/render_look_down.tscn`

var _client: PlaylotClient = null


func _ready() -> void:
	PlaylotPresentation.use_scratch_settings("render_look_down")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots"))
	_client = PlaylotClient.new()
	_client.name = "Client"
	var config := PlaylotConfig.new()
	config.records_directory = ""
	config.record_replays = false
	_client.config = config
	add_child(_client)
	_run.call_deferred()


func _run() -> void:
	await get_tree().create_timer(2.0).timeout
	_client.mouse_capture_override = true
	_client.active_sampler().look_at_angles(_client.player.controller.state.yaw, -70.0)
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	print("body_shown=%s view=%s save=%s" % [_client.player.body_shown(), _client.view_id(),
		error_string(image.save_png(ProjectSettings.globalize_path("res://screenshots/look_down.png")))])
	get_tree().quit()
