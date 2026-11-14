# 非地图美术重绘与视觉小说对话（2026-11-12）

用户授权按四张人物原图画风重绘其余美术，用原定妆固定姿势的表情差分替换立绘，对话框绘于立绘前方。本轮保留此前地图建筑与道路成果。等价需求审核无阻塞；沿用 godot-gdscript-patterns，imagegen 技能；原始附件只读。

35张版本化PNG位于assets/redraw-v1。包含四位角色各六表情、148食材、100菜品、标题/厨房/剧情背景、CG人物动作和道具、地图行走、普通顾客行走与坐姿、小屋及餐厅道具。restaurant-furniture.png为兼容备用常量，主装修模型使用dining-parts与diner-props并有程序绘制部分；不能将它写成全部家具的实际来源。全工程47张当前使用PNG与1张备用的逐文件用途、布局、完整路径见docs/当前美术资源修改清单.md与active-art-inventory.json。

TDRedrawArt按既有材料/菜谱ID索引，不更改经济与菜谱数据。index.json记录顺序；icon-regions.json记录按透明留白实测的非等分裁切。旧别名仅在ID不在正式目录时映射，正式oil/pepper/vinegar/wine不可被旧别名覆盖。AtlasTexture只读裁切，所有PNG由image_gen生成/编辑；像素测量只产生裁切元数据，不修改图像。generation.json及修正generation文件保存提示和来源，sha256.json记录最终图像哈希。

对话左右立绘z=0、底部面板z=2，文本从36px开始；六表情使用共享裁切框，换表情不改变身位。序章对白使用无CG人物的背景，阿铃画外喊话时不提前显示；CG保持原AnimationPlayer时长、音效和暂停/跳过/取消规则。正式人物移动、碰撞、地图地籍、经营、存档规则不改。project.godot与content/dev_samples.json用户原有修改经起点备份哈希比对一致。

验证：首轮story-expansion 46/46、相关回归redraw 81/81（2843断言）通过；裁切/名称修正后redraw-assets 3/3（630断言）通过。源工程GPU最终381项/43图与真实用餐GPU74项/22图通过。首次图形检查发现四个旧别名导致空图、邻格残边，日志与43图留在visual-first/gpu-first，修正后全部通过。源资源加载149/149；最终导出712运行文件，35张新PNG及索引/裁切均在包内，实际EXE启动3次各4项、headless正式输入94项通过。证据分别在artifacts/check/redraw-story-expansion、redraw-final、pre-export-20261112-125608、style-redraw、export。

当前输出美术重绘与对话立绘版.zip。当前用户追加要求的可编辑表格为outputs/当前美术资源修改清单.csv与.md。未读取或覆盖真实玩家存档，未提交/推送，未跑全仓或远程CI；人工画面验收PENDING。root写入锁释放。
