# Aviator Gunship v3 boss — concept model (open octagonal cockpit, white armour).
# Run: Blender -b --factory-startup -P build_gunship_v3.py -- '{"out":"<dir>"}'
# Builds a levitating gunship (2 wing rocket pods, 2 gatlings, 1 front laser eye) piloted
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


LASER = P.get("laser_col", (1.0, 0.07, 0.0))
THRUST = P.get("thrust_col", (0.35, 0.85, 1.0))
M_LASER = glow_mat("Laser_Glow", LASER, 9)
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


M_LASER_CORE = glow_mat("Laser_Core", (1.0, 0.75, 0.4), 25)

def ring_z(rx, ry, z, n=8, cx=0.0, cy=0.0, rot=math.pi / 8):
    return [(cx + rx * math.cos(2 * math.pi * i / n + rot), cy + ry * math.sin(2 * math.pi * i / n + rot), z) for i in range(n)]


def slab(c0, c1, t):
    """chunky bevelled armour-plate cross-section in (y, z)."""
    c = c1 - c0
    return [(c0, 0), (c0 + .12 * c, t * .5), (c1 - .06 * c, t * .5), (c1, 0), (c1 - .06 * c, -t * .5), (c0 + .12 * c, -t * .5)]


def plate_wing(name, sec, sw, fn=None, parent=None):
    profs = [[(x, y, z + zz) for (y, zz) in slab(a, b, t)] for (x, a, b, t, z) in sec]
    return finish(loft(profs), name, sw, fn=fn, parent=parent, smooth=False)


def plate_fin(name, sec, sw, fn=None):
    profs = [[(zz, y, z) for (y, zz) in slab(a, b, t)] for (z, a, b, t) in sec]
    return finish(loft(profs), name, sw, fn=fn, smooth=False)


white_top = lambda p: "steel" if p.normal.z < -.3 else "white"

# ---------------------------------------------------------------- hull (faceted octagonal armour pod)
HULL = [(-2.75, 1.05, .8, 0), (-2.35, 1.65, 1.2, 0), (-1.2, 2.0, 1.4, .05), (0.7, 1.95, 1.38, .08),
        (1.9, 1.6, 1.1, .12), (2.8, 1.05, .72, .18), (3.2, .7, .45, .2)]
bm = loft([ring_y(y, rx, rz, zo, 8, rot=math.pi / 8) for (y, rx, rz, zo) in HULL])
cut = [f for f in bm.faces if (lambda c: c.z > 1.2 and -1.2 < c.y < .7 and abs(c.x) < .5)(f.calc_center_median())]
bmesh.ops.delete(bm, geom=cut, context="FACES")
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
HULL_FACES = [([v.co.copy() for v in f.verts], f.normal.copy(), f.calc_center_median()) for f in bm.faces]
finish(bm, "Hull", "white", smooth=False,
       fn=lambda p: "steel" if p.normal.z < -.3 else ("steel" if p.center.y < -2.3 or p.center.y > 2.75 else "white"))
# side vents
for s in (-1, 1):
    for k in range(3):
        box("HullVent_%d_%d" % (s, k), "dark", (s * 1.6, -1.95 + k * .26, .25), (.08, .14, .6))
    box("HullVentFrame_%d" % s, "steel", (s * 1.57, -1.69, .25), (.06, .95, .78))

# ---------------------------------------------------------------- open octagonal cockpit
CY, CZ = -.25, 1.37
rim = [ring_z(1.32, 1.42, .9, cy=CY), ring_z(1.24, 1.34, 1.66, cy=CY), ring_z(1.16, 1.26, 1.74, cy=CY),
       ring_z(.82, .94, 1.74, cy=CY), ring_z(.74, .86, 1.6, cy=CY), ring_z(.7, .82, .55, cy=CY)]
finish(loft(rim), "CockpitRim", "white", smooth=False,
       fn=lambda p: "dark" if math.hypot(p.center.x, (p.center.y - CY) * .9) < .95 and p.center.z < 1.62 else ("steel" if p.center.z > 1.62 else "white"))
box("Dashboard", "steel", (0, CY - .7, 1.42), (1.05, .32, .4), rot=(-25, 0, 0))
box("DashScreen", "dark", (0, CY - .82, 1.52), (.6, .04, .18), rot=(-25, 0, 0), mat=M_LASER)
box("YokeColumn", "dark", (0, CY - .72, 1.6), (.1, .1, .3))
box("YokeBar", "dark", (0, CY - .62, 1.68), (.85, .08, .08))
for s in (-1, 1):
    tube_y("YokeGrip_%s" % ("R" if s < 0 else "L"), "brown", CY - .7, CY - .55, .07, x=s * .4, z=1.68, n=8)
box("SeatBack", "brown2", (0, CY + .62, 1.35), (.8, .18, .9), rot=(-10, 0, 0))

# ---------------------------------------------------------------- laser eye (front centre)
las = empty("LaserCannon", (0, -2.75, .02))
tube_y("LaserHousing", "white", .05, -.25, 1.0, .95, parent=las, n=16)
torus_y("LaserOuterRing", "dark", -.27, .8, .13, parent=las)
disc("LaserLensBack", .7, (0, -.26, 0), None, parent=las, axis="Y", seg=16)
glow = torus_y("LaserGlowRing", "red", -.3, .56, .09, parent=las)
glow.data.materials.clear()
glow.data.materials.append(M_LASER)
bm = bmesh.new()
bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=8, radius=.36)
bmesh.ops.scale(bm, vec=(1, .45, 1), verts=bm.verts)
finish(bm, "LaserCore", "", loc=(0, -.3, 0), parent=las, mat=M_LASER_CORE)
empty("Muzzle_Laser", (0, -.5, 0), parent=las)

# ---------------------------------------------------------------- wings with top-mounted rocket pods
for s, tag in ((-1, "R"), (1, "L")):
    plate_wing("Wing_" + tag, [(s * 1.75, -1.3, 1.5, .5, .05), (s * 3.4, -.6, 1.7, .38, .2), (s * 4.7, .1, 1.75, .28, .3)], "white", fn=white_top)
    plate_wing("WingTip_" + tag, [(s * 4.68, .1, 1.75, .28, .3), (s * 5.0, .45, 1.6, .2, .32)], "steel")
    box("WingPanel_%s_0" % tag, "steel", (s * 3.0, .55, .45), (1.1, .9, .04), rot=(0, s * -5, 0))
    box("WingPanel_%s_1" % tag, "steel", (s * 4.15, 1.0, .53), (.6, .6, .04), rot=(0, s * -5, 0))
    # rocket pod on top of the wing
    pod = empty("RocketPod_" + tag, (s * 2.95, -.15, .9))
    box("RocketPylon_" + tag, "steel", (0, .2, -.32), (.3, .9, .3), parent=pod)
    box("RocketPodBody_" + tag, "white", (0, .1, 0), (.62, 1.7, .78), parent=pod, fn=white_top)
    box("RocketPodFace_" + tag, "dark", (0, -.77, 0), (.56, .08, .72), parent=pod)
    box("RocketPodBand_" + tag, "gold", (0, .55, 0), (.68, .22, .84), parent=pod)
    box("RocketPodBand2_" + tag, "gold", (0, -.45, 0), (.68, .12, .84), parent=pod)
    for k, oz in enumerate((.18, -.18)):
        finish(loft([ring_y(-.7, .12, .12, oz, 8), ring_y(-.95, .12, .12, oz, 8), ring_y(-1.12, .02, .02, oz, 8)]),
               "Rocket_%s_%d" % (tag, k), "red", parent=pod)
        empty("Muzzle_Rocket_%s_%d" % (tag, k), (0, -1.15, oz), parent=pod)
    # gatling under the wing root
    g = empty("GunCannon_" + tag, (s * 2.05, -1.25, -.3))
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=6, radius=.36)
    finish(bm, "GunMount_" + tag, "dark", parent=g)
    tube_y("GunHousing_" + tag, "steel", .1, -.6, .3, .27, parent=g, n=10)
    tube_y("GunCollar_" + tag, "dark", -.55, -.7, .3, parent=g, n=10)
    sp = empty("GunBarrels_" + tag, (0, -.7, 0), parent=g)
    for k in range(6):
        a = math.radians(60 * k)
        tube_y("GunBarrel_%s_%d" % (tag, k), "dark", 0, -1.25, .06, x=.15 * math.cos(a), z=.15 * math.sin(a), parent=sp, n=6)
    for yy in (-.35, -1.05):
        tube_y("GunClamp_%s_%s" % (tag, yy), "steel", yy, yy - .1, .25, parent=sp, n=10)
    empty("Muzzle_Gun_" + tag, (0, -2.0, 0), parent=g)

# ---------------------------------------------------------------- tail: canted twin fins + stabilisers
for s, tag in ((-1, "R"), (1, "L")):
    f = plate_fin("TailFin_" + tag, [(0, 1.3, 3.15, .3), (1.25, 2.35, 3.4, .2), (1.6, 2.75, 3.45, .14)], "white",
                  fn=lambda p: "steel" if p.center.z > 1.0 else "white")
    f.location = (s * .55, 0, .95)
    f.rotation_euler = (0, s * math.radians(28), 0)
    plate_wing("Stabilizer_" + tag, [(s * .9, 2.2, 3.3, .24, .35), (s * 2.3, 2.75, 3.35, .14, .45)], "white", fn=white_top)
tube_y("TailExhaust", "dark", 3.15, 3.45, .55, .45, z=.2, n=8, cap=False)
disc("TailExhaustGlow", .45, (0, 3.35, .2), M_THRUST, axis="Y", seg=8)

# ---------------------------------------------------------------- hover thrusters (belly + under wings)
VENTS = [("HoverThruster_C", (0, .2, -1.25), .6), ("HoverThruster_R", (-3.7, .75, -.05), .32), ("HoverThruster_L", (3.7, .75, -.05), .32)]
for nm, loc, r in VENTS:
    t = empty(nm, loc)
    bm = loft([[(r * 1.2 * math.cos(2 * math.pi * i / 12), r * 1.2 * math.sin(2 * math.pi * i / 12), .2) for i in range(12)],
               [(r * 1.25 * math.cos(2 * math.pi * i / 12), r * 1.25 * math.sin(2 * math.pi * i / 12), -.12) for i in range(12)]])
    finish(bm, nm + "_Ring", "dark", parent=t)
    disc(nm + "_Glow", r, (0, 0, -.11), M_THRUST, parent=t)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=False, segments=12, radius1=r * .45, radius2=r * 1.05, depth=1.0)
    bmesh.ops.translate(bm, vec=(0, 0, -.62), verts=bm.verts)
    finish(bm, nm + "_Cone", "", parent=t, mat=M_THRUST_CONE, smooth=False)


# ---------------------------------------------------------------- surface details: metal plates, rivets, vents, lights
MAT_METAL = atlas_mat()
MAT_METAL.name = "AviatorGunship_Metal"
_mb = MAT_METAL.node_tree.nodes["Principled BSDF"]
_mb.inputs["Metallic"].default_value = P.get("metal", .3)
_mb.inputs["Roughness"].default_value = .38
M_NAV_R = glow_mat("NavLight_Red", (1, .05, .05), 8)
M_NAV_G = glow_mat("NavLight_Green", (.1, 1, .25), 8)


def plate_k(n, c):
    """inset factor for the hull facets that get a raised metal plate (None = bare)."""
    if -2.35 < c.y < -1.2 and .45 < n.z < .92:
        return .78
    if -1.2 < c.y < .7 and abs(n.x) > .9:
        return .8
    if .7 < c.y < 1.9 and .45 < n.z < .88:
        return .76
    if .7 < c.y < 1.9 and n.z >= .88:
        return .72
    return None


pbm, rbm = bmesh.new(), bmesh.new()
back_plate = None
for verts, n, c in HULL_FACES:
    k = plate_k(n, c)
    if k is None:
        continue
    base = [pbm.verts.new(c + (v - c) * k + n * .005) for v in verts]
    top = [pbm.verts.new(c + (v - c) * (k - .05) + n * .055) for v in verts]
    pbm.faces.new(top)
    for i in range(len(verts)):
        j = (i + 1) % len(verts)
        pbm.faces.new((base[i], base[j], top[j], top[i]))
    for v in verts:
        bmesh.ops.create_icosphere(rbm, subdivisions=1, radius=.035, matrix=Matrix.Translation(c + (v - c) * (k - .13) + n * .06))
    if n.z >= .88 and c.y > .7:
        back_plate = (c, n)
plates = finish(pbm, "ArmorPlates", "", mat=MAT_METAL, smooth=False)
paint(plates, "steel")
for d in plates.data.uv_layers[0].data:  # one even mid-grey tone from the steel swatch
    d.uv.y = P.get("plate_v", .962)
rivets = finish(rbm, "Rivets", "", mat=MAT_METAL, smooth=False)
paint(rivets, "dark")
if back_plate:  # cooling vent on the rear top plate
    c, n = back_plate
    for k in range(4):
        box("BackVent_%d" % k, "dark", c + n * .08 + Vector((0, -.33 + k * .22, 0)), (.75, .09, .05))
# bolts on the cockpit rim corners
bbm = bmesh.new()
for i in range(8):
    a = math.pi / 8 + i * math.pi / 4
    bmesh.ops.create_icosphere(bbm, subdivisions=1, radius=.06, matrix=Matrix.Translation((.99 * math.cos(a), CY + 1.1 * math.sin(a), 1.76)))
paint(finish(bbm, "RimBolts", "", mat=MAT_METAL, smooth=False), "steel")
# metallic finish on the existing grey panels
for o in bpy.data.objects:
    if o.name.startswith(("WingPanel_", "HullVentFrame_", "GunHousing_", "GunClamp_", "RocketPylon_")):
        o.data.materials.clear()
        o.data.materials.append(MAT_METAL)
# wingtip navigation lights (port red, starboard green) + dorsal antenna
for s, tag, m in ((1, "L", M_NAV_R), (-1, "R", M_NAV_G)):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=.1)
    finish(bm, "NavLight_" + tag, "", loc=(s * 5.0, 1.05, .33), mat=m, smooth=False)
pipe("Antenna", "dark", [(.42, 1.25, 1.2), (.44, 1.35, 2.05)], .03, n=6)
bm = bmesh.new()
bmesh.ops.create_icosphere(bm, subdivisions=1, radius=.07)
finish(bm, "AntennaTip", "", loc=(.44, 1.35, 2.1), mat=M_NAV_R, smooth=False)

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
    l2 = tube_y("GoggleGlass_%d" % s, "steel", -.13, -.15, .11 * GS, parent=gog, n=10)
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


light("SUN", (-6, -8, 12), 2.4, (1, 0.96, 0.9))
light("AREA", (8, 10, 9), 2500, (0.85, 0.9, 1.0), 10)
light("AREA", (-9, -6, 4), 1200, (1, 0.85, 0.75), 8)
for nm, loc, col, e in (("LaserL", (0, -4.0, HOVER), LASER, 500), ("ThrustL", (0, 0, HOVER - 2.0), THRUST, 500)):
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
    "view_hero": [(-8, -11, 9), (0, -.3, HOVER), 40],
    "view_front": [(0, -18, HOVER + 1.2), (0, 0, HOVER), 40],
    "view_side": [(17, -1, HOVER + .6), (0, -.3, HOVER), 40],
    "view_top": [(0, -.01, 22), (0, 0, HOVER), 40],
    "view_back": [(9, 12, 8.5), (0, 0, HOVER), 40],
    "view_pilot": [(-3.6, -6.0, HOVER + 4.0), (0, -.4, HOVER + 1.5), 45],
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
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "aviator_gunship_v3.blend"))
print("RES ok", len([o for o in bpy.data.objects if o.type == "MESH"]), "meshes")
