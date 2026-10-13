# 三人合作开发规范

版本：2026-10-13 v1。

本规范适用于最多三名程序成员。它规定目录所有权、分支、工作树、工作单、契约、测试、交接和合并方式。Phase 4 的具体任务仍以 `doc/agent_prompts/Phase_4.md` 为准；本文件不构成开工授权。

机器可读所有权在根目录 `collaboration.config.json`，自动检查入口是 `tools/collab.ps1`。两者与本文件冲突时，先停止合并，由当波集成者统一修订三处，不能私自选择有利版本。

## 1. 固定三条工作线

### 做菜与研发 `cook`

负责：

- 做菜模型、QTE、厨房、评分；
- 固定工序、熟练度、研发和低 SAN 入锅变换；
- 做菜内容定义及对应单元/厨房集成测试。

不得直接修改世界会话、经济账、主入口或公共契约。

### 经济与供货 `economy`

负责：

- 库存、订单经济、市场、调料、店型规则；
- 分店模拟、品牌、全球影响力和经营存档规则；
- 对应业务、存储和经济测试。

不得在 UI 直接加钱、扣料或伪造菜品结果。

### 小镇与事件 `town`

负责：

- 餐厅、小镇、NPC、服务流程、事件、市政、装修和引导表现；
- 客流、实体客人、事件场景和对应测试；
- 调用公开做菜/经济边界，不复制规则。

不得在场景脚本中重新实现评分、库存或市场公式。

三人只对应职责，不绑定真实姓名。成员更换时只更新 `CURRENT_WAVE.md`，不改角色 ID。

## 2. 轮值集成者

每个波次由三人之一兼任集成者，不增加第四个人。

集成者拥有：

- 共享文件的唯一写权限；
- 集成分支和集成工作树；
- 合并顺序、冲突处理和全量验证；
- 阶段记录和断点更新。

集成者不拥有：

- 擅自修改产品范围的权力；
- 在集成分支替其他工作线完成大块功能的权力；
- 把失败测试、未试玩或冲突隐藏为通过的权力。

Phase 4 轮值沿用 `docs/COLLABORATION.md`：4-0/4-1 为 town，4-2 为 economy，4-3 为 cook。后续波次在开工前写入 `CURRENT_WAVE.md`。

## 3. 文件所有权和共享锁

角色分支只能改 `collaboration.config.json` 中自己的 `owned_patterns`。

下列内容属于共享锁：

- `project.godot`、导出、依赖和 CI；
- `src/app/`、`src/contracts/`、`src/platform/`；
- 世界总会话、SAN 旧入口和 active 内容；
- 公共契约、阶段状态、决策、架构和总规划；
- 检查/导出工具及跨线集成测试。

共享文件只能在集成分支修改。工作线需要共享改动时：

1. 在工作单写“共享改动提案”；
2. 给出调用方、提供方、字段、单位、错误码、幂等和迁移影响；
3. 在自己的目录提供实现和边界测试；
4. 交接时由集成者在共享文件落地。

紧急修复也不允许两个人同时打开同一个共享文件。集成者先在 `CURRENT_WAVE.md` 登记锁，再开始修改。

## 4. 分支和工作树

每波有四个分支、四个工作树，但仍是三个人：

- 集成：`integration/phase-{phase}-wave-{wave}`；
- 做菜：`work/cook/phase-{phase}-wave-{wave}`；
- 经济：`work/economy/phase-{phase}-wave-{wave}`；
- 小镇：`work/town/phase-{phase}-wave-{wave}`。

集成工作树由当波集成者在合并日使用，不是第四条功能线。

规则：

1. 三个角色分支都从该波集成分支建立。
2. 角色 PR 只合到该波集成分支，不能直接合到 `main`。
3. 集成 PR 才能从集成分支合到 `main`。
4. 一个工作树只检出一个分支；三个人不能共用同一工作目录。
5. 新波次必须从已提交、已同步、可复现的基线建立。
6. `tools/collab.ps1 -Action Init` 拒绝脏工作区，避免未提交文件只存在于某个人电脑。
7. 初始化脚本不提交、不推送、不创建 PR。

## 5. 波次生命周期

### 第一步：Ready

集成者填写 `CURRENT_WAVE.md`：

- Phase、波次、基线提交和集成者；
- 三条线的工作单；
- 本波 AC、来源和 AI 编号；
- 共享契约清单；
- 禁改文件和明确延期项；
- 计划运行的检查。

满足以下条件才是 Ready：

- 产品规则已在决策/AI 总表中找到来源；
- AC 有输入和可观察结果；
- 文件归属无重叠；
- 提供方/调用方和合并顺序明确；
- 存档、随机、幂等和旧档影响已判断；
- 没有要求成员同时改同一共享文件。

### 第二步：Contract

跨线功能先完成契约：

1. 提供方在自己的工作单列出数据结构和失败语义；
2. 调用方确认能否消费；
3. 集成者把确认结果写入 `docs/CONTRACTS.md` 的 `PLANNED` 段；
4. 两边先写边界失败测试；
5. 字段冻结后才能实现。

普通内部重构不需要全员问答，但不能改变公开语义。

### 第三步：Develop

每名成员：

- 一次只处理一个工作单；
- 先写失败测试，再实现最小可用纵向路径；
- 每天开始前确认计划修改文件；
- 每次提交保持单一目的；
- 下班前运行本角色检查并更新工作单；
- 不把孤立类、假按钮或预制成功结果当完成。

推荐提交格式：

`type(scope): 简短结果`

允许的 `type`：`feat`、`fix`、`test`、`refactor`、`docs`、`chore`。

### 第四步：Handoff

角色完成后复制 `templates/HANDOFF_TEMPLATE.md`，记录：

- 实际变化和没有做的内容；
- 提供的公开入口；
- 修改文件；
- 测试命令、数量和结果；
- 存档/随机/幂等风险；
- 共享文件提案；
- 集成复现步骤。

没有真实测试结果的交接只能标 `NOT_RUN/BLOCKED`，不能写“应该通过”。

### 第五步：Review

每个角色 PR 至少由另一条线的一人审查。审查重点：

- 是否越权改文件；
- 是否符合 AC 和来源；
- 是否绕过规则层；
- 是否破坏模板/实例隔离；
- 是否存在重复扣料、发钱、结算、领奖或随机重抽；
- 测试是否验证真实边界；
- 是否把人工体验冒充自动通过。

跨契约或存档变更须由三人都确认后合并。

### 第六步：Integrate

合并日：

1. 三个角色分支停止写入；
2. 集成者按依赖顺序合入提供方，再合入调用方；
3. 冲突在集成分支处理，不回到共享主工作区抢改；
4. 集成者实现共享装配，不重写角色核心；
5. 跑专项套件、真实场景和全量检查；
6. 更新 CONTRACTS、PROJECT_STATE、阶段报告和 CURRENT_WAVE；
7. 仍失败时保持集成分支，不合到 `main`。

### 第七步：Close

满足 Definition of Done 后才能关闭波次：

- 所有计划 AC 有状态和证据；
- 角色所有权检查通过；
- 公开契约与实际实现一致；
- 必跑测试无失败、跳过、解析错误和超时；
- 真实入口已接通；
- 存档迁移和幂等风险有测试；
- 人工项明确为 PASS 或 PENDING；
- 下一断点准确；
- 没有自动开始下一波。

## 6. 测试责任

角色分支至少运行 `collaboration.config.json` 的 `required_suites`。如果改到真实场景，还要运行对应集成测试。

集成分支必须运行：

1. 三条线报告的专项命令；
2. 跨线真实场景；
3. `tools/check.ps1` 全量入口；
4. 涉及存档时的中断/坏档/未知版本；
5. 涉及随机时的固定种子和读档不重抽；
6. 涉及 UI/QTE 时的图形或人工项，无法执行则如实记录。

本地通过不代替远程 CI，自动输入不代替实体设备，规则测试不代替真实场景。

## 7. PR 和合并规范

PR 必须使用 `.github/PULL_REQUEST_TEMPLATE.md`，并满足：

- 标题包含 Phase、波次、角色和结果；
- 正文引用 AC、来源/AI 编号和工作单；
- 只包含一个角色所有权范围；
- 说明是否有共享改动提案；
- 粘贴真实测试摘要，不只写命令；
- 标记人工试玩状态；
- 不混入格式化全仓、依赖升级或无关清理。

禁止：

- 角色分支直接合 `main`；
- 强推覆盖别人历史；
- 用 `git reset --hard` 或 checkout 丢弃他人改动；
- 通过删测试或降低 AC 让检查变绿；
- 未授权时由 Agent 自动提交、推送或发布。

## 8. 冲突和阻塞

冲突优先级：

1. 用户最新决定；
2. 1013 会议；
3. 设计大纲；
4. 带编号 AI 填充；
5. 当前契约；
6. 普通实现偏好。

处理方式：

- 产品冲突：停止受影响实现，记录到 DECISIONS；
- 接口冲突：回到 Contract 步骤，不在调用方猜字段；
- 文件冲突：由集成者处理，角色成员不互相覆盖；
- 测试冲突：保留最严格且符合当前 AC 的测试；
- 人员不足：缩小波次，不让剩余成员无授权跨线。

## 9. 工具使用

只校验配置：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/collab.ps1 -Action Validate
```

查看 Phase 4 第 0 波预期分支和现有工作树：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/collab.ps1 -Action Status -Phase 4 -Wave 0
```

在基线已提交且工作区干净后，预演创建：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/collab.ps1 -Action Init -Phase 4 -Wave 0 -BaseRef main -WhatIf
```

实际创建：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/collab.ps1 -Action Init -Phase 4 -Wave 0 -BaseRef main
```

角色本地检查未提交改动：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/collab.ps1 -Action Check -Role cook `
  -BaseRef integration/phase-4-wave-0 -IncludeWorkingTree
```

工具兼容 Windows PowerShell 5.1 和 PowerShell 7；CI 使用 `pwsh`。CI 会根据分支名自动检查所有权和 PR 目标：角色分支只能进入同波集成分支，集成分支只能进入 `main`。非协作分支只提示跳过，不影响历史维护流程。

## 10. 当前状态

当前仓库还没有启动 Phase 4，`CURRENT_WAVE.md` 为 `IDLE`。现有工作区包含未提交改动，因此不应立即运行 `-Action Init`。先由用户决定提交边界，再从明确提交创建工作树。
