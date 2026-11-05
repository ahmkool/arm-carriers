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
}
WEAPONS = {
    "bazooka": ("uid://cq5v348mrgy7q", "res://src/weapon/bazooka.tscn"),
    "sword": ("uid://bgdgrubg87row", "res://src/weapon/sword.tscn"),
    "saw": ("uid://lilxckjevvd5", "res://src/weapon/saw.tscn"),
}
TRIGGER = "AllPlayersAreaTrigger"
EVENTS = "Level/Events/"
AREAS = "Level/Areas/"
GROUPS = "Enemies/"


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

    def __init__(self, out, palette, weapon, deco_seed, floor_seed, hint=None, follow_offset=None):
        self.out = out
        self.lib_path, self.lib_uid = LIBRARIES[palette]
        self.weapon = weapon
        self.floor_seed = floor_seed
        self.deco_seed = deco_seed
        self.hint = f'"{hint}"' if hint else None
        self.follow_offset = follow_offset
        self.nodes = []
        self.connections = []
        self.boxes = {}
        self.curve = None
        self.platforms = {}
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
        self.node("DirectionalLight3D", ".", "DirectionalLight3D", props={
            "transform": "Transform3D(1, 0, 0, 0, -0.6213803, 0.78350914, 0, -0.78350914, -0.6213803, 0, 5.421253, -5.724377)",
            "shadow_enabled": "true", "shadow_normal_bias": "5.0", "shadow_blur": "2.0"})
        self.node("GameStateMachine", ".", instance="gsm")
        self.node("Players", ".", instance="players")
        self.node("Enemies", ".", "Node")

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
        self.node(name, f"Enemies/{group}/InstancedEnemies", instance="enemy", props={
            "transform": tf(wx, 0, wz, FACE_SOUTH), "is_offensive": "false"})

    def mage(self, group, name, cx, cz, cast_max=14.0, cooldown=3.0):
        """Stationary mage. Keep cast_max short enough that anything able to fire is on screen."""
        wx, wz = world(cx, cz)
        parent = f"Enemies/{group}/InstancedEnemies"
        self.node(name, parent, instance="mage", props={"transform": tf(wx, 0, wz), "is_offensive": "false"})
        self.node("MageBehavior", f"{parent}/{name}", "Node", props={
            "script": 'ExtResource("mage_behavior")', "mobility": "1", "cast_max_distance": fmt_decimal(cast_max), "cast_cooldown": fmt_decimal(cooldown)})

    def survival_group(self, spawn_cells, duration):
        self.node("SurvivalEnemyGroup", "Enemies", "Node3D", props={
            "script": 'ExtResource("survival_group")', "spawn_interval_curve": 'SubResource("Curve_survival")', "fight_duration": fmt_decimal(duration)})
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

    def add_terrain(self, floor, mouths, decoration_count, fall_z, water_x, water_z):
        floor_cells = _encode_cells(self.build_floor(floor, mouths))
        deco_cells = _encode_cells(self.build_decoration(floor, decoration_count))
        self.node("Level", ".", "Node")
        self.node("FallArea", "Level", "Area3D", props={"transform": tf(0, -6.726822, 0), "script": 'ExtResource("fall")'})
        self.node("CollisionShape3D", "Level/FallArea", "CollisionShape3D", props={
            "transform": tf(0, 4.5282993, fall_z), "shape": 'SubResource("BoxShape3D_fall")'})
        self.node("NavigationRegion3D", "Level", "NavigationRegion3D", props={"navigation_mesh": 'SubResource("NavigationMesh_level")'})
        self.nodes.append('[node name="GridMapFloor" type="GridMap" parent="Level/NavigationRegion3D"]\nmesh_library = ExtResource("tiles")\n'
                          'cell_size = Vector3(2.999, 2, 2.999)\ncollision_layer = 4\ncollision_mask = 0\n'
                          'data = {\n"cells": PackedInt32Array(' + floor_cells + ')\n}\nmetadata/_editor_floor_ = Vector3(0, -1, 0)')
        self.nodes.append('[node name="Decoration" type="GridMap" parent="Level"]\nmesh_library = ExtResource("tiles")\n'
                          'data = {\n"cells": PackedInt32Array(' + deco_cells + ')\n}\nmetadata/_editor_floor_ = Vector3(0, -1, 0)')
        self.node("Water", "Level", instance="water", props={"transform": tf(water_x, -4.6065345, water_z, "2, 0, 0, 0, 1, 0, 0, 0, 1.7")})
        self.node("Events", "Level", "Node")

    def set_bridges(self, bridges):
        count = 0
        self.bridges = bridges
        for number, cells in bridges.items():
            self.platforms[number] = [f"BridgePlatform{count + i + 1}" for i in range(len(cells))]
            count += len(cells)

    def bridge_event(self, name, number, close=False, next_event=None):
        props = {"script": 'ExtResource("toggle_bridge")',
                 "platforms": node_paths(["../../Bridges/" + p for p in self.platforms[number]]),
                 "platform_animation_stagger_seconds": "0.5"}
        if close:
            props.update({"use_camera_focus": "false", "event_type": "1"})
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
            ("PackedScene", "uid://chaj7v8uajl4q", "res://src/world/elements/bridge_platform.tscn", "bridge"),
            ("Script", "uid://craclr3fqyunt", "res://src/events/toggle_bridge_event.gd", "toggle_bridge"),
            ("Script", "uid://d2pnle1sbun8v", "res://src/events/change_enemies_behavior.gd", "change_behavior"),
            ("Script", "uid://cpybi6smjnan5", "res://src/events/level_finished_event.gd", "finished"),
            ("Script", "uid://b330nc18vwhrr", "res://src/events/camera_add_focal_point_event.gd", "camera_focus"),
            ("Script", "uid://caypfr8giu78a", "res://src/events/camera_clear_focal_points_event.gd", "camera_clear"),
            ("Script", "uid://dm0qyuvkt2r20", "res://src/world/elements/all_players_area_trigger.gd", "all_players"),
            ("PackedScene", weapon_uid, weapon_path, self.weapon),
            ("AudioStream", "uid://bp1ug7cyuchid", "res://assets/music/PerituneMaterial_Amenoshita.mp3", "music"),
        ]

    def _sub_resources(self, nav_body):
        start, end = self.curve
        boxes = "\n\n".join(f'[sub_resource type="BoxShape3D" id="BoxShape3D_{key}"]\nsize = Vector3({x}, {y}, {z})'
                            for key, (x, y, z) in self.boxes.items())
        return f"""[sub_resource type="PanoramaSkyMaterial" id="PanoramaSkyMaterial_sky"]
panorama = ExtResource("sky")

[sub_resource type="Sky" id="Sky_level"]
sky_material = SubResource("PanoramaSkyMaterial_sky")

[sub_resource type="Environment" id="Environment_sky"]
background_mode = 2
sky = SubResource("Sky_level")
ambient_light_sky_contribution = 0.4
ambient_light_energy = 0.3

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
        parts += [f'[ext_resource type="{t}" uid="{u}" path="{p}" id="{i}"]' for t, u, p, i in self._external_resources()]
        parts += ["", self._sub_resources(nav_body), "\n\n".join(self.nodes), ""]
        parts += [f'[connection signal="{s}" from="{f}" to="{t}" method="{m}"]' for s, f, t, m in self.connections]
        Path(out).write_text("\n".join(parts) + "\n")
        print("wrote", out)


def fmt_decimal(value):
    return f"{float(value):.1f}"


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
