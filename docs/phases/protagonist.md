# 主角四向形象与行走动画

2026-10-27，用户授权的视觉增量，不启动其他玩法阶段。

## 经营闭环同步后的复验（2026-10-27）

用户随后要求拉取新内容。主角增量保存为本地3085cdb，与origin/main的732d144经营闭环整合；代码保留两边职责，记录中的同名D040/AI-048分别标注VISIT来源。新guest_visit导出依赖补齐。首轮全量检出旧调试顾客pay路径被就座逻辑拦住，已仅对正式Shop顾客保留pay就座，旧流程可正常结账离店；该修正不改主角计步。

最终pre-export-20261027-204644：461/461、15561断言、723.902秒，0失败/跳过；主角5项、新餐厅12项、旧顾客6项均通过。标准导出和实际EXE三次启动退出、29项菜单/移动检查通过，本轮未出现退出泄漏警告；R2此前偶发警告历史仍保留，不能声称已定位其根因。证据artifacts/pull-20261027-202823，GPU人工观感仍PENDING，本轮仅本地同步。

## R2 餐厅计步坐标修复（2026-10-27，步频工程通过、待人工复验）

- USER_CONFIRMED：R1后餐厅前后步频仍太快。当前继续D040反馈修复，复用已读取的godot-gdscript-patterns，无新增阻塞产品选择。
- 根因：餐厅motion_transform为含非均匀比例的等距逆投影；basis_xform_inv仅对正交归一基有效，旧调用把真实左右位移放大2倍、前后放大8倍。R1图形探针也使用了同一错误转换，其“屏幕位移”数值并不真实，撤回以该数据作节奏正确性证明；历史测试/导出确实通过，但覆盖没有检出本缺陷。
- AC-PROTAGONIST-R2-001：真实餐厅WASD输入后，用绘制端project计算独立屏幕位移；迈步相位×140（左右）/224（上下）须与该位移一致。先在旧实现复现失败，再修复运行；不以同一计步公式自证。
- AC-PROTAGONIST-R2-002：继续保持餐厅180屏幕像素/秒、碰撞和R1尺寸；停止/暂停/隐藏行为通过既有用例，图形与实际导出复验。4拍时长理论左右约0.78秒、上下约1.24秒，人工观感仍待复验。
- API依据：[Godot Transform2D官方文档](https://docs.godotengine.org/en/stable/classes/class_transform2d.html#class-transform2d-method-basis-xform-inv)；实际以锁定4.7.2执行结果为准。本次只修步态距离路径，朝向交互策略保持既有行为。
- RED已执行：protagonist-r2-red共20项，19通过、1失败，4个方向的计距断言失败、进程退出1；画面21像素被旧逻辑计为42（左右）/168（上下），其余速度/碰撞用例通过。
- 修正后的真实GPU探针退出0、17图：三个方向都实际移动21像素，左右相位0.15、上下0.09375，对应140/224，尺寸保持70/71.875/72。日志和截图在artifacts/protagonist-stride-r2。
- GREEN：标准`pwsh -NoProfile -File tools/export.ps1`前置检查pre-export-20261027-193053为458/458、15519断言、726.786秒，0失败/跳过，版本/导入/加载/测试全部退出0；4条既有Float/Int警告保留。新回归在完整运行中通过，不以旧版结果代替。
- 19:43重建build/TownDiner.exe/PCK；实际导出、440资源审计、EXE启动退出3次×4项通过。但首次菜单探针虽29项通过、进程退出0，退出时出现2个ObjectDB对象泄漏警告，标准export.ps1正确退出1，原始summary保持FAIL，没有抹掉失败或放宽门禁。
- 用户要求重试后，同一导出包先以verbose复跑29项，再按原错误/泄漏/超时门禁连续重试3次；全部29/29、退出0、无错误或泄漏警告。生产代码与包未改，不重复全量458项。聚合证据artifacts/protagonist-stride-r2/build-receipt.json，专门复验export-recheck.json，保留title-input-first.log及export-first-summary.json。首次退出警告原因未定位，暂未复现，不能写成已修复或标准导出首轮全通过。
- AC-R2-001通过；AC-R2-002运动/图形及导出复验通过，退出稳定性保留上述风险。人工步频/美术观感PENDING，远程CI NOT_RUN。所有权39文件检查PASS，原站姿/补帧图集哈希不变；本轮锁释放，停在本地交付点，未提交或推送。

R2复验：运行build/TownDiner.exe，进入餐厅，分别按住W/S走一段再松开；比较A/D、停步及靠墙表现。使用19:43的新包并保持同目录TownDiner.pck配套；不沿用R1的17:52包。

## R1 人工反馈修正（2026-10-27，工程完成、待用户复验）

- USER_CONFIRMED：餐厅人物大小合适，厨房和小镇偏小；餐厅前后行走步频过快。属于D040验收反馈，不启动新阶段，不需要新增产品问答；继续使用已读取的godot-gdscript-patterns。
- AC-PROTAGONIST-R1-001：1280×800实际画面中，厨房/小镇人物高度调整至餐厅附近，餐厅/小屋维持原大小；物理脚点及碰撞不变。实际图形探针与既有运动回归验证。
- AC-PROTAGONIST-R1-002：餐厅前后循环变慢，左右节奏和八向移动速度保持；暂停/停步/受阻正确。实际图形探针与既有运动回归验证。
- ASSUMPTION AI-048修订：厨房显示高100本地像素，经营界面0.71875缩放后71.875；小镇48→72；餐厅/小屋70不变。步态距离与显示大小解耦：房间视图坐标下厨房/餐厅/小屋基准140，小镇维持96；仅餐厅前后循环为224屏幕距离（步频为原来的62.5%）。切方向保留归一化步态相位。参数待用户复验，当前结果不得沿用上一轮通过状态。
- 既有专项复验：protagonist-tuning-r1为19/19、481断言、75.327秒，0失败/跳过、各阶段退出0。图形探针首轮等待自动绘制超时，保留visual-console-timeout.log，未算通过；改为用RenderingServer.force_draw(false)实际渲染视口后，18图、退出0、无运行错误。实际测量cottage=70、kitchen=71.875、restaurant=70、town=72；餐厅右移42距离推进0.3循环，上/下各168距离推进0.75循环，即每轮分别140/224。不是以不同采样时长比较移动速度；八向等速由既有运动集成用例验证。
- R2更正：上一条R1的42/168距离是错误转换的输出，真实距离均为21；由其推导的节奏正确性结论作废，保留历史记录供追溯。
- 已目视核对放大后的厨房/小镇和餐厅背面。证据artifacts/protagonist-tuning-r1；标准export.ps1全量pre-export-20261027-173949为457/457、15505断言、742.261秒，0失败/跳过，版本/导入/加载/测试退出0。440资源审计、实际EXE启动退出3次×4项和菜单/移动29项均通过，各步骤退出0。
- 17:52重建build/TownDiner.exe/PCK，17:53导出门禁完成。构建快照和SHA256见artifacts/protagonist-tuning-r1/build-receipt.json。AC-R1-001/002工程PASS，比例和步态最终观感待用户复验；旧17:17包不包含本修正。协作所有权39文件PASS，图集哈希不变、写入锁释放，未提交/推送。

## 来源与范围

- USER_CONFIRMED：使用assets/characters/protagonist/protagonist-idle-four-directions-v1.png替换现有主角，完善行走动画。原图及其四向身份保留，原稿只读；NPC与雇员不替换。
- 事实：原图1254×1254，2×2四张站姿；各格脚点并不相同，切片/锚点采用原asset-manifest.json并在真实场景校验。此前人物只做整图上下移动/扭转，没有迈步帧。
- 实际技能：grilling，C:/Users/Administrator/.codex/skills/grilling/SKILL.md；godot-gdscript-patterns，C:/Users/Administrator/.codex/skills/godot-gdscript-patterns/SKILL.md；imagegen，C:/Users/Administrator/.codex/skills/.system/imagegen/SKILL.md。三者无版本字段。已读取技能及Godot参考；按grilling进行只读运动链事实调查。
- GRILL_RESULT = NO_BLOCKING_PRODUCT_QUESTIONS：形象由指定图确定，四向和移动规则沿用D039；补帧、脚点归一和采样速率是可逆视觉实现，不涉及新的产品玩法选择。
- ASSUMPTION AI-048：四向各4拍（左脚迈步→原站姿过渡→右脚迈步→原站姿过渡），8张独立迈步姿按实际屏幕位移推进；步长与显示尺寸可调，最终观感待试玩。透明位图由内置image_gen补绘，原图不覆盖。初版16格出现帽子镜像/朝向错误已弃用；改为8张相反迈步姿与原站姿组成循环。

## 验收

| 编号 | 来源/输入 | 可观察结果 | 验证 |
|---|---|---|---|
| AC-PROTAGONIST-001 | 指定PNG/四向转身 | 四面分别使用原站姿，脚点稳定、不镜像错位 | 图集与真实场景 |
| AC-PROTAGONIST-002 | 真实移动/松键/撞墙 | 手臂与双腿逐帧迈步，只有实际位移才推进，停下回对应站姿 | 输入/碰撞集成 |
| AC-PROTAGONIST-003 | 小镇/餐厅/厨房/小屋 | 同角色同一动画状态，餐厅遮挡排序和方向正确 | 四场景/图形探针 |
| AC-PROTAGONIST-004 | 弹窗/暂停/隐藏/重入 | 不后台跑步、不遗留旧步态、不改变物理与交互 | 生命周期集成 |
| AC-PROTAGONIST-005 | 标准检查与导出 | 资源进入运行包、全量与实际EXE检查通过；来源原图哈希不变 | check/export/哈希 |
| AC-PROTAGONIST-006 | 人工走动观察 | 步态、大小、转身和携物效果可接受 | PENDING人工 |

## 当前断点

四场景已经接入。普通房间由TDKitchenPlayer选择帧，餐厅投影读取同一帧；速度、物理碰撞、交互、存档和NPC规则未改。TDChefArt缓存12张只读切片（4站姿＋8迈步），原图字节未改。最终补帧图集1536×1024、4列×2行，生成提示/迭代说明在素材目录walk-generation.json。

## 已执行验证

- `pwsh -NoProfile -File tools/check.ps1 -Suite protagonist -ReportName protagonist-first`：19/19、481断言、117.889秒，0失败/跳过，版本/导入/加载/测试退出0。包含本轮4项真实入口集成，复用住所/朝向/碰撞与厨房回归。较早的idle预检5/5仅证明站姿接入，不作为走路验收。
- 锁定Godot运行`--path . --script res://tools/protagonist_probe.gd`：Compatibility / NVIDIA RTX 3050 Laptop实际渲染，15张图包含四场景、厨房/餐厅四拍及停步，最终退出0、无解析/运行错误。已目视检查透明背景、四向帽子/背锅、底部脚点与投影；artifacts/protagonist/visual-report.json为success=true。
- 图形探针初次在physics_frame信号恢复点过早断言松键状态，已改为等待完整物理更新；第二次图片检查通过但探针调用了不存在的app.request_quit导致超时。修正为回标题并调用真实shell.request_quit，第三次全过程退出0。失败日志分别保留visual-console-first/second.log，没有更改游戏规则去掩盖探针问题。
- 协作所有权检查：integrator→main、工作树36文件PASS；原始素材基线除明确追加接入说明的assets角色README外，其余逐项SHA256一致，见artifacts/protagonist/source-integrity.json。
- 标准`pwsh -NoProfile -File tools/export.ps1`完整通过：pre-export-20261027-170516为457/457、15505断言、697.91秒、0失败/跳过，各阶段退出0。4条既有Float/Int比较警告未隐藏。导出440个运行资源，明确含两张主角图集及导入资源；设计稿/对话立绘/生成记录/测试不出包。实际EXE启动退出3次×4项、菜单/移动29项全部通过，无运行错误，各步骤退出0。
- 2026-10-27 17:17重新生成build/TownDiner.exe与TownDiner.pck。完整快照、文件SHA256、来源一致性见artifacts/protagonist/build-receipt.json；可审阅图形/全量原始日志。旧15:46导出仍属此前版本，不混用结果。

## 验收结论与衔接

AC-PROTAGONIST-001–005工程PASS；006人工美术/步态/携物观感PENDING，远程CI NOT_RUN。本轮使用真实图集、输入、碰撞、四场景与导出程序；无替身替代画面或运动链。未实现额外表情、服装或NPC替换；半身立绘仍留作后续对话接入。

关键文件：src/world/chef_art.gd、kitchen_player.gd、src/restaurant/restaurant_iso.gd、assets/characters/protagonist两张运行图集；专项测试tests/integration/test_protagonist.gd。共享写入锁释放，停在D040本地交付点，未提交或推送；前序导出依赖修复和用户原资料完整保留。

## 五步试玩（人工PENDING）

1. 运行本次build/TownDiner.exe，继续或开一个新槽。
2. 在小镇用WASD向四面走动，再松键；核对四个面与原设计一致、双腿有交替。
3. 面向店门按E，进入餐厅，水平/斜向移动并靠近墙；观察脚点不漂浮、撞墙停步，交互仍选面向目标。
4. 经后门进厨房，拿起食材走到灶台；观察携物与角色重叠是否合适，再用Esc暂停/恢复。
5. 到小屋床边走动、转身并停下；反馈角色大小、迈步节奏与转身观感。工程图形检查不代替人工美术接受。
