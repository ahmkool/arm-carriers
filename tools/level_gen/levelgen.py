"""Writes Arm Carriers level scenes (.tscn) from a small Python description.

See docs/level-creation-for-agents.md for the workflow, and
example_saw_gauntlet.py for a complete level.
"""
import json
import random
import re
import sys
from pathlib import Path

CELL = 2.999
BRIDGE_Y = -3.9927697
CHECKPOINT_Y = 1.8026123
FACE_SOUTH = "-1, 0, 8.742278e-08, 0, 1, 0, -8.742278e-08, 0, -1"

# Orientations decoded from world_local_level_2.tscn. Directions: N = -z, S = +z, W = -x, E = +x.
TOP_SIDE_A = {"N": 16, "W": 10, "E": 0, "S": 22}  # Hill_Top_F_Side
TOP_SIDE_B = {"N": 10, "W": 22, "E": 16, "S": 0}  # Hill_Top_H_Side
TOP_CORNER = {"NW": 22, "NE": 10, "SW": 0, "SE": 16}  # Hill_Top_G_OuterCorner / InnerCorner
CLIFF_SIDE = {"N": 10, "W": 22, "E": 16, "S": 0}  # Hill_Cliff_Tall_H_Side
CLIFF_CORNER = {"NW": 10, "NE": 16, "SW": 22, "SE": 0}  # Hill_Cliff_Tall_I_OuterCorner / InnerCorner

LIBRARIES = {
    1: ("assets/mesh_library/tiles_Color1_no_shadows.tres", "uid://denn6v2rnn43l"),  # green
    6: ("assets/mesh_library/tiles_Color6_no_shadows.tres", "uid://nskho8hh0n1l"),  # orange
    7: ("assets/mesh_library/tiles_Color7_no_shadows.tres", "uid://ck1qun6nlwpwr"),  # pink
    "dungeon": ("src/world/elements/dungeon/dungeon_tiles.tres", None),  # stone
    "lava": ("src/world/elements/lava/lava_tiles.tres", None),  # basalt; built by build_lava_tiles.gd
    "decks": ("src/world/elements/sky_decks/deck_tiles.tres", None),  # planks
    "space": ("src/world/elements/space/space_tiles.tres", None),  # station plating; built by build_space_tiles.gd
}
WEAPONS = {
    "bazooka": ("uid://cq5v348mrgy7q", "res://src/weapon/bazooka.tscn"),
    "sword": ("uid://bgdgrubg87row", "res://src/weapon/sword.tscn"),
    "saw": ("uid://lilxckjevvd5", "res://src/weapon/saw.tscn"),
    "pulse_rifle": ("uid://o1x22yp71o80", "res://src/weapon/pulse_rifle.tscn"),
}
## PeriTune tracks (peritune.com): free for games, but the audio files themselves must not be redistributed.
MUSIC = {
    "amenoshita": ("uid://bp1ug7cyuchid", "res://assets/music/PerituneMaterial_Amenoshita.mp3"),
    "entangle": ("uid://buw0c1srev4kl", "res://assets/music/PerituneMaterial_Entangle.mp3"),
    "dark_fairies": ("uid://da7v13g67if2i", "res://assets/music/Peritune_Dark_Fairies.mp3"),
    "rituale_machina": ("uid://bsytwijbvocyp", "res://assets/music/PeriTune_Rituale_Machina.mp3"),
    "relentless": ("uid://dgwtoe0amw7rc", "res://assets/music/PeriTune_Relentless.mp3"),
    "ticking_labyrinth": ("uid://dxb245ts7cdnt", "res://assets/music/PeriTune_Ticking_Labyrinth.mp3"),
    "rising_tension": ("uid://bkee2kcxygr38", "res://assets/music/PeriTune_Rising_Tension.mp3"),
    "overworld_orchestra": ("uid://duaul8r11ug66", "res://assets/music/PerituneMaterial_OverWorld_Orchestra.mp3"),
    "cyber_noir": ("uid://etr5pc8rj0ge", "res://assets/music/PerituneMaterial_Cyber_Noir.mp3"),
}
TRIGGER = "AllPlayersAreaTrigger"
EVENTS = "Level/Events/"
AREAS = "Level/Areas/"
GROUPS = "Enemies/"


ENVIRONMENT_SKY = """background_mode = 2
sky = SubResource("Sky_level")
ambient_light_sky_contribution = 0.4
ambient_light_energy = 0.3"""
ENVIRONMENT_DARK = """background_mode = 1
background_color = Color(0, 0, 0, 1)
sky = SubResource("Sky_level")
reflected_light_source = 2
ambient_light_source = 2
ambient_light_color = Color(0.32, 0.38, 0.6, 1)
ambient_light_energy = 0.32
tonemap_mode = 3
glow_enabled = true
glow_intensity = 0.7
glow_bloom = 0.05"""
ENVIRONMENT_LAVA = """background_mode = 2
sky = SubResource("Sky_level")
ambient_light_source = 2
ambient_light_color = Color(0.72, 0.66, 0.68, 1)
ambient_light_energy = 0.5
tonemap_mode = 3
glow_enabled = true
glow_intensity = 0.45
glow_bloom = 0.04
glow_hdr_threshold = 1.1"""
ENVIRONMENT_SPACE = """background_mode = 2
sky = SubResource("Sky_level")
reflected_light_source = 2
ambient_light_source = 2
ambient_light_color = Color(0.42, 0.48, 0.66, 1)
ambient_light_energy = 0.55
tonemap_mode = 3
glow_enabled = true
glow_intensity = 0.6
glow_bloom = 0.04
glow_hdr_threshold = 1.0"""
SKY_SPACE = """[sub_resource type="ShaderMaterial" id="PanoramaSkyMaterial_sky"]
shader = ExtResource("space_sky")"""
SKY_PANORAMA = """[sub_resource type="PanoramaSkyMaterial" id="PanoramaSkyMaterial_sky"]
panorama = ExtResource("sky")"""
SKY_ASH = """[sub_resource type="ProceduralSkyMaterial" id="PanoramaSkyMaterial_sky"]
sky_top_color = Color(0.46, 0.34, 0.3, 1)
sky_horizon_color = Color(0.24, 0.1, 0.05, 1)
ground_horizon_color = Color(0.24, 0.1, 0.05, 1)
ground_bottom_color = Color(0.3, 0.13, 0.05, 1)"""
ROTOR_BASIS = {"E": "1, 0, 0, 0, 1, 0, 0, 0, 1", "W": "-1, 0, 0, 0, 1, 0, 0, 0, -1",
               "N": "0, 0, 1, 0, 1, 0, -1, 0, 0", "S": "0, 0, -1, 0, 1, 0, 1, 0, 0"}  # the arm points this way
LAVA_Y = -4.6  # lava_rock.gdshader's lava_y must match
LAVA_FALL_Y = -9.6  # puts the top of the kill box at the lava's surface


def rect(x0, x1, z0, z1):
    """All cells in an inclusive rectangle. Subtract one from another to cut pits."""
    return {(x, z) for x in range(x0, x1 + 1) for z in range(z0, z1 + 1)}


def world(cx, cz):
    """World x, z of a cell centre. The grid is offset: cell x = 0 is centred on world x = 1.5."""
    return (cx + 0.5) * CELL, (cz + 0.5) * CELL


def fmt(value):
    return repr(round(float(value), 4)).rstrip("0").rstrip(".")


def tf(x, y, z, basis="1, 0, 0, 0, 1, 0, 0, 0, 1"):
    return f"Transform3D({basis}, {fmt(x)}, {fmt(y)}, {fmt(z)})"


def node_paths(paths):
    return "[" + ", ".join(f'NodePath("{p}")' for p in paths) + "]"


def triple_bridge(z1, z2):
    """Three platforms wide (9 m): room for any weapon, side by side."""
    return [(x, z) for z in (z1, z2) for x in (-1, 0, 1)]


def double_bridge(z1, z2):
    """Two platforms wide with no gap (6 m): sword side by side."""
    return [(x, z) for x in (-0.5, 0.5) for z in (z1, z2)]


def twin_rails(z1, z2):
    """Two rails 6 m apart. Saw only: its 5.5 to 7 m carry distance keeps a player on each."""
    return [(x, z) for x in (-1, 1) for z in (z1, z2)]


def single_bridge(z1, z2, x=0):
    """One platform wide (3 m): single file, the bazooka levels' default."""
    return [(x, z) for z in (z1, z2)]


def _encode_cells(cells):
    def s32(value):
        return value - (1 << 32) if value >= (1 << 31) else value

    out = []
    for (x, y, z), (item, rot) in sorted(cells.items()):
        out += [s32((x & 0xFFFF) | ((y & 0xFFFF) << 16)), z & 0xFFFF, item | (rot << 16)]
    return ", ".join(map(str, out))


def _missing_sides(cell, floor):
    x, z = cell
    sides = (("N", (x, z - 1)), ("S", (x, z + 1)), ("W", (x - 1, z)), ("E", (x + 1, z)))
    missing = [name for name, neighbour in sides if neighbour not in floor]
    too_thin = {"N", "S"} <= set(missing) or {"W", "E"} <= set(missing)
    assert len(missing) <= 2 and not too_thin, f"floor must be at least 2 cells wide at {cell}"
    return missing


def _missing_diagonal(cell, floor):
    x, z = cell
    diagonals = {"NW": (x - 1, z - 1), "NE": (x + 1, z - 1), "SW": (x - 1, z + 1), "SE": (x + 1, z + 1)}
    for name, neighbour in diagonals.items():
        if neighbour not in floor:
            return name
    return None


class Level:
    """Collects a level's nodes, in the scene layout from docs/level-authoring.md."""

    def __init__(self, out, palette, weapon, deco_seed, floor_seed, hint=None, follow_offset=None, music="amenoshita"):
        self.out = out
        self.music = MUSIC[music]
        self.lib_path, self.lib_uid = LIBRARIES[palette]
        self.weapon = weapon
        self.floor_seed = floor_seed
        self.deco_seed = deco_seed
        self.hint = f'"{hint}"' if hint else None
        self.follow_offset = follow_offset
        self.nodes = []
        self.connections = []
        self.extra_ext = []
        self.environment = ENVIRONMENT_SKY
        self.has_sun = True
        self.sun_extra = {}
        self.sky_material = SKY_PANORAMA
        self.bridge_scene = ("uid://chaj7v8uajl4q", "res://src/world/elements/bridge_platform.tscn")
        self.boxes = {}
        self.curve = None
        self.platforms = {}
        self.melee_scene = "enemy"
        self.mage_scene = "mage"
        self.survival_scene = None  # the group's default (skeletons) unless set
        text = Path(self.lib_path).read_text()
        self.items = {re.sub(r"_Color\d+$", "", name): int(index)
                      for index, name in re.findall(r'^item/(\d+)/name = "([^"]+)"', text, re.M)}

    def node(self, name, parent=None, type_=None, instance=None, paths=None, props=None):
        head = f'[node name="{name}"'
        head += f' type="{type_}"' if type_ else ""
        head += f' parent="{parent}"' if parent is not None else ""
        if paths:
            head += " node_paths=PackedStringArray(" + ", ".join(f'"{p}"' for p in paths) + ")"
        head += f' instance=ExtResource("{instance}")' if instance else ""
        self.nodes.append("\n".join([head + "]"] + [f"{k} = {v}" for k, v in (props or {}).items()]))

    def connect(self, signal, source, target, method="trigger"):
        self.connections.append((signal, source, target, method))

    def add_shell(self):
        rig = {"transform": "Transform3D(1, 0, 0, 0, 0.246593, 0.96911913, 0, -0.96911913, 0.246593, 0, 13.292481, 5.3253326)",
               "script": 'ExtResource("rig")'}
        if self.follow_offset:
            rig["follow_offset"] = self.follow_offset
        self.node("WorldLocal", type_="Node3D", props={"script": 'ExtResource("world")'})
        self.node("CameraFollowRig", ".", "Node3D", props=rig)
        self.node("ShakePivot", "CameraFollowRig", "Node3D", props={"script": 'ExtResource("shake")'})
        self.node("Camera3D", "CameraFollowRig/ShakePivot", "Camera3D")
        self.node("UI", ".", instance="ui")
        self._add_hint_box()
        self.node("WorldEnvironment", ".", "WorldEnvironment", props={"environment": 'SubResource("Environment_sky")'})
        self._add_sun()
        self.node("GameStateMachine", ".", instance="gsm")
        self.node("Players", ".", instance="players")
        self.node("Enemies", ".", "Node")

    def _add_sun(self):
        if not self.has_sun:
            return
        self.node("DirectionalLight3D", ".", "DirectionalLight3D", props={
            "transform": "Transform3D(1, 0, 0, 0, -0.6213803, 0.78350914, 0, -0.78350914, -0.6213803, 0, 5.421253, -5.724377)",
            "shadow_enabled": "true", "shadow_normal_bias": "5.0", "shadow_blur": "2.0", **self.sun_extra})

    def _add_hint_box(self):
        if not self.hint:
            return
        box = "UI/InfoMessageBottomRight"
        self.node("InfoMessageBottomRight", "UI", "MarginContainer", props={
            "anchors_preset": "3", "anchor_left": "1.0", "anchor_top": "1.0", "anchor_right": "1.0", "anchor_bottom": "1.0",
            "offset_left": "-778.0", "offset_top": "-338.0", "grow_horizontal": "0", "grow_vertical": "0", "theme": 'ExtResource("theme")'})
        self.node("PanelContainer", box, "PanelContainer", props={"layout_mode": "2"})
        self.node("MarginContainer", f"{box}/PanelContainer", "MarginContainer", props={"layout_mode": "2"})
        self.node("InfoLabel", f"{box}/PanelContainer/MarginContainer", "RichTextLabel", props={
            "layout_mode": "2", "bbcode_enabled": "true", "text": self.hint, "fit_content": "true", "scroll_active": "false"})

    def enemy_group(self, name):
        self.node(name, "Enemies", "Node3D", props={"script": 'ExtResource("normal_group")'})
        self.node("InstancedEnemies", f"Enemies/{name}", "Node3D")

    def melee(self, group, name, cx, cz):
        wx, wz = world(cx, cz)
        self.node(name, f"Enemies/{group}/InstancedEnemies", instance=self.melee_scene, props={
            "transform": tf(wx, 0, wz, FACE_SOUTH), "is_offensive": "false"})

    def mage(self, group, name, cx, cz, cast_max=14.0, cooldown=3.0):
        """Stationary mage. Keep cast_max short enough that anything able to fire is on screen."""
        wx, wz = world(cx, cz)
        parent = f"Enemies/{group}/InstancedEnemies"
        self.node(name, parent, instance=self.mage_scene, props={"transform": tf(wx, 0, wz), "is_offensive": "false"})
        self.node("MageBehavior", f"{parent}/{name}", "Node", props={
            "script": 'ExtResource("mage_behavior")', "mobility": "1", "cast_max_distance": fmt_decimal(cast_max), "cast_cooldown": fmt_decimal(cooldown)})

    def survival_group(self, spawn_cells, duration):
        props = {"script": 'ExtResource("survival_group")', "spawn_interval_curve": 'SubResource("Curve_survival")', "fight_duration": fmt_decimal(duration)}
        if self.survival_scene:
            props["enemy_scene"] = f'ExtResource("{self.survival_scene}")'
        self.node("SurvivalEnemyGroup", "Enemies", "Node3D", props=props)
        self.node("Enemies", "Enemies/SurvivalEnemyGroup", "Node3D")
        self.node("SpawnPoints", "Enemies/SurvivalEnemyGroup", "Node3D")
        for index, (cx, cz) in enumerate(spawn_cells, 1):
            wx, wz = world(cx, cz)
            self.node(f"Node3D{index}", "Enemies/SurvivalEnemyGroup/SpawnPoints", "Node3D", props={"transform": tf(wx, 0, wz)})

    def checkpoints(self, entries, setter_marker, shooter_marker):
        """entries: (name, cx, cz, arrays). Markers are local (x, z) offsets for each carrier's spawn."""
        self.node("CheckpointManager", ".", "Node", paths=["current_checkpoint"], props={
            "script": 'ExtResource("cp_manager")', "current_checkpoint": 'NodePath("Checkpoint")'})
        for name, cx, cz, arrays in entries:
            wx, wz = world(cx, cz)
            props = {"transform": tf(wx, CHECKPOINT_Y, wz), "script": 'ExtResource("checkpoint")'}
            props.update({key: node_paths(value) for key, value in arrays.items()})
            self.node(name, "CheckpointManager", "Node3D", paths=list(arrays.keys()) or None, props=props)
            self.node("PositionDirectionSetter", f"CheckpointManager/{name}", "Marker3D", props={"transform": tf(setter_marker[0], 0, setter_marker[1])})
            self.node("PositionShooter", f"CheckpointManager/{name}", "Marker3D", props={"transform": tf(shooter_marker[0], 0, shooter_marker[1])})

    def build_floor(self, floor, mouths):
        cells = {}
        rng = random.Random(self.floor_seed)
        for cell in sorted(floor):
            top, cliff = self._floor_tiles(cell, floor, rng)
            if cell in mouths:
                top = (self.items["Hill_Top_E_Center"], 0)  # flat lip where a bridge lands
            cells[(cell[0], -1, cell[1])] = top
            if cliff:
                cells[(cell[0], -3, cell[1])] = cliff
        return cells

    def _floor_tiles(self, cell, floor, rng):
        missing = _missing_sides(cell, floor)
        if len(missing) == 2:
            key = missing[0] + missing[1]
            return ((self.items["Hill_Top_G_OuterCorner"], TOP_CORNER[key]),
                    (self.items["Hill_Cliff_Tall_I_OuterCorner"], CLIFF_CORNER[key]))
        if len(missing) == 1:
            return self._side_tiles(missing[0], rng)
        diagonal = _missing_diagonal(cell, floor)
        if diagonal:
            return ((self.items["Hill_Top_G_InnerCorner"], TOP_CORNER[diagonal]),
                    (self.items["Hill_Cliff_Tall_I_InnerCorner"], CLIFF_CORNER[diagonal]))
        return (self.items["Hill_Top_E_Center"], 0), None

    def _side_tiles(self, side, rng):
        cliff = (self.items["Hill_Cliff_Tall_H_Side"], CLIFF_SIDE[side])
        if rng.random() < 0.5:
            return (self.items["Hill_Top_F_Side"], TOP_SIDE_A[side]), cliff
        return (self.items["Hill_Top_H_Side"], TOP_SIDE_B[side]), cliff

    def build_decoration(self, floor, count):
        """Non-colliding grass only. The Decoration GridMap keeps the default 2 m cells."""
        rng = random.Random(self.deco_seed)
        grass = [self.items[name] for name in ("Grass_1_A", "Grass_1_B", "Grass_1_C", "Grass_2_A")]
        interior = [c for c in sorted(floor)
                    if all((c[0] + dx, c[1] + dz) in floor for dx in (-1, 0, 1) for dz in (-1, 0, 1))]
        cells = {}
        for cell in rng.sample(interior, min(count, len(interior))):
            wx, wz = world(*cell)
            cells[(int(wx // 2), -1, int(wz // 2))] = (rng.choice(grass), rng.choice([0, 10, 16, 22]))
        return cells

    def add_terrain(self, floor, mouths, decoration_count, fall_z, water_x=None, water_z=None, fall_y=-6.726822):
        """Leave water_x as None for a level without water. Lower fall_y for a longer visible drop."""
        floor_cells = _encode_cells(self.build_floor(floor, mouths))
        deco_cells = _encode_cells(self.build_decoration(floor, decoration_count))
        self.node("Level", ".", "Node")
        self.node("FallArea", "Level", "Area3D", props={"transform": tf(0, fall_y, 0), "script": 'ExtResource("fall")'})
        self.node("CollisionShape3D", "Level/FallArea", "CollisionShape3D", props={
            "transform": tf(0, 4.5282993, fall_z), "shape": 'SubResource("BoxShape3D_fall")'})
        self.node("NavigationRegion3D", "Level", "NavigationRegion3D", props={"navigation_mesh": 'SubResource("NavigationMesh_level")'})
        self.nodes.append('[node name="GridMapFloor" type="GridMap" parent="Level/NavigationRegion3D"]\nmesh_library = ExtResource("tiles")\n'
                          'cell_size = Vector3(2.999, 2, 2.999)\ncollision_layer = 4\ncollision_mask = 0\n'
                          'data = {\n"cells": PackedInt32Array(' + floor_cells + ')\n}\nmetadata/_editor_floor_ = Vector3(0, -1, 0)')
        self.nodes.append('[node name="Decoration" type="GridMap" parent="Level"]\nmesh_library = ExtResource("tiles")\n'
                          'data = {\n"cells": PackedInt32Array(' + deco_cells + ')\n}\nmetadata/_editor_floor_ = Vector3(0, -1, 0)')
        if water_x is not None:
            self.node("Water", "Level", instance="water", props={"transform": tf(water_x, -4.6065345, water_z, "2, 0, 0, 0, 1, 0, 0, 0, 1.7")})
        self.node("Events", "Level", "Node")

    def add_sky(self, floor, tiers=2):
        """Replaces water: cloud layers, plus deeper cliffs so islands don't end where the sea used to hide them."""
        self.bridge_scene = (None, "res://src/world/elements/sky/sky_bridge_platform.tscn")
        self.extra_ext.append(("PackedScene", None, "res://src/world/elements/sky/cloud_layers.tscn", "clouds"))
        self.extra_ext.append(("Script", None, "res://src/world/elements/sky/floating_bob.gd", "bob"))
        self.node("CloudLayers", "Level", instance="clouds")
        self.nodes.append(self._grid_map("IslandCliffs", "Level", self._deep_cliffs(floor, tiers), 'cell_size = Vector3(2.999, 2, 2.999)\ncollision_layer = 0\ncollision_mask = 0'))

    def _deep_cliffs(self, floor, tiers):
        cells = {}
        walls = {key: tile for key, tile in self.build_floor(floor, set()).items() if key[1] == -3}
        for tier in range(1, tiers + 1):
            cells.update({(x, y - 2 * tier, z): tile for (x, y, z), tile in walls.items()})
        return cells

    def _grid_map(self, name, parent, cells, settings):
        return (f'[node name="{name}" type="GridMap" parent="{parent}"]\nmesh_library = ExtResource("tiles")\n{settings}\n'
                'data = {\n"cells": PackedInt32Array(' + _encode_cells(cells) + ')\n}\nmetadata/_editor_floor_ = Vector3(0, -1, 0)')

    def add_distant_island(self, name, position, floor, tree_count):
        """Decorative island far below the play space, with no collision and a slow bob."""
        x, y, z = position
        path = f"Level/DistantIslands/{name}"
        self.node(name, "Level/DistantIslands", "Node3D", props={"transform": tf(x, y, z), "script": 'ExtResource("bob")'})
        no_collision = 'cell_size = Vector3(2.999, 2, 2.999)\ncollision_layer = 0\ncollision_mask = 0'
        terrain = self.build_floor(floor, set())
        terrain.update(self._deep_cliffs(floor, 1))
        self.nodes.append(self._grid_map("Terrain", path, terrain, no_collision))
        self.nodes.append(self._grid_map("Trees", path, self._island_trees(floor, tree_count), "collision_layer = 0\ncollision_mask = 0"))

    def _island_trees(self, floor, count):
        rng = random.Random(len(floor) * 31 + count)
        trees = [self.items[f"Tree_{n}"] for n in ("1_A", "2_A", "3_A", "4_A", "5_A", "6_A")]
        interior = [c for c in sorted(floor) if all((c[0] + dx, c[1] + dz) in floor for dx in (-1, 0, 1) for dz in (-1, 0, 1))]
        cells = {}
        for cell in rng.sample(interior, min(count, len(interior))):
            wx, wz = world(*cell)
            cells[(int(wx // 2), -1, int(wz // 2))] = (rng.choice(trees), 0)
        return cells

    def use_dark_environment(self):
        """Call before add_shell: black background, faint blue ambient, no sun, gates instead of bridges."""
        self.environment = ENVIRONMENT_DARK
        self.has_sun = False
        self.bridge_scene = (None, "res://src/world/elements/dungeon/dungeon_gate.tscn")
        self.extra_ext.append(("PackedScene", None, "res://src/world/elements/dungeon/dungeon_brazier.tscn", "brazier"))
        self.extra_ext.append(("Script", None, "res://src/world/elements/dungeon/carrier_light.gd", "carrier_light"))

    def add_dungeon_terrain(self, floor, pits, pillars, fall_z, fall_y=-17):
        """Stone floor with walls generated around it. Pits stay open: nothing but black below."""
        cells = {(x, -1, z): (self.items["Floor"], 0) for x, z in floor}
        cells.update(self._dungeon_walls(floor, pits))
        cells.update({(x, -1, z): (self.items["Pillar"], 0) for x, z in pillars})
        self.node("Level", ".", "Node")
        self.node("FallArea", "Level", "Area3D", props={"transform": tf(0, fall_y, 0), "script": 'ExtResource("fall")'})
        self.node("CollisionShape3D", "Level/FallArea", "CollisionShape3D", props={
            "transform": tf(0, 4.5282993, fall_z), "shape": 'SubResource("BoxShape3D_fall")'})
        self.node("NavigationRegion3D", "Level", "NavigationRegion3D", props={"navigation_mesh": 'SubResource("NavigationMesh_level")'})
        self.nodes.append(self._grid_map("GridMapFloor", "Level/NavigationRegion3D", cells, 'cell_size = Vector3(2.999, 2, 2.999)\ncollision_layer = 4\ncollision_mask = 0'))
        self.node("Events", "Level", "Node")
        self.node("CarrierLight", "Level", "OmniLight3D", props={
            "transform": tf(1.5, 4, 6), "script": 'ExtResource("carrier_light")', "light_color": "Color(1, 0.86, 0.68, 1)",
            "light_energy": "1.6", "shadow_enabled": "true", "omni_range": "13.0", "omni_attenuation": "0.9"})

    def _dungeon_walls(self, floor, pits):
        """Walls on the camera side stay low so they never hide what stands behind them."""
        open_cells = floor | pits
        around = {(x + dx, z + dz) for x, z in open_cells for dx in (-1, 0, 1) for dz in (-1, 0, 1)}
        cells = {}
        for x, z in around - open_cells:
            is_camera_side = (x, z - 1) in open_cells
            name = "WallLow" if is_camera_side else "WallTall"
            cells[(x, -1, z)] = (self.items[name], 0)
        return cells

    def use_lava_environment(self):
        """Call before add_shell: ash sky, a dim red sun, and bridges that rise out of the lava."""
        self.environment = ENVIRONMENT_LAVA
        self.sky_material = SKY_ASH
        self.sun_extra = {"light_color": "Color(1, 0.86, 0.74, 1)", "light_energy": "0.8", "light_specular": "0.15"}
        self.bridge_scene = (None, "res://src/world/elements/lava/lava_bridge_platform.tscn")
        self.extra_ext.append(("PackedScene", None, "res://src/world/elements/lava/lava_surface.tscn", "lava"))
        self.extra_ext.append(("PackedScene", None, "res://src/world/elements/lava/lava_embers.tscn", "embers"))
        self.extra_ext.append(("PackedScene", None, "res://src/world/elements/lava/lava_vent.tscn", "vent"))

    def add_lava_terrain(self, floor, mouths, fall_z, outcrops=()):
        """Basalt floor over a molten surface. Touching the lava is the fall: the kill box sits right at its surface."""
        self.node("Level", ".", "Node")
        self.node("FallArea", "Level", "Area3D", props={"transform": tf(0, LAVA_FALL_Y, 0), "script": 'ExtResource("fall")'})
        self.node("CollisionShape3D", "Level/FallArea", "CollisionShape3D", props={
            "transform": tf(0, 4.5282993, fall_z), "shape": 'SubResource("BoxShape3D_fall")'})
        self.node("NavigationRegion3D", "Level", "NavigationRegion3D", props={"navigation_mesh": 'SubResource("NavigationMesh_level")'})
        self.nodes.append(self._grid_map("GridMapFloor", "Level/NavigationRegion3D", self.build_floor(floor, mouths), 'cell_size = Vector3(2.999, 2, 2.999)\ncollision_layer = 4\ncollision_mask = 0'))
        self.node("LavaSurface", "Level", instance="lava", props={"transform": tf(0, LAVA_Y, fall_z)})
        self.node("LavaEmbers", "Level", instance="embers", props={"transform": tf(1.5, LAVA_Y, 0)})
        # Lit from below, so anything that stands above the lava picks up its colour. It can't reach the tops of tiles.
        self.node("LavaGlow", "Level", "DirectionalLight3D", props={
            "transform": "Transform3D(1, 0, 0, 0, 0.6, -0.8, 0, 0.8, 0.6, 0, 0, 0)",
            "light_color": "Color(1, 0.42, 0.14, 1)", "light_energy": "0.55", "sky_mode": "1"})
        self._add_outcrops(outcrops)
        self.node("Events", "Level", "Node")

    def _add_outcrops(self, outcrops):
        """outcrops: (cx, cz, rock name, rotation). Scenery in the lava with no collision, three times the rocks' size."""
        if not outcrops:
            return
        self.node("Outcrops", "Level", "Node3D", props={"transform": tf(0, LAVA_Y - 0.6, 0, "3, 0, 0, 0, 3, 0, 0, 0, 3")})
        cells = {(round(cx / 3), 0, round(cz / 3)): (self.items[name], rot) for cx, cz, name, rot in outcrops}
        self.nodes.append(self._grid_map("Rocks", "Level/Outcrops", cells, 'cell_size = Vector3(2.999, 2, 2.999)\ncollision_layer = 0\ncollision_mask = 0'))

    def add_vents(self, vents):
        """vents: (cx, cz, phase) on the floor. Each burns whatever stands inside its marked circle when it erupts."""
        self.node("Vents", "Level", "Node")
        for index, (cx, cz, phase) in enumerate(vents, 1):
            wx, wz = world(cx, cz)
            self.node(f"LavaVent{index}", "Level/Vents", instance="vent", props={"transform": tf(wx, -1, wz), "phase": fmt_decimal2(phase)})

    def add_lava_spouts(self, spouts):
        """spouts: (cx, cz, phase) out in the lava. Harmless scenery, about twice the size of a vent."""
        self.node("Spouts", "Level", "Node")
        scale = "2, 0, 0, 0, 2, 0, 0, 0, 2"
        for index, (cx, cz, phase) in enumerate(spouts, 1):
            wx, wz = world(cx, cz)
            self.node(f"LavaSpout{index}", "Level/Spouts", instance="vent", props={
                "transform": tf(wx, LAVA_Y, wz, scale), "phase": fmt_decimal2(phase), "is_dangerous": "false", "period_seconds": "5.0"})

    def use_rotor_decks(self):
        """Call before add_shell: ferries instead of bridges, and the clouds and rotors these levels need."""
        self.bridge_scene = (None, "res://src/world/elements/sky_decks/rotor_ferry.tscn")
        self.extra_ext.append(("PackedScene", None, "res://src/world/elements/sky/cloud_layers.tscn", "clouds"))
        self.extra_ext.append(("Script", None, "res://src/world/elements/sky/floating_bob.gd", "bob"))
        self.extra_ext.append(("PackedScene", None, "res://src/world/elements/sky_decks/deck_rotor.tscn", "rotor"))

    def add_deck_terrain(self, decks, lanes, fall_z, fall_y=-17):
        """decks: list of cell sets. lanes: cells next to where a ferry docks, which get no rotor."""
        floor = set().union(*decks)
        cells = {(x, -1, z): (self.items["Deck"], 0) for x, z in floor}
        self.node("Level", ".", "Node")
        self.node("FallArea", "Level", "Area3D", props={"transform": tf(0, fall_y, 0), "script": 'ExtResource("fall")'})
        self.node("CollisionShape3D", "Level/FallArea", "CollisionShape3D", props={
            "transform": tf(0, 4.5282993, fall_z), "shape": 'SubResource("BoxShape3D_fall")'})
        self.node("NavigationRegion3D", "Level", "NavigationRegion3D", props={"navigation_mesh": 'SubResource("NavigationMesh_level")'})
        self.nodes.append(self._grid_map("GridMapFloor", "Level/NavigationRegion3D", cells, 'cell_size = Vector3(2.999, 2, 2.999)\ncollision_layer = 4\ncollision_mask = 0'))
        self.nodes.append(self._grid_map("DeckFrame", "Level", self._deck_frame(floor), 'cell_size = Vector3(2.999, 2, 2.999)\ncollision_layer = 0\ncollision_mask = 0'))
        self.node("CloudLayers", "Level", instance="clouds")
        self.node("Rotors", "Level", "Node3D")
        self._add_rotors("Level/Rotors", _rotor_spots(floor, lanes), 0)
        self.node("Events", "Level", "Node")

    def _deck_frame(self, floor):
        """Dark joists under each cell, one layer below the deck. A GridMap cell holds one item, so the beams along
        outer edges go on further layers below, with their meshes lifted back up (see deck_tiles.tres)."""
        cells = {(x, -1, z): (self.items["Joists"], 0) for x, z in floor}
        for layer, (name, dx, dz) in enumerate((("EdgeN", 0, -1), ("EdgeS", 0, 1), ("EdgeW", -1, 0), ("EdgeE", 1, 0)), 2):
            for x, z in floor:
                if (x + dx, z + dz) not in floor:
                    cells[(x, -layer, z)] = (self.items[name], 0)
        return cells

    def _add_rotors(self, parent, spots, index):
        for wx, wz, side in spots:
            index += 1
            self.node(f"Rotor{index}", parent, instance="rotor", props={"transform": tf(wx, -1, wz, ROTOR_BASIS[side])})
        return index

    def add_distant_deck(self, name, position, shape):
        """Scenery far below the play space, with no collision and a slow bob."""
        x, y, z = position
        path = f"Level/DistantDecks/{name}"
        self.node(name, "Level/DistantDecks", "Node3D", props={"transform": tf(x, y, z), "script": 'ExtResource("bob")'})
        settings = 'cell_size = Vector3(2.999, 2, 2.999)\ncollision_layer = 0\ncollision_mask = 0'
        cells = {(cx, -1, cz): (self.items["Deck"], 0) for cx, cz in shape}
        self.nodes.append(self._grid_map("Deck", path, cells, settings))
        self.nodes.append(self._grid_map("Frame", path, self._deck_frame(shape), settings))
        self._add_rotors(path, _rotor_spots(shape, set(), every=2, origin=(0, 0)), 0)

    def use_space_station(self):
        """Call before add_shell: starfield, a white sun, hard-light bridges, and robots instead of skeletons."""
        self.environment = ENVIRONMENT_SPACE
        self.sky_material = SKY_SPACE
        self.sun_extra = {"light_color": "Color(1, 0.97, 0.92, 1)", "light_energy": "1.25"}
        self.bridge_scene = (None, "res://src/world/elements/space/hard_light_bridge_platform.tscn")
        self.melee_scene, self.mage_scene, self.survival_scene = "robot", "robot_gunner", "robot"
        self.extra_ext += [
            ("Shader", None, "res://src/world/elements/space/space_sky.gdshader", "space_sky"),
            ("PackedScene", None, "res://src/enemy/enemy_robot.tscn", "robot"),
            ("PackedScene", None, "res://src/enemy/enemy_robot_gunner.tscn", "robot_gunner"),
            ("PackedScene", None, "res://src/world/elements/space/planet.tscn", "planet"),
            ("PackedScene", None, "res://assets/models/space_base/rocks_B.gltf", "asteroid"),
            ("Script", None, "res://src/world/elements/space/drifting_spin.gd", "drift"),
            ("Script", None, "res://src/world/elements/sky/floating_bob.gd", "bob"),
        ]

    def add_station_terrain(self, decks, props, fall_z, fall_y=-17):
        """decks: list of cell sets. props: {(cx, cz): (item, rotation)}; each stands on a plate and blocks movement."""
        floor = set().union(*decks)
        assert set(props) <= floor, sorted(set(props) - floor)
        self.node("Level", ".", "Node")
        self.node("FallArea", "Level", "Area3D", props={"transform": tf(0, fall_y, 0), "script": 'ExtResource("fall")'})
        self.node("CollisionShape3D", "Level/FallArea", "CollisionShape3D", props={
            "transform": tf(0, 4.5282993, fall_z), "shape": 'SubResource("BoxShape3D_fall")'})
        self.node("NavigationRegion3D", "Level", "NavigationRegion3D", props={"navigation_mesh": 'SubResource("NavigationMesh_level")'})
        self.nodes.append(self._grid_map("GridMapFloor", "Level/NavigationRegion3D", self._station_floor(floor, props), 'cell_size = Vector3(2.999, 2, 2.999)\ncollision_layer = 4\ncollision_mask = 0'))
        self.nodes.append(self._grid_map("StationHull", "Level", self._station_hull(floor), 'cell_size = Vector3(2.999, 2, 2.999)\ncollision_layer = 0\ncollision_mask = 0'))
        self.node("Events", "Level", "Node")

    def _station_floor(self, floor, props):
        cells = {(x, -1, z): (self.items["Plate"], 0) for x, z in floor}
        cells.update({(x, -1, z): (self.items[name], rot) for (x, z), (name, rot) in props.items()})
        return cells

    def _station_hull(self, floor):
        """A keel under every plate, and glowing trims along outer edges. A GridMap cell holds one item, so the
        trims go on lower layers with their meshes lifted back up (see build_space_tiles.gd)."""
        cells = {(x, -2, z): (self.items["Hull"], 0) for x, z in floor}
        for layer, (name, dx, dz) in enumerate((("TrimN", 0, -1), ("TrimS", 0, 1), ("TrimW", -1, 0), ("TrimE", 1, 0)), 3):
            for x, z in floor:
                if (x + dx, z + dz) not in floor:
                    cells[(x, -layer, z)] = (self.items[name], 0)
        return cells

    def add_planet(self, position, radius):
        x, y, z = position
        self.node("Planet", "Level", instance="planet", props={"transform": tf(x, y, z, f"{radius}, 0, 0, 0, {radius}, 0, 0, 0, {radius}")})

    def add_distant_station(self, name, position, shape, props):
        """Scenery far below the play space, with no collision and a slow bob."""
        x, y, z = position
        path = f"Level/DistantStations/{name}"
        self.node(name, "Level/DistantStations", "Node3D", props={"transform": tf(x, y, z), "script": 'ExtResource("bob")'})
        settings = 'cell_size = Vector3(2.999, 2, 2.999)\ncollision_layer = 0\ncollision_mask = 0'
        self.nodes.append(self._grid_map("Deck", path, self._station_floor(shape, props), settings))
        self.nodes.append(self._grid_map("Hull", path, self._station_hull(shape), settings))

    def add_asteroids(self, asteroids):
        """asteroids: (x, y, z, scale). Scenery with no collision, tumbling slowly."""
        self.node("Asteroids", "Level", "Node3D")
        for index, (x, y, z, scale) in enumerate(asteroids, 1):
            self.node(f"Asteroid{index}", "Level/Asteroids", instance="asteroid", props={
                "transform": tf(x, y, z, f"{scale}, 0, 0, 0, {scale}, 0, 0, 0, {scale}"), "script": 'ExtResource("drift")'})

    def add_braziers(self, cells):
        self.node("Braziers", "Level", "Node")
        for index, (cx, cz) in enumerate(cells, 1):
            wx, wz = world(cx, cz)
            self.node(f"Brazier{index}", "Level/Braziers", instance="brazier", props={"transform": tf(wx, -1, wz)})

    def set_bridges(self, bridges):
        count = 0
        self.bridges = bridges
        for number, cells in bridges.items():
            self.platforms[number] = [f"BridgePlatform{count + i + 1}" for i in range(len(cells))]
            count += len(cells)

    def bridge_event(self, name, number, close=False, next_event=None, camera_focus=True):
        """camera_focus=False opens without locking input and cutting the camera to the platform."""
        props = {"script": 'ExtResource("toggle_bridge")',
                 "platforms": node_paths(["../../Bridges/" + p for p in self.platforms[number]]),
                 "platform_animation_stagger_seconds": "0.5"}
        if close:
            props.update({"use_camera_focus": "false", "event_type": "1"})
        if not close and not camera_focus:
            props["use_camera_focus"] = "false"
        if next_event:
            props["next_event"] = f'NodePath("../{next_event}")'
        paths = ["platforms"] + (["next_event"] if next_event else [])
        self.node(name, "Level/Events", "Node", paths=paths, props=props)

    def offensive_event(self, name, group):
        self.node(name, "Level/Events", "Node", paths=["enemy_group"], props={
            "script": 'ExtResource("change_behavior")', "enemy_group": f'NodePath("../../../Enemies/{group}")'})

    def add_focus(self, areas):
        """areas: {label: (x0, x1, z_south, z_north)}. Adds a focal point at each of four corners."""
        for label in areas:
            for corner in ("SW", "SE", "NW", "NE"):
                name = f"Focus{label}{corner}"
                self.node(name, "Level/Events", "Node", paths=["focal_point"], props={
                    "script": 'ExtResource("camera_focus")', "focal_point": f'NodePath("../../FocusPoints/{name}")'})
        self.node("UnfocusCamera", "Level/Events", "Node", props={"script": 'ExtResource("camera_clear")'})
        self.node("FocusPoints", "Level", "Node3D")
        for label, (x0, x1, z_south, z_north) in areas.items():
            corners = (("SW", x0, z_south), ("SE", x1, z_south), ("NW", x0, z_north), ("NE", x1, z_north))
            for corner, cx, cz in corners:
                wx, wz = world(cx, cz)
                self.node(f"Focus{label}{corner}", "Level/FocusPoints", "Node3D", props={"transform": tf(wx, 0, wz)})

    def add_end_area(self, cx, cz):
        wx, wz = world(cx, cz)
        self.node("EndLevelArea", "Level", "Area3D", props={"transform": tf(wx, 0, wz), "script": 'ExtResource("all_players")'})
        self.node("CollisionShape3D", "Level/EndLevelArea", "CollisionShape3D", props={"shape": 'SubResource("BoxShape3D_end")'})

    def add_bridge_nodes(self):
        self.node("Bridges", "Level", "Node")
        for number, cells in self.bridges.items():
            for name, (cx, cz) in zip(self.platforms[number], cells):
                wx, wz = world(cx, cz)
                self.node(name, "Level/Bridges", instance="bridge", props={"transform": tf(wx, BRIDGE_Y, wz)})

    def add_triggers(self, triggers):
        """triggers: (name, cx, cz, box_key)."""
        self.node("Areas", "Level", "Node")
        for name, cx, cz, box in triggers:
            wx, wz = world(cx, cz)
            self.node(name, "Level/Areas", "Area3D", props={"transform": tf(wx, 0, wz), "script": 'ExtResource("all_players")'})
            self.node("CollisionShape3D", f"Level/Areas/{name}", "CollisionShape3D", props={"shape": f'SubResource("BoxShape3D_{box}")'})

    def add_weapon(self, name, transform):
        self.node("Weapon", ".", "Node3D")
        self.node(name, "Weapon", instance=self.weapon, props={"transform": transform})

    def add_audio_and_hint(self):
        self.node("AudioStreamPlayer", ".", "AudioStreamPlayer", props={
            "stream": 'ExtResource("music")', "volume_db": "-20.14", "autoplay": "true", "bus": '&"Music"', "parameters/looping": "true"})
        if self.hint:
            self.node("ShowMessageAtLaunch", ".", "Node", props={"script": 'ExtResource("launch_message")', "message_string": self.hint})

    def _external_resources(self):
        weapon_uid, weapon_path = WEAPONS[self.weapon]
        return [
            ("Script", "uid://bj06i7pt2w2l7", "res://src/world/world_local.gd", "world"),
            ("Script", "uid://dqtkaa0x7s0pv", "res://src/world/camera_follow_rig.gd", "rig"),
            ("Script", "uid://cqwm8n5kpivt1", "res://src/world/camera_shake_pivot.gd", "shake"),
            ("Texture2D", "uid://chj3qn7lpf02", "res://assets/material/sky/panorama_image.png", "sky"),
            ("PackedScene", "uid://ddmgied4vtriv", "res://src/world/ui/ui.tscn", "ui"),
            ("Theme", "uid://cqojbbcsl6jfh", "res://assets/theme/ui_theme.tres", "theme"),
            ("Script", "uid://css2lrdcxlitf", "res://src/world/ui/show_message_at_launch.gd", "launch_message"),
            ("PackedScene", "uid://l3q0p7d7n4fk", "res://src/game/states/game_state_machine.tscn", "gsm"),
            ("PackedScene", "uid://d2bo2n33sqvci", "res://src/world/levels/players.tscn", "players"),
            ("PackedScene", "uid://cif7328pvepge", "res://src/enemy/enemy_local.tscn", "enemy"),
            ("PackedScene", "uid://cj1jiphwktvpn", "res://src/enemy/enemy_mage_no_behavior.tscn", "mage"),
            ("Script", "uid://s3p4luca33c7", "res://src/enemy/behavior/mage_behavior.gd", "mage_behavior"),
            ("Script", "uid://bk8xqm3nw2h4r", "res://src/enemy/normal_enemy_group.gd", "normal_group"),
            ("Script", "uid://bvpjcgrdkl4we", "res://src/enemy/survival_enemy_group.gd", "survival_group"),
            ("Script", "uid://bx3gk3t68de8s", "res://src/world/checkpoints/checkpoint_manager.gd", "cp_manager"),
            ("Script", "uid://c3uca7pxa3ofw", "res://src/world/checkpoints/checkpoint.gd", "checkpoint"),
            ("Script", "uid://dgghjmfpume34", "res://src/world/fall_area.gd", "fall"),
            ("MeshLibrary", self.lib_uid, "res://" + self.lib_path, "tiles"),
            ("PackedScene", "uid://c2hrlod45sfxd", "res://src/world/elements/water.tscn", "water"),
            ("PackedScene", self.bridge_scene[0], self.bridge_scene[1], "bridge"),
            ("Script", "uid://craclr3fqyunt", "res://src/events/toggle_bridge_event.gd", "toggle_bridge"),
            ("Script", "uid://d2pnle1sbun8v", "res://src/events/change_enemies_behavior.gd", "change_behavior"),
            ("Script", "uid://cpybi6smjnan5", "res://src/events/level_finished_event.gd", "finished"),
            ("Script", "uid://b330nc18vwhrr", "res://src/events/camera_add_focal_point_event.gd", "camera_focus"),
            ("Script", "uid://caypfr8giu78a", "res://src/events/camera_clear_focal_points_event.gd", "camera_clear"),
            ("Script", "uid://dm0qyuvkt2r20", "res://src/world/elements/all_players_area_trigger.gd", "all_players"),
            ("PackedScene", weapon_uid, weapon_path, self.weapon),
            ("AudioStream", self.music[0], self.music[1], "music"),
        ] + self.extra_ext

    def _sub_resources(self, nav_body):
        start, end = self.curve
        boxes = "\n\n".join(f'[sub_resource type="BoxShape3D" id="BoxShape3D_{key}"]\nsize = Vector3({x}, {y}, {z})'
                            for key, (x, y, z) in self.boxes.items())
        return f"""{self.sky_material}

[sub_resource type="Sky" id="Sky_level"]
sky_material = SubResource("PanoramaSkyMaterial_sky")

[sub_resource type="Environment" id="Environment_sky"]
{self.environment}

[sub_resource type="Curve" id="Curve_survival"]
_limits = [0.0, 3.0, 0.0, 1.0]
_data = [Vector2(0, {start}), 0.0, 0.0, 0, 0, Vector2(1, {end}), 0.0, 0.0, 0, 0]
point_count = 2

{boxes}

[sub_resource type="NavigationMesh" id="NavigationMesh_level"]
{nav_body}"""

    def write(self, argv):
        """Usage: script.py [baked.json] [--out PATH] [--force]. Refuses to overwrite an existing file without --force."""
        args = list(argv)
        force = "--force" in args
        args = [a for a in args if a != "--force"]
        out = self.out
        if "--out" in args:
            index = args.index("--out")
            out = args[index + 1]
            del args[index:index + 2]
        if Path(out).exists() and not force:
            sys.exit(f"{out} exists. It may hold hand edits: review them, then pass --force.")
        baked = json.loads(Path(args[0]).read_text()) if args else None
        uid_attr = f' uid="{baked["uid"]}"' if baked else ""
        nav_body = f'vertices = {baked["vertices"]}\npolygons = {baked["polygons"]}\n' if baked else ""
        parts = [f"[gd_scene format=3{uid_attr}]\n"]
        parts += [_ext_line(*entry) for entry in self._external_resources()]
        parts += ["", self._sub_resources(nav_body), "\n\n".join(self.nodes), ""]
        parts += [f'[connection signal="{s}" from="{f}" to="{t}" method="{m}"]' for s, f, t, m in self.connections]
        Path(out).write_text("\n".join(parts) + "\n")
        print("wrote", out)


def _rotor_spots(floor, lanes, every=3, origin=None):
    """(world x, world z, side) along a deck's outer edges, at every few cells, skipping lanes."""
    spots = []
    sides = (("E", 1, 0), ("W", -1, 0), ("N", 0, -1), ("S", 0, 1))
    for cell in sorted(floor):
        for side, dx, dz in sides:
            neighbour = (cell[0] + dx, cell[1] + dz)
            along = cell[1] if dx else cell[0]
            if neighbour in floor or cell in lanes or along % every:
                continue
            wx, wz = _local_or_world(cell, origin)
            spots.append((wx + dx * 1.5, wz + dz * 1.5, side))
    return spots


def _local_or_world(cell, origin):
    if origin is None:
        return world(*cell)
    return (cell[0] + 0.5) * CELL + origin[0], (cell[1] + 0.5) * CELL + origin[1]


def _ext_line(kind, uid, path, ext_id):
    uid_attr = f' uid="{uid}"' if uid else ""
    return f'[ext_resource type="{kind}"{uid_attr} path="{path}" id="{ext_id}"]'


def fmt_decimal(value):
    return f"{float(value):.1f}"


def fmt_decimal2(value):
    return f"{float(value):.2f}"


def checkpoint(name, cx, cz, opened=None, reset=None, defeated=None, react=None, done=None):
    """One checkpoint's restore state: what is open, reset, dead, and which triggers are live or spent."""
    arrays = {}
    pairs = (("events_completed", "../../Level/Events/", opened), ("enemy_groups_reset", "../../Enemies/", reset),
             ("enemy_groups_defeated", "../../Enemies/", defeated), ("areas_to_reactivate", "../../Level/Areas/", react),
             ("areas_already_activated", "../../Level/Areas/", done))
    for key, prefix, value in pairs:
        if value:
            arrays[key] = [prefix + value]
    return (name, cx, cz, arrays)
