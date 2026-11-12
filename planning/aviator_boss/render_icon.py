# Renders the boss health bar icon (420 px, transparent) from aviator_gunship_v3.blend.
# Run: Blender -b aviator_gunship_v3.blend -P render_icon.py
import bpy
from mathutils import Vector
sc = bpy.context.scene
for o in list(bpy.data.objects):
    top = o
    while top.parent:
        top = top.parent
    if o.name == "Floor" or top.name == "Player_ScaleRef":
        o.hide_render = True
sc.render.film_transparent = True
sc.render.resolution_x = sc.render.resolution_y = 420
cam = sc.camera
cam.data.lens = 50
root = bpy.data.objects["AviatorGunship"].matrix_world.translation
target = root + Vector((0, -0.6, 0.6))
cam.location = root + Vector((-6.5, -11.5, 6.5))
cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
sc.render.filepath = "/Users/ahmedkulovic/Documents/games/arm-carriers/assets/sprites/ui/icons/aviator_gunship_boss_icon.png"
bpy.ops.render.render(write_still=True)
print("RES icon")
