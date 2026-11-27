"""Extract each edible silhouette from the plated recipe atlas for the kitchen props."""
from pathlib import Path
import json

import cv2
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1] / "assets"
CELL = (128, 96)
# Normalized against each visible dish, independent of padding in the source sheet.
BOWL = {"C03":(50,47,41,32),"C04":(50,45,36,21),"C07":(50,49,41,34),
        "C10":(50,47,42,34),"C12":(50,48,38,27),"C14":(50,47,42,37),
        "C15":(50,47,42,34),"C16":(50,48,37,32),"C19":(43,45,34,24),
        "E03":(50,35,34,30),"E07":(50,40,42,34),"E09":(50,48,41,37),
        "E11":(50,45,43,35),"E15":(50,45,43,36),"J03":(50,41,42,32),
        "J05":(50,42,43,34),"J06":(50,40,43,31),"J10":(50,42,42,31),
        "J11":(50,42,42,32),"J13":(50,44,41,32),"J14":(50,40,41,30),
        "J16":(50,43,42,32),"J17":(50,43,42,34),"C20":(50,42,17,10)}
# Plate-free outlines for foods which project well outside the rim or are nearly white.
SHAPES = {
    "C08":[(2,74),(9,59),(39,38),(66,29),(77,39),(94,20),(99,8),(96,41),(99,50),(82,54),(69,73),(25,86),(6,83)],
    "E01":[(5,28),(16,8),(34,3),(51,13),(69,1),(85,2),(96,23),(91,59),(76,85),(57,93),(25,94),(8,78)],
    "E18":[(12,31),(17,17),(34,4),(65,2),(85,12),(91,26),(86,43),(77,51),(39,56),(16,44)],
    "J01":[(2,79),(12,46),(29,27),(43,31),(46,19),(62,1),(73,3),(90,37),(87,66),(75,72),(68,86),(38,90),(21,84)],
}
def silhouette(rgba, key):
    alpha = np.asarray(rgba.getchannel("A"))
    crop = Image.fromarray(np.uint8(alpha > 48)*255).getbbox()
    rgba = rgba.crop(crop)
    image = np.array(rgba)
    h,w = image.shape[:2]
    y,x = np.mgrid[:h,:w]
    xx, yy = (x+.5)*100/w, (y+.5)*100/h
    sat = cv2.cvtColor(image[:,:,:3],cv2.COLOR_RGB2HSV)[:,:,1]
    if key in BOWL:
        cx,cy,rx,ry = BOWL[key]
        field=((xx-cx)/rx)**2+((yy-cy)/ry)**2
        # The narrow irregular rim follows the food, with no part of the bowl wall below it.
        mask = (field < .94) | ((field<1.07) & (sat>95))
    elif key in SHAPES:
        mask = np.zeros((h,w),np.uint8)
        contour = np.array([(round(a*w/100),round(b*h/100)) for a,b in SHAPES[key]],np.int32)
        cv2.fillPoly(mask,[contour],1)
    else:
        field=((xx-50)/47)**2+((yy-48)/47)**2
        # The plates share a cream glaze. Seeds on the porcelain and transparent
        # exterior separate it from food without removing pale ingredients inside.
        labels=np.full((h,w),cv2.GC_PR_BGD,np.uint8)
        labels[((field<.83)&(sat>42)) | ((field<1.18)&(sat>85))]=cv2.GC_PR_FGD
        labels[(field<.72)&(sat>95)]=cv2.GC_FGD
        labels[(image[:,:,3]<50)|((field>1.12)&(sat<75))]=cv2.GC_BGD
        if np.any(labels==cv2.GC_FGD):
            cv2.grabCut(image[:,:,:3].copy(),labels,None,np.zeros((1,65),np.float64),np.zeros((1,65),np.float64),4,cv2.GC_INIT_WITH_MASK)
        mask = ((labels==cv2.GC_FGD)|(labels==cv2.GC_PR_FGD))
    if key=="J08":
        # Sushi rice is close in colour to the plate, but enclosed by the nori.
        contours,_=cv2.findContours(mask.astype(np.uint8),cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)
        mask=np.zeros((h,w),np.uint8)
        cv2.drawContours(mask,contours,-1,1,cv2.FILLED)
    image[:,:,3]=np.where(mask,image[:,:,3],0)
    result=Image.fromarray(image)
    return result.crop(result.getbbox())

def mushroom_soup():
    """Two pixel tiles for the recipe icon and the food-only cooking overlay."""
    sheet = Image.new("RGBA", (96, 40))
    draw = ImageDraw.Draw(sheet)
    draw.ellipse((4, 11, 43, 34), fill="#3d2d29")
    draw.ellipse((5, 11, 42, 31), fill="#ad8765")
    draw.ellipse((4, 8, 43, 27), fill="#e7d0ac")
    draw.ellipse((6, 9, 41, 25), fill="#f9e8c6")
    for x in (0, 48):
        draw.ellipse((x+8, 11, x+39, 24), fill="#95704e")
        draw.ellipse((x+9, 11, x+38, 23), fill="#cba87b")
        draw.ellipse((x+11, 12, x+36, 21), fill="#e8cba0")
        for cx, cy in ((15, 16), (24, 19), (31, 15)):
            draw.rectangle((x+cx, cy, x+cx+1, cy+2), fill="#b28962")
            draw.polygon([(x+cx-3, cy), (x+cx-2, cy-2), (x+cx+2, cy-2),
                          (x+cx+3, cy)], fill="#785239")
        for gx, gy in ((20, 13), (28, 19), (34, 18), (11, 18)):
            draw.rectangle((x+gx, gy, x+gx+1, gy), fill="#67733a")
    return sheet.resize((288, 120), Image.Resampling.NEAREST)


def main():
    cv2.setRNGSeed(140)
    directory = ROOT / "redraw-v1"
    index = json.loads((directory / "index.json").read_text(encoding="utf-8"))
    regions = json.loads((directory / "icon-regions.json").read_text(encoding="utf-8"))
    pages = [Image.open(directory / f"dishes-{page}.png").convert("RGBA") for page in range(3)]
    tiles = Image.new("RGBA", (CELL[0] * 8, CELL[1] * 8))
    for i, key in enumerate(index["dish_ids"]):
        page, cell = divmod(index.get("dish_slots", {}).get(key, i), 20)
        x, y, w, h = regions[f"dishes-{page}.png"][cell]
        food = silhouette(pages[page].crop((x, y, x + w, y + h)), key)
        food.thumbnail((CELL[0] - 4, CELL[1] - 4), Image.Resampling.LANCZOS)
        tiles.paste(food, (i % 8 * CELL[0] + (CELL[0] - food.width) // 2,
                           i // 8 * CELL[1] + (CELL[1] - food.height) // 2))
    # Scrambled curds have their own frame before tomatoes enter the wok.
    process = Image.open(ROOT / "kitchen/cooking-process.png")
    x, y = 3 * CELL[0], 4 * CELL[1]
    tiles.paste(process.crop((x, y, x + CELL[0], y + CELL[1])), (7 * CELL[0], 7 * CELL[1]))
    tiles.save(ROOT / "kitchen/cooking-food.png", optimize=True)
    mushroom_soup().save(ROOT / "kitchen/mushroom-soup.png", optimize=True)

if __name__ == "__main__":
    main()
