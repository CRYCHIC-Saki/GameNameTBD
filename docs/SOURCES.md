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

开发规范原入口：doc/agent_prompts/00_PROJECT_PROTOCOL.md；工程持久入口：docs/DEVELOPMENT_PROTOCOL.md。
近期范围：当前为Phase2，D020用户答复优先：选切型后按谱、订单外自由烹饪、保留处理状态的食材退回、锁定汽锅鸡探索及失败菜处理。D019统一冰箱、自动订单、长按调味继续复用；D015/D016中台面、自动工序、逐拍排布、双锅和简化HUD仍按做菜操作.md §3–7复用。汽锅鸡菜名/汽蒸来源于towns.json相应条目，定量配方与平衡参数标PROPOSED，不改原文。doc/agent_prompts/Phase_1.md和Phase_2.md为机制参考，范围冲突见DECISIONS。

来源优先级：用户最新明确决定与已确认决策可修订旧设计；大纲机制、附录内容和Onboarding案例分别溯源；建议值与实现假设不是用户产品决定。未决冲突见DECISIONS.md。

Phase0/旧原型未制作电子表格或正式素材。后续完整Phase1按用户要求实际调用imagegen生成厨房背景与透明厨师，来源与提示词见assets/kitchen/README.md；grilling、godot-gdscript-patterns实际使用记录见阶段报告。本轮未涉及Spreadsheets/visualize/skill-creator任务。原文指纹复核见artifacts/source-verification.json。

D014复用既有像素资产，新增原生Godot占位功能位/动作，未重新调用imagegen。六份资料最终复核全部匹配：artifacts/pc-source-verification.json。

D016继续复用像素资产，改Godot谱面/判定/反馈与时间，不新增正式美术。六份资料复核全部匹配：artifacts/d016-source-verification.json。

D020继续复用像素资产，增加Godot原生垃圾桶、材料气泡与调味状态绘制；六份资料复核全部匹配：artifacts/d020-source-verification.json。新汽锅鸡定量数据来源与建议值见docs/systems/business.md，不改原始towns.json。
