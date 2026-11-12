# Exports the v3 gunship to the game: the model only (no floor, lights or scale reference), with the pilot's
# seated pose baked into plain meshes and the root at the origin.
# Run: Blender -b aviator_gunship_v3.blend --factory-startup -P export_gunship.py
import bpy
import os

OUT = "/Users/ahmedkulovic/Documents/games/arm-carriers/assets/models/enemies/aviator_gunship/aviator_gunship.glb"
ROOT_NAME = "AviatorGunship"

root = bpy.data.objects[ROOT_NAME]
pilot = bpy.data.objects["Pilot"]
view_layer = bpy.context.view_layer


def descendants(obj):
    out = []
    for child in obj.children:
        out.append(child)
        out.extend(descendants(child))
    return out


def unparent_keep(obj, new_parent=None):
    world = obj.matrix_world.copy()
    obj.parent = new_parent
    obj.matrix_world = world


# Bake the pilot's pose: apply each skinned mesh's armature modifier, then hang it straight off the root.
pilot_tree = descendants(pilot)
for obj in [o for o in pilot_tree if o.type == "MESH" and any(m.type == "ARMATURE" for m in o.modifiers)]:
    for mod in [m for m in obj.modifiers if m.type == "ARMATURE"]:
        with bpy.context.temp_override(object=obj, active_object=obj, selected_objects=[obj]):
            bpy.ops.object.modifier_apply(modifier=mod.name)
    unparent_keep(obj, root)
# The goggles ride on the head bone: re-hang them on the root before the armature goes.
for obj in [o for o in pilot_tree if o.parent == pilot and o.name.startswith("PilotGoggles")]:
    unparent_keep(obj, root)
for obj in [o for o in pilot_tree if o.parent == pilot]:
    unparent_keep(obj, root)
bpy.data.objects.remove(pilot, do_unlink=True)

# Drop everything that isn't part of the craft.
keep = {root} | set(descendants(root))
for obj in list(bpy.data.objects):
    if obj not in keep:
        bpy.data.objects.remove(obj, do_unlink=True)

root.location = (0, 0, 0)
view_layer.update()
for obj in bpy.data.objects:
    obj.select_set(True)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_yup=True, export_apply=True,
                          export_animations=False)
print("RES exported", len(bpy.data.objects), "objects")
