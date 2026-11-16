#!/bin/bash
# Publishes this game's pack. Linked addons (symlinks in addons/) are left out: the host ships them. The game-owned adapters
# committed in addons/ (pg_timer, pg_natural_disasters) must ship, so addons/ is not excluded wholesale. images/ and screenshots/ are README art.
# maps/custom (the linked playlot-maps checkout) never ships: playlot-maps is its own pack, and a map id already in the catalogue
# is never replaced, so a copy in this pack would shadow every maps update (0.1.32 shipped a 311-box pgc_fork stub that way).
#   tools/publish.sh VERSION [extra publish_pack.sh flags, e.g. --site URL --token-file F --lock F --dry-run]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
V=${1:?usage: tools/publish.sh VERSION [flags]}; shift
# A worktree under ~/wt has no sibling dot-cloud / dot-server-deploy: GS_CLOUD and GS_HOST_LOCK name them, else the family beside the main clone.
FAM="$(cd "$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir)/../.." && pwd)"
CLOUD=${GS_CLOUD:-${DOT_CLOUD:-$FAM/dot-cloud}}; HOSTLOCK=${GS_HOST_LOCK:-${DOT_HOST_LOCK:-$FAM/dot-server-deploy/addons.lock}}
EX=(); for l in "$HERE"/addons/*; do [ -L "$l" ] && EX+=(--exclude-dir "$(basename "$l")"); done
exec "$CLOUD/tools/publish_pack.sh" publish --source "$HERE" --id game-playlot --version "$V" --host-addons "$HOSTLOCK" \
    "${EX[@]}" --exclude-dir images --exclude-dir screenshots --exclude-dir maps/custom \
    --lock "$HERE/content.lock.json" "$@"
