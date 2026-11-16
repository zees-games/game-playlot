extends Node

const PlaylotClient := preload("../game/playlot_client.gd")
const PlaylotConfig := preload("../game/playlot_config.gd")
const PlaylotPresentation := preload("../game/playlot_presentation.gd")

## Renders the offline client at rest and mid-flinch after a hit into `screenshots/flinch/`, and prints whether the camera moved.
##
## Run: `xvfb-run -a godot --path . --resolution 1280x720 res://tools/render_flinch.tscn`

const OUT_DIR := "res://screenshots/flinch"

var _client: PlaylotClient = null


func _ready() -> void:
	PlaylotPresentation.use_scratch_settings("render_flinch")
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
	await get_tree().create_timer(2.5).timeout
	var rest := await _shot("rest")
	_client.platform.note_hit(80.0)
	await get_tree().create_timer(0.06).timeout
	var hit := await _shot("flinch")
	var moved := not rest.is_equal_approx(hit)
	print("camera moved by the flinch: %s (%s -> %s)" % [moved, rest, hit])
	get_tree().quit(0 if moved else 1)


## Frame sequence after each still (GS_SHOT_FRAMES, set by the .sh); see DotShotSeq.
var _seq := DotShotSeq.new()


func _shot(shot_name: String) -> Transform3D:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, shot_name])
	print("%s: %s" % [shot_name, error_string(image.save_png(path))])
	await _seq.record(get_tree(), path)
	return _client.camera.global_transform
