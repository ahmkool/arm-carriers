"""Builds world_local_02_medieval.tscn: world_local_02.tscn reskinned as a moated castle, with the same gameplay.

The level is derived from the original file each time, so floor cells, navmesh, enemies, checkpoints, triggers and
events stay the same. Only these change (see medieval.py):
  - both GridMaps use castle_tiles.tres (same item ids, castle stone and green grass; see build_castle_tiles.gd),
  - the lighting, fog and water colour (the sky panorama stays),
  - the music,
  - a new Level/Medieval node of props with no collision, placed by hand below: curtain walls and towers across the
    moat, a gatehouse where the (unused) bridge points, banners and torches on the walls, boats, reeds and lily pads.
It also writes the prop scenes into src/world/elements/medieval/.

Run from the project root (it refuses to overwrite the level without --force):
  PYTHONDONTWRITEBYTECODE=1 python3 tools/level_gen/build_medieval_02.py [--force]
Then check it with:
  tools/level_gen/godot.sh test tools/level_gen/verify_medieval_keep.gd res://src/world/levels/world_local_02_medieval.tscn /tmp/medieval_shots
"""

import sys

from medieval import (CLIFF_BANNER_SCALE, CLIFF_OUT, CLIFF_TOP_Y, CLIFF_TORCH_Y, WALL_BANNER_DROP, WALL_HEIGHT, WALL_TORCH_DROP,
                      Decoration, Reskin, heraldry_params, transform, wall_segments, write_props)

SOURCE = "src/world/levels/world_local_02.tscn"
OUT = "src/world/levels/world_local_02_medieval.tscn"
WATER_Y = -5.0
WALL_TOP_Y = WATER_Y + WALL_HEIGHT

# ---------------------------------------------------------------- layout (world coordinates)
# Floor top is y = 0 and the moat surface y = -5. Floor edges (from world_local_02's cells):
#   courtyard x -18..9, z -6..18 (a notch to z -9 at x -16.5..-10.5); bailey x -48..-27, z -15..3;
#   causeway x -36..-18, z 3..12 (and to z 15 at x -27..-18). The camera looks steeply down from the south,
#   so tall pieces go north, east and west of the play space; south of it, only low things sit on the water.
#   (A tower south-east of the courtyard filled a quarter of the screen from the courtyard's south edge.)

TOWERS = [
    (17.0, -14.0), (17.0, 13.0), (-22.0, -14.0), (-22.0, -23.0),
    (-55.0, -23.0), (-55.0, 9.0), (-42.5, -23.0), (-32.5, -23.0),
]
# Straight wall runs between tower centres: (x0, z0, x1, z1). Segments stop short of the towers.
WALL_RUNS = [
    (-22.0, -14.0, 17.0, -14.0),
    (17.0, -14.0, 17.0, 13.0),
    (-22.0, -23.0, -22.0, -14.0),
    (-32.5, -23.0, -22.0, -23.0),
    (-55.0, -23.0, -42.5, -23.0),
    (-55.0, -23.0, -55.0, 9.0),
]
GATEHOUSE = (-37.5, -23.0)  # where the bridge that never rises points
# Banners on walls (x, z, facing yaw) hanging from the wall top, and on the floor's south cliffs (x, cell edge z).
WALL_BANNERS = [(-12.0, -13.2, 0), (-1.0, -13.2, 0), (8.5, -13.2, 0), (-50.0, -22.2, 0), (-27.0, -22.2, 0),
                (16.2, -3.0, -90), (16.2, 6.0, -90), (-54.2, -12.0, 90), (-54.2, -1.0, 90)]
CLIFF_BANNERS = [(-12.0, 18.0), (0.0, 18.0), (-31.5, 12.0), (-41.5, 3.0)]
WALL_TORCHES = [(-17.0, -13.2, 0), (-6.5, -13.2, 0), (4.0, -13.2, 0), (13.0, -13.2, 0), (-46.0, -22.2, 0),
                (-29.0, -22.2, 0), (16.2, -7.5, -90), (16.2, 1.5, -90), (16.2, 9.0, -90), (-54.2, -17.0, 90),
                (-54.2, -6.5, 90), (-54.2, 4.0, 90)]
CLIFF_TORCHES = [(-14.0, 18.0), (-10.0, 18.0), (-2.0, 18.0), (2.0, 18.0), (-33.5, 12.0), (-29.5, 12.0),
                 (-43.5, 3.0), (-39.5, 3.0)]
BOATS = [(-22.5, -3.0, 80), (13.0, 7.0, 10), (-41.0, 8.0, -20), (-6.0, 22.0, 5)]
REEDS = [(-51.5, -18.5), (-51.0, 5.5), (14.0, -10.5), (13.5, 19.5), (-25.0, -10.0), (-38.0, 9.5), (-20.0, 17.5),
         (8.0, 21.0)]
LILIES = [(-24.0, -7.0), (12.0, -4.0), (-51.0, -8.0), (-30.0, 15.5), (11.5, 13.0), (-45.0, 7.5), (-34.0, -18.0)]


def decoration(refs):
    d = Decoration(refs, ["Towers", "Walls", "Banners", "Torches", "Moat"])
    for index, (x, z) in enumerate(TOWERS):
        d.add("Towers", "tower", transform((x, WATER_Y, z), index * 23.0))
    d.add("Towers", "gatehouse", transform((GATEHOUSE[0], WATER_Y, GATEHOUSE[1])))
    for run in WALL_RUNS:
        for x, z, yaw, stretch in wall_segments(*run):
            d.add("Walls", "wall", transform((x, WATER_Y, z), yaw, (stretch, 1, 1)))
    for index, (x, z, yaw) in enumerate(WALL_BANNERS):
        d.add("Banners", "banner", transform((x, WALL_TOP_Y - WALL_BANNER_DROP, z), yaw), heraldry_params(index))
    for index, (x, z) in enumerate(CLIFF_BANNERS):
        d.add("Banners", "banner", transform((x, CLIFF_TOP_Y, z + CLIFF_OUT), 0.0, CLIFF_BANNER_SCALE), heraldry_params(index + 1))
    for x, z, yaw in WALL_TORCHES:
        d.add("Torches", "torch", transform((x, WALL_TOP_Y - WALL_TORCH_DROP, z), yaw))
    for x, z in CLIFF_TORCHES:
        d.add("Torches", "torch", transform((x, CLIFF_TORCH_Y, z + CLIFF_OUT)))
    for x, z, yaw in BOATS:
        d.add("Moat", "boat", transform((x, WATER_Y, z), yaw))
    for index, (x, z) in enumerate(REEDS):
        d.add("Moat", "reeds", transform((x, WATER_Y, z), index * 47.0))
    for index, (x, z) in enumerate(LILIES):
        d.add("Moat", "lilies", transform((x, WATER_Y, z), index * 61.0))
    return d


def main():
    force = "--force" in sys.argv[1:]
    write_props()
    level = Reskin(SOURCE)
    level.castle_tiles()
    level.castle_music()
    level.castle_arrow_colors()
    level.castle_environment()
    level.castle_light()
    level.moat()
    level.add_props()
    level.insert_decoration(decoration(level.refs))
    level.write(OUT, force)


if __name__ == "__main__":
    main()
