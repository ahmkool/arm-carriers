#!/usr/bin/env python3
"""A second space level, in the same biome as world_local_space_station.tscn: world_local_space_station_2.tscn.
Played with the pulse rifle. Being built section by section.

1. The warm-up. Nine robots stand idle on the starting deck, in three packs. Each pack is two plain robots and one
   with a shield bubble, standing about 4 m from its pair so it is plain which bolts bounce: shots at the pair land,
   shots at the bubble come straight back. The robots never wake. The bubbles force the VENT prompt, since venting
   up close is the only way to pop them. Clearing all nine sets Checkpoint2 and projects a hard-light bridge north.
2. The hold. Stepping onto deck 2 switches the bridge off behind the carriers and starts 60 s of robots that run at
   them, one every 3 s, while four shielded robot gunners, one in each corner, open fire from long range. The gunners
   hold their corners: hits don't move them, and only a vent up close pops their bubbles. Once the wave is over and
   all four gunners are down (`GroupsDefeatedGate`), Checkpoint3 is set and a bridge projects north.
3. The gunner island. Bridge 2 lands on a deck split in two: the carriers' half, and across a 6 m gap an island
   where four robot gunners stand behind three flat shields, on its west, east and south sides. Bolts and vents
   from those sides bounce off the shields, while the gunners' shots pass through them. The only way round is a
   one-cell-wide S-shaped walkway out over the void on the west, which leads to a ledge behind (north of) the
   island, where the gunners are open. A wrong step falls off. Stepping onto the deck switches bridge 2 off, frames
   the island, and starts 40 s of robots that run at the carriers, one every 3 s, onto the walkway too. Once the
   wave is over and all four gunners are down, Checkpoint4 is set on the ledge and a bridge projects east from it.
4. The bank shot. A bridge east from the ledge lands on deck 4. Across a 6 m gap to its south, four robot gunners
   stand on an island behind a flat cover shield (with a short return at its east end), so no bolt can reach them
   straight. East of them, on the carriers' right, a flat shield stands at 45 degrees: a bolt fired south at it
   turns 90 degrees and runs west along a row of gunners. Where along the bank it lands picks the row, so the
   carriers strafe to reach both. Landing frames the island and wakes the gunners; once all four are down,
   Checkpoint5 is set and a bridge projects east.
5. The crossfire. Deck 5 has the same island to its south and another to its north: the south island turned 180
   degrees about the deck's centre, so its bank stands on the carriers' left (west). The carriers have to turn round
   to bank shots both ways while both islands fire at them. Once all eight gunners are down, Checkpoint6 is set and
   a bridge projects east.
6. Placeholder: the next deck, east of deck 5, with the end area, until the rest of the level is designed.

Run from the project root; see docs/level-creation-for-agents.md.
"""
import math
import sys

from levelgen import AREAS, BRIDGE_Y, EVENTS, GROUPS, TRIGGER as T, Level, node_paths, rect, single_bridge, tf, world

T3, T4, T5 = T + "3", T + "4", T + "5"
CELL = 2.999
FLOOR_TOP_Y = -1.0  # the decks' top: flat shields stand here
SHIELD_HEIGHT = 3.0
SHIELD_INSET = 0.3  # how far inside an island's edge a shield along it stands


def rounded(x0, x1, z0, z1):
    """A rectangle with its corners cut."""
    return rect(x0, x1, z0, z1) - {(x0, z0), (x0, z1), (x1, z0), (x1, z1)}


# ---- Layout, in grid cells. Forward is -z, east is +x. ----
START = rounded(-5, 5, -8, 5)  # the warm-up deck; the carriers spawn at its south end
DECK2 = rounded(-5, 5, -22, -11)  # the hold
# Section 3: the carriers' half of the split deck, the gunner island across the gap, the S walkway round its west
# side, and the ledge behind the island where the walkway ends.
LANDING = rounded(-5, 5, -29, -25)
GUNNER_ISLAND = rect(-2, 2, -36, -32)
WALKWAY = [(-4, -30), (-4, -31), (-5, -31), (-6, -31), (-7, -31), (-7, -32), (-7, -33), (-7, -34), (-6, -34),
           (-5, -34), (-5, -35), (-5, -36), (-5, -37)]  # in walking order: north, west, north, east, north
LEDGE = rect(-5, 3, -40, -38)


# Sections 4 and 5: bank-shot islands. Section 4's island, south of deck 4, is the base geometry; section 5 shifts it
# one deck east and adds its 180-degree turn about deck 5's centre to the north.
def west_edge(cx):
    return cx * CELL + 1.5 - CELL / 2


def east_edge(cx):
    return cx * CELL + 1.5 + CELL / 2


def north_edge(cz):
    return cz * CELL + 1.5 - CELL / 2


DECK4 = rect(6, 11, -42, -38)
COVER_Z = north_edge(-35) + SHIELD_INSET
BANK_BASE = {
    "island": rect(5, 12, -35, -32),
    "gunners": [(6, -34), (7, -34), (6, -33), (7, -33)],
    # (name, world (x, z) centre, length, angle): each pane runs along its local x, turned `angle` degrees about y,
    # so its normal is (sin, 0, cos). The cover faces the deck; the return closes the gap at its east end down to
    # the gunners' first row, so no diagonal from the deck slips round it; the bank turns bolts west along the rows.
    "shields": [
        ("Cover", ((west_edge(5) + east_edge(9)) / 2, COVER_Z), east_edge(9) - west_edge(5), 0),
        ("Return", (east_edge(9), (COVER_Z + north_edge(-34)) / 2), north_edge(-34) - COVER_Z, 90),
        ("Bank", world(10.5, -33.5), 7.0, 45),
    ],
}


def shifted(geometry, dx, dz=0):
    """The bank island moved `dx` cells east and `dz` cells south."""
    return {"island": {(x + dx, z + dz) for x, z in geometry["island"]},
            "gunners": [(x + dx, z + dz) for x, z in geometry["gunners"]],
            "shields": [(n, (x + dx * CELL, z + dz * CELL), length, angle) for n, (x, z), length, angle in geometry["shields"]]}


def turned(geometry, centre):
    """The bank island turned 180 degrees about the cell `centre`."""
    cx, cz = centre
    wx, wz = world(cx, cz)
    return {"island": {(round(2 * cx - x), round(2 * cz - z)) for x, z in geometry["island"]},
            "gunners": [(round(2 * cx - x), round(2 * cz - z)) for x, z in geometry["gunners"]],
            "shields": [(n, (2 * wx - x, 2 * wz - z), length, (angle + 180) % 180) for n, (x, z), length, angle in geometry["shields"]]}


# Deck 5 is three rows deep and its south island sits a row closer than deck 4's, so the two islands' gunners span
# 33 m: at five rows, with the same 6 m gaps, they spanned 42 m and the framing couldn't zoom out far enough to show
# either island.
DECK5 = rect(15, 20, -41, -39)
BANK4 = BANK_BASE
CROSSFIRE_SOUTH = shifted(BANK_BASE, 9, -1)
CROSSFIRE_NORTH = turned(CROSSFIRE_SOUTH, (17.5, -40))
DECK6 = rect(23, 28, -42, -38)  # placeholder for the next section, east of deck 5
BANK_ISLANDS = [BANK4["island"], CROSSFIRE_SOUTH["island"], CROSSFIRE_NORTH["island"]]
DECKS = [START, DECK2, LANDING, GUNNER_ISLAND, set(WALKWAY), LEDGE, DECK4, DECK5, DECK6] + BANK_ISLANDS
FLOOR = set().union(*DECKS)


def touches(a, b):
    """Whether any cell of `a` shares an edge with a cell of `b`."""
    return any((x + dx, z + dz) in b for x, z in a for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)))


# The walkway joins the carriers' half to the ledge and nothing else, and the island stands alone.
assert touches(LANDING, set(WALKWAY)) and touches(set(WALKWAY), LEDGE)
assert not touches(GUNNER_ISLAND, FLOOR - GUNNER_ISLAND), "the gunner island must stand alone"
assert not touches(LANDING, LEDGE | DECK4) and not touches(LEDGE, DECK4)
for island in BANK_ISLANDS:
    assert not touches(island, FLOOR - island), "each bank island must stand alone"
assert not touches(DECK4, DECK5) and not touches(DECK5, DECK6)
for (ax, az), (bx, bz) in zip(WALKWAY, WALKWAY[1:]):
    assert abs(ax - bx) + abs(az - bz) == 1, "the walkway must be one continuous line of cells"
for x, z in WALKWAY:  # one cell wide: each walkway cell touches only its neighbours along the walkway
    around = {(x + 1, z), (x - 1, z), (x, z + 1), (x, z - 1)} & (FLOOR - LANDING - LEDGE)
    assert len(around) <= 2, (x, z)

BRIDGES = {1: single_bridge(-9, -10), 2: single_bridge(-23, -24), 3: [(4, -39), (5, -39)],
           4: [(12, -40), (13, -40), (14, -40)], 5: [(21, -40), (22, -40)]}
EAST_WEST_BRIDGES = {3, 4, 5}  # turned a quarter: the hard-light surface stretches along its own z
assert all(cell not in FLOOR for cells in BRIDGES.values() for cell in cells)

# The warm-up packs: (pair centre, shielded robot), in cells. The pair stands side by side, 1.2 m apart; its shielded
# robot stands level with it, 1.5 cells to the side (about 3.9 m from the nearer of the pair), so a bolt bouncing
# straight back off the bubble misses the pair, and the other packs are further still. One row deep, about 5 m
# ahead of the carriers: the rifle's camera shows only about 6 m ahead, and from further back the bubbles' tops were
# cut off. The middle pack is fully on screen from the spawn, and the rifle starts pointing at its pair; the outer
# packs come fully into view as the carriers walk up to them.
PACKS = (
    ((-3.3, 1.2), (-4.8, 1.2)),
    ((0.0, 1.2), (1.5, 1.2)),
    ((3.3, 1.2), (4.8, 1.2)),
)
PAIR_OFFSETS = ((-0.2, 0.0), (0.2, 0.0))

# Props stand on a plate and block movement. (item, GridMap orientation: 0, 10, 16 or 22.) The rows the packs
# stand on (2 to 0) stay clear, so nothing hides them.
PROPS = {
    # Start deck: parked craft behind the spawn, cargo by the bridge, beacons either side of its landing.
    (-4, 4): ("Dropship", 16), (4, 4): ("Lander", 0), (-2, 5): ("Lights", 0), (2, 5): ("Lights", 0),
    (-4, -5): ("CargoA", 0), (4, -5): ("CargoB", 10), (-4, -7): ("Antenna", 0), (4, -7): ("StructureTall", 0),
    (-2, -8): ("Lights", 0), (2, -8): ("Lights", 0),
    # Deck 2: modules on the side edges and two cargo stacks for the chasers to come around, clear of the corners,
    # the spawns and both landings.
    (-5, -16): ("BaseModuleA", 0), (5, -16): ("BaseModuleC", 10), (-3, -17): ("CargoA", 0), (3, -17): ("CargoB", 10),
    (-2, -11): ("Lights", 0), (2, -11): ("Lights", 0), (-2, -22): ("Lights", 0), (2, -22): ("Lights", 0),
    # The carriers' half of deck 3: beacons by the landing.
    (-2, -25): ("Lights", 0), (2, -25): ("Lights", 0),
    # Decks 4 and 5: beacons on the rows away from the bank lanes (deck 4's south edge, deck 5's south edge to the
    # east and north edge to the west), so the carriers can line up on every lane.
    (7, -42): ("Lights", 0), (10, -42): ("Lights", 0), (15, -39): ("Lights", 0), (20, -41): ("Lights", 0),
    # Deck 6 (placeholder): a craft at the far side.
    (28, -40): ("Dropship", 16), (24, -38): ("Lights", 0), (24, -42): ("Lights", 0),
}
LANDINGS = {(0, -8), (0, -11), (0, -22), (0, -25), (3, -39), (6, -39), (11, -40), (15, -40), (20, -40), (23, -40)}
assert not set(PROPS) & LANDINGS, "keep the bridge landings clear"
assert set(PROPS) <= FLOOR, sorted(set(PROPS) - FLOOR)
PACK_ROWS = {cz for (_, cz) in PROPS if 0 <= cz <= 2}
assert not PACK_ROWS, "keep the warm-up rows clear"

# The hold. Gunners stand in deck 2's four corners (the cells beside the cut corners). From the middle of the deck
# each is about 20 m away, so all four reach it with a 22 m range; from one corner, the far ones can't.
GUNNERS = ((-5, -12), (5, -12), (-5, -21), (5, -21))
GUNNER_RANGE = 22.0
GUNNER_COOLDOWN = 3.5
SURVIVAL_SPAWNS = ((-2, -21), (2, -21), (-4, -19), (4, -19), (-4, -14), (4, -14))
SURVIVAL_SECONDS = 60
SURVIVAL_INTERVAL = 3.0
assert set(GUNNERS) <= DECK2 and set(SURVIVAL_SPAWNS) <= DECK2
assert not (set(GUNNERS) | set(SURVIVAL_SPAWNS)) & (set(PROPS) | LANDINGS), "keep spawns and gunners off props and landings"

# Section 3. The gunners stand in the island's middle rows. From the bridge landing they are 21 to 28 m away, so a
# 26 m range has the near two firing as soon as the carriers land, and all four once they step north.
ISLAND_GUNNERS = ((-1, -33), (1, -33), (-1, -35), (1, -35))
ISLAND_GUNNER_RANGE = 26.0
SURVIVAL2_SPAWNS = ((-4, -26), (4, -26), (4, -28), (2, -29), (-2, -28))
SURVIVAL2_SECONDS = 40
assert set(ISLAND_GUNNERS) <= GUNNER_ISLAND and set(SURVIVAL2_SPAWNS) <= LANDING
assert not set(SURVIVAL2_SPAWNS) & (set(PROPS) | LANDINGS)
# The flat shields stand on the deck 0.3 m inside the island's west, east and south edges and span its full length.
ISLAND_WEST = -2 * CELL + 1.5 - CELL / 2
ISLAND_EAST = 2 * CELL + 1.5 + CELL / 2
ISLAND_SOUTH = -32 * CELL + 1.5 + CELL / 2
ISLAND_NORTH = -36 * CELL + 1.5 - CELL / 2
FACE_EAST_WEST = "0, 0, 1, 0, 1, 0, -1, 0, 0"  # a quarter turn: the pane faces along x
ISLAND_SHIELDS = (
    ("WestShield", ISLAND_WEST + SHIELD_INSET, (ISLAND_SOUTH + ISLAND_NORTH) / 2, ISLAND_SOUTH - ISLAND_NORTH, FACE_EAST_WEST),
    ("EastShield", ISLAND_EAST - SHIELD_INSET, (ISLAND_SOUTH + ISLAND_NORTH) / 2, ISLAND_SOUTH - ISLAND_NORTH, FACE_EAST_WEST),
    ("SouthShield", (ISLAND_WEST + ISLAND_EAST) / 2, ISLAND_SOUTH - SHIELD_INSET, ISLAND_EAST - ISLAND_WEST, None),
)

# Sections 4 and 5. From deck 4 the gunners are 10 to 27 m away.
BANK_GUNNER_RANGE = 24.0
BANK_SECTIONS = (  # (group, geometry, the deck it is fought from)
    ("BankGunners", BANK4, DECK4),
    ("CrossfireSouth", CROSSFIRE_SOUTH, DECK5),
    ("CrossfireNorth", CROSSFIRE_NORTH, DECK5),
)


# ---- The bank geometry, checked in 2D: no straight line from where a muzzle can be reaches a gunner, and a bolt
# fired straight across the gap at the bank reaches each row of gunners from somewhere on the deck. ----
MUZZLE_REACH = 3.0  # the rifle reaches about this far beyond the carriers, so muzzles can hang over the gap
GUNNER_HALF_WIDTH = 0.5


def pane_ends(centre, length, angle):
    ax, az = math.cos(math.radians(angle)), -math.sin(math.radians(angle))
    (x, z), h = centre, length / 2
    return (x - ax * h, z - az * h), (x + ax * h, z + az * h)


def crosses(p, q, a, b):
    def side(o, u, v):
        return (u[0] - o[0]) * (v[1] - o[1]) - (u[1] - o[1]) * (v[0] - o[0])
    return (side(a, b, p) > 0) != (side(a, b, q) > 0) and (side(p, q, a) > 0) != (side(p, q, b) > 0)


def ray_to_segment(p, d, a, b):
    """Distance along the ray from `p` in direction `d` to segment a-b, or None."""
    ex, ez = b[0] - a[0], b[1] - a[1]
    den = d[0] * ez - d[1] * ex
    if abs(den) < 1e-9:
        return None
    t = ((a[0] - p[0]) * ez - (a[1] - p[1]) * ex) / den
    u = ((a[0] - p[0]) * d[1] - (a[1] - p[1]) * d[0]) / den
    return t if t > 1e-6 and 0.0 <= u <= 1.0 else None


def ray_to_circle(p, d, c, r):
    fx, fz = p[0] - c[0], p[1] - c[1]
    b = fx * d[0] + fz * d[1]
    disc = b * b - (fx * fx + fz * fz - r * r)
    if disc < 0:
        return None
    t = -b - math.sqrt(disc)
    return t if t > 1e-6 else None


def deck_bounds(deck):
    xs, zs = [x for x, _ in deck], [z for _, z in deck]
    return west_edge(min(xs)), east_edge(max(xs)), north_edge(min(zs)), north_edge(max(zs)) + CELL


def check_no_straight_shot(deck, geometry):
    x0, x1, z0, z1 = deck_bounds(deck)
    panes = [pane_ends(c, length, angle) for _, c, length, angle in geometry["shields"]]
    steps_x, steps_z = int((x1 - x0 + 2 * MUZZLE_REACH) / 0.5), int((z1 - z0 + 2 * MUZZLE_REACH) / 0.5)
    for i in range(steps_x + 1):
        for j in range(steps_z + 1):
            p = (x0 - MUZZLE_REACH + i * 0.5, z0 - MUZZLE_REACH + j * 0.5)
            for g in geometry["gunners"]:
                gx, gz = world(*g)
                for target in ((gx - GUNNER_HALF_WIDTH, gz), (gx, gz), (gx + GUNNER_HALF_WIDTH, gz)):
                    assert any(crosses(p, target, a, b) for a, b in panes), f"a straight shot from {p} reaches {g}"


def bank_rows_reached(deck, geometry):
    """The gunner rows a bolt fired straight across the gap at the bank reaches, from anywhere along the deck."""
    x0, x1, z0, z1 = deck_bounds(deck)
    island_z = world(*geometry["gunners"][0])[1]
    toward = 1.0 if island_z > z1 else -1.0
    start_z = z1 if toward > 0 else z0
    panes = {n: pane_ends(c, length, angle) for n, c, length, angle in geometry["shields"]}
    bank_angle = next(angle for n, _, _, angle in geometry["shields"] if n == "Bank")
    normal = (math.sin(math.radians(bank_angle)), math.cos(math.radians(bank_angle)))
    rows = set()
    x = x0 + 0.25
    while x < x1:
        p, d = (x, start_z), (0.0, toward)
        hits = {n: ray_to_segment(p, d, a, b) for n, (a, b) in panes.items()}
        hits = {n: t for n, t in hits.items() if t is not None}
        if hits and min(hits, key=hits.get) == "Bank":
            t = hits["Bank"]
            q = (p[0] + d[0] * t, p[1] + d[1] * t)
            dot = d[0] * normal[0] + d[1] * normal[1]
            r = (d[0] - 2 * dot * normal[0], d[1] - 2 * dot * normal[1])
            blocks = [ray_to_segment(q, r, a, b) for n, (a, b) in panes.items() if n != "Bank"]
            nearest_block = min([t for t in blocks if t is not None], default=math.inf)
            for g in geometry["gunners"]:
                t = ray_to_circle(q, r, world(*g), GUNNER_HALF_WIDTH)
                if t is not None and t < nearest_block:
                    rows.add(g[1])
        x += 0.25
    return rows


for _, geometry, deck in BANK_SECTIONS:
    assert set(geometry["gunners"]) <= geometry["island"]
    check_no_straight_shot(deck, geometry)
    assert bank_rows_reached(deck, geometry) == {z for _, z in geometry["gunners"]}, "a bank shot must reach every row"

level = Level("src/world/levels/world_local_space_station_2.tscn", palette="space", weapon="pulse_rifle", floor_seed=7,
              deco_seed=7, music="cyber_noir",
              hint="[color=#88ddff]Space Station II[/color]\n\nShields bounce your bolts straight back.\nGet close and VENT to pop them.")
level.use_space_station()
level.curve = (SURVIVAL_INTERVAL, SURVIVAL_INTERVAL)  # one robot every 3 s for the whole hold
level.boxes = {"fall": (400, 1, 400), "deck2": (27, 3, 6), "deck3": (27, 3, 6), "bankdeck": (6, 3, 15), "end": (9, 3, 9)}
level.extra_ext.append(("Script", None, "res://src/events/groups_defeated_gate.gd", "groups_gate"))
level.extra_ext.append(("PackedScene", None, "res://src/enemy/shield/flat_shield.tscn", "flat_shield"))
level.add_shell()
# Framings only. The camera zooms out 0.6 m per metre its focal points spread from their middle, up to this limit.
# The crossfire's framing corners stand a few cells past its two islands to zoom out about 19 m, which the default
# 14 m limit would cap, leaving the islands' far rows off the screen. Ordinary carrying never zooms out this far.
MAX_ZOOM_OUT = 20.0
rig_index = next(i for i, n in enumerate(level.nodes) if n.startswith('[node name="CameraFollowRig"'))
level.nodes[rig_index] += f"\nmax_zoom_out = {MAX_ZOOM_OUT:.1f}"

# ---- Enemies. ----
level.enemy_group("EnemyGroup")  # the warm-up: never woken
for pack, ((px, pz), (sx, sz)) in enumerate(PACKS, 1):
    for letter, (dx, dz) in zip("ab", PAIR_OFFSETS):
        level.melee("EnemyGroup", f"EnemyRobot{pack}{letter}", px + dx, pz + dz)
    level.melee("EnemyGroup", f"EnemyRobot{pack}Shielded", sx, sz, shielded=True, forces_vent_prompt=True)
level.survival_group(SURVIVAL_SPAWNS, duration=SURVIVAL_SECONDS)  # the hold's chasers
level.enemy_group("Gunners", spawn_on_trigger=True)  # the hold's corners
for index, (cx, cz) in enumerate(GUNNERS, 1):
    level.mage("Gunners", f"EnemyRobotGunner{index}", cx, cz, cast_max=GUNNER_RANGE, cooldown=GUNNER_COOLDOWN,
               shielded=True, holds_position=True)
# Section 3: the second survival wave, on the carriers' half, at the same one robot every 3 s.
level.node("SurvivalEnemyGroup2", "Enemies", "Node3D", props={
    "script": 'ExtResource("survival_group")', "spawn_interval_curve": 'SubResource("Curve_survival")',
    "fight_duration": f"{SURVIVAL2_SECONDS:.1f}", "enemy_scene": 'ExtResource("robot")'})
level.node("Enemies", "Enemies/SurvivalEnemyGroup2", "Node3D")
level.node("SpawnPoints", "Enemies/SurvivalEnemyGroup2", "Node3D")
for index, (cx, cz) in enumerate(SURVIVAL2_SPAWNS, 1):
    sx, sz = world(cx, cz)
    level.node(f"Node3D{index}", "Enemies/SurvivalEnemyGroup2/SpawnPoints", "Node3D", props={"transform": tf(sx, 0, sz)})
level.enemy_group("IslandGunners", spawn_on_trigger=True)
for index, (cx, cz) in enumerate(ISLAND_GUNNERS, 1):
    level.mage("IslandGunners", f"EnemyRobotGunner{index}", cx, cz, cast_max=ISLAND_GUNNER_RANGE, cooldown=GUNNER_COOLDOWN,
               holds_position=True)
# Sections 4 and 5: the bank islands' gunners, unshielded but out of straight reach.
for group, geometry, _ in BANK_SECTIONS:
    level.enemy_group(group, spawn_on_trigger=True)
    for index, (cx, cz) in enumerate(geometry["gunners"], 1):
        level.mage(group, f"EnemyRobotGunner{index}", cx, cz, cast_max=BANK_GUNNER_RANGE, cooldown=GUNNER_COOLDOWN,
                   holds_position=True)


# ---- Checkpoints. Each one's arrays describe the world as it is once the previous fight is won. ----
def checkpoint(name, cx, cz, opened=(), reset=(), defeated=(), react=(), done=()):
    arrays = {}
    for key, prefix, names in (("events_completed", "../../Level/Events/", opened), ("enemy_groups_reset", "../../Enemies/", reset),
                               ("enemy_groups_defeated", "../../Enemies/", defeated), ("areas_to_reactivate", "../../Level/Areas/", react),
                               ("areas_already_activated", "../../Level/Areas/", done)):
        if names:
            arrays[key] = [prefix + n for n in names]
    return (name, cx, cz, arrays)


# Checkpoints stand outside the deck triggers, so walking onto a deck still starts its fight after a respawn.
# Checkpoint4 is on the ledge behind the gunner island, where the carriers end that fight.
SECTION1 = ["EnemyGroup"]
SECTION2 = ["SurvivalEnemyGroup", "Gunners"]
SECTION3 = ["SurvivalEnemyGroup2", "IslandGunners"]
SECTION4 = ["BankGunners"]
SECTION5 = ["CrossfireSouth", "CrossfireNorth"]
level.checkpoints([
    checkpoint("Checkpoint", 0, 3, react=[T]),
    checkpoint("Checkpoint2", 0, -6, ["OpenBridge1"], SECTION2, SECTION1, [T]),
    checkpoint("Checkpoint3", 0, -19, ["CloseBridge1", "OpenBridge2"], SECTION3, SECTION1 + SECTION2, [T3], [T]),
    checkpoint("Checkpoint4", 0, -39, ["CloseBridge1", "CloseBridge2", "OpenBridge3"], SECTION4, SECTION1 + SECTION2 + SECTION3,
               [T4], [T, T3]),
    checkpoint("Checkpoint5", 10, -40, ["CloseBridge1", "CloseBridge2", "CloseBridge3", "OpenBridge4"], SECTION5,
               SECTION1 + SECTION2 + SECTION3 + SECTION4, [T5], [T, T3, T4]),
    checkpoint("Checkpoint6", 19, -40, ["CloseBridge1", "CloseBridge2", "CloseBridge3", "CloseBridge4", "OpenBridge5"], [],
               SECTION1 + SECTION2 + SECTION3 + SECTION4 + SECTION5, [], [T, T3, T4, T5]),
], setter_marker=(0, -0.5082588), shooter_marker=(0, 2.1002235))

# ---- Terrain and scenery. ----
level.add_station_terrain(DECKS, PROPS, fall_z=-60)
level.node("Shields", "Level", "Node3D")
for name, sx, sz, width, basis in ISLAND_SHIELDS:
    transform = tf(sx, FLOOR_TOP_Y, sz, basis) if basis else tf(sx, FLOOR_TOP_Y, sz)
    level.node(name, "Level/Shields", instance="flat_shield", props={
        "transform": transform, "size": f"Vector2({width:.3f}, {SHIELD_HEIGHT:.1f})"})


def turn_basis(angle):
    c, s_ = math.cos(math.radians(angle)), math.sin(math.radians(angle))
    return ", ".join(f"{v:.8g}" for v in (c, 0, s_, 0, 1, 0, -s_, 0, c))


for group, geometry, _ in BANK_SECTIONS:
    for name, (sx, sz), length, angle in geometry["shields"]:
        level.node(f"{group}{name}", "Level/Shields", instance="flat_shield", props={
            "transform": tf(sx, FLOOR_TOP_Y, sz, turn_basis(angle)), "size": f"Vector2({length:.3f}, {SHIELD_HEIGHT:.1f})"})
level.add_planet((-240, -480, -170), 280)
level.node("DistantStations", "Level", "Node")
for name, position, shape, props in (
        ("StationA", (58, -30, 2), rounded(-3, 3, -2, 2), {(0, 0): ("Dome", 0), (-2, 0): ("BaseModuleB", 0), (2, 0): ("SolarRoof", 0)}),
        ("StationB", (-64, -42, -36), rounded(-4, 4, -3, 3), {(0, 0): ("LandingPad", 0), (-3, 1): ("Garage", 0), (3, -1): ("EcoModule", 0)}),
        ("StationC", (70, -46, -84), rounded(-3, 4, -4, 3), {(1, 0): ("Command", 0), (-1, -2): ("StructureTall", 0), (2, 2): ("Antenna", 0)}),
):
    level.add_distant_station(name, position, shape, props)
level.add_asteroids((
    (42, -26, -6, 5), (-46, -32, -18, 7), (50, -40, -58, 9), (-36, -26, -70, 4), (-24, -58, -34, 12), (30, -50, -110, 10),
))

# ---- Events. ----
def offensive(name, group, next_event=None):
    props = {"script": 'ExtResource("change_behavior")', "enemy_group": f'NodePath("../../../Enemies/{group}")'}
    paths = ["enemy_group"]
    if next_event:
        props["next_event"] = f'NodePath("../{next_event}")'
        paths.append("next_event")
    level.node(name, "Level/Events", "Node", paths=paths, props=props)


level.set_bridges(BRIDGES)
level.bridge_event("OpenBridge1", 1)
level.bridge_event("CloseBridge1", 1, True, "StartSurvival")
offensive("StartSurvival", "SurvivalEnemyGroup", "MakeGunnersOffensive")
offensive("MakeGunnersOffensive", "Gunners")
level.node("HoldCleared", "Level/Events", "Node", paths=["next_event", "groups", "checkpoint"], props={
    "script": 'ExtResource("groups_gate")', "next_event": 'NodePath("../OpenBridge2")',
    "groups": node_paths(["../../../Enemies/SurvivalEnemyGroup", "../../../Enemies/Gunners"]),
    "checkpoint": 'NodePath("../../../CheckpointManager/Checkpoint3")'})
level.bridge_event("OpenBridge2", 2)
level.bridge_event("CloseBridge2", 2, True, "StartSurvival2")
offensive("StartSurvival2", "SurvivalEnemyGroup2", "MakeIslandGunnersOffensive")
offensive("MakeIslandGunnersOffensive", "IslandGunners")
CORNERS = ("SW", "SE", "NW", "NE")
# The gunners stand where the carriers can't walk, so their island is framed while the fight lasts. The crossfire's
# corners reach past its islands on purpose (see MAX_ZOOM_OUT). The framing runs
# from the landing to the ledge and over the walkway: framing the island alone left the carriers cut off at the
# bottom of the screen on the landing, and at the top on the ledge.
level.add_focus({"GunnerIsland": (-7, 2, -27, -39), "BankIsland": (5, 12, -32, -42), "Crossfire": (12, 23, -31, -49)})
level.node("IslandCleared", "Level/Events", "Node", paths=["next_event", "groups", "checkpoint", "also_trigger"], props={
    "script": 'ExtResource("groups_gate")', "next_event": 'NodePath("../OpenBridge3")',
    "groups": node_paths(["../../../Enemies/" + g for g in SECTION3]),
    "checkpoint": 'NodePath("../../../CheckpointManager/Checkpoint4")',
    "also_trigger": node_paths(["../UnfocusCamera"])})
level.bridge_event("OpenBridge3", 3)
level.bridge_event("CloseBridge3", 3, True, "MakeBankGunnersOffensive")
offensive("MakeBankGunnersOffensive", "BankGunners")
level.node("BankCleared", "Level/Events", "Node", paths=["next_event", "groups", "checkpoint", "also_trigger"], props={
    "script": 'ExtResource("groups_gate")', "next_event": 'NodePath("../OpenBridge4")',
    "groups": node_paths(["../../../Enemies/" + g for g in SECTION4]),
    "checkpoint": 'NodePath("../../../CheckpointManager/Checkpoint5")',
    "also_trigger": node_paths(["../UnfocusCamera"])})
level.bridge_event("OpenBridge4", 4)
level.bridge_event("CloseBridge4", 4, True, "MakeCrossfireSouthOffensive")
offensive("MakeCrossfireSouthOffensive", "CrossfireSouth", "MakeCrossfireNorthOffensive")
offensive("MakeCrossfireNorthOffensive", "CrossfireNorth")
level.node("CrossfireCleared", "Level/Events", "Node", paths=["next_event", "groups", "checkpoint", "also_trigger"], props={
    "script": 'ExtResource("groups_gate")', "next_event": 'NodePath("../OpenBridge5")',
    "groups": node_paths(["../../../Enemies/" + g for g in SECTION5]),
    "checkpoint": 'NodePath("../../../CheckpointManager/Checkpoint6")',
    "also_trigger": node_paths(["../UnfocusCamera"])})
level.bridge_event("OpenBridge5", 5)
level.node("LevelSucceeded", "Level/Events", "Node", props={"script": 'ExtResource("finished")'})
level.add_end_area(26, -40)
level.add_bridge_nodes()
for number in EAST_WEST_BRIDGES:
    for name, (cx, cz) in zip(level.platforms[number], BRIDGES[number]):
        bx, bz = world(cx, cz)
        head = f'[node name="{name}" parent="Level/Bridges" instance=ExtResource("bridge")]'
        index = next(i for i, n in enumerate(level.nodes) if n.startswith(head))
        level.nodes[index] = head + "\ntransform = " + tf(bx, BRIDGE_Y, bz, FACE_EAST_WEST)
level.add_triggers(((T, 0, -13, "deck2"), (T3, 0, -26, "deck3"), (T4, 8, -40, "bankdeck"), (T5, 17, -40, "bankdeck")))
wx, wz = world(0, 3)
level.add_weapon("PulseRifle", tf(wx, 0.593, wz))
level.add_audio_and_hint()

# ---- Signals. ----
level.connect("enemies_defeated", GROUPS + "EnemyGroup", "CheckpointManager/Checkpoint2", "_trigger_checkpoint")
level.connect("enemies_defeated", GROUPS + "EnemyGroup", EVENTS + "OpenBridge1")
level.connect("all_players_inside", AREAS + T, EVENTS + "CloseBridge1")
level.connect("enemies_defeated", GROUPS + "SurvivalEnemyGroup", EVENTS + "HoldCleared")
level.connect("enemies_defeated", GROUPS + "Gunners", EVENTS + "HoldCleared")
level.connect("all_players_inside", AREAS + T3, EVENTS + "CloseBridge2")
for corner in CORNERS:
    level.connect("all_players_inside", AREAS + T3, EVENTS + f"FocusGunnerIsland{corner}")
for group in SECTION3:
    level.connect("enemies_defeated", GROUPS + group, EVENTS + "IslandCleared")
for trigger, close, focus, groups, gate in ((T4, "CloseBridge3", "BankIsland", SECTION4, "BankCleared"),
                                            (T5, "CloseBridge4", "Crossfire", SECTION5, "CrossfireCleared")):
    level.connect("all_players_inside", AREAS + trigger, EVENTS + close)
    for corner in CORNERS:
        level.connect("all_players_inside", AREAS + trigger, EVENTS + f"Focus{focus}{corner}")
    for group in groups:
        level.connect("enemies_defeated", GROUPS + group, EVENTS + gate)
level.connect("all_players_inside", "Level/EndLevelArea", EVENTS + "LevelSucceeded")

level.write(sys.argv[1:])
