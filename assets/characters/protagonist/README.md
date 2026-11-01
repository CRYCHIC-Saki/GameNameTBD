# 主角美术素材 v1

当前选定半身立绘：`protagonist-dialogue-halfbody-pose-pixel-v7.png`。用户于2026-10-28确认保留此版；文件与哈希记录在 `asset-manifest.json` 的 `selected_dialogue_portrait` 中，后续半身立绘工作以此为基准。原图字节保留，历史版本继续留档。

## 2026-10-28 高光、刀鞘与脸长微调 v7

用户要求在v6上调整三处：眼睛高光自然一些；腰间物件是刀鞘而非袋子；脸稍微长一点。内置 image_gen 两轮编辑后，去除瞳孔中央的大白块，改为深棕瞳孔和每眼左上小面积高光；腰间配件按原稿改为扁平、无包盖的棕色菜刀鞘；脸部略拉长并保留柔和下巴、托腮动作及细像素风。首轮高光仍有残留，已再修正，最终交付仅采用第二轮。

新版 `protagonist-dialogue-halfbody-pose-pixel-v7.png`（1254×1254，RGBA透明PNG），完整两轮提示及哈希见 `portrait-pose-pixel-v7-generation.json`。已检查PNG、透明背景并目视核对三处调整，用户已确认保留此版。后续须按“角色右腰／画面左侧是菜刀鞘”理解形象，不再沿用历史提示里的袋子／翻盖包画法。旧版本保留；游戏代码、动画和导出包未改，本轮游戏检查NOT_RUN。

## 2026-10-28 指定v4人物与上一版托腮构图结合 v6

用户本轮指定的 `exec-2581c576-37b7-44ee-82a8-94e7e046bfc8.png` 与项目v4逐字节一致；用其脸型、五官和人物形象，结合上一张v5的托腮动作、半身构图和细像素画法。内置 image_gen 双参考生成新版 `protagonist-dialogue-halfbody-pose-pixel-v6.png`（1254×1254，RGBA透明PNG），完整提示与两张参考的具体职责见 `portrait-pose-pixel-v6-generation.json`。

已检查PNG、透明背景并目视核对人物、姿势和画风；人工美术确认PENDING。旧版本、原稿、角色动画及游戏代码保留；本轮没有游戏运行检查或导出。

## 2026-10-28 指定托腮图可爱风微调 v5

用户重新指定 `exec-44d728b2-3ae1-47fb-bac2-fe01a2291638.png`，要求保持该图姿势和像素表现，仅将风格变得可爱一些。以内置 image_gen 编辑这张指定图，柔化眉眼与脸部线条，保留托腮和扶刀鞘姿势、构图及细像素表现。新版为 `protagonist-dialogue-halfbody-pose-cute-v5.png`（1254×1254，RGBA透明PNG），完整提示词及哈希见 `portrait-pose-cute-v5-generation.json`。输入原图已按原字节归档到 `doc/source/characters/protagonist/dialogue-pose-selected-reference.png`，没有以v4替代用户指定参考。

PNG与透明背景检查通过，已目视核对姿势和画风；生成编辑不宣称脸部以外逐像素完全不变。用户美术确认仍为PENDING。旧版文件保留，未修改运行素材、游戏代码或导出包。

## 2026-10-28 半身脸型微调 v4

用户要求脸稍微瘦一点。以内置 image_gen 在v3上小幅收窄两颊与下颌，保留大眼、短圆下巴和既有像素画风。新版 `protagonist-dialogue-halfbody-pixel-v4.png` 为1254×1254 RGBA透明PNG；来源、完整提示词与哈希见 `portrait-pixel-v4-generation.json`。PNG解码和透明检查通过，已目视检查；人工确认PENDING。历史版本与运行素材不覆盖，本次不改游戏代码、不重建程序。

## 2026-10-28 半身像素立绘重绘 v3

用户指出v2只是原稿换动作，像素画法不足，未通过美术验收。本次按原始人物形象重新绘制像素游戏半身立绘：保留原稿圆脸、大眼、短下巴、可爱神态及服装，用明显方形像素块、阶梯轮廓和分层色块重绘五官、头发及衣物。新文件 `protagonist-dialogue-halfbody-pixel-v3.png`（1254×1254，RGBA透明PNG）；内置 image_gen 的完整提示及来源哈希见 `portrait-pixel-v3-generation.json`。

已检查PNG解码、透明背景和可见像素表现，用户最终美术确认仍为PENDING。提示词中的128×128是画法细节目标，成品保持生成器实际输出尺寸，不声称已具备严格128×128像素网格或32色调色板。没有脚本缩放、滤镜或重新量化，也未修改角色动画、游戏代码或原始设计稿。仅交付修订素材，未执行游戏检查或重建程序。v1、v2保留为历史版本，不能视为已认可形象。

## 2026-10-28 半身立绘可爱风修订 v2

用户反馈上一版半身像与原稿风格差异较大，希望保留可爱风格。本次直接以原始无标注设计稿为主参考，使用内置 image_gen 重做圆脸、大圆眼、短下巴和大头小身比例；阴影、材质与像素感减轻，双手放在围裙前，保留原服装和火焰特征。新版为 `protagonist-dialogue-halfbody-cute-v2.png`（1254×1254，RGBA透明PNG），完整提示词及SHA256见 `portrait-cute-v2-generation.json`。

新版用于左侧半身头像、右侧独立文字的对话布局，当前为待用户确认的美术修订。原稿、旧半身v1和四向站姿哈希复核一致，行走素材及游戏代码未修改。PNG解码、透明背景与目视检查通过；本次只修改素材，未执行Godot游戏检查或重建程序，半身对话接入仍待后续任务。保留下面的历史交付记录，不将本次修订视为人工美术已验收。

## 2026-10-27 D040游戏接入增量

指定四向站姿已接入小镇、餐厅、厨房和小屋。新增protagonist-walk-four-directions-v1.png（1536×1024、RGBA）：4列依次向下/上/左/右，2行为相反迈步姿；循环为迈步A→原站姿→迈步B→原站姿，共8张新姿势。内置image_gen生成与透明背景处理的完整提示见walk-generation.json；未使用CLI/API fallback，也未用脚本改写位图。

运行切片按alpha≥128可见边界测量，定义在src/world/chef_art.gd，底部中心对齐实际碰撞脚点。原站姿、半身像及doc/source设计稿字节未更改；半身对话立绘仍未接入。以下保留最初素材交付记录；最新运行验收以docs/phases/protagonist.md为准。动画美术最终观感仍待人工确认。

2026-10-27，根据用户提供的两张主角设计稿，使用内置 `image_gen` 生成；未使用 CLI/API fallback。唯一素材写入者为本次任务 Agent。两张原稿原样归档，新素材独立保存。

## 文件与用途

| 文件 | 用途 | 实际尺寸 |
|---|---|---|
| protagonist-idle-four-directions-v1.png | 四向静止小人，2×2透明图集 | 1254×1254，每格627×627 |
| protagonist-dialogue-halfbody-v1.png | 微像素半身对话立绘，左侧放头像、右侧放文字 | 1254×1254，透明PNG |
| asset-manifest.json | 来源哈希、实际切片、建议脚点、验证记录 | JSON |
| generation-prompts.json | 完整最终提示词及半身构图修订提示词 | JSON |

原稿在 `doc/source/characters/protagonist/`：`design-annotated-original.jpg` 与 `design-clean-original.png`。源图 SHA256 与用户临时附件一致，不能拿生成结果覆盖原稿。该参考目录中的 `.gdignore` 用于避免原稿成为运行资源。

## 四向切片

坐标从图集左上角起算，单位为图像像素；`[x,y,width,height]`。每格各一张站姿，没有行走动画。

| 朝向 | 图集区域 | 格内建议脚底锚点 |
|---|---|---|
| 正面／向下 | [0, 0, 627, 627] | [370, 625] |
| 背面／向上 | [627, 0, 627, 627] | [254.5, 625] |
| 朝左 | [0, 627, 627, 627] | [382, 598] |
| 朝右 | [627, 627, 627, 627] | [248.5, 598] |

这些脚点按 alpha≥128 的可见外接框底部中心估计，接入时需要在游戏中验证。图集内角色没有机械居中，不能直接把每格中心当作同一个脚点。推荐 nearest 采样；图像保持生成器原尺寸，未冒称原生48×64低分辨率导出，也未用脚本缩放、抠图、重绘或改写透明通道。

## 形象约束与美术演绎

保留金黄／红色火焰发色、火苗发束、偏戴厨师帽、琥珀眼、白衬衫、红领带、奶油色围裙、深色短裙、棕靴、刀鞘和背锅。小人左右面分别绘制，刀鞘与围裙火焰的角色左右关系可区分。小人采用双手自然下垂的待机姿势，半身采用亲切而自信的微笑。

侧面和背面、站姿、半身表情是基于正面原稿的可调整美术演绎，不是用户新增确认的世界观设定。立绘用于左侧头像区，文字应由界面独立显示在右侧；图像不含烘焙文字、边框或按钮。

## 验证与断点

- 原稿复制：2/2 SHA256一致。
- 两张成品：PNG解码正常，均为32位RGBA，背景存在真实alpha透明。
- 四向图集：四面目视检查完成；以alpha≥128测量，四个人物的可见主体均未跨越各自格边界。
- 半身：已修订顶部留白；可见火苗顶部约距画布98像素，帽子和发束完整，底部为有意腰部截取。
- 保留生成透明通道，其边缘含半透明像素及极低alpha像素；边界测量阈值只用于元数据，没有修改原图。
- 只交付素材与接入参数；当前游戏角色及对话代码未替换。Godot运行检查、导出及游戏内观感：NOT_RUN；人工美术确认：PENDING。
- 本轮为美术素材任务，未执行 `tools/check.ps1`，不沿用历史游戏测试结果充当本次验收。
- 实际使用 imagegen 与 grilling；GRILL_RESULT=NO_BLOCKING_PRODUCT_QUESTIONS。技能来源分别为本机 `C:/Users/Administrator/.codex/skills/.system/imagegen/SKILL.md` 和 `C:/Users/Administrator/.codex/skills/grilling/SKILL.md`，均无版本字段。
- 未提交、推送或发布。断点为素材已归档、生成和目视核对；运行时替换、行走动画及表情扩展属于后续工作。

完整提示词见同目录 `generation-prompts.json`；生成调用ID与文件哈希见 `asset-manifest.json`。

