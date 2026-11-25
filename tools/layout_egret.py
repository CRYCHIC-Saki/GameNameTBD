"""Rebuild the European port in reference-image coordinates, including its property survey."""
import base64
import json
import math
import random
import zlib
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from shapely.affinity import affine_transform
from shapely.geometry import LineString, Point, Polygon, box
from shapely.ops import unary_union
from building_footprints import EGRET, stamp_building, wall_clearance
from town_contacts import stamp_rock
from egret_cart_track import cart_track
from egret_land_use import VENUE_USES, measure_routes, survey_districts

ROOT = Path(__file__).resolve().parents[1]
W,H=2263,1085
CELL=31
OX,OY=0,19
# Expand the spacing of the original composition, keeping sprite sizes fixed.
SPACING=1.13
WEST_MARGIN,TOP_MARGIN=350,8

def placed(x,y):
    return WEST_MARGIN+x*SPACING,TOP_MARGIN+y*SPACING

def projected(geom):
    return affine_transform(geom,[SPACING,0,0,SPACING,WEST_MARGIN,TOP_MARGIN])

REGIONS=json.loads((ROOT/"tools/map_art/egret-regions.json").read_text())
with Image.open(ROOT/"assets/town/egret-quay.png") as quarry:
    # Keep the grain from the town's stone atlas and light each dressed block separately.
    gray=quarry.convert("L")
    grain=np.asarray(gray,dtype=float)-np.asarray(gray.filter(ImageFilter.GaussianBlur(3)),dtype=float)
    Image.fromarray(np.clip(234+grain*.97,174,255).astype("uint8")).save(ROOT/"assets/town/egret-granite.png")
separate_art=("passenger-station","wharf","bollard")
for art in separate_art:
    with Image.open(ROOT/f"assets/town/egret-{art}.png") as source:
        REGIONS[art]=[0,0,*source.size]
rng=random.Random(1864)
scene=['[gd_scene format=3]','[ext_resource type="Script" path="res://src/town/outdoor_atmosphere.gd" id="outdoors"]']
for name in ["sprites","grass","sea","cobbles","quay","granite","cart-track",*separate_art]:
    scene.append(f'[ext_resource type="Texture2D" path="res://assets/town/egret-{name}.png" id="{name}"]')
scene.extend(['[node name="EgretPort" type="Node2D"]','y_sort_enabled = true','texture_filter = 1'])
extent=box(0,0,W,H)
surface=Image.new("L",(W,H),ord("~"))
sites=Image.new("1",(W,H),0)
solids=Image.new("1",(W,H),0)
walls=Image.new("1",(W,H),0)
reserved_solids=Image.new("1",(W,H),0)
sprite_alpha=Image.open(ROOT/"assets/town/egret-sprites.png").getchannel("A")
uses=Image.new("L",(W,H),ord("."))
residential_doors=[]
plot_rows=[]
objects=[]
doors=[]
bounds=[]
counter=0


def smooth(points):
    # Interpolating Catmull-Rom through the traced bends.
    coords=np.array(points,dtype=float)
    result=[]
    for i in range(len(coords)-1):
        a,b,c,d=coords[max(0,i-1)],coords[i],coords[i+1],coords[min(len(coords)-1,i+2)]
        for t in np.linspace(0,1,max(3,round(np.linalg.norm(c-b)/8)),endpoint=False):
            result.append(tuple(.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t**3)))
    return result+[tuple(coords[-1])]


def shape(name, geom, z, texture=None, color=None, code=None):
    draw_shape(name,projected(geom),z,texture,color,code)

def draw_shape(name, geom, z, texture=None, color=None, code=None):
    global counter
    geom=geom.intersection(extent)
    if geom.is_empty: return
    if geom.geom_type=="MultiPolygon":
        for part in geom.geoms: draw_shape(name,part,z,texture,color,code)
        return
    if geom.geom_type!="Polygon": return
    pts=list(geom.simplify(.25).exterior.coords)[:-1]
    if len(pts)<3: return
    counter+=1
    scene.extend([f'[node name="{name}{counter}" type="Polygon2D" parent="."]',f'z_index = {z}',
                  'polygon = PackedVector2Array('+', '.join(f'{v:.2f}' for p in pts for v in p)+')'])
    if texture:
        scene.extend([f'texture = ExtResource("{texture}")','texture_repeat = 2'])
        if name in ("WestPromenade","PortLane"):
            scene.append('uv = PackedVector2Array('+', '.join(f'{v*1.55:.2f}' for p in pts for v in p)+')')
    if color:
        scene.append('color = Color('+','.join(f'{int(color[i:i+2],16)/255:.4f}' for i in range(0,len(color),2))+')')
    if code:
        ImageDraw.Draw(surface).polygon(pts,fill=ord(code))


def pixel_rect(x,y,w,h):
    return box(x-w/2,y-h,x+w/2,y)


def sprite(key,x,y,w,h,name=None,plot=None,base=None,flip=False,z=0,shadow=False,world=False):
    if not world: x,y=placed(x,y)
    texture=key if key in (*separate_art,"cart-track") else "sprites"
    ax,ay,aw,ah=REGIONS[key]
    name=name or f'{key.title()}{len(objects):03}'
    objects.append((name,key,x,y,w,h))
    scene.extend([f'[node name="{name}" type="Sprite2D" parent="."]',
                  f'position = Vector2({x:.2f},{y:.2f})',f'scale = Vector2({w/aw:.7f},{h/ah:.7f})',
                  f'texture = ExtResource("{texture}")','region_enabled = true',
                  f'region_rect = Rect2({ax},{ay},{aw},{ah})',f'offset = Vector2(0,{-ah/2})',f'metadata/art = "{key}"'])
    if flip: scene.append('flip_h = true')
    if z: scene.append(f'z_index = {z}')
    if base:
        dx,dy,bw,bh=base
        scene.append(f'metadata/base = Rect2({dx:.2f},{dy:.2f},{bw:.2f},{bh:.2f})')
        footing=(math.ceil(x+dx),math.ceil(y+dy),math.ceil(x+dx+bw)-1,math.ceil(y+dy+bh)-1)
        if key!="rock": ImageDraw.Draw(reserved_solids).rectangle(footing,fill=1)
        if key in EGRET:
            stamp_building(walls,EGRET[key],(x,y),(w,h),flip)
        elif key=="rock":
            stamp_rock(solids,sprite_alpha.crop((ax,ay,ax+aw,ay+ah)),(x,y),(w,h),flip)
        else:
            ImageDraw.Draw(solids).rectangle(footing,fill=1)
        if plot:
            ImageDraw.Draw(uses).rectangle(footing,fill=ord(VENUE_USES[plot[1]]))
        elif key in ("gable","twins"):
            ImageDraw.Draw(uses).rectangle(footing,fill=ord("a"))
            residential_doors.append((x+dx+bw/2,y+dy+bh))
    if plot:
        pid,kind,label=plot
        scene.append(f'metadata/plot_id = "{pid}"')
        if pid!="harbor":
            dx,dy,bw,bh=base
            left=max(0,OX+math.floor((x+dx)/CELL))
            top=max(0,OY+math.floor((y+dy)/CELL))
            right=OX+math.ceil((x+dx+bw)/CELL)
            bottom=OY+math.ceil((y+dy+bh)/CELL)
            plot_rows.append([pid,kind,label,left,top,right-left,bottom-top,0,0])
            doors.append((x+dx+bw/2,y+dy+bh))
    if shadow:
        ellipse=[(x+w*.07+w*.45*math.cos(t),y-4+h*.065*math.sin(t)) for t in np.linspace(0,math.tau,32,endpoint=False)]
        draw_shape("GroundShade",Polygon(ellipse),-2,color="39342645")


# The outer lip follows the stone waterfront in the approved harbor view.
# Both the exposed face and the whitewater run down the west edge of the map.
reference_bank=[
    (68,-34),(65,7),(66,28),(83,41),(102,52),(113,70),(111,81),(101,93),
    (104,109),(116,119),(145,128),(167,138),(183,154),(185,172),(178,188),
    (171,200),(172,215),(183,227),(204,237),(226,247),(245,261),(251,275),
    (247,285),(238,296),(238,316),(249,327),(272,336),(290,349),(299,365),
    (303,389),(304,416),(306,442),(310,478),(308,501),(296,512),(290,518),
    (298,526),(310,540),(310,555),(295,574),(271,589),(241,602),(222,608),
    (214,620),(218,636),(215,648),(199,658),(177,669),(161,684),(160,702),
    (158,717),(148,733),(132,744),(115,755),(111,770),(117,782),(134,793),
    (147,805),(150,819),(145,833),(144,850),(151,860),(172,870),(193,877),
    (211,888),(220,901),(223,918),(225,934),(236,974)]
coastline=smooth([(1.035*x,8+1.13*y) for x,y in reference_bank])
west_edge=LineString(coastline)
north,south=coastline[0][1],coastline[-1][1]
west_water=Polygon([(-100,north)]+coastline+[(-100,south)])
land=Polygon(coastline+[(W+5,south),(W+5,north)])
draw_shape("Sea",extent,-15,"sea",code="~")
draw_shape("Meadow",land,-10,"grass",code=".")

def bank_frame(s):
    point=west_edge.interpolate(s)
    a=west_edge.interpolate(max(0,s-2))
    b=west_edge.interpolate(min(west_edge.length,s+2))
    dx,dy=(b.x-a.x)/a.distance(b),(b.y-a.y)/a.distance(b)
    return np.array([point.x,point.y]),np.array([dy,-dx])

def bank_point(s,inset,drop=0):
    p,n=bank_frame(s)
    return tuple(p+n*inset+np.array([0,drop]))

def stone_band(s,e,inner,outer,top,bottom):
    # Midpoints keep the joint faces continuous round a tight bend.
    steps=np.linspace(s,e,max(3,math.ceil((e-s)/6)))
    return Polygon([bank_point(t,inner,top) for t in steps]+
                   [bank_point(t,outer,bottom) for t in steps[::-1]]).buffer(0)

distances=np.linspace(0,west_edge.length,math.ceil(west_edge.length/4))
def promenade_width(s):
    y=west_edge.interpolate(s).y
    return float(np.interp(y,[-40,220,368,455,565,640,790,1108],[43,45,47,55,60,48,39,44]))

walk_strips=[]
for a,b in zip(distances[::3],list(distances[::3][1:])+[west_edge.length]):
    mid=(a+b)/2
    spine=LineString([bank_point(s,0) for s in (a,mid,b)])
    walk_strips.append(spine.buffer(promenade_width(mid),quad_segs=8))
quay=unary_union(walk_strips).intersection(land)
draw_shape("WestPromenade",quay,-8,"cobbles",code="q")
grass_edge=quay.boundary.difference(west_edge.buffer(12))
draw_shape("KerbAtLawn",grass_edge.buffer(.85).intersection(land),-7,color="b5af9aef")
wall_foot=[bank_point(s,-14,12) for s in distances]
draw_shape("MortaredSeaWall",Polygon(coastline+wall_foot[::-1]).buffer(0),-12,color="4d515aff")

stone=random.Random(821)
stone_palettes=[
    ("c6bca8","a59a8e","817c76","615f63"),("c1bdac","a3a094","827e78","68696b"),
    ("d0c5b4","aa9d90","91867d","736b6b"),("bdb9ac","9d9a92","797b78","5e6465"),
    ("c5beb5","a79f97","847b78","6c666b"),("d2c9b3","b2a995","8c887b","6b6b65")]
start=0
while start<west_edge.length-2:
    end=min(west_edge.length,start+stone.uniform(13,20))
    cap,upper,lower,shadow=stone.choice(stone_palettes)
    # Continue the lower stone courses underneath the deck and its front beam.
    if end-start>2:
        inset=stone.uniform(8,11)
        s,e=start+.65,end-.45
        draw_shape("GraniteFoot",stone_band(s,e,-1,-14,0,11),-11,"granite",lower+"ff")
        draw_shape("LowerFacet",stone_band(s,e,-10,-14,7,11),-11,"granite",shadow+"ff")
        draw_shape("UpperFacet",stone_band(s,e,0,-6,-.5,5),-11,"granite",upper+"ff")
        draw_shape("CornerBevel",stone_band(s,s+1.5,-.6,-12,0,9),-11,color="c1bcacaf")
        draw_shape("QuayCoping",stone_band(s,e,inset,0,-1.8,-1.8),-7,"granite",cap+"ff")
        draw_shape("CopingBevel",stone_band(s+.3,e-.2,1.1,-.5,-2,-.7),-7,color="e4dac4ff")
        draw_shape("CopingJoint",LineString([bank_point(s,inset-1,-1.8),bank_point(s,0,-1.8)]).buffer(.55),-7,color="716f70ff")
        if stone.random()<.43:
            chip=s+(e-s)*stone.uniform(.2,.6)
            draw_shape("StoneChip",LineString([bank_point(chip,3,-2),bank_point(chip+2,4,-2),bank_point(chip+3,5,-2)]).buffer(.44),-7,color="a6a498db")
    start=end

# Irregular, branching crests follow the foot of the wall, with open water between wakes.
foam=random.Random(438)
start=2
while start<west_edge.length-30:
    length=min(foam.uniform(19,64),west_edge.length-start-1)
    steps=np.linspace(0,length,max(6,int(length/3)))
    phase=foam.uniform(0,math.tau)
    wave=[bank_point(start+t,-15.4-1.9*math.sin(phase+t*.19)-foam.uniform(0,1.7),12) for t in steps]
    draw_shape("Seafoam",LineString(wave).buffer(1.5),-12,color="85d7d9ed")
    draw_shape("BreakingCrest",LineString(wave).buffer(.9),-11,color="ecfaf4ff")
    if length>24:
        t=.20*length
        fork=[bank_point(start+t,-16,12),bank_point(start+t+3,-21,12),
              bank_point(start+t+9,-25,12),bank_point(start+t+14,-24,12),
              bank_point(start+t+18,-20,12)]
        draw_shape("FoamEddy",LineString(fork).buffer(.75),-12,color="d8f3e9ff")
        drop=bank_point(start+t+11,-29,12)
        draw_shape("Spray",Point(drop).buffer(.95,quad_segs=2),-12,color="e8fcf3ff")
    for t in np.arange(1,length,5):
        r=foam.uniform(16,26)
        px,py=bank_point(start+t,-r,foam.uniform(10.5,14))
        draw_shape("BrokenFoam",LineString([(px-foam.uniform(1,3.7),py+.5),(px,py)]).buffer(foam.uniform(.4,.95)),-11,color=foam.choice(["c3eae5ef","f4fcf2ef","95d7d8cf"]))
    start+=length+foam.uniform(1,6)

hall_x,hall_y=305,312
# Rolling cobbled lanes link the three civic buildings and the gates in their reference positions.
paths=[
    (52,[(77,-55),(62,105),(71,182),(122,237),(125,277),(95,323),(68,354),(79,379),(231,366),(359,343),(485,350),(569,365)]),
    (54,[(624,-35),(619,71),(624,156),(649,205),(682,254),(703,312)]),
    (50,[(1185,-28),(1177,65),(1156,134),(1123,186),(1080,226),(1056,251),(1047,281),(1049,311)]),
    (35,[(1495,235),(1478,272),(1444,308),(1434,348),(1432,394),(1430,449),(1427,500)]),
    (47,[(849,378),(938,385),(1003,381),(1087,392)]),
    (49,[(1123,472),(1174,502),(1264,514),(1362,507),(1488,490),(1591,459),(1690,437)]),
    (48,[(650,544),(621,606),(625,671),(622,724),(590,767),(532,790),(450,800),(363,798),(305,800)]),
    (48,[(595,764),(657,765),(723,749),(791,717),(874,702),(965,699)]),
    # The former waterfront houses still share a street with the inn.
    (29,[(957,701),(988,713),(1046,720),(1110,712),(1176,693),(1211,676),(1258,655),
         (1315,652),(1374,663),(1446,665),(1501,650),(1565,626),(1620,622),(1707,612)]),
    (35,[(1284,513),(1281,531),(1269,585),(1243,625),(1185,664)]),
]
lanes=[LineString(smooth(points)).buffer(width/(2*SPACING),quad_segs=5) for width,points in paths]
market_floor=Polygon(smooth([(765,307),(832,278),(934,265),(1031,266),(1107,294),(1140,328),(1138,367),(1102,406),(1050,421),(929,416),(864,397),(814,370),(765,307)])).buffer(0)
lanes.append(market_floor)
for lane in lanes: shape("StoneKerb",lane.buffer(3),-7,color="a7a381ff",code="r")
for lane in lanes: shape("Street",lane,-6,"cobbles",code="r")
# Lay a small forecourt from the foot of the steps to the main street.
bank_entry=Polygon([(hall_x-39,hall_y),(hall_x+39,hall_y),(hall_x+31,367),(hall_x-31,367)])
shape("BankForecourt",bank_entry,-6,"cobbles",code="r")
trail=projected(LineString(smooth([(305,800),(298,829),(304,872),(294,910),(280,962)])))
dirt,track_art=cart_track(trail,ROOT/"assets/town/egret-cart-track.png",ROOT/"assets/town/map-surfaces-v2.png")
ImageDraw.Draw(surface).polygon(list(dirt.exterior.coords),fill=ord("t"))
REGIONS["cart-track"]=[0,0,*track_art[2:]]
sprite("cart-track",*track_art,"MillCartTrack",z=-5,world=True)
for i,(dx,dy) in enumerate([(-12,8),(-3,9),(7,8),(-8,14),(2,14),(9,19),(-5,22)]):
    x,y=placed(305,800)
    sett=box(x+dx,y+dy,x+dx+6-i%2,y+dy+3)
    draw_shape("EndSetts",sett.buffer(.6),-4,color="9d9177ff")
    draw_shape("WornStone",sett,-4,"granite",color="c9b99fff")
square_x,square_y=714,432
ellipse=Polygon([(square_x+205*math.cos(t),square_y+149*math.sin(t)) for t in np.linspace(0,math.tau,120,endpoint=False)])
ImageDraw.Draw(surface).polygon(list(projected(ellipse).exterior.coords),fill=ord("g"))
sprite("mosaic",square_x,square_y+149,411*SPACING,298*SPACING,"FountainSquare",z=-3)

# The waterfront lanes surround the ticket cottage and meet the existing civic street.
harbor_lanes=[
    (17,[(318,424),(351,434),(386,438),placed(79,379)]),
    (15,[(330,520),(345,560),(371,586),(410,599),(453,603),(487,599),
         (525,584),(553,558),(574,528),(601,481),(627,448)])]
for width,pts in harbor_lanes:
    road=LineString(smooth(pts)).buffer(width)
    # A curb only borders grass. The rounded end of the lane must not be outlined
    # inside the quay; the same cobble UVs carry across both public surfaces.
    shoulder=road.buffer(2).intersection(land).difference(quay)
    draw_shape("PortLaneKerb",shoulder,-7,color="aaa38eff",code="r")
    draw_shape("PortLane",road.intersection(land),-6,"cobbles",code="r")

# The native wharf sprite includes the seaward fascia and piles; only the plank top is walkable.
deck=Polygon([(42,488),(313,488),(314,506),(316,537),(314,553),(310,559),
              (43,559),(20,543),(20,513)])
assert deck.distance(land)<8
ImageDraw.Draw(surface).polygon(list(deck.exterior.coords),fill=ord("d"))
sprite("ship",143,493,236,224,"PassengerShip",z=-5,world=True)
# Intersect the timber profile with the quay so the fascia and the final pile end at the wall.
landing_outline=Polygon([(20,488),(313,488),(314,506),(316,537),(314,553),(310,559),
                         (303,565),(297,570),(291,580),(288,600),(20,600)])
draw_shape("FerryLanding",landing_outline,-3,"wharf")
aw,ah=REGIONS["wharf"][2:]
# draw_shape clips against the extent; use its final vertex order for the sprite's UVs.
deck_uv=list(landing_outline.intersection(extent).simplify(.25).exterior.coords)[:-1]
scene.append('uv = PackedVector2Array('+', '.join(f'{(x-20)*aw/312:.2f}, {(y-488)*ah/112:.2f}' for x,y in deck_uv)+')')
lip=[(313,488),(314,506),(316,537),(314,553),(310,559)]
threshold=Polygon(lip+[(x+7,y) for x,y in lip[::-1]])
draw_shape("LandingSill",threshold,-2,"granite",color="b5a997ff",code="q")
for y,x in [(496,313.5),(514,314.5),(534,315.8),(550,314.3)]:
    draw_shape("SillJoint",LineString([(x,y),(x+7,y-.5)]).buffer(.55),-2,color="807a70ff")
for x,y in [(313,489),(311,557)]:
    draw_shape("BankAbutment",Polygon([(x-7,y-2),(x+7,y-2),(x+8,y+2),(x-6,y+3)]),-2,"granite",color="c3b8a3ff")
for y in [492,552]:
    draw_shape("TiePlate",box(305,y,316,y+2),-2,color="746854ff")
    draw_shape("TieBolt",box(307,y,308.5,y+1),-2,color="c3b5a1ff")
sprite("sailboat",216,669,105,135,"Dinghy",z=1,world=True)
def waterline(points):
    return LineString(smooth(points)).intersection(west_water)
for water_curve in [[(173,645),(181,656),(202,666),(224,670),(246,663),(257,654)],
                    [(58,467),(69,480),(95,487),(124,491)],
                    [(37,541),(29,543),(23,540),(20,534)]]:
    wake=waterline(water_curve)
    draw_shape("HullWaterline",wake.buffer(3),-6,color="175667a6")
    draw_shape("HullRipple",wake.buffer(.8),-5,color="b2e7e1ec")
for px in [44,97,150,204,259]:
    ripple=waterline([(px-8,597),(px-5,600),(px,602),(px+6,600),(px+8,598)])
    draw_shape("PileRipple",ripple.buffer(1.15),-5,color="c8efeadd")
for hull in [box(72,457,211,486),box(191,641,249,659)]:
    assert west_water.covers(hull) and not deck.intersects(hull)
sprite("cargo",120,526,74,53,"LandingCargo",base=(-24,-9,49,9),world=True)
sprite("cargo",270,511,56,42,"LandingBarrels",base=(-18,-7,36,7),flip=True,world=True)
sprite("passenger-station",459,579,167,117,"PassengerStation",("harbor","harbor","白鹭河客运站"),
       (-48,-23,86,23),world=True)
sprite("lamp",371,476,24,90,"TicketOfficeLamp",base=(-4,-5,8,5),world=True)
bank_ys=[y for x,y in coastline]
bank_xs=[x for x,y in coastline]
def rim_x(y):
    return float(np.interp(y,bank_ys,bank_xs))
for i,y in enumerate([98,164,228,311,360,464,609,650,710,790,852,928,1028]):
    x=rim_x(y)+11
    sprite("bollard",x,y,13,21,f"QuayBollard{i+1:02}",base=(-4,-4,8,4),world=True)

def building(key,x,y,w,h,name=None,plot=None,foot=.78):
    sprite(key,x,y,w,h,name,plot,(-w*foot/2,-h*.29,w*foot,h*.29),shadow=True)
    bounds.append(pixel_rect(*placed(x,y),w*.85,h*.66))

building("hall",hall_x,hall_y,232,261,"TownHall",("commercial_street:bank","bank","白鹭河市政厅 · 银行"))
building("chapel",1501,259,186,225,"Chapel",("landmark","landmark","彩窗礼拜堂"))
building("forge",839,197,371,190,"Forge",("workshops","supply_factory","炉火铁匠铺"))
building("inn",1021,692,413,217,"HarborInn",("hotel","hotel","白鹭河旅馆"),.78)
building("market",895,306,269,137,"ProduceMarket",("market-main","market","喷泉广场露天市集"))
building("mill",229,718,159,257,"Windmill",("mill","landmark","麦田风车磨坊"),.46)
building("thatch",400,650,121,127,"MillHouse",("residences-a","urban_village","磨坊巷住宅"))
building("thatch",512,716,120,123,"BakersCottage",("competitor:shop:0","competitor","麦香面包屋"))
building("shop",1228,470,143,119,"StreetGrocer",("market-neighborhood","market","邻里鲜蔬市"))
building("twins",1350,471,122,149,"EastBistro",("competitor:shop:1","competitor","红瓦小馆"))
building("gable",1511,447,118,148,"EastCafe",("competitor:shop:2","competitor","花窗咖啡馆"))
building("gable",1608,423,115,148,"EastHouse",("residences-b","rich_district","花园街住宅"))
for key,x,y,w,h,flip in [
    ("gable",132,125,127,163,0),("twins",370,54,84,83,1),
    ("gable",1048,110,108,141,0),("gable",1601,65,101,119,0),
    ("gable",1666,143,92,132,1),("twins",-26.5,191,135,110,0),
    ("gable",17.7,307,110,123,0),("twins",1451,638,143,117,0),("twins",1597,600,153,154,0),
    ("gable",602,929,169,139,0),("gable",474,973,101,97,1)]:
    building(key,x,y,w,h)
    if flip:
        # Flipping the graphic keeps the symmetric wall footing fixed.
        k=next(j for j in range(len(scene)-1,-1,-1) if scene[j].startswith('metadata/art'))
        scene.insert(k,'flip_h = true')
# The basin ellipse is centred 37 px behind the sprite's front lip.
sprite("fountain",square_x,square_y+37/SPACING,141,121,"Fountain",("plaza","plaza","彩石喷泉广场"),(-49,-23,98,23),shadow=True)
sprite("well",405,758,64,91,"VillageWell",base=(-20,-14,40,14),shadow=True)
sprite("gate",304,873,155,122,"StoneGate")
gate_x,gate_y=placed(304,873)
for dx in [-47,49]:
    gx,gy=gate_x+dx,gate_y-7
    draw_shape("GatePierBase",pixel_rect(gx,gy,19,21),-4,color="716e6280")
    ImageDraw.Draw(reserved_solids).rectangle((gx-10,gy-21,gx+10,gy),fill=1)
    ImageDraw.Draw(solids).rectangle((gx-10,gy-21,gx+10,gy),fill=1)
sprite("carriage",261,378,113,70,"TownHallCarriage",base=(-40,-13,80,13),shadow=True)
sprite("carriage",785,680,125,65,"InnCarriage",base=(-44,-12,88,12),shadow=True)
for x,y,w in [(956,383,76),(1083,387,72)]:
    sprite("fruitcart",x,y,w,w*249/329,base=(-w*.28,-10,w*.56,10),shadow=True)
sprite("bench",447,316,84,50,"TownHallBench",base=(-33,-8,66,8))
for x,y,h in [(150,347,98),(1199,486,89)]: sprite("lamp",x,y,h*.24,h,base=(-4,-4,8,4))
for x,y in [(560,405),(648,323),(800,311),(859,403),(852,523),(579,530),(939,691),(993,697),(1082,685)]:
    sprite("planter",x,y,41,35,base=(-10,-5,20,5))
# Author each clump of grain separately. Curving fence runs follow the planted field.
field=Polygon([(0,578),(48,565),(101,564),(145,575),(183,605),(169,650),(135,672),(177,706),(201,744),(195,786),(137,808),(0,808)])
draw_shape("WheatSoil",projected(field).difference(quay.buffer(3)),-5,color="a48041ff",code="w")
for y in range(597,816,20):
    for x in range(-19,220,30):
        xx=x+rng.randint(-5,5)
        if field.covers(Point(max(0,xx),y-12)):
            w,h,flip=45+rng.randrange(9),35+rng.randrange(8),rng.choice([0,1])
            px,py=placed(xx,y)
            if quay.intersects(pixel_rect(px,py,w+4,h+2)):
                if xx<0: continue
                curb=quay.intersection(box(0,py-h-2,W,py+2))
                px=curb.bounds[2]+w/2+2
            sprite("wheat",px,py,w,h,flip=flip,world=True)
def fence_line(points):
    trail=LineString(points)
    count=max(1,round(trail.length*SPACING/32))
    for i in range(count):
        a,b=trail.interpolate(i/count,normalized=True),trail.interpolate((i+1)/count,normalized=True)
        x,y=(a.x+b.x)/2,(a.y+b.y)/2
        w=abs(a.x-b.x)*SPACING+8
        sprite("fence",x,y,max(12,w),22+abs(a.y-b.y)*SPACING,base=(-w*.42,-4,w*.84,4))
fence_line([(36,571),(65,564),(107,563),(159,573)])
fence_line([(0,809),(80,813),(146,810),(194,793),(202,757)])
fence_line([(1289,638),(1309,628)])
fence_line([(1318,640),(1373,625)])
# The main oak stands alone west of the chapel. Place boundary woodland and smaller trees by hand.
trees=[
 (21,70,96,95),(4,24,69,73),(-83,136,73,64),(229,46,69,76),(276,42,64,68),(433,56,75,65),(448,49,52,54),(550,49,82,76),
 (694,78,83,89),(753,42,69,71),(931,43,60,69),(971,46,63,70),(1125,71,66,74),(1239,57,85,80),(1318,46,88,79),
 (1392,59,81,90),(1445,70,72,85),(1535,39,72,75),(1601,110,65,74),(1630,248,93,103),(1669,190,75,91),
 (1370,134,108,103),(1362,283,191,201),(1151,233,67,76),(1266,82,71,76),(179,196,77,92),(155,288,87,86),
 (72,258,43,51),(155,319,45,49),(439,221,53,62),(414,163,66,74),(449,261,55,63),(726,237,45,55),
 (136,410,62,69),(149,559,70,76),(169,580,68,64),(312,624,68,91),(151,698,70,77),(291,694,41,54),(483,592,79,77),
 (565,688,52,67),(749,647,73,78),(700,680,57,68),(1148,505,76,77),(1359,609,73,89),(1494,542,72,65),
 (20,920,66,81),(86,950,82,95),(188,930,51,51),(414,952,83,61),(506,899,74,81),(608,827,62,67),(699,852,76,81),(737,851,64,67)]
for i,(x,y,w,h) in enumerate(trees):
    key="oak" if i==23 else ["oak_wide","lime","oak","shrub","lime"][i%5]
    sprite(key,x,y,w,h,base=(-w*.07,-h*.09,w*.14,h*.09),flip=i%3==1,shadow=True)
flower_beds=[(183,94),(307,34),(415,53),(447,57),(538,115),(576,123),(976,58),(1100,103),(1142,216),(1200,171),
 (1399,257),(1434,255),(1559,260),(1583,257),(216,254),(49,286),(19,286),(517,303),(547,314),(606,295),(677,278),
 (795,264),(808,290),(1147,333),(929,617),(899,657),(989,663),(1085,659),(715,664),(348,645),(446,646),(541,712),(469,709),
 (295,710),(164,712),(205,729),(260,863),(374,865),(694,900),(655,904),(538,929),(460,944),(1442,631),(1512,615),(1558,584)]
open_lawns=[box(27*CELL,3*CELL,32*CELL,7*CELL),
            box(28*CELL,7*CELL,33*CELL,11*CELL),
            box(55*CELL,4*CELL,60*CELL,8*CELL)]
for x,y in flower_beds:
    w=rng.randint(20,40)
    if any(lawn.intersects(pixel_rect(*placed(x,y),w,w*.7)) for lawn in open_lawns): continue
    sprite("flowers",x,y,w,w*.7,flip=rng.choice([0,1]))
for x,y,w in [(422,408,53),(316,520,30),(43,550,43),(132,853,47),(372,893,37),(659,762,30),(1243,253,54),
              (1364,282,31),(1281,361,53),(1168,396,29),(1250,579,34),(1104,139,31),(698,225,27)]:
    # A grass parcel remains clear all the way to its boundary. Fit the cluster
    # on the cells that already contain its stones, including their uphill feet.
    px,py=placed(x,y)
    old=(math.ceil(px-w*.28),math.ceil(py-4),math.ceil(px+w*.28)-1,math.ceil(py)-1)
    ImageDraw.Draw(reserved_solids).rectangle(old,fill=1)
    left,top=(old[0]//CELL)*CELL,(old[1]//CELL)*CELL
    right,bottom=(old[2]//CELL+1)*CELL,(old[3]//CELL+1)*CELL
    w=min(w,(right-left-2)/.92)
    h=w*.60
    px=min(max(px,left+.46*w+1),right-.46*w-1)
    py=min(max(py,top+.52*h+1),bottom+.02*h-1)
    sprite("rock",px,py,w,h,base=(-w*.46,-h*.52,w*.92,h*.50),world=True)
# A few copses on the outside of the new southern meadow frame its open building land.
for i,(x,y,w,h) in enumerate([(1490,1080,86,86),(1555,1091,58,66),(1773,1059,60,67),
        (1818,1075,88,92),(2015,988,64,66),(2058,1005,86,88),(2204,1073,79,86),
        (2251,1054,81,81),(2261,867,73,78)]):
    sprite(["lime","shrub","oak_wide"][i%3],x,y,w,h,base=(-5,-6,10,6),shadow=True,world=True)
for x,y in [(1519,1075),(1744,1065),(2036,1009),(2181,1078)]:
    sprite("flowers",x,y,24,15,world=True)

# The grass between the stair-stepped north wall and the town is lightly planted.
for i,(x,y,w,h) in enumerate([(129,28,54,67),(185,66,64,72),(241,40,58,58),
        (193,120,41,42),(267,152,42,57),(271,220,51,57),(315,283,37,45),
        (269,807,42,43),(224,891,32,30),(287,995,46,45)]):
    sprite(["lime","oak_wide","shrub"][i%3],x,y,w,h,base=(-4,-4,8,4),world=True)
for x,y in [(213,131),(245,182),(283,243),(320,292),(275,802),(241,881),(281,976)]:
    sprite("flowers",x,y,23,17,world=True)
# Small wildflowers belong to the meadow, scattered in patches between the larger props.
for _ in range(460):
    x,y=rng.randrange(W),rng.randrange(H)
    if surface.getpixel((x,y))!=ord(".") or any(b.contains(Point(x,y)) for b in bounds): continue
    wid=rng.uniform(7,18)
    sprite("daisies",x,y,wid,wid*.44,z=-4,flip=rng.choice([0,1]),world=True)
# Store the same foot mask and clear whole-cell building land used by the native art.
surf=np.asarray(surface)
reserved=np.asarray(reserved_solids)
walk=np.isin(surf,[ord(c) for c in ".qrdgt"]) & ~np.asarray(solids)
wall_pixels=np.asarray(walls)
clear_ground=walk & ~wall_pixels
walk &= ~wall_clearance(walls,40/24)
# The shore reaches the southwest corner, with uninterrupted land across the southern town.
assert np.all(surf[-1,264:] != ord("~")) and np.all(surf[:,350:] != ord("~"))
assert np.all(surf[-1,:205] == ord("~"))
cells,frontage,build=[],[],[]
for y in range(73):
    cs,fs,bs=[],[],[]
    for x in range(73):
        lx,ly=(x-OX)*CELL,(y-OY)*CELL
        if lx<0 or ly<0 or lx+CELL>W or ly+CELL>H:
            cs.append("_");fs.append("-");bs.append("-");continue
        tile=surf[ly:ly+CELL,lx:lx+CELL]
        value=chr(tile[CELL//2,CELL//2])
        # A grass verge can touch the street without its centre becoming stone.
        road=value in "rtqgd" or (value=="." and np.any(np.isin(tile,[ord(c) for c in "rtqg"])))
        fs.append("+" if road else "-")
        cs.append(value)
        bs.append("." if np.all(tile==ord(".")) and not reserved[ly:ly+CELL,lx:lx+CELL].any() else "-")
    cells.append("".join(cs));frontage.append("".join(fs));build.append("".join(bs))
for row,(x,y) in zip(plot_rows,doors):
    options=[]
    for gy in range(max(0,int(y//CELL)+OY-1),min(73,int(y//CELL)+OY+4)):
        for gx in range(max(0,int(x//CELL)+OX-3),min(73,int(x//CELL)+OX+4)):
            px,py=(gx-OX)*CELL+CELL//2,(gy-OY)*CELL+CELL//2
            if 4<=px<W-4 and y+3<=py<H-4 and walk[py-3:py+4,px-3:px+4].all():
                options.append(((px-x)**2+(py-y-8)**2,gx,gy))
    assert options,row
    _,row[7],row[8]=min(options)
# These three vacant commercial properties follow paved frontage and avoid special scenery.
titles=[]
for row in plot_rows:
    pid=row[0]
    if pid.startswith("competitor:shop:"): titles.append([pid,*row[3:9]])
reserved=set()
for i,(px,py) in enumerate([(396,417),(862,214),(1124,516)]):
    px,py=placed(px,py)
    options=[]
    for y in range(2,68):
        for x in range(2,68):
            footprint={(x+dx,y+dy) for dy in range(3) for dx in range(3)}
            if any(build[cy][cx]!="." for cx,cy in footprint) or reserved & footprint: continue
            if any(cx in range(r[3],r[3]+r[5]) and cy in range(r[4],r[4]+r[6]) for cx,cy in footprint for r in plot_rows):continue
            neighbors=[(x+dx,y+3) for dx in range(3)]+[(x+dx,y-1) for dx in range(3)]+[(x-1,y+dy) for dy in range(3)]+[(x+3,y+dy) for dy in range(3)]
            front=[p for p in neighbors if frontage[p[1]][p[0]]=="+" and cells[p[1]][p[0]]!="d" and walk[(p[1]-OY)*CELL+CELL//2,(p[0]-OX)*CELL+CELL//2]]
            if front:
                options.append((((x-OX+1.5)*CELL-px)**2+((y-OY+1.5)*CELL-py)**2,x,y,front[0]))
    _,x,y,(ex,ey)=min(options)
    reserved.update((x+dx,y+dy) for dx in range(3) for dy in range(3))
    titles.append([f"commercial_street:shop:{i}",x,y,3,3,ex,ey])
arrival=[5,36]
assert cells[arrival[1]][arrival[0]]=="d"
districts,land_use=survey_districts(cells, uses, plot_rows, projected(market_floor), placed, CELL, OY)
routes=measure_routes(walk, plot_rows, residential_doors, arrival, CELL, OY)
# The registered survey still validates paid leases. New sites must clear the full walls.
clear_sites=[]
for y,row in enumerate(build):
    ly=(y-OY)*CELL
    clear_sites.append("".join("." if c=="." and clear_ground[ly:ly+CELL,x*CELL:(x+1)*CELL].all() else "-" for x,c in enumerate(row)))
survey={"issued_sites":build,"arrival":arrival,"reference_frame":[WEST_MARGIN,TOP_MARGIN,SPACING],"cells":cells,"frontage":frontage,
        "districts":districts,"land_use":land_use,"routes":routes,"sites":clear_sites,"plots":plot_rows,"titles":titles,
        "walk_bits":base64.b64encode(zlib.compress(np.packbits(walk,bitorder="little").tobytes(),9)).decode()}
(ROOT/"content/towns/egret_survey.json").write_text(json.dumps(survey,ensure_ascii=False,separators=(",",":"))+"\n",encoding="utf-8")
scene.extend(['[node name="Atmosphere" type="Node2D" parent="."]', 'script = ExtResource("outdoors")'])
(ROOT/"src/town/egret_map.tscn").write_text("\n".join(scene)+"\n",encoding="utf-8")
print(f"{len(objects)} separate sprite instances, {len(plot_rows)} mapped venues, {len(titles)} stable commercial titles.")
