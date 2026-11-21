# Converted map judge rubric

A fresh judge reads this before it looks at any frame of a converted Playlot map (a Source BSP brought over by
gs-map-convert). It answers one question: **would a player who loads this map in a modern shooter or sandbox
(CS:S, Garry's Mod, CS2) notice something wrong?** The default answer is **no, not ready**. `production_ready: true` must be
earned by the frames. A metric that passes, an author's note or "it is better than before" earns nothing.

The frames are GPU renders (Forward+ on Vulkan) of the map as a client draws it: overviews from above, then eye-level
views (about 1.7 m up) at the spawn and around the map. Judge what is in the frames, not what the map is meant to be.

## Categories (each gets a line in `categories_clean` or a defect)

- **ground**: no holes in the floor, no sky or void showing through the ground, no terrain missing under a road or
  building, nothing that would let a player fall out of the world. Buildings stand on the ground and do not float.
- **proportion**: every prop is the right size against a door (about 2 m), a person and the buildings beside it.
  A fence, rail, lamp, window, crate, car or tree that is several times too big or too small is a defect. So is a
  prop drawn with the wrong proportions (a window as a thick block, a door as a cube).
- **blobs**: large plain grey or single-colour blocks standing where the map clearly had a detailed model (a
  vehicle, a pile of junk, a fire escape, a statue) are defects: a player reads them as broken. A small neutral crate
  or block that reads as a crate or block is fine. Count roughly how many and say where.
- **placement**: props float, sink into the floor, poke through walls, or sit turned the wrong way (a bench facing a wall,
  a car on its side).
- **texture**: no missing-texture checkerboards, pink/black, stretched or smeared textures, or walls of one flat
  colour where the map had detail. Tiling should be at a believable scale.
- **lighting**: the map is readable: not black, not blown out, shadows plausible, no light leaking through walls in
  large patches.
- **sky**: a sky is drawn, the 3D skybox (distant buildings, hills) sits on the horizon and is not a giant model
  floating over the playable area.
- **completeness**: no missing walls, roofs, or whole buildings, no see-through faces where geometry should be.

Severity: `blocker` means it cannot ship (a hole a player falls through, a giant blob in a main street, half the
map black), `major` means a player notices (a 10x fence, a row of grey boxes along a road, a floating house),
`minor` means polish. `production_ready` is true only when there are **no blocker or major defects in any frame**.
The justification must say why each category is clean, citing frames. A verdict that is true with a thin
justification is wrong.

## verdict.json

The same shape as gs-game's visual judge (docs/visual-judge-rubric.md there), with frames instead of cameras:

```json
{
  "subject": "playlot pgc_fork",
  "judge": "fresh claude -p, no author context",
  "cameras": ["overview", "eye"],
  "frames": [{"file": "pgc_fork_overview.png", "camera": "overview", "findings": "..."}],
  "defects": [{"id": "D1", "category": "proportion", "severity": "major", "camera": "eye",
               "frames": ["pgc_fork_eye_2.png"], "what": "chain-link fence about 4x a door's height along the road",
               "fix_hint": "fence stand-in size", "nightly": ""}],
  "categories_clean": {"ground": "frames 1-6: road and grass continuous, no void"},
  "production_ready": false,
  "justification": "D1 is major: ..."
}
```

`nightly` is filled by the loop (tools/map_judge.sh) when it files an item for an unresolved defect.
