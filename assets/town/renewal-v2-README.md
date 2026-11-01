# D048 环境美术

新增版本，不覆盖旧图或人物原稿。三张PNG由内置 image_gen 工具生成，按指定主角作风格参考；工具未暴露模型版本，不虚构模型型号。来源输出文件、生产描述、尺寸和SHA256见 renewal-v2-manifest.json。

- town-sprites-v2.png：中式街区建筑/植物图集；生成结果并非等宽网格，TDEnvironmentArt使用逐物件矩形取图，不改原图像。
- diner-props-v2.png：餐厅/厨房功能家具；复用真实装修摆放与工位位置。
- ../kitchen/kitchen-background-v2.png：空厨房背景；工位独立绘制，侧墙碰撞按地板边界更新。

场景截图与核查日志在 artifacts/town-renewal/visual。像素画面、布局疏密和昼夜明暗仍需人工体验；不是最终美术定稿。地形底图用代码一次生成并缓存，未为每地块创建节点。文档/生成清单不进入发布资源包。
