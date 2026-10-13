# 《小镇食堂》Godot 分阶段开发提示词包

## 使用顺序

首次直接把 `START_Phase_0.md` 的全部内容交给有仓库读写能力的开发 Agent。该文件已经合并总控规范与 Phase 0，无需再发两遍提示词。

Phase 1–6 的 v3 总方案入口是：

- `docs/FULL_IMPLEMENTATION_FLOW.md`：完整顺序、状态、依赖和来源覆盖；
- `docs/AI_FILLED_DETAILS.md`：所有 `【AI填充细节 AI-xxx】`；
- 本目录的 `Phase_1.md` 至 `Phase_6.md`：每阶段可执行提示。

产品来源顺序：

1. `doc/source/1013会议纪要.txt`；
2. `doc/source/美食游戏设计大纲_v0.2_重写版.md`；
3. `docs/AI_FILLED_DETAILS.md`。

1013 会议未明确的内容才使用大纲；两者都模糊时才使用带编号的 AI 填充。AI 填充不能冒充用户原话。

当前状态：

- Phase 1、2 工程基线已完成，人工试玩仍有待办；
- Phase 3 已由小组确认开发完成，人工试玩仍为 `PENDING`；
- Phase 4 是下一阶段，执行 1013 会议的研发、自动化、市场、店型、调料、市政和事件三波；
- Phase 5 完成食品品牌成长和首发内容；
- Phase 6 做发布候选。

不要机械地从 Phase 1 重跑。先看 `docs/PROJECT_STATE.md`，只执行当前未完成 Phase。Phase 3 的 D023–D026 历史验收保存在 `docs/phases/phase-4.md`，但在小组口径中仍计入已完成的 Phase 3。

每阶段开头读取持久化规范和已有决定，并使用当前环境实际可用的 Grill Me skill；没有技能时明确报告并执行等价审查，不能假称已调用。

将五份原始资料放入该 Agent 可读取的位置；建议为项目的 `docs/source/`。提示词不假定聊天附件会自动出现在其他软件或仓库里。

阶段内由 Agent 完成小步实现、测试、修复；阶段结束后由用户试玩并决定是否推进。换会话或中断后使用 `RESUME_CURRENT_PHASE.md`。需要审查当前阶段时使用 `REVIEW_CURRENT_PHASE.md`。

## 文件说明

`00_PROJECT_PROTOCOL.md` 是总控规范原文；阶段0会把它的内容保存进工程并合入AGENTS入口。不要把本包里的某个文件直接覆盖项目已有的AGENTS.md。

提示词中的 `当前状态` 以工程记录为依据，未来任务仍只是计划。没有代码和真实测试证据的条目不能写成已实现。原始资料保持只读。

当前环境中的Grill Me版本可能与公开仓库不同，必须读实际SKILL.md；决策落盘和实施闭环由总控驱动层负责，不能假定技能本身有这些能力。

参考依据见 `REFERENCES.md`。本包未运行游戏测试，不声称已验证未来实现的可玩性。
