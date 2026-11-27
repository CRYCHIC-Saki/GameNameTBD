# main 新美术迁移（2026-11-26）

基线：远端 main `cedc4cc`。来源：GitHub Desktop 本地暂存 `ff890d4`（完整保留）。本地分支 `integration/main-new-art-20261126`，未提交/未推送。

## 范围与验收

用户授权在本地迁移 11/23 新美术。保留 main 的三镇地图、地籍、通行、角色、音频、玩法、113 个食材与 60 道菜品。图标必须按稳定 ID 对应原图格；新剧情背景、CG 和半身构图必须由原生 VN 播放并进入导出包；不得恢复旧转场。

GRILL_SKILL = NOT_AVAILABLE。依项目协议进行等价需求审查，GRILL_RESULT = NO_BLOCKING_PRODUCT_QUESTIONS。已使用 ../work/godot-gdscript-patterns-SKILL.md。

## 迁移方式

- 迁移 31 张记录中的 27 张当前版本适用图片：主页面、木牌/羊皮纸、家具、食材/菜品、通用地图对象和三地域餐厅。另 4 张为已停用地域/菜品页，仍保存在原暂存，没有重新加入当前发行范围。
- 迁移 10 张剧情背景/CG、资源登记、正式章节、半身构图和必要 VN 宿主/编辑器接入。
- 保留 main 的食材筛选和 ingredient_slots；增加 dish_slots 明确绑定原始美术格，保留当前 60 个菜品 ID。
- 保留 main 的剧情导航新地图路线，三方合入 VN 接入；旧转场显示器只保留兼容 API。
- 导出保留三镇新资源规则，新增剧情注册文件和正式章节烘焙清单。
- 不恢复暂存中的音频改动/删除 service.wav，不替换新角色、工作人员、地图地形和存档代码。

## 地图适用范围

江南、潮见町、白鹭港在 main 已换成独立原生地图及专用图集。旧新美术包没有这些新增图集的对应重绘，故保留 main 专用地图图片与节点位置。此次迁移新通用贴图及餐厅美术，并不宣称三张独立地图已全部重画。要让独立地图彻底统一赛璐璐画风，需要后续对各专用图集另行重绘，不能以旧地图覆盖。

## 验证

视觉小说 35/35、410 断言；美术及剧情玩法 86/86、3326 断言；三镇内容 81/81、6067 断言。资源加载 194 项通过，实际剧情 GPU 28 检查、11 张美术实景图通过。Windows 导出 1462 个运行文件，三次启动及 97 项输入交互通过。完整测试与远程 CI 未运行，人工观感待试玩。首轮失败日志保留。隔离测试不读取或改写真实玩家存档。逐图来源/hash 见 artifacts/art-migration-20261126/migration.json。


## 手动修改入口

| 内容 | 文件/目录 |
|---|---|
| 主页面 | `assets/redraw-v1/title.png` |
| 木牌、对话羊皮纸 | `assets/ui-wood-v1/wood-light.png`、`parchment.png` |
| 食材图 | `assets/redraw-v1/ingredients-0.png` 至 `ingredients-4.png` |
| 菜品图 | `assets/redraw-v1/dishes-0.png` 至 `dishes-2.png` |
| 图标 ID 与裁切 | `assets/redraw-v1/index.json`、`icon-regions.json`，保留 `ingredient_slots`/`dish_slots` |
| 剧情背景/CG | `assets/vn-painterly-v1/`；登记在 `content/story/vn/presentation.json` |
| 三镇当前专用图集/地表 | 继续使用 main 的 `assets/town/jiangnan-*`、`shiomi-*`、`egret-*` |
| 当前试玩入口 | `build/TownDiner.exe`，配套同目录 `TownDiner.pck` |

迁移记录中的 generation manifest 是历史生成信息，部分 hash 与后来保存到暂存的文件不一致。本次逐张比较了实际暂存 Git blob，27 张均一致，证据不依赖旧 manifest hash。

Windows 实际 EXE 已完成 11 张实景截图，退出码 0。当前包引用的 27 张迁移纹理与导入缓存逐字节一致，缓存源 MD5 对应新 PNG；未引用图片：无。
