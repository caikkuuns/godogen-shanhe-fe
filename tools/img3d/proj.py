# front-projection of the reference onto front-facing faces, baked into UV texture
if STAGE=="full":
    V=np.array([v.co[:] for v in o.data.vertices])
    xmin,xmax=V[:,0].min(),V[:,0].max(); zmin,zmax=V[:,2].min(),V[:,2].max()
    import json
    _bb=json.load(open(f"{D}/bbox.json")); PX0,PY0,PX1,PY1=_bb["bbox"]; IW,IH=_bb["size"]
    ax=(PX1-PX0)/(xmax-xmin)/IW; bx=PX0/IW-ax*xmin
    az=(PY1-PY0)/(zmax-zmin)/IH; bz=1-PY1/IH-az*zmin
    print("PROJ",ax,bx,az,bz)
    nt=mat.node_tree; N=nt.nodes; Lk=nt.links
    tc=N.new("ShaderNodeTexCoord"); sep=N.new("ShaderNodeSeparateXYZ"); Lk.new(tc.outputs["Object"],sep.inputs[0])
    def lin(inp,a,b):
        m1=N.new("ShaderNodeMath"); m1.operation='MULTIPLY_ADD'; Lk.new(inp,m1.inputs[0]); m1.inputs[1].default_value=a; m1.inputs[2].default_value=b; return m1.outputs[0]
    comb=N.new("ShaderNodeCombineXYZ"); Lk.new(lin(sep.outputs["X"],ax,bx),comb.inputs[0]); Lk.new(lin(sep.outputs["Z"],az,bz),comb.inputs[1])
    ref=N.new("ShaderNodeTexImage"); ref.image=bpy.data.images.load(f"{D}/ref_front_dilated.png"); ref.extension='EXTEND'
    Lk.new(comb.outputs[0],ref.inputs[0])
    geo=N.new("ShaderNodeNewGeometry"); sn=N.new("ShaderNodeSeparateXYZ"); Lk.new(geo.outputs["Normal"],sn.inputs[0])
    # facing toward the in-game camera (front, tilted ~35deg down) so top surfaces also get the painted ref
    dp=N.new("ShaderNodeVectorMath"); dp.operation='DOT_PRODUCT'; Lk.new(geo.outputs["Normal"],dp.inputs[0]); dp.inputs[1].default_value=(0.0,-0.82,0.57)
    f1=lin(dp.outputs["Value"],1/0.32,-0.38/0.32)
    cl=N.new("ShaderNodeClamp"); Lk.new(f1,cl.inputs[0])
    # side projection (u from depth y, v from z)
    ymin,ymax=V[:,1].min(),V[:,1].max()
    SX0,SX1=304,666
    ay=-(SX1-SX0)/(ymax-ymin)/IW; by=SX0/IW-ay*ymax
    print("SIDEPROJ",ay,by,ymin,ymax)
    comb2=N.new("ShaderNodeCombineXYZ"); Lk.new(lin(sep.outputs["Y"],ay,by),comb2.inputs[0]); Lk.new(lin(sep.outputs["Z"],az,bz),comb2.inputs[1])
    sref=N.new("ShaderNodeTexImage"); sref.image=bpy.data.images.load("/workspace/wuxia-team/art/characters/ref3d/shenyan_side.png"); sref.extension='EXTEND'
    Lk.new(comb2.outputs[0],sref.inputs[0])
    ab=N.new("ShaderNodeMath"); ab.operation='ABSOLUTE'; Lk.new(sn.outputs["X"],ab.inputs[0])
    cs=N.new("ShaderNodeClamp"); Lk.new(lin(ab.outputs[0],1/0.3,-0.5/0.3),cs.inputs[0])
    mixs=N.new("ShaderNodeMix"); mixs.data_type='RGBA'
    Lk.new(cs.outputs[0],mixs.inputs["Factor"]); Lk.new(tex.outputs["Color"],mixs.inputs[6]); Lk.new(sref.outputs["Color"],mixs.inputs[7])
    mix=N.new("ShaderNodeMix"); mix.data_type='RGBA'
    Lk.new(cl.outputs[0],mix.inputs["Factor"]); Lk.new(tex.outputs["Color"],mix.inputs[6]); Lk.new(ref.outputs["Color"],mix.inputs[7])
    # hair-side cleanup: grey/white low-saturation blobs on head sides/back -> hair colour
    hsv=N.new("ShaderNodeSeparateColor"); hsv.mode='HSV'; Lk.new(mix.outputs[2],hsv.inputs[0])
    def mth(op,a,b=None):
        m=N.new("ShaderNodeMath"); m.operation=op
        for k,v in enumerate((a,b)):
            if v is None: continue
            if isinstance(v,float): m.inputs[k].default_value=v
            else: Lk.new(v,m.inputs[k])
        return m.outputs[0]
    HAIRFIX=float(os.environ.get("HAIRFIX","1"))
    zin=mth('MULTIPLY',mth('GREATER_THAN',sep.outputs["Z"],1.49*K),mth('LESS_THAN',sep.outputs["Z"],1.62*K)); zin=mth('MULTIPLY',zin,HAIRFIX)
    notfront=mth('LESS_THAN',sn.outputs["Y"],-0.0); notfront=mth('SUBTRACT',1.0,mth('GREATER_THAN',mth('MULTIPLY',sn.outputs["Y"],-1.0),0.55))
    grey=mth('MULTIPLY',mth('GREATER_THAN',hsv.outputs[2],0.025),mth('LESS_THAN',hsv.outputs[1],0.25))
    hm=mth('MULTIPLY',mth('MULTIPLY',zin,notfront),grey)
    mixh=N.new("ShaderNodeMix"); mixh.data_type='RGBA'; Lk.new(hm,mixh.inputs["Factor"]); Lk.new(mix.outputs[2],mixh.inputs[6]); mixh.inputs[7].default_value=(0.045,0.045,0.06,1)
    # boot-tip cleanup (HAIRFIX characters = 沈砚 with grey boots): bright low-saturation texels below 0.14 m -> boot grey
    hsv2=N.new("ShaderNodeSeparateColor"); hsv2.mode='HSV'; Lk.new(mixh.outputs[2],hsv2.inputs[0])
    feet=mth('MULTIPLY',mth('LESS_THAN',sep.outputs["Z"],0.14*K),HAIRFIX)
    bright=mth('MULTIPLY',mth('GREATER_THAN',hsv2.outputs[2],0.30),mth('LESS_THAN',hsv2.outputs[1],0.30))
    mixb=N.new("ShaderNodeMix"); mixb.data_type='RGBA'; Lk.new(mth('MULTIPLY',feet,bright),mixb.inputs["Factor"]); Lk.new(mixh.outputs[2],mixb.inputs[6]); mixb.inputs[7].default_value=(0.13,0.13,0.14,1)
    bsdf=N["Principled BSDF"]; Lk.new(mixb.outputs[2],bsdf.inputs["Base Color"])
    # bake
    out=bpy.data.images.new(f"{NAME}_albedo",2048,2048)
    # start from the TripoSR texture so any texel the bake skips (degenerate UV after decimation) is not black
    _src=tex.image; _src.scale(2048,2048) if tuple(_src.size)!=(2048,2048) else None; out.pixels[:]=_src.pixels[:]
    tgt=N.new("ShaderNodeTexImage"); tgt.image=out; N.active=tgt; tgt.select=True
    sc.render.engine='CYCLES'; sc.cycles.device='CPU'; sc.cycles.samples=4
    bpy.ops.object.select_all(action='DESELECT'); o.select_set(True); bpy.context.view_layer.objects.active=o
    bpy.ops.object.bake(type='DIFFUSE',pass_filter={'COLOR'},margin=8,use_clear=False)
    out.filepath_raw=f"{D}/{NAME}_albedo.png"; out.file_format='PNG'; out.save()
    # rewire: material uses the baked texture only
    for n in list(N):
        if n.type not in ('BSDF_PRINCIPLED','OUTPUT_MATERIAL'): N.remove(n)
    t2=N.new("ShaderNodeTexImage"); t2.image=out; Lk.new(t2.outputs["Color"],N["Principled BSDF"].inputs["Base Color"])
    print("BAKED")
