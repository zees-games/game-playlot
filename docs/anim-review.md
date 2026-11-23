# Animation review

PLAYLOT's visual QA loop for the zee weapons and the avatar, adopted from Fatal Contact's. It is game-local until gs-game's shared version lands (nightly gs-game-visual-qa-1); then these tools become thin wrappers around it.

## Run it

    tools/anim_review.sh                                  # first weapon of each pose, every clip, 60 fps
    tools/anim_review.sh --only sniper,smg --anims idle,fire
    tools/anim_review.sh --anims avatar_walk              # the avatar only
    tools/anim_review.sh --fps 30                         # at least 15

`anim_review.sh` sends the capture to a GPU box through `gpu.sh shot --route`. If no box takes it, the capture is queued here behind `heavy`. `tools/anim_review_shot.sh` is the half that runs on the box: Godot under xvfb with `--fixed-fps`, then ffmpeg.

Output goes to `screenshots/anim_review/<weapon>/`:

- `<clip>.mp4`: three views side by side at the capture fps, with the frame index burnt in:
  - first person (the game's own camera, view model and view arms);
  - behind-right third person;
  - an opponent's view from the front side.
- `<clip>_{fp,tp,op}_sheet.png`: one contact sheet per view, 15 cells per second of clip. Read
  these first; they cost far fewer tokens than the clip.
- `report.md`: one row per weapon and clip, with a verdict and the measured numbers.

## What it checks

The harness fails a clip on:

- a view-model jump between frames (`fire` allows its kick);
- the firing or support hand off its grip for too long (melee, thrown and fists are exempt);
- no view model for too long (`draw` is exempt);
- a third-person bone turning faster than `bone_pop` allows (gs-core's `GSClipMetrics`).

The numbers do not cover everything. Look at the sheets for:

- clipping arms;
- floating hands;
- finger grip;
- muzzle origin;
- T-pose;
- texture stretching;
- pops.

## Post it

    nightly review new "PLAYLOT animation review" --key <key>
    tools/anim_review_post.sh <key> --variant before --dir <old run>
    tools/anim_review_post.sh <key> --variant after

Each clip is posted with its verdict and metrics; the report's reason goes in as the thing to look at.

## Arguments

The harness takes `--key=value` arguments only. The map drop intake (GSMapDropIntake) treats any bare argument that names an existing folder, such as the output folder, as a map dropped on the window.
