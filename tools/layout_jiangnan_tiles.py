"""Prepare Jiangnan sprite atlases and editor cells from independent art sheets.

This authoring tool takes independent sprite and texture sheets. It never reads
the overview image. Once assembled, edit the .tscn directly in Godot.
"""

import argparse
import json
import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter
from paint_jiangnan_bridges import ART_SCALE, bridge_approaches, bridge_atlas
from paint_jiangnan_streetscape import detail_atlas, fit_buildings, paint_frontages
from paint_jiangnan_weathering import contact_shadows, damp_wall, quay_masonry_face, shade_blossoms, weathered_ground


ROOT = Path(__file__).resolve().parents[1]
TOWN = ROOT / "content/towns"
ASSETS = ROOT / "assets/town"
WIDTH, HEIGHT = 1670, 941
WORLD_SCALE = (73 * 90) / WIDTH
PROP_SCALE = 80 / 90
TILE_PIXELS, TILE_WORLD, VARIANTS = 8, 20, 6
COLS = math.ceil(WIDTH * WORLD_SCALE / TILE_WORLD)
ROWS = math.ceil(HEIGHT * WORLD_SCALE / TILE_WORLD)
NATURE = ("banyan", "willow", "blossom", "grove", "reeds", "lotus")
BUILDINGS = ("diner", "bank", "grocer", "inn", "terminal", "house")
STRUCTURES = ("bridge", "pavilion", "produce", "fish", "theatre", "sampan")
PLANTING = ("wild_ivory", "wild_gold", "wild_pink", "bank_shrub", "bank_rocks", "young_willow")
MARKET = ("lantern_cart", "tea_table", "stone_seat", "teal_stall", "snack_stall", "festival_lamp")
BRIDGES = ("north_arch", "south_arch")
TIMBER = ("harbor_pier", "pavilion_spur")
STONE_LANDINGS = ("main_wharf", "east_ferry_walk", "ferry_tea_deck", "pavilion_walk")


def load_data(name):
    return json.loads((TOWN / name).read_text(encoding="utf-8-sig"))


def shape(outline):
    image = Image.new("L", (WIDTH, HEIGHT))
    ImageDraw.Draw(image).polygon([tuple(point) for point in outline], fill=255)
    return image


def union(outlines):
    image = Image.new("L", (WIDTH, HEIGHT))
    brush = ImageDraw.Draw(image)
    for points in outlines:
        brush.polygon([tuple(point) for point in points], fill=255)
    return image


def road_surface(roads):
    roads_mask = Image.new("L", (WIDTH, HEIGHT))
    brush = ImageDraw.Draw(roads_mask)
    for road in roads:
        points = [tuple(point) for point in road["points"]]
        radius = road["radius"] * 1.02
        brush.line(points, fill=255, width=round(radius * 2), joint="curve")
        for x, y in points:
            brush.ellipse((x-radius, y-radius, x+radius, y+radius), fill=255)
    return roads_mask


def grid_masks(image):
    # Neighboring cells share all boundary samples. Rounded banks and streets
    # use four-corner transitions rather than rectangles snapped to plot lots.
    mx = np.minimum(np.round(np.arange(COLS+1) * TILE_WORLD / WORLD_SCALE).astype(int), WIDTH-1)
    my = np.minimum(np.round(np.arange(ROWS+1) * TILE_WORLD / WORLD_SCALE).astype(int), HEIGHT-1)
    pixels = (np.asarray(image)[np.ix_(my, mx)] > 127).astype(np.uint8)
    return pixels[:-1, :-1] | pixels[:-1, 1:]*2 | pixels[1:, 1:]*4 | pixels[1:, :-1]*8


def difference(left, right):
    return Image.fromarray(np.where((np.asarray(left)>0) & (np.asarray(right)==0), 255, 0).astype(np.uint8))


def intersection(left, right):
    return Image.fromarray(np.minimum(np.asarray(left), np.asarray(right)))

def irregular_edge(image, radius):
    # Coarse offsets at the scale of individual slabs, with shared transition
    # samples between cells. Never perturb the middle of a street.
    solid = np.asarray(image.filter(ImageFilter.MinFilter(2 * radius + 1))) > 0
    available = np.asarray(image.filter(ImageFilter.MaxFilter(2 * radius + 1))) > 0
    y, x = np.ogrid[:HEIGHT, :WIDTH]
    offsets = ((x // 4) * 37 + (y // 5) * 53 + ((x + y) // 9) * 13) % 7
    treatment = np.where((np.asarray(image) > 0), offsets > 0, offsets >= 5)
    return Image.fromarray(((solid | (available & treatment)) * 255).astype(np.uint8))


def shifted_down(image, distance):
    shifted = Image.new("L",image.size)
    shifted.paste(image,(0,distance))
    return shifted


def tile_rows(geography):
    land = union(geography["land"].values())
    woods = intersection(land, union(geography["woods"].values()))
    streets = intersection(irregular_edge(road_surface(geography["road_centerlines"]), 3), land)
    squares = geography["public_ground"]
    paving = union([squares[id_] for id_ in ("banyan_square", "south_market")])
    night_court = intersection(shape(squares["night_food_street"]),shape([[0,621],[WIDTH,621],[WIDTH,HEIGHT],[0,HEIGHT]]))
    paving = Image.fromarray(np.maximum(np.asarray(paving),np.asarray(night_court)))
    paving = Image.fromarray(np.maximum(np.asarray(paving),np.asarray(
        shape([[505,481],[586,464],[607,475],[611,504],[601,523],[531,532],[509,522]]))))
    sand_range = shape([[0,780],[900,720],[1000,698],[1145,717],[1145,941],[0,941]])
    sand = intersection(difference(land, land.filter(ImageFilter.MinFilter(29))), sand_range)
    rim = difference(land.filter(ImageFilter.MaxFilter(9)), land.filter(ImageFilter.MinFilter(5)))
    coastal_foam = intersection(rim, shape([[950,625],[1670,573],[1670,941],[0,941],[0,796],[823,804]]))
    paving = intersection(irregular_edge(paving, 3), land)
    # The public market apron reaches both access lanes. Follow their surveyed
    # centers at the joins so narrow wedges of lawn cannot split the court.
    apron = shape([[269,237],[293,211],[345,196],[482,218],[519,224],[528,261],
                   [502,287],[461,314],[405,323],[361,318],[326,309],[304,279],[281,252]])
    market_outline = Image.fromarray(np.maximum(np.asarray(apron),np.asarray(shape(squares["fresh_market"]))))
    fresh_market = intersection(irregular_edge(market_outline, 1), land)
    square_bed = Image.fromarray(np.maximum(np.asarray(paving),np.asarray(fresh_market)))
    decks = geography["public_decks"]
    bridge_profiles = {key: decks[key] for key in BRIDGES}
    bridge_ground = union(bridge_profiles.values())
    landings = intersection(union(bridge_approaches(bridge_profiles)),land)
    streets = Image.fromarray(np.maximum(np.asarray(streets), np.asarray(landings)))
    port_lawn = intersection(land,shape([[1176,484],[1350,469],[1402,484],
        [1401,600],[1368,615],[1200,613],[1176,597]]))
    stone_wharf = difference(union([decks[key] for key in STONE_LANDINGS]),port_lawn)
    # One cell of slate below the arch hides raster rounding at the common edge.
    south = bridge_profiles["south_arch"]
    mid = len(south)//2
    overlap = shape([south[mid-2],south[mid-1],south[mid],south[mid+1]])
    stone_wharf = Image.fromarray(np.maximum(np.asarray(stone_wharf),np.asarray(overlap)))
    wood_wharf = union([decks[key] for key in TIMBER])
    deck_union = Image.fromarray(np.maximum(np.asarray(stone_wharf),np.asarray(wood_wharf)))
    all_decks = Image.fromarray(np.maximum(np.asarray(deck_union),np.asarray(bridge_ground)))
    quay_rim = shape(decks["main_wharf"]).filter(ImageFilter.MaxFilter(23))
    coastal_foam = difference(coastal_foam,quay_rim)
    other_quays = difference(stone_wharf, shape(decks["main_wharf"]))
    quay_face = difference(shifted_down(other_quays, 10), all_decks)
    raised_bank = difference(shifted_down(land, 8), land)
    raised_bank = difference(intersection(raised_bank, difference(rim.filter(ImageFilter.MaxFilter(9)), sand_range)), all_decks)
    raised_bank = difference(raised_bank,quay_rim)

    rows = {}
    full = np.full((ROWS,COLS), 15, dtype=np.uint8)
    land_masks = grid_masks(land)
    river_edge = np.arange(ROWS)[:, None] * TILE_WORLD / WORLD_SCALE
    water_rows = np.where(river_edge < 621, 2, 3)
    rows["Water"] = pack_grid([(m, np.where((land_masks != 15) & (water_rows == m), full, 0)) for m in (2,3)])
    rows["Land"] = pack_grid([(0, land_masks)])
    rows["Woodlands"] = pack_grid([(6, grid_masks(woods))])
    stony_banks = difference(difference(intersection(land,rim),sand_range),quay_rim)
    rows["Shore"] = pack_grid([(8,grid_masks(coastal_foam)),(4,grid_masks(sand)),
        (9,grid_masks(stony_banks)),(9,grid_masks(raised_bank)),(13,grid_masks(quay_face))])
    street_cells = grid_masks(streets)
    square_cells = grid_masks(square_bed)
    paved_cells = street_cells | square_cells
    rows["Streets"] = pack_grid([(1, np.where(square_cells == 0, paved_cells, 0))])
    rows["Squares"] = pack_grid([(1, np.where(square_cells != 0, paved_cells, 0))])
    deck_masks = grid_masks(deck_union)
    corner_count = np.array([mask.bit_count() for mask in range(16)])
    wood = (grid_masks(wood_wharf) != 0) & (corner_count[grid_masks(stone_wharf)] < 2)
    rows["Wharf"] = pack_grid([(1,np.where(~wood,deck_masks,0)),(7,np.where(wood,deck_masks,0))])
    rows["BridgeDeck"] = pack_grid([(12,grid_masks(bridge_ground))])
    visible_shore = Image.fromarray(np.maximum.reduce([np.asarray(sand),np.asarray(stony_banks),np.asarray(raised_bank)]))
    streetscape = {"shore":visible_shore,"market":fresh_market,
        "main_quay":shape(decks["main_wharf"]), "sand":sand,
        "stone":Image.fromarray(np.maximum.reduce([np.asarray(streets), np.asarray(square_bed),np.asarray(stone_wharf)])),
        "decks":all_decks,"paved":Image.fromarray(np.maximum.reduce([
        np.asarray(streets),np.asarray(square_bed),np.asarray(all_decks)])),
        "wharf":difference(all_decks,land),"port_lawn":difference(port_lawn,streets.filter(ImageFilter.MaxFilter(9)))}
    return rows, (land, woods, streets, square_bed), streetscape

def pack_grid(material_masks):
    # One Godot atlas source. Each drawn cell stores x, y, atlas_x, atlas_y.
    cells = {}
    for material, masks in material_masks:
        y_positions, x_positions = np.nonzero(masks)
        for y, x in zip(y_positions.tolist(), x_positions.tolist()):
            mask = int(masks[y,x])
            cells[x,y] = [x, y, (mask-1)*VARIANTS+x%VARIANTS, material*VARIANTS+y%VARIANTS]
    return list(cells.values())


def swatch(sheet, index, crop_fraction=.61):
    x, y = index % 3, index // 3
    w, h = sheet.width / 3, sheet.height / 2
    px, py = (x + .5)*w, (y + .5)*h
    span = min(w,h)*crop_fraction
    data = sheet.crop(tuple(round(n) for n in (px-span*.5,py-span*.5,px+span*.5,py+span*.5)))
    return data.resize((VARIANTS*TILE_PIXELS,)*2, Image.Resampling.LANCZOS).convert("RGB")


def seamless(image):
    rgb = np.asarray(image).astype(float)
    for axis in (0, 1):
        a = np.moveaxis(rgb, axis, 0)
        delta = (a[-1] - a[0]) * .5
        for p in range(6):
            weight = (1-p/6)**2
            a[p] += delta*weight
            a[-p-1] -= delta*weight
    return Image.fromarray(np.clip(rgb,0,255).astype(np.uint8))


def mask_alpha(mask):
    center = (np.arange(TILE_PIXELS)+.5)/TILE_PIXELS
    x, y = np.meshgrid(center,center)
    fill = ((1-x)*(1-y)*(mask&1>0) + x*(1-y)*(mask&2>0) + x*y*(mask&4>0) + (1-x)*y*(mask&8>0))
    # Half-pixel clusters on the border break up the long, artificial diagonals.
    edge = .49 + ((np.arange(TILE_PIXELS)[:,None]*31+np.arange(TILE_PIXELS)*17)%7-3)*.013
    return Image.fromarray(np.where(fill>=edge,255,0).astype(np.uint8))


def native_coverage(masks):
    tiles = np.stack([np.asarray(mask_alpha(m))>0 for m in range(16)])
    return tiles[masks].transpose(0,2,1,3).reshape(ROWS*TILE_PIXELS,COLS*TILE_PIXELS)


def parcel_survey(layers, props, sand):
    # Sample the same four corners as Godot at each parcel center. Use the
    # full parcel for new construction and for finding adjacent street edges.
    fields = {}
    for name in ("Land","Woodlands","Streets","Squares","Wharf","BridgeDeck"):
        field = np.zeros((ROWS,COLS),dtype=np.uint8)
        for x,y,ax,ay,*source in layers[name]:
            field[y,x] = source[1] if source else 1+ax//VARIANTS
        fields[name] = field
    tiles = [np.asarray(mask_alpha(mask))>0 for mask in range(16)]
    # Rasterize occupied cadastral cells from the same wall bands used by walking.
    from building_footprints import JIANGNAN
    wall_cells=set()
    cell_span=WIDTH/73
    for prop in props:
        if prop["sprite"] not in JIANGNAN and not prop.get("market_contact"): continue
        for bx,by,bw,bh in prop.get("walking_feet",[]):
            for cy in range(math.floor(by/cell_span),math.ceil((by+bh)/cell_span)):
                for cx in range(math.floor(bx/cell_span),math.ceil((bx+bw)/cell_span)):
                    wall_cells.add((cx,cy))
    soil = np.asarray(sand)>0
    bases = [b for p in props for b in p["bases"]]
    types, flags = [], []
    grid_unit = 90 / TILE_WORLD
    survey_unit = WIDTH / 73
    public = np.logical_or.reduce([native_coverage(fields[k]) for k in ("Streets","Squares","Wharf","BridgeDeck")])
    grass = native_coverage(fields["Land"]) & ~public & ~native_coverage(fields["Woodlands"])
    for y in range(73):
        chars, bits = [], []
        for x in range(73):
            gx,gy = (x+.5)*grid_unit,(y+.5)*grid_unit
            px,py = (x+.5)*survey_unit,(y+.5)*survey_unit
            if py>=HEIGHT:
                chars.append("s"); bits.append("0"); continue
            def contains(key):
                mask = int(fields[key][int(gy),int(gx)])
                # Match the upper/left texel at a seam in the drawn Godot layer.
                ix=max(0,math.ceil((gx%1)*TILE_PIXELS)-1)
                iy=max(0,math.ceil((gy%1)*TILE_PIXELS)-1)
                return tiles[mask][iy,ix]
            ground = next((code for key,code in (("BridgeDeck","b"),("Wharf","q"),("Squares","p"),
                    ("Streets","r"),("Woodlands","f"),("Land","g")) if contains(key)), "s" if py>=621 else "w")
            if ground=="g" and soil[int(py),int(px)]:
                ground = "a"
            native_unit = int(grid_unit*TILE_PIXELS)
            cell = np.s_[y*native_unit:(y+1)*native_unit,x*native_unit:(x+1)*native_unit]
            clear = ground=="g" and (y+1)*survey_unit <= HEIGHT and grass[cell].all()
            blocked = any(bx<=px<bx+bw and by<=py<by+bh for bx,by,bw,bh in bases)
            chars.append(ground)
            value=int(clear) | int(public[cell].any())*2 | int(blocked)*4
            # 8 marks formerly clear grass touched by a full wall (other flags here are only 1).
            if value==1 and (x,y) in wall_cells: value=9
            bits.append(str(value))
        types.append("".join(chars))
        flags.append("".join(bits))
    anchors = {"market":[],"residential":[],"station":[]}
    for p in props:
        group = {"harbor-terminal":"station","market-blue-fish-stall":"market",
                 "chen-food-shop":"market"}.get(p["id"])
        if p["sprite"]=="house":
            group = "residential"
        if group:
            anchors[group].append([int(v/survey_unit) for v in p["foot"]])
    return {"version":1,"surfaces":types,"flags":flags,"anchors":anchors}


def terrain_atlas(path, materials_path):
    sheet = Image.open(path)
    base = [swatch(sheet,i) for i in range(6)]
    base[0] = ImageEnhance.Color(base[0]).enhance(.85)
    materials = Image.open(materials_path)
    base[1] = ImageEnhance.Brightness(ImageEnhance.Color(swatch(materials,0,.96)).enhance(.82)).enhance(1.11)
    turf = ImageEnhance.Brightness(base[0]).enhance(.63)
    woods = Image.blend(turf,Image.new("RGB",turf.size,"#153b2b"),.28)
    wood = swatch(materials,4)
    foam = Image.blend(base[2], Image.new("RGB",base[2].size,"#abdbc0"),.58)
    embankment = ImageEnhance.Brightness(swatch(materials,5)).enhance(.86)
    masonry = swatch(materials,3)
    verge = ImageEnhance.Brightness(ImageEnhance.Color(swatch(materials,1,.84)).enhance(.76)).enhance(.89)
    images = [*base, woods, wood, foam, embankment, verge, swatch(materials,2),
              masonry, ImageEnhance.Brightness(masonry).enhance(.68)]
    atlas = Image.new("RGBA", (15*VARIANTS*TILE_PIXELS,len(images)*VARIANTS*TILE_PIXELS))
    masks = [mask_alpha(mask) for mask in range(1,16)]
    for material, image in enumerate(images):
        image = seamless(image)
        for dy in range(VARIANTS):
            for dx in range(VARIANTS):
                xx, yy = dx*TILE_PIXELS, dy*TILE_PIXELS
                tile = image.crop((xx,yy,xx+TILE_PIXELS,yy+TILE_PIXELS)).convert("RGBA")
                for idx, alpha in enumerate(masks):
                    tile.putalpha(alpha)
                    dest = ((idx*VARIANTS+dx)*TILE_PIXELS,(material*VARIANTS+dy)*TILE_PIXELS)
                    atlas.paste(tile,dest)
    atlas.save(ASSETS / "jiangnan-map-tiles-v3.png", optimize=True)
    return seamless(images[13])


def mirrored_swatch(image):
    width, height = image.size
    mirrored = Image.new("RGB",(2*width,2*height))
    mirrored.paste(image,(0,0))
    mirrored.paste(image.transpose(Image.Transpose.FLIP_LEFT_RIGHT),(width,0))
    mirrored.paste(image.transpose(Image.Transpose.FLIP_TOP_BOTTOM),(0,height))
    mirrored.paste(image.transpose(Image.Transpose.ROTATE_180),(width,height))
    return mirrored


def apply_reference_paving(rows):
    # The R12 street sampled a 136 px mirrored repeat at 2 world px/texel.
    # Give paving its own atlas so the old brick density doesn't depend on the
    # shorter repeat used by grass, water, wood and other terrain.
    surfaces = Image.open(ASSETS/"district-surfaces-v1.png").convert("RGB")
    lane = surfaces.crop((2,2,(surfaces.width+2)//4-2,(surfaces.height+2)//5-2))
    lane = mirrored_swatch(lane.resize((210,210),Image.Resampling.NEAREST))
    lane = lane.resize((136,136),Image.Resampling.LANCZOS)
    size = tuple(round(length*2.0/TILE_WORLD)*TILE_PIXELS for length in lane.size)
    pattern = lane.resize(size,Image.Resampling.LANCZOS)
    alpha = {mask:mask_alpha(mask) for mask in range(1,16)}
    columns = 128
    regions = {}
    for layer in ("Streets","Squares","Wharf"):
        for index, cell in enumerate(rows[layer]):
            x,y,ax,ay = cell
            if ay//VARIANTS != 1:
                continue
            mask = 1+ax//VARIANTS
            key = (x%(pattern.width//TILE_PIXELS),y%(pattern.height//TILE_PIXELS),mask)
            if key not in regions:
                regions[key] = len(regions)
            slot = regions[key]
            rows[layer][index] = [x,y,slot%columns,slot//columns,1,mask]
    atlas = Image.new("RGBA",(columns*TILE_PIXELS,math.ceil(len(regions)/columns)*TILE_PIXELS))
    for (x,y,mask), slot in regions.items():
        left, top = x*TILE_PIXELS, y*TILE_PIXELS
        tile = pattern.crop((left,top,left+TILE_PIXELS,top+TILE_PIXELS)).convert("RGBA")
        tile.putalpha(alpha[mask])
        atlas.paste(tile,(slot%columns*TILE_PIXELS,slot//columns*TILE_PIXELS))
    atlas.save(ASSETS/"jiangnan-map-paving-v1.png",optimize=True)
    return pattern


def extract_sheet(path, keys):
    image = Image.open(path).convert("RGBA")
    regions = alpha_islands(image)
    panels = [[] for _ in keys]
    for island in regions:
        left,top,right,bottom = island[1]
        column = min(2,int(((left+right)*.5)/image.width*3))
        row = min(1,int(((top+bottom)*.5)/image.height*2))
        panels[row*3+column].append(island)
    if any(not panel for panel in panels):
        raise ValueError(f"{path.name} does not contain six isolated sprites")
    anchors = [max(panel,key=lambda item: item[0]) for panel in panels]
    groups = [[island] for island in anchors]
    attached = {id(island) for island in anchors}
    for island in regions:
        if id(island) in attached:
            continue
        center = min(range(len(keys)),key=lambda i: separated_by(island[1],anchors[i][1]))
        _,_,w,h = bounds_size(anchors[center][1])
        if separated_by(island[1],anchors[center][1]) <= max(10,min(w,h)*.39):
            groups[center].append(island)
    return {key: masked_sprite(image,group) for key,group in zip(keys,groups)}


def alpha_islands(image):
    # Transparent outlines can run over a nominal sheet divider. Group
    # touching runs first so a neighboring crop cannot steal a wheel or leaf.
    occupied = np.asarray(image.getchannel("A")) >= 22
    spans, parents, previous = [], [], []

    def root(index):
        while parents[index] != index:
            parents[index] = parents[parents[index]]
            index = parents[index]
        return index

    for y,pixels in enumerate(occupied):
        edges = np.flatnonzero(np.diff(np.pad(pixels,(1,1)))).tolist()
        row = []
        start = 0
        for left,right in zip(edges[::2],edges[1::2]):
            index = len(spans)
            spans.append((y,left,right))
            parents.append(index)
            row.append(index)
            while start < len(previous) and spans[previous[start]][2] < left:
                start += 1
            for neighbor in previous[start:]:
                if spans[neighbor][1] > right:
                    break
                parents[root(neighbor)] = root(index)
        previous = row

    groups = {}
    for index,span in enumerate(spans):
        groups.setdefault(root(index),[]).append(span)
    islands = []
    for rows in groups.values():
        area = sum(right-left for _,left,right in rows)
        if area < 10:
            continue
        bounds = (min(r[1] for r in rows),rows[0][0],max(r[2] for r in rows),rows[-1][0]+1)
        islands.append((area,bounds,rows))
    return islands


def separated_by(a,b):
    return math.hypot(max(0,a[0]-b[2],b[0]-a[2]),max(0,a[1]-b[3],b[1]-a[3]))


def bounds_size(bounds):
    x,y,right,bottom = bounds
    return x,y,right-x,bottom-y


def masked_sprite(image, group):
    bounds = (min(part[1][0] for part in group),min(part[1][1] for part in group),
              max(part[1][2] for part in group),max(part[1][3] for part in group))
    x,y,w,h = bounds_size(bounds)
    mask = np.zeros((h,w),dtype=np.uint8)
    for _,_,rows in group:
        for yy,left,right in rows:
            mask[yy-y,left-x:right-x] = 255
    sprite = image.crop(bounds)
    alpha = np.minimum(mask,np.asarray(sprite.getchannel("A")))
    sprite.putalpha(Image.fromarray(alpha))
    return sprite


def pack_sprites(sprites, output):
    canvas = Image.new("RGBA", (1536, 2100))
    x, y, row = 2, 2, 0
    regions = {}
    for name, image in sorted(sprites.items()):
        image.thumbnail((300,285),Image.Resampling.LANCZOS)
        if x+image.width+3 >= canvas.width:
            x,y,row = 2,y+row+4,0
        canvas.paste(image,(x,y))
        regions[name] = [x,y,image.width,image.height]
        x += image.width+4
        row = max(row,image.height)
    canvas.crop((0,0,canvas.width,y+row+2)).save(output, optimize=True)
    return regions


def catalog(buildings, nature, structures, planting, market):
    stamps = {}
    for path, keys in [(buildings,BUILDINGS),(nature,NATURE),(structures,STRUCTURES),(planting,PLANTING),(market,MARKET)]:
        stamps.update(extract_sheet(path,keys))
    del stamps["bridge"]
    widths = {"banyan":282,"willow":100,"young_willow":83,"grove":88,"blossom":103,
              "bank_rocks":42,"bank_shrub":67,"reeds":43,"wild_ivory":30,"wild_gold":30,"wild_pink":30,
              "teal_stall":111,"snack_stall":111,"lantern_cart":102,"tea_table":87,"stone_seat":31,"festival_lamp":39}
    for key,width in widths.items():
        art = stamps[key]
        stamps[key] = art.resize((width,max(1,round(art.height*width/art.width))),Image.Resampling.LANCZOS)

    def from_atlas(name, filename, rect):
        x,y,w,h = rect
        sheet = Image.open(ASSETS / filename).convert("RGBA")
        tile = sheet.crop((x,y,x+w,y+h))
        stamps[name] = tile.crop(tile.getchannel("A").getbbox())

    def from_grid(name, filename, index, size, stride=320, columns=4):
        w,h=size
        from_atlas(name,filename,(index%columns*stride+(stride-w)//2,index//columns*stride+stride-4-h,w,h))

    for name, index, size in [
        ("stable",1,(158,113)),("gate",2,(214,204)),("furniture",7,(149,84)),("storydesk",8,(59,77)),
        ("pier",10,(170,136)),("bamboo",15,(192,162)),("rock",16,(141,113)),("peony",9,(87,61))]:
        from_grid(name,"jiangnan-landmarks-v1.png",index,size)
    for name, index, size in [("stools",11,(46,27)),("cart",2,(112,111)),("teastall",3,(126,126))]:
        from_grid(name,"jiangnan-square-v1.png",index,size,stride=240)
    for name, rect in {"forge":(329,340,249,272),"dyer":(582,340,268,238),"tofu":(0,616,242,219),
                       "nightshops":(0,839,500,151),"crates":(276,996,107,92),"smallcart":(387,996,114,82),
                       "crock":(0,996,50,54),"stone_mill":(505,996,101,108),"laundry":(582,340,268,60)}.items():
        from_atlas(name,"jiangnan-traders-v1.png",rect)
    from_atlas("lighthouse","harbor-estuary-v1.png",(1476,259,146,306))
    from_atlas("junk","harbor-estuary-v1.png",(735,251,542,417))
    from_atlas("gallery","jiangnan-frontage-v1.png",(342,74,275,242))
    from_atlas("cottageroof","jiangnan-frontage-v1.png",(10,61,300,255))
    for name in ("diner","bank","grocer","inn","terminal","house","forge","dyer","tofu","nightshops","stable"):
        stamps[name] = damp_wall(stamps[name])
    stamps["blossom"] = shade_blossoms(stamps["blossom"])
    household = Image.open(ROOT/"tools/map_art/jiangnan-household.png").convert("RGBA")
    for i, name in enumerate(("laundry","stools","crock","firewood","greens","barrel")):
        x,y = i%3*96,i//3*96
        cut = household.crop((x,y,x+96,y+96))
        stamps[name] = cut.crop(cut.getchannel("A").getbbox())
    # Extend the wood between the two end frames; retain the original leg width.
    stool = stamps["stools"]
    third = stool.width//3
    board = stool.crop((third,0,stool.width-third,stool.height))
    bench = Image.new("RGBA",(stool.width+board.width*3,stool.height))
    bench.paste(stool.crop((0,0,third,stool.height)),(0,0))
    for i in range(4):
        bench.paste(board,(third+board.width*i,0))
    bench.paste(stool.crop((stool.width-third,0,stool.width,stool.height)),(bench.width-third,0))
    stamps["bench"] = bench
    stamps["fishnet"] = Image.open(ROOT/"tools/map_art/jiangnan-fishing-net.png").convert("RGBA")
    stamps["shadow"] = ground_shadow()
    return pack_sprites(stamps,ASSETS/"jiangnan-map-props-v2.png")


def ground_shadow():
    x,y = np.meshgrid(np.linspace(-1,1,56),np.linspace(-1,1,24))
    d = x*x+y*y + ((x*134+y*77)%11)*.021
    opacity = np.clip((1.08-d)*106,0,100).astype(np.uint8)
    image = Image.new("RGBA",(56,24),"#243b29")
    image.putalpha(Image.fromarray(opacity))
    return image


def sprite_for(part):
    id_ = part["id"]
    direct = {"diner":"diner","bank":"bank","chen-food-shop":"grocer","inn":"inn","inn-stable":"stable",
              "harbor-terminal":"terminal","harbor-beacon":"lighthouse","square-stage":"theatre","river-pavilion":"pavilion",
              "south-entrance-gate":"gate",
              "east-tea-dock":"teastall","river-pier-stall":"teastall","ferry-junk":"junk","forge":"forge",
              "dyers-and-tofu-makers":"dyer","crafts-wood-shop":"tofu","food-street-west":"nightshops",
              "food-street-east":"nightshops","food-street-benches":"furniture","food-street-benches-east":"furniture",
              "square-cart":"cart","square-upper-stall":"teastall","square-storyteller-desk":"storydesk",
              "market-blue-fish-stall":"fish","waterfront-show-stage":"theatre","harbor-cargo-crates":"crates",
              "harbor-dock-crates":"crates","plaza_banyan":"banyan"}
    if id_ in direct:
        return direct[id_]
    if part["layer"] == "foliage":
        if "willow" in id_: return "willow"
        if "cherry" in id_: return "blossom"
        return "grove"
    if id_.startswith("covered-boat-"):
        return "sampan"
    if "homes" in id_ or "house" in id_ or "court" in id_:
        return ("house","gallery","cottageroof")[sum(map(ord,id_))%3]
    if "stool" in id_:
        return "stools"
    if "stall" in id_ or "kiosk" in id_:
        return "produce" if "blue" not in id_ else "fish"
    raise ValueError(f"No independent art for scenic object {id_}")


def place_polished_props(parts, edits):
    props = []
    for part in parts:
        if part["id"] in ("north-stone-bridge", "south-stone-bridge", "pavilion-wood-deck"):
            continue
        row = dict(part, sprite=sprite_for(part))
        edit = edits.get(part["id"])
        if edit is not None:
            x,y,w,h = edit["pose"]
            row.update(foot=[x,y],rect=[x-w*.5,y-h,w,h],
                       bases=edit.get("bases",row["bases"]),sprite=edit.get("sprite",row["sprite"]))
        # Scale the ground plan around each prop's feet; the geography expands
        # but a door, chair or cart keeps its existing size relative to a person.
        fx, fy = row["foot"]
        def compact(rect):
            x, y, width, height = rect
            return [fx + (x-fx)*PROP_SCALE, fy + (y-fy)*PROP_SCALE,
                    width*PROP_SCALE, height*PROP_SCALE]
        row["rect"] = compact(row["rect"])
        row["bases"] = [compact(rect) for rect in row["bases"]]
        props.append(row)
    return props


def map_props(masks, regions, streetscape):
    definition = load_data("jiangnan_reference_visuals.json")
    polish = load_data("jiangnan_scene_polish.json")
    props = place_polished_props(definition["parts"], polish["props"])
    land, woods, roads, squares = [np.asarray(im)>0 for im in masks]
    forbidden = Image.fromarray(np.maximum.reduce([np.asarray(streetscape[key])
        for key in ("paved","shore","market")]+[np.asarray(masks[1])]))
    scenery = Image.open(ASSETS/"jiangnan-map-props-v2.png")
    entries = fit_buildings(props,regions,scenery,masks[0],forbidden,streetscape["port_lawn"])
    path_exclusion = Image.fromarray(np.maximum(np.asarray(streetscape["wharf"]),np.asarray(streetscape["market"])))
    paths, path_mask = paint_frontages(entries,masks[0],streetscape["paved"],path_exclusion)
    scenic_boxes = [p["rect"] for p in props]
    squares = squares | path_mask
    rng = random.Random(21908)

    def item(name, sprite, point, width, layer="foliage"):
        x,y = point
        props.append({"id":name,"layer":layer,"sprite":sprite,"foot":[x,y],"rect":[x-width*.5,y,width,0],"bases":[]})

    for i,(x,y) in enumerate(polish["waterfront_lamps"]):
        item(f"waterfront-lamp-{i}","festival_lamp",(x,y),10,"structures")

    for yy in range(18, HEIGHT-3, 24):
        for xx in range(9, WIDTH-6, 22):
            x = min(WIDTH-3, max(4, xx+rng.randrange(-8,9)))
            y = min(HEIGHT-3, max(5, yy+rng.randrange(-9,10)))
            if woods[y,x] and rng.random() > .085:
                if y > 846 and x < 468 and (x+y)%9 < 4:
                    continue
                species = rng.choices(("grove","blossom","willow"),(82,12,6))[0]
                item(f"grove-{yy}-{xx}",species,(x,y),rng.randrange(33,66))

    shoreline = np.asarray(Image.fromarray((land*255).astype(np.uint8)).filter(ImageFilter.MaxFilter(29)))>0
    wet_edges = shoreline & ~land
    shore_distance = np.asarray(Image.fromarray((land*255).astype(np.uint8)).filter(ImageFilter.MinFilter(29)))==0
    collision = load_data("jiangnan_reference_geography.json")
    decks = np.asarray(union(collision["public_decks"].values()))>0
    considered = []
    bridge_clearance = np.asarray(union([
        [[859,228],[1066,224],[1070,292],[863,297]],
        [[808,551],[998,548],[1001,621],[815,629]],
    ]))>0
    for i,(x,y,species,width) in enumerate(polish["southwest_planting"]):
        if land[y,x] and not roads[y,x] and not decks[y,x]:
            item(f"southwest-plant-{i}",species,(x,y),width)
            considered.append((x,y))

    flowers = ("wild_ivory", "wild_gold", "wild_pink")
    for index in range(3100):
        x,y = rng.randrange(12,WIDTH-12),rng.randrange(26,HEIGHT-7)
        if woods[y,x] or decks[y,x] or roads[y,x] or squares[y,x] or bridge_clearance[y,x]:
            continue
        if not land[y,x] and not wet_edges[y,x]:
            continue
        if any(abs(rect[0]+rect[2]*.5-x)<rect[2]*.5+8 and rect[1]-10<y<rect[1]+rect[3]+10
               for rect in scenic_boxes):
            continue
        if any(abs(px-x)<12 and abs(py-y)<11 for px,py in considered):
            continue
        if land[y,x]:
            if shore_distance[y,x]:
                species = rng.choices(("reeds","bank_rocks","young_willow"),(59,39,2))[0]
            elif rng.random() < .22:
                species = flowers[(x+2*y)%len(flowers)]
            elif rng.random() < .11:
                species = "peony"
            elif rng.random() < .17:
                species = "reeds"
            else:
                continue
        else:
            if y < 302 or rng.random() > .34:
                continue
            species = "lotus"
        if species in flowers:
            span = rng.randrange(10,20)
        elif species == "young_willow":
            span = rng.randrange(32,49)
        else:
            span = rng.randrange(7,20)
        item(f"detail-{index}",species,(x,y),span)
        considered.append((x,y))

    bank_index = 0
    for id_, outline in collision["land"].items():
        for (ax,ay),(bx,by) in zip(outline,outline[1:]+outline[:1]):
            distance = math.hypot(bx-ax,by-ay)
            if distance < 6: continue
            for along in np.arange(rng.uniform(.1,5),distance,rng.uniform(10,17)):
                x,y = round(ax+(bx-ax)*along/distance),round(ay+(by-ay)*along/distance)
                if not 5 < x < WIDTH-6 or not 107 < y < HEIGHT-5:
                    continue
                if any(mask[y,x] for mask in (woods,decks,roads,bridge_clearance)) or not shoreline[y,x]:
                    continue
                if id_ == "east_bank" and 1110 < x < 1585 and 555 < y < 678:
                    continue
                if any(abs(px-x)<10 and abs(py-y)<9 for px,py in considered):
                    continue
                piece = rng.choices(("bank_rocks","reeds","wild_ivory","wild_pink"),(63,14,14,9))[0]
                item(f"bank-detail-{bank_index}",piece,(x,y),rng.randrange(15,30))
                bank_index += 1
    planting = rng.sample([(x,y) for y in range(108,844,33) for x in range(35,1640,37)], 740)
    dry_grass = land & ~woods & ~(np.asarray(forbidden)>0) & ~path_mask
    for i,(cx,cy) in enumerate(planting):
        x,y = cx+rng.randrange(-10,11),cy+rng.randrange(-10,11)
        if not dry_grass[y-3:y+4,x-4:x+5].all() or any(
            bx-15<x<bx+bw+15 and by-10<y<by+bh+17 for bx,by,bw,bh in scenic_boxes
        ):
            continue
        grove = i%5 == 0 and dry_grass[y-20:y+8,x-16:x+17].all()
        kind = ("grove","blossom","young_willow")[i%3] if grove else flowers[i%len(flowers)]
        item(f"lawn-plant-{i}",kind,(x,y),rng.randrange(27,43) if grove else rng.randrange(10,18))
    for i,(x,y) in enumerate([(593,251),(670,307),(768,298),(880,159),(1108,335),
                              (1498,124),(1564,360),(1465,469),(564,788),(796,841),
                              (1530,170),(1458,222),(1551,427),(1142,364),(747,214),(622,315)]):
        for j,(dx,dy,species,width) in enumerate([
            (0,0,"bank_shrub",33),(16,6,"bank_shrub",25),(-18,5,"rock",33),
            (10,14,"wild_ivory",16),(-9,14,"wild_pink",17),(24,10,"wild_gold",13),
        ]):
            px,py=x+dx,y+dy
            if dry_grass[py-6:py+5,px-9:px+10].all() and not any(
                bx-12<px<bx+bw+12 and by<py<by+bh+14 for bx,by,bw,bh in scenic_boxes
            ):
                item(f"garden-group-{i}-{j}",species,(px,py),width)
    for i,(x,y) in enumerate([(80,61),(335,53),(677,53),(873,52),(1215,53),(1440,58),
                              (1578,72),(1626,165),(1633,250),(1629,335),(1634,445)]):
        item(f"forest-bamboo-{i}","bamboo",(x,y),rng.randrange(42,65))
    for i,entry in enumerate(entries):
        x,y,w,h=entry["bounds"]
        dx,dy=entry["door"]
        side = -1 if i%2==0 else 1
        variants = [("crock",16),("firewood",25),("stone_mill",20),("laundry",32)]
        species,width=variants[i%len(variants)]
        px,py=round(dx+side*(w*.43)),round(dy+5)
        for side in (side,-side):
            px=round(dx+side*(w*.41))
            if dry_grass[py,px] and not any(
                bx<px<bx+bw and by<py<by+bh for bx,by,bw,bh in scenic_boxes
            ):
                item(f"door-prop-{i}",species,(px,py),width,"structures")
                break
        for j, fraction in enumerate((.18,.76)):
            px = round(x+w*fraction)
            py = round(dy+1+(i+j)%3)
            if not dry_grass[py-1:py+3,px-4:px+5].all():
                continue
            if any(abs(part["foot"][0]-px)<13 and abs(part["foot"][1]-py)<8
                   for part in props if part["id"].startswith("door-prop-")):
                continue
            shrub = entry["id"].startswith(("west-","north-west-","east-")) or j == i%2
            kind = "bank_shrub" if shrub else "reeds"
            item(f"wall-growth-{i}-{j}",kind,(px,py),rng.randrange(13,21) if shrub else rng.randrange(9,14))
    for i,(x,y,sprite,width) in enumerate([
        (327,503,"stools",13),(485,514,"stools",12),(464,519,"stools",12),
        (509,512,"smallcart",30),(355,487,"tea_table",38),(561,522,"stools",14),
        (1200,649,"fishnet",31),(1459,631,"fishnet",34),(1035,780,"fishnet",20),
        (285,717,"greens",16),(346,731,"barrel",14),(415,717,"greens",17),
        (497,727,"barrel",15),(675,723,"greens",18),(382,260,"greens",17),(411,274,"barrel",15),
    ]):
        item(f"street-life-{i}",sprite,(x,y),width,"structures")
    for i,tree in enumerate([p for p in props if p["sprite"]=="blossom" and p["foot"][0]>1000 and p["foot"][1]<450]):
        x,y=map(round,tree["foot"])
        if dry_grass[y,x]:
            item(f"blossom-underbrush-{i}","bank_shrub",(x+4,y+2),22)
    shadows = contact_shadows(entries, props, regions, scenery, masks[0], streetscape["paved"])
    return props, paths, shadows, entries


def main():
    from town_contacts import jiangnan_contacts
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("terrain", "buildings", "nature", "structures", "materials", "planting", "market", "out"):
        parser.add_argument(f"--{name}", type=Path, required=True)
    args = parser.parse_args()
    quay_masonry = terrain_atlas(args.terrain,args.materials)
    atlas = catalog(args.buildings,args.nature,args.structures,args.planting,args.market)
    geography = load_data("jiangnan_reference_geography.json")
    rows, masks, streetscape = tile_rows(geography)
    street_pattern = apply_reference_paving(rows)
    main_quay = native_coverage(grid_masks(streetscape["main_quay"]))
    wall = quay_masonry_face(main_quay,quay_masonry,native_coverage(grid_masks(masks[0])))
    wall_exclusion = wall.getchannel("A").resize((WIDTH, HEIGHT), Image.Resampling.NEAREST)
    props, frontages, shadows, entries = map_props(masks,atlas,streetscape)
    wear = weathered_ground(masks[0],streetscape["stone"],streetscape["decks"])
    wear.putalpha(Image.fromarray(np.where(np.asarray(wall_exclusion)>0,0,
        np.asarray(wear.getchannel("A"))).astype(np.uint8)))
    props = [p for p in props if not (p["id"].startswith(("detail-","bank-detail-")) and
        wall_exclusion.getpixel(tuple(map(round,p["foot"])))) ]
    rows.update(detail_atlas({"GroundDetails":frontages, "ContactShadows":shadows,"SurfaceDetails":wear,"QuayWall":wall},
        COLS,ROWS,TILE_PIXELS,ASSETS/"jiangnan-map-frontages-v1.png"))
    jiangnan_contacts(props,atlas,Image.open(ASSETS/"jiangnan-map-props-v2.png").getchannel("A"))
    decks = geography["public_decks"]
    bridge_art = bridge_atlas({key:decks[key] for key in BRIDGES},street_pattern,quay_masonry,
        WORLD_SCALE*TILE_PIXELS/TILE_WORLD,ASSETS/"jiangnan-map-arches-v1.png")
    args.out.parent.mkdir(parents=True,exist_ok=True)
    args.out.write_text(json.dumps({"tile_pixels":TILE_PIXELS,"tile_world":TILE_WORLD,"variants":VARIANTS,
        "source_scale":WORLD_SCALE,"layers":rows,"props":props,"prop_regions":atlas,
        "bridge_art":bridge_art,"bridge_art_scale":ART_SCALE,"timber":{key:decks[key] for key in TIMBER},
        "entries":entries},separators=(",",":")),encoding="utf-8")
    footprints = {"parts":[dict(id=row["id"],bases=row["bases"]) for row in props if row["bases"]]}
    footprints["survey"] = parcel_survey(rows, props, streetscape["sand"])
    (TOWN / "jiangnan_map_footprints.json").write_text(json.dumps(footprints,separators=(",",":"))+"\n",encoding="utf-8")
    print(", ".join(f"{name}={len(layer)}" for name,layer in rows.items()), f"scenery={len(props)}")


if __name__ == "__main__":
    main()
