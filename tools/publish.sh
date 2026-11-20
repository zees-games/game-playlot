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
PUB="$CLOUD/tools/publish_pack.sh"; GV="$V"
BASE=(publish --source "$HERE" --id game-playlot --host-addons "$HOSTLOCK" "${EX[@]}" --exclude-dir images --exclude-dir screenshots --exclude-dir maps/custom)
# Gates before an upload (a --dry-run gets the first only): every load of the game's own files goes through the
# game's path rebase (tools/check_pack_paths.sh), and the pack a dry run builds boots mounted, under
# res://dot_cloud/<id>/<version>/, on a host built at addons.lock's tags (tools/pack_boot_test.sh). Airdrift and
# Playlot 0.1.33 and Zombie Zone 0.1.40 failed the second (stale trees, a renamed addon) and booted nothing on servers.
"$HERE/tools/check_pack_paths.sh" "$HERE"
case " $* " in *" --dry-run "*) ;; *)
    G=(); skip=""
    for a in "$@"; do
        if [ -n "$skip" ]; then [ "$skip" = --version ] && GV="$a"; skip=""; continue; fi
        case "$a" in --version|--bump|--out|--site|--token-file|--lock) skip="$a" ;; *) G+=("$a") ;; esac
    done
    T="$(mktemp -d)"
    # Keep the gates' verdicts: 1 = does not boot, anything else = could not judge (2), never turned into a verdict.
    rc=0; "$PUB" "${BASE[@]}" --version "$GV" "${G[@]}" --dry-run --out "$T/out" >&2 \
        && "$HERE/tools/pack_boot_test.sh" "$T/out" "$HOSTLOCK" || rc=$?
    if [ "$rc" != 0 ]; then
        [ "$rc" = 1 ] || rc=2; rm -rf "$T"
        echo "publish: refusing to upload (gates above, exit $rc: 1 does not boot, 2 could not judge); nothing was sent" >&2; exit "$rc"
    fi
    rm -rf "$T"; set -- "$@" --no-import ;;
esac
exec "$PUB" "${BASE[@]}" --version "$V" --lock "$HERE/content.lock.json" "$@"
