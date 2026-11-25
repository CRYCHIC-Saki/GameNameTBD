# D033 中式小镇像素素材

### 江南街区 D080-R12

本轮新制三张游戏图集。jiangnan-landmarks-v1.png 用于南埠客栈、马厩、石牌坊、钱庄、六角亭、榕树、说书人、院墙、竹丛和钓台。jiangnan-traders-v1.png 收录 20 个独立店面和摊位部件；jiangnan-district-grounds-v2.png 提供 6 种有物理比例的近地材质。取景约定、八区位置、入口和扩建地交接见 [江南小镇街区地图](../../docs/phases/jiangnan-district-plan.md)。菜筐内的三种蔬菜来自 [ScratchIO 的 CC0 图集](jiangnan-produce-cc0.source.md)。设计全景只随开发资料留存，导出检查核对素材清单。

### 江南街景 D080-R11

江南道路从自有 `district-surfaces-v1.png` 的江南石巷取图，草坪沿用 `map-surfaces-v2.png`。广场专用地面 `jiangnan-court-v1.png` 以 400×280 绘制缓存（世界尺寸 800×560）。`jiangnan-square-v1.png` 包含树、棋桌、摊贩、浅塘、观众和街灯等 12 个透明对象。住宅、挂件及西岸陈设分别使用 `jiangnan-frontage-v1.png`、`jiangnan-eaves-v1.png`、`jiangnan-riverbank-v1.png`。五张新图来自本次生成、裁切与像素尺度整理。

参考作品按用途记录。作者的 16×16 楼桑村样本可用于研究屋面尺度；森林套件的草土/草水提供直边、外角与内角组合；32 像素村镇套件提供广场与街路铺面的区分。本项目使用自己的图集。用户提到的 Village Grass / Dirt 缺少唯一作者或原页，未据其名称登记授权。[楼桑村样本](https://bbbits.itch.io/pixel-art-three-kingdoms-lousang-village-tileset/devlog/1551579/free-sample-three-kingdoms-lousang-village-tileset) · [どんぐりラボ・森](https://booth.pm/ja/items/9114130) · [Pixel Village & Town](https://booth.pm/ja/items/9176912)

2026-10-30 D051新增town-sprites-v3.png、residential-houses-v2.png、ground-materials-v4.png，以及两名角色目录的独立walk-four-directions-v1.png。内置image_gen；五张素材完整prompt和参考来源见visual-unity-v3-generation.json。原图只读，运行时裁取缓存；镇图/民居生成间隔不严格等分，使用实测分区防邻图串入。NPC近透明Alpha杂点不参与帧边界计算，无磁盘像素重绘。人工视觉/步态验收待试玩。

2026-10-30 D050新增`residential-houses-v1.png`：1254×1254透明四象限，单户/连排民居/三屋封闭小院/双屋花园院落。内置image_gen生成，完整prompt及来源见同目录`residential-houses-v1-generation.json`。原素材未修改；运行时AtlasTexture只裁各象限透明边，图集缓存只读。它是住宅外观，不代表四个新增经济家庭。美术最终观感待用户试玩。

2026-10-23；本任务使用内置 image_gen 新生成。未从第三方素材站下载；仍是开发迭代美术，未代表整套最终美术验收。

| 文件 | 用途与布局 | 生成记录 |
|---|---|---|
| title-town-v1.png | 主菜单背景，中式食堂清晨，左侧留出菜单区域；不含 baked-in 按钮 | exec-4f9782a3-7935-418b-8932-0d0e44bdaa6a |
| town-sprites-v1.png | 透明 2×2 图集：食堂、民居、蔬菜摊、树木 | exec-faf54660-5bb5-4d43-bc02-f3eb8a9b44e2 |
| diner-furniture-v1.png | 透明 2×2 图集：餐桌凳、账台、装修桌、榻；2:1斜角 | exec-ec1ca25d-e8f3-4f79-9861-5465d9e52466 |

共同提示规格：Chinese cozy small town diner, warm wood, cream bowls, vermilion accents, crisp chunky pixel art, orthographic game sprites, no typography. 家具与街区图集要求四格等分、透明底、独立完整轮廓；标题图要求宽屏街景和左侧安静留白。

原始生成文件保留于本机 `.codex/generated_images/01a11e94-e1d7-7c40-8dde-4cfdbe246fc8/`，工程使用本目录副本。没有用脚本重绘、抠图或修改原始位图。图集切片由 Godot `AtlasTexture` / `draw_texture_rect_region` 完成；小镇与餐厅使用 nearest 采样。旧厨房与厨师素材继续使用 `assets/kitchen/` 的已有来源记录。

导出仅白名单包含三个 PNG 及其导入资源；本来源文档、测试画面和原始设计资料不进入运行包。
# 江南可编辑地图素材

正式场景 `src/town/jiangnan_map.tscn` 使用 `jiangnan-map-tiles-v2.png` 和 `jiangnan-map-props-v2.png`，地块配置为 `src/town/jiangnan_map_tileset.tres`。R16 新稿采用暖灰错缝青石、完整横跨的双端石拱桥、无底色的三色野花与岸边灌木，以及摊棚、推车和茶桌。整件透明轮廓按连通区域打包，以保留越过图集格线的轮、凳及叶梢。局部摆放在 `content/towns/jiangnan_scene_polish.json`，碰撞和经营选址使用同一套放置尺寸。

# 江南参考全景分层素材（R14 历史记录）

`jiangnan-reference-land.png` 和 `jiangnan-reference-water.png` 使用同一 1670×941 画幅。`jiangnan-reference-buildings.png`、`jiangnan-reference-structures.png` 和 `jiangnan-reference-foliage.png` 分别收录立面、桥梁与摊位、前景植被。素材来自用户确认的全景，路上原有的绘制行人经过局部补画，角色由游戏运行时绘制。地编可在 `content/towns/jiangnan_reference_buildings.json` 和 `jiangnan_reference_foliage.json` 复核每项素材的源坐标、落脚点和轮廓，重新打包的入口见 `tools/pack_jiangnan_reference.py`。
