#!/usr/bin/env bash
# The converted-map judge loop (docs/map-judge-rubric.md): a GPU capture of a converted map (tools/screenshot.sh on
# a GPU box through dot-bootstrap's gpu.sh, never software rendering), then a FRESH judge (claude -p, no author
# context) that reads the rubric and every frame and writes verdict.json with production_ready true|false; then
# fix -> recapture -> fresh judge until it passes. Run as gamedev from the game-playlot checkout or a ~/wt worktree:
#   tools/map_judge.sh --map pgc_fork [--out DIR] [--model opus] [--max-rounds N] [--fix-cmd 'CMD'] [--give-up]
#        [--no-capture] [--views 'NAME:FX,FY,FZ:AX,AY,AZ ...'] [--repos a,b]
# --fix-cmd: run between rounds with VERDICT=<out>/verdict.json in its environment; without it each call is one round
#   and the author fixes and calls again (the round count is kept in --out).
# --max-rounds (env MAP_JUDGE_MAX_ROUNDS, default 0 = unlimited): at that round, or with --give-up, every unresolved
#   blocker/major defect gets a nightly item (key written back into verdict.json) and the tool exits 3.
# --model: the judge's model, opus (default) or sonnet; never another tier.
# The verdict schema is dot-game's visual judge's (addons/dot_game/tools/dot_game_visual_judge.sh, clip-based); this
# is its still-frame map variant. Move onto that tool's still-frame mode once it has one.
# Exit: 0 production ready, 1 not ready (defects printed), 3 gave up (items filed), 2 usage, 4 software renderer or no
#   frames, 5 the judge wrote no valid verdict.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
root=$(pwd -L)
map= out= model=${MAP_JUDGE_MODEL:-opus} max_rounds=${MAP_JUDGE_MAX_ROUNDS:-0} fix= give_up=0 capture=1 views= repos=game-playlot,dot-map-convert,playlot-maps
while (($#)); do
  case $1 in
    --map) map=$2; shift 2 ;;
    --out) out=$2; shift 2 ;;
    --model) model=$2; shift 2 ;;
    --max-rounds) max_rounds=$2; shift 2 ;;
    --fix-cmd) fix=$2; shift 2 ;;
    --give-up) give_up=1; shift ;;
    --no-capture) capture=0; shift ;;
    --views) views=$2; shift 2 ;;
    --repos) repos=$2; shift 2 ;;
    *) echo "map_judge.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done
die() { echo "map_judge.sh: $*" >&2; exit "${code:-2}"; }
[[ -n $map ]] || die "--map ID is required"
case $model in opus | sonnet | haiku) ;; *) die "--model must be opus, sonnet or haiku" ;; esac
[[ $max_rounds =~ ^[0-9]+$ ]] || die "--max-rounds must be a number (0 = unlimited)"
out=${out:-$root/screenshots/judge/$map}
mkdir -p "$out"
rubric=$root/docs/map-judge-rubric.md
[[ -f $rubric ]] || die "no docs/map-judge-rubric.md"
gpu=${GPU_SH:-$HOME/godot/dot-bootstrap/tools/gpu.sh}
nightly=${NIGHTLY:-/home/core/stack/nightly/bin/nightly}
run_nightly() { if [[ $(id -un) == core ]]; then "$nightly" "$@"; else sudo -u core "$nightly" "$@"; fi; }
judge_claude() {
  if [[ -n ${MAP_JUDGE_CLAUDE:-} ]]; then $MAP_JUDGE_CLAUDE "$@"; return; fi
  local cfg
  cfg=$(run_nightly account env 2> /dev/null | sed -n "s/^export CLAUDE_CONFIG_DIR='\\(.*\\)'$/\\1/p")
  if [[ $(id -un) == christian ]]; then CLAUDE_CONFIG_DIR=${cfg:-$HOME/.claude} /home/christian/.local/bin/claude "$@"
  elif [[ -n $cfg ]] && sudo -n -u christian true 2> /dev/null; then sudo -n -u christian env CLAUDE_CONFIG_DIR="$cfg" /home/christian/.local/bin/claude "$@"
  else claude "$@"; fi
}

round_file=$out/round
round=$(($(cat "$round_file" 2> /dev/null || echo 0) + 1))
while :; do
  echo "$round" > "$round_file"
  dir=$out/round_$round
  rm -rf "$dir"; mkdir -p "$dir"; chmod 777 "$dir"
  if ((capture)); then
    rm -f "$root"/screenshots/"$map".png "$root"/screenshots/"$map"_*.png
    args=(tools/screenshot.sh "$map")
    for v in $views; do args+=(--view "$v"); done
    # gpu.sh shot copies the worktree (symlinks followed: maps/custom and its .stores) to a GPU box and the PNGs back.
    "$gpu" shot "$root" "${args[@]}" > "$dir/capture.log" 2>&1 || { tail -20 "$dir/capture.log" >&2; die "capture failed (see $dir/capture.log)"; }
    if grep -qiE 'llvmpipe|softpipe|lavapipe|SwiftShader|software rasterizer' "$dir/capture.log"; then code=4 die "software rendering in $dir/capture.log: refused"; fi
    grep -qiE 'NVIDIA|Radeon|AMD|Intel\(R\)|Using Device' "$dir/capture.log" || { code=4 die "no GPU renderer named in $dir/capture.log: refused"; }
  fi
  shopt -s nullglob
  frames=("$root"/screenshots/"$map"[.]png "$root"/screenshots/"$map"_*.png)
  ((${#frames[@]})) || { code=4 die "no frames screenshots/${map}_*.png"; }
  cp "${frames[@]}" "$dir/"
  list=$(cd "$dir" && ls ./*.png | sed 's|^\./||' | tr '\n' ' ')
  prompt="You are a fresh judge with no context from the people who made this map. First read $rubric in full. Then read every frame in this folder ($list) with the Read tool, one by one, before you decide anything. Judge the converted Playlot map $map against the rubric only. Write ./verdict.json (in this folder) exactly in the rubric's verdict.json shape: subject \"playlot $map\", judge \"fresh claude -p, no author context\", every frame in frames with its findings, every defect with id, category, severity (blocker|major|minor), camera, frames, what, fix_hint and nightly \"\", categories_clean for every clean category, production_ready, justification. Default to not ready. Write nothing else."
  (cd "$dir" && judge_claude -p "$prompt" --model "$model" --allowedTools "Read,Write" --permission-mode acceptEdits \
    --add-dir "$(dirname "$rubric")" > "$dir/judge.log" 2>&1)
  verdict=$dir/verdict.json
  ready=$(python3 -I - "$verdict" << 'PY'
import json, sys
try:
    v = json.load(open(sys.argv[1]))
    assert isinstance(v.get("production_ready"), bool) and isinstance(v.get("defects"), list) and v.get("justification")
except Exception as e:
    print("invalid"); sys.exit(0)
bad = [d for d in v["defects"] if d.get("severity") in ("blocker", "major")]
if v["production_ready"] and bad:
    v["production_ready"] = False   # the rubric's rule wins over a careless flag
    json.dump(v, open(sys.argv[1], "w"), indent=1)
print("yes" if v["production_ready"] else "no")
for d in v["defects"]:
    print("  %s %-8s %-12s %s" % (d.get("id"), d.get("severity"), d.get("category"), d.get("what")), file=sys.stderr)
PY
)
  cp -f "$verdict" "$out/verdict.json" 2> /dev/null
  case $ready in
    invalid) code=5 die "round $round: the judge wrote no valid verdict ($dir/judge.log)" ;;
    yes) echo "map_judge.sh: $map production ready at round $round ($verdict)"; exit 0 ;;
  esac
  echo "map_judge.sh: $map not ready at round $round ($verdict)"
  if ((give_up)) || ((max_rounds > 0 && round >= max_rounds)); then
    python3 -I - "$verdict" "$map" "$repos" > "$dir/items.tsv" << 'PY'
import json, sys
v = json.load(open(sys.argv[1]))
for d in v["defects"]:
    if d.get("severity") in ("blocker", "major") and not d.get("nightly"):
        print("%s\t%s: %s %s: %s" % (d["id"], sys.argv[2], d.get("severity"), d.get("category"), d.get("what", "")[:150]))
PY
    while IFS=$'\t' read -r id title; do
      key=$(run_nightly add --title "$title" --kind issue --repos "$repos" --body "map judge verdict $verdict, defect $id" 2>&1 | grep -oE '[A-Za-z0-9_-]+-[0-9]+' | head -1)
      python3 -I - "$verdict" "$id" "$key" << 'PY'
import json, sys
p, i, k = sys.argv[1:4]
v = json.load(open(p))
for d in v["defects"]:
    if d["id"] == i:
        d["nightly"] = k
json.dump(v, open(p, "w"), indent=1)
PY
      echo "map_judge.sh: filed $key for $id"
    done < "$dir/items.tsv"
    cp -f "$verdict" "$out/verdict.json"
    exit 3
  fi
  [[ -n $fix ]] || exit 1
  VERDICT=$verdict bash -c "$fix" || die "the fix command failed"
  round=$((round + 1))
done
