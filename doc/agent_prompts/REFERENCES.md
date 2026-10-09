# 资料与技术依据

## 用户提供的设计资料

- 《美食游戏设计大纲_v0.2_重写版.md》：§3.1口味矩阵、§3.6食谱、§3.7客人评分、§4工序/QTE、§6 SAN、§8经营、§10技术建议与原阶段。
- 《Onboarding 剧本（具体案例）.md》：B.2番茄炒蛋与细碎度陷阱、雇人、分店、低SAN和融合创作；B.3引导原则。
- `towns.json`：meta字段说明与各小镇的文化、偏好和菜品资料。它不是完整运行时食材/口味数据表。
- 《低SAN食谱.md》：A.0消耗分级、A.7原创阴暗菜、A.8设计要点。与其他资料冲突处应保留并由项目决策。
- 《游戏成就系统.md》：分类成就与对应条件。

提示词没有静默统一五维/六项属性、SAN数值或主支线冲突；首发规模、程序结构、测试门槛和阶段产物属于本套提示词的工程建议，不是原文的既定承诺。

## 公开技术资料（2026-10-09核对）

下面列出检索时使用的来源。真正实施时以项目锁定版本及实际安装的技能为准，不把stable或main链接当作永久版本锁。

```text
Grill Me作者仓库的使用说明：
https://github.com/mattpocock/skills/blob/main/docs/productivity/grill-me.md
Grill Me当前技能入口（可能委托其他skill）：
https://raw.githubusercontent.com/mattpocock/skills/main/skills/productivity/grill-me/SKILL.md
Godot：场景组织
https://docs.godotengine.org/en/stable/tutorials/best_practices/scene_organization.html
Godot：Autoload与普通节点
https://docs.godotengine.org/en/stable/tutorials/best_practices/autoloads_versus_regular_nodes.html
Godot：Resource及缓存、复制行为
https://docs.godotengine.org/en/stable/classes/class_resource.html
Godot：命令行与headless
https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html
Godot：音画同步
https://docs.godotengine.org/en/stable/tutorials/audio/sync_with_audio.html
Godot：版本控制
https://docs.godotengine.org/en/stable/tutorials/best_practices/version_control_systems.html
GUT：命令行（仅作已查阅版本，不强制本项目使用9.7.0）
https://gut.readthedocs.io/en/v9.7.0/Command-Line.html
```

Grill Me公开实现可能无状态、不写文件；本套提示词的决策文档由外层项目流程维护。GUT文档说明pending不影响退出码，所以提示词另加“必测pending/零测试不能过门槛”的规则。Godot音画同步文档标注可能未完全适配其当前stable版本；这里仅据其同步与延迟原则提出要求，不保证示例API无需验证即可照搬。
