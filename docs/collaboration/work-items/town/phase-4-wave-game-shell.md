# D033 物件交互与中式像素场景工作单

- 角色：town；负责人为同一 Agent 顺序执行的小镇角色。
- 基线 main@a164b1c；分支 work/town/phase-4-wave-game-shell；集成分支 integration/phase-4-wave-game-shell。
- 来源：D033、AI-040；AC-PHASE-4-G01/G02/G06/G08。
- 实现：生产模式门/NPC交互，餐厅营业牌、账本、菜谱架、装修桌、休息处与后厨门；来客投影当前营业订单；摄像机/输入切换；新档四桌布局，读档保留已有布局。
- 世界快照显式校验再恢复，包含已有供货、区域、建设、时间与随机状态。旧独立调试场景默认行为保留，不以第二套业务账接单结算。
- 文件：src/town/world_snapshot.gd、town_world.gd、town_art.gd；src/restaurant/restaurant_layout.gd、restaurant_world.gd、restaurant_iso.gd；assets/town 三张PNG及来源/导入配置。
- 画面资源：内置image_gen新生成，原生图集切片；无第三方素材下载。民居合组只改变显示，不改地图ID、道路或人口规则。
- 公共入口与输入映射由轮值集成者修改。debug才允许旧实验按钮，正常生产只保留物件操作所需界面。
- 验证：12张真实 Compatibility/NVIDIA 截图退出0；往返真实场景、订单、设置和保存由共享 game suite 覆盖。全量证据见 docs/phases/game-shell.md。最终美术与真人体验 PENDING。
- 状态：READY_FOR_REVIEW；本地角色文件集成，无提交推送。

2026-10-23餐厅移动反馈：实际复现176条跨场景幽灵阻挡。隔离餐厅/小镇碰撞层；空功能分区按实际家具占地通行，服务落脚点仍限定过道；物理与顾客寻路同源。人物纹理透明边距计入脚底锚点，家具底影与前后遮挡按地面位置绘制。测试test_town_motion增加全过道扫描、真实输入、切场景、家具拆移与脚底投影；旧paint(D)阻挡用例改为真实墙体paint(#)，新增空分区可走的正向断言。未改存档/资产/烹饪/经济规则。完整验证见主阶段报告。
