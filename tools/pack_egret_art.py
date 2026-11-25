"""Prepare the independent Egret Town sprites from the five commissioned art sheets."""
import argparse
import json
import math
import random
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "assets/town"
SHEETS = {
    "architecture": [["hall", "chapel"], ["inn", "forge"]],
    "village": [["mill", "thatch", "gable"], ["twins", "shop", "market"], ["oak", "fountain", "ship"]],
    "details": [["carriage", "well", "gate"], ["sailboat", "flowers", "wheat"], ["lamp", "fruitcart", "cargo"]],
    "garden": [["oak_wide", "lime", "shrub"], ["bench", "planter", "rock"], ["fence", "laundry", "daisies"]],
}


def split(sheet, rows):
    rgba = np.array(sheet.convert("RGBA"))
    n, labels, stats, centers = cv2.connectedComponentsWithStats((rgba[:, :, 3] > 20).astype("uint8"))
    height, width = labels.shape
    cells = {}
    for y, row in enumerate(rows):
        for x, key in enumerate(row):
            ids = [i for i in range(1, n) if stats[i, 4] >= 5
                   and int(centers[i, 0] * len(row) / width) == x
                   and int(centers[i, 1] * len(rows) / height) == y]
            mask = np.isin(labels, ids)
            pixels = rgba.copy()
            pixels[:, :, 3] *= mask
            image = Image.fromarray(pixels)
            cells[key] = image.crop(image.getbbox())
    return cells


def plaza():
    # Complete rings of individually cut voussoirs. The fan extends underneath the fountain.
    rng = random.Random(41)
    im = Image.new("RGBA", (820, 592))
    draw = ImageDraw.Draw(im)
    palettes = [(172, 157, 149), (206, 149, 92), (183, 99, 82), (150, 142, 145)]
    def point(r, a):
        return (410 + 408*r*math.cos(a), 296 + 294*r*math.sin(a))
    for i in range(23):
        inner, outer = i/23, (i+1)/23
        n = max(8, round(2*math.pi*(i+.5)/1.75))
        if 5 <= i < 19:
            n = max(16, round(n/16)*16)
        for j in range(n):
            shift = 0 if 5 <= i < 19 else (i%2)*.5
            a,b = 2*math.pi*(j+shift)/n, 2*math.pi*(j+1+shift)/n
            col = palettes[([2,3,1,3]*4)[min(15,int((j+.5)*16/n))]] if 5<=i<19 else palettes[0]
            tone = rng.randint(-15, 14)
            fill = tuple(np.clip(np.array(col)+tone, 0, 255).tolist())
            perimeter = [point(outer,a+(b-a)*k/5) for k in range(6)] + [point(inner,b-(b-a)*k/5) for k in range(6)]
            draw.polygon(perimeter, fill=fill, outline=(91,77,76))
            draw.line(perimeter[:6], fill=tuple(min(255,c+23) for c in fill), width=2)
            for _ in range(i//4+1):
                px,py=point(rng.uniform(inner,outer),rng.uniform(a,b))
                draw.point((px,py),fill=tuple(max(0,c-15) for c in fill))
    return im


def dock():
    rng=random.Random(19)
    scale=2
    im=Image.new("RGBA",(910,405))
    d=ImageDraw.Draw(im)
    def poly(points, fill, outline=None):
        d.polygon([(round(x*scale),round(y*scale)) for x,y in points],fill=fill,outline=outline,width=2)
    def line(points, fill, w=1):
        d.line([(round(x*scale),round(y*scale)) for x,y in points],fill=fill,width=w)
    a,b,c=(5,35),(126,3),(444,131)
    tip=(323,164)
    for start,end in [(a,tip),(tip,c)]:
        poly([start,end,(end[0],end[1]+12),(start[0],start[1]+12)],"#865033","#523529")
    for start,end,n in [(a,tip,10),(tip,c,4),(b,c,10)]:
        for i in range(n+1):
            t=i/n
            x=start[0]*(1-t)+end[0]*t
            y=start[1]*(1-t)+end[1]*t
            poly([(x-3,y),(x+4,y),(x+3,y+28),(x,y+32),(x-3,y+29)],"#805033","#4c3027")
            line([(x+1,y+2),(x+1,y+26)],"#c2874e",2)
    def p(u,v):
        return (a[0]+(b[0]-a[0])*u+(tip[0]-a[0])*v,a[1]+(b[1]-a[1])*u+(tip[1]-a[1])*v)
    colors=["#c88750","#c88b53","#d3965b","#dba165","#c08a57","#dea768"]
    for i in range(44):
        v=i/44
        poly([p(0,v),p(1,v),p(1,(i+1)/44),p(0,(i+1)/44)],rng.choice(colors),"#815432")
        line([p(.02,v+.003),p(.98,v+.003)],"#f0c797",2)
        u=rng.uniform(.02,.56)
        line([p(u,v+.012),p(u+rng.uniform(.13,.37),v+.012)],"#b57a4c",2)
    for start,end,n in [(a,tip,6),(tip,c,2),(b,c,6)]:
        for i in range(n+1):
            t=i/n
            x=start[0]*(1-t)+end[0]*t
            y=start[1]*(1-t)+end[1]*t
            poly([(x-3,y),(x+3,y),(x+3,y-10),(x-3,y-10)],"#9d603a","#684029")
            d.ellipse([(int((x-3)*2),int((y-12)*2)),(int((x+3)*2),int((y-9)*2))],fill="#e5be82",outline="#654630")
    return im


def main(folder):
    items={}
    for stem, rows in SHEETS.items():
        items.update(split(Image.open(folder/(stem+".png")),rows))
    items["mosaic"]=plaza()
    items["pier"]=dock()
    atlas=Image.new("RGBA",(2048,4096))
    x=y=line_height=2
    regions={}
    for key, im in items.items():
        if x+im.width+2>atlas.width:
            x=2
            y+=line_height+4
            line_height=0
        atlas.paste(im,(x,y))
        regions[key]=[x,y,*im.size]
        line_height=max(line_height,im.height)
        x+=im.width+4
    used=y+line_height+2
    assert used<=atlas.height
    atlas.crop((0,0,atlas.width,used)).save(ART/"egret-sprites.png")
    (ROOT/"tools/map_art/egret-regions.json").write_text(json.dumps(regions,indent=2)+"\n")
    materials=Image.open(folder/"materials.png").convert("RGB")
    w,h=materials.size
    for k,name in enumerate(["grass","cobbles","sea","quay"]):
        x=(k%2)*w//2
        y=(k//2)*h//2
        im=materials.crop((x+6,y+6,x+w//2-6,y+h//2-6)).resize((256,256),Image.Resampling.LANCZOS)
        # Blend opposite edges inside a narrow overlap to avoid reflective seams in masonry.
        a=np.array(im).astype(float)
        for axis in (0,1):
            b=np.swapaxes(a,0,axis).copy()
            for j in range(18):
                t=(1-j/18)*.5
                left,right=b[j].copy(),b[-1-j].copy()
                b[j]=left*(1-t)+right*t
                b[-1-j]=right*(1-t)+left*t
            a=np.swapaxes(b,0,axis)
        Image.fromarray(a.astype("uint8")).save(ART/("egret-"+name+".png"))

if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("folder",type=Path)
    main(parser.parse_args().folder)
