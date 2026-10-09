# Phase 1 像素厨房素材

2026-10-09 使用内置 `image_gen`（非 CLI/API fallback）生成，项目内持久化；不覆盖已有素材。像素场景原型，尚未进行人工美术/手感验收。

- `kitchen-background-v1.png`：实际厨房背景，1586×992；按1280×800场景显示，Nearest过滤。背景灶台在上方中部，中央空地可移动。碰撞区域依据实际图像柜边建立。
- `chef-v1.png`：实际透明全身厨师图，1086×1448 RGBA；角色脚点作为CharacterBody2D碰撞原点。行走目前用原图的脚步起伏/转向表现，不宣称四方向逐帧角色动画已完成。
- 默认生成目录：`C:/Users/Administrator/.codex/generated_images/01a11f4f-030d-75f3-85d4-614be2be4ee8/`；已复制到本目录，游戏不依赖该外部目录。

## 最终提示词

背景：Use case: stylized-concept. Asset type: Godot 2D pixel-art kitchen background for a playable top-down Chinese small-town diner. Create one 1600x1000 or similar 16:10 landscape bitmap. Orthographic top-down with slight front-facing cabinet sides, clearly readable deliberate pixel blocks, cozy warm wood and muted blue-green cabinets, daylight. Layout for actual collision-based gameplay: along the entire top wall a shallow counter strip occupying the top quarter, with exactly two clear adjacent wok stovetops near the middle, sink left and vegetable prep board right. Along the left wall a narrow shelf and along the right wall a narrow refrigerator/pantry, all flush to wall. The remaining central and lower two-thirds are completely open simple warm tiled floor where a character can walk, no islands or furniture blocking it. Room edges rectangular, no isometric skew. Detailed objects only in counter strip and side walls, sparse floor texture. No people, no UI, no labels, no letters, no logos, no watermark. Crisp coherent pixel art, no soft painterly rendering or depth-of-field blur. This is a usable level background, not an illustration of a screen.

角色：Use case: stylized-concept. Asset type: single transparent character sprite for a top-down 2D pixel-art Chinese small-town cooking game. One compact full-body chef, slightly viewed from above, facing down toward camera, standing neutral, centered. Friendly young adult chef in an ivory short-sleeve shirt, teal apron, dark trousers, small brown shoes, black hair in tidy short cut, simple white headband (no tall chef hat). Silhouette should be squat and readable like a 32x48 or 48x64 old console RPG character, clean deliberate pixel clusters, hard pixel edges, restrained warm cream/teal/brown palette, no smooth gradients. Small separated arms at sides, feet visible. Actual transparent background and tight subject framing, no floor, no shadow, no border, no UI, no words, no extra objects, only one complete character. Sprite body should fill most of the canvas; not an illustration or render.
