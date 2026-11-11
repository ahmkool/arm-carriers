# Builds the gun-shielded aviator's tower shield with its mounted gun and exports it as glTF.
# Run headless from the project root:
#   /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/build_avian_gun_shield.py -- <out.glb> [preview.png]
# Faces Blender +Y, which the glTF exporter turns into -Z: Godot's forward.
# The origin is the centre of the plate's back face, where the aviator holds it.
import math
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_PATH = argv[0] if argv else "AvianGunShield.glb"
PREVIEW_PATH = argv[1] if len(argv) > 1 else ""

PLATE_W = 1.15
PLATE_H = 1.6
PLATE_D = 0.09


def reset_scene():
	bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, color, metallic=0.0, roughness=0.6, emission=None):
	mat = bpy.data.materials.new(name)
	mat.use_nodes = True
	bsdf = mat.node_tree.nodes["Principled BSDF"]
	bsdf.inputs["Base Color"].default_value = (*color, 1.0)
	bsdf.inputs["Metallic"].default_value = metallic
	bsdf.inputs["Roughness"].default_value = roughness
	if emission is not None:
		bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
		bsdf.inputs["Emission Strength"].default_value = 3.0
	mat.diffuse_color = (*color, 1.0)
	return mat


def box(name, size, location, mat, bevel=0.0, segments=2):
	bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
	obj = bpy.context.active_object
	obj.name = name
	obj.scale = size
	bpy.ops.object.transform_apply(scale=True)
	obj.data.materials.append(mat)
	if bevel > 0.0:
		mod = obj.modifiers.new("Bevel", "BEVEL")
		mod.width = bevel
		mod.segments = segments
		mod.limit_method = "ANGLE"
	return obj


def cylinder(name, radius, depth, location, mat, rotation=(0.0, 0.0, 0.0), vertices=16):
	bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, location=location, rotation=rotation, vertices=vertices)
	obj = bpy.context.active_object
	obj.name = name
	obj.data.materials.append(mat)
	bpy.ops.object.shade_smooth()
	return obj


def along_y():
	return (math.radians(90.0), 0.0, 0.0)


def bend(obj, degrees):
	# Curves the plate round the vertical axis so its middle bulges forward, toward +Y.
	mod = obj.modifiers.new("Bend", "SIMPLE_DEFORM")
	mod.deform_method = "BEND"
	mod.deform_axis = "Z"
	mod.angle = math.radians(degrees)


def subdivide_for_bend(obj, cuts):
	bpy.context.view_layer.objects.active = obj
	bpy.ops.object.mode_set(mode="EDIT")
	bpy.ops.mesh.select_all(action="SELECT")
	bpy.ops.mesh.subdivide(number_cuts=cuts)
	bpy.ops.object.mode_set(mode="OBJECT")


def build():
	steel = material("ShieldSteel", (0.30, 0.38, 0.50), metallic=0.6, roughness=0.45)
	iron = material("ShieldIron", (0.10, 0.10, 0.12), metallic=0.7, roughness=0.5)
	brass = material("ShieldBrass", (0.85, 0.58, 0.20), metallic=0.8, roughness=0.35)
	gunmetal = material("GunMetal", (0.16, 0.17, 0.19), metallic=0.8, roughness=0.4)
	feather = material("ShieldCrest", (0.75, 0.16, 0.12), roughness=0.7)
	glow = material("MuzzleGlow", (1.0, 0.55, 0.1), emission=(1.0, 0.45, 0.05))

	parts = []
	y_front = PLATE_D
	plate = box("Plate", (PLATE_W, PLATE_D, PLATE_H), (0.0, PLATE_D * 0.5, 0.0), steel, bevel=0.02)
	parts.append(plate)
	rim_t = 0.07
	for side in (-1.0, 1.0):
		parts.append(box("RimSide", (rim_t, PLATE_D + 0.05, PLATE_H + 0.04), (side * (PLATE_W * 0.5), PLATE_D * 0.5 + 0.01, 0.0), iron, bevel=0.015))
		parts.append(box("RimEnd", (PLATE_W + 0.04, PLATE_D + 0.05, rim_t), (0.0, PLATE_D * 0.5 + 0.01, side * (PLATE_H * 0.5)), iron, bevel=0.015))
	# Rivets along the rim.
	for i in range(5):
		z = -PLATE_H * 0.4 + i * PLATE_H * 0.2
		for side in (-1.0, 1.0):
			parts.append(cylinder("Rivet", 0.028, 0.03, (side * (PLATE_W * 0.5 - 0.09), y_front + 0.01, z), brass, rotation=along_y(), vertices=8))
	# A raised chevron crest down the middle.
	parts.append(box("Spine", (0.12, 0.05, PLATE_H * 0.82), (0.0, y_front + 0.02, -0.05), brass, bevel=0.015))
	for side in (-1.0, 1.0):
		wing = box("Chevron", (0.42, 0.04, 0.09), (side * 0.17, y_front + 0.02, -0.18), brass, bevel=0.012)
		wing.rotation_euler = (0.0, side * math.radians(-28.0), 0.0)
		parts.append(wing)
		feathered = box("Feather", (0.16, 0.035, 0.55), (side * 0.3, y_front + 0.015, -0.48), feather, bevel=0.01)
		feathered.rotation_euler = (0.0, side * math.radians(12.0), 0.0)
		parts.append(feathered)
	# A sight slit near the top for the aviator to look through.
	parts.append(box("Slit", (0.42, 0.04, 0.06), (-0.12, y_front + 0.01, PLATE_H * 0.33), iron))

	# The gun: a housing bolted on the upper right, its barrel poking forward through the plate.
	gun_x = 0.3
	gun_z = 0.28
	parts.append(box("GunHousing", (0.26, 0.3, 0.24), (gun_x, y_front + 0.15, gun_z), gunmetal, bevel=0.03))
	parts.append(box("GunBrace", (0.32, 0.06, 0.32), (gun_x, y_front + 0.02, gun_z), iron, bevel=0.015))
	parts.append(cylinder("Barrel", 0.065, 0.7, (gun_x, y_front + 0.6, gun_z), gunmetal, rotation=along_y()))
	parts.append(cylinder("BarrelBand", 0.085, 0.06, (gun_x, y_front + 0.42, gun_z), brass, rotation=along_y()))
	parts.append(cylinder("MuzzleRing", 0.095, 0.09, (gun_x, y_front + 0.93, gun_z), iron, rotation=along_y()))
	parts.append(cylinder("MuzzleGlow", 0.05, 0.02, (gun_x, y_front + 0.98, gun_z), glow, rotation=along_y(), vertices=12))
	parts.append(box("Ammo", (0.14, 0.2, 0.22), (gun_x, y_front + 0.12, gun_z - 0.22), gunmetal, bevel=0.02))

	# Handles on the back, so it reads as held.
	parts.append(box("Grip", (0.5, 0.06, 0.06), (0.0, -0.08, 0.05), iron, bevel=0.01))
	for side in (-1.0, 1.0):
		parts.append(box("GripPost", (0.05, 0.08, 0.06), (side * 0.22, -0.035, 0.05), iron))

	subdivide_for_bend(plate, 6)
	bend(plate, -18.0)

	for obj in parts:
		obj.select_set(True)
	bpy.context.view_layer.objects.active = plate
	for obj in parts:
		bpy.context.view_layer.objects.active = obj
		for mod in list(obj.modifiers):
			bpy.ops.object.modifier_apply(modifier=mod.name)
	bpy.ops.object.select_all(action="DESELECT")
	for obj in parts:
		obj.select_set(True)
	bpy.context.view_layer.objects.active = plate
	bpy.ops.object.join()
	shield = bpy.context.active_object
	shield.name = "AvianGunShield"
	# Mark the muzzle for the game: an empty at the barrel's tip.
	bpy.ops.object.empty_add(location=(gun_x, y_front + 1.0, gun_z))
	muzzle = bpy.context.active_object
	muzzle.name = "Muzzle"
	muzzle.parent = shield
	return shield


def render_preview(path):
	scene = bpy.context.scene
	scene.render.engine = "BLENDER_WORKBENCH"
	scene.display.shading.light = "STUDIO"
	scene.display.shading.color_type = "MATERIAL"
	scene.render.resolution_x = 900
	scene.render.resolution_y = 900
	scene.render.film_transparent = False
	world = bpy.data.worlds.new("World")
	scene.world = world
	world.color = (0.75, 0.78, 0.82)
	bpy.ops.object.camera_add(location=(2.6, 3.6, 1.2))
	cam = bpy.context.active_object
	direction = Vector((0.0, 0.4, 0.0)) - cam.location
	cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
	scene.camera = cam
	scene.render.filepath = path
	bpy.ops.render.render(write_still=True)


reset_scene()
build()
bpy.ops.export_scene.gltf(filepath=OUT_PATH, export_format="GLB", use_selection=False, export_apply=True)
if PREVIEW_PATH:
	render_preview(PREVIEW_PATH)
print("EXPORTED", OUT_PATH)
