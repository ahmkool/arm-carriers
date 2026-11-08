import bpy, math, sys, json
from mathutils import Vector, Matrix, Euler
S="/private/tmp/claude-501/-Users-ahmedkulovic--claude-spares-spare-m9m8lS/9055e3b2-3cf5-43be-a5b3-314df696971b/scratchpad/boss/"
A="/Users/ahmedkulovic/Documents/games/arm-carriers/assets/"
K="/Users/ahmedkulovic/Documents/games/assets/The Complete KayKit Collection v8/"
MECH=K+"KayKit Mystery Monthly Series 5 (1.1)/1 - July 2024 - Combat Mech/"
bpy.ops.wm.read_factory_settings(use_empty=True)
sc=bpy.context.scene
def imp(path, name):
    before=set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new=[o for o in bpy.data.objects if o not in before]
    for o in list(new):
        if o.name.startswith("Icosphere"):
            new.remove(o); bpy.data.objects.remove(o, do_unlink=True)
    roots=[o for o in new if o.parent is None]
    if len(roots)==1: g=roots[0]
    else:
        g=bpy.data.objects.new(name,None); sc.collection.objects.link(g)
        for r in roots: r.parent=g
    g.name=name
    return g,new

P=json.loads(sys.argv[sys.argv.index("--")+1]) if "--" in sys.argv else {}
SCALE=P.get("scale",4.5)
mech,mobjs=imp(MECH+"characters/CombatMech.glb","FinalBoss")
mech.scale=(SCALE,)*3
tex=bpy.data.images.load(S+"overlord_texture.png")
for o in mobjs:
    if o.type=='MESH':
        for m in o.data.materials:
            for n in m.node_tree.nodes:
                if n.type=='TEX_IMAGE': n.image=tex
arm=mech
bpy.context.view_layer.update()
def rot_bone(name, axis, deg):
    pb=arm.pose.bones[name]
    h=pb.head.copy()
    R=Matrix.Translation(h)@Matrix.Rotation(math.radians(deg),4,axis)@Matrix.Translation(-h)
    pb.matrix=R@pb.matrix
    bpy.context.view_layer.update()
P=json.loads(sys.argv[sys.argv.index("--")+1]) if "--" in sys.argv else {}
pose=P.get("pose",{"upperarm.r":[("Y",-55),("Z",20)],"lowerarm.r":[("Z",45)],"upperarm.l":[("Y",55),("Z",-15)],"lowerarm.l":[("Z",-30)]})
for b,ops in pose.items():
    for ax,d in ops: rot_bone(b,ax,d)
def bone_world(name):
    pb=arm.pose.bones[name]; return arm.matrix_world@pb.matrix
def attach(obj, bone, loc=(0,0,0), rot=(0,0,0), s=1.0):
    obj.parent=arm
    if bone: obj.parent_type='BONE'; obj.parent_bone=bone
    obj.rotation_mode='XYZ'
    obj.location=loc; obj.rotation_euler=Euler([math.radians(r) for r in rot]); obj.scale=(s,)*3
# weapons in hands
mg,_=imp(MECH+"assets/gltf/CombatMech_Minigun.gltf","Boss_Minigun")
attach(mg,"handslot.r",*P.get("mg",[(0,0,0),(0,0,0),1.6]))
def worldify(obj, s, extra):
    bpy.context.view_layer.update()
    p=obj.matrix_world.translation.copy()
    obj.parent=None
    obj.matrix_world=Matrix.Translation(p)@Euler([math.radians(r) for r in extra]).to_matrix().to_4x4()@Matrix.Scale(SCALE*s,4)
    obj.parent=arm; obj.matrix_parent_inverse=arm.matrix_world.inverted()
worldify(mg,*P.get("mgw",[1.0,(0,0,0)]))
ax,_=imp(MECH+"assets/gltf/CombatMech_Axe.gltf","Boss_Axe")
attach(ax,"handslot.l",*P.get("ax",[(0,0,0),(0,0,0),1.8]))
worldify(ax,*P.get("axw",[1.0,(0,0,0)]))
# trophy rack on back (chest bone)
troph=[("golem",A+"models/weapon/enemies/golem_axe/golem_axe.glb"),("frost",A+"models/weapon/enemies/frost_golem_axe/FrostGolem_Axe_Large.gltf"),("scythe",A+"models/weapon/enemies/necromancer_scythe/Skeleton_Scythe.gltf"),("katana",A+"models/weapon/enemies/4gtn_katana/4GTN_Katana.gltf")]
tp=P.get("troph",{})
for k,f in troph:
    o,_=imp(f,"Trophy_"+k)
    attach(o,None,*tp.get(k,[(0,0,0),(0,0,0),0.5]))
for m in bpy.data.materials:
    if m.node_tree:
        for n in m.node_tree.nodes:
            if n.type=='TEX_IMAGE' and n.image and n.image.name.lower().startswith('combatmech'): n.image=tex
# reactor core
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=P.get("core_r",0.11))
core=bpy.context.active_object; core.name="Boss_Core"
cm=bpy.data.materials.new("CoreGlow"); cm.use_nodes=True
bs=cm.node_tree.nodes["Principled BSDF"]; bs.inputs["Base Color"].default_value=(1,0.3,0.05,1)
bs.inputs["Emission Color"].default_value=(1,0.25,0.03,1); bs.inputs["Emission Strength"].default_value=12
core.data.materials.append(cm)
attach(core,None,*P.get("core",[(0,0.05,-0.16),(0,0,0),1.0]))
pl=bpy.data.lights.new("CoreL",'POINT'); pl.energy=800; pl.color=(1,0.35,0.1); plo=bpy.data.objects.new("CoreL",pl); sc.collection.objects.link(plo); bpy.context.view_layer.update(); plo.location=core.matrix_world.translation+Vector((0,-1.2,0))
# scale reference: two knights carrying bazooka
KX,KY,KR=P.get("kn",[5,-6,20])
for i,x in enumerate([-1.3,1.3]):
    kn,_=imp(A+"models/Kaykit/characters/Knight.glb","Player_%d"%(i+1))
    kn.rotation_mode='XYZ'
    kn.location=(x+KX,KY,0); kn.rotation_euler=(0,0,math.radians(KR))
    for b,a_,d in [("upperarm.r","Y",-65),("upperarm.l","Y",65),("lowerarm.r","Z",80),("lowerarm.l","Z",-80)]:
        pb=kn.pose.bones.get(b)
        if pb:
            h=pb.head.copy(); pb.matrix=Matrix.Translation(h)@Matrix.Rotation(math.radians(d),4,a_)@Matrix.Translation(-h)@pb.matrix; bpy.context.view_layer.update()
bz,_=imp(A+"models/weapon/bazooka/bazooka.glb","Players_Bazooka")
bz.rotation_mode='XYZ'; bz.scale=(0.42,)*3; bz.location=(KX,KY,P.get("bzz",1.9)); bz.rotation_euler=(0,0,math.radians(KR+90))
# floor
bpy.ops.mesh.primitive_plane_add(size=60); fl=bpy.context.active_object
fm=bpy.data.materials.new("Floor"); fm.use_nodes=True; fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value=(0.06,0.065,0.08,1); fl.data.materials.append(fm)
# lights & world
w=bpy.data.worlds.new("W"); sc.world=w; w.use_nodes=True; w.node_tree.nodes["Background"].inputs[0].default_value=(0.03,0.035,0.05,1); w.node_tree.nodes["Background"].inputs[1].default_value=1.0
def light(t,loc,e,col,rot=(0,0,0),size=5):
    d=bpy.data.lights.new("L",t); d.energy=e; d.color=col
    if t=='AREA': d.size=size
    o=bpy.data.objects.new("L",d); sc.collection.objects.link(o); o.location=loc; o.rotation_euler=[math.radians(r) for r in rot]
    if t=='AREA': o.rotation_euler=(Vector((0,0,4))-Vector(loc)).to_track_quat('-Z','Y').to_euler()
    return o
light('SUN',(0,0,10),3.0,(1,0.95,0.9),(50,0,-35))
light('AREA',(-6,6,8),2500,(1,0.3,0.15),(-120,0,-40),6)
light('AREA',(-4,14,10),P.get('back_e',6000),(0.85,0.8,1.0),(-125,0,195),10)
light('AREA',(6,-8,5),1200,(0.6,0.75,1),(70,0,30),8)
sc.render.engine='BLENDER_EEVEE'
try: sc.eevee.use_shadows=True
except: pass
sc.render.resolution_x=P.get("rx",1400); sc.render.resolution_y=P.get("ry",1000)
sc.view_settings.view_transform='AgX'
cam_d=bpy.data.cameras.new("C"); cam=bpy.data.objects.new("Cam",cam_d); sc.collection.objects.link(cam); sc.camera=cam
cam_d.lens=P.get("lens",40)
views=P.get("views",{"hero":[(9,-16,4.5),(0,0,3.4)]})
for name,(loc,tgt) in views.items():
    cam.location=loc
    d=Vector(tgt)-Vector(loc); cam.rotation_euler=d.to_track_quat('-Z','Y').to_euler()
    sc.render.filepath=S+name+".png"; bpy.ops.render.render(write_still=True)
if P.get("save"): bpy.ops.wm.save_as_mainfile(filepath=P["save"])
print("RES ok")
