"""Project the painted lower wall or rock face onto its ground contact."""
import numpy as np
from PIL import Image
from building_footprints import JIANGNAN, building_mask, market_contour


def stamp_rock(mask, alpha, anchor, size, flip=False):
    x, y = anchor
    w, h = (max(1, round(v)) for v in size)
    left, top = round(x-w/2), round(y-h)
    silhouette = alpha.resize((w, h), Image.Resampling.NEAREST)
    if flip:
        silhouette = silhouette.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    py, px = np.ogrid[:h, :w]
    contact = ((px+.5-w*.5)/(w*.46))**2 + ((py+.5-h*.73)/(h*.25))**2 <= 1
    stencil = Image.fromarray(((np.asarray(silhouette)>=105) & contact).astype('uint8')*255)
    mask.paste(1, (left, top, left+w, top+h), stencil)


def jiangnan_contacts(props, regions, sheet):
    """Bake short horizontal bands in reference coordinates for the scene assembler."""
    for part in props:
        key = part["sprite"]
        rock = key in {"rock", "bank_rocks"}
        counter = market_contour(part)
        if not rock and counter is None and key not in JIANGNAN:
            continue
        x, y, w, h = part["rect"]
        if rock and w < 12:
            continue
        ax, ay, aw, ah = regions[key]
        span = min(w, h*aw/ah*1.28) if h else w
        size = (max(1, round(span)), max(1, round(span*ah/aw)))
        width, height = size
        origin = (x+w/2-width/2, y+h-height)
        if rock:
            mask = Image.new("L",size)
            stamp_rock(mask,sheet.crop((ax,ay,ax+aw,ay+ah)),(width/2,height),size)
        elif counter is not None:
            mask = building_mask(size, counter)
            part.pop("enclosed", None)
            part["market_contact"] = True
        else:
            mask = building_mask(size,JIANGNAN[key])
            part["enclosed"]=True
        bands = []
        pixels = np.asarray(mask)
        step = 1 if counter is not None else 2
        for row in range(0, height, step):
            hit = np.any(pixels[row:row+step],axis=0)
            edges = np.flatnonzero(np.diff(hit,prepend=False,append=False))
            for left, right in edges.reshape(-1,2):
                bands.append([origin[0]+int(left),origin[1]+row,int(right-left),min(step,height-row)])
        if bands:
            part["walking_feet"] = bands
