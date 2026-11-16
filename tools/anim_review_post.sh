#!/usr/bin/env bash
# Post an anim_review run to a nightly review: one clip per weapon and clip,
# labelled with its verdict and metrics from report.md.
#
#   tools/anim_review_post.sh <review-key> [--variant before|after] [--dir screenshots/anim_review]
#
# Create the review first: nightly review new "PLAYLOT animation review" --key <key>.
# Runs nightly as core (NIGHTLY, default the board's path), so the files are
# staged in a world-readable temp dir first.
# Game-local until dot-game's shared visual QA lands (nightly dot-game-visual-qa-1);
# then this becomes a wrapper around it.
set -euo pipefail

key="${1:?usage: anim_review_post.sh <review-key> [--variant before|after] [--dir D]}"
shift
variant=""
dir="screenshots/anim_review"
while [[ $# -gt 0 ]]; do
	case "$1" in
		--variant) variant="$2"; shift 2 ;;
		--dir) dir="$2"; shift 2 ;;
		*) echo "anim_review_post: unknown argument $1" >&2; exit 2 ;;
	esac
done
NIGHTLY="${NIGHTLY:-/home/core/stack/nightly/bin/nightly}"
report="$dir/report.md"
[[ -f "$report" ]] || { echo "anim_review_post: no $report; run tools/anim_review.sh first" >&2; exit 1; }

stage="$(mktemp -d /tmp/anim-review-post.XXXXXX)"
chmod 755 "$stage"
trap 'rm -rf "$stage"' EXIT

posted=0
failed=0
# Rows: | weapon | clip | verdict | why | hand max m | pop m | pop deg |
while IFS='|' read -r _ weapon clip verdict why hand pop deg _; do
	weapon="$(echo "$weapon" | xargs)"; clip="$(echo "$clip" | xargs)"
	verdict="$(echo "$verdict" | xargs)"; why="$(echo "$why" | xargs)"
	[[ -z "$weapon" || "$weapon" == weapon || "$weapon" == ---* ]] && continue
	src="$dir/$weapon/$clip.mp4"
	if [[ ! -f "$src" ]]; then
		echo "anim_review_post: missing $src" >&2
		failed=$((failed + 1))
		continue
	fi
	dst="$stage/${weapon}_${clip}${variant:+_$variant}.mp4"
	cp "$src" "$dst"
	chmod 644 "$dst"
	metrics="$(printf '{"verdict":"%s","hand_max_m":"%s","pop_m":"%s","pop_deg":"%s"}' \
		"$verdict" "$(echo "$hand" | xargs)" "$(echo "$pop" | xargs)" "$(echo "$deg" | xargs)")"
	args=(review media "$key" "$weapon" "$dst" --slot clip --label "$clip $verdict" --metrics "$metrics" --by anim-review)
	[[ -n "$variant" ]] && args+=(--variant "$variant")
	[[ -n "$why" && "$why" != "-" ]] && args+=(--look "$why")
	if sudo -u core "$NIGHTLY" "${args[@]}" >/dev/null; then
		posted=$((posted + 1))
	else
		echo "anim_review_post: posting $weapon/$clip failed" >&2
		failed=$((failed + 1))
	fi
done < "$report"
echo "anim_review_post: $posted posted, $failed failed to $key"
[[ $failed -eq 0 ]]
