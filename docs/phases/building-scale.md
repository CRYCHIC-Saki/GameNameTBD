# 建筑显示比例调整（2026-11-11）

用户指出地图空旷，允许不同建筑采用不同倍率，各建筑保持原图宽高比例。

验收：小店及民居有明显尺寸提升；不拉伸图像；门口底部中心不漂移；道路、地籍、碰撞、产权和存档不变；源工程实景检查及受影响回归通过。

root单人集成；基线 `artifacts/building-scale/baseline`。沿用godot-gdscript-patterns静态类型与只读图集规范（本地缓存work技能文档），grilling缺失，采用等价需求审核，GRILL_RESULT=NO_BLOCKING_PRODUCT_QUESTIONS。

主镇：老陈食材铺1.8倍，小屋1.55倍，餐厅/竞争店1.4倍，作坊1.25倍，银行/车站/地标1.35倍，其他独立店1.3倍；院落1.35倍，居民组1.25倍；市场摊位宽度从每档0.94调至1.12，约1.19倍。原阴影与图像共用调整后宽度。

四镇旅行：餐馆1.8倍，民居1.25倍，公共建筑1.4倍，港口建筑1.3倍。仅Sprite等比显示放大，原基座计算仍使用未放大的逻辑尺寸，保留通行与交互范围。图集PNG没有重采样或覆盖。

源代码：`src/town/town_art.gd`、`src/world/environment_art.gd`、`src/town/travel_world.gd`。实景工具 `tools/building_scale_probe.gd` 使用隔离档案；不操作真实存档。

验证：building-scale-town 48/48、building-scale-travel 11/11、导出前travel-core复验11/11；GPU82项/14图PASS，实景抽查主镇与四镇；导出636资源、3次启动各4项与实际EXE输入94项PASS。证据artifacts/building-scale、artifacts/check及artifacts/export。outputs/建筑比例调整版.zip与截图/说明已交付。人工审美确认PENDING，全量/远程CI未跑；不提交、不推送。
