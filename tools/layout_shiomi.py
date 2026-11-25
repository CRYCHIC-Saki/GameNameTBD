"""Assemble Shiomi from original sprite/material sheets. Coordinates are in
the approved artist's 1536 x 1024 composition. No overview image is an input.
Run with --sheets buildings.png vegetation.png surfaces.png village.png coast.png once to cut the kit.
Subsequent layout builds reuse the project's packed art and region manifest.
"""
from building_footprints import SHIOMI, stamp_building
import argparse
import base64
import json
import math
import random
import struct
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance
import shiomi_finishes as finishes
import shiomi_survey as cadastral

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "assets/town"
SRC = ROOT / "src/town"
CELLS = 73
ORIGIN = (8, 17)
STEP = 24  # reference pixels per economic cell
UNIT = 6   # fine terrain tile in reference pixels
SPRITES = ("shrine torii produce stage bank office tower fish inn bath port mill "
           "sakura pine bamboo azalea crag reef wheel boat lantern bridge house tubs").split()
GRASS, STONE, SEA, DECK, CLIFF, RICE, SAND, STREAM, BRIDGE, PALE_STONE, QUAY, DRY_BED, BEACH = range(13)
TILES = ("Meadows", "Streets", "Sea", "Wharf", "Escarpments",
         "RiceTerraces", "DryGarden", "Watercourse", "Crossings", "WhiteCourts", "QuayStone", "DryRiverbed","ShellBeach")
REGIONS = ROOT / "tools/map_art/shiomi-regions.json"


def prepare_kit(paths):
    atlas = Image.new("RGBA", (416 * 4, 352 * 10))
    regions = {}
    for sheet, path in enumerate(paths[:2]):
        src = Image.open(path).convert("RGBA")
        for i in range(12):
            row, col = divmod(i, 4)
            # The painted gutters are slightly staggered between rows.
            xs = ([[0, 360, 718, 1090, 1536], [0, 396, 767, 1060, 1536],
                   [0, 411, 774, 1136, 1536]][row] if sheet == 0 else [0, 386, 773, 1153, 1536])
            ys = [0, 337, 687, 1024]
            box = (xs[col], ys[row], xs[col+1], ys[row+1])
            pic = src.crop(box)
            alpha = pic.getchannel("A").point(lambda a: 0 if a < 95 else min(255, a * 2))
            pic.putalpha(alpha)
            pic = pic.crop(alpha.getbbox())
            key = SPRITES[sheet*12+i]
            if key == "wheel":
                # The wheel rotates, its fixed wooden trestle belongs to the mill.
                diameter = min(pic.width, round(pic.height * .94))
                pic = pic.crop((0, 0, diameter, diameter))
                a = np.array(pic)
                yy, xx = np.ogrid[:diameter, :diameter]
                a[(xx-diameter/2)**2+(yy-diameter/2)**2 > (diameter/2)**2, 3] = 0
                pic = Image.fromarray(a)
            pic.thumbnail((405, 340), Image.Resampling.NEAREST)
            xy = (col*416+4, (row+3*sheet)*352+4)
            atlas.paste(pic, xy)
            regions[key] = [*xy, *pic.size]
    names = ["bench fence fall shore zen buckets housewares pigeons",
             "meadow ledge outcrop hydrangea pier cargo dwarf basin"]
    for sheet, names_row in enumerate(names):
        props = Image.open(paths[3+sheet]).convert("RGBA")
        pw, ph = props.size
        for i, name in enumerate(names_row.split()):
            row,col=divmod(i,4)
            xs=([0,390,879,1338,pw] if sheet==1 and row==0 else [j*pw//4 for j in range(5)])
            pic=props.crop((xs[col],row*ph//2,xs[col+1],(row+1)*ph//2))
            alpha=pic.getchannel("A").point(lambda a: 0 if a<100 else min(255,2*a))
            pic.putalpha(alpha)
            pic=pic.crop(alpha.getbbox())
            pic.thumbnail((404,338),Image.Resampling.NEAREST)
            xy=(col*416+4,(row+6+sheet*2)*352+4)
            atlas.paste(pic,xy)
            regions[name]=[*xy,*pic.size]
    finishes.clean_foliage(atlas, regions)
    atlas.save(ART/"shiomi-sprites-v1.png")
    REGIONS.write_text(json.dumps(regions, indent=2)+"\n")
    source = Image.open(paths[2]).convert("RGB")
    # Mirrored repeats avoid cut seams in the hand-painted ground materials.
    tiles = Image.new("RGB", (96*12, 96))
    for i in range(8):
        row, col = divmod(i, 4)
        w, h = source.size
        patch = source.crop((col*w//4+4, row*h//2+4, (col+1)*w//4-4, (row+1)*h//2-4))
        if i==1:
            # At walking scale one paving stone should read as a slab.
            pw,ph=patch.size
            patch=patch.crop((pw*.25,ph*.25,pw*.75,ph*.75))
        patch = patch.resize((48,48), Image.Resampling.LANCZOS)
        if i in [0,2,5]:
            patch = ImageEnhance.Contrast(patch).enhance(.69)
        if i==STONE:
            patch=ImageEnhance.Color(patch).enhance(.52)
            patch=ImageEnhance.Brightness(patch).enhance(1.31)
        if i==7:
            patch=ImageEnhance.Color(patch).enhance(.34)
        for y in range(2):
            for x in range(2):
                cell = patch.transpose(Image.Transpose.FLIP_LEFT_RIGHT) if x else patch
                if y: cell = cell.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
                tiles.paste(cell,(i*96+x*48,y*48))
    lawn=tiles.crop((0,0,96,96))
    for index,color in enumerate([(130,145,67),(100,125,56),(152,150,71),(99,125,70)]):
        tiles.paste(Image.blend(lawn,Image.new("RGB",(96,96),color),.39),(96*(8+index),0))
    tiles.save(ART/"shiomi-ground-v1.png")


# Individual silhouettes of the main island, harbor cove and its southern headland.
coast = [(25,158),(83,99),(156,86),(235,77),(330,84),(440,107),(542,82),(630,101),
 (717,88),(805,109),(902,77),(989,84),(1080,64),(1190,65),(1263,81),(1378,66),
 (1459,117),(1494,199),(1514,249),(1461,291),(1468,352),(1510,404),(1481,488),
 (1450,529),(1431,561),(1463,609),(1492,643),(1436,672),(1368,651),(1282,628),
 (1184,607),(1122,614),(1079,650),(1027,675),(1021,710),(1100,738),(1185,770),
 (1311,794),(1367,827),(1322,857),(1244,886),(1160,911),(1070,912),(943,946),
 (817,958),(742,979),(639,955),(518,952),(406,932),(290,930),(211,904),(145,907),
 (61,858),(36,796),(50,761),(26,715),(93,677),(150,654),(123,633),(46,620),
 (14,589),(36,528),(21,490),(64,464),(18,438),(42,392),(31,353),(56,320),
 (12,292),(44,259),(38,230),(77,203),(38,190)]
roads = [
 (25,[(254,123),(260,170),(258,239),(258,301),(233,354),(235,393),(221,432),(201,477),(201,505),(216,523),(248,552),(269,601),(276,650),(300,684),(352,702),(425,688),(510,704),(547,717),(605,695),(668,668),(730,652),(788,615),(803,577),(794,540)]),
 (23,[(247,552),(312,528),(354,508),(407,496),(465,479),(518,457),(561,444),(623,422),(662,401),(692,363),(750,342),(828,340),(927,361),(1002,350),(1078,340),(1136,324),(1181,302)]),
 (23,[(926,359),(943,392),(935,441),(929,494),(951,517),(997,523),(1049,531),(1098,542),(1154,557),(1226,560),(1320,582)]),
 (24,[(664,405),(655,451),(659,508),(660,543),(723,548),(793,548),(858,552),(922,538),(947,518)]),
 (20,[(547,718),(523,750),(540,780),(574,820),(588,854),(617,881),(697,881),(783,895),(858,877),(878,852),(854,811)]),
 (17,[(873,858),(928,850),(1002,860),(1066,869),(1138,854),(1190,831),(1171,790)]),
 (18,[(301,678),(251,695),(210,701),(175,721),(155,753)]),
 (22,[(454,295),(491,295),(546,297),(602,300),(631,305),(654,316),(678,335),(694,363)]),
 (18,[(926,359),(935,312),(949,296)]),
 (15,[(254,353),(281,335),(359,318),(411,289),(488,296)]),
 (16,[(426,689),(453,656),(454,607)]),
]
# Place objects by their foot point. Width is always aspect-preserving.
objects = []
def obj(art,x,y,w,plot="",kind="",name="",base=.20):
    objects.append(dict(art=art,x=x,y=y,w=w,plot=plot,kind=kind,title=name,base=base))

obj("shrine",254,134,100,"landmark","landmark","坂下樱花参道")
obj("torii",255,292,119,base=0)
obj("produce",405,481,231,"market-neighborhood","market","町内食材铺")
obj("stage",450,633,208,"plaza","plaza","滨町能舞台")
obj("bank",793,516,248,"commercial_street:bank","bank","潮见信用金库")
obj("office",940,295,185,"office","landmark","潮见町役场")
obj("tower",1136,309,79,"watch","landmark","火之见橹")
obj("fish",1253,510,298,"market-main","market","湾岸鱼市")
obj("house",670,784,134,base=.13)
obj("house",924,785,137,base=.13)
obj("inn",807,809,296,"hotel","hotel","潮见旅馆")
obj("bath",1070,832,158,"onsen","landmark","潮见露天汤")
obj("port",1386,604,116,"harbor","harbor","潮见客港")
obj("mill",149,802,102,"workshops","supply_factory","水车坊")
obj("wheel",170,807,63,base=0)
obj("house",517,288,102,"competitor:shop:0","competitor","坂上食事处")
obj("house",623,291,94,"competitor:shop:1","competitor","青竹庵")
obj("house",601,396,98,"competitor:shop:2","competitor","町家食堂")
obj("house",197,682,91,"residences-b","rich_district","松荫民居")
obj("house",239,523,82,"residences-a","urban_village","浜町木屋巷")
obj("bridge",1274,246,78,base=0)
obj("boat",1164,700,95,base=0)
obj("boat",1413,746,111,base=0)
obj("tubs",1130,512,49)
for x,y,w in [(199,296,26),(346,298,25),(366,664,25),(584,662,24),(620,831,21),(1203,846,20)]:
    obj("lantern",x,y,w)
trees = {"sakura":[(84,164,115),(145,218,129),(172,124,113),(211,76,86),(321,112,113),(391,156,128),(336,222,107),(115,278,75),(822,259,90),(1047,145,88),(1411,187,72)],
"bamboo":[(475,141,88),(541,141,65),(716,114,85),(778,225,78),(1025,281,93),(1089,255,55),(1171,131,71),(1002,705,56)],
"pine":[(110,333,109),(573,91,103),(633,138,89),(675,209,93),(811,125,121),(929,100,104),(1004,89,88),(1411,115,112),(1482,228,87),(1421,325,116),(1173,382,109),(1004,416,91),(719,312,78),(112,470,92),(99,591,112),(636,478,94),(859,629,114),(1044,602,84),(78,729,112),(494,750,78),(662,812,80),(675,910,90),(938,882,99),(1229,804,115),(1316,811,67)]}
for art,placements in trees.items():
    for x,y,w in placements: obj(art,x,y,w,base=.09)

for px in [407,454,505,544]: obj("bench",px,654,29,base=.22)
for px in [146,178,220,250]: obj("fence",px,699,31,base=.17)
for px,py in [(146,271),(174,278),(198,292),(320,296),(348,290),(373,280),
              (438,183),(466,180),(494,177),(518,174),(619,274),(656,274),(682,268)]:
    obj("fence",px,py,30,base=.16)
for px,py,w in [(1285,142,66),(1260,199,45),(204,857,34),(213,920,40)]: obj("fall",px,py,w,base=0)
for px,py,w in [(715,824,34),(768,840,20),(690,841,16)]: obj("zen",px,py,w)
obj("buckets",1000,823,22)
obj("housewares",307,478,21)
obj("housewares",648,391,22)
obj("pigeons",397,636,15,base=0)
obj("pigeons",533,636,14,base=0)

# Pier pile faces, garden stones, a chozuya and groups of coastal plants.
for x,y in [(1113,601),(1154,602),(1195,618),(1237,619),(1286,638),(1327,640),(1372,642),(1417,645),(1461,645)]:
    obj("pier",x,y+7,44,base=0)
for x,y in [(1120,553),(1429,569),(1465,607)]: obj("cargo",x,y,27)
obj("basin",360,292,27)
for x,y,w in [(415,146,64),(590,161,89),(662,141,81),(797,147,85),(852,137,82),(909,143,77),(996,127,94),(1068,139,86),(1152,136,93),(1231,129,70),(1342,137,89),(1371,222,65),(1222,279,49)]:
    obj("ledge",x,y,w,base=.12)
for x,y,w in [(93,311,57),(357,306,58),(587,176,64),(777,147,75),(1010,160,66),(1190,162,61),(1397,198,68),(1359,340,56),(692,457,44),(904,323,36),(995,745,64),(663,830,57),(387,733,66),(1229,819,75),(123,719,63),(68,540,57)]:
    obj("dwarf",x,y,w,base=.09)
for x,y,w in [(691,510,31),(899,505,35),(843,318,36),(1010,315,37),(650,797,42),(945,806,42),(1104,848,33),(218,333,24),(1394,334,31)]:
    obj("hydrangea",x,y,w,base=.1)

# Building heights follow comparable Jiangnan facades. Walking characters in all
# three towns use OUTDOOR_PERSON_HEIGHT. x/y are the feet of each facade.
BUILDING_SIZES = {
    "shrine": (87,0,-2), "produce": (147,0,-5), "stage": (140,0,-18),
    "bank": (147,0,-5), "office": (145,0,-2), "tower": (62,0,0),
    "fish": (185,0,-4), "inn": (174,0,-14), "bath": (121,-111,-21),
    "port": (111,22,-60), "mill": (85,3,-1)
}

LAWN_PLACEMENTS = {
    "market-neighborhood": (405,453),
    "competitor:shop:0": (533,261),
    "competitor:shop:1": (632,276),
    "residences-a": (264,507),
    "residences-b": (197,665),
}


def resize_buildings(props):
    updated=[]
    for prop in props:
        art=prop["art"]
        if art=="fence" and prop["y"]==699:
            updated.append(dict(prop,y=675,on_existing_lawn=True))
            continue
        if art in BUILDING_SIZES:
            w,dx,dy=BUILDING_SIZES[art]
        elif art=="house":
            w=round(max(78,min(94,prop["w"]*.89)))
            dx,dy=0,-4
            if not prop["plot"] and prop["x"]==924:
                dx,dy=-63,-4  # the ryokan's side wing opens onto the bath court
        elif art=="wheel":
            w,dx,dy=52,0,0
        else:
            updated.append(prop)
            continue
        placement=LAWN_PLACEMENTS.get(prop["plot"])
        if placement:
            x,y=placement
            updated.append(dict(prop,w=w,x=x,y=y,on_existing_lawn=True))
        else:
            updated.append(dict(prop,w=w,x=prop["x"]+dx,y=prop["y"]+dy))
    return updated


def scenery_overlaps(prop):
    key,x,y=prop["art"],prop["x"],prop["y"]
    return (key in {"ledge","azalea","dwarf","meadow"} and (
                (1176<x<1230 and 225<y<293)
                or (1228<x<1315 and 185<y<224)
                or (1316<x<1380 and 216<y<240)
                or (1262<x<1307 and 104<y<145))
            or not prop["base"] and key in {"ledge","azalea","meadow","shore","dwarf","outcrop"} and 111<x<208 and 795<y<845
            or key in {"ledge","azalea","dwarf"} and 245<x<324 and 849<y<883
            or not prop["base"] and key in {"ledge","azalea","shore","crag","outcrop","reef"}
            and ((1450<x<1515 and 342<y<390) or (1259<x<1303 and 252<y<279)))


def smooth(points):
    result=[points[0]]
    for a,b in zip(points,points[1:]):
        for t in [.25,.75]:
            result.append(tuple(round(i+(j-i)*t) for i,j in zip(a,b)))
    return result+[points[-1]]

def ground_plan(profile=None):
    im = Image.new("L",(1536,1024),SEA)
    draw = ImageDraw.Draw(im)
    draw.polygon(coast,fill=CLIFF)
    draw.polygon([(x, y-15) for x,y in coast],fill=GRASS)
    if profile is None: profile=finishes.beach_profile()
    im.paste(SEA,mask=Image.fromarray(profile.wash))
    im.paste(GRASS,mask=Image.fromarray(profile.crown))
    im.paste(BEACH,mask=Image.fromarray(profile.sand))
    im.paste(CLIFF,mask=Image.fromarray(profile.rear_lip | profile.face))
    # Mossy ridge ledges and the stepped mountain stream.
    for pts in [[(399,103),(558,93),(693,105),(783,90),(828,111),(724,143),(544,147),(436,134)],
                [(861,94),(972,72),(1162,62),(1313,85),(1372,109),(1340,137),(1240,144),(1095,138),(961,149),(873,132)]]:
        draw.polygon(pts,fill=CLIFF)
    finishes.flow_path(im,finishes.DRY_CHANNEL,[19,25,29,32,30,25,16],DRY_BED)
    finishes.flow_path(im,finishes.MILL_CHANNEL,finishes.MILL_WIDTHS,STREAM)
    for bed in finishes.PADDIES:
        draw.polygon(bed,fill=RICE)
    for width,points in roads:
        draw.line(smooth(smooth(points)),fill=STONE,width=width,joint="curve")
    # The western bend widens on the outside; the inner margin follows the
    # residential garden, while the meadow keeps its original street frontage.
    draw.polygon([(215,418),(203,429),(191,443),(181,459),(175,480),
                  (177,503),(185,516),(200,530),(220,540),(240,548),
                  (221,520),(204,499),(205,472),(217,436)],fill=STONE)
    draw.rounded_rectangle((655,471,928,553),radius=12,fill=STONE)
    draw.ellipse(finishes.THEATRE_COURT,fill=PALE_STONE)
    draw.ellipse(finishes.INN_GARDEN,fill=SAND)
    draw.polygon(finishes.INN_DOOR_JOIN,fill=PALE_STONE)
    draw.polygon(finishes.QUAY_WATER_CUT,fill=SEA)
    draw.polygon(finishes.QUAY_OUTLINE,fill=QUAY)
    pier=Image.new("L",im.size)
    ImageDraw.Draw(pier).polygon(finishes.PIER_OUTLINE,fill=255)
    pier_over_sea=(np.asarray(pier)>0)&(np.asarray(im)==SEA)
    im.paste(DECK,mask=Image.fromarray(pier_over_sea.astype("uint8")*255))
    for width,points in finishes.BRIDGE_APPROACHES:
        approach=Image.new("L",im.size)
        ImageDraw.Draw(approach).line(smooth(smooth(points)),fill=255,width=width,joint="curve")
        # Hold the westward shoulder below the hillside lots while connecting
        # the last stones directly to the bridge posts.
        ImageDraw.Draw(approach).rectangle((0,0,1223,239),fill=0)
        im.paste(STONE,mask=approach)
    finishes.flow_path(im,finishes.NORTH_CHANNEL,[9,13,18,15,13,17,20,17,15],STREAM)
    finishes.flow_path(im,finishes.LOWER_RUN,finishes.LOWER_WIDTHS,STREAM)
    for outline in [finishes.SPRING_POOL,*finishes.FALL_POOLS,finishes.EAST_OUTFALL]:
        draw.polygon(outline,fill=STREAM)
    draw.line([(257,131),(257,341)],fill=STONE,width=33)
    above_water=Image.new("L",im.size)
    ImageDraw.Draw(above_water).polygon(finishes.BRIDGE_DECK,fill=255)
    crossed_water=(np.asarray(above_water)>0)&(np.asarray(im)==STREAM)
    navigation=Image.fromarray(np.where(crossed_water,BRIDGE,np.asarray(im)).astype("uint8"))
    return navigation,im


def write_map():
    reg=json.loads(REGIONS.read_text())
    beach_profile=finishes.beach_profile()
    ground,below_bridge=ground_plan(beach_profile)
    registered=objects[:]
    buildings=resize_buildings(registered)
    grass_art=finishes.grass_aprons(ground,buildings,reg,BUILDING_SIZES)
    rng=random.Random(48063)
    # Coastal ledges and free-standing reefs follow the shoreline; gaps form the dock entrance.
    for i,(x,y) in enumerate(coast):
        nx,ny=coast[(i+1)%len(coast)]
        if not (1080<x and 514<y<735):
            # Irregular tall cliff faces and lower clusters of rocks in the surf.
            length=math.hypot(nx-x,ny-y)
            strips=max(1,round(length/35))
            for part in range(strips):
                t=(part+.36)/strips
                cx=x+(nx-x)*t+rng.randint(-5,5);cy=y+(ny-y)*t
                if 192<cx<228 and cy>890: continue
                obj(rng.choice(["ledge","crag","ledge"]),cx,cy+rng.randint(1,9),rng.randint(44,80),base=0)
                if part%2==i%2 and (cy>670 or cx>1450 or cx<70):
                    obj("outcrop",cx+rng.randint(-14,14),cy+rng.randint(8,19),rng.randint(31,55),base=0)
        if y<100 or 1080<x and 520<y<735 or 150<x<245 and y>885: continue
        if i%2==0: obj("crag",x,y+7,rng.randint(48,81),base=0)
        if ny>y-60 and (y>655 or x<90 or x>1420):
            span=math.hypot(nx-x,ny-y)
            count=max(1,round(span/30))
            for j in range(count):
                t=(j+.5)/count
                obj("shore",x+(nx-x)*t,y+(ny-y)*t+3,rng.randint(31,49),base=0)
        if i%5==0: obj("reef",x+(12 if x>768 else -15),y+19,rng.randint(27,56),base=0)
    for x,y in [(380,745),(580,588),(990,480),(1401,379),(1154,406),(766,178),(89,411),(364,714),(1207,852),(1022,899),(1396,275),(575,198),(740,593),(903,309),(304,296),(1023,334),(156,646),(541,569)]:
        for _ in range(rng.randint(2,4)):
            px=x+rng.randint(-24,24);py=y+rng.randint(-10,10)
            if ground.getpixel((px,py))==GRASS: obj("azalea",px,py,rng.randint(12,31),base=0)
    # Underplant slopes and cliff tops in irregular drifts. Only decorative flowers
    # occupy the margins of clearings, so the centers remain available for leases.
    for x,y,w in [(101,389,48),(119,571,59),(384,703,50),(515,170,56),(1439,369,47),
                  (1187,431,29),(763,582,48),(555,570,42),(592,852,45),(373,842,58),
                  (911,911,55),(1071,886,47),(968,684,46),(896,570,40),(1354,290,58),
                  (1188,325,39),(952,201,42),(445,267,43),(363,171,47),(244,745,30)]:
        for j in range(7):
            xx=x+rng.randint(-32,32); yy=y+rng.randint(-16,16)
            if ground.getpixel((xx,yy))==GRASS: obj("meadow",xx,yy,rng.randint(w//3,w),base=0)
    for x,y in [(122,374),(427,129),(556,148),(791,146),(887,143),(1292,131),(1271,170),
                (1247,213),(1241,275),(1198,299),(1176,315),(1295,193),(1321,179),
                (1224,137),(1236,169),(1317,112),(1472,330),(1031,650),(946,934),
                (824,956),(531,923),(340,897),(301,872),(170,829),(173,801),(223,890)]:
        for j in range(3):
            px=x+rng.randint(-17,17);py=y+rng.randint(-6,6)
            if ground.getpixel((px,py)) in [STONE,BRIDGE,DECK]: continue
            obj("ledge" if j==0 else "azalea",px,py,rng.randint(27,56),base=0)
    for x,y,w in [(332,168,53),(377,206,43),(1127,127,58),(1170,100,66),(1336,113,65),
                  (1256,86,53),(706,106,61),(603,135,53),(437,157,55),(1365,234,42),
                  (1474,303,47),(1172,357,40),(1113,400,31),(88,787,51),(259,870,43)]:
        obj("bamboo" if x in [1127,1170,706,437] else "dwarf",x,y,w,base=.08)
    # TileMapLayer binary layout is version(uint16), followed by six little-endian
    # uint16 per cell (map x/y, atlas source, atlas x/y, alternative).
    tile_size=12
    cells=[bytearray(b"\0\0") for _ in TILES]
    full=np.pad(np.array(ground),((0,2),(0,0)),mode='edge')
    sampled=full[3::6,3::6]
    paving=Image.open(ART/"shiomi-ground-v1.png").convert("RGB")
    # Keep the registered survey coordinates and old reserves while updating
    # the surface art and exact pedestrian access in the staged areas.
    land=np.asarray(ground)
    terrain=Image.fromarray(np.where(grass_art | (beach_profile.rear_lip & (land==CLIFF)),GRASS,np.where(land==BRIDGE,np.asarray(below_bridge),land)).astype("uint8"))
    visual,stepping_stones=finishes.walking_finish(terrain,roads,smooth,GRASS,STONE,paving)
    painted=np.pad(np.asarray(visual),((0,2),(0,0)),mode='edge')
    creek=finishes.creek_colors(painted,STREAM)
    swatches=np.asarray(paving)
    edges=[]
    edge_keys={}
    tile_material=[0,1,3,4,5,6,7,3,4,7,1,1,2]
    for y,row in enumerate(sampled):
        for x,material in enumerate(row):
            light=math.sin(x*.115+math.sin(y*.13))+.8*math.cos(y*.105-x*.052)+.38*math.sin(x*.29+y*.12)
            grass_tex=8 if light>1.14 else 9 if light<-.75 else 10 if light>.46 else 11 if light<-.26 else GRASS
            tile_material[GRASS]=grass_tex
            surface=painted[y*6+3,x*6+3]
            tex=tile_material[surface]
            source,ax,ay=0,tex*8+x%8,y%8
            patch=painted[y*6:y*6+6,x*6:x*6+6]
            if np.any(patch!=surface) or surface in [QUAY,DRY_BED,STREAM]:
                # Preserve irregular verges at one reference pixel. These are small
                # reusable mixed-material tiles; no structures are baked into them.
                layer=np.repeat(np.repeat(patch,2,axis=0),2,axis=1)
                pixels=np.empty((12,12,3),dtype=np.uint8)
                for idx in np.unique(layer):
                    sx=(tile_material[idx]*8+x%8)*12
                    sy=(y%8)*12
                    brush=swatches[sy:sy+12,sx:sx+12]
                    if idx==STREAM:
                        brush=np.repeat(np.repeat(creek[y*6:y*6+6,x*6:x*6+6],2,axis=0),2,axis=1)
                    if idx==QUAY:
                        brush=np.clip(brush.astype(np.int16)+[12,12,9],0,255).astype("uint8")
                    if idx==DRY_BED:
                        luma=brush.mean(axis=2,keepdims=True)
                        brush=np.clip((luma-135)*.42+[169,158,130],0,255).astype("uint8")
                    pixels[layer==idx]=brush[layer==idx]
                key=pixels.tobytes()
                if key not in edge_keys:
                    edge_keys[key]=len(edges)
                    edges.append(Image.fromarray(pixels))
                index=edge_keys[key]
                source,ax,ay=1,index%64,index//64
            cells[material].extend(struct.pack("<6H",x,y,source,ax,ay,0))
    edge_sheet=Image.new("RGB",(64*12,math.ceil(len(edges)/64)*12))
    for k,tile in enumerate(edges): edge_sheet.paste(tile,(k%64*12,k//64*12))
    edge_sheet.save(ART/"shiomi-verges-v1.png")
    tiles=['[gd_resource type="TileSet" format=3]',
           '[ext_resource type="Texture2D" path="res://assets/town/shiomi-ground-v1.png" id="ground"]',
           '[sub_resource type="TileSetAtlasSource" id="tiles"]','texture = ExtResource("ground")','texture_region_size = Vector2i(12,12)']
    for y in range(8):
        for x in range(96): tiles.append(f'{x}:{y}/0 = 0')
    tiles.insert(2,'[ext_resource type="Texture2D" path="res://assets/town/shiomi-verges-v1.png" id="verges"]')
    tiles+=['[sub_resource type="TileSetAtlasSource" id="edges"]','texture = ExtResource("verges")','texture_region_size = Vector2i(12,12)']
    tiles += [f'{k%64}:{k//64}/0 = 0' for k in range(len(edges))]
    tiles+=['[resource]','sources/1 = SubResource("edges")' ,'tile_size = Vector2i(12,12)','sources/0 = SubResource("tiles")']
    (SRC/'shiomi_tiles.tres').write_text('\n'.join(tiles)+'\n')
    sheet=Image.open(ART/"shiomi-sprites-v1.png")
    alpha=sheet.getchannel("A")
    sx,sy,sw,sh=reg["outcrop"]
    reef_art=sheet.crop((sx,sy,sx+sw,sy+sh))
    for x,y,w in [(1195,748,30),(1318,780,21),(1391,865,48),(1305,902,28)]:
        obj("reef",x,y,w,base=0)
    scenic_objects=buildings+objects[len(registered):]
    scenic_objects.append(dict(art="fall",x=1491,y=398,w=62,base=0,plot=""))
    beach_mask=np.asarray(ground)==BEACH
    for prop in scenic_objects:
        prop["hidden_by_landscape"]=scenery_overlaps(prop)
        key=prop["art"]
        # Preserve a clear view of the stream from the bridge to the gravel fan.
        if key in {"ledge","azalea","meadow","dwarf"} and not prop["base"]:
            x,y=round(prop["x"]),round(prop["y"])
            if 1183<x<1295 and 251<y<325 and ground.getpixel((x,y)) in [STREAM,DRY_BED]:
                prop["hidden_by_landscape"]=True
        if key in {"ledge","shore","crag","outcrop","reef"} and not prop["base"]:
            x,y=round(prop["x"]),round(prop["y"])
            width=round(prop["w"])
            if beach_mask[max(0,y-width//3):y+7,max(0,x-width//2):x+width//2+1].any():
                prop["hidden_by_landscape"]=True
    # Anchor the foam skirt of each reef in open water, including on the
    # north-facing side of the headland, where a downward offset lands on turf.
    water=np.asarray(ground)==SEA
    for p in scenic_objects:
        if p["art"]!="reef": continue
        x,y,w=round(p["x"]),round(p["y"]),round(p["w"])
        radius=(w+1)//2
        def room(x,y):
            return (radius<=x<1536-radius and w//2<=y<1024-2 and
                    water[y-w//2:y+2,x-radius:x+radius+1].all())
        options=[(x+dx,y+dy) for dx in range(-72,73,3) for dy in range(-72,73,3)
                 if room(x+dx,y+dy)]
        if options:
            p["x"],p["y"]=min(options,key=lambda pos: (pos[0]-x)**2+(pos[1]-y)**2)
            p["hidden_by_landscape"]=False
        else:
            p["hidden_by_landscape"]=True
    contacts,wall_grasses=finishes.contacts(scenic_objects,reg,alpha,set(trees))
    sx,sy,sw,sh=reg["bridge"]
    bridge_art=sheet.crop((sx,sy,sx+sw,sy+sh))
    bridge_back,bridge_rail=finishes.paint_bridge(bridge_art)
    deck_text=",".join(f"{x},{y}" for x,y in finishes.BRIDGE_DECK)
    bounds=finishes.BRIDGE_FRAME
    rock_mask=Image.new("L",ground.size)
    layers=[
        ("TidalSand",-7,finishes.beach_finish(ground,BEACH,SEA,paving,beach_profile)),
        ("MeadowUndergrowth",-7,finishes.meadow(np.asarray(visual)==GRASS,objects,roads)),
        ("RoadVerge",-6,stepping_stones),
        ("BeachBluffs",-5,finishes.beach_escarpment(ground,CLIFF,BEACH,sheet,reg,beach_profile)),
        ("RakedSand",-6,finishes.raked_court(ground,PALE_STONE)),
        ("PaddyFields",-6,finishes.rice_paddies()),
        ("ShrineStairs",-5,finishes.shrine_staircase(paving)),
        ("TideAndMillBanks",-5,finishes.shoreline(ground,coast,SEA,STREAM,reef_art)),
        ("BankPlanting",-5,finishes.bank_planting(ground,GRASS,SEA,STREAM,sheet,reg,rock_mask)),
        ("WaterfallPools",-5,finishes.waterfall_pools(ground,STREAM,reef_art)),
        ("RiverbedStones",-5,finishes.dry_riverbed(ground,DRY_BED,STREAM)),
        ("BridgeWaterShadow",-3,finishes.bridge_water_shadow()),
        ("LandingTimbers",-4,finishes.harbor(ground,DECK,QUAY)),
        ("ContactInk",-2,contacts),("WallGrasses",0,wall_grasses),
        ("BridgeDeck",-2,bridge_back),("MountainSpring",-1,finishes.mountain_spring(sheet,reg)),
        ("MillHeadwater",-3,finishes.mill_headwater(ground,STREAM,sheet,reg)),("TidalOutfalls",1,finishes.outfalls(sheet,reg)),
        ("BridgeNearRail",1,bridge_rail)]
    blocks=finishes.fallen_blocks(sheet,reg,ground,BEACH)
    finish_resources,finish_nodes,rock_nodes=finishes.pack_layers(layers,ART,blocks)
    scene=['[gd_scene format=4]','[ext_resource type="Script" path="res://src/town/outdoor_atmosphere.gd" id="outdoors"]',
     '[ext_resource type="TileSet" path="res://src/town/shiomi_tiles.tres" id="tiles"]',
     '[ext_resource type="Texture2D" path="res://assets/town/shiomi-sprites-v1.png" id="sheet"]',
     '[ext_resource type="Script" path="res://src/town/shiomi_ambience.gd" id="ambience"]',
     '[ext_resource type="Texture2D" path="res://assets/town/shiomi-detail-tiles.png" id="detail_sheet"]',
     *finish_resources,
     '[node name="Shiomi" type="Node2D"]','y_sort_enabled = true','texture_filter = 1',
     f'metadata/bridge_lane = PackedVector2Array({deck_text})',
     f'metadata/bridge_bounds = Rect2({bounds[0]},{bounds[1]},{bounds[2]},{bounds[3]})']
    for i,layer in enumerate(TILES):
        scene += [f'[node name="{layer}" type="TileMapLayer" parent="."]','z_index = -8','scale = Vector2(0.5,0.5)',
          'tile_set = ExtResource("tiles")','tile_map_data = PackedByteArray("'+base64.b64encode(cells[i]).decode()+'")']
    scene+=finish_nodes
    walking_rocks=rock_mask.copy()
    mask=np.array(ground)
    protect=Image.new('L',ground.size,0)
    footprints=ImageDraw.Draw(protect)
    fixed=Image.new('L',ground.size,0)
    fixed_brush=ImageDraw.Draw(fixed)
    walls=Image.new('L',ground.size)
    foreground=Image.new("L",ground.size,0)
    plots=[]
    for i,o in enumerate(scenic_objects):
        key=o["art"]; x,y,w=o["x"],o["y"],o["w"]
        if key=="bridge": continue
        rx,ry,rw,rh=reg[key]; ratio=w/rw; h=rh*ratio
        base=0 if o["base"]==0 else max(3,h*o["base"])
        bw=w*(.18 if key in trees else .86)
        label=f'{key.capitalize()}{i:03}'
        scene += [f'[node name="{label}" type="Sprite2D" parent="."]',
          f'position = Vector2({x},{y})',f'scale = Vector2({ratio:.7f},{ratio:.7f})',
          'texture = ExtResource("sheet")','region_enabled = true',f'region_rect = Rect2({rx},{ry},{rw},{rh})',
          f'offset = Vector2(0, {-rh*.5})',f'metadata/art = "{key}"']
        if key=="wheel":
            # Center pivot at axle, above the fixed mill foundation.
            scene[scene.index(f'[node name="{label}" type="Sprite2D" parent="."]')+1]=f'position = Vector2({x},{y-h/2:.3f})'
            scene[-2]='offset = Vector2(0,0)'
            scene+=['z_index = 1']
        hidden=o["hidden_by_landscape"]
        if key=="pier" or hidden:
            # Individual piles now follow the true wharf profile. Open a small
            # pocket between the original outer rock sprites for the shell beach.
            scene+=['visible = false']
        if key in ["sakura","pine","bamboo","dwarf","azalea","shore","outcrop","crag","ledge","meadow"] and i%3==1:
            scene+=['flip_h = true']
        if o["plot"]: scene += [f'metadata/plot_id = "{o["plot"]}"']
        # A cleared plant no longer blocks feet. The flooded field itself
        # still reserves its ground against siting.
        if key in cadastral.ROCK_FEET and not hidden:
            flipped=i%3==1 and key in {"shore","outcrop","crag","ledge"}
            cadastral.rock_contact(rock_mask,key,x,y,w,h,flipped)
            cadastral.rock_contact(walking_rocks,key,x,y,w,h,flipped,alpha.crop((rx,ry,rx+rw,ry+rh)))
        if base and not hidden:
            footprints.rectangle((x-bw/2,y-base,x+bw/2,y),fill=1)
            if key not in cadastral.ROCK_FEET:
                scene += [f'metadata/base = Rect2({-bw/2:.2f},{-base:.2f},{bw:.2f},{base:.2f})']
                if key in SHIOMI:
                    stamp_building(walls,SHIOMI[key],(x,y),(w,h))
                else:
                    fixed_brush.rectangle((x-bw/2,y-base,x+bw/2,y),fill=1)
        if key=="torii":
            for dx in [-41,41]: fixed_brush.rectangle((x+dx-4,y-7,x+dx+4,y),fill=1)
        if (key in BUILDING_SIZES or key=="house") and not finishes.paved_building(o):
            scene+=['metadata/grass_footing = true']
        if not hidden and (key in trees or key in {"house","produce","stage","bank","office","tower","fish","inn","bath","port","mill","shrine","torii"}):
            silhouette=alpha.crop((rx,ry,rx+rw,ry+rh)).resize((round(w),round(h)),Image.Resampling.NEAREST)
            if key in trees and i%3==1: silhouette=silhouette.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            foreground.paste(255,(round(x-w/2),round(y-h),round(x-w/2)+silhouette.width,round(y-h)+silhouette.height),silhouette)
        if o["plot"] and o["plot"]!="harbor":
            anchor=registered[i]
            px,py,pw=anchor["x"],anchor["y"],anchor["w"]
            pb=pw*.86
            depth=max(3,pw*rh/rw*anchor["base"])
            ax=math.floor((px-pb/2)/STEP)+8
            ay=math.floor((py-depth)/STEP)+17
            ex=math.floor((px+pb/2)/STEP)+9
            ey=math.floor(py/STEP)+18
            footprints.rectangle((px-pb/2,py-depth,px+pb/2,py),fill=1)
            plots.append([o["plot"],o["kind"],o["title"],ax,ay,ex-ax,ey-ay,math.floor(px/STEP)+8,ey])
    for x,y,w,h,_ in blocks:
        if w>=15:
            for target in (rock_mask,walking_rocks): ImageDraw.Draw(target).ellipse((x-w*.38,y-h*.38,x+w*.38,y),fill=1)
    for x,y,w,h in [(102,811,23,13),(117,807,17,10),(1263,108,43,20),(1305,105,47,23),(1317,118,32,16),(1252,126,27,13)]:
        for target in (rock_mask,walking_rocks): cadastral.rock_contact(target,"ledge",x,y,w,h)
    scene+=rock_nodes
    dock_solids=Image.new("L",ground.size)
    scene+=finishes.dock_props(ground,DECK,QUAY,reg,dock_solids)
    scene+=['[node name="Weather" type="Node2D" parent="."]','z_index = 3','script = ExtResource("ambience")']
    scene.extend(['[node name="Atmosphere" type="Node2D" parent="."]', 'script = ExtResource("outdoors")'])
    (SRC/'shiomi_map.tscn').write_text('\n'.join(scene)+'\n',encoding='utf-8')
    footprints=np.array(protect)
    survey=[]
    for cy in range(CELLS):
        row=""
        for cx in range(CELLS):
            x=(cx-8)*STEP;y=(cy-17)*STEP
            if x<0 or y<0 or x+STEP>1536 or y+STEP>1024: row+="~"; continue
            patch=mask[y:y+STEP,x:x+STEP]
            material=patch[STEP//2,STEP//2]
            if (patch==STONE).sum()>=STEP*2: code="r"
            elif material in [STONE,SAND,DECK,BRIDGE,PALE_STONE,QUAY]: code={STONE:'r',SAND:'z',DECK:'d',BRIDGE:'b',PALE_STONE:'g',QUAY:'d'}[material]
            elif material in [SEA,STREAM]:code="~"
            elif material==BEACH:code="s"
            elif material==CLIFF:code="^"
            elif material==RICE:code="p"
            elif np.logical_or(patch==GRASS,patch==DRY_BED).all() and not footprints[y:y+STEP,x:x+STEP].any():
                code="v" if (patch==DRY_BED).sum()>=STEP*5 else "."
            else:code=","
            row+=code
        survey.append(row)
    # The atlas draws hover hints above its rendered texture. Exclude roofs and
    # crowns in that overlay without expanding their ground ownership or collision.
    measured=cadastral.survey(ground,rock_mask,walking_rocks,dock_solids,fixed,walls,survey,buildings,finishes.BRIDGE_FRAME,finishes.BRIDGE_DECK)
    measured["issued_sites"]=json.loads((ROOT/"tools/map_art/shiomi-issued-sites-v1.json").read_text(encoding="utf-8"))
    covered=np.array(foreground)>127
    visible=[]
    for cy,row in enumerate(survey):
        y=(cy-ORIGIN[1])*STEP
        clear=[]
        for cx,material in enumerate(row):
            x=(cx-ORIGIN[0])*STEP
            clear.append("." if measured["sites"][cy][cx]=="." and not covered[y:y+STEP,x:x+STEP].any() else "-")
        visible.append("".join(clear))
    (ROOT/'content/towns/shiomi_survey.json').write_text(json.dumps(dict(cells=survey,visible_lawn=visible,plots=plots,**measured),ensure_ascii=False,indent=1)+'\n',encoding='utf-8')

if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("--sheets",nargs=5)
    args=parser.parse_args()
    if args.sheets: prepare_kit(args.sheets)
    write_map()
