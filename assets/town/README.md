# D033 中式小镇像素素材

2026-10-23；本任务使用内置 image_gen 新生成。未从第三方素材站下载；仍是开发迭代美术，未代表整套最终美术验收。

| 文件 | 用途与布局 | 生成记录 |
|---|---|---|
| title-town-v1.png | 主菜单背景，中式食堂清晨，左侧留出菜单区域；不含 baked-in 按钮 | exec-4f9782a3-7935-418b-8932-0d0e44bdaa6a |
| town-sprites-v1.png | 透明 2×2 图集：食堂、民居、蔬菜摊、树木 | exec-faf54660-5bb5-4d43-bc02-f3eb8a9b44e2 |
| diner-furniture-v1.png | 透明 2×2 图集：餐桌凳、账台、装修桌、榻；2:1斜角 | exec-ec1ca25d-e8f3-4f79-9861-5465d9e52466 |

共同提示规格：Chinese cozy small town diner, warm wood, cream bowls, vermilion accents, crisp chunky pixel art, orthographic game sprites, no typography. 家具与街区图集要求四格等分、透明底、独立完整轮廓；标题图要求宽屏街景和左侧安静留白。

原始生成文件保留于本机 `.codex/generated_images/01a11e94-e1d7-7c40-8dde-4cfdbe246fc8/`，工程使用本目录副本。没有用脚本重绘、抠图或修改原始位图。图集切片由 Godot `AtlasTexture` / `draw_texture_rect_region` 完成；小镇与餐厅使用 nearest 采样。旧厨房与厨师素材继续使用 `assets/kitchen/` 的已有来源记录。

导出仅白名单包含三个 PNG 及其导入资源；本来源文档、测试画面和原始设计资料不进入运行包。
