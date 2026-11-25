"""Survey the drawn island in map pixels. The game reads the baked results."""
import base64
import heapq
import math
import zlib

import numpy as np
from building_footprints import wall_clearance
from PIL import ImageDraw, ImageFilter, Image


# Ground-contact lobes, measured within each sprite (left, top, right, bottom).
# The pale foam skirt and moss hanging over the sides are outside the solid.
ROCK_FEET = {
    "ledge": [(0.05,.66,.37,.96),(.20,.53,.81,.89),(.69,.49,.94,.78)],
    "crag": [(.04,.70,.34,.97),(.26,.57,.73,.88),(.63,.47,.98,.78)],
    "shore": [(.03,.42,.35,.74),(.24,.46,.69,.82),(.62,.50,.97,.86)],
    "outcrop": [(.04,.51,.29,.72),(.19,.42,.63,.72),(.48,.68,.88,.89),(.82,.49,.95,.61)],
    "reef": [(.06,.55,.22,.67),(.25,.42,.75,.66),(.77,.51,.90,.62),
             (.19,.75,.34,.87),(.67,.73,.85,.86)],
    "fall": [(.03,.64,.24,.89),(.76,.64,.98,.91)],
}


def rock_contact(mask, key, x, y, w, h, flipped=False, alpha=None):
    if alpha is not None:
        size = (max(1,round(w)),max(1,round(h)))
        local = Image.new("L",size)
        rock_contact(local,key,size[0]/2,size[1],*size,flipped)
        paint = alpha.resize(size,Image.Resampling.NEAREST)
        if flipped: paint=paint.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        stencil = Image.fromarray(((np.asarray(local)>0) & (np.asarray(paint)>=125)).astype("uint8")*255)
        bx,by=round(x-size[0]/2),round(y-size[1])
        mask.paste(1,(bx,by,bx+size[0],by+size[1]),stencil)
        return
    brush = ImageDraw.Draw(mask)
    for left, top, right, bottom in ROCK_FEET[key]:
        if flipped:
            left, right = 1-right, 1-left
        brush.ellipse((round(x+(left-.5)*w), round(y+(top-1)*h),
                       round(x+(right-.5)*w), round(y+(bottom-1)*h)), fill=1)


# Distances follow walkable ground. Slabs and the quay are easier going than
# meadows, and loose beach sand is slower. One cost unit is one map pixel.
def route_costs(weights, doors, step):
    height, width = weights.shape
    distance = np.full(weights.shape, np.inf)
    queue = []
    for px, py in doors:
        scored = []
        for y in range(max(0, py//step-4), min(height, py//step+5)):
            for x in range(max(0, px//step-4), min(width, px//step+5)):
                if weights[y,x]:
                    scored.append(((x*step+step//2-px)**2+(y*step+step//2-py)**2, y, x))
        if not scored:
            raise ValueError(f"No approach to economic anchor at {px},{py}")
        _, y, x = min(scored)
        distance[y,x] = 0
        heapq.heappush(queue, (0., y, x))
    while queue:
        cost, y, x = heapq.heappop(queue)
        if cost != distance[y,x]:
            continue
        for dy, dx in ((0,1),(1,0),(0,-1),(-1,0),(1,1),(1,-1),(-1,1),(-1,-1)):
            ny,nx = y+dy,x+dx
            if not (0<=ny<height and 0<=nx<width) or not weights[ny,nx]:
                continue
            if dx and dy and not (weights[y,nx] and weights[ny,x]):
                continue
            new = cost + step*(1.4142 if dx and dy else 1.)*(weights[y,x]+weights[ny,nx])*.5
            if new < distance[ny,nx]:
                distance[ny,nx] = new
                heapq.heappush(queue,(new,ny,nx))
    return distance


def survey(ground, rocks, walking_rocks, dock_solids, solid, walls, legacy, buildings, bridge_frame, bridge_lane):
    land = np.asarray(ground)
    # Same one-pixel coastline and stream that the artist draws. Bridge rail
    # takes priority inside its frame, including where it hangs over dry turf.
    base = (np.isin(land,[0,1,3,6,8,9,10,11,12]) & ~np.asarray(walking_rocks,dtype=bool)
            & ~np.asarray(dock_solids,dtype=bool))
    walking = Image.fromarray(base.astype("uint8"))
    brush = ImageDraw.Draw(walking)
    x,y,w,h = bridge_frame
    brush.rectangle((x,y,x+w-1,y+h-1),fill=0)
    brush.polygon(bridge_lane,fill=1)
    clearance = Image.fromarray(np.asarray(walking) & ~np.asarray(solid,dtype=bool) & ~wall_clearance(walls,80/24))
    bits = np.packbits(np.asarray(clearance),axis=1,bitorder="little")
    packed = base64.b64encode(zlib.compress(bits.tobytes(),9)).decode()
    # Allow for the player's foot radius when measuring approach distances.
    step = 3  # an arched bridge lane is too narrow for the terrain tile spacing
    samples = np.s_[step//2::step,step//2::step]
    coarse = np.asarray(clearance.convert("L").filter(ImageFilter.MinFilter(5)))[samples]>0
    weights = np.where(coarse, np.where(np.isin(land[samples],[1,3,8,9,10]),1.,1.22),0.)
    weights[coarse & (land[samples]==12)] = 1.52
    groups = {"residential":["residences-a","residences-b"],"market":["market-main","market-neighborhood"],"station":["harbor"]}
    routes = {}
    for key,ids in groups.items():
        doors = [(p["x"],p["y"]+5) for p in buildings if p["plot"] in ids]
        routes[key] = route_costs(weights,doors,step)
    surfaces = []
    sites = []
    travel = {key:bytearray() for key in groups}
    stone = np.asarray(rocks,dtype=bool)
    obstacles = np.asarray(solid,dtype=bool) | np.asarray(walls,dtype=bool)
    # One economic cell covers 4x4 navigation samples. The surface describes
    # its centre, the approach uses its nearest reachable ground.
    for cy, row in enumerate(legacy):
        material_row, site_row = [], []
        for cx, previous in enumerate(row):
            x,y = (cx-8)*24,(cy-17)*24
            valid = 0<=x<=land.shape[1]-24 and 0<=y<=land.shape[0]-24
            code, eligible = "~",False
            if valid:
                patch = land[y:y+24,x:x+24]
                rock = stone[y:y+24,x:x+24]
                code = ".r~d^pzibgqvs"[patch[12,12]]
                if (patch==8).sum()>=20:
                    code="b"
                elif rock[12,12] and code not in "rbgqd":
                    code="o" if code=="~" else "k"
                elif previous=="v" and code==".":
                    code="v"
                eligible = previous in ".v" and not rock.any() and not obstacles[y:y+24,x:x+24].any()
            for key,dist in routes.items():
                near = dist[y//step:(y+24)//step,x//step:(x+24)//step].min() if valid else np.inf
                # 255 denotes disconnected; the other bytes are tenths of a minute.
                travel[key].append(min(254,round(20+near/8)) if math.isfinite(near) else 255)
            material_row.append(code)
            site_row.append("." if eligible and travel["station"][-1]!=255 else "-")
        surfaces.append("".join(material_row))
        sites.append("".join(site_row))
    return dict(walk_bits=packed, surfaces=surfaces, sites=sites,
                travel={key:base64.b64encode(buf).decode() for key,buf in travel.items()})
