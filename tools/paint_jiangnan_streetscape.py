"""Place Jiangnan buildings on grass and paint their street-side entrances."""

import math
import random
from collections import deque

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


OPEN_STRUCTURES = {"theatre", "pavilion", "teal_stall", "snack_stall"}
WORKSHOP_WIDTH = {"forge":76, "dyers-and-tofu-makers":93, "crafts-wood-shop":62}


def is_house(prop):
    return prop["layer"] == "buildings" and prop["sprite"] not in OPEN_STRUCTURES


def fit_buildings(props, regions, sprite_atlas, land, paving, port_terrain):
    """Keep opaque eaves and foundations a few pixels clear of any road."""
    bounds = land.size
    allowed = (np.asarray(land) > 0) & (np.asarray(paving) == 0)
    allowed = np.asarray(Image.fromarray(allowed.astype(np.uint8)*255).filter(ImageFilter.MinFilter(9)))>0
    taken = np.zeros_like(allowed)
    entries = []
    for prop in [part for part in props if is_house(part)]:
        id_ = prop["id"]
        home = prop["sprite"] in ("house","gallery","cottageroof")
        if home:
            prop["sprite"] = "house"
        ax, ay, aw, ah = regions[prop["sprite"]]
        alpha = sprite_atlas.crop((ax,ay,ax+aw,ay+ah)).getchannel("A")
        x,y,w,h = prop["rect"]
        bottom = y+h
        center = x+w*.5
        wanted = min(w,h*aw/ah*1.28)
        if home:
            wanted = min(wanted, 90)
        wanted = min(wanted,WORKSHOP_WIDTH.get(id_,wanted))
        valid = (np.asarray(port_terrain) > 0) & ~taken if id_ == "harbor-terminal" else allowed & ~taken
        # Search around the authored house, preferring its original scale and
        # moving away from the road only as far as needed.
        offsets = sorted(((dx,dy) for dx in range(-112,113,4) for dy in range(-104,105,4)),
                         key=lambda at: at[0]**2+at[1]**2)
        candidates = []
        for factor in (1.,.91,.82,.73):
            wi = round(wanted*factor)
            he = round(wi*ah/aw)
            mask = np.asarray(alpha.resize((wi,he),Image.Resampling.BILINEAR)) > 0
            for dx,dy in offsets:
                left,top = round(center+dx-wi/2), round(bottom+dy)-he
                if left<0 or top<0 or left+wi>bounds[0] or top+he>bounds[1]:
                    continue
                if np.any(mask & ~valid[top:top+he,left:left+wi]):
                    continue
                candidates.append((math.hypot(dx,dy)+(1-factor)*155,left,top,wi,he,mask))
                break
        if not candidates:
            raise ValueError(f"No roadside grass plot fits {id_}")
        _,left,top,wi,he,mask = min(candidates,key=lambda item:item[0])
        bottom = top+he
        cx = left+wi*.5
        taken[max(0,top-3):min(bounds[1],bottom+4),max(0,left-3):min(bounds[0],left+wi+3)] = True
        prop["rect"] = [left,top,wi,he]
        prop["foot"] = [cx,bottom]
        prop["grass_house"] = True
        if prop["bases"]:
            prop["bases"] = [[round(left+wi*.065,2),round(bottom-he*.22,2),round(wi*.87,2),round(he*.19,2)]]
        entries.append({"id":id_,"door":[cx,bottom],"bounds":[left,top,wi,he]})
    return entries


def paint_frontages(entries, land, paved, excluded):
    """Paint low edges on the grass and interrupt them for curved door paths."""
    land = np.asarray(land) > 0
    road = np.asarray(paved) > 0
    road_center = np.asarray(paved.filter(ImageFilter.MinFilter(9))) > 0
    near_stone = np.asarray(paved.filter(ImageFilter.MaxFilter(3))) > 0
    roadside = np.asarray(paved.filter(ImageFilter.MaxFilter(11))) > 0
    verge = land & roadside & ~road & ~(np.asarray(excluded)>0)
    paths = Image.new("L",paved.size)
    stepping_stones = Image.new("RGBA",paved.size)
    paint = ImageDraw.Draw(stepping_stones)
    gravel_ground = land & ~road & ~(np.asarray(excluded)>0)
    openings = Image.new("L",paved.size)
    footprint = Image.new("L",paved.size)
    for entry in entries:
        x,y,w,h = entry["bounds"]
        ImageDraw.Draw(footprint).rectangle((x,y,x+w,y+h-1),fill=255)
    occupied = np.asarray(footprint)>0
    gravel_ground &= ~occupied
    bank = np.asarray(excluded)>0
    yy,xx = np.nonzero(road_center)
    on_grid = (xx%3 == 0) & (yy%3 == 0)
    yy,xx = yy[on_grid],xx[on_grid]
    for i,entry in enumerate(entries):
        sx,sy=entry["door"]
        dx,dy=xx-sx,yy-sy
        distal = (dx*dx+dy*dy>7**2) & (np.abs(dx)<147) & (np.abs(dy)<158) & ~bank[yy,xx]
        ranks = (dx*dx+dy*dy+np.maximum(-dy,0)**2*1.8)[distal]
        ends = np.column_stack((xx[distal],yy[distal]))
        for j in np.argsort(ranks)[:720]:
            x,y=ends[j]
            length=math.hypot(x-sx,y-sy)
            bend = min(12,length*.21)*(-1 if i%2 else 1)
            t=np.linspace(0,1,max(6,int(length/2)))
            points_x=sx+(x-sx)*t + bend*np.sin(t*math.tau)
            # Step out of the doorway before the trail bends toward the street.
            points_y=sy+(y-sy)*t + min(16,length*.5)*np.sin(t*math.pi)
            points=np.rint(np.column_stack((points_x,points_y))).astype(int)
            px,py=points.T
            if np.any(~land[py,px] | occupied[py,px] | bank[py,px]):
                continue
            joins=[tuple(p) for p in points]
            break
        else:
            joins = walk_around_houses((round(sx),round(sy)),land & ~occupied & ~bank,road_center)
            if not joins:
                raise ValueError(f"No connecting footpath from {entry['id']}")
        width=7 if entry["id"] in WORKSHOP_WIDTH else 9
        ImageDraw.Draw(paths).line(joins,fill=255,width=width,joint="curve")
        ImageDraw.Draw(openings).line(joins,fill=255,width=width+6)
        entry["lane"]=[int(v) for v in joins[-1]]
        paint_stepping_stones(paint, joins, gravel_ground, random.Random(2200 + i))
    path=(np.asarray(paths)>0)&land&~occupied
    verge=verge & ~(np.asarray(openings)>0) & ~occupied
    yy,xx=np.indices(road.shape)
    fleck=(xx*13+yy*19+xx*yy)%17-8
    rgba=np.zeros((*road.shape,4),dtype=np.uint8)
    stone_clusters = ((xx//3*13 + yy//2*7 + (xx//5)*(yy//4)) % 17)
    low_curb = verge & near_stone & (stone_clusters < 13)
    gravel = verge & (((xx//2)*13+yy*7+(xx//3)*(yy//5))%29 < 3)
    grass_tips = verge & ((xx*5+yy*11+xx//5)%31 < 3)
    for mask, color, opacity in [
        (verge & near_stone, (61,57,48), 139),
        (low_curb, (113,110,96), 222),
        (gravel, (171,169,150), 208),
        (grass_tips, (153,158,72), 173),
    ]:
        rgba[mask,:3]=np.clip(np.asarray(color)+fleck[mask,None],0,255)
        rgba[mask,3]=opacity
    decoration = np.asarray(stepping_stones).copy()
    decoration[~gravel_ground,3] = 0
    result = Image.fromarray(rgba)
    result.alpha_composite(Image.fromarray(decoration))
    return result, path


def paint_stepping_stones(brush, joins, dry, rng):
    points = np.asarray(joins)
    distances = np.r_[0, np.cumsum(np.linalg.norm(np.diff(points, axis=0), axis=1))]
    stone_faces = ("#b0b4aa", "#a6afa9", "#bcb9a7", "#9ba8a4")
    pebble_colors = ("#5d6056", "#9e9f88", "#b0a691", "#71786a")
    last_stone = None
    for distance in np.arange(6, distances[-1], 13):
        x, y = [round(np.interp(distance, distances, axis)) for axis in points.T]
        x += rng.randrange(-2, 3)
        y += rng.randrange(-1, 2)
        if not dry[y-3:y+4,x-5:x+6].all():
            continue
        if last_stone and math.dist((x, y), last_stone) < 11:
            continue
        last_stone = (x, y)
        # Scuffs are small muted grass patches around individual stones.
        brush.polygon([(x-7,y+1),(x-4,y-4),(x+3,y-4),(x+7,y+2),(x+1,y+5),(x-5,y+4)],
                      fill=(118,108,64,99))
        width = rng.randrange(3, 6)
        face = [(x-width,y),(x-width+2,y-2),(x+2,y-3),
                (x+width,y-1),(x+width-1,y+1),(x-2,y+2)]
        brush.polygon([(px,py+2) for px,py in face], fill="#53584e")
        brush.polygon(face, fill=rng.choice(stone_faces))
        brush.line([(x-width+2,y-2),(x+2,y-3)], fill="#cccbc0")
        if rng.randrange(3) == 0:
            brush.point((x+1,y),fill="#626d55")
    # Loose chippings near the doorway, sparse and without a solid fill.
    for _ in range(27):
        x = int(points[0,0]) + rng.randrange(-8, 9)
        y = int(points[0,1]) + rng.randrange(1, 10)
        brush.point((x,y),fill=rng.choice(pebble_colors))


def walk_around_houses(start, free, road):
    queue = deque([start])
    parent = {start: None}
    while queue:
        point = queue.popleft()
        x,y = point
        if road[y,x]:
            route = [point]
            while parent[point] is not None:
                point = parent[point]
                route.append(point)
            route.reverse()
            # Averaging the interior waypoints rounds the bends between houses.
            interior = [tuple(round(sum(axis)/3) for axis in zip(a,b,c))
                        for a,b,c in zip(route,route[1:],route[2:])]
            return [route[0],*interior,route[-1]]
        for dx,dy in ((0,3),(3,2),(-3,2),(3,0),(-3,0),(0,-3)):
            nx,ny=x+dx,y+dy
            if not (2<=nx<free.shape[1]-2 and 2<=ny<free.shape[0]-2):
                continue
            if abs(nx-start[0])>186 or abs(ny-start[1])>194:
                continue
            if (nx,ny) in parent or not (free[ny,nx] and free[(y+ny)//2,(x+nx)//2]):
                continue
            parent[nx,ny]=point
            queue.append((nx,ny))
    return []


def detail_atlas(art_layers, columns, rows, tile_pixels, output):
    variants={}
    layers={}
    atlas_width=128
    for name,art in art_layers.items():
        image=art.resize((columns*tile_pixels,rows*tile_pixels),Image.Resampling.NEAREST)
        values=np.asarray(image).reshape(rows,tile_pixels,columns,tile_pixels,4).transpose(0,2,1,3,4)
        occupied=np.any(values[:,:,:,:,3],axis=(2,3))
        cells=[]
        for y,x in np.argwhere(occupied):
            pixels=values[y,x].tobytes()
            slot=variants.setdefault(pixels,len(variants))
            cells.append([int(x),int(y),slot%atlas_width,slot//atlas_width,2,15])
        layers[name]=cells
    atlas=Image.new("RGBA",(atlas_width*tile_pixels,math.ceil(len(variants)/atlas_width)*tile_pixels))
    for pixels,slot in variants.items():
        tile=Image.frombytes("RGBA",(tile_pixels,tile_pixels),pixels)
        atlas.paste(tile,(slot%atlas_width*tile_pixels,slot//atlas_width*tile_pixels))
    atlas.save(output,optimize=True)
    return layers
