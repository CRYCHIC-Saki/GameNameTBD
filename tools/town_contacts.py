"""Project the painted lower wall or rock face onto its ground contact."""
import numpy as np
from PIL import Image
from building_footprints import JIANGNAN, building_mask, market_contour


# Normalized ground silhouettes (the final row is the near edge of the sprite).
# Separate islands for open gates, drying racks and the stools beside a table.
TRUNK = [(31,94),(41,89),(44,82),(55,81),(60,89),(71,94),(62,98),(39,99)]
ROUND_BASE = [(6,70),(18,56),(76,54),(95,68),(94,86),(77,98),(24,99),(6,87)]
LONG_BASE = [(4,68),(12,54),(87,54),(97,64),(96,95),(85,98),(80,89),(17,89),(14,98),(4,98)]
POST_PAIR = [[(4,76),(17,75),(17,98),(3,98)],[(82,76),(95,74),(97,98),(82,98)]]
CART = [(7,73),(18,59),(72,51),(87,64),(96,68),(93,76),(80,78),(76,93),(65,99),(49,95),(23,95),(11,88)]
FIXTURES = {
    "banyan": [[(21,95),(31,91),(38,85),(43,71),(49,68),(57,70),(62,85),(70,91),(81,95),
                (73,97),(64,95),(59,99),(52,96),(46,99),(40,96),(30,99)]],
    "smallcart":[CART], "lantern_cart":[CART], "fruitcart":[CART],
    "tea_table":[[(19,51),(29,38),(65,37),(80,54),(78,85),(68,87),(63,78),(33,78),(30,88),(22,87)],
                 [(0,73),(8,63),(20,65),(24,74),(21,97),(3,99)],
                 [(78,72),(89,63),(98,70),(99,94),(85,98),(77,88)]],
    "gate":POST_PAIR, "laundry":POST_PAIR, "fishnet":POST_PAIR,
    "stone_seat":[ROUND_BASE],"stools":[LONG_BASE],"bench":[LONG_BASE],
    "festival_lamp":[[(4,92),(12,86),(24,85),(31,94),(29,99),(4,99)]],
    "peony":[[(6,80),(25,68),(55,66),(67,77),(75,82),(79,61),(88,62),(92,85),(92,95),(56,98),(20,95)]],
    "crock":[ROUND_BASE],"stone_mill":[ROUND_BASE],"firewood":[ROUND_BASE],"crates":[ROUND_BASE],
    "grove":[TRUNK],"blossom":[TRUNK],"willow":[TRUNK],"young_willow":[TRUNK],
    "bamboo":[[(15,85),(39,78),(80,82),(89,95),(68,98),(18,96)]],
    "sakura":[TRUNK],"pine":[TRUNK],"dwarf":[TRUNK],"oak":[TRUNK],"oak_wide":[TRUNK],"lime":[TRUNK],
    "shrub":[ROUND_BASE],"hydrangea":[ROUND_BASE],"zen":[ROUND_BASE],"housewares":[ROUND_BASE],
    "tubs":[ROUND_BASE],"buckets":[ROUND_BASE],"cargo":[ROUND_BASE],"basin":[ROUND_BASE],
    "wheel":[[(27,72),(66,65),(82,80),(76,94),(52,99),(31,93)]],
    "lantern":[[(26,84),(36,73),(62,73),(75,86),(73,98),(25,98)]],
    "lamp":[[(28,87),(40,82),(62,82),(75,91),(74,99),(26,99)]],
    "bollard":[ROUND_BASE],"fence":[[(4,68),(95,68),(96,97),(3,97)]],
    "fountain":[[(2,68),(10,58),(29,50),(72,50),(91,59),(98,72),(91,86),(72,97),(30,98),(10,88)]],
    "well":[ROUND_BASE],"planter":[ROUND_BASE],
    "carriage":[[(4,65),(13,51),(52,49),(63,65),(74,64),(80,47),(96,51),(98,65),
                 (91,72),(88,95),(80,94),(76,78),(65,79),(62,95),(45,96),(18,99),(5,88)]],
}


def fixture_mask(key, size, flip=False):
    """Opaque ground volumes include the space between legs under a solid seat."""
    mask = Image.new("L", size)
    for contour in FIXTURES[key]:
        component = building_mask(size, contour, flip)
        mask.paste(255, mask=component)
    return mask


def stamp_fixture(target, key, anchor, size, flip=False):
    width, height = (max(1,round(v)) for v in size)
    mask = fixture_mask(key,(width,height),flip)
    x, y = round(anchor[0]-width/2), round(anchor[1]-height)
    target.paste(1,(x,y,x+width,y+height),mask)


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
        if not rock and counter is None and key not in JIANGNAN and key not in FIXTURES:
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
        elif key in FIXTURES:
            mask = fixture_mask(key,size)
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
