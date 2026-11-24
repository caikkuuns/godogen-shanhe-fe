import bpy, sys, math, mathutils, bmesh, os
argv=sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
STAGE=argv[0] if argv else "orient"
D=os.environ.get("IMG3D_DIR","/workspace/shenyan-img3d")
CH=float(os.environ.get("CHAR_H","1.70")); K=CH/1.70
NAME=os.environ.get("CHAR_NAME","shenyan")
SD=os.path.dirname(os.path.abspath(__file__))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc=bpy.context.scene
bpy.ops.wm.obj_import(filepath=f"{D}/out_tsr/0/mesh.obj")
o=bpy.context.selected_objects[0]; o.name="Shenyan"
bpy.context.view_layer.objects.active=o
print("UVS",len(o.data.uv_layers))
# orientation: rot set via env
rx,ry,rz=[float(x) for x in os.environ.get("ROT","0,0,-90").split(",")]
o.rotation_euler=(math.radians(rx),math.radians(ry),math.radians(rz))
bpy.ops.object.transform_apply(rotation=True)
bb=[mathutils.Vector(c) for c in o.bound_box]
mn=mathutils.Vector([min(v[i] for v in bb) for i in range(3)]); mx=mathutils.Vector([max(v[i] for v in bb) for i in range(3)])
print("BB",mn,mx)
s=CH/(mx.z-mn.z); o.scale=(s,s,s); bpy.ops.object.transform_apply(scale=True)
bb=[mathutils.Vector(c) for c in o.bound_box]
mn=mathutils.Vector([min(v[i] for v in bb) for i in range(3)]); mx=mathutils.Vector([max(v[i] for v in bb) for i in range(3)])
o.location=(-(mn.x+mx.x)/2,-(mn.y+mx.y)/2,-mn.z); bpy.ops.object.transform_apply(location=True)
# material
mat=bpy.data.materials.new("ShenyanTex"); mat.use_nodes=True
nt=mat.node_tree; bsdf=nt.nodes["Principled BSDF"]
tex=nt.nodes.new("ShaderNodeTexImage"); tex.image=bpy.data.images.load(f"{D}/out_tsr/0/texture.png")
nt.links.new(tex.outputs["Color"],bsdf.inputs["Base Color"]); bsdf.inputs["Roughness"].default_value=0.8
o.data.materials.clear(); o.data.materials.append(mat)
def setup_render(path_prefix, views):
    sc.render.engine="BLENDER_EEVEE_NEXT"
    sc.render.resolution_x=600; sc.render.resolution_y=900
    sc.view_settings.view_transform="Standard"
    w=bpy.data.worlds.new("W"); sc.world=w; w.use_nodes=True; w.node_tree.nodes["Background"].inputs[0].default_value=(1,1,1,1); w.node_tree.nodes["Background"].inputs[1].default_value=1.0
    sun=bpy.data.objects.new("Sun",bpy.data.lights.new("Sun","SUN")); sc.collection.objects.link(sun); sun.data.energy=1.5; sun.rotation_euler=(math.radians(40),0,math.radians(20))
    cam=bpy.data.objects.new("Cam",bpy.data.cameras.new("Cam")); sc.collection.objects.link(cam); sc.camera=cam
    cam.data.type="ORTHO"; cam.data.ortho_scale=1.95*K
    for name,ang in views:
        a=math.radians(ang); r=5
        # angle 0 = camera at -Y looking +Y (front)
        cam.location=(r*math.sin(a),-r*math.cos(a),0.85*K); cam.rotation_euler=(math.radians(90),0,a)
        sc.render.filepath=f"{path_prefix}_{name}.png"; bpy.ops.render.render(write_still=True)
exec(open(os.path.join(SD,"stage2.py")).read())
if STAGE=="orient":
    setup_render(f"{D}/render/orient",[("front",0),("side",90),("back",180),("left",-90)])
