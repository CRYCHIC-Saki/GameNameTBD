# 设计来源索引

原资料保持原位置，只读。已阅读最初五份资料，并按最新用户要求完整阅读做菜操作.md；每次交付重新核对指纹。案例数值不当作已确认平衡。

| 文件 | 作用 | SHA256 |
|---|---|---|
| doc/source/美食游戏设计大纲_v0.2_重写版.md | 机制定义、建议值、旧P0–P4阶段 | 331F1A92235CC08566CE7DEBFCA278C27D94323A243BA9975EB0F02923101412 |
| doc/source/Onboarding 剧本（具体案例）.md | 玩家旅程和引导案例，不作数值真值 | 433B2064E91525D4CFE7F853029730DD3E9E178104E3B418332AEC5CB025CB61 |
| doc/source/towns.json | 候选城镇/菜品内容，75城镇217菜品；不是完整运行库 | 6FF947E8BAAFD7D3916DB5B346EB6D8F183C201E47312926256C9114B4F9FD95 |
| doc/source/低SAN食谱.md | 地域料理、Tier与特殊钩子 | 3B89180E43ADCE8A591190AADA9C08FFF6277D7D0BC52966C3DED49F7F354D6D |
| doc/source/游戏成就系统.md | 未来可观察行为与成就素材 | 9938B5192303C0A986F559AEAA5211AB6B85CE81CD4ABFAE6823D0DE8F7DC023 |
| doc/source/做菜操作.md | 最新PC操作M1–M7、节拍表、键鼠并行及HUD；用户明确要求据此实现 | 67E6E1D1E15090B0BB736FEABEDAE87F67DCF930E41631598EE0437AB3D1643D |
| doc/source/1013会议纪要.txt | 2026-10-13 小组会议。修订 Phase 3 之后的方案，不覆盖已落地的 D021–D026 | FC1B9B70FB4B7E212FDEC28D85F8D06AE0E672E6E615E0569F6C501DEF4659EA |

开发规范原入口：doc/agent_prompts/00_PROJECT_PROTOCOL.md；工程持久入口：docs/DEVELOPMENT_PROTOCOL.md。
近期范围：Phase 3 开发已完成。Phase 1–6 新版总入口是 `docs/FULL_IMPLEMENTATION_FLOW.md`，逐阶段提示是 `doc/agent_prompts/Phase_1.md` 至 `Phase_6.md`，AI 补充总表是 `docs/AI_FILLED_DETAILS.md`。下一阶段是 D028 版 Phase 4，三波任务仍在 `docs/phases/plan-1013.md`。D021–D026 的餐厅、客流、分店和传菜继续有效，直到对应波次改掉调用。D020 的切型、取回和探索解锁，以及 D015/D016 的自动工序和逐拍表，继续作为做菜基线。

来源优先级：1013 会议明确内容优先；会议未说明时用《美食游戏设计大纲 v0.2》；两者都模糊时只能使用 `docs/AI_FILLED_DETAILS.md` 中带编号的 AI 填充。其他资料用于内容候选、案例或历史实现，不能覆盖该顺序。建议值、PROPOSED 和 AI 填充都不是用户原话。未决冲突见 DECISIONS.md。

Phase0/旧原型未制作电子表格或正式素材。后续完整Phase1按用户要求实际调用imagegen生成厨房背景与透明厨师，来源与提示词见assets/kitchen/README.md；grilling、godot-gdscript-patterns实际使用记录见阶段报告。本轮未涉及Spreadsheets/visualize/skill-creator任务。原文指纹复核见artifacts/source-verification.json。

D014复用既有像素资产，新增原生Godot占位功能位/动作，未重新调用imagegen。六份资料最终复核全部匹配：artifacts/pc-source-verification.json。

D016继续复用像素资产，改Godot谱面/判定/反馈与时间，不新增正式美术。六份资料复核全部匹配：artifacts/d016-source-verification.json。

D020继续复用像素资产，增加Godot原生垃圾桶、材料气泡与调味状态绘制；六份资料复核全部匹配：artifacts/d020-source-verification.json。新汽锅鸡定量数据来源与建议值见docs/systems/business.md，不改原始towns.json。
