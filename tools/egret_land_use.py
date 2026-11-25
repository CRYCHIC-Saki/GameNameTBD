"""Sample cadastral attributes in the same pixel coordinates as the European town."""
from collections import deque

import numpy as np
from PIL import Image, ImageDraw


VENUE_USES = {"bank":"b", "landmark":"l", "supply_factory":"f", "hotel":"i", "market":"m",
              "urban_village":"u", "competitor":"c", "rich_district":"v", "plaza":"p", "harbor":"h"}


def survey_districts(cells, uses, plots, market_floor, placed, cell, offset_y):
    # Inland boundaries follow the forge lane, church gardens, shopping street
    # and mill lane. The waterfront forecourt is in native harbour coordinates.
    districts = Image.new("L", uses.size, ord("C"))
    pen = ImageDraw.Draw(districts)
    outlines = {
        "N": [(-400,-100),(1150,-100),(1130,137),(1064,210),(925,232),
              (728,245),(650,205),(540,228),(397,214),(214,158),
              (106,199),(124,285),(90,331),(-28,343),(-400,300)],
        "F": [(-400,550),(153,535),(291,509),(465,508),(597,558),
              (650,576),(624,684),(624,729),(652,767),(690,826),
              (746,1040),(-400,1040)],
        "G": [(1150,-100),(1850,-100),(1850,1040),(746,1040),(690,826),
              (811,745),(977,730),(1120,711),(1190,663),(1248,600),
              (1194,503),(1141,431),(1126,393),(1147,332),(1112,282),
              (1064,210),(1130,137)],
        "S": [(1130,413),(1217,385),(1340,387),(1460,372),(1608,350),
              (1715,339),(1800,355),(1800,476),(1607,512),(1466,546),
              (1280,565),(1170,546),(1115,493)],
        "I": [(650,582),(787,560),(924,525),(1084,526),(1206,571),
              (1248,600),(1202,659),(1120,711),(977,730),(811,745),
              (690,826),(652,767),(624,729),(624,684)],
    }
    for code, points in outlines.items():
        pen.polygon([placed(x,y) for x,y in points], fill=ord(code))
    pen.polygon([(0,390),(336,391),(392,414),(436,447),(510,454),(562,477),
                 (576,526),(548,575),(500,609),(433,626),(350,644),(0,632)],
                fill=ord("Q"))
    market = Image.new("1", uses.size)
    ImageDraw.Draw(market).polygon(list(market_floor.exterior.coords), fill=1)
    # Unpaved margins inside a registered building lot belong to that venue.
    # Keep any public paving that also crosses its coarse cadastral rectangle.
    yards = {(cx,cy):VENUE_USES[kind] for _,kind,_,x,y,w,h,_,_ in plots
             for cy in range(y,y+h) for cx in range(x,x+w)}
    district_rows, use_rows = [], []
    for y, surfaces in enumerate(cells):
        ds, us = [], []
        for x, surface in enumerate(surfaces):
            point = (x*cell+cell//2, (y-offset_y)*cell+cell//2)
            if surface == "_":
                district, use = "_", "_"
            elif surface == "~":
                district, use = "Q", "~"
            else:
                district = chr(districts.getpixel(point))
                use = chr(uses.getpixel(point))
                if use == "." and surface == ".":
                    use = yards.get((x,y), ".")
                if surface in "qd" or use == "h":
                    district = "Q"
                elif use == "v":
                    district = "G"
                elif surface == "g" or (surface == "r" and market.getpixel(point)):
                    district = "C"
                elif surface == "w":
                    district = "F"
                if use == ".":
                    use = {"q":"h","d":"h","g":"p","w":"w","r":"r","t":"r"}.get(surface,".")
                    if surface == "r" and market.getpixel(point):
                        use = "m"
            ds.append(district)
            us.append(use)
        district_rows.append("".join(ds))
        use_rows.append("".join(us))
    return district_rows, use_rows


def measure_routes(walk, plots, house_doors, arrival, cell, offset_y):
    # Five samples per tile put one node exactly at each surveyed tile centre.
    # Test every intervening pixel so paths cannot jump fences or narrow water.
    steps = 5
    height, width = walk.shape
    xs = (np.arange(width//cell*steps)*cell+cell//2)//steps
    ys = (np.arange(height//cell*steps)*cell+cell//2)//steps
    gx, gy = len(xs), len(ys)
    next_x, next_y = np.roll(xs,-1), np.roll(ys,-1)
    right = walk[np.ix_(ys,xs)].copy()
    down = right.copy()
    for offset in range(1, (cell+steps-1)//steps+1):
        right &= walk[np.ix_(ys, np.minimum(xs+offset, next_x))]
        down &= walk[np.ix_(np.minimum(ys+offset, next_y), xs)]
    right[:,-1] = False
    down[-1,:] = False
    # Padding the four edge tables lets the search share a flat index at the rim.
    left = np.roll(right, 1, axis=1)
    up = np.roll(down, 1, axis=0)
    edges = [(1,right.ravel()),(-1,left.ravel()),(gx,down.ravel()),(-gx,up.ravel())]

    def tile_node(x, y):
        return ((y-offset_y)*steps+steps//2)*gx+x*steps+steps//2

    starts = {"residential":[], "market":[], "station":[tile_node(*arrival)]}
    for _, kind, _, _, _, _, _, x, y in plots:
        if kind in ("urban_village","rich_district"):
            starts["residential"].append(tile_node(x,y))
        elif kind == "market":
            starts["market"].append(tile_node(x,y))
    for px, py in house_doors:
        if not (0 <= px < width and 0 <= py < height):
            continue
        # Use the nearest passable sample in front of the foundation.
        candidates = [(int((xs[x]-px)**2+(ys[y]-py)**2), y*gx+x)
                      for y in np.flatnonzero((ys>=py)&(ys<=py+cell))
                      for x in np.flatnonzero(abs(xs-px)<=cell) if walk[ys[y],xs[x]]]
        if candidates:
            starts["residential"].append(min(candidates)[1])

    routes = {}
    for origin, sources in starts.items():
        distance = [-1]*(gx*gy)
        queue = deque(sources)
        for source in sources:
            distance[source] = 0
        while queue:
            node = queue.popleft()
            for delta, open_edge in edges:
                if open_edge[node] and distance[node+delta] == -1:
                    distance[node+delta] = distance[node]+1
                    queue.append(node+delta)
        grid = np.array(distance).reshape(gy,gx)
        routes[origin] = grid[steps//2::steps, steps//2::steps].tolist()
    return routes
