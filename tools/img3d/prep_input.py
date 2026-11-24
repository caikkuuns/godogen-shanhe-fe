# Prepare TripoSR input + projection texture from the A-pose front reference.
#  - flood-fill white key from the border (keeps white trousers/robe)
#  - also key enclosed white gaps between hair strands/neck (head box)
#  - input_gray.png: 512x512, subject at 0.85, gray(0.5) background (TripoSR --no-remove-bg)
#  - ref_front_dilated.png: fg eroded 4 px, bg filled with nearest fg colour (no white fringe when projected)
import sys
from PIL import Image
import numpy as np
from scipy import ndimage
D = sys.argv[1] if len(sys.argv) > 1 else "."
SRC = sys.argv[2] if len(sys.argv) > 2 else "/workspace/wuxia-team/art/characters/ref3d/shenyan_front.png"
a = np.asarray(Image.open(SRC).convert('RGB')); ai = a.astype(int)
near = ai.min(2) > 235; lab, _ = ndimage.label(near)
border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
bg = np.isin(lab, list(border))
import os, json
hole = np.zeros_like(bg)
HB = os.environ.get("HEADBOX", "150,288,380,680")  # y0,y1,x0,x1 of enclosed hair gaps; "" to disable
if HB:
    y0_, y1_, x0_, x1_ = map(int, HB.split(",")); box = (slice(y0_, y1_), slice(x0_, x1_))
    hole[box] = ai[box].min(2) > 215
hole = ndimage.binary_dilation(hole, iterations=2) & (ai.min(2) > 170)
fg = ndimage.binary_opening(~bg, iterations=1) & ~hole
ys, xs = np.where(fg); y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max(); print("bbox", x0, y0, x1, y1)
json.dump({"bbox": [int(x0), int(y0), int(x1), int(y1)], "size": [a.shape[1], a.shape[0]]}, open(f"{D}/bbox.json", "w"))
rgba = np.dstack([a, fg.astype(np.uint8) * 255])[y0:y1 + 1, x0:x1 + 1]
h, w = rgba.shape[:2]; S = int(max(h, w) / 0.85); c = np.zeros((S, S, 4), np.uint8)
oy = (S - h) // 2; ox = (S - w) // 2; c[oy:oy + h, ox:ox + w] = rgba
cf = c.astype(float) / 255; rgb = cf[..., :3] * cf[..., 3:] + 0.5 * (1 - cf[..., 3:])
Image.fromarray((rgb * 255).astype(np.uint8)).resize((512, 512), Image.LANCZOS).save(f'{D}/input_gray.png')
core = ndimage.binary_erosion(fg, iterations=4)
idx = ndimage.distance_transform_edt(~core, return_distances=False, return_indices=True)
Image.fromarray(a[idx[0], idx[1]]).save(f'{D}/ref_front_dilated.png')
