"""Pack a registered Jiangnan panorama into painted ground and ordered sprites.

Run from the repo with Pillow installed and the approved 1670×941 PNG:
    python tools/pack_jiangnan_reference.py path/to/reference.png
An ImageGen clean plate can supply patches via --clean-plate when pixel aligned.
"""

import argparse
import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter


SIZE = (1670, 941)
LAYERS = ("buildings", "structures", "foliage")
GUTTER = 2
ATLAS_WIDTH = 1024
# Original actors are removed before packing. Receivers use nearby paint of
# the same material. Rectangles enclose their shadows as well as silhouettes.
ACTORS = (
    ((214, 202, 234, 228), (12, 27)), ((332, 291, 351, 321), (17, 13)),
    ((385, 252, 405, 281), (22, 8)), ((607, 253, 628, 283), (24, 0)),
    ((553, 349, 578, 376), (3, 27)), ((147, 426, 173, 457), (-3, 33)),
    ((339, 446, 363, 476), (-16, 25)), ((342, 488, 365, 520), (24, 3)),
    ((486, 505, 511, 532), (-23, 3)), ((244, 629, 267, 657), (-6, 27)),
    ((600, 617, 618, 645), (-26, 6)), ((792, 507, 813, 538), (-22, -10)),
    ((302, 714, 323, 744), (24, 8)), ((427, 718, 452, 750), (-30, 4)),
    ((465, 705, 487, 737), (-18, -1)), ((609, 702, 630, 734), (-10, 8)),
    ((687, 719, 711, 753), (25, 1)), ((1218, 237, 1237, 267), (0, 32)),
    ((1213, 356, 1234, 387), (2, -33)), ((1354, 425, 1374, 451), (0, 31)),
    ((974, 558, 990, 581), (29, 3)), ((1066, 546, 1087, 575), (24, -1)),
    ((1116, 556, 1138, 584), (22, 2)), ((1254, 606, 1274, 634), (-31, -1)),
    ((1297, 595, 1318, 623), (27, 7)), ((1411, 586, 1430, 614), (18, 12)),
    ((1462, 557, 1483, 586), (19, 0)), ((1503, 588, 1525, 616), (-19, 1)),
)
# These masks partition the visible raster for separate land and water draws.
# Shore stones, fringe plants, and tide foam keep their original painted edges;
# collision and property checks use the separately surveyed world geography.
WATER = (
    [(1053, 0), (1117, 0), (1134, 119), (1070, 196), (1045, 273), (1040, 323),
     (1008, 356), (1060, 390), (1090, 425), (1177, 455), (1192, 526),
     (1173, 549), (1121, 624), (1230, 682), (1520, 649), (1670, 599),
     (1670, 941), (450, 941), (555, 915), (707, 876), (888, 812),
     (1023, 771), (1060, 737), (991, 708), (950, 720), (894, 738),
     (810, 792), (692, 784), (494, 791), (230, 816), (128, 813),
     (0, 817), (0, 788), (107, 775), (253, 782), (437, 796), (684, 766),
     (764, 752), (847, 715), (912, 666), (920, 623), (871, 606),
     (879, 578), (917, 530), (962, 481), (982, 437), (961, 375),
     (967, 326), (925, 289), (888, 267), (923, 234), (946, 213),
     (974, 152), (1040, 67)],
    [(0, 528), (68, 516), (102, 546), (60, 566), (27, 599), (0, 624)],
)


def clear_actors(original, clean_plate):
    result = original.copy()
    for rect, shift in ACTORS:
        left, top, right, bottom = rect
        dx, dy = shift
        # Feather outside the original silhouette so its shadow never survives.
        padding = 6
        padded = (left - padding, top - padding, right + padding, bottom + padding)
        x1, y1, x2, y2 = padded
        size = (x2 - x1, y2 - y1)
        patch = original.crop((x1 + dx, y1 + dy, x2 + dx, y2 + dy))
        if clean_plate is not None:
            # An edit is safe to transplant only if its perimeter still aligns.
            candidate = clean_plate.crop(padded)
            edge = ImageChops.difference(original.crop(padded), candidate)
            perimeter = [edge.getpixel((x, y)) for x in range(size[0]) for y in range(size[1])
                         if x == 0 or y == 0 or x == size[0] - 1 or y == size[1] - 1]
            if sum(sum(pixel[:3]) for pixel in perimeter) / (len(perimeter) * 3) < 28:
                patch = candidate
        alpha = Image.new("L", size)
        ImageDraw.Draw(alpha).rectangle((3, 3, size[0] - 4, size[1] - 4), fill=255)
        result.paste(patch, (x1, y1), alpha.filter(ImageFilter.GaussianBlur(1.3)))
    return result


def mask_for(part):
    mask = Image.new("L", SIZE)
    ImageDraw.Draw(mask).polygon([tuple(point) for point in part["outline"]], fill=255)
    return mask


def pack_atlas(parts, textures):
    x = y = row_height = GUTTER
    for part in parts:
        world, sprite = textures[part["id"]]
        if x + sprite.width + GUTTER > ATLAS_WIDTH:
            x, y, row_height = GUTTER, y + row_height + GUTTER, 0
        part["atlas"] = [x, y, *sprite.size]
        part["rect"] = [world[0], world[1], *sprite.size]
        x += sprite.width + GUTTER
        row_height = max(row_height, sprite.height)
    atlas = Image.new("RGBA", (ATLAS_WIDTH, y + row_height + GUTTER))
    for part in parts:
        atlas.paste(textures[part["id"]][1], tuple(part["atlas"][:2]))
    return atlas


def pack(root, original, clean_plate):
    content = root / "content/towns"
    assets = root / "assets/town"
    entries = []
    for name in ("buildings", "foliage"):
        entries.extend(json.loads((content / f"jiangnan_reference_{name}.json").read_text(encoding="utf-8-sig")))
    assert len({part["id"] for part in entries}) == len(entries)
    assert all(part["layer"] in LAYERS for part in entries)
    image = clear_actors(original, clean_plate)
    textures = {}
    occupied = Image.new("L", SIZE)
    # Give each original sample to the nearest overlapping foreground sprite.
    # The final composite is identical regardless of atlas order or padding.
    for part in sorted(entries, key=lambda item: (item["foot"][1], item["id"]), reverse=True):
        outline = mask_for(part)
        mask = ImageChops.subtract(outline, occupied)
        bounds = mask.getbbox()
        if bounds is None:
            continue
        occupied = ImageChops.lighter(occupied, outline)
        sprite = image.crop(bounds)
        sprite.putalpha(mask.crop(bounds))
        textures[part["id"]] = bounds, sprite

    water = Image.new("L", SIZE)
    for outline in WATER:
        ImageDraw.Draw(water).polygon(outline, fill=255)
    land = ImageChops.invert(water)
    ground = ImageChops.invert(occupied)
    for name, mask in (("land", land), ("water", water)):
        plane = Image.new("RGBA", SIZE)
        plane.paste(image, (0, 0), ImageChops.multiply(mask, ground))
        plane.save(assets / f"jiangnan-reference-{name}.png", optimize=True)
    for layer in LAYERS:
        parts = [part for part in entries if part["layer"] == layer and part["id"] in textures]
        pack_atlas(parts, textures).save(assets / f"jiangnan-reference-{layer}.png", optimize=True)

    runtime = [dict(part) for part in entries if part["id"] in textures]
    for part in runtime:
        del part["outline"]
    (content / "jiangnan_reference_visuals.json").write_text(
        json.dumps({"size": SIZE, "parts": runtime}, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")

    composite = Image.new("RGBA", SIZE)
    for name in ("land", "water"):
        composite.alpha_composite(Image.open(assets / f"jiangnan-reference-{name}.png"))
    atlases = {name: Image.open(assets / f"jiangnan-reference-{name}.png") for name in LAYERS}
    for part in runtime:
        x, y, w, h = part["atlas"]
        composite.alpha_composite(atlases[part["layer"]].crop((x, y, x + w, y + h)), tuple(part["rect"][:2]))
    assert ImageChops.difference(composite.convert("RGB"), image.convert("RGB")).getbbox() is None
    assert composite.getchannel("A").getextrema() == (255, 255)
    changed = ImageChops.difference(composite.convert("RGB"), original.convert("RGB"))
    count = sum(pixel != (0, 0, 0) for pixel in changed.get_flattened_data())
    print(f"{len(runtime)} independent sprites; {count}/{SIZE[0]*SIZE[1]} reference pixels changed for actors")
    return composite


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reference", type=Path)
    parser.add_argument("--clean-plate", type=Path)
    parser.add_argument("--preview", type=Path)
    args = parser.parse_args()
    source = Image.open(args.reference).convert("RGBA")
    if source.size != SIZE:
        parser.error(f"expected {SIZE}, got {source.size}")
    plate = Image.open(args.clean_plate).convert("RGBA") if args.clean_plate else None
    if plate is not None and plate.size != SIZE:
        plate = plate.resize(SIZE, Image.Resampling.LANCZOS)
    preview = pack(Path(__file__).resolve().parents[1], source, plate)
    if args.preview:
        preview.save(args.preview)


if __name__ == "__main__":
    main()
