# 五镇地图素材画风统一（2026-11-11）

来源：用户在五种焰请八方店铺贴图接入后，明确要求其他地图建筑、道路等素材也参考同组图片修改。范围为五个可探索小镇的住宅、公建、作坊、摊位、港口、树木/装饰及道路/草地/土地/水面；沿用既有地图和功能，不重新设计道路布局、地块、经济、人物或存档。本轮新素材匹配已接入店铺的暖色描边像素画风与各地建筑语言。

基线：继续本地integration/phase-4-wave-restaurant-art，保留前轮全部未提交成果；本轮待修改文件和前轮截图备份到`artifacts/map-style/baseline`与`before`，用户桌面参考图和旧PNG只读。

技能：沿用imagegen与已读取的godot-gdscript-patterns（路径见restaurant-designs报告）。grilling本机缺失，按DEVELOPMENT_PROTOCOL执行等价审查：GRILL_SKILL=NOT_AVAILABLE，GRILL_RESULT=NO_BLOCKING_PRODUCT_QUESTIONS。用户明确外观范围、地区与参照画风，常规素材拆分和图集参数为可逆实现选择，不增加产品决策问题。

实施前验收：
- AC-MAP-001：主镇建筑/住宅/供应作坊/港口、四镇公建/住宅/港口与各地植被装饰采用暖色统一素材，全部图集索引含义不变，已接入五店保持。
- AC-MAP-002：五镇有对应的草地、道路、土地和水面材质，弱化冷灰大混凝土板观感，路面色调参考各店门前铺装；保留桥、岸线和可行走地形位置。
- AC-MAP-003：新图集透明空隙正确，切片无串格；跨镇建筑保持原3:2逻辑画布，避免素材尺寸改变碰撞。地籍/道路/角色/钱物/存档快照不因图像选择改变。
- AC-MAP-004：资源导入、加载、受影响town-polish/visual-unity/travel专项、五镇实景与导出包检查有真实证据。零测试/跳过/超时不算通过；用户审美确认与全量/远程CI单独标记。

新图以版本化文件接入，生成提示和来源将在`assets/town/map-style-v1-generation.json`留档。只用内置image_gen创建位图，不以脚本重绘生成结果；Godot保留既有运行时切片/缩放/地表合成。

本轮root独占：上述七类新图集/导入/元数据、EnvironmentArt/TownScenery/TravelCatalog/TravelWorld/Harbor外观绑定、必要回归与图形探针、导出清单及本轮文档。没有其他写入者，不改其他工作线核心规则。状态：DELIVERED_LOCAL_PLAYTEST_PENDING，写入锁释放。

## 实际实现

- 内置image_gen生成7个完整图集；位图仍为生成结果原字节，不脚本改写alpha/缩放文件。六套对象图透明，地表图全不透明。主镇及住宅图的生成位置不严格等分，通过只读alpha投影测量空隙，将实测Rect2切片写入既有绑定，避免裁到屋檐或邻格；实测数据在生成清单中。
- EnvironmentArt切换town-sprites-v4、residential-houses-v3、supply-factories-v2；Harbor切换harbor-v2并在两个独立图格中裁透明边。主镇外海与地图共用新水面材质，原港口/船/码头位置保持。
- TravelCatalog切换four-cultures-v2及props-v2，仍为1536×1024，与旧资源一致；建筑索引、3:2画布、实际碰撞缩放保持。四个地区餐饮仍优先用上一轮独立五店素材，不被新图集覆盖。
- TownScenery将map-surfaces-v1分为4列×5行，按中/日/欧/东南亚/墨西哥选择草地/道路/土/水；以原运行时120px采样与连续坐标拼接，选区内缩2px避开分格线，不改生成PNG。TravelWorld移除旧灰色逐像素混色，保留原地形、桥和岸线几何。
- 地图图集、提示清单均在assets/town；导出显式加入7图，既有tools/export.ps1资源白名单无需改。artifacts/.gdignore仅忽略本地验证/备份，防止复制的脚本或.import被Godot扫描为重复UID/类，不影响运行时FileAccess的隔离检查文件。

## 验证证据

使用工作区便携Godot 4.7.2.stable.steam.ed1daf0bf，进程APPDATA/LOCALAPPDATA仍隔离到.tools下；未升级或修改系统环境。

- town-polish：48发现/48执行/48通过，0失败/跳过；最终由tools/export.ps1前置运行，证据artifacts/check/pre-export-20261111-220130。
- visual-unity：43发现/43执行/43通过，0失败/跳过；证据artifacts/check/map-style-visual-unity。
- travel-core：11发现/11执行/11通过，0失败/跳过；证据artifacts/check/map-style-travel。
- 三份JUnit去重为78个独立用例，不能将102次套件执行声称为102独立用例。
- tools/map_style_probe.gd：Compatibility/OpenGL3.3/RTX4060，82项通过，退出0。14张图覆盖五镇风格总览、主镇食堂/两院落/市场/港口、四镇港口及街区，已逐图目视核对；包含图集边界、五镇道路不透明、建筑3:2画布、无暂停遮挡及旅行后游戏状态不变。证据artifacts/map-style/gpu-final.log、gpu/summary.json。
- 导出636运行资源，包检查/启动退出3次×4/实际EXE输入94项全部通过，证据artifacts/export/summary.json。本地build/TownDiner.exe及同目录PCK更新。
- git diff --check与integrator所有权范围检查通过；旧PNG及原始资料无修改，生成结果与落盘新图SHA256一致。

修复与限制：初次导入发现TravelWorld旧sand分支残留color变量，已移除并复验；复制截图备份产生的UID警告通过忽略验证目录消除。首轮town-polish为47/48，失败项是前轮已换木门的单像素固定色差阈值；同一门图不改，改测下方中央门区95%以上不透明且60%以上为暖木色，保持“不是透明门洞/摊位”的原验收意图，最终48/48。原失败日志保留。首版Bangkok截图曾被隐藏窗口焦点丢失的暂停层遮住，探针在隔离实例内清理临时层并新增无遮挡检查，最终14图已重新核对；生产暂停逻辑不改。

AC-MAP-001–004工程验收通过，用户人工审美PENDING；全仓all、远程CI及长期人工试玩NOT_RUN。未提交、推送或发布。下一步为用户反馈后局部调整，不自动进入新玩法阶段。
