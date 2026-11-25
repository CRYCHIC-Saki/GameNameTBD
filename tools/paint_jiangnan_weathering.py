"""Pixel-art wear and shoreline accents layered over the surveyed town."""

import math
import random

import numpy as np
from PIL import Image, ImageDraw


def contact_shadows(entries, props, regions, sprite_atlas, land, pavement):
    buildings = {part["id"]: part for part in props}
    shadow = Image.new("RGBA", land.size)
    brush = ImageDraw.Draw(shadow)
    for entry in entries:
        left, _, width, height = entry["bounds"]
        _, baseline = entry["door"]
        ax, ay, aw, ah = regions[buildings[entry["id"]]["sprite"]]
        outline = sprite_atlas.crop((ax,ay,ax+aw,ay+ah)).getchannel("A")
        outline = np.asarray(outline.resize((width,height), Image.Resampling.BILINEAR))
        for x in range(width):
            base = np.flatnonzero(outline[int(height*.77):,x] > 100)
            if not base.size:
                continue
            y = baseline - height + int(height*.77) + int(base[-1])
            brush.point((left+x,y+1), fill=(26,41,56,181))
            brush.point((left+x,y+2), fill=(35,49,61,112 if (left+x)//3%4 else 80))
    pixels = np.asarray(shadow).copy()
    pixels[(np.asarray(land) == 0) | (np.asarray(pavement) > 0),3] = 0
    return Image.fromarray(pixels)


def weathered_ground(land, stone, decks):
    art = Image.new("RGBA",land.size)
    ink = ImageDraw.Draw(art)
    on_stone = np.asarray(stone)>0
    rng = random.Random(802021)
    for i in range(370):
        x,y = rng.randrange(21,1649),rng.randrange(90,783)
        if not on_stone[y,x]:
            continue
        if not i%6:
            w,h=rng.randrange(6,14),rng.randrange(3,7)
            ink.polygon([(x-w,y+1),(x-w+3,y-h//2),(x+w-3,y-h//2-1),
                         (x+w,y),(x+w-3,y+h//2),(x-3,y+h//2+1)],fill=(32,48,52,130))
            ink.line([(x-w+4,y-1),(x-2,y-2),(x+3,y-2)],fill=(133,161,152,126))
        elif i%3:
            w=rng.randrange(4,11)
            ink.line([(x-w,y),(x-3,y+1),(x,y-1),(x+3,y),(x+w,y-2)],
                     fill=(35,39,39,143))
            ink.line([(x-1,y),(x+1,y+3),(x+3,y+4)],fill=(43,48,43,117))
        else:
            for _ in range(8):
                a,b=x+rng.randrange(-6,7),y+rng.randrange(-2,4)
                ink.point((a,b),fill=(73,92,39,rng.randrange(119,191)))
    # Fresh market puddles and cart tracks worn through the thin dusty layer.
    for x,y,w,h in [(367,280,12,5),(413,297,14,5),(467,266,9,4),(257,720,9,3),(656,722,13,4)]:
        ink.ellipse((x-w,y-h,x+w,y+h),fill=(53,61,57,120))
        ink.line([(x-w+4,y-h+1),(x+4,y-h+1)],fill=(147,156,144,105))
    for cx,cy in [(284,719),(410,718),(675,726),(379,261)]:
        for _ in range(7):
            x,y = cx+rng.randrange(-8,10),cy+rng.randrange(2,9)
            ink.polygon([(x-2,y),(x+1,y-1),(x+2,y),(x,y+1)],fill=(76,99,43,224))
    carts = [[(150,679),(190,661),(221,658),(267,658),(307,656),(339,650)],
             [(392,164),(435,173),(482,170),(510,170),(558,171),(585,175)],
             [(234,731),(285,736),(347,742),(392,744),(471,742)]]
    for track in carts:
        for side in (-3,3):
            line=[(x,y+side) for x,y in track]
            ink.line(line, fill=(83,66,50,98),width=2,joint="curve")
            ink.line([(x,y+1) for x,y in line],fill=(171,153,109,78))
    rgba=np.asarray(art).copy()
    rgba[~on_stone,3]=0
    art=Image.fromarray(rgba)

    water=(np.asarray(land)==0) & ~(np.asarray(decks)>0)
    spray=Image.new("RGBA",land.size)
    ink=ImageDraw.Draw(spray)
    for x,y,w,h in [(958,270,54,12),(902,601,45,13)]:
        for step in range(4):
            radius=w-step*4
            ink.ellipse((x-radius,y-h//2+step,x+radius,y+h-step),
                        fill=(15,36,48,100+step*24))
    for x,y in [(1356,695),(1416,659),(1492,648),(1197,668),(826,786),(849,787)]:
        for k in range(5):
            a,b=x+k*4,y+round(math.sin(k)*2)
            ink.line([(a,b),(a+2,b-1),(a+4,b-1)],fill=(177,228,204,145 if k%2 else 198))
    pixels=np.asarray(spray).copy()
    pixels[~water,3]=0
    art.alpha_composite(Image.fromarray(pixels))
    return art


def damp_wall(sprite):
    rgba = np.asarray(sprite).copy()
    y,x=np.indices(rgba.shape[:2])
    sill=np.clip((y/sprite.height-.82)*3.0,0,.38)
    mottling=.65+.35*((x*13+y*11)%19)/18
    rgba[:,:,:3]=(rgba[:,:,:3]*(1-sill*mottling)[...,None]).astype(np.uint8)
    return Image.fromarray(rgba)


def shade_blossoms(sprite):
    rgba=np.asarray(sprite).copy()
    y,x=np.indices(rgba.shape[:2])
    rgb=rgba[:,:,:3].astype(float)
    petals=(rgb[:,:,0]>rgb[:,:,1]*1.13)&(rgb[:,:,2]>rgb[:,:,1]*1.03)
    lighting=(1.09-.20*y/sprite.height-.055*x/sprite.width)[...,None]
    rgba[petals,:3]=np.clip((rgb*lighting)[petals],0,255).astype(np.uint8)
    return Image.fromarray(rgba)


def quay_masonry_face(apron, stone, land):
    """Extrude the actual last opaque deck texel; water is behind the masonry."""
    h,w = apron.shape
    art = Image.new("RGBA",(w,h))
    pixels = art.load()
    grain = np.asarray(stone.convert("L"),dtype=float)
    grain = np.clip((grain-np.median(grain))*.30,-12,12)
    colors = [(112,110,100),(127,124,111),(103,107,105),(120,117,104),(109,115,110)]
    rng = random.Random(824)
    beds = []
    for _ in range(4):
        blocks = []
        while len(blocks)<w:
            length = rng.randrange(15,34)
            tint = rng.choice(colors)
            blocks.extend((tint,offset) for offset in range(length))
        beds.append(blocks)
    # The exposed west return is visible in the oblique view, even where the
    # southern face tapers to one column. Stop the masonry at natural land.
    for y in np.flatnonzero(apron.any(axis=1)):
        start = int(np.flatnonzero(apron[y])[0])
        for depth in range(19,0,-1):
            side = start-1-depth//6
            if not land[y+depth,side]:
                tint = 75 if depth%7 else 52
                pixels[side,int(y)+depth] = (tint,tint+3,tint+1,255)
    for x in np.flatnonzero(apron.any(axis=0)):
        lip = int(np.flatnonzero(apron[:,x])[-1])
        for depth in range(-2,26):
            course, row = divmod(max(0,depth-3),7)
            color,joint = beds[course][x]
            relief = int(grain[(lip+depth)%grain.shape[0],x%grain.shape[1]]) - course*5
            if depth <= 0:
                color,relief = (156,151,135),0
            elif depth == 1:
                color,relief = (183,174,150),0
            elif depth == 2:
                color,relief = (63,65,62),0
            elif depth >= 23:
                color = (59,77,73)
                relief = int(grain[depth%grain.shape[0],x%grain.shape[1]])
            elif row==6 or joint==0:
                relief -= 26
            elif row==0 or joint==1:
                relief += 13
            pixels[int(x),lip+depth] = tuple(c+relief for c in color)+(255,)
    # Iron rings bolt into individual capstones on either side of the gangway.
    brush = ImageDraw.Draw(art)
    span = np.flatnonzero(apron.any(axis=0))
    for fraction in (.16,.32,.71,.89):
        x = int(span[round((len(span)-1)*fraction)])
        y = int(np.flatnonzero(apron[:,x])[-1])+7
        brush.rectangle((x-1,y-2,x+1,y+1),fill="#706755")
        brush.ellipse((x-3,y,x+3,y+6),outline="#35413f",width=2)
        brush.line((x-2,y+1,x,y),fill="#93927d")
        brush.point((x+1,y+5),fill="#aba18b")
    return art
