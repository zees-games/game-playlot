#!/bin/bash
# Publishes this game's pack. Linked addons (symlinks in addons/) are left out: the host ships them. The game-owned adapters
# committed in addons/ (pg_timer, pg_natural_disasters) must ship, so addons/ is not excluded wholesale. images/ and screenshots/ are README art.
# maps/custom (the linked playlot-maps checkout) never ships: playlot-maps is its own pack, and a map id already in the catalogue
# is never replaced, so a copy in this pack would shadow every maps update (0.1.32 shipped a 311-box pgc_fork stub that way).
#   tools/publish.sh VERSION [extra publish_pack.sh flags, e.g. --site URL --token-file F --lock F --dry-run]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
V=${1:?usage: tools/publish.sh VERSION [flags]}; shift
# A worktree under ~/wt has no sibling gs-cloud / gs-server-deploy: GS_CLOUD and GS_HOST_LOCK name them, else the family beside the main clone.
FAM="$(cd "$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir)/../.." && pwd)"
CLOUD=${GS_CLOUD:-$FAM/gs-cloud}; HOSTLOCK=${GS_HOST_LOCK:-$FAM/gs-server-deploy/addons.lock}
EX=(); for l in "$HERE"/addons/*; do [ -L "$l" ] && EX+=(--exclude-dir "$(basename "$l")"); done
PUB="$CLOUD/tools/publish_pack.sh"; GV="$V"
BASE=(publish --source "$HERE" --id game-playlot --host-addons "$HOSTLOCK" "${EX[@]}" --exclude-dir images --exclude-dir screenshots --exclude-dir maps/custom)
# Gates before an upload: every load of the game's own files goes through the game's path rebase
# (tools/check_pack_paths.sh), and publish_pack.sh boots the pack it builds mounted, under res://gs_cloud/<id>/<version>/,
# on a host built at --host-addons addons.lock's tags (gs-cloud tools/pack_boot_test.sh; exit 1 does not boot, 2 could
# not judge). Airdrift and Playlot 0.1.33, Zombie Zone 0.1.40 and Hungario 0.1.19 booted nothing on servers without it.
"$HERE/tools/check_pack_paths.sh" "$HERE"
exec "$PUB" "${BASE[@]}" --version "$V" --lock "$HERE/content.lock.json" "$@"
