# Character image-to-3D pipeline (TripoSR, CPU only): 沈砚 / 林照晚 / 厉横

Produces `assets/glb/shenyan.glb` (14.8k tris, 1.70 m, 19 bones, idle/walk, 2048 albedo).
The previous script-built model is `assets/glb/shenyan_script.glb` (tools/make_shenyan.py).
No weights or venv are committed; everything below is free/open source.

| Part | Source | License |
|---|---|---|
| TripoSR code | github.com/VAST-AI-Research/TripoSR | MIT |
| TripoSR weights | huggingface.co/stabilityai/TripoSR (1.68 GB, auto-download) | MIT |
| marching cubes | scikit-image (replaces torchmcubes, needs no compiler) | BSD-3 |
| Blender | 4.5.3 (~/.local/bin/blender) | GPL (tool only) |

## Steps (work dir `$IMG3D_DIR`, default /workspace/shenyan-img3d)
```bash
export IMG3D_DIR=/workspace/shenyan-img3d; mkdir -p $IMG3D_DIR/render; cp tools/img3d/* $IMG3D_DIR/; cd $IMG3D_DIR
git clone --depth 1 https://github.com/VAST-AI-Research/TripoSR.git
(cd TripoSR && git apply ../triposr_skimage_mc.patch)
uv venv -p 3.11 venv && . venv/bin/activate
uv pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
uv pip install omegaconf==2.3.0 Pillow==10.1.0 einops==0.7.0 transformers==4.35.0 trimesh==4.0.5 \
  huggingface-hub "imageio[ffmpeg]" xatlas==0.0.9 moderngl==5.10.0 scikit-image scipy
python prep_input.py .            # input_gray.png + ref_front_dilated.png (white fringe removed)
mkdir -p out_tsr/0 && python TripoSR/run.py input_gray.png --device cpu --no-remove-bg \
  --mc-resolution 320 --bake-texture --texture-resolution 2048 --output-dir $IMG3D_DIR/out_tsr   # ~50 s on 8 CPU cores
~/.local/bin/blender -b --python build.py -- full   # ~40 s: orient, 1.70 m, decimate, project+bake, rig, anims, export
python compose.py .                # compare_img3d.png
cp shenyan_img3d.glb <repo>/assets/glb/shenyan.glb
```

## Other characters (林照晚 1.63 m, 厉横 1.85 m)
```bash
for c in linzhaowan:1.63 liheng:1.85; do n=${c%%:*}; h=${c##*:}; d=$IMG3D_DIR/chars/$n
  mkdir -p $d/render $d/out_tsr/0
  HEADBOX="" python prep_input.py $d /workspace/wuxia-team/art/characters/ref3d/${n}_apose_front.png
  (cd TripoSR && python run.py $d/input_gray.png --device cpu --no-remove-bg --mc-resolution 320 \
     --bake-texture --texture-resolution 2048 --output-dir $d/out_tsr)
  IMG3D_DIR=$d CHAR_H=$h CHAR_NAME=$n HAIRFIX=0 ARM_DOWN=$([ $n = liheng ] && echo 6 || echo 20) \
     ~/.local/bin/blender -b --python build.py -- full
  python compose.py $d $n; cp $d/${n}_img3d.glb <repo>/assets/glb/$n.glb
done
```
Env knobs: `CHAR_H` height (bones scale with it), `CHAR_NAME` output names, `HEADBOX` (y0,y1,x0,x1 of enclosed
white hair gaps to key, 沈砚 default; "" disables), `HAIRFIX` (grey-blob → hair colour on head sides; 0 for
characters with light hair ornaments), `ARM_DOWN` degrees the clips lower the arms from the reference pose.
In game: player uses scripts/world/player.gd, NPCs use ToonModel (scripts/world/toon_model.gd) via
world_builder.gd `NPC_MODELS`; a missing GLB falls back to the billboard sprites.

## What build.py / stage2.py / proj.py do
- Orient TripoSR mesh (front = Blender -Y = Godot +Z), scale to 1.70 m, feet at origin.
- Fill small marching-cube holes, decimate to ~14.8k tris (keeps TripoSR UVs).
- `proj.py`: orthographic front projection of the reference (`ref_front_dilated.png`) onto faces that face the
  front/overhead camera, blended over the TripoSR texture, plus grey-blob cleanup on the hair sides, baked
  (Cycles DIFFUSE colour, target pre-filled with the TripoSR texture so skipped texels are never black) to `<name>_albedo.png`. This is what makes face/clothes match the painting.
- 19-bone humanoid armature, automatic (heat) weights, arms lowered 20 deg from the A-pose in the clips.
- Actions `idle` (48 f breathing) and `walk` (32 f) as NLA strips -> glTF animations `idle`/`walk`.

## Known limits
Back/side are TripoSR guesses (softer), hands have no fingers, sword and robe are fused into the body mesh
(robe skirt follows the thighs when walking), cloth folds are only painted.
