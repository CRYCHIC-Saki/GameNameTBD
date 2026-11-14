# 五种焰请八方店铺贴图（2026-11-11）

来源：用户提供中式酒楼、日式居酒屋、欧式饭店、东南亚小馆、墨西哥餐厅五张设定页，授权处理调整后替换原贴图。本轮只改外观及资源绑定，不改经营、地籍、门口交互、存档或室内。

当前工作副本：`C:/Users/myzpw/Documents/ChatGPT/NJU GAMING/GameNameTBD`，由上一聊天目录的干净本地克隆复制，基线3fe4c8b，独立分支integration/phase-4-wave-restaurant-art。原工作副本及用户桌面原图保留。

实际技能：内置image_gen，说明来自`C:/Users/myzpw/.codex/skills/.system/imagegen/SKILL.md`；godot-gdscript-patterns读取wshobson/agents的`plugins/game-development/skills/godot-gdscript-patterns/SKILL.md`（本机缓存缺失，工作目录保存只读参考副本），采用静态类型、只读纹理和既有缓存。grilling本机缺失，按DEVELOPMENT_PROTOCOL执行等价需求审查，GRILL_SKILL=NOT_AVAILABLE；GRILL_RESULT=NO_BLOCKING_PRODUCT_QUESTIONS：五种用途与既有地图一一对应，本轮无新增玩法决策。

实施前验收：
- AC-ART-001：五张素材为独立正面透明PNG，移除设定页标注和多视图；保留各店屋顶、招牌、配色与特色装饰；人工审美待用户确认。
- AC-ART-002：中式绑定主镇食堂，其余四种绑定各镇餐饮建筑；住宅、港口、公共建筑及旧图集保留。
- AC-ART-003：跨镇贴图以AtlasTexture透明边距维持原3:2逻辑画布，底部居中，不改既有碰撞缩放与地块/交互/存档规则。
- AC-ART-004：导入、加载、travel-core及visual-unity相关回归与实际图形截图检查；导出资源显式加入五图。未实际运行的检查不得记为通过。

素材与完整提示集：`assets/town/restaurant-designs-v1-generation.json`。均使用内置image_gen，未用CLI/API回退；运行时AtlasTexture只读裁切/加透明边距，未用脚本改写生成位图。旧PNG逐字节保留。

验证结果：
- 引擎：4.7.2.stable.steam.ed1daf0bf，使用原已安装版本的工作区便携副本；APPDATA/LOCALAPPDATA仅在本次进程中指向`.tools/test-appdata`和`.tools/test-localappdata`，不改系统或真实玩家档。初轮未隔离用户目录，检查因`user://`目录不可写失败；失败证据保留，隔离后通过，不将初轮记为通过。
- `tools/check.ps1 -Suite travel-core`：11发现/11执行/11通过，0失败/跳过，导入/加载/测试均退出0，证据`artifacts/check/restaurant-travel-isolated`。
- `tools/check.ps1 -Suite visual-unity`：43发现/43执行/43通过，0失败/跳过，证据`artifacts/check/restaurant-visual-unity`。
- `tools/restaurant_art_probe.gd`：Compatibility/OpenGL3.3、RTX4060，33项通过、退出0，五镇实际场景与五种店铺预览共6图已目视检查；透明边角、非空图像、3:2逻辑画布、隔离新档及往返状态不变均通过。首版预览TextureRect受最小尺寸影响重叠，已仅修探针布局并复验，最终见`artifacts/restaurant-art/gpu-final.log`和`gpu/summary.json`。
- `tools/export.ps1 -CheckSuite travel-core`：前置11项再次通过，导出/打包检查退出0；622运行资源，直接核对包内包含全部五张新图的导入映射；实际EXE启动退出3次×4检查、标题与移动94项通过，证据`artifacts/export/summary.json`。
- `git diff --check`及integrator协作范围检查通过。旧PNG及原始资料没有修改；新图与内置生成结果SHA256相同，未脚本重采样/抠图/改写alpha。引用图和新图哈希已记录在生成清单。

AC-ART-001工程处理完成、人工审美PENDING；AC-ART-002–004通过。全仓all、远程CI及长期人工试玩NOT_RUN；没有沿用旧回归结果。未提交、推送或发布。

复现（PowerShell，仓库根目录）：先将本次进程的APPDATA/LOCALAPPDATA指向上述`.tools`隔离目录，再用`-GodotPath`指定`.tools/godot/godot.windows.opt.tools.64.exe`运行tools/check.ps1及tools/export.ps1。图形检查以同一引擎运行`--path . --rendering-method gl_compatibility --script res://tools/restaurant_art_probe.gd`；桌面程序看`build/TownDiner.exe`，同目录保留TownDiner.pck。

用户确认步骤：打开五店预览；运行本地程序；用测试槽查看主镇食堂；从港口前往四镇查看餐饮外观；反馈屋顶/招牌/配色或地图显示尺寸是否需要继续微调。当前阶段结束，等待美术反馈。
