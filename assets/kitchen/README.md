# Phase 1 像素厨房素材

2026-10-09 使用内置 `image_gen`（非 CLI/API fallback）生成，项目内持久化；不覆盖已有素材。像素场景原型，尚未进行人工美术/手感验收。

- `kitchen-background-v1.png`：实际厨房背景，1586×992；按1280×800场景显示，Nearest过滤。背景灶台在上方中部，中央空地可移动。碰撞区域依据实际图像柜边建立。
- `chef-v1.png`：实际透明全身厨师图，1086×1448 RGBA；角色脚点作为CharacterBody2D碰撞原点。行走目前用原图的脚步起伏/转向表现，不宣称四方向逐帧角色动画已完成。
- 默认生成目录：`C:/Users/Administrator/.codex/generated_images/01a11f4f-030d-75f3-85d4-614be2be4ee8/`；已复制到本目录，游戏不依赖该外部目录。

## 最终提示词

背景：Use case: stylized-concept. Asset type: Godot 2D pixel-art kitchen background for a playable top-down Chinese small-town diner. Create one 1600x1000 or similar 16:10 landscape bitmap. Orthographic top-down with slight front-facing cabinet sides, clearly readable deliberate pixel blocks, cozy warm wood and muted blue-green cabinets, daylight. Layout for actual collision-based gameplay: along the entire top wall a shallow counter strip occupying the top quarter, with exactly two clear adjacent wok stovetops near the middle, sink left and vegetable prep board right. Along the left wall a narrow shelf and along the right wall a narrow refrigerator/pantry, all flush to wall. The remaining central and lower two-thirds are completely open simple warm tiled floor where a character can walk, no islands or furniture blocking it. Room edges rectangular, no isometric skew. Detailed objects only in counter strip and side walls, sparse floor texture. No people, no UI, no labels, no letters, no logos, no watermark. Crisp coherent pixel art, no soft painterly rendering or depth-of-field blur. This is a usable level background, not an illustration of a screen.

角色：Use case: stylized-concept. Asset type: single transparent character sprite for a top-down 2D pixel-art Chinese small-town cooking game. One compact full-body chef, slightly viewed from above, facing down toward camera, standing neutral, centered. Friendly young adult chef in an ivory short-sleeve shirt, teal apron, dark trousers, small brown shoes, black hair in tidy short cut, simple white headband (no tall chef hat). Silhouette should be squat and readable like a 32x48 or 48x64 old console RPG character, clean deliberate pixel clusters, hard pixel edges, restrained warm cream/teal/brown palette, no smooth gradients. Small separated arms at sides, feet visible. Actual transparent background and tight subject framing, no floor, no shadow, no border, no UI, no words, no extra objects, only one complete character. Sprite body should fill most of the canvas; not an illustration or render.

## 2026-11-18 工位特写

正式厨房和菜谱研习共用 `cooking-closeups-v1.png`（锅、食材、工具和竹制蒸具十二格）及 `cooking-techniques-v1.png`（混合、烘烤、油炸、寿司和烙饼八格）。使用内置图像生成器生成透明 PNG。美术源图保留完整，游戏按逐格裁切的坐标绘制。背景取自本店所属菜系的厨房。制作效果、食材消耗和评分仍由实际谱面与会话提供。

两张图集的生成要求如下。

1. 四列三行独立透明像素素材，暖色左上光源、三分之二侧俯视。按行依次为黑铁木柄空炒锅、蘑菇与青豆炒菜、木柄金属锅铲、砖砌炭炉，带包子的竹蒸笼、独立穹顶笼盖、旧木案板、菜刀，空青花盘、倾斜调味壶、汤锅、烤串炭架。各格留裁切间距，不生成界面、文字和人物。
2. 四列两行同视角暖色十六位像素风，透明单件道具。首行是盛有蔬菜面糊的青瓷碗、木饭勺、烤面包的铸铁小烤炉、盛天妇罗的黄铜炸篓。次行是寿司竹帘、切开的海苔卷、烙有玉米饼的陶板、奶油碗。保持独立轮廓、金色高光和足够间距。

## 2026-11-26 新版厨房特写

中式特写直接取新版厨房房间的墙面和柜台。调味盘、实际倾倒中的调料和装盘图使用新版食材及菜品图集。原图集中缺少的空器具、欧式与日式墙面、切配和各阶段食物补绘成同一套暖色赛璐璐风格。空器具原图为 `closeup-cookware-v2.png`，区域背景为 `closeup-regions-v2.png`。`cooking-process.png` 与 `ingredient-cuts.png` 沿用各工序与切型的稳定格位。`tools/build_cooking_food.py` 读取当前菜品索引生成锅内使用的食物轮廓。
