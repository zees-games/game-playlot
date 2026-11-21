extends Node

const PlaylotClient := preload("../game/playlot_client.gd")
const PlaylotConfig := preload("../game/playlot_config.gd")
const PlaylotPresentation := preload("../game/playlot_presentation.gd")

## Renders the Escape menu and the console through the real offline client (the platform owns
## the menu, the pointer and the console) into `screenshots/touch/`.
##
## [codeblock]
## xvfb-run -a godot --path . --resolution 1280x720 res://tools/render_touch.tscn
## [/codeblock]

const OUT_DIR := "res://screenshots/touch"

var _client: PlaylotClient = null


func _ready() -> void:
	GSPlatform.touch_override = 1
	PlaylotPresentation.use_scratch_settings("render_touch")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_client = PlaylotClient.new()
	_client.name = "Client"
	var config := PlaylotConfig.new()
	config.records_directory = ""
	config.record_replays = false
	_client.config = config
	add_child(_client)
	_run.call_deferred()


func _run() -> void:
	await _frames(60)
	await _shot("play")
	get_tree().quit()


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, shot_name])
	print(shot_name, " -> ", error_string(get_viewport().get_texture().get_image().save_png(path)))


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame
