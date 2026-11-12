# Aviator Hover Gunship boss — concept model.
# Run: Blender -b --factory-startup -P build_hoverpod.py -- '{"out":"<dir>"}'
# Builds a levitating gunship pod (2 rocket launchers, 2 chin gatlings, 1 belly laser) piloted
# by the AvianSwordsman, UV-mapped onto the avian KayKit gradient atlas, then renders
# preview views and saves the .blend.
import bpy, bmesh, math, sys, json, os
from mathutils import Vector, Matrix, Euler

A = "/Users/ahmedkulovic/Documents/games/arm-carriers/assets/"
HERE = os.path.dirname(os.path.abspath(__file__))
P = json.loads(sys.argv[sys.argv.index("--") + 1]) if "--" in sys.argv else {}
OUT = P.get("out", HERE)
HOVER = P.get("hover", 3.0)

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene

# ---------------------------------------------------------------- atlas
ATLAS = bpy.data.images.load(A + "characters/avian_swordsman/AvianSwordsman_avianswordsman_texture.png")
SW = {"blue": (0, 0), "white": (1, 0), "dark": (2, 0), "yellow": (3, 0), "steel": (4, 0),
      "green": (5, 0), "brown": (6, 0), "tan": (7, 0), "white2": (0, 1), "red": (1, 1),
      "gold": (2, 1), "orange": (3, 1), "paleblue": (6, 1), "brown2": (7, 1), "tan2": (5, 1)}


def atlas_mat():
    m = bpy.data.materials.new("AviatorGunship_Atlas")
    m.use_nodes = True
    nt = m.node_tree
    bs = nt.nodes["Principled BSDF"]
    bs.inputs["Roughness"].default_value = 0.75
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = ATLAS
    nt.links.new(t.outputs["Color"], bs.inputs["Base Color"])
    return m


MAT = atlas_mat()


def glow_mat(name, col, strength, alpha=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bs = nt.nodes["Principled BSDF"]
    bs.inputs["Base Color"].default_value = (*col, 1)
    bs.inputs["Emission Color"].default_value = (*col, 1)
    bs.inputs["Emission Strength"].default_value = strength
    bs.inputs["Alpha"].default_value = alpha
    return m


LASER = P.get("laser_col", (1.0, 0.04, 0.08))
THRUST = P.get("thrust_col", (0.35, 0.85, 1.0))
M_LASER = glow_mat("Laser_Glow", LASER, 5)
M_THRUST = glow_mat("Thruster_Glow", THRUST, 10)
M_THRUST_CONE = glow_mat("Thruster_Cone", THRUST, 2, 0.1)

ROOT = bpy.data.objects.new("AviatorGunship", None)
sc.collection.objects.link(ROOT)
ROOT.location = (0, 0, HOVER)


def paint(obj, sw, fn=None):
    """UV every face onto an atlas swatch; vertical gradient follows object-local Z."""
    me = obj.data
    uv = me.uv_layers.new(name="UVMap")
    zs = [v.co.z for v in me.vertices]
    z0, z1 = min(zs), max(zs)
    for poly in me.polygons:
        s = fn(poly) if fn else sw
        c, r = SW[s]
        u = (c + 0.5) / 8
        vlo = 0.75 if r == 0 else 0.5
        for li in poly.loop_indices:
            z = me.vertices[me.loops[li].vertex_index].co.z
            t = (z - z0) / (z1 - z0 + 1e-6)
            uv.data[li].uv = (u, vlo + 0.03 + t * 0.19)


def finish(bm, name, sw, loc=(0, 0, 0), parent=None, fn=None, mat=None, smooth=True):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    sc.collection.objects.link(o)
    o.parent = parent or ROOT
    o.location = loc
    me.materials.append(mat or MAT)
    if mat is None:
        paint(o, sw, fn)
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
        if hasattr(me, "set_sharp_from_angle"):
            me.set_sharp_from_angle(angle=math.radians(35))
    return o


def loft(profiles, cap=True):
    """profiles: list of point lists (same length); consecutive profiles are bridged."""
    bm = bmesh.new()
    rings = [[bm.verts.new(p) for p in prof] for prof in profiles]
    n = len(profiles[0])
    for a, b in zip(rings, rings[1:]):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b[j], b[i]))
    if cap:
        bm.faces.new(rings[0])
        bm.faces.new(list(reversed(rings[-1])))
    return bm


def ring_y(y, rx, rz, zo=0.0, n=12, x0=0.0, rot=0.0):
    return [(x0 + rx * math.cos(2 * math.pi * i / n + rot), y, zo + rz * math.sin(2 * math.pi * i / n + rot)) for i in range(n)]


def tube_y(name, sw, y0, y1, r0, r1=None, x=0, z=0, n=12, parent=None, fn=None, mat=None, cap=True):
    r1 = r0 if r1 is None else r1
    bm = loft([ring_y(y0, r0, r0, z, n, x), ring_y(y1, r1, r1, z, n, x)], cap=cap)
    return finish(bm, name, sw, parent=parent, fn=fn, mat=mat)


def torus_y(name, sw, y, R, r, x=0, z=0, parent=None, n=16, m=6):
    bm = bmesh.new()
    rings = []
    for i in range(n):
        a = 2 * math.pi * i / n
        c = Vector((x + R * math.cos(a), y, z + R * math.sin(a)))
        d = Vector((math.cos(a), 0, math.sin(a)))
        rings.append([bm.verts.new(c + d * r * math.cos(2 * math.pi * k / m) + Vector((0, r * math.sin(2 * math.pi * k / m), 0))) for k in range(m)])
    for i in range(n):
        a, b = rings[i], rings[(i + 1) % n]
        for k in range(m):
            kk = (k + 1) % m
            bm.faces.new((a[k], a[kk], b[kk], b[k]))
    return finish(bm, name, sw, parent=parent)


def box(name, sw, center, size, rot=(0, 0, 0), parent=None, fn=None, mat=None):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    M = Matrix.Translation(center) @ Euler([math.radians(r) for r in rot]).to_matrix().to_4x4() @ Matrix.Diagonal((*size, 1))
    bmesh.ops.transform(bm, matrix=M, verts=bm.verts)
    return finish(bm, name, sw, parent=parent, fn=fn, mat=mat, smooth=False)


def airfoil(c0, c1, t):
    """6-point airfoil cross-section in (y, z) from leading edge c0 to trailing edge c1."""
    c = c1 - c0
    return [(c0, 0), (c0 + 0.15 * c, t * 0.5), (c0 + 0.6 * c, t * 0.4), (c1, 0), (c0 + 0.6 * c, -t * 0.25), (c0 + 0.15 * c, -t * 0.4)]


def wing(name, sec, sw, fn=None, parent=None):
    """sec: list of (x, y_le, y_te, thickness, z) spanwise sections."""
    profs = [[(x, y, z + zz) for (y, zz) in airfoil(a, b, t)] for (x, a, b, t, z) in sec]
    return finish(loft(profs), name, sw, fn=fn, parent=parent)


def fin(name, sec, sw, fn=None):
    """vertical surface: sec = (z, y_le, y_te, thickness)."""
    profs = [[(zz, y, z) for (y, zz) in airfoil(a, b, t)] for (z, a, b, t) in sec]
    return finish(loft(profs), name, sw, fn=fn)


def empty(name, loc, parent=None):
    e = bpy.data.objects.new(name, None)
    sc.collection.objects.link(e)
    e.parent = parent or ROOT
    e.location = loc
    e.empty_display_size = 0.3
    return e



# ---------------------------------------------------------------- extra helpers
def pipe(name, sw, pts, r, n=8, parent=None):
    """tube swept along a polyline (ends capped)."""
    pts = [Vector(p) for p in pts]
    profs = []
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        a = Vector((0, 0, 1)) if abs(t.z) < .9 else Vector((1, 0, 0))
        u = t.cross(a).normalized()
        v = t.cross(u)
        profs.append([tuple(p + (u * math.cos(2 * math.pi * k / n) + v * math.sin(2 * math.pi * k / n)) * r) for k in range(n)])
    return finish(loft(profs), name, sw, parent=parent)


def bez(a, c, b, steps=8):
    a, c, b = Vector(a), Vector(c), Vector(b)
    return [(1 - t) ** 2 * a + 2 * (1 - t) * t * c + t * t * b for t in (i / steps for i in range(steps + 1))]


def disc(name, r, loc, mat, parent=None, axis="Z", seg=14, sw="dark"):
    bm = bmesh.new()
    bmesh.ops.create_circle(bm, cap_ends=True, radius=r, segments=seg)
    if axis == "Y":
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "X"))
    return finish(bm, name, sw, loc=loc, parent=parent, mat=mat, smooth=False)


M_GLASS = bpy.data.materials.new("Canopy_Glass")
M_GLASS.use_nodes = True
_g = M_GLASS.node_tree.nodes["Principled BSDF"]
_g.inputs["Base Color"].default_value = (0.55, 0.85, 1.0, 1)
_g.inputs["Roughness"].default_value = 0.05
_g.inputs["Alpha"].default_value = P.get("glass_alpha", 0.2)
_g.inputs["Emission Color"].default_value = (0.4, 0.75, 1.0, 1)
_g.inputs["Emission Strength"].default_value = 0.15
try:
    M_GLASS.surface_render_method = "BLENDED"
except Exception:
    pass

# ---------------------------------------------------------------- hull
HULL = [(-3.45, .25, .2, -.15), (-3.1, 1.1, .5, -.1), (-2.3, 1.85, .82, -.02), (-1.0, 2.25, 1.0, .05),
        (0.4, 2.35, 1.05, .1), (1.8, 2.1, .95, .15), (2.8, 1.5, .75, .2), (3.45, .65, .4, .25)]
finish(loft([ring_y(y, rx, rz, zo, 18, rot=math.pi / 18) for (y, rx, rz, zo) in HULL]), "Hull", "steel",
       fn=lambda p: "dark" if p.normal.z < -.35 else ("steel" if p.normal.z < .25 else "blue"))
# gold armour belt around the hull's widest line
out = [(rx * 1.035, y, zo) for (y, rx, rz, zo) in HULL] + [(-rx * 1.035, y, zo) for (y, rx, rz, zo) in reversed(HULL)]
belt = loft([[(x, y, z - .13) for (x, y, z) in out], [(x * 1.02, y, z) for (x, y, z) in out], [(x, y, z + .13) for (x, y, z) in out]], cap=False)
finish(belt, "ArmorBelt", "gold", smooth=False)
# beak-like nose plate
finish(loft([ring_y(y, rx * 1.04, rz * 1.04, zo, 18, rot=math.pi / 18) for (y, rx, rz, zo) in HULL[:2]]), "NosePlate", "gold",
       fn=lambda p: "dark" if p.normal.z < -.35 else "gold")
# dorsal fin
fin("DorsalFin", [(.75, 1.2, 3.1, .34), (1.7, 2.1, 3.25, .24), (2.45, 2.85, 3.4, .14)], "blue",
    fn=lambda p: "gold" if p.center.z > 2.2 else "blue")

# ---------------------------------------------------------------- canopy
CY, CZ = -.45, 1.08
cp = empty("Canopy", (0, CY, CZ))
torus_y("CanopyRing", "dark", 0, 1.0, .16, parent=cp).rotation_euler = (math.radians(90), 0, 0)
bpy.data.objects["CanopyRing"].scale = (1.22, 1.42, 1.3)
disc("CockpitFloor", 1.18, (0, 0, .02), None, parent=cp)
bpy.data.objects["CockpitFloor"].scale = (1.0, 1.18, 1)
bm = bmesh.new()
bmesh.ops.create_uvsphere(bm, u_segments=18, v_segments=10, radius=1.0)
bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -.01], context="VERTS")
bmesh.ops.scale(bm, vec=(1.2, 1.42, 1.85), verts=bm.verts)
finish(bm, "CanopyGlass", "", parent=cp, mat=M_GLASS)
for s in (-1, 1):  # canopy frame ribs
    k = math.sqrt(1 - (.55 / 1.2) ** 2) * 1.02
    pipe("CanopyRib_%d" % s, "gold", [(s * .56, 1.42 * k * math.cos(math.radians(t)), 1.85 * k * math.sin(math.radians(t))) for t in range(0, 181, 12)], .05, n=6, parent=cp)
# control yoke
box("YokeColumn", "dark", (0, -.8, .25), (.12, .12, .5), rot=(15, 0, 0), parent=cp)
box("YokeBar", "dark", (0, -.85, .5), (.85, .08, .08), parent=cp)
for s in (-1, 1):
    tube_y("YokeGrip_%s" % ("R" if s < 0 else "L"), "brown", -.92, -.77, .07, x=s * .4, z=.5, n=8, parent=cp)

# ---------------------------------------------------------------- side turbines
EX, EY, EZ = 2.95, .7, .05
for s, tag in ((-1, "R"), (1, "L")):
    e = empty("Turbine_" + tag, (s * EX, EY, EZ))
    rings = [(-1.75, .55), (-1.55, .82), (-.6, .9), (1.0, .82), (1.75, .62), (1.95, .55)]
    finish(loft([ring_y(y, r, r, 0, 16) for (y, r) in rings], cap=False), "TurbineShell_" + tag, "steel", parent=e,
           fn=lambda p: "dark" if p.normal.z < -.4 else ("gold" if p.center.y < -1.35 else "steel"))
    disc("TurbineIntake_" + tag, .56, (0, -1.6, 0), None, parent=e, axis="Y")
    fan = empty("TurbineFan_" + tag, (0, -1.5, 0), parent=e)
    finish(loft([ring_y(0, .2, .2, 0, 10), ring_y(-.3, .02, .02, 0, 10)]), "FanHub_" + tag, "gold", parent=fan)
    for k in range(6):
        a = math.radians(60 * k)
        b = box("FanBlade_%s_%d" % (tag, k), "steel", (0, 0, 0), (.16, .04, .38), parent=fan)
        b.location = (math.cos(a) * .32, .05, math.sin(a) * .32)
        b.rotation_euler = Euler((0, math.radians(90) - a, 0))
        b.rotation_euler.rotate_axis("Z", math.radians(30))
    disc("TurbineExhaust_" + tag, .5, (0, 1.9, 0), M_THRUST, parent=e, axis="Y")
    tube_y("ExhaustNozzle_" + tag, "dark", 1.85, 2.25, .55, .45, parent=e, n=16, cap=False)
    # pylon + hoses into the hull
    box("TurbinePylon_" + tag, "dark", (-s * .75, .1, 0), (.9, 1.6, .35), parent=e)
    for k, (dy, dz) in enumerate(((-.5, .55), (.55, .5))):
        pts = bez((-s * .25, dy, .82), (-s * .9, dy, 1.25), (-s * 1.6, dy - .1, .78))
        pipe("Hose_%s_%d" % (tag, k), "dark", [tuple(p) for p in pts], .11, parent=e)

# ---------------------------------------------------------------- hover vents (belly + turbines)
VENTS = [("HoverThruster_C", (0, .4, -.98), .55), ("HoverThruster_R", (-EX, EY + .2, EZ - .86), .4), ("HoverThruster_L", (EX, EY + .2, EZ - .86), .4)]
for nm, loc, r in VENTS:
    t = empty(nm, loc)
    bm = loft([[(r * 1.15 * math.cos(2 * math.pi * i / 14), r * 1.15 * math.sin(2 * math.pi * i / 14), .18) for i in range(14)],
               [(r * 1.2 * math.cos(2 * math.pi * i / 14), r * 1.2 * math.sin(2 * math.pi * i / 14), -.1) for i in range(14)]])
    finish(bm, nm + "_Ring", "dark", parent=t)
    disc(nm + "_Glow", r, (0, 0, -.09), M_THRUST, parent=t)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=False, segments=14, radius1=r * .45, radius2=r * 1.05, depth=1.0)
    bmesh.ops.translate(bm, vec=(0, 0, -.6), verts=bm.verts)
    finish(bm, nm + "_Cone", "", parent=t, mat=M_THRUST_CONE, smooth=False)

# ---------------------------------------------------------------- gun cannons (x2, chin gatlings)
for s, tag in ((-1, "R"), (1, "L")):
    g = empty("GunCannon_" + tag, (s * 1.35, -2.0, -.62))
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=.42)
    finish(bm, "GunMount_" + tag, "dark", parent=g)
    tube_y("GunHousing_" + tag, "steel", .1, -.75, .3, .26, parent=g, n=10)
    tube_y("GunCollar_" + tag, "gold", -.7, -.85, .3, parent=g, n=10)
    sp = empty("GunBarrels_" + tag, (0, -.85, 0), parent=g)
    for k in range(3):
        a = math.radians(90 + 120 * k)
        tube_y("GunBarrel_%s_%d" % (tag, k), "dark", 0, -1.05, .08, x=.14 * math.cos(a), z=.14 * math.sin(a), parent=sp, n=8)
    tube_y("GunBarrelClamp_" + tag, "steel", -.75, -.85, .27, parent=sp, n=10)
    empty("Muzzle_Gun_" + tag, (0, -1.95, 0), parent=g)

# ---------------------------------------------------------------- rocket launchers (x2, outboard of turbines)
for s, tag in ((-1, "R"), (1, "L")):
    pod = empty("RocketPod_" + tag, (s * (EX + 1.25), .2, .25))
    box("RocketMount_" + tag, "dark", (-s * .5, .3, -.05), (.5, .8, .3), parent=pod)
    finish(loft([[(x * .55, y, z * .5) for (x, z) in ((-1, -1), (1, -1), (1, 1), (-1, 1))] for y in (1.1, -1.2)]), "RocketBox_" + tag, "green", parent=pod, smooth=False)
    box("RocketBoxTrim_" + tag, "gold", (0, -1.0, 0), (1.18, .16, 1.08), parent=pod)
    for k, (ox, oz) in enumerate(((-.3, .24), (0, .24), (.3, .24), (-.3, -.24), (0, -.24), (.3, -.24))):
        tube_y("RocketTube_%s_%d" % (tag, k), "dark", -1.05, -1.25, .12, x=ox, z=oz, parent=pod, n=8)
        finish(loft([ring_y(-1.0, .085, .085, oz, 8, ox), ring_y(-1.32, .085, .085, oz, 8, ox), ring_y(-1.52, .01, .01, oz, 8, ox)]),
               "Rocket_%s_%d" % (tag, k), "red", parent=pod)
        empty("Muzzle_Rocket_%s_%d" % (tag, k), (ox, -1.55, oz), parent=pod)

# ---------------------------------------------------------------- belly laser (center)
las = empty("LaserCannon", (0, -2.35, -.78))
bm = bmesh.new()
bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=10, radius=.62)
finish(bm, "LaserTurret", "steel", parent=las, fn=lambda p: "gold" if abs(p.center.z) < .15 else "steel")
tube_y("LaserCollar", "gold", -.45, -.75, .42, .38, parent=las, n=14)
tube_y("LaserBarrel", "dark", -.75, -2.0, .24, .2, parent=las, n=12)
for k, y in enumerate((-1.0, -1.32, -1.64)):
    torus_y("LaserCoil_%d" % k, "orange", y, .28, .07, parent=las)
    finish(loft([ring_y(y - .035, .22, .22, 0, 12), ring_y(y + .035, .22, .22, 0, 12)]), "LaserCoilGlow_%d" % k, "", parent=las, mat=M_LASER)
tube_y("LaserEmitter", "steel", -1.95, -2.22, .3, .36, parent=las, n=12)
for k in range(3):
    a = math.radians(90 + 120 * k)
    finish(loft([ring_y(-2.12, .08, .08, .32 * math.sin(a), 6, .32 * math.cos(a)),
                 ring_y(-2.55, .05, .05, .25 * math.sin(a), 6, .25 * math.cos(a)),
                 ring_y(-2.78, .01, .01, .15 * math.sin(a), 6, .15 * math.cos(a))]), "LaserProng_%d" % k, "gold", parent=las)
bm = bmesh.new()
bmesh.ops.create_icosphere(bm, subdivisions=1, radius=.2)
finish(bm, "LaserCrystal", "", loc=(0, -2.3, 0), parent=las, mat=M_LASER, smooth=False)
empty("Muzzle_Laser", (0, -2.5, 0), parent=las)

# antenna
pipe("Antenna", "dark", [(.6, 2.3, .95), (.62, 2.4, 1.9)], .03, n=6)
bm = bmesh.new()
bmesh.ops.create_icosphere(bm, subdivisions=1, radius=.08)
finish(bm, "AntennaTip", "", loc=(.62, 2.4, 1.95), mat=M_LASER, smooth=False)


# ---------------------------------------------------------------- pilot
def imp(path, name):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    for o in list(new):
        if o.name.startswith("Icosphere"):
            new.remove(o)
            bpy.data.objects.remove(o, do_unlink=True)
    root = [o for o in new if o.parent is None][0]
    root.name = name
    return root, new


pilot, _ = imp(A + "characters/avian_swordsman/AvianSwordsman.glb", "Pilot")
pilot.parent = ROOT
pilot.location = (0, CY + .05, CZ - .22 - .41)
bpy.context.view_layer.update()


def rot_bone(arm, name, axis, deg):
    pb = arm.pose.bones[name]
    h = pb.head.copy()
    pb.matrix = Matrix.Translation(h) @ Matrix.Rotation(math.radians(deg), 4, axis) @ Matrix.Translation(-h) @ pb.matrix
    bpy.context.view_layer.update()


POSE = P.get("pose", [["upperleg.r", "X", -85], ["upperleg.l", "X", -85], ["lowerleg.r", "X", 85], ["lowerleg.l", "X", 85],
                      ["upperarm.r", "Z", 72], ["upperarm.r", "X", 18], ["upperarm.l", "Z", -72], ["upperarm.l", "X", 18],
                      ["lowerarm.r", "Z", 12], ["lowerarm.l", "Z", -12], ["spine", "X", 6], ["head", "X", -6]])
for b, ax, d in POSE:
    rot_bone(pilot, b, ax, d)

# aviator goggles on the head bone
gog = empty("PilotGoggles", (0, 0, 0))
gog.parent = pilot
gog.parent_type = "BONE"
gog.parent_bone = "head"
bpy.context.view_layer.update()
gog.matrix_world = pilot.matrix_world @ Matrix.Translation(Vector(P.get("gog", (0, -.02, 2.02))))
GS = P.get("gog_s", .9)
tube_y("GoggleStrap", "brown2", .06, -.06, .47 * GS, .47 * GS, z=0, parent=gog, n=16, cap=False).rotation_euler = (math.radians(90 + P.get("gog_tilt", -14)), 0, 0)
for s in (-1, 1):
    l = tube_y("GoggleLens_%d" % s, "gold", 0, -.14, .16 * GS, .15 * GS, parent=gog, n=10)
    l.location = (s * .19 * GS, -.5 * GS, .04)
    l2 = tube_y("GoggleGlass_%d" % s, "paleblue", -.13, -.15, .11 * GS, parent=gog, n=10)
    l2.location = (s * .19 * GS, -.5 * GS, .04)

# ---------------------------------------------------------------- staging: player for scale, floor, lights
if P.get("knight", True):
    kn, _ = imp(A + "models/Kaykit/characters/Knight.glb", "Player_ScaleRef")
    kn.location = P.get("kn", (5.5, -7.5, 0))
    kn.rotation_euler = (0, 0, math.radians(P.get("knr", 200)))
bpy.ops.mesh.primitive_plane_add(size=80)
fl = bpy.context.active_object
fl.name = "Floor"
fm = bpy.data.materials.new("Floor")
fm.use_nodes = True
fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.32, 0.36, 0.42, 1)
fl.data.materials.append(fm)
w = bpy.data.worlds.new("W")
sc.world = w
w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.45, 0.6, 0.8, 1)
w.node_tree.nodes["Background"].inputs[1].default_value = 0.6


def light(t, loc, e, col, size=5, tgt=(0, 0, 3)):
    d = bpy.data.lights.new("L", t)
    d.energy = e
    d.color = col
    if t == "AREA":
        d.size = size
    o = bpy.data.objects.new("L", d)
    sc.collection.objects.link(o)
    o.location = loc
    o.rotation_euler = (Vector(tgt) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    return o


light("SUN", (-6, -8, 12), 3.5, (1, 0.96, 0.9))
light("AREA", (8, 10, 9), 3500, (0.85, 0.9, 1.0), 10)
light("AREA", (-9, -6, 4), 1200, (1, 0.85, 0.75), 8)
for nm, loc, col, e in (("LaserL", (0, -5.3, HOVER - .8), LASER, 300), ("ThrustL", (0, 0, HOVER - 2.0), THRUST, 500)):
    d = bpy.data.lights.new(nm, "POINT")
    d.energy = e
    d.color = col
    o = bpy.data.objects.new(nm, d)
    sc.collection.objects.link(o)
    o.location = loc

sc.render.engine = "BLENDER_EEVEE"
sc.render.resolution_x = P.get("rx", 1200)
sc.render.resolution_y = P.get("ry", 900)
sc.view_settings.view_transform = "AgX"
try:
    sc.eevee.taa_render_samples = 32
except Exception:
    pass
cam_d = bpy.data.cameras.new("C")
cam = bpy.data.objects.new("Cam", cam_d)
sc.collection.objects.link(cam)
sc.camera = cam
views = P.get("views", {
    "view_hero": [(-9, -12, 7), (0, -.6, HOVER - .1), 42],
    "view_front": [(0, -18, HOVER + 1.2), (0, 0, HOVER), 40],
    "view_side": [(17, -1, HOVER + .6), (0, -.3, HOVER), 40],
    "view_top": [(0, -.01, 22), (0, 0, HOVER), 40],
    "view_back": [(9, 12, 8.5), (0, 0, HOVER), 35],
    "view_pilot": [(-3.4, -6.2, HOVER + 2.8), (0, -.4, HOVER + 1.2), 45],
})
only = P.get("only")
for name, (loc, tgt, lens) in views.items():
    if only and name not in only:
        continue
    cam_d.lens = lens
    cam.location = loc
    cam.rotation_euler = (Vector(tgt) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
if P.get("save", True):
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "aviator_gunship.blend"))
print("RES ok", len([o for o in bpy.data.objects if o.type == "MESH"]), "meshes")
