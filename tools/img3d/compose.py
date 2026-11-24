# Compose compare_img3d.png (IMG3D front/side/45 vs REF front/side) like captures/shenyan_3d_compare.png
from PIL import Image, ImageDraw, ImageFont
import glob, sys
D = sys.argv[1] if len(sys.argv) > 1 else "."
NAME = sys.argv[2] if len(sys.argv) > 2 else "shenyan"
R = "/workspace/wuxia-team/art/characters/ref3d/"
fp = glob.glob('/usr/share/fonts/**/DejaVuSans.ttf', recursive=True)
F = ImageFont.truetype(fp[0], 28) if fp else ImageFont.load_default()
def panel(img, label, H=1000):
    img = img.convert('RGBA'); bg = Image.new('RGBA', img.size, 'white'); bg.alpha_composite(img); img = bg.convert('RGB')
    w = int(img.width * H / img.height); img = img.resize((w, H), Image.LANCZOS)
    p = Image.new('RGB', (w, H + 50), (220, 218, 212)); p.paste(img, (0, 50))
    d = ImageDraw.Draw(p); tw = d.textlength(label, font=F); d.text(((w - tw) / 2, 10), label, fill=(30, 30, 30), font=F); return p
def sheet(ps, out):
    gap = 30; W = sum(p.width for p in ps) + gap * (len(ps) + 1); H = ps[0].height + 2 * gap
    o = Image.new('RGB', (W, H), (220, 218, 212)); x = gap
    for p in ps: o.paste(p, (x, gap)); x += p.width + gap
    o.save(out); print(out, o.size)
sheet([panel(Image.open(f'{D}/render/v_front.png'), 'IMG3D FRONT'), panel(Image.open(f'{D}/render/v_side.png'), 'IMG3D SIDE'),
       panel(Image.open(f'{D}/render/v_45.png'), 'IMG3D 45'), panel(Image.open(R + ({'shenyan':'shenyan_front.png'}.get(NAME, NAME+'_apose_front.png'))), 'REF FRONT'),
       panel(Image.open(R + ({'shenyan':'shenyan_side.png'}.get(NAME, NAME+'_apose_side.png'))), 'REF SIDE')], f'{D}/compare_img3d.png')
sheet([panel(Image.open(f'{D}/render/v_back.png'), 'IMG3D BACK (guessed)'), panel(Image.open(f'{D}/render/walk_front.png'), 'WALK FRONT'),
       panel(Image.open(f'{D}/render/walk_side.png'), 'WALK SIDE')], f'{D}/compare_img3d_extra.png')
