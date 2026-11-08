# Four cultures atlas — AI-070

Created 2026-11-08 using built-in image_gen (not CLI). User authorized four locally inspired pixel towns; these are fictional neighborhoods, not literal reconstructions of real cities.

- `four-cultures-v1.png`: 1536×1024, transparent, 4×4 building atlas; rows Japan, France, Thailand, Mexico; columns food shop, residence, public landmark, port. Original generated file exec-27515583-553b-440d-9888-7ac7c19b6e79.png retained outside project.
- `four-cultures-props-v1.png`: 1536×1024, 4×2, tree/prop cells ordered Japan, France, Thailand, Mexico. First generation had opaque white background; image_gen edit removed background. Original exec-b5935455-10bd-4105-ab02-b87be4ea584a.png; final exec-09240b24-ad73-473e-8c44-a9790cb3651e.png. Final corner alpha verified zero; GPU appearance checked separately.
- SHA256 buildings: 5834d220f5c094f8348eef173bfaf3b392ff2342e5a5e60521f68644af38bf02.
- SHA256 props: b009fea80d5fc67e6b4d1a3a04c0750d520cc8da944b20162db33756e88f3e14.

Building prompt specification: production game sprite atlas for cute 2D pixel art cooking town; orthographic front elevations with slightly visible roofs, no isometric diagonal walls or vanishing points; exactly 4 rows ×4 columns, equal cells, transparent padding, no ground squares/text/people. Japan: machiya restaurant navy noren, tiled residence, vermilion shrine, harbor booth/boat. France: limestone bistro red awning/mansard, shuttered townhouses, civic clocktower, river quay/launch. Thailand: teal canal food house, stilt house, orange/gold temple, floating stall/longtail. Mexico: ochre cantina, colorful courtyard homes, mission belltower, terracotta ferry booth. Consistent warm pixel palette, full isolated silhouettes.

Props prompt specification: 4×2 transparent atlas, 384×512 cells, no ground/text/people; top cherry blossom tree, plane tree, coconut palm, cactus/agave; bottom stone lantern/pots, lamp/bench/flowers, baskets/bananas/tropical pots, colorful umbrella/bougainvillea. Final edit prompt: remove all white background and grid lines, true alpha zero outside silhouettes and leaf gaps; preserve all eight objects, colors, positions and 1536×1024 layout. No other edits.

Runtime uses read-only AtlasTexture regions; no edits to earlier town/character originals.
