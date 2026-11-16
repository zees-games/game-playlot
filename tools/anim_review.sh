#!/usr/bin/env bash
# The animation review's capture step (docs/anim-review.md): plays the zee weapons' clips (idle, draw, fire, reload, ads,
# sprint) and the avatar's locomotion (avatar_walk, _strafe, _run, _crouch, _jump) and writes, per weapon and clip,
# labelled contact sheets for first person, behind-right and the opponent's view, one side-by-side <weapon>/<clip>.mp4
# at --fps (default 60), and report.md with a PASS/FAIL verdict from the glitch numbers.
#   tools/anim_review.sh [--only rifle,pistol|all] [--anims fire,reload] [--no-avatar] [--fps 60] [--soft]
# Default weapons: the first of each pose. The capture goes to a GPU box through gpu.sh shot (clips copied back with
# --pull) and, when no box takes it, through heavy here; run it as gamedev from the checkout or a ~/wt worktree.
# --soft keeps it here on software rendering.
set -euo pipefail
cd "$(dirname "$0")/.."
soft=0 fps=60 pass=()
while (($#)); do
  case $1 in
    --only | --anims) pass+=("$1" "$2"); shift 2 ;;
    --no-avatar) pass+=("$1"); shift ;;
    --fps) fps=$2; shift 2 ;;
    --soft) soft=1; shift ;;
    *) echo "anim_review.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done
command -v heavy > /dev/null || PATH=$HOME/bin:$HOME/.local/bin:/home/gamedev/bin:/home/gamedev/.local/bin:$PATH
out=screenshots/anim_review
log=$out/capture.log
rm -rf "$out"
mkdir -p "$out"
[[ $soft == 1 ]] && export GPU_OFFLOAD=0
# The clips come back through a scratch directory at the same absolute path on the box and here.
clips=$(mktemp -d /tmp/anim-review-clips.XXXXXX)
chmod 755 "$clips"
trap 'rm -rf "$clips"' EXIT
shot=(tools/anim_review_shot.sh --out "$out" --clips "$clips" --fps "$fps" "${pass[@]}")
gpu=$(dirname "$PWD")/gpu.sh
rc=75
# --route: exit 75 when no box takes it (then heavy queues it here), else the tool's own exit code.
if [[ $soft == 0 && -x $gpu ]]; then
  rc=0
  SHOT_DIR=$PWD GPU_SHOT_WAIT=${GPU_SHOT_WAIT:-1500} "$gpu" shot --route --timeout 3500 --pull "$clips" "$(basename "$PWD")" "${shot[@]}" > "$log" 2>&1 || rc=$?
fi
if [[ $rc == 75 ]]; then
  rc=0
  heavy -- timeout 3500 "${shot[@]}" > "$log" 2>&1 || rc=$?
fi
for c in "$clips"/*__*.mp4; do
  [[ -e $c ]] || continue
  n=$(basename "$c" .mp4)
  mkdir -p "$out/${n%%__*}"
  mv "$c" "$out/${n%%__*}/${n#*__}.mp4"
done
python3 - "$log" "$out/report.md" "$fps" <<'PY'
import json, sys
log, report, fps = sys.argv[1:4]
rows = []
for line in open(log, errors="replace"):
    if line.startswith("ANIMREVIEW {"):
        rows.append(json.loads(line[len("ANIMREVIEW "):]))
with open(report, "w") as f:
    f.write(f"# PLAYLOT animation review\n\nfps: {fps}\n\n")
    f.write("| weapon | clip | verdict | why | hand max m | pop m | pop deg |\n|---|---|---|---|---|---|---|\n")
    for r in rows:
        f.write(f"| {r['weapon']} | {r['clip']} | {r['verdict']} | {r['why']} | {r['hand_max_m']} | {r['pop_m']} | {r['pop_deg']} |\n")
fails = sum(r["verdict"] == "FAIL" for r in rows)
print(f"anim_review.sh: {len(rows)} clips, {fails} FAIL; {report}")
PY
grep -E 'SCRIPT ERROR|Parse Error|ERROR: ' "$log" | head -20 || true
exit $rc
