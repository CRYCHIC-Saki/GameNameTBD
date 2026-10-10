# 分工与集成基线

## D020 本轮文件归属与验证入口

主开发/集成角色负责project.godot、ShopView、FullKitchen与共享契约；本轮仅委派grilling要求的只读事实审查，无外部任务/推送。后续烹饪线修改Model/Handling，QTE线修改controller/beat_sheet/GuidedView，经营线修改ShopSession/Store/Catalog；跨线先更新CONTRACTS与AC，再由集成角色验证。

独立检查：tools/check.ps1 -Suite business（含test_kitchen_freedom）、-Suite qte、-Suite service；完整入口不变。新静态方法season_prompt可独立验证UI状态；真实F/Q/E、切型按钮和鼠标长按必须在service场景测试中验证。

## Phase 2当前协作边界

D019延续同一文件归属：本轮只有集成负责人写入。共享新增接口为CookingSession.set_material_sink/select_recipe、Lane.use_recipe_profile、ServiceCatalog.request_profile/material_needs、ShopSession.consume_materials/sync_kitchen/context_for_ingredients/first_order_for。移除旧begin_order/consume_total；业务独测和真实营业入口仍分别使用business/service套件，无新增全局管理器。

本轮仅集成负责人写文件，grilling事实审查Agent只读，无外部任务分派。经营规则负责人可修改 `src/business/shop_session.gd` 和对应规则测试；内容负责人可修改 `service_catalog.gd` / `content/service_content.json`；存储负责人拥有 `src/platform/shop_store.gd` 和中断恢复测试；应用集成负责人拥有 `shop_view.gd`、main、FullKitchen接入、世界显示名、工具、共享契约和导出白名单。角色不是编造的团队成员。

公开接口见CONTRACTS的Phase2部分。独立规则/存储：`tools/check.ps1 -Suite business`；营业真实场景：`-Suite service`；原做菜/QTE/评分套件继续独立运行。生产入口为 `tools/run.ps1`，Phase1独立厨房为 `-FullKitchen`。改变钱料语义或场景连接先改契约与AC，由集成负责人统一合入，再运行全量和真实场景；不让业务UI绕过Session直接改钱料。

Phase2允许最简方案命名保存并上架，覆盖下方Phase1移除配方库菜单的旧范围。旧dev入口与TEST_ONLY内容仍不是营业菜单。下方分工及证据路径是历史索引。

## D016增量分工

本轮集成负责人统一写入；grilling事实审查Agent只读。内容线拥有菜谱preparation_sheets与逐拍行/预告，QTE线拥有cut_actions、last_judgement及长按生命周期；厨房线拥有反馈缓存、菜谱传递和双锅鼠标预约；视图只读取。新增 `test_recipe_performance.gd` 进入qte套件，真实入口仍在test_guided_kitchen。验证使用check.ps1；新版图形证据前缀为artifacts/d016-*，不要混用旧六刀截图。本轮不自动提交或推送。

## 当前D015协作入口

文件归属继续沿用下表角色；本轮只有集成负责人写文件，事实审查Agent只读。规则线追加 `module_scores/steps.module`、真实勾芡材料；内容线管理 `pc_operations.document_sheets/document_weights` 和材料柜；QTE线管理编译后拍点与窗口；厨房/UI线拥有 `guided_cooking_view.gd`、自动功能位路由与M5跨界面HUD。共享场景、主菜单、导出与检查脚本由集成负责人统一修改。

独立入口仍用check.ps1的content/cooking/qte/scoring/integration；本轮专项为 `test_document_operations.gd` 和 `test_guided_kitchen.gd`。图形复现用 `tools/guided_visual_check.gd`，不能拿旧pc_visual_check的自由工序截图充当当前验收。主菜单移除了历史回归按钮，开发者仍可显式用run.ps1的-Module/-Cooking启动旧入口；完整生产流用-FullKitchen。

接口变更核对CONTRACTS的D015部分→边界测试→实现双方→全量检查/真实场景→记录证据。未分派任何外部任务。文档以下描述的自由工序、配方库菜单等为历史基线，当前玩家范围以D015为准。

## 当前D014文件归属

| 工作线 | 本轮公开边界与文件 | 独立验证 |
|---|---|---|
| 规则/内容 | cooking_model.gd的transfer_to/并行结果提交；cooking_catalog.gd与cooking_system.json的PC配置 | check.ps1 -Suite cooking / content；test_pc_cooking |
| QTE | cooking_qte.gd、beat_sheet.gd、temperature_view.gd、cooking_action_view.gd；过程帧与结果，不修改菜品 | check.ps1 -Suite qte；test_pc_operations |
| 世界与厨房集成 | world的稳定station_id；kitchen_handling.gd、cooking_lane.gd、full_kitchen.gd的所有权/输入编排 | check.ps1 -Suite integration；test_pc_kitchen；run.ps1 -FullKitchen |
| 存储/节拍 | recipe_library.gd兼容方案1/2；beat_audio.gd局部循环音轨 | check.ps1 -Suite platform / cooking |

共享配置、世界场景、导出清单、工具及文档由集成负责人统一合入；修改控制器结果字段必须同时修改模型边界测试，不能在视图补写结果绕过校验。上表为角色分工，没有自动向外部派任务。PC集成使用真实Viewport键鼠事件、模型和评分；旧full_kitchen测试显式选择legacy配置作为兼容回归，不替代PC场景验收。图形工具为tools/pc_visual_check.gd，物理设备验收另列。

## 既有分工约定（保留）

当前D013完整系统已采用v3，活动配置是content/cooking_system.json；完整接口见systems/cooking.md。下面旧原型说明仅保留历史。集成负责人拥有src/app、full_kitchen.gd、project.godot、工具和导出；世界/动作工作线分别src/world＋assets/kitchen、src/qte；规则线src/cooking＋src/content；配方库src/platform。独立套件入口已纳入full_*新增测试，完整厨房独立运行`tools/run.ps1 -FullKitchen`。共享接口变更先改systems/cooking.md及边界测试，再由集成负责人统一导入/全量验证。

Phase1增量契约见PHASE1_INTERFACES.md。原型唯一活动数据为content/cooking_prototype.json；dev_samples.json仅供既有探针。content/cooking/qte/integration套件已纳入所有新增测试；评分独立入口为`tools/check.ps1 -Suite scoring`，原型独立运行`tools/run.ps1 -Cooking`。实际菜品评分已完成，旧NOT_IMPLEMENTED只适用于非菜品探针。

负责人均为角色标记，未指定具体团队成员。此文件只约定协作边界，不向外部分派任务。开始多人工作前由集成负责人分配互不重叠文件。

| 工作线 / 角色 | 可修改目录 | 公开边界 | 独立检查入口 |
|---|---|---|---|
| 烹饪核心负责人 | src/cooking、tests/unit/test_session.gd | TDRequest / TDFrame → TDOutcome / TDSnapshot | tools/check.ps1 -Suite cooking |
| QTE负责人 | src/qte、tests/unit/test_time_qte.gd | input/advance/release_input/cancel；注入Clock和随机源 | tools/check.ps1 -Suite qte |
| 内容配方负责人 | src/content、content、tests/unit/test_content.gd | 版本化配置→校验目录→分离模板 | tools/check.ps1 -Suite content |
| 独立评分负责人 | src/scoring、tests/unit/test_customer_scoring.gd | evaluate只读快照，不回写实例 | tools/check.ps1 -Suite scoring |
| 基础设施负责人 | src/platform、tests/unit/test_storage_scoring.gd | 时间/随机/存储返回明确错误 | tools/check.ps1 -Suite platform |
| 厨房集成负责人 | src/kitchen、tests/integration | 依赖注入、输入路由、界面结果、生命周期 | tools/check.ps1 -Suite integration；tools/run.ps1 -Module |
| 应用/集成负责人 | src/app、dev、project.godot、export_presets.cfg、tools、CI、锁文件 | 唯一场景装配入口 | tools/check.ps1；tools/export.ps1 |

共享文件：src/contracts/*、AGENTS.md、项目规范/状态/决策、架构/契约文档、阶段记录，由集成负责人合入。其他角色提出改动，不各自复制一套公共类型或重建工程。

接口变更流程：
1. 给出受影响AC、来源/已确认决定、兼容性影响；只有真正产品阻塞才问用户。
2. 先更新docs/CONTRACTS.md与双方边界测试，约定字段版本、单位、错误码与重复调用语义。
3. 实现提供方与调用方；跑各自套件，再跑all与真实场景集成。
4. 共享场景由集成负责人合入；检查接口没有经由全局Manager或硬编码跨场景路径绕开。
5. 更新阶段证据与未验证项。变更引擎/依赖、重大玩法或阶段范围须有用户明确决定。

测试不需要全量游戏/世界数据，只加载原型或明确DEV_ONLY探针。测试存储在artifacts，与真实设置隔离。FixedRandom只用于Phase0依赖边界测试；Phase1集成使用真实目录、会话、控制器、输入与评分。人工设备体验另列。

构建是Phase0开发演示包。export_presets.cfg显式列运行资源，独立dev/module_test.tscn、工具、GUT、测试、源设计文档不导出；当前菜单中的开发厨房是演示包的明确运行功能，未来正式发行需另立正式内容清单。
