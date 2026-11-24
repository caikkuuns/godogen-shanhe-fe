import numpy as np
if STAGE in ("full",):
    # ---- cleanup ----
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.remove_doubles(threshold=0.0005)
    bpy.ops.mesh.delete_loose()
    # close small marching-cube holes (a chest hole showed the black outline hull through it)
    bpy.ops.mesh.select_all(action='DESELECT'); bpy.ops.mesh.select_non_manifold(extend=False, use_wire=True, use_boundary=True, use_multi_face=False, use_non_contiguous=False, use_verts=False)
    bpy.ops.mesh.fill_holes(sides=0)
    bpy.ops.mesh.select_all(action='SELECT'); bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    # drop tiny disconnected islands
    bm=bmesh.new(); bm.from_mesh(o.data); bm.verts.ensure_lookup_table()
    seen=set(); islands=[]
    for v in bm.verts:
        if v.index in seen: continue
        st=[v]; isl=[]; seen.add(v.index)
        while st:
            x=st.pop(); isl.append(x)
            for e in x.link_edges:
                y=e.other_vert(x)
                if y.index not in seen: seen.add(y.index); st.append(y)
        islands.append(isl)
    islands.sort(key=len,reverse=True)
    rm=[v for isl in islands[1:] if len(isl)<200 for v in isl]
    print("ISLANDS",len(islands),[len(i) for i in islands[:5]],"removed",len(rm))
    bmesh.ops.delete(bm,geom=rm,context='VERTS'); bm.to_mesh(o.data); bm.free()
    tris0=sum(len(p.vertices)-2 for p in o.data.polygons)
    m=o.modifiers.new("dec","DECIMATE"); m.ratio=min(1.0,14800/tris0); m.use_collapse_triangulate=True
    bpy.ops.object.modifier_apply(modifier="dec")
    bpy.ops.object.shade_smooth()
    tris=sum(len(p.vertices)-2 for p in o.data.polygons)
    print("TRIS",tris0,"->",tris)
    exec(open(os.path.join(SD,"proj.py")).read())
    # ---- measure landmarks from mesh ----
    V=np.array([v.co[:] for v in o.data.vertices])
    H=CH
    def band(z0,z1): return V[(V[:,2]>z0)&(V[:,2]<z1)]
    # hands: extreme |x|
    Vh=V[V[:,2]>0.42*CH]  # ignore weapons hanging below the hands (e.g. Li Heng's blade)
    R=Vh[Vh[:,0]>0]; L=Vh[Vh[:,0]<0]
    hr=R[np.argmax(R[:,0])]; hl=L[np.argmin(L[:,0])]
    print("HANDTIP R",hr,"L",hl)
    # ---- armature ----
    arm=bpy.data.armatures.new("Rig"); ao=bpy.data.objects.new("Rig",arm); sc.collection.objects.link(ao)
    bpy.context.view_layer.objects.active=ao; bpy.ops.object.mode_set(mode='EDIT')
    eb=arm.edit_bones
    def B(n,h,t,p=None,conn=False):
        b=eb.new(n); b.head=tuple(c*K for c in h); b.tail=tuple(c*K for c in t)
        if p: b.parent=eb[p]; b.use_connect=conn
        return b
    yb=0.0
    B("hips",(0,yb,0.92),(0,yb,1.02))
    B("spine",(0,yb,1.02),(0,yb,1.20),"hips",True)
    B("chest",(0,yb,1.20),(0,yb,1.38),"spine",True)
    B("neck",(0,yb,1.38),(0,yb,1.48),"chest",True)
    B("head",(0,yb,1.48),(0,yb,1.70),"neck",True)
    for s,sg in (("L",-1),("R",1)):
        ht=(hr if sg>0 else hl)/K
        sh=np.array([sg*0.17,yb,1.34]); wr=np.array([ht[0]-sg*0.06, ht[1], ht[2]+0.07])
        el=(sh+wr)/2+np.array([0,0.02,0])
        B(f"shoulder.{s}",(sg*0.04,yb,1.36),tuple(sh),"chest")
        B(f"upper_arm.{s}",tuple(sh),tuple(el),f"shoulder.{s}",True)
        B(f"forearm.{s}",tuple(el),tuple(wr),f"upper_arm.{s}",True)
        B(f"hand.{s}",tuple(wr),(ht[0],ht[1],ht[2]),f"forearm.{s}",True)
        B(f"thigh.{s}",(sg*0.09,yb,0.92),(sg*0.095,yb-0.01,0.48),"hips")
        B(f"shin.{s}",(sg*0.095,yb-0.01,0.48),(sg*0.10,yb+0.01,0.09),f"thigh.{s}",True)
        B(f"foot.{s}",(sg*0.10,yb+0.01,0.09),(sg*0.10,yb-0.12,0.02),f"shin.{s}",True)
    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='DESELECT'); o.select_set(True); ao.select_set(True)
    bpy.context.view_layer.objects.active=ao
    bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    vg=[g.name for g in o.vertex_groups]
    unweighted=sum(1 for v in o.data.vertices if not any(g.weight>0.01 for g in v.groups))
    print("VGROUPS",len(vg),"UNWEIGHTED",unweighted,"/",len(o.data.vertices))
    # ---- animations ----
    ao.animation_data_create()
    def act(name,frames,keys):
        a=bpy.data.actions.new(name); ao.animation_data.action=a
        for pb in ao.pose.bones: pb.rotation_mode='XYZ'
        for f,pose in keys:
            for pb in ao.pose.bones:
                pb.rotation_euler=pose.get(pb.name,(0,0,0)); pb.keyframe_insert("rotation_euler",frame=f)
            ao.pose.bones["hips"].location=pose.get("_hipsloc",(0,0,0)); ao.pose.bones["hips"].keyframe_insert("location",frame=f)
        a.use_fake_user=True
        tr=ao.animation_data.nla_tracks.new(); tr.name=name; tr.strips.new(name,1,a)
        ao.animation_data.action=None
        return a
    r=math.radians
    ARM_DOWN=float(os.environ.get("ARM_DOWN","20"))
    def arm_e(side,deg,extra_fwd=0.0):
        b=ao.data.bones[f"upper_arm.{side}"]; M=b.matrix_local.to_3x3()
        sg=1 if side=="R" else -1
        R=mathutils.Matrix.Rotation(r(sg*deg),3,'Y')@mathutils.Matrix.Rotation(r(extra_fwd),3,'X')
        L=M.inverted()@R@M
        return tuple(L.to_euler('XYZ'))
    def arms(fwdL=0.0,fwdR=0.0,dd=0.0):
        return {"upper_arm.L":arm_e("L",ARM_DOWN+dd,fwdL),"upper_arm.R":arm_e("R",ARM_DOWN+dd,fwdR)}
    idle=act("idle",48,[(1,{"chest":(r(1),0,0),"head":(r(-1),0,0),**arms()}),(25,{"chest":(r(-1.5),0,0),"head":(r(1),0,0),**arms(dd=-2)}),(49,{"chest":(r(1),0,0),"head":(r(-1),0,0),**arms()})])
    A=20
    def wp(ph):
        return {"thigh.L":(r(A*ph),0,0),"thigh.R":(r(-A*ph),0,0),"shin.L":(r(-10*max(0,-ph)),0,0),"shin.R":(r(-10*max(0,ph)),0,0),
                **arms(fwdL=-8*ph,fwdR=8*ph),"_hipsloc":(0,0,0)}
    walk=act("walk",32,[(1,wp(1)),(9,wp(0)),(17,wp(-1)),(25,wp(0)),(33,wp(1))])
    sc.frame_start=1; sc.frame_end=48
    bpy.ops.export_scene.gltf(filepath=f"{D}/{NAME}_img3d.glb",export_format='GLB',export_animations=True,export_nla_strips=True)
    bpy.ops.wm.save_as_mainfile(filepath=f"{D}/{NAME}_img3d.blend")
    # ---- renders: rest pose views + walk stress frame + back ----
    ao.data.pose_position="POSE"; ao.animation_data.action=idle
    for t in ao.animation_data.nla_tracks: t.mute=True
    sc.frame_set(1)
    setup_render(f"{D}/render/v",[("front",0),("side",-90),("45",-45),("back",180)])
    # walk pose stress test
    ao.data.pose_position="POSE"
    ao.animation_data.action=walk
    for t in ao.animation_data.nla_tracks: t.mute=True
    sc.frame_set(1)
    bpy.data.objects.remove(bpy.data.objects["Sun"]); setup_render(f"{D}/render/walk",[("front",0),("side",-90)])
