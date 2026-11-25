"""Paint independent pixel-art arch, deck and rail sprites from surveyed deck edges."""

import math

import numpy as np
from PIL import Image, ImageDraw


ART_SCALE = 1.6
SHORE_ROAD_CENTERS = {
    "north_arch": ((841,252),(1089,268)),
    "south_arch": ((786,602),(1023,585)),
}


def bridge_approaches(profiles):
    for name, outline in profiles.items():
        half = len(outline) // 2
        tips = ((outline[0],outline[-1]),(outline[half-1],outline[half]))
        for (back, front), (shore_x, shore_y) in zip(tips, SHORE_ROAD_CENTERS[name]):
            x, top = back
            bottom = front[1]
            direction = 1 if shore_x > x else -1
            yield [(shore_x,shore_y-9),(x,top),(x-direction*7,top),
                   (x-direction*7,bottom),(x,bottom),(shore_x,shore_y+9)]


def paint_bridge(outline, street_pattern, pixels_per_survey_px, east_quay=None):
    half = len(outline) // 2
    back = np.asarray(outline[:half])
    front = np.asarray(outline[half:][::-1])
    left, right = front[0, 0], front[-1, 0]
    span = right - left
    center = (left + right) * .5
    origin = [math.floor(left)-3, math.floor(back[:, 1].min())-15]
    size = (math.ceil((span+6)*ART_SCALE),
            math.ceil((front[:, 1].max()+23-origin[1])*ART_SCALE))

    def pixels(points):
        return [tuple(round((p-o)*ART_SCALE) for p,o in zip(point,origin)) for point in points]

    def stroke(draw, points, color, width=1):
        draw.line(pixels(points),fill=color,width=max(1,round(width*ART_SCALE)))

    def polygon(draw, points, color):
        draw.polygon(pixels(points),fill=color)

    def deck_y(edge, x):
        return float(np.interp(x,edge[:,0],edge[:,1]))

    def between(at, course):
        return at, np.interp(course,[0,3],[deck_y(back,at),deck_y(front,at)])

    def footing(x):
        distance = min(x-left,right-x)
        east_shoulder = max(0, 1 - (right-x)/30)
        return deck_y(front,x) + 1 + 13 * min(1, distance/30) + (9*east_shoulder if east_quay is not None else 0)

    arch_radius = span * .274
    opening_height = footing(center) - deck_y(front,center) - 8

    def arch_point(theta, rim=0):
        x = center + (arch_radius+rim)*math.cos(theta)
        return x, footing(x) - (opening_height+rim)*math.sin(theta)

    opening = [arch_point(angle) for angle in np.linspace(math.pi,0,121)]
    left_bank = [(x,footing(x)) for x in np.linspace(left,opening[0][0],12)[:-1]]
    right_bank = [(x,footing(x)) for x in np.linspace(opening[-1][0],right,12)[1:]]
    bottom = [*left_bank, *opening, *right_bank]
    fascia = [*map(tuple,front), *reversed(bottom)]
    stone = Image.new("RGBA",size,"#918a7f")
    brush = ImageDraw.Draw(stone)
    for row, y in enumerate(np.arange(front[:,1].min(),max(footing(left),footing(right))+6,5.3)):
        for col, x in enumerate(np.arange(left-9 + row%2*7,right+8,15)):
            tone = ("#9c9587","#a7a094","#99958c","#b0a596")[int(row*7+col*5)%4]
            polygon(brush,[(x,y),(x+14.6,y-.2),(x+15,y+4.8),(x,y+5)],tone)
            stroke(brush,[(x+1,y+.5),(x+13,y+.5)],"#beb4a4",.7)
    # The inner edge uses the same ellipse as the opening. Individual tapered
    # blocks wrap the ring from one footing to the other.
    for block in range(13):
        lo = math.pi*(1-(block+1)/13)
        hi = math.pi*(1-block/13)
        sector = np.linspace(lo,hi,9)
        polygon(brush,[*[arch_point(t,5.8) for t in sector],
            *[arch_point(t) for t in reversed(sector)]],
            ("#bdb19e","#aa9f8f","#cec4ae","#b6aa96")[block%4])
        stroke(brush,[arch_point(lo),arch_point(lo,5.8)],"#777267",.65)
    stroke(brush,[arch_point(t,5.8) for t in np.linspace(0,math.pi,75)],"#d3c7b3",.8)
    stroke(brush,opening,"#6c675d",1.2)
    stone_mask = Image.new("L",size)
    polygon(ImageDraw.Draw(stone_mask),fascia,255)
    stone.putalpha(stone_mask)

    brush = ImageDraw.Draw(stone)
    polygon(brush,outline,"#a7a498")
    for section, x in enumerate(np.arange(left,right,10)):
        end = min(x+10,right)
        for row in range(3):
            # The block joints run lengthwise over the arch, with staggered
            # cross sections and alternating daylight tones.
            start = max(left,x-4 if row%2 and x!=left else x)
            stop = end-4 if row%2 and end!=right else end
            tone = ("#bcb8aa","#b5b0a2","#c7c0ad","#b0ad9f")[(section*3+row*7)%4]
            span_points = [between(start,row),between(stop,row),between(stop,row+1),between(start,row+1)]
            polygon(brush,span_points,tone)
            stroke(brush,span_points[:2],"#969184",.7)
            stroke(brush,[span_points[0],span_points[3]],"#918b80",.65)
    stroke(brush,front,"#736b5f",1.9)
    stroke(brush,front-np.array([0,1.1]),"#e2d6c0",1.6)
    stroke(brush,back,"#958d80",1)

    def railing(edge):
        rail = Image.new("RGBA",size)
        brush = ImageDraw.Draw(rail)
        # The openings at both bridgeheads leave the full deck width usable.
        rail_x = np.linspace(left+10,right-10,45)
        feet = [(x,deck_y(edge,x)) for x in rail_x]
        for height, shade, width in [(2.6,"#7b7265",2.4),(3.2,"#b1a592",1.3),
                                    (7.9,"#746b60",3.5),(8.6,"#c4b8a4",2.5),
                                    (9.15,"#e2d7c3",1)]:
            stroke(brush,[(x,y-height) for x,y in feet],shade,width)
        posts = np.linspace(rail_x[0],rail_x[-1],9)
        for i, x in enumerate(posts):
            y = deck_y(edge,x)
            width = 2.5 if i in (0,len(posts)-1) else 1.9
            polygon(brush,[(x-width,y+.5),(x-width,y-10.3),(x,y-11.6),
                          (x+width,y-10.3),(x+width,y),(x,y+1.2)],"#746b60")
            polygon(brush,[(x-width+.6,y-.5),(x-width+.6,y-9.9),(x+.5,y-10.4),
                          (x+.5,y+.25)],"#d5cbb8")
            stroke(brush,[(x-width-.3,y-10.2),(x,y-11.5),(x+width+.25,y-10.35)],"#f1e5cd",1)
            stroke(brush,[(x+1,y-8.8),(x+1,y-.7)],"#a69b89",1)
        return rail

    deck_mask = Image.new("L",size)
    polygon(ImageDraw.Draw(deck_mask),outline,255)
    road_tiles = np.asarray(street_pattern)
    for label, image in [("ArchStonework",stone),("BackRail",railing(back)),("FrontRail",railing(front))]:
        # Muted pixel grain sits in the stone only. The cut-out arch exposes live water.
        rgba = np.asarray(image).copy()
        y,x = np.indices(rgba.shape[:2])
        grain = (((x*13+y*17+(x*y)%19)%17)-8)[...,None]
        rgb = rgba[:,:,:3].astype(float)
        gray = rgb @ np.array([.25,.55,.20])
        if label == "ArchStonework":
            ref_x = x/ART_SCALE+origin[0]
            ref_y = y/ART_SCALE+origin[1]
            distance = np.minimum(ref_x-left,right-ref_x)
            shoulder = np.clip(1-distance/27,0,1)
            # Slate at the approaches eases into the lighter arch masonry.
            middle = np.stack((gray*.78,gray*.83,gray*.88),axis=-1)
            entry = np.stack((gray*.59,gray*.66,gray*.73),axis=-1)
            rgb = middle+(entry-middle)*shoulder[...,None]
            # Each tip picks up the same brick phase as the adjoining road.
            tile_x = np.floor(ref_x*pixels_per_survey_px).astype(int) % road_tiles.shape[1]
            tile_y = np.floor(ref_y*pixels_per_survey_px).astype(int) % road_tiles.shape[0]
            paving = road_tiles[tile_y,tile_x]
            blend = (np.clip((29-distance)/23,0,1) * (np.asarray(deck_mask)>0))[...,None]
            rgb = rgb+(paving-rgb)*blend
            if east_quay is not None:
                face = np.asarray(east_quay)
                cx = np.floor(ref_x*pixels_per_survey_px).astype(int) % face.shape[1]
                cy = np.floor(ref_y*pixels_per_survey_px).astype(int) % face.shape[0]
                amount = (np.clip(1-(right-ref_x)/28,0,1)*(np.asarray(deck_mask)==0))[...,None]
                rgb += (face[cy,cx]-rgb)*amount
        else:
            rgb = np.stack((gray*.83,gray*.86,gray*.9),axis=-1)
        rgba[:,:,:3] = np.clip(rgb+grain,0,255)
        image = Image.fromarray(rgba)
        bounds = image.getbbox()
        at = [round(coordinate + pixel/ART_SCALE,3) for coordinate,pixel in zip(origin,bounds[:2])]
        yield label, image.crop(bounds), at


def bridge_atlas(profiles, street_pattern, quay_masonry, pixels_per_survey_px, output):
    atlas = Image.new("RGBA",(384,768))
    y = 2
    result = {}
    for bridge, outline in profiles.items():
        parts = {}
        # Unlike the three land approaches, the eastern abutment meets a raised quay.
        east_quay = quay_masonry if bridge == "south_arch" else None
        for label, sprite, origin in paint_bridge(outline, street_pattern, pixels_per_survey_px, east_quay):
            if sprite.width+4 > atlas.width or y+sprite.height+2 > atlas.height:
                raise ValueError(f"Bridge art exceeds atlas: {bridge}/{label}")
            atlas.paste(sprite,(2,y))
            parts[label] = {"region":[2,y,sprite.width,sprite.height],"origin":origin}
            y += sprite.height+3
        result[bridge] = parts
    atlas.crop((0,0,atlas.width,y)).save(output,optimize=True)
    return result
