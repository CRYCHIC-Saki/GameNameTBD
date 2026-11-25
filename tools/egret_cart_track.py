"""Paint the wheel-worn lane beneath the mill gate from the local soil atlas."""
import math

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from shapely.geometry import Polygon


def cart_track(spine, destination, atlas):
    rng = np.random.default_rng(1352)
    stations = np.arange(0, spine.length + 2, 2)
    centers = np.array([spine.interpolate(float(s)).coords[0] for s in stations])
    tangents = np.gradient(centers, axis=0)
    normals = np.column_stack((-tangents[:, 1], tangents[:, 0]))
    normals /= np.linalg.norm(normals, axis=1)[:, None]
    width = 18 + 2 * np.sin(stations / 34) + 1.4 * np.cos(stations / 11)
    left = centers + normals * (width + rng.uniform(-1, 1, len(width)))[:, None]
    right = centers - normals * (width + rng.uniform(-1, 1, len(width)))[:, None]
    footprint = Polygon(np.vstack((left, right[::-1]))).buffer(0)
    x0, y0, x1, y1 = footprint.buffer(5).bounds
    x0, y0, x1, y1 = math.floor(x0), math.floor(y0), math.ceil(x1), math.ceil(y1)
    yy, xx = np.mgrid[y0:y1, x0:x1]
    # This north-south lane crosses each scanline once.
    axis = np.interp(yy, centers[:, 1], centers[:, 0])
    across = xx - axis
    half = np.interp(yy, centers[:, 1], width)
    grit = rng.normal(0, 1, xx.shape)
    noise = Image.fromarray(np.uint8(np.clip(128 + grit*30, 0, 255)))
    patch = (np.asarray(noise.filter(ImageFilter.GaussianBlur(2.2)), dtype=float) - 128) * .23
    ledge = half - np.abs(across) + 1.4 * patch
    joins_cobbles = np.clip((yy-centers[0,1]+1.5*patch)/17,0,1)
    alpha = np.uint8(np.clip((ledge + 1.4 * grit) / 3, 0, 1) * joins_cobbles * 255)
    alpha[(yy < centers[0, 1]) | (yy > centers[-1, 1])] = 0
    with Image.open(atlas) as img:
        # The third material in the European row is the local sand/earth texture.
        tw, th = img.width / 4, img.height / 5
        earth = np.asarray(img.crop((round(2*tw+5),round(2*th+5),round(3*tw-5),round(3*th-5)))
                           .resize((93,93),Image.Resampling.LANCZOS).convert("RGB"),dtype=float)
    texture = earth[yy % earth.shape[0], xx % earth.shape[1]]
    grain = texture.mean(axis=2) - earth.mean()
    wheel_distance = np.abs(np.abs(across + 0.9*np.sin(yy/18)) - 7.7)
    wheel = np.exp(-(wheel_distance / 1.8)**2) * np.clip(.65 + patch*.36, 0, 1)
    median = np.clip(1 - np.abs(across) / 5, 0, 1) * np.clip(patch + .3, 0, 1)
    value = grain*.85 + grit*3.0 + patch*3.1 - wheel*17
    rgb = np.array([193,158,109]) + value[:, :, None] + median[:, :, None]*[-8,0,-13]
    tile = Image.fromarray(np.dstack((np.uint8(np.clip(rgb,0,255)),alpha)))
    detail = ImageDraw.Draw(tile)
    for _ in range(135):
        x, y = rng.integers(0,tile.width), rng.integers(0,tile.height)
        if alpha[y,x] < 230 or abs(across[y,x]) < 3: continue
        tint = rng.choice(["#a48c64","#c6b08c","#dfc396","#ae9b72"])
        detail.line((x,y,x+int(rng.integers(1,3)),y),fill=tint,width=1)
    tile.save(destination, optimize=True)
    return footprint, (x0+tile.width/2, y1, tile.width, tile.height)
