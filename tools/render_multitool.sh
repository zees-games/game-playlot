#!/usr/bin/env bash
# Renders the multi-tool filmstrip sheets (tools/render_multitool.gd) into screenshots/multitool/ on a GPU box.
set -euo pipefail
cd "$(dirname "$0")/.."
out=${1:-screenshots/multitool}
mkdir -p "$out"
exec xvfb-run -a godot --path . --resolution 1280x720 res://tools/render_multitool.tscn -- "$PWD/$out" "${@:2}"
