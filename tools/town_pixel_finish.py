"""Finish the current town atlases without changing alpha, tile layout, or sprite bounds."""
import argparse
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent
LUMA = np.array((.28, .57, .15), np.float32)
HUE_INK = np.array((.055, .050, .067), np.float32)
WARM_LIGHT = np.array((.026, .006, -.027), np.float32)
COOL_SHADOW = np.array((-.016, -.006, .030), np.float32)

# Tonal corrections on continuous surfaces are pointwise to preserve tile seams.
SURFACES = {
    "egret-cart-track": .15, "egret-cobbles": .21, "egret-granite": .24,
    "egret-grass": .12, "egret-quay": .20, "egret-sea": .17,
    "jiangnan-map-frontages-v1": .17, "jiangnan-map-paving-v1": .20,
    "jiangnan-map-tiles-v3": .17, "shiomi-detail-tiles": .14,
    "shiomi-ground-v1": .18, "shiomi-verges-v1": .13, "world-atlas-v1": .16,
}
SPRITES = {
    "egret-bollard": 1.0, "egret-passenger-station": 2.4,
    "egret-sprites": 3.0, "egret-wharf": 1.6,
    "jiangnan-map-arches-v1": 1.7, "jiangnan-map-props-v2": 2.0,
    "restaurant-chinese-v1": 4.0, "restaurant-european-v1": 4.0,
    "restaurant-japanese-v1": 4.0, "shiomi-sprites-v1": 3.0,
    "shiomi-water-tub": 1.0,
}
REGION_FINISH = {
    "egret-sprites": ("egret", {"mosaic", "pier"}, {"flowers", "wheat", "daisies", "laundry"}),
    "shiomi-sprites-v1": ("shiomi", {"fall", "shore", "zen", "meadow", "ledge", "reef"},
                         {"bamboo", "hydrangea", "dwarf", "pigeons"}),
}


def luminance(rgb):
    return cv2.transform(rgb, LUMA.reshape(1, 3))


def tone(rgb, contrast, saturation, steps, snap):
    luma = luminance(rgb)
    # Bright faces keep their hue while midtone shadows pull away from them.
    bend = (luma - .47) * (4.0 * luma * (1.0 - luma)) * contrast
    value = np.clip(luma + bend, 0.0, 1.0)
    value += (np.round(value * steps) / steps - value) * snap
    return value[..., None] + (rgb - luma[..., None]) * saturation


def neighborhood_light(luma, coverage, radius):
    weighted_value = cv2.GaussianBlur(coverage * luma, (0, 0), radius)
    weight = cv2.GaussianBlur(coverage, (0, 0), radius)
    return weighted_value / np.maximum(weight, .001)

def finish_sprite(rgb, alpha, width):
    shape = (alpha >= 128).astype(np.uint8)
    padded_shape = np.pad(shape, 1)
    inset = cv2.distanceTransform(padded_shape, cv2.DIST_L2, cv2.DIST_MASK_PRECISE)[1:-1, 1:-1]

    normalized = rgb.astype(np.float32) / 255.0
    filtered = cv2.bilateralFilter(rgb, 5, 19.0, 2.0).astype(np.float32) / 255.0
    pigment = cv2.addWeighted(normalized, .65, filtered, .35, 0.0)
    paint = tone(pigment, .37, 1.09, 18, .80)

    coverage = alpha.astype(np.float32) / 255.0
    luma = luminance(pigment)
    nearby = neighborhood_light(luma, coverage, 2.0)
    broader = neighborhood_light(luma, coverage, 6.5)
    # Split neighboring material planes without strengthening isolated speckles.
    planes = nearby - broader
    planes = np.sign(planes) * np.maximum(np.abs(planes) - .017, 0.0)
    seams = np.clip((luma - nearby) * .42, -.044, .034)
    relief = np.clip(planes * 1.48, -.083, .077) + seams
    relief = np.where(relief > 0, relief * np.clip((1.0 - luma) * 4.1, .18, 1.0), relief)
    interior = np.clip((inset - 1.4) / max(width, 1.5), 0.0, 1.0)

    shades = np.clip((.58 - luma) * 3.1, 0.0, 1.0) * np.clip(luma * 5.0, 0.0, 1.0)
    lights = np.clip((luma - .55) * 3.0, 0.0, 1.0) * np.clip((1.0 - luma) * 5.0, 0.0, 1.0)
    accents = relief[..., None] + lights[..., None] * WARM_LIGHT + shades[..., None] * COOL_SHADOW
    paint += accents * interior[..., None]

    # A twig or rope has little solid area behind its edge, so use less ink there.
    reach = max(4, int(np.ceil(width * 2.0)))
    deepest = cv2.dilate(inset, np.ones((reach * 2 + 1, reach * 2 + 1), np.uint8))
    support = np.clip((deepest - 1.0) / max(2.0, width), 0.0, 1.0)
    edge_width = max(1.0, width * .83)
    contour = np.clip((edge_width + 1.0 - inset) / edge_width, 0.0, 1.0)
    contour *= (.24 + .46 * support) * (1.0 - .22 * np.clip((luma - .68) / .26, 0.0, 1.0))
    adjacent = cv2.dilate(shape, np.ones((3, 3), np.uint8))
    contour *= np.where(shape != 0, 1.0, adjacent * .48)
    ink = np.minimum(paint, normalized * .25 + HUE_INK)
    return paint + (ink - paint) * contour[..., None]


def finish(source, name):
    pixels = np.array(Image.open(source).convert("RGBA"))
    rgb = np.ascontiguousarray(pixels[:, :, :3])
    alpha = pixels[:, :, 3]
    if name in SURFACES:
        paint = tone(rgb.astype(np.float32) / 255.0, SURFACES[name], 1.04, 29, .28)
    else:
        width = SPRITES[name]
        paint = finish_sprite(rgb, alpha, width)
        if name in REGION_FINISH:
            town, surfaces, fine = REGION_FINISH[name]
            region_path = ROOT / "map_art" / f"{town}-regions.json"
            regions = json.loads(region_path.read_text(encoding="utf-8"))
            for region_name in sorted(surfaces | fine):
                x, y, w, h = regions[region_name]
                area = np.s_[y:y+h, x:x+w]
                tile = rgb[area]
                if region_name in surfaces:
                    paint[area] = tone(tile.astype(np.float32) / 255.0, .18, 1.04, 29, .28)
                else:
                    paint[area] = finish_sprite(np.ascontiguousarray(tile), alpha[area], 1.0)

    changed_rgb = np.round(np.clip(paint, 0.0, 1.0) * 255.0).astype(np.uint8)
    pixels[alpha > 0, :3] = changed_rgb[alpha > 0]
    return Image.fromarray(pixels)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path, help="Unfinished atlas directory")
    parser.add_argument("--output", required=True, type=Path, help="Finished atlas directory")
    args = parser.parse_args()
    if args.source.resolve() == args.output.resolve():
        parser.error("source and output must be different directories")
    args.output.mkdir(parents=True, exist_ok=True)
    for name in sorted(SURFACES.keys() | SPRITES.keys()):
        filename = name + ".png"
        finish(args.source / filename, name).save(args.output / filename, optimize=True)


if __name__ == "__main__":
    main()
