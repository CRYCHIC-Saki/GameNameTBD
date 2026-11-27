"""Native, non-colliding tile layers for Shiomi. All brush sizes are in map pixels."""
import base64
import math
import random
import struct
from typing import NamedTuple

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

PADDIES = [
    [(216,758),(223,751),(234,750),(244,746),(258,747),(270,743),(284,745),(291,749),
     (302,752),(304,759),(311,766),(307,772),(297,773),(287,779),(269,776),(251,782),(237,782),(230,776),(220,775)],
    [(230,796),(241,789),(256,788),(267,783),(279,782),(292,785),(303,780),(311,785),
     (315,792),(322,797),(318,805),(325,811),(318,819),(307,819),(297,826),(279,824),
     (264,831),(251,829),(244,822),(233,817),(231,807),(226,802)],
    [(242,847),(247,839),(263,838),(278,831),(294,832),(307,826),(317,828),(319,835),
     (327,842),(324,850),(330,857),(328,866),(318,872),(304,873),(295,880),(281,877),
     (269,883),(258,879),(253,871),(241,869),(238,859)]
]

# The two edges follow the arched plank surface above the river. Bank paving
# overlaps the ends, where the northern and southern rails both terminate.
BRIDGE_FRAME = (1230,195,88,57)
BRIDGE_BACK = [(1229,227),(1243,222),(1254,216),(1266,212),(1280,212),
               (1293,216),(1304,222),(1313,227),(1319,227)]
BRIDGE_FRONT = [(1229,242),(1243,234),(1254,228),(1266,224),(1280,224),
                (1293,228),(1304,235),(1319,242)]
BRIDGE_DECK = BRIDGE_BACK + BRIDGE_FRONT[::-1]
BRIDGE_APPROACHES = [
    (24, [(1171,307),(1186,299),(1201,285),(1214,265),(1219,246),(1224,237),(1232,234)]),
    (22, [(1316,235),(1333,231),(1350,222),(1380,205)])
]
FALL_POOLS = [
    [(1267,132),(1279,129),(1293,130),(1300,137),(1300,147),(1293,155),(1282,158),
     (1270,156),(1265,152),(1262,144)],
    [(1244,184),(1263,181),(1280,184),(1294,190),(1307,193),(1313,202),(1307,211),
     (1294,216),(1279,216),(1264,212),(1250,212),(1236,205),(1233,196)]
]
SPRING_POOL = [(1274,110),(1284,104),(1296,105),(1304,112),(1301,121),
               (1289,126),(1277,122),(1271,116)]
NORTH_CHANNEL = [(1292,112),(1288,126),(1284,139),(1277,151),(1257,164),
                 (1259,191),(1266,208),(1274,229),(1271,253)]
# A narrowing thread meanders inside the wider alluvial bed.
LOWER_RUN = [(1271,249),(1271,255),(1274,259),(1268,268),(1256,275),
             (1246,276),(1235,280),(1227,282),(1221,285),(1218,294),(1217,300)]
LOWER_WIDTHS = [17,16,14,13,10,9,7,5,4,3,1]
DRY_CHANNEL = [(1273,255),(1266,272),(1252,277),(1234,281),(1218,296),
               (1203,308),(1190,313)]
# The leat curves around the low forecourt before its right arm meets the wheel.
MILL_CHANNEL = [(114,811),(120,812),(130,815),(137,819),(144,823),(152,825),
                (161,824),(168,820),(172,814),(174,807),(178,804),(184,806),
                (192,812),(199,818),(204,825),(200,838),(207,853),(199,869),
                (209,886),(205,900),(212,920),(211,941)]
MILL_WIDTHS = [5,7,9,11,12,13,13,12,10,10,13,14,15,16,16,13,19,17,20,16,23,17]
EAST_OUTFALL = [(1467,353),(1474,352),(1482,357),(1486,369),(1491,378),
                (1504,387),(1512,394),(1506,401),(1494,398),(1486,388),
                (1479,378),(1477,366),(1469,363)]
THEATRE_COURT = (306,588,596,679)
INN_GARDEN = (619,792,855,868)
INN_DOOR_JOIN = [(699,801),(714,792),(743,789),(770,788),(803,789),(823,797),
                 (841,810),(825,818),(732,814)]
QUAY_TOP = [(1066,522),(1082,521),(1085,494),(1090,483),(1439,483),
            (1455,490),(1461,521),(1469,554),(1476,585)]
QUAY_FRONT = [(1476,585),(1428,586),(1364,587),(1293,587),(1219,588),
              (1161,588),(1117,590),(1097,586)]
QUAY_OUTLINE = QUAY_TOP+QUAY_FRONT[1:]+[(1090,557),(1066,552)]
QUAY_WATER_CUT = QUAY_FRONT+[(1097,627),(1107,686),(1508,686),(1510,593)]
PIER_OUTLINE = [(1098,584),(1475,582),(1477,655),(1472,664),(1226,665),
                (1223,624),(1107,624),(1100,618)]


def paved_building(prop):
    return prop["art"] in {"stage","inn","fish","port"}


def canvas():
    return Image.new("RGBA", (1536, 1024))


def flow_path(ground, points, widths, material):
    """Paint a continuous tapered channel with wet banks, one local span at a time."""
    brush=ImageDraw.Draw(ground)
    for (a,b),(wa,wb) in zip(zip(points,points[1:]),zip(widths,widths[1:])):
        length=max(1,math.ceil(math.dist(a,b)))
        for step in range(length+1):
            t=step/length
            x,y=(round(p+(q-p)*t) for p,q in zip(a,b))
            r=(wa+(wb-wa)*t)*.5
            brush.ellipse((round(x-r),round(y-r),round(x+r),round(y+r)),fill=material)


def restrict(image, mask):
    image.putalpha(Image.fromarray(np.where(mask, np.asarray(image.getchannel("A")), 0).astype("uint8")))


class BeachProfile(NamedTuple):
    sand: np.ndarray
    wet_depth: np.ndarray
    wash: np.ndarray
    crown: np.ndarray
    rear_lip: np.ndarray
    face: np.ndarray


# Survey the skyline of the facing bluff in screen coordinates. Both ends of
# every exposed vertical edge share x. The central break is the beach access.
BLUFF_CREST = [(1090,902),(1099,896),(1108,895),(1110,889),(1118,889),
               (1125,883),(1135,884),(1138,878),(1146,879),(1151,874),
               (1159,875),(1161,871),(1172,871),(1176,867),(1186,869),
               (1191,865),(1202,867),(1213,868),(1222,864),(1225,859),
               (1234,860),(1237,852),(1246,853),(1250,846),(1261,847),
               (1265,842),(1275,843),(1278,835),(1284,835),(1288,830),
               (1297,831),(1299,825),(1308,826),(1311,819),(1318,820),
               (1321,815),(1328,815),(1331,810),(1338,811),(1342,812)]
BLUFF_HEIGHT = [(1090,2),(1105,11),(1126,20),(1164,23),(1180,21),
                (1192,12),(1201,0),(1219,0),(1231,14),(1248,24),(1278,23),
                (1302,24),(1324,21),(1335,14),(1342,4)]



def coast_section(xs, survey):
    xp,yp=zip(*survey)
    return np.rint(np.interp(xs,xp,yp)).astype(int)


def beach_profile():
    # Trace just the onsen headland, tapering to rock at both ends of the cove.
    shore=[(1019,703),(1024,711),(1056,723),(1100,738),(1185,770),
           (1256,782),(1311,794),(1343,806),(1367,826),(1355,839),
           (1322,857),(1244,886),(1160,911),(1124,911),(1091,912)]
    yy,xx=np.mgrid[675:950,980:1410]
    best=np.full(xx.shape,np.inf)
    along=np.zeros_like(best)
    run=0
    for (x,y),(tx,ty) in zip(shore,shore[1:]):
        dx,dy=tx-x,ty-y
        length=math.hypot(dx,dy)
        t=np.clip(((xx-x)*dx+(yy-y)*dy)/length**2,0,1)
        dist=(xx-x-t*dx)**2+(yy-y-t*dy)**2
        closer=dist<best
        along[closer]=run+t[closer]*length
        best=np.minimum(best,dist)
        run+=length
    # Use the actual shore polygon for the sign. Testing the infinite tangent
    # of a segment leaves a stray sandy ray in the sea beyond a convex point.
    peninsula=Image.new("L",(430,275))
    ring=shore+[(975,912),(975,698)]
    ImageDraw.Draw(peninsula).polygon([(x-980,y-675) for x,y in ring],fill=255)
    inward=np.where(np.asarray(peninsula)>0,1,-1)*np.sqrt(best)
    taper=np.clip(np.minimum(along,run-along)/29,0,1)
    wave=np.sin(along*.095)+.65*np.sin(along*.33)
    outer=(7+1.7*wave)*taper
    inner=(19+4.2*np.sin(along*.035)+2.2*wave)*taper
    # A downward orthographic projection hides the entire rear wall behind
    # the plateau. Its narrow grass lip still stops feet at the actual drop.
    front_start=sum(math.dist(a,b) for a,b in zip(shore[:8],shore[1:9]))
    rear=along<front_start
    landward=(inward>=-outer)&(taper>0)
    rear_inner=(4+.8*wave)*taper
    top=coast_section(xx[0],BLUFF_CREST)
    height=coast_section(xx[0],BLUFF_HEIGHT)
    foot=top+height
    near_wall=(xx>=BLUFF_CREST[0][0])&(xx<=BLUFF_CREST[-1][0])
    before_tip=xx<=BLUFF_CREST[-1][0]
    crown=landward & (inward<=inner+38) & before_tip
    # Keep the existing rocky coast outside the authored section.
    crown &= rear | near_wall
    back_sand=rear & (inward<=rear_inner)
    fore_sand=near_wall & (yy>=foot)
    sand=landward & (back_sand | fore_sand | ~before_tip)
    face=landward & near_wall & (yy>=top) & (yy<foot) & ~back_sand
    lip=rear & before_tip & landward & (inward>rear_inner) & (inward<=rear_inner+7*taper)
    lip &= (yy<top) | ~near_wall
    sand &= ~face
    # Each outcrop ends on the same beach. The tide follows the surveyed cove.
    wash=(inward < -outer)&(inward > -25)&(taper>0)
    wet_depth=inward+outer
    def full(local):
        image=np.zeros((1024,1536),dtype=local.dtype)
        image[675:950,980:1410]=local
        return image
    return BeachProfile(full(sand),full(wet_depth.astype(np.float32)),
                        full(wash),
                        full(crown),full(lip),full(face))


def beach_finish(ground,beach,sea,paving,profile):
    mask=profile.sand & (np.asarray(ground)==beach)
    depth=profile.wet_depth
    y,x=np.where(mask)
    grain=np.asarray(paving)[y%96,192+x%96].mean(axis=1)
    grain=(grain-np.mean(grain))*.45+2.3*np.sin(x*.17+y*.32)+2*np.sin(x*.1-y*.06)
    dry=np.clip(depth[y,x]/13,0,1)[:,None]
    tones=(1-dry)*np.array([152,150,126])+dry*np.array([213,195,153])+grain[:,None]
    out=canvas()
    pixels=np.array(out)
    pixels[y,x,:3]=np.clip(tones,0,255)
    pixels[y,x,3]=255
    out=Image.fromarray(pixels)
    brush=ImageDraw.Draw(out)
    rng=random.Random(8604)
    for i in rng.sample(range(len(x)),len(x)//27):
        px,py=int(x[i]),int(y[i])
        brush.line((px,py,px+rng.choice([0,0,1,2]),py),fill=rng.choice(["#aeaa8a","#e7d9b0","#c0b08d"]))
    for i in rng.sample(range(len(x)),len(x)//475):
        px,py=int(x[i]),int(y[i])
        for _ in range(rng.randint(2,5)):
            dx,dy=px+rng.randrange(-4,5),py+rng.randrange(-2,3)
            if not mask[dy,dx]: continue
            brush.line((dx-1,dy,dx+1,dy),fill="#989783")
            brush.point((dx,dy-1),fill="#d4cdb4")
    # The wash follows the outer wet-sand edge. Break it into curling fragments.
    sea_pixels=np.asarray(ground)==sea
    wash=np.asarray(Image.fromarray(mask).convert("L").filter(ImageFilter.MaxFilter(5)))>0
    ys,xs=np.where(wash & sea_pixels)
    for px,py in zip(xs,ys):
        if math.sin(px*.085+py*.17)+.4*math.sin(px*.5-py*.44)>-.18:
            brush.point((px,py),fill=rng.choice(["#99c4bd","#cfdfce","#b4d2ca"]))
    return out


def beach_escarpment(ground,cliff,beach,sheet,regions,profile):
    """Paint exposed rock only where a vertical ray can see the south face."""
    native=np.asarray(ground)
    face=profile.face & (native==cliff)
    sand=native==beach
    ink=canvas()
    brush=ImageDraw.Draw(ink)
    rng=random.Random(1953)
    # The middle of the local intertidal rock brush supplies mineral grain;
    # the barnacles and white surf belong out to sea.
    sx,sy,w,h=regions["shore"]
    quarry=sheet.crop((sx+w//6,sy+h//4,sx+w*5//6,sy+h//2)).convert("L")
    grain=np.asarray(quarry.resize((97,24),Image.Resampling.BOX),dtype=int)
    start,end=BLUFF_CREST[0][0],BLUFF_CREST[-1][0]
    xs=np.arange(start,end+1)
    crest=coast_section(xs,BLUFF_CREST)
    height=coast_section(xs,BLUFF_HEIGHT)
    # Each fractured slab has its own width, depth of shade and mineral seam.
    joints=[start-11]
    while joints[-1]<end+10:
        joints.append(joints[-1]+rng.randint(7,19))
    shades=[rng.choice([-9,-5,0,2,7,11]) for _ in joints]
    for i,x in enumerate(xs):
        top=int(crest[i])
        depth=int(height[i])
        for y in range(top,top+depth):
            if not face[y,x]: continue
            dy=y-top
            shift=round(1.4*math.sin(y*.16+x*.029))
            slab=int(np.searchsorted(joints,x+shift,side="right")-1)
            u=x+shift-joints[slab]
            span=joints[slab+1]-joints[slab]
            # Broad fracture planes, a narrow light-catching left arris,
            # and a recessed right edge. Fissures run down the picture plane.
            facet=16 if u<span*.29 else -2 if u<span*.79 else -18
            if u==0: facet=-29
            if u==1 and dy>2: facet=18
            value=shades[slab]+facet+(grain[(y+slab*3)%24,(x+slab*13)%97]-84)*.49
            if dy>depth*.65: value-=7
            if 0<dy<3 and (x//4)%4: value+=8
            if dy>=depth-2: value-=14
            inkcolor=np.array([83,86,90])+round(value)
            if facet>0: inkcolor+=np.array([7,4,-1])
            brush.point((int(x),y),fill=tuple(np.clip(inkcolor,13,165).astype(int)))
        foot=top+depth
        if not depth or not face[foot-1,x]: continue
        # The darkest joint is directly at the bearing surface. Beyond it the
        # short broken shadow picks up sand colour (never projected onto sea).
        for off,rgba in enumerate([(31,37,42,244),(47,47,47,211),(65,61,57,139),(76,70,61,80)]):
            if not sand[foot+off,x]: break
            if off>=2 and ((x//6+off)%5==0 or depth<8): continue
            brush.point((int(x),foot+off),fill=rgba)
    # Catch light on broken ledges within a face. Fractures terminate or change
    # direction at these shelves; they do not run from crest to sand like seams.
    chips=canvas()
    cut=ImageDraw.Draw(chips)
    for left,right in zip(joints,joints[1:]):
        mid=(left+right)//2
        if not start<=mid<=end: continue
        depth=int(height[mid-start])
        if depth<7: continue
        cy=int(crest[mid-start])+rng.randint(4,max(4,depth-3))
        x=left+rng.randrange(1,4)
        length=rng.randint(3,max(4,right-left-2))
        line=[(x,cy),(x+length//2,cy-1),(x+length,cy-3)]
        cut.line(line,fill=(41,47,53,197))
        cut.line([(px,py-1) for px,py in line[:2]],fill=(160,153,133,201))
        cut.line([(x+length,cy-3),(x+length-1,cy),(x+length-2,cy+3)],fill=(48,50,57,187))
        for _ in range(rng.randrange(2,6)):
            px=x+rng.randrange(0,length)
            py=cy+rng.randrange(-4,4)
            cut.point((px,py),fill=rng.choice(["#86867a","#a5a193","#747b77","#969388"]))
    restrict(chips,face)
    ink.alpha_composite(chips)
    # Short, discontinuous turf overhangs follow the actual grass skyline.
    for i,x in enumerate(xs):
        top=int(crest[i])
        if not face[top,x]: continue
        length=1+int((1+math.sin(x*.26)+.7*math.sin(x*.61))*.85)
        for off in range(max(1,length)):
            if face[top+off,x]:
                brush.point((int(x),top+off),fill=["#737745","#626c40","#4b593a"][off%3])
    for x in [1105,1121,1139,1156,1173,1181,1233,1245,1262,1283,1304,1319,1330]:
        top=int(crest[x-start])
        if not face[top,x]: continue
        width=rng.randint(10,20)
        waterside_prop(ink,sheet,regions,"meadow",x,top+2,width)
        for _ in range(5):
            root=x+rng.randint(-width//3,width//3)
            y=int(crest[root-start])
            length=rng.randint(3,8)
            brush.line([(root,y),(root-1,y+length//2),(root-2,y+length)],
                       fill=rng.choice(["#525b38","#606c3d","#6e7442"]))
            brush.point((root-1,y+length//2),fill="#899254")
    return ink


def rock_fragments(sheet,regions):
    # Cut only fracture planes above the surf from Shiomi's own rock painting.
    sx,sy,sw,sh=regions["outcrop"]
    source=sheet.crop((sx,sy,sx+sw,sy+sh))
    chips=[[(60,74),(65,43),(86,18),(116,4),(138,5),(152,25),(133,34),(110,57),(76,87),(63,89)],
           [(71,99),(89,67),(123,34),(149,29),(177,38),(199,56),(203,72),
            (199,105),(181,120),(150,129),(125,124),(119,112),(94,107)],
           [(201,91),(207,77),(220,68),(239,71),(254,81),(265,95),(259,102),(243,105),(216,102)],
           [(151,166),(163,147),(183,136),(208,132),(230,136),(243,146),(242,156),(221,166),(191,170),(169,175)]]
    fragments=[]
    for outline in chips:
        mask=Image.new("L",source.size)
        ImageDraw.Draw(mask).polygon([(x*sw/370,y*sh/225) for x,y in outline],fill=255)
        fragment=source.copy()
        fragment.putalpha(mask)
        fragments.append(fragment.crop(mask.getbbox()))
    return fragments


def fallen_blocks(sheet,regions,ground,beach):
    fragments=rock_fragments(sheet,regions)
    placements=[(1118,909,8,5,3),(1132,910,21,13,1),(1144,912,8,5,0),
                (1166,907,12,7,2),(1245,884,8,5,0),(1253,878,17,10,3),
                (1259,874,5,3,2),(1304,859,21,12,1),(1317,854,7,4,3),(1340,843,12,8,0)]
    blocks=[]
    for i,(x,y,w,h,variant) in enumerate(placements):
        if ground.getpixel((x,y))!=beach:
            raise ValueError(f"Fallen block outside beach at {x},{y}")
        tile=Image.new("RGBA",(24,24))
        brush=ImageDraw.Draw(tile)
        brush.ellipse((11-w//2,18-h//5,12+w//2,21),fill=(50,49,51,126))
        art=fragments[variant]
        if i%2: art=art.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        art=art.resize((w,h),Image.Resampling.LANCZOS)
        tile.alpha_composite(art,(12-w//2,21-h))
        blocks.append((x,y,w,h,tile))
    return blocks


def raked_court(ground,pale):
    left,top,right,bottom=THEATRE_COURT
    out=canvas()
    brush=ImageDraw.Draw(out)
    for center in [(363,649),(585,649)]:
        x,y=center
        for radius in range(10,101,5):
            ry=radius*.34
            brush.arc((x-radius,y-ry,x+radius,y+ry),4,352,fill=(130,126,113,105))
            brush.arc((x-radius,y-ry+1,x+radius,y+ry+1),4,352,fill=(247,241,219,116))
    shape=Image.new("L",out.size)
    ImageDraw.Draw(shape).ellipse((left+3,top+2,right-3,bottom-2),fill=255)
    restrict(out,(np.asarray(ground)==pale)&(np.asarray(shape)>0))
    return out


def clean_foliage(sheet, regions):
    """Key the tinted extraction matte using its RGB in adjacent transparent texels."""
    for name in ("sakura", "pine", "bamboo", "azalea", "dwarf", "meadow", "hydrangea"):
        x, y, w, h = regions[name]
        rgba = np.array(sheet.crop((x,y,x+w,y+h)))
        rgb = rgba[:,:,:3].astype(np.int16)
        painted = rgba[:,:,3] > 0
        known = ~painted
        backdrop = rgb.copy()
        # Carry the local matte inward. Its tint changes from pink to brown
        # between the blossom canopy and the trunk, even inside a single sprite.
        limit = {"sakura":9,"bamboo":32,"pine":24}.get(name,4)
        for _ in range(limit):
            if known.all(): break
            candidates = np.pad(known, 1)
            colors = np.pad(backdrop, ((1,1),(1,1),(0,0)), mode="edge")
            count = np.zeros((h,w), np.int16)
            total = np.zeros_like(rgb)
            for dy,dx in [(0,1),(2,1),(1,0),(1,2)]:
                neighbor = candidates[dy:dy+h,dx:dx+w]
                count += neighbor
                total += colors[dy:dy+h,dx:dx+w] * neighbor[:,:,None]
            ring = ~known & (count>0)
            backdrop[ring] = total[ring] // count[ring,None]
            known |= ring
        distance = np.max(np.abs(backdrop-rgb), axis=2)
        grey = Image.fromarray(np.asarray(rgb.mean(axis=2),dtype=np.uint8))
        contrast = np.asarray(grey.filter(ImageFilter.MaxFilter(3))).astype(int) - np.asarray(grey.filter(ImageFilter.MinFilter(3)))
        remove = known & ((distance<14) | ((distance<34) & (contrast<30)))
        if name in {"sakura","bamboo","pine"}:
            # A one-texel fringe of the pale backing can survive between the
            # keyed area and the painted edge; keep saturated tips and flowers.
            near = np.asarray(Image.fromarray(remove).convert("L").filter(ImageFilter.MaxFilter(3)))>0
            remove |= near & (distance<52) & (contrast<66)
        if name=="sakura":
            # Close pinholes inside blossom clusters, then drop detached rings
            # in the extraction fringe. Keep the pale petal highlights opaque.
            keep = Image.fromarray((painted & ~remove).astype(np.uint8)*255)
            keep = keep.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))
            keep = keep.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(3))
            remove = np.asarray(keep)==0
        rgba[remove,3] = 0
        sheet.paste(Image.fromarray(rgba),(x,y))


def grass_aprons(ground, props, regions, sizes):
    apron=Image.new("L",ground.size)
    draw=ImageDraw.Draw(apron)
    for p in props:
        if paved_building(p) or p.get("on_existing_lawn"): continue
        if p["art"] not in sizes and p["art"]!="house": continue
        w,x,y=p["w"],p["x"],p["y"]
        *_,rw,rh=regions[p["art"]]
        base=round(w*rh/rw*p["base"])
        left,right=round(x-w*.52),round(x+w*.52)
        back=min(y-base-8,467 if p["art"]=="bank" else y)
        draw.polygon([(left,y-base),(left+6,back+3),(right-9,back),(right,y-base-4),
                      (right+2,y),(right-1,y+4),(right-14,y+6),(right-21,y+10),
                      (x+5,y+9),(x-15,y+12),(left+11,y+8),(left-1,y+4)],fill=255)
    return np.asarray(apron)>0


def paint_bridge(art):
    x,y,w,h=BRIDGE_FRAME
    bridge=art.resize((w,h),Image.Resampling.LANCZOS)
    whole=canvas()
    whole.alpha_composite(bridge,(x,y))
    rail_mask=Image.new("L",whole.size)
    # The texture's lower rail and its support beams are drawn over the actor;
    # the back railing and walking planks sit below the actor.
    rail=[(1230,235),(1237,233),(1244,230),(1255,225),(1265,222),
          (1275,221),(1288,222),(1302,226),(1312,233),(1318,235)]
    ImageDraw.Draw(rail_mask).polygon(rail+[(1318,252),(1230,252)],fill=255)
    near=whole.copy()
    restrict(near,np.asarray(rail_mask)>0)
    restrict(whole,np.asarray(rail_mask)==0)
    return whole,near


def rice_paddies():
    out=canvas()
    d=ImageDraw.Draw(out)
    for channel in [[(239,800),(244,788),(247,777)],
                    [(203,837),(216,825),(238,812)],[(208,870),(223,867),(247,860)]]:
        d.line(channel,fill="#514b32",width=5,joint="curve")
        d.line(channel,fill="#81988c",width=2,joint="curve")
    rng=random.Random(7292)
    for index,bed in enumerate(PADDIES):
        # Draw in local coordinates: banks retain their thickness in concave bends.
        ox,oy=min(x for x,y in bed)-4,min(y for x,y in bed)-4
        size=(max(x for x,y in bed)-ox+6,max(y for x,y in bed)-oy+7)
        rim=Image.new("L",size)
        ImageDraw.Draw(rim).polygon([(x-ox,y-oy) for x,y in bed],fill=255)
        water=np.asarray(rim.filter(ImageFilter.MinFilter(5)))>0
        bank=np.asarray(rim)>0
        shallow=water & (np.asarray(rim.filter(ImageFilter.MinFilter(13)))==0)
        d.polygon([(x,y+1) for x,y in bed],fill="#574735")
        paint=Image.new("RGBA",size)
        ink=ImageDraw.Draw(paint)
        for y,x in zip(*np.where(bank)):
            x,y=int(x),int(y)
            gleam=math.sin(y*.62+x*.035)+.6*math.cos(x*.11-y*.26)
            if water[y,x]:
                color=np.array([105,113,85]) if shallow[y,x] else np.array([104,132,119])
                shade=round(6*gleam)+rng.randrange(-3,4)
            else:
                color=np.array([112,80,49]) if y+2<size[1] and bank[y+2,x] else np.array([76,56,38])
                shade=rng.randrange(-12,14)
            ink.point((x,y),fill=tuple(int(c+shade) for c in color))
        for y,x in zip(*np.where(water)):
            x,y=int(x),int(y)
            if (math.sin(y*.64+x*.038)+.6*math.cos(x*.11-y*.26)>1 and rng.random()<.22):
                ink.line((x,y,x+2,y),fill="#a8b6a3")
        for row,y in enumerate(range(8,size[1]-4,6+index)):
            for x0 in range(6+row%2*3,size[0]-5,9+index):
                x=x0+rng.randrange(-2,3)
                foot=y+round(2*math.sin(x*.066+row*.3))+rng.randrange(-1,2)
                if not water[foot,x] or rng.random()<.12: continue
                h=rng.randint(4,6)+index
                ink.line((x,foot,x+3,foot+1),fill="#566a52")
                ink.line((x,foot,x-3,foot-h+2),fill="#486032")
                ink.line([(x,foot),(x+1,foot-3),(x+4,foot-h)],fill="#637a39")
                ink.line((x,foot-1,x-1,foot-h),fill="#a4ae5f")
                ink.point((x+3,foot-h+1),fill="#bdc97a")
        for y,x in zip(*np.where(bank & ~water)):
            if rng.random()<.085:
                color=rng.choice(["#b39869","#91784d","#686b3e","#826746"])
                ink.line((int(x),int(y),int(x)+1,int(y)-1),fill=color)
        out.alpha_composite(paint,(ox,oy))
        # Grasses spill over a few wet shoulders; other mud banks stay exposed.
        for k,(x,y) in enumerate(bed):
            if (k+index)%3: continue
            turf(d,x,y+1,3,rng)
        for x,y in bed[2::4]:
            d.line([(x-1,y+1),(x+2,y),(x+4,y+1)],fill="#8a784f")
    return out


def shrine_staircase(paving_texture):
    out=canvas()
    d=ImageDraw.Draw(out)
    rng=random.Random(303)
    for start,count in [(150,5),(199,5),(246,4),(297,4)]:
        end=start+count*8
        d.polygon([(233,start+2),(272,start+2),(278,end+3),(231,end+3)],fill=(36,49,51,104))
        for i in range(count):
            y=start+i*8
            spread=round(2*i/max(1,count-1))
            l,r=238-spread,272+spread
            d.rectangle((l,y,r,y+4),fill=rng.choice(["#929589","#8b9089","#99998b"]))
            for px in range(l+1,r):
                for py in (y+2,y+3,y+4):
                    pattern=paving_texture.getpixel((96+px%96,py%96))
                    d.point((px,py),fill=tuple((c+v)//2 for c,v in zip((157,158,143),pattern)))
            d.line((l+1,y+1,r-1,y+1),fill="#bdbbac")
            d.rectangle((l,y+5,r,y+7),fill="#595e59")
            d.line((l+1,y+5,r-1,y+5),fill="#757970")
            d.line((l,y+8,r,y+8),fill="#414a48")
            seam=rng.randint(l+9,r-7)
            d.line((seam,y+2,seam-1,y+5),fill="#777e72")
            for x in (l+3,r-2):
                d.line((x,y+3,x+rng.randint(-2,2),y+4),fill=rng.choice(["#737e52","#6c7750"]))
        # Narrow side cheeks, with their dark outward face and lit stone cap.
        for x in (235,273):
            d.polygon([(x,start-2),(x+4,start-3),(x+5,end),(x,end+2)],fill="#626b66")
            d.line((x+1,start-1,x+2,end),fill="#9c9c88",width=2)
            for y in range(start+3,end,8):
                d.line((x+1,y,x+4,y),fill="#4a554d")
    return out


def rock(d, x, y, r, tone=0):
    """A low faceted stone with a damp foot and an uneven lichen-coloured top."""
    h = max(2, round(r * .57))
    shades = [("#555a57", "#929189", "#b4b4a3"), ("#555f67", "#89979b", "#bbc3bb"),
              ("#636355", "#a4a393", "#c8c3a7")][tone % 3]
    d.polygon([(x-r,y-1),(x-r+1,y-h),(x-1,y-h-2),(x+r-2,y-h),(x+r,y-1),
               (x+r-2,y+1),(x-2,y+2)], fill=shades[0])
    d.polygon([(x-r+1,y-2),(x-r+2,y-h),(x-1,y-h-1),(x+r-2,y-h),(x+r-2,y-2),
               (x+1,y)], fill=shades[1])
    d.line([(x-r+2,y-h),(x-1,y-h-1),(x+max(0,r//3),y-h)], fill=shades[2])


def turf(d, x, y, length, rng, blossom=False):
    for _ in range(length):
        px, py = x+rng.randint(-length,length), y+rng.randint(-3,3)
        dx, h = rng.choice([-2,-1,1,2]), rng.randint(2,5)
        d.line((px,py,px+dx,py-h),fill=rng.choice(["#52613e","#627046","#6a7848","#586e48"]))
        d.point((px+dx,py-h),fill=rng.choice(["#a1a65c","#959c5e","#b1ae74"]))
        if blossom and rng.random()<.32:
            d.line((px+dx-1,py-h-1,px+dx+1,py-h-1),fill=rng.choice(["#e3d9ad","#ecd58c","#dbbaba"]))
            d.point((px+dx,py-h-2),fill="#f1e5c1")


def meadow(mask, objects, roads):
    rng=random.Random(6883)
    out=canvas()
    # Three scales of coherent pigment: sun-bleached grass, cool sheltered
    # patches and tiny plant clusters. Never outline a parcel or cadastral cell.
    noise_gen=np.random.default_rng(532)
    def field(w,h):
        samples=noise_gen.integers(0,256,(h,w),dtype=np.uint8)
        return np.asarray(Image.fromarray(samples).resize(out.size,Image.Resampling.BICUBIC),dtype=float)/255
    noise=.47*field(18,13)+.34*field(49,36)+.19*field(140,91)
    pigment=np.empty((1024,1536,4),dtype=np.uint8)
    warm=noise>.49
    pigment[:,:,:3]=np.where(warm[:,:,None],(188,170,88),(42,89,64))
    pigment[:,:,3]=np.clip((abs(noise-.49)*290-7),0,90)
    out=Image.fromarray(pigment)
    d=ImageDraw.Draw(out)
    centers=[(p["x"],p["y"]+2) for p in objects if p["art"] in ("pine","sakura","bamboo","dwarf")]
    centers += [point for _,points in roads for point in points[1:-1:3]]
    centers += [(rng.randrange(70,1455),rng.randrange(95,940)) for _ in range(202)]
    for cx,cy in centers:
        for _ in range(rng.randint(3,11)):
            x,y=round(cx+rng.gauss(0,16)),round(cy+rng.gauss(0,8))
            turf(d,x,y,rng.randint(2,5),rng,blossom=rng.random()<.5)
        if rng.random()<.30:
            x,y=round(cx+rng.uniform(-14,14)),round(cy+rng.uniform(-8,8))
            rock(d,x,y,rng.randint(3,6),rng.randrange(3))
            rock(d,x+7,y+1,2)
    for _ in range(185):
        cx,cy=rng.randrange(50,1480),rng.randrange(82,955)
        for _ in range(rng.randint(2,6)):
            x,y=cx+rng.randint(-13,13),cy+rng.randint(-7,7)
            if not mask[y,x]: continue
            d.ellipse((x-4,y-1,x+4,y+1),fill=(55,73,43,110))
            turf(d,x,y,4,rng,blossom=rng.random()<.42)
            if rng.random()<.13: rock(d,x+3,y+1,3,2)
    restrict(out,mask)
    return out


def walking_finish(ground, roads, smooth, grass, stone, paving_texture):
    rng=random.Random(68751)
    visible=ground.copy()
    d=ImageDraw.Draw(visible)
    stones=canvas()
    marks=ImageDraw.Draw(stones)
    # Only the ends of secondary lanes become stepping stones. Keep the former
    # right of way for the player and for old lease boundaries underneath them.
    routes=[(roads[5][1][2:],17),(roads[6][1][2:],18)]
    for points,width in routes:
        trail=smooth(smooth(points))
        d.line(trail,fill=grass,width=width+2,joint="curve")
    # Restore intersections with primary streets before drawing broken stones.
    for width,points in roads[:5]:
        d.line(smooth(smooth(points)),fill=stone,width=width,joint="curve")
    # Restrict this repaint to locations that actually were flagstone.
    visible=Image.fromarray(np.where(np.asarray(ground)==stone,np.asarray(visible),np.asarray(ground)).astype("uint8"))
    routes += [([(197,683),(193,692),(203,699)],9), ([(264,510),(258,523),(249,538)],9),
               ([(632,280),(631,289),(628,299)],8), ([(531,267),(527,276),(530,287)],8),
               ([(947,817),(945,829),(939,840),(929,849)],9)]
    for points,width in routes:
        trail=smooth(smooth(points))
        gap=4
        for a,b in zip(trail,trail[1:]):
            dx,dy=b[0]-a[0],b[1]-a[1]
            length=math.hypot(dx,dy)
            if length<.5: continue
            while gap<length:
                t=gap/length
                x=round(a[0]+dx*t+rng.uniform(-1.4,1.4))
                y=round(a[1]+dy*t+rng.uniform(-1.2,1.2))
                rx,ry=rng.randint(4,7),rng.randint(2,4)
                shape=[(x-rx,y),(x-rx+1,y-ry),(x+1,y-ry-1),(x+rx,y-ry+1),(x+rx-1,y+1),(x-2,y+ry)]
                marks.polygon([(px-1,py+1) for px,py in shape],fill="#5b6252")
                color=rng.choice([(145,151,138),(151,155,146),(164,159,140),(154,162,151)])
                marks.polygon(shape,fill=color)
                marks.line(shape[1:3],fill="#b9bcab")
                # A stony face shares the street's existing grain and has the
                # occasional hairline crack. Preserve the grass in the gaps.
                for _ in range(rx*ry):
                    px,py=x+rng.randint(-rx+1,rx-1),y+rng.randint(-ry+1,ry-1)
                    if stones.getpixel((px,py))[:3]!=color: continue
                    q=paving_texture.getpixel((96+px%96,py%96))
                    marks.point((px,py),fill=tuple((2*c+s)//3 for c,s in zip(color,q[:3])))
                if rng.random()<.25:
                    marks.line([(x-1,y-ry),(x,y-1),(x-1,y)],fill="#838b80")
                gap+=rng.randint(11,15)
            gap-=length
    # Side fragments are sparser than the tread. This keeps a discernible edge
    # without turning the verges into an unbroken grey border.
    paved=Image.fromarray((np.asarray(visible)==stone).astype("uint8")*255)
    rim=(np.asarray(paved.filter(ImageFilter.MaxFilter(9)))>0)&(np.asarray(visible)==grass)
    ys,xs=np.where(rim)
    for i in rng.sample(range(len(xs)),len(xs)//7):
        x,y=int(xs[i]),int(ys[i])
        marks.line((x,y,x+rng.choice([0,1,2]),y),fill=rng.choice(["#939685","#a9a994","#808876","#adb0a0"]))
    # Short pockets of wear cross the seam on both sides; vary their spacing.
    for i in rng.sample(range(len(xs)),len(xs)//68):
        x,y=int(xs[i]),int(ys[i])
        for _ in range(rng.randint(2,6)):
            px,py=x+rng.randrange(-4,5),y+rng.randrange(-3,4)
            if not (0<px<visible.width-4 and 3<py<visible.height-4): continue
            if visible.getpixel((px,py)) not in (stone,grass): continue
            marks.line((px-1,py,px+1,py),fill=rng.choice(["#857c65","#7f806b","#707862"]))
            marks.point((px,py-1),fill="#b8b7a4")
            if rng.random()<.16: turf(marks,px,py,2,rng)
    return visible,stones


def creek_colors(materials, stream):
    """Clear green-grey shallows, a deeper centre, and broken reflected sky."""
    water=Image.fromarray((materials==stream).astype("uint8"))
    depth=np.zeros(materials.shape,dtype="float32")
    for _ in range(7):
        water=water.filter(ImageFilter.MinFilter(3))
        depth+=np.asarray(water)
    yy,xx=np.ogrid[:materials.shape[0],:materials.shape[1]]
    grain=np.random.default_rng(7310).integers(-2,3,size=materials.shape)
    sky=np.maximum(0,np.sin(xx*.26+np.sin(yy*.49))-.70)*np.sin(yy*.82+xx*.06)**4
    return np.stack([92-depth*4.7+grain+sky*26,137-depth*3.4+grain+sky*32,
                     125-depth*1.8+grain+sky*29],axis=-1).astype("uint8")


def waterfall_pools(ground, stream, reef_art):
    out=canvas()
    foam=canvas()
    rim=ImageDraw.Draw(out)
    ripples=ImageDraw.Draw(foam)
    rng=random.Random(731)
    for basin,(fx,fy) in zip(FALL_POOLS,[(1284,138),(1260,198)]):
        for start,end in zip(basin,basin[1:]+basin[:1]):
            if abs(start[0]-fx)<8 and (start[1]<fy-4 or start[1]>fy+10):
                continue  # keep the inlet and outlet open
            rim.line((start,end),fill="#748c75",width=2)
            if rng.random()<.74:
                width=rng.randrange(6,13)
                rock=reef_art.resize((width,max(3,width//2)),Image.Resampling.BOX)
                out.alpha_composite(rock,(start[0]-width//2,start[1]-3))
        for radius in (6,12,18):
            ripples.arc((fx-radius,fy-radius*.32,fx+radius,fy+radius*.53),25,104,fill="#91b6ad")
        for _ in range(12):
            x=fx+rng.randrange(-15,17)
            y=fy+rng.randrange(0,13)
            ripples.line((x,y,x+rng.randrange(1,3),y),fill=rng.choice(["#a8c6b6","#89aba2","#96b9af"]))
    restrict(foam,np.asarray(ground)==stream)
    out.alpha_composite(foam)
    return out


def shoreline(ground, coast, sea, stream, reef_art):
    rng=random.Random(2408)
    out=canvas()
    d=ImageDraw.Draw(out)
    water=np.asarray(ground)==sea
    # Locate the wet side rather than assuming that south is always offshore.
    def at_sea(x,y):
        return 0<=x<1536 and 0<=y<1024 and water[int(y),int(x)]
    for k,(a,b) in enumerate(zip(coast,coast[1:]+coast[:1])):
        dx,dy=b[0]-a[0],b[1]-a[1]
        length=math.hypot(dx,dy)
        ux,uy=dx/length,dy/length
        nx,ny=uy,-ux
        if not at_sea((a[0]+b[0])/2+nx*20,(a[1]+b[1])/2+ny*20): nx,ny=-nx,-ny
        for s in range(2,round(length),5):
            t=s/length
            depth=9+4*math.sin(s*.10+k)+rng.randint(-3,5)
            x=round(a[0]+t*dx+nx*depth); y=round(a[1]+t*dy+ny*depth)
            if not at_sea(x,y) or (1080<x<1503 and 520<y<680): continue
            if rng.random()<.5:
                r=rng.randrange(2,7)
                d.arc((x-r-3,y-2,x+r+4,y+3),10,160,fill="#80b6b4")
                stone=reef_art.resize((r*3,r+3),Image.Resampling.BOX)
                if k%2: stone=stone.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
                out.alpha_composite(stone,(x-stone.width//2,y-stone.height+1))
            if rng.random()<.66:
                wx,wy=round(x+nx*5),round(y+ny*5)
                d.line([(wx-3,wy),(wx,wy+1),(wx+rng.randint(2,6),wy)],fill=rng.choice(["#a9cfca","#86bebd","#d4ded0"]))
    # The mill channel gets two irregular banks with individual wet stones.
    wet=Image.fromarray((np.asarray(ground)==stream).astype("uint8")*255)
    near=(np.asarray(wet.filter(ImageFilter.MaxFilter(5)))>0) & (np.asarray(wet.filter(ImageFilter.MinFilter(5)))==0)
    ys,xs=np.where(near[:, :240])
    for i in rng.sample(range(len(xs)),len(xs)//5):
        x,y=int(xs[i]),int(ys[i])
        if not 833<y<908: continue
        w=rng.randint(5,10)
        stone=reef_art.resize((w,max(3,w//2)),Image.Resampling.BOX)
        out.alpha_composite(stone,(x-w//2,y-stone.height//2))
    return out


def bank_planting(ground, grass, sea, stream, sheet, regions, rock_mask):
    """Low stones and flowers planted along the dry side of both shorelines."""
    materials=np.asarray(ground)
    turf_mask=materials==grass
    def near_water(material,spread):
        radius=spread//2
        padded=np.pad(materials==material,radius)
        summed=np.pad(padded,((1,0),(1,0))).cumsum(axis=0,dtype=np.int32).cumsum(axis=1,dtype=np.int32)
        return (summed[spread:,spread:]-summed[:-spread,spread:]
                -summed[spread:,:-spread]+summed[:-spread,:-spread])>0
    coasts=turf_mask & near_water(sea,65)
    streams=turf_mask & near_water(stream,33)
    out=canvas()
    bank_solids=Image.new("L",ground.size)
    stones=ImageDraw.Draw(bank_solids)
    rng=random.Random(8036)
    atlas={}
    for key in ["ledge","meadow","azalea"]:
        x,y,w,h=regions[key]
        atlas[key]=sheet.crop((x,y,x+w,y+h))

    def scatter(key,x,foot,width):
        source=atlas[key]
        height=max(3,round(width*source.height/source.width))
        patch=source.resize((width,height),Image.Resampling.BOX)
        if rng.random()<.5: patch=patch.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        out.alpha_composite(patch,(x-width//2,foot-height+1))
        if key=="ledge" and width>=17:
            stones.ellipse((x-width*.36,foot-height*.37,x+width*.36,foot-1),fill=1)

    for y in range(83,960,25):
        for x in range(16,1512,25):
            px,py=x+rng.randrange(-10,11),y+rng.randrange(-10,11)
            if 115<px<209 and 792<py<839: continue
            if not (coasts[py,px] or streams[py,px]): continue
            if 1202<px<1344 and 214<py<261: continue  # timber bridge and stone approaches
            if rng.random()<.18: continue
            scatter("ledge",px,py,rng.randrange(10,23))
            for _ in range(rng.randrange(2,4)):
                dx,dy=px+rng.randrange(-9,10),py+rng.randrange(-4,7)
                if not turf_mask[dy,dx]: continue
                kind="azalea" if rng.random()<.24 else "meadow"
                scatter(kind,dx,dy,rng.randrange(10,19))
    # The narrow headwater and the two tight mill banks need a closer spacing.
    for x,y in [(1244,149),(1306,153),(1248,176),(1320,206),(1313,268),
                (1248,268),(1207,288),(1191,227),(186,779),(202,797),
                (222,819),(218,843),(196,866),(233,887),(235,914)]:
        if not turf_mask[y,x]: continue
        scatter("ledge",x,y,rng.randrange(7,14))
        scatter("meadow",x+3,y-1,rng.randrange(10,16))
    restrict(out,turf_mask)
    rock_mask.paste(1,mask=Image.fromarray((np.asarray(bank_solids,dtype=bool)&turf_mask).astype("uint8")*255))
    return out


def waterside_prop(target, sheet, regions, name, x, y, width, darker=0):
    sx,sy,sw,sh=regions[name]
    patch=sheet.crop((sx,sy,sx+sw,sy+sh)).resize(
        (width,round(width*sh/sw)),Image.Resampling.LANCZOS)
    if darker:
        color=Image.new("RGBA",patch.size,(53,62,62,255))
        shade=Image.blend(patch,color,darker)
        shade.putalpha(patch.getchannel("A"))
        patch=shade
    target.alpha_composite(patch,(round(x-width/2),y-patch.height))


def reeds(brush,x,y,rng,dry=False):
    for offset in [-4,-2,0,1,4]:
        tip=x+offset+rng.choice([-4,-2,0,2,4])
        top=y-rng.randint(7,16)
        brush.line([(x+offset,y),(x+offset,top+5),(tip,top)],fill="#626844" if dry else "#476b42")
        brush.line((tip,top,tip,top+3),fill="#bd9f5e" if dry else "#9bae65")
        brush.line((x+offset,y-3,x+offset+3,y-7),fill="#a28f55" if dry else "#849b58")


def dry_riverbed(ground, dry, stream):
    detail=canvas()
    brush=ImageDraw.Draw(detail)
    rng=random.Random(7420)
    mask=np.asarray(ground)==dry
    ys,xs=np.where(mask)
    for i in rng.sample(range(len(xs)),len(xs)//3):
        x,y=int(xs[i]),int(ys[i])
        r=rng.choices([1,2,3,4],weights=[10,7,3,1])[0]
        h=max(1,r//2)
        brush.ellipse((x-r,y-h,x+r,y+h),fill=rng.choice(["#8e8876","#989383","#7e8177"]))
        brush.ellipse((x-r,y-h,x+r-1,y+h-1),fill=rng.choice(["#c1b9a4","#b3b3a4","#d4ccba","#aaa897"]))
        brush.point((x-r+1,y-h),fill="#d6cebb")
    restrict(detail,mask)
    brush=ImageDraw.Draw(detail)
    # As the last water thins, reveal the same gravel through it. This also
    # gives the final trickle a wet edge, before the entirely dry pebble fan.
    wet=np.asarray(ground)==stream
    last_water=Image.new("L",ground.size)
    flow_path(last_water,LOWER_RUN,LOWER_WIDTHS,255)
    ys,xs=np.where(wet & (np.asarray(last_water)>0))
    for y,x in zip(ys,xs):
        x,y=int(x),int(y)
        t=max(0,min(1,(y-247)/48))
        shade=rng.choice([-5,-3,0,0,1,3,5])
        rgb=(round(61+70*t)+shade,round(124+17*t)+shade,round(125-5*t)+shade)
        brush.point((x,y),fill=rgb+(round(70+174*t),))
        if t>.46 and rng.random()<.16:
            brush.point((x,y),fill=rng.choice(["#9da999","#bac0a8","#879a8e"]))
    for x,y in [(1282,266),(1245,274),(1258,294),(1228,280),(1219,309),(1203,324)]:
        reeds(brush,x,y,rng,dry=True)
    return detail


def mountain_spring(sheet, regions):
    out=canvas()
    brush=ImageDraw.Draw(out)
    # Small bamboo clusters stand behind and alongside grey ledges, hiding
    # the uphill end of the rivulet while leaving a visible gap at the spring.
    for x,y,w in [(1250,100,49),(1321,108,59)]:
        waterside_prop(out,sheet,regions,"bamboo",x,y,w)
    # The visible stream lip, wet rocks and plunge are one painted waterfall
    # sprite. Place the shoulders behind it so the water emerges between them.
    for x,y,w in [(1263,108,43),(1305,105,47),(1317,118,32),(1252,126,27)]:
        waterside_prop(out,sheet,regions,"ledge",x,y,w)
    # Wet paving in the abutments anchors the bridge to the footpath.
    for x,y in [(1233,247),(1314,247)]:
        waterside_prop(out,sheet,regions,"outcrop",x,y,19,.22)
        brush.line([(x-6,y-4),(x-2,y-5),(x+5,y-4)],fill="#8e988d")
    waterside_prop(out,sheet,regions,"basin",1344,246,18)
    return out


def mill_headwater(ground,stream,sheet,regions):
    out=canvas()
    brush=ImageDraw.Draw(out)
    rng=random.Random(420)
    left,top,right,bottom=110,790,215,834
    crop=Image.fromarray((np.asarray(ground)[top:bottom,left:right]==stream).astype("uint8")*255)
    bed=np.asarray(crop)>0
    rim=(np.asarray(crop.filter(ImageFilter.MaxFilter(7)))>0)&~bed
    for y,x in zip(*np.where(bed)):
        # Shallow stone-bottomed water grades into the deeper millrace.
        xx,yy=left+int(x),top+int(y)
        shade=round(5*math.sin(xx*.17+yy*.59))+rng.randrange(-3,4)
        brush.point((xx,yy),fill=(77+shade,118+shade,116+shade,max(0,min(255,28*(834-yy)))))
    for y,x in zip(*np.where(rim)):
        xx,yy=left+int(x),top+int(y)
        if yy>830 or rng.random()>.79: continue
        brush.point((xx,yy),fill=rng.choice(["#787861","#686956","#8c8d79"]))
    # Separate rounded stones on the two banks follow each bend of the U.
    for i,(a,b) in enumerate(zip(MILL_CHANNEL[:14],MILL_CHANNEL[1:15])):
        dx,dy=b[0]-a[0],b[1]-a[1]
        length=math.hypot(dx,dy)
        for step in range(0,round(length),4):
            t=step/length
            width=(MILL_WIDTHS[i]*(1-t)+MILL_WIDTHS[i+1]*t)*.5+1
            for side in (-1,1):
                x=round(a[0]+t*dx-side*dy/length*width)
                y=round(a[1]+t*dy+side*dx/length*width)
                rock(brush,x,y,rng.choice([2,2,3]),rng.randrange(3))
            if i%2:
                x,y=round(a[0]+t*dx),round(a[1]+t*dy)
                brush.line((x-1,y,x+1,y),fill="#abc4ac")
    # Use the same mineral faces as the beach scree. The spring mouth sits in
    # front of the mill wall, with a gap between two weathered stone shoulders.
    fragments=rock_fragments(sheet,regions)
    for x,y,w,h,variant in [(102,811,23,13,1),(117,807,17,10,0),(108,814,10,6,2),
                            (140,825,7,4,2),(153,831,7,4,1),(162,818,6,3,3),
                            (177,816,7,4,2),(192,818,6,4,3)]:
        out.alpha_composite(fragments[variant].resize((w,h),Image.Resampling.BOX),(x-w//2,y-h))
    brush.line([(111,808),(114,809),(114,811)],fill="#303f40",width=2)
    brush.line([(112,810),(115,812),(119,812)],fill="#b1cdbe")
    brush.line([(117,814),(121,815),(124,815)],fill="#91b6ae")
    for x,y,r in [(173,805,6),(177,807,9),(183,809,6)]:
        brush.arc((x-r,y-2,x+r,y+2),8,159,fill="#deebe1")
    waterside_prop(out,sheet,regions,"buckets",99,797,16)
    return out


def outfalls(sheet, regions):
    out=canvas()
    brush=ImageDraw.Draw(out)
    rng=random.Random(2214)
    for cx,cy in [(214,929),(1500,397)]:
        for side in (-1,1):
            x=cx+side*13
            brush.polygon([(x-9,cy-3),(x-5,cy-7),(x+3,cy-6),
                           (x+8,cy-3),(x+5,cy),(x-6,cy+1)],fill="#b5a780")
            for _ in range(29):
                px,py=x+rng.randint(-7,7),cy+rng.randint(-6,-1)
                if out.getpixel((px,py))[3]: brush.point((px,py),fill=rng.choice(["#d8c69d","#9c9279","#bbae87"]))
        for dx,dy,w in [(-19,-5,21),(14,-1,17),(20,-8,29)]:
            waterside_prop(out,sheet,regions,"outcrop",cx+dx,cy+dy,w,.20)
        for rx,ry in [(10,3),(16,5),(23,7)]:
            brush.arc((cx-rx,cy-ry,cx+rx,cy+ry),8,152,fill=(165,210,205,212))
    waterside_prop(out,sheet,regions,"ledge",1468,360,37,.28)
    waterside_prop(out,sheet,regions,"ledge",1474,363,28)
    return out


def bridge_water_shadow():
    out=canvas()
    brush=ImageDraw.Draw(out)
    brush.polygon([(1238,229),(1253,223),(1272,220),(1292,226),(1308,234),
                   (1305,250),(1284,252),(1259,248),(1242,246)],fill=(14,24,31,95))
    brush.ellipse((1251,232,1298,247),fill=(13,27,36,115))
    return out


def contacts(objects, regions, alpha_sheet, tree_names):
    ink=canvas()
    d=ImageDraw.Draw(ink)
    walls=canvas()
    leaves=ImageDraw.Draw(walls)
    rng=random.Random(941)
    buildings={"house","produce","stage","fish","bank","office","tower","inn","bath","port","shrine","torii","mill"}
    for i,o in enumerate(objects):
        art=o["art"]
        if o.get("hidden_by_landscape") or art not in buildings|set(tree_names)|{"dwarf","wheel","lantern"}: continue
        rx,ry,rw,rh=regions[art]
        w=round(o["w"]); h=round(w*rh/rw)
        silhouette=alpha_sheet.crop((rx,ry,rx+rw,ry+rh)).resize((w,h),Image.Resampling.NEAREST)
        a=np.asarray(silhouette)>150
        if art in tree_names|{"dwarf"} and i%3==1 and art!="dwarf": a=np.fliplr(a)
        has=a.any(axis=0)
        lower=h-1-np.argmax(a[::-1],axis=0)
        ox,oy=round(o["x"]-w/2),round(o["y"]-h)
        for col in np.flatnonzero(has & (lower>h*.78)):
            x,y=ox+int(col),oy+int(lower[col])
            d.line((x-2,y+2,x-1,y+4),fill=(38,48,53,85))
            d.line((x-1,y+1,x,y+2),fill=(27,39,47,190))
        if art in {"house","produce","shrine","mill","fish","inn","office","stage","port"}:
            # Low sill under each wing, broken at the entry stair and posts.
            for col in np.flatnonzero(has & (lower>h*.91)):
                f=col/w
                if not (.08<f<.40 or .60<f<.93): continue
                x,y=ox+int(col),oy+int(lower[col])
                d.line((x,y,x,y+2),fill="#584736" if col%17 else "#493c31")
                d.point((x,y+1),fill="#705b40" if (col//7)%3 else "#66533d")
                d.point((x-1,y+3),fill=(32,40,44,185))
        if art in buildings-{"torii","tower","fish","port"}:
            for fraction in [.09,.15,.22,.79,.85,.92]:
                col=round(w*(fraction+rng.uniform(-.018,.018)))
                if not has[col] or lower[col]<h*.78: continue
                x,y=ox+col,oy+int(lower[col])+2
                leaves.ellipse((x-4,y-2,x+4,y),fill=(49,57,38,160))
                turf(leaves,x,y,rng.randint(3,6),rng)
    return ink,walls


def harbor(ground, deck, quay):
    out=canvas()
    d=ImageDraw.Draw(out)
    materials=np.asarray(ground)
    wood=materials==deck
    rng=random.Random(2291)
    for x in range(1066,1478):
        rows=np.flatnonzero(materials[:,x]==quay)
        if not len(rows): continue
        edge=int(rows[-1])
        # A light cap at the joint and stone masonry down to tidal water.
        d.point((x,edge),fill="#a8a89a")
        for depth in range(1,9):
            if wood[edge+depth,x]: break
            course=1 if depth>=5 else 0
            joint=(x+course*5)//10
            grout=depth in (4,8) or (x+course*5)%10==0
            face=["#68716c","#777c73","#818477"][(joint+course)%3]
            d.point((x,edge+depth),fill="#515f5e" if grout else face)
    for x in range(1098,1478):
        rows=np.flatnonzero(wood[:,x])
        if not len(rows): continue
        edge=int(rows[-1])
        end=edge+int((x//8*7)%5)-2
        d.line((x,end-2,x,end+2),fill=["#75543b","#796046","#826547"][(x//8)%3])
        d.point((x,end-2),fill="#ba9669" if x%8 else "#644d38")
        d.point((x,end+1),fill="#554434")
        d.point((x,end+3),fill="#3f4036")
        if (x+3)%8==0:
            d.line((x,edge-5,x,end),fill="#574431")
        if x%18==3: d.point((x,edge-4),fill="#4a433a")
    for _ in range(380):
        x,y=rng.randint(1105,1468),rng.randint(590,660)
        if not wood[y,x:x+10].all(): continue
        d.line((x,y,x+rng.randint(2,9),y),fill=rng.choice([(187,152,105,104),(67,52,40,103)]))
    for x in (1110,1140,1170,1200,1234,1268,1301,1335,1369,1403,1435,1467):
        edge=int(np.flatnonzero(wood[:,x])[-1])
        d.polygon([(x-9,edge+2),(x-5,edge+2),(x+1,edge+7),(x+1,edge+11)],fill="#645342")
        d.line((x-8,edge+3,x,edge+9),fill="#967a54")
    return out


def cropped_prop(name,region,outline,x,y,width):
    """Map a polygon of the packed art, preserving transparency and texel density."""
    rx,ry,rw,rh=region
    points=[(u*rw,v*rh) for u,v in outline]
    left=min(px for px,py in points)
    right=max(px for px,py in points)
    bottom=max(py for px,py in points)
    scale=width/(right-left)
    def coords(pairs):
        return "PackedVector2Array("+",".join(f"{v:.3f}" for pt in pairs for v in pt)+")"
    return [f'[node name="{name}" type="Polygon2D" parent="."]',f'position = Vector2({x},{y})',
            'texture = ExtResource("sheet")',
            'polygon = '+coords([((px-(left+right)/2)*scale,(py-bottom)*scale) for px,py in points]),
            'uv = '+coords([(rx+px,ry+py) for px,py in points])]


def dock_props(ground,deck,quay,regions,solid):
    nodes=[]
    brush=ImageDraw.Draw(solid)
    def place_solid(name,kind,outline,x,y,w,depth):
        nodes.extend(cropped_prop(name,regions[kind],outline,x,y,w))
        brush.rounded_rectangle((round(x-w*.39),y-depth,round(x+w*.39),y-1),
                                radius=min(3,depth//2),fill=1)
    box=[(.70,.49),(.825,.39),(.99,.42),(.99,.84),(.86,.90),(.705,.85)]
    post=[(.40,.81),(.435,.73),(.442,.28),(.437,.2),(.441,.135),(.429,.12),(.431,.035),
          (.457,.005),(.51,.005),(.558,.032),(.56,.13),(.545,.145),(.55,.72),(.59,.79),
          (.63,.91),(.60,1),(.395,1),(.36,.93)]
    dry_post=[(.43,.035),(.46,0),(.52,0),(.56,.03),(.55,.15),(.546,.64),
              (.53,.68),(.45,.69),(.44,.65),(.443,.16)]
    net=[(.53,.93),(.54,.81),(.62,.77),(.666,.685),(.71,.59),(.79,.51),(.84,.50),
         (.89,.53),(.93,.62),(.945,.69),(.988,.75),(.998,.82),(.966,.87),
         (.926,.90),(.875,.975),(.82,.976),(.79,.934),(.74,.962),(.65,.956)]
    rope=[(.005,.85),(.045,.795),(.104,.754),(.21,.74),(.29,.758),(.32,.794),
          (.371,.80),(.383,.849),(.374,.94),(.31,.988),(.18,1),(.08,.97),(.013,.924)]
    for name,x,y,w in [("DockTubs1334",1334,531,25),("DockTubs1161",1160,529,19),
                       ("DockTubs1320",1315,523,17)]:
        nodes.extend([f'[node name="{name}" type="Sprite2D" parent="."]',
                      f'position = Vector2({x},{y})', f'scale = Vector2({w/48:.7f},{w/48:.7f})',
                      'texture = ExtResource("water_tub")', 'offset = Vector2(0,-19)',
                      'metadata/art = "water_tub"'])
        depth=round(w*.30)
        brush.rounded_rectangle((round(x-w*.39),y-depth,round(x+w*.39),y-1),
                                radius=min(3,depth//2),fill=1)
    for x,y,w in [(1145,572,17),(1158,575,14),(1446,601,22)]:
        place_solid(f'DockCargo{x}',"cargo",box,x,y,w,round(w*.38))
    nodes+=cropped_prop("SeineWithFloats",regions["tubs"],net,1207,569,37)
    nodes+=cropped_prop("LoadingRope",regions["cargo"],rope,1234,574,20)
    nodes+=cropped_prop("BerthRope",regions["cargo"],rope,1348,655,13)
    # Cargo groups leave the central passenger lane free from quay to ship.
    for i,(x,y,w) in enumerate([(1128,608,22),(1147,611,23),(1137,601,19),
                                (1424,634,26),(1447,638,22),(1435,621,24)]):
        place_solid(f"FreightCrate{i:02}","cargo",box,x,y,w,round(w*.38))
    for i,(x,y,w) in enumerate([(1259,642,44),(1450,648,30)]):
        nodes+=cropped_prop(f"DryingSeine{i}",regions["tubs"],net,x,y,w)
    for i,(x,y,w) in enumerate([(1166,615,19),(1280,647,24),(1410,642,17)]):
        nodes+=cropped_prop(f"HawserCoil{i}",regions["cargo"],rope,x,y,w)
    materials=np.asarray(ground)
    for i,x in enumerate([1110,1140,1170,1200,1234,1268,1301,1335,1369,1403,1435,1467]):
        edge=int(np.flatnonzero(materials[:,x]==deck)[-1])
        nodes+=cropped_prop(f'TidalPile{i:02}',regions["pier"],post,x,edge+13+i%3,11+i%3)
    for i,x in enumerate([1120,1170,1230,1295,1371,1455]):
        edge=int(np.flatnonzero(materials[:,x]==quay)[-1])
        place_solid(f'StoneFootBollard{i:02}',"pier",dry_post,x,edge-2,6,3)
    return nodes


def pack_layers(layers, art_dir, blocks):
    """Deduplicate transparent brush tiles. Each subject remains editable/visible separately."""
    size=24
    atlas_tiles=[]
    ids={}
    nodes=[]
    for name,z,image in layers:
        data=bytearray(b"\0\0")
        for y in range(0,image.height,size):
            for x in range(0,image.width,size):
                tile=image.crop((x,y,x+size,y+size))
                if not tile.getbbox(): continue
                key=tile.tobytes()
                if key not in ids:
                    ids[key]=len(atlas_tiles)
                    atlas_tiles.append(tile)
                idx=ids[key]
                data.extend(struct.pack("<6H",x//size,y//size,0,idx%64,idx//64,0))
        nodes.extend([f'[node name="{name}" type="TileMapLayer" parent="."]',f'z_index = {z}',
                      'tile_set = SubResource("finish_tiles")',
                      'tile_map_data = PackedByteArray("'+base64.b64encode(data).decode()+'")'])
        if name=="WallGrasses":
            nodes.extend(['y_sort_enabled = true','y_sort_origin = 12'])
    rock_nodes=[]
    for i,(x,y,w,h,tile) in enumerate(blocks):
        idx=len(atlas_tiles)
        atlas_tiles.append(tile)
        rock_nodes.extend([f'[node name="FallenBlock{i:02}" type="Sprite2D" parent="."]',
                      f'position = Vector2({x},{y})','texture = ExtResource("detail_sheet")',
                      'region_enabled = true',f'region_rect = Rect2({idx%64*size},{idx//64*size},{size},{size})',
                      'offset = Vector2(0,-9)','metadata/art = "fallen_block"'])
    atlas=Image.new("RGBA",(64*size,math.ceil(len(atlas_tiles)/64)*size))
    for i,tile in enumerate(atlas_tiles): atlas.paste(tile,(i%64*size,i//64*size))
    atlas.save(art_dir/"shiomi-detail-tiles.png")
    resources=['[sub_resource type="TileSetAtlasSource" id="finish_source"]',
               'texture = ExtResource("detail_sheet")','texture_region_size = Vector2i(24,24)']
    resources.extend(f'{i%64}:{i//64}/0 = 0' for i in range(len(atlas_tiles)))
    resources.extend(['[sub_resource type="TileSet" id="finish_tiles"]','tile_size = Vector2i(24,24)',
                      'sources/0 = SubResource("finish_source")'])
    return resources,nodes,rock_nodes
