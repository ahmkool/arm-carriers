# Aviator Warplane boss — concept model.
# Run: Blender -b --factory-startup -P build_warplane.py -- '{"out":"<dir>"}'
# Builds a hovering war plane (2 rocket pods, 2 gun cannons, 1 nose laser) piloted
# by the AvianSwordsman, UV-mapped onto the avian KayKit gradient atlas, then renders
# preview views and saves the .blend.
import bpy, bmesh, math, sys, json, os
from mathutils import Vector, Matrix, Euler

A = "/Users/ahmedkulovic/Documents/games/arm-carriers/assets/"
HERE = os.path.dirname(os.path.abspath(__file__))
P = json.loads(sys.argv[sys.argv.index("--") + 1]) if "--" in sys.argv else {}
OUT = P.get("out", HERE)
HOVER = P.get("hover", 3.4)

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene

# ---------------------------------------------------------------- atlas
ATLAS = bpy.data.images.load(A + "characters/avian_swordsman/AvianSwordsman_avianswordsman_texture.png")
SW = {"blue": (0, 0), "white": (1, 0), "dark": (2, 0), "yellow": (3, 0), "steel": (4, 0),
      "green": (5, 0), "brown": (6, 0), "tan": (7, 0), "white2": (0, 1), "red": (1, 1),
      "gold": (2, 1), "orange": (3, 1), "paleblue": (6, 1), "brown2": (7, 1), "tan2": (5, 1)}


def atlas_mat():
    m = bpy.data.materials.new("AviatorWarplane_Atlas")
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

ROOT = bpy.data.objects.new("AviatorWarplane", None)
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


# ---------------------------------------------------------------- fuselage
FUS = [(-4.1, .5, .5, -.05), (-3.6, .85, .82, 0), (-2.6, 1.1, 1.0, .02), (-1.0, 1.18, 1.05, .05),
       (0.6, 1.12, 1.0, .08), (2.0, .9, .8, .2), (3.4, .55, .5, .38), (4.7, .22, .25, .55)]
fus = finish(loft([ring_y(y, rx, rz, zo, 14, rot=math.pi / 14) for (y, rx, rz, zo) in FUS]), "Fuselage", "blue",
             fn=lambda p: "white" if p.center.z < -0.45 else ("gold" if 2.55 < p.center.y < 2.95 else "blue"))
# nose cowl band
tube_y("NoseBand", "gold", -4.12, -3.75, .56, .8, z=-.03, n=14)

# cockpit
CY, CZ = 0.3, 1.1
torus_y("CockpitRim", "brown", 0, .66, .13).rotation_euler = (math.radians(90), 0, 0)
bpy.data.objects["CockpitRim"].location = (0, CY, CZ + .02)
bpy.data.objects["CockpitRim"].scale = (1, 1.25, 1)
tube_y("CockpitHole", "dark", 0, .1, .64, n=16).rotation_euler = (math.radians(90), 0, 0)
bpy.data.objects["CockpitHole"].location = (0, CY, CZ - .04)
bpy.data.objects["CockpitHole"].scale = (1, 1.25, 1)
box("Headrest", "brown2", (0, CY + .82, CZ + .35), (.7, .22, .75), rot=(-12, 0, 0))
# windscreen: 3 tilted panes + frame
for i, a in enumerate((-32, 0, 32)):
    w = box("Windscreen_%d" % i, "paleblue", (0, 0, 0), (.5, .04, .36), rot=(-35, 0, a))
    w.location = (math.sin(math.radians(a)) * .48, CY - 1.12 + (abs(a) / 32) * .2, CZ + .2)
box("WindscreenFrame", "gold", (0, CY - 1.12, CZ + .05), (1.25, .12, .1))
# control yoke
box("YokeColumn", "dark", (0, CY - .72, CZ + .2), (.12, .12, .45), rot=(25, 0, 0))
box("YokeBar", "dark", (0, CY - .58, CZ + .42), (.9, .08, .08))
for s in (-1, 1):
    tube_y("YokeGrip_%s" % ("R" if s < 0 else "L"), "brown", CY - .65, CY - .5, .07, x=s * .42, z=CZ + .42, n=8)

# ---------------------------------------------------------------- wings & tail
blue_top = lambda p: "white" if p.normal.z < -0.3 else "blue"
for s, tag in ((-1, "R"), (1, "L")):
    wing("Wing_" + tag, [(s * .9, -1.7, 1.5, .5, -.35), (s * 3.2, -1.15, 1.15, .36, -.22), (s * 5.4, -.6, .8, .22, -.1)], "blue", fn=blue_top)
    wing("WingTip_" + tag, [(s * 5.38, -.6, .8, .22, -.1), (s * 5.85, -.35, .55, .14, -.05)], "gold")
    wing("Stabilizer_" + tag, [(s * .2, 3.25, 4.55, .22, .55), (s * 2.3, 3.95, 4.55, .12, .62)], "blue", fn=blue_top)
fin("TailFin", [(.6, 3.0, 4.75, .3), (1.9, 3.75, 4.7, .2), (2.35, 4.05, 4.65, .14)], "blue",
    fn=lambda p: "gold" if p.center.z > 1.95 else "blue")

# ---------------------------------------------------------------- engines + propellers
NX, NZ = 2.7, -.12
for s, tag in ((-1, "R"), (1, "L")):
    x = s * NX
    rings = [(-1.85, .38), (-1.6, .58), (-0.8, .62), (0.5, .52), (1.55, .2)]
    finish(loft([ring_y(y, r, r, NZ, 12, x) for (y, r) in rings]), "Nacelle_" + tag, "steel",
           fn=lambda p: "red" if p.center.y < -1.45 else "steel")
    tube_y("Exhaust_" + tag, "dark", .9, 1.25, .12, .1, x=x + s * .55, z=NZ + .1, n=8)
    hub = empty("Propeller_" + tag, (x, -2.0, NZ))
    finish(loft([ring_y(0, .3, .3, 0, 10), ring_y(-.45, .14, .14, 0, 10), ring_y(-.62, .02, .02, 0, 10)]), "Spinner_" + tag, "gold", parent=hub)
    for k in range(3):
        a = math.radians(90 + 120 * k)
        b = box("Blade_%s_%d" % (tag, k), "brown2", (0, 0, 0), (.26, .06, 1.25), rot=(0, 0, 0), parent=hub)
        b.location = (math.cos(a) * .75, .05, math.sin(a) * .75)
        b.rotation_euler = Euler((0, math.radians(90) - a, 0))
        b.rotation_euler.rotate_axis("Z", math.radians(18))

# ---------------------------------------------------------------- gun cannons (x2)
for s, tag in ((-1, "R"), (1, "L")):
    g = empty("GunCannon_" + tag, (s * 1.38, -1.1, -.78))
    finish(loft([ring_y(1.0, .2, .2, 0, 10), ring_y(.7, .34, .34, 0, 10), ring_y(-.9, .34, .34, 0, 10), ring_y(-1.15, .24, .24, 0, 10)]),
           "GunHousing_" + tag, "steel", parent=g)
    tube_y("GunJacket_" + tag, "steel", -1.1, -2.1, .17, parent=g, n=10)
    for k in range(4):
        tube_y("GunVent_%s_%d" % (tag, k), "dark", -1.25 - k * .22, -1.36 - k * .22, .19, parent=g, n=10)
    tube_y("GunBarrel_" + tag, "dark", -2.1, -2.7, .1, parent=g, n=8)
    tube_y("GunMuzzle_" + tag, "dark", -2.65, -2.9, .15, .13, parent=g, n=8)
    empty("Muzzle_Gun_" + tag, (0, -2.95, 0), parent=g)

# ---------------------------------------------------------------- rocket pods (x2)
RX, RZ = 4.35, -.82
for s, tag in ((-1, "R"), (1, "L")):
    pod = empty("RocketPod_" + tag, (s * RX, -.5, RZ))
    box("RocketPylon_" + tag, "steel", (0, .2, .45), (.16, .9, .5), parent=pod)
    finish(loft([ring_y(1.2, .2, .2, 0, 12), ring_y(.9, .42, .42, 0, 12), ring_y(-1.0, .42, .42, 0, 12), ring_y(-1.15, .36, .36, 0, 12)]),
           "RocketPodBody_" + tag, "green", parent=pod, fn=lambda p: "gold" if -0.8 < p.center.y < -0.55 else "green")
    for k, (ox, oz) in enumerate(((-.16, .16), (.16, .16), (-.16, -.16), (.16, -.16))):
        tube_y("RocketTube_%s_%d" % (tag, k), "dark", -1.1, -1.25, .14, x=ox, z=oz, parent=pod, n=8)
        finish(loft([ring_y(-1.0, .1, .1, oz, 8, ox), ring_y(-1.3, .1, .1, oz, 8, ox), ring_y(-1.5, .01, .01, oz, 8, ox)]),
               "Rocket_%s_%d" % (tag, k), "red", parent=pod)
        empty("Muzzle_Rocket_%s_%d" % (tag, k), (ox, -1.5, oz), parent=pod)

# ---------------------------------------------------------------- nose laser
las = empty("LaserCannon", (0, -4.05, -.05))
tube_y("LaserCollar", "gold", 0, -.35, .55, .5, parent=las, n=14)
tube_y("LaserBarrel", "dark", -.35, -1.7, .28, .24, parent=las, n=12)
for k, y in enumerate((-.6, -.95, -1.3)):
    torus_y("LaserCoil_%d" % k, "orange", y, .32, .08, parent=las)
    finish(loft([ring_y(y - .04, .26, .26, 0, 12), ring_y(y + .04, .26, .26, 0, 12)]), "LaserCoilGlow_%d" % k, "", parent=las, mat=M_LASER)
tube_y("LaserEmitter", "steel", -1.65, -1.95, .36, .42, parent=las, n=12)
for k in range(3):
    a = math.radians(90 + 120 * k)
    pr = finish(loft([ring_y(-1.85, .09, .09, .38 * math.sin(a), 6, .38 * math.cos(a)),
                      ring_y(-2.35, .06, .06, .3 * math.sin(a), 6, .3 * math.cos(a)),
                      ring_y(-2.6, .01, .01, .18 * math.sin(a), 6, .18 * math.cos(a))]), "LaserProng_%d" % k, "gold", parent=las)
bm = bmesh.new()
bmesh.ops.create_icosphere(bm, subdivisions=1, radius=.24)
finish(bm, "LaserCrystal", "", loc=(0, -2.05, 0), parent=las, mat=M_LASER, smooth=False)
empty("Muzzle_Laser", (0, -2.3, 0), parent=las)

# ---------------------------------------------------------------- hover thrusters
for k, (x, y, z) in enumerate(((0, -2.2, -1.0), (0, 2.0, -.62), (-NX, .2, NZ - .58), (NX, .2, NZ - .58))):
    t = empty("HoverThruster_%d" % k, (x, y, z))
    bm = loft([[(0.42 * math.cos(2 * math.pi * i / 12), .42 * math.sin(2 * math.pi * i / 12), .15) for i in range(12)],
               [(0.46 * math.cos(2 * math.pi * i / 12), .46 * math.sin(2 * math.pi * i / 12), -.12) for i in range(12)]])
    finish(bm, "ThrusterRing_%d" % k, "steel", parent=t)
    bm = bmesh.new()
    bmesh.ops.create_circle(bm, cap_ends=True, radius=.36, segments=12)
    bmesh.ops.translate(bm, vec=(0, 0, -.11), verts=bm.verts)
    finish(bm, "ThrusterGlow_%d" % k, "", parent=t, mat=M_THRUST, smooth=False)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=False, segments=12, radius1=.16, radius2=.4, depth=1.0)
    bmesh.ops.translate(bm, vec=(0, 0, -.62), verts=bm.verts)
    finish(bm, "ThrusterCone_%d" % k, "", parent=t, mat=M_THRUST_CONE, smooth=False)

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
pilot.location = (0, CY, CZ + .04 - .41)
bpy.context.view_layer.update()


def rot_bone(arm, name, axis, deg):
    pb = arm.pose.bones[name]
    h = pb.head.copy()
    pb.matrix = Matrix.Translation(h) @ Matrix.Rotation(math.radians(deg), 4, axis) @ Matrix.Translation(-h) @ pb.matrix
    bpy.context.view_layer.update()


POSE = P.get("pose", [["upperleg.r", "X", -85], ["upperleg.l", "X", -85], ["lowerleg.r", "X", 85], ["lowerleg.l", "X", 85],
                      ["upperarm.r", "Z", 72], ["upperarm.r", "X", 38], ["upperarm.l", "Z", -72], ["upperarm.l", "X", 38],
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
for nm, loc, col, e in (("LaserL", (0, -6.3, HOVER - .05), LASER, 300), ("ThrustL", (0, 0, HOVER - 2.0), THRUST, 500)):
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
    "view_hero": [(-10, -13, 8), (0, -.6, HOVER - .2), 42],
    "view_front": [(0, -18, HOVER + 1.2), (0, 0, HOVER), 40],
    "view_side": [(17, -1, HOVER + .6), (0, -.3, HOVER), 40],
    "view_top": [(0, -.01, 24), (0, 0, HOVER), 40],
    "view_back": [(9, 12, 8.5), (0, 0, HOVER), 35],
    "view_pilot": [(-3.2, -5.2, HOVER + 3.4), (0, .2, HOVER + 1.6), 45],
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
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "aviator_warplane.blend"))
print("RES ok", len([o for o in bpy.data.objects if o.type == "MESH"]), "meshes")
