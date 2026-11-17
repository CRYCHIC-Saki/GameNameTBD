# D077 剧情可视化编辑器（2026-11-16）

## D077-R4 美术交接保存（2026-11-16，LOCAL_EDITOR_READY / AUTHOR_PLAYTEST_PENDING）
USER：编辑器主要由美术制作剧情；保存时以自然语言标注所属段落，之后由AI/开发者接入，不要求美术配置触发。实际使用grilling与godot-gdscript-patterns（C:/Users/Administrator/.codex/skills对应SKILL.md，无版本字段），vn_handoff_facts只读核实。GRILL_RESULT = NO_BLOCKING_PRODUCT_QUESTIONS：交接说明不执行、保留原触发机制供开发使用，已明确。root唯一写入编辑器及检查/记录，不改运行玩法或真实档。
AI-087-R4：保存前填写剧情名、所属段落、插入位置（至少有一项位置说明）、可选备注；随TXT以原生忽略的注释保存，单文件原子替换。正式已绑定/港口开篇通过美术保存入口只另存待接入副本。原高级接入入口隐藏到高级模式；不自动根据自然语言注册触发。

| AC | 条件/结果 | 验证 |
|---|---|---|
| AC-PHASE-VNE-R4-001 | 保存/另存先填中文交接说明，重开能回填和修改；取消不写文件 | 原生编辑器图形 |
| AC-PHASE-VNE-R4-002 | TXT自带结构化注释供人/AI读取；对白/分支语义不变，坏版本/重复块不静默覆盖 | 原生解析/文件单元 |
| AC-PHASE-VNE-R4-003 | 保存备注不改events或正式原篇；已接入文件只另存，未登记作品不被发布 | 文件/导出 |
| AC-PHASE-VNE-R4-004 | 保存冲突/失败不损原文，草稿恢复保留说明；已有53项回归 | 现有检查入口 |

实际实现0.5.0：保存/另存/Ctrl+S统一中文表单；同TXT的版本化JSON注释，重开回填、普通更新保留身份、复制保存记录原路径/哈希并换身份。取消不落盘，未知/损坏/重复头拒绝；位置不确定可写待定。开篇及登记的启停两态文件拒绝作者覆盖；原开发接入移到高级步骤。正文与说明单文件保存/备份/冲突保护，选中页随注释行数变化保持。未用替身替代编辑器或原生播放，未实现自然语言自动插入。

| 验证 | 实际结果/证据 |
|---|---|
| 导入→加载→单元/原生集成 | `tools/check.ps1 -Suite vn-editor -GodotPath "F:/MyGameTBD/artifacts/vn-framework-20261113/engine/godot.exe" -TimeoutSeconds 240 -ReportName vn-handoff-fixed`：59/59、448断言、0失败/跳过，161加载，全部exit0。新增6项覆盖转义/中文/CRLF、注释语义、冲突/恢复、正式文件及停用登记保护。 |
| 真实编辑器 | `artifacts/vn-handoff-20261116/editor-first.log`：28检查、2图、0失败、exit0。通过实际编辑器按钮信号及文件选择回调验证表单/必填/取消/重开/另存/关闭/选中页/原篇保护；不冒称人工点击验收。 |
| 原生图形预览 | `native-play.log`：6检查、1图、exit0。保存后的同一TXT由真正VN播放器显示背景/角色/对白，交接头不显示，内存预览不读写玩家档，退出释放单例。 |
| 发布隔离 | `draft-export.log`及`export-check.json`：隔离ZIP导出exit0，1267资源匹配现有tools/export.ps1白名单。待接入TXT实际存在时导出，未被烘焙/带入；正式intro仍在包中。未重建EXE，未进行本轮EXE图形测试。 |
| 资料与收尾 | `protected-result.json`：34保护文件一致；intro与events登记哈希未变。测试TXT保留证据副本后逐文件移除，作者原恢复草稿还原；git diff --check exit0。保留前轮未提交代码及14:44 EXE/PCK，不推送。 |

AC-PHASE-VNE-R4-001–004工程通过；人工长篇制作/交接体验PENDING，全仓及远程CI NOT_RUN。首轮57/59失败记录保留：JSON整数类型往返归一化、损坏登记的解析错误改为友好拒绝后复验通过。独立StoryRunner加载检查的缺默认asset_map警告为既有裸实例提示，正式宿主/图形播放有实际资源且通过。root锁释放，停在本轮交付点，后续由美术保存真实剧本再交开发者接入。

以下R3及R2/R1为历史记录；作者流程以本节与docs/VN_EDITOR.md“美术保存与交接”为准。

## D077-R2 素材导入（2026-11-16，LOCAL_EDITOR_READY / AUTHOR_PLAYTEST_PENDING）
R2.1关闭入口修复：用户反馈看不到关闭按钮；在弹窗内容顶栏增加可见的×，不依赖操作系统窗口装饰，Esc显式关闭，保留底部取消；导入busy时禁用关闭控件，不改变入库规则。固定换行说明的最小宽度，避免弹窗被撑到1328px高而遮住底部按钮；最终500×631。本轮复用AC-R2-003取消/重开边界，无产品阻塞问题。Godot真实独立弹窗输入12项/1图、0失败、exit0（artifacts/vn-import-close-20261116/editor-close-routing.log）；验证正常高度、选图后鼠标关闭、重新打开清未提交表单、取消/Esc、cast和导出清单未变化。首次探针窗口事件路由错误2项失败，紧凑布局验证两次鼠标注入未关闭各1项失败，均保留日志；最终使用弹窗window_id、等待焦点并处理嵌入窗口坐标后通过。原40用例为上一轮记录，本次不重跑全量；人工PENDING，未重建EXE/推送。

USER：增加导入素材功能。入口再次读取实际grilling与godot-gdscript-patterns（C:/Users/Administrator/.codex/skills对应SKILL.md，均无版本字段），事实工作线只读核实原生登记与导入缓存。GRILL_RESULT = NO_BLOCKING_PRODUCT_QUESTIONS：用户已明确PNG背景/角色入库需求，原生播放器/原图只读/项目存档不变；本轮范围为背景、新角色与已有角色表情图片，音频和CG仍沿原接口。

| AC | 条件/来源 | 可观察结果/验证 |
|---|---|---|
| AC-PHASE-VNE-R2-001 | 用户：选择本地图片导入 | 图片选择/预览/中文名称，自动注册背景、新角色或表情，无需填写ID和修改资源文件；真实编辑器验证 |
| AC-PHASE-VNE-R2-002 | 导入成功 | 新素材立即出现在库中并能插入/拖动/原生试玩；已存在原图不改；真实资源导入与播放 |
| AC-PHASE-VNE-R2-003 | 重名、坏文件、并发修改、取消及中途写入失败 | 拒绝覆盖/取消不落盘；失败回滚本次写入，保留原登记与导出设置；隔离故障测试 |
| AC-PHASE-VNE-R2-004 | 新素材交付 | 自动进入现有发布名单；隔离导出不漏图片和引用、不带测试草稿或编辑器；旧32用例/原生开篇回归 |

实际交付：本地编辑器0.3.0，顶部导入窗口，背景/新角色/角色表情三种类型；中文名称、PNG/JPG/WebP选择与预览、可选插入当前页；原图只读、自动ID/引用/角色表及Windows导出名单，同名与并发修改拒绝覆盖，备份及写入失败回滚，真实扫描完成后刷新缓存。未实现音视频导入、图集拆分、新NPC/任务。新导入不会绕过原生播放或另建存档权威。

| 本轮验证 | 真实结果 |
|---|---|
| 导入/加载/单元/场景 | tools/check.ps1 -Suite vn-editor -ReportName vn-import-final -TimeoutSeconds 180：40/40用例287断言，0失败/0跳过；160加载及导入exit0。新增8用例覆盖三类素材、中文空格路径、PNG/JPG/WebP、拒绝损坏/非法请求、同名/重复提交、并发配置保护，以及在第1/2/3/4次实际文件写入后故意失败并复原。旧32项开篇/画布/保存/原生播放保持通过。 |
| 真实编辑器 | artifacts/vn-import-20261116/import-editor-fixed.log：33检查/4图，0失败、exit0；真实FileDialog选择信号、确认按钮、图像导入、立即插入和角色缓存刷新，同名拒绝、busy重复提交、取消无登记。图片选择器的操作系统键鼠手选体验仍人工待验收。 |
| 原生播放 | import-runtime.log：9检查/1图、0失败、exit0；用实际新背景/新角色/新表情运行原生Main/Runner/DialogUI，正文/角色名/纹理显示，关闭清单例、无玩家档。 |
| 隔离导出/加载 | export-imported.log：1276资源（含3个临时导入素材）、exit0，完整白名单PASS；import-pack-load.log在空目录从ZIP独立加载三份AtlasTexture，3/3、exit0。编辑器/测试/来源资料不在包内，未覆盖build。 |
| 清理与保护 | imports.json记录测试写入前像及提交哈希；cleanup.ps1逐文件验证并恢复cast/preset，移除三份测试图片及引用和各自.import，不执行递归删除。34原资料SHA256保护，前轮成果/正式剧情保持；临时导入不是新正式角色。 |

AC-PHASE-VNE-R2-001–004工程通过；人工作者体验PENDING，全仓/远程CI NOT_RUN。首轮测试类型错误、空测试库目录扫描错误、图形探针对空备份base64编码产生的ERROR均保留日志，不算通过；分别修正后最终记录如上。外部图片无效时提示失败，不承诺自动去背/裁切；多文件失败可回滚，不宣称进程断电事务原子性。
本轮不重建EXE、不提交推送，root锁释放。入口docs/VN_EDITOR.md；技能来源同本节入口，事实代理只读结束。API依据[EditorFileSystem官方文档](https://docs.godotengine.org/en/4.7/classes/class_editorfilesystem.html)，本项目锁定4.7.2实际执行。下一步等用户导入素材试编，不自动接入新剧情章节。


## D077-R1 · PPT式画布（2026-11-16，LOCAL_EDITOR_READY / AUTHOR_PLAYTEST_PENDING）
USER：希望像PPT插入背景、角色并拖动位置。实际再次使用grilling与godot-gdscript-patterns（来源同下，技能无版本字段），只读事实审查确认原生仅支持横向比例。GRILL_RESULT = NO_BLOCKING_PRODUCT_QUESTIONS：Godot内编辑、复用原生VN已确定，二维坐标和画布形式属于本次明确请求；不改剧情或存档。AI-087-R1记录可逆坐标/页模型选择。

| ID | 来源/输入 | 可观察结果 | 验证 |
|---|---|---|---|
| AC-PHASE-VNE-R1-001 | 用户：像PPT | 默认页缩略图，背景/角色素材选择，点击人物出现选框，鼠标拖动无需填坐标；高级模式保留 | 真实编辑器输入/截图 |
| AC-PHASE-VNE-R1-002 | 用户：拖动位置 | 编辑器和原生播放器使用相同二维布局；缩放窗口不漂移；保存重开/快进/后续台词不重置 | 原生场景集成及画布鼠标 |
| AC-PHASE-VNE-R1-003 | 保留D077无损/开篇保护 | 页操作一次撤销；拖动取消/失焦/切页不残留；不改变未编辑页及原始资料；保存冲突检查继续有效 | 文档与UI测试 |
| AC-PHASE-VNE-R1-004 | 原生VN兼容 | 旧left/right/数字位置及CG/命名保持；无上游版本升级，正式发布包含本地布局支持、不含编辑器 | 回归/导出检查 |

R1实际交付：本地编辑器0.2.0默认页缩略图；点击既有素材卡插入背景/角色、二维鼠标拖动、换表情/等比大小/移除；即时对白、新页/复制/删除、同页撤销重做。原步骤和分支表单在高级模式。新增本地VN CharacterLayer子类与共用几何，保留上游0.23.0代码，正式TXT/CG/命名未修改；四个背景仅引用既有图集，不修改原图。没有以替身替代真实编辑器或播放器。

| 本轮验证 | 实际结果 |
|---|---|
| 导入、加载、规则与原生场景 | `tools/check.ps1 -Suite vn-editor -ReportName vn-slides-final -TimeoutSeconds 180`：导入exit0、160加载exit0，32/32用例216断言，0失败/0跳过、exit0。含旧开篇8项、文档10项、页画布9项、原生播放器5项。 |
| 实际编辑器输入 | `artifacts/vn-slides-20261116/slides-editor-final.log`：43项/3图、0失败、exit0。真实鼠标选取/上下左右拖动、Esc取消，素材卡、页卡、同页撤销/重做、复制/删除、保存重开及独立进程试玩。退出时文件扫描中止警告属于临时剧本清理，不是导入/解析失败。 |
| 高级模式回归 | `advanced-regression.log`及advanced-gpu：35项/4图、0失败、exit0；选项目标、外部修改拒绝覆盖、保存/草稿和Ctrl+Enter继续工作。 |
| 原生播放器图形 | `slides-runtime-final.log`及runtime-gpu：10项/2图、0失败、exit0；实际鼠标翻页，拖动后的X/Y/大小与画布相同，后页/重播正确，无玩家档。 |
| 隔离导出 | `export.log`、`export-check.json`：exit0，1264运行资源，完整发布白名单及新增运行布局/背景齐全；无td_vn_editor、开发入口、测试/草稿或原始资料。只导出隔离ZIP，build/TownDiner.exe与PCK仍为14:44的D076-R1包。 |
| 原资料与协作 | `protected-result.json`：34文件逐字节一致。正式intro、manifest、上游源码无diff，前轮主角成果保留，未提交推送。原先恢复草稿若存在已备份还原。 |

AC-PHASE-VNE-R1-001–004工程通过；人工长篇编排/视觉偏好PENDING，全仓与远程CI NOT_RUN。失败记录保留：首轮类型推断错误；首轮原生布局用例误把GUT方形根窗口当1280×800，已在真实设计尺寸和半尺寸中分别验证；实际UI发现空说话人`:`产生原生警告，改为`narrator:`并加入回归；撤销行锚移动问题修复为保持页序。最终修复不覆盖首轮失败日志。

root共享锁释放。下一步由作者用「剧情」页试编并试玩，后续剧情与新素材登记仍另行集成。技术契约见CONTRACTS D077与AI-087-R1；鼠标坐标依据[官方Control文档](https://docs.godotengine.org/en/stable/classes/class_control.html)并以锁定引擎实际结果为准。

## 以下为D077初版交付记录（历史）

范围：用户请求在 Godot 中像 Galgame 编辑器一样操作。增量提供编辑器主面板；原生 VN Engine 0.23.0、TXT 剧本、CG 场景、游戏存档权威保持。不是替换插件，也不自动把后续全部剧情迁移为原生脚本。

## 入口审查
实际使用 grilling（C:/Users/Administrator/.codex/skills/grilling/SKILL.md，无版本字段）与 godot-gdscript-patterns（同技能根目录）；只读事实工作线 vn_authoring_facts 核实原生语法和宿主耦合，root 唯一修改代码。
GRILL_RESULT = NO_BLOCKING_PRODUCT_QUESTIONS。Godot 内可视化编辑已由上一轮询问明确；使用现有播放器、保留开篇 CG/命名和唯一存档权威已有决定。控件布局、编辑器临时草稿属于可逆实现选择（AI-087）。

## 验收标准
| ID | 来源/输入 | 可观察结果 | 验证 |
|---|---|---|---|
| AC-PHASE-VNE-001 | 用户：简单可视化操作；打开项目 | Godot 顶部剧情页，步骤列表、构图预览、对白/角色/背景字段，新增/删除/排序/撤销/重做 | 原生编辑器图形检查 |
| AC-PHASE-VNE-002 | D072-R1：真实 TXT 权威；原开篇与未知命令 | 未修改打开保存逐字保持；未知语句不丢失；无效标签/资产/命令、损坏开篇交接不可保存 | 单元与真实解析器 |
| AC-PHASE-VNE-003 | 编辑、外部同时修改文件、关闭编辑器 | 校验后备份/替换；外部修改拒绝覆盖；未保存内容有自动恢复草稿与切换确认 | 隔离文件测试/界面 |
| AC-PHASE-VNE-004 | 未保存草稿点击试玩 | 独立进程真实 VN 播放对白、立绘、选择与 CG/姓名；停止重开；正式资源不变，不创建玩家档 | 原生播放器集成/图形 |
| AC-PHASE-VNE-005 | 原开篇正常游戏和导出边界 | 原开篇回归通过；编辑器不加入游戏发布资源；前轮主角和用户资料保留 | 检查入口/清单/哈希 |

## 交付与验证
当前状态：LOCAL_EDITOR_READY / AUTHOR_PLAYTEST_PENDING。AC-PHASE-VNE-001–005 工程检查通过；作者长篇编排体验仍待人工反馈。

实际实现：Godot 原生主屏插件、步骤表单、静态构图、排序/删除/撤销/重做、分支目标下拉、原生校验、保存备份/冲突拒绝、最近草稿恢复、独立窗口试玩。没有测试替身代替播放；试玩使用真实 VN Main/StoryRunner/DialogUI、CG 场景、姓名控件和原生选项。没有改正式剧情文本、上游插件、Profile/存档或玩家玩法。

| 检查 | 实际结果与证据 |
|---|---|
| 导入 / 加载 | 锁定 Godot4.7.2，exit0；158资源加载通过。既有独立实例化 StoryRunner 无 content_root 的 asset_map 警告保留，不是正式宿主缺资源。 |
| 单元 / 集成 | `tools/check.ps1 -Suite vn-editor -ReportName vn-editor-release`：21/21、133断言、0失败/0跳过、exit0；涵盖原开篇8项、文档10项和草稿播放器3项。 |
| 原生编辑器 Compatibility | `artifacts/vn-editor-20261116/editor-gpu-delivery-fixed.log`：35检查/4图、0失败、exit0。实际主屏页、字段/分支下拉、保存、撤销、外部冲突、Ctrl+Enter拉起真实进程。 |
| 真实草稿播放器 Compatibility | `draft-gpu-click-fixed.log`：16检查/3图、0失败、exit0；真实鼠标完成CG恢复/对白/原生分支，姓名替换，取消重开及正式manifest不变。 |
| 导出隔离 | `editor-export-pack-fixed.log`：Windows Framework Demo 隔离runtime.zip导出exit0，1252运行资源；无本编辑器、测试草稿/资料/dev/tests。未覆盖build。 |
| 保护与原成果 | protected-result.json：34份原资料/罗厄文件逐字节相同。D076-R1未提交成果保留，正式intro/manifest/upstream无改动。 |

失败证据保留：首次plugin常量名冲突；测试误用不存在的jump_to（20/21失败后改原生make_choice）；一次错误导出预设名及控件局部变量同名解析错误；编辑器计时器/后台限帧导致两次图形探针超时；真实选项测试未等待原生点击淡出，补足等待后通过。早期35/29图形之前的白块/加载遮罩截图不作为最终视觉结果。

全仓与远程CI NOT_RUN；人工长期编排、音频设备试听 PENDING。没有提交推送；EXE/PCK仍为2026-11-16 14:44的D076-R1包，此工具在Godot编辑器中使用。root共享锁释放，停在本次工具交付点，不自动制作后续剧情。

使用步骤见 [../VN_EDITOR.md](../VN_EDITOR.md)。关键实现为addons/td_vn_editor，检查入口为tools/check.ps1的vn-editor组。API参考 [Godot主屏插件官方文档](https://docs.godotengine.org/en/stable/tutorials/plugins/editor/making_main_screen_plugins.html)，并已在锁定版本实际执行。
# D077-R3 游戏触发配置（2026-11-16，LOCAL_EDITOR_READY / AUTHOR_PLAYTEST_PENDING）

用户确认增加“游戏触发”面板。GRILL_RESULT = NO_BLOCKING_PRODUCT_QUESTIONS：上轮示例范围已确认；grilling 与 godot-gdscript-patterns 实际来源为 C:/Users/Administrator/.codex/skills/<技能名>/SKILL.md，无版本字段。vn_trigger_facts 只读核实接口，root 唯一写入。原港口/教学优先，不向作者暴露跳过教学的任意 beat 修改。完成自定义节点可作下一演出的前置，解锁仅接已存在菜系/商路接口。AI-087-R3：默认一次，关闭不完成，重复播放不重复奖励，地点指已登记场景/五镇，任务节点取现有真实进度；普通退出不保存。

| AC | 输入 | 结果 | 验证 |
|---|---|---|---|
| AC-PHASE-VNE-R3-001 | 保存演出，打开游戏触发 | 中文选择人物/地点/真实任务节点、前置/次数/完成效果，登记稳定ID，重开保留 | 编辑器集成 |
| AC-PHASE-VNE-R3-002 | 正式入口交互/进入/任务完成 | 使用同一原生VN播放；原教学、QTE及模态优先，暂停统一 | 真实Shell集成及图形 |
| AC-PHASE-VNE-R3-003 | 正常完成/取消/重复回调/切槽 | 只完成一次效果，取消不完成，存档隔离，旧档缺字段可读，损坏拒绝 | 规则及Profile往返 |
| AC-PHASE-VNE-R3-004 | 未发布草稿/有效登记/非法配置 | 只打包正式登记与原开篇；配置/循环依赖/引用拒绝，失败保留原文件 | 导出及文件事务 |

本轮001–004工程检查PASS。实现：中文触发表单、单JSON备份与冲突校验、循环依赖拒绝、稳定ID、Profile可选内部v1及旧档兼容、原生独立章节播放、镇上/餐厅人物交互、五镇及主店地点观察、真实任务节点派生、J节点与重试、取消/世代令牌/一次效果、菜系/商路正式接口。原剧情/服务交互/模态/QTE/装修/暂停优先。运行定义默认空表，不把验证用示例作为正式剧情。没有测试替身代替真实播放器；固定对话只用于隔离验收。

| 检查 | 实际结果/证据 |
|---|---|
| 检查入口 | `tools/check.ps1 -Suite vn-editor -ReportName vn-triggers-interaction`，53/53、398断言、0失败/0跳过、exit0；161加载，包含本轮13用例和原40项回归。真实Shell、原生Runner、餐厅食客交互、港口旅行、保存与旧档验证。 |
| 真实编辑器 | editor-config.log：14项1图，exit0；配置、保存、重开、取消不提交、开篇保护。 |
| 最终真实游戏Compatibility | game-trigger-final.log：18项1图，exit0；真实进入餐厅触发、时间冻结、取消重试、正常返回、菜系效果、保存/重载不重复、清理单例。 |
| 最终导出与加载 | registered-export-final.log：1268资源，严格白名单PASS，包含一个临时登记演出、排除同目录未发布草稿。pack-load-final.log空目录实际包加载4项、exit0，无源工程文件依赖。未覆盖build。 |
| 清理/保护 | protected-result.json：34份原资料一致；临时登记按哈希恢复、两份临时剧本逐文件删除，恢复原作者草稿。clean-load.log：161加载、exit0。 |

首轮49/50失败源于测试夹具直接设小屋unlocked但未设床边锚点，改走真实unlock_residence；第二轮49/50暴露JSON数值恢复为浮点，运行完成计数现规范为整数，第三轮50/50通过；增加真实餐厅交互/旅行/对话装修保护后最终53/53。失败日志全部保留，不冒称首轮通过。独立实例化StoryRunner的既有asset_map无宿主警告保留，正式播放与包内资源正常。全仓与远程CI NOT_RUN，用户编排/玩法/设备体验PENDING。

复现（最多5步）：保存新章节 → 游戏触发选择“进入地点/主店餐厅”与“港口介绍完成” → 保存触发 → Godot运行并从港口进入餐厅 → 正常结束后主动保存，再载入确认不重播。取消后重新进入可重试；如用任务节点可在J重试。导出游戏需另行重新打包；当前EXE仍为14:44前轮包。未推送、未自动接入后续正式剧情，本轮到此停止。
# D077-R5 画外构图（2026-11-17，LOCAL_EDITOR_READY / AUTHOR_PLAYTEST_PENDING）

GRILL_RESULT = NO_BLOCKING_PRODUCT_QUESTIONS。依据：用户明确要求提高角色倍率及允许画外站位，编辑和原生播放已有共同TDVNLayout，不涉及剧情/存档决策。已读取C:/Users/Administrator/.codex/skills/grilling/SKILL.md和godot-gdscript-patterns/SKILL.md（未标版本），只读vn_canvas_bounds_facts核查限制与恢复路径。AI-087-R5（ASSUMPTION，可调）：倍率0.25–5，中心X/底边Y允许-10–11个设计画幅，画布视图10%–100%；仅限制极端无意义坐标，正常拖动不再夹在画内。

| AC | 来源/输入 | 可观察结果 | 验证 |
|---|---|---|---|
| AC-PHASE-VNE-R5-001 | 用户本轮，选角色并放大/拖出四边 | 最大5倍，画外仍可编辑；可缩小画布、从列表找回并居中 | 规则及真实编辑器输入 |
| AC-PHASE-VNE-R5-002 | 修改本页、取消/撤销/保存重开 | 一次拖动一次撤销，后页不变；坐标及倍率原样恢复 | 文档往返及编辑器 |
| AC-PHASE-VNE-R5-003 | 大倍率/画外原生show/move/恢复/缩窗 | 编辑器与播放器共用几何，播放及缩略图裁到实际画面；旧站位不变 | 原生场景及GPU |
| AC-PHASE-VNE-R5-004 | 损坏/无穷坐标与本地既有内容 | 非法数据拒绝；34保护文件、正式开篇/登记及恢复草稿保持 | 检查入口/哈希核对 |

001–004工程检查PASS；没有用替身替代真实VN运行。工具0.6.0，原生0.23.0不变。已取消整个人物框必须在屏内的限制；增加倍率输入、编辑视图缩放、画外列表找回/居中，缩略图按实际画框遮罩；旧left/right及原td坐标数值不变。

| 实际检查 | 结果与证据 |
|---|---|
| 导入/加载/单元/集成 | `tools/check.ps1 -Suite vn-editor -GodotPath F:/MyGameTBD/artifacts/vn-framework-20261113/engine/godot.exe -TimeoutSeconds 240 -ReportName vn-canvas-final`；62/62、506断言、0失败/跳过、161加载，各阶段exit0。 |
| 真实编辑器Compatibility | artifacts/vn-canvas-20261117/editor-first.log；22检查/3图、exit0。实际鼠标拖出右/上边、撤销重做、列表找回、倍率、居中、Esc取消、真实TXT保存重开。单元另覆盖四边及三种画布缩放。 |
| 真实原生播放器Compatibility | runtime-first.log；12检查/3图、exit0。两倍近景、完全画外移动、内存预览释放、缩略图留边像素裁切。场景测试另覆盖五倍show、move、恢复与缩窗。 |
| 内容保护 | protected-result.json；34保护文件加正式intro/事件登记/原恢复草稿共37项逐字节一致，测试剧情逐文件移除；D076未提交内容保留。 |

首轮61/62失败：测试用@move写成`in 0`，上游实际语法为`over 0`，导致检查发生在0.4秒动画中途；修订测试夹具为真实语法后完整62/62通过，失败日志保留。图形证据经查看，倍率/画外构图符合目标；编辑器第二窗口提示已有调试端口占用，不影响此轮场景/图形检查。全部检查有非零用例及真实退出码，不将本轮专项记为全仓通过。

复现：重新打开Godot项目 → 剧情页插入角色 → 右侧调倍率（最多5倍） → 缩小上方画布并拖到暗区 → 用本页角色列表选回，或保存/试玩核对。未重建EXE、未提交推送；全仓/远程CI/导出本轮NOT_RUN，人工连续编排PENDING。root本轮锁释放，停止在本次编辑器修正。
