# 工作单目录

每个角色把自己的工作单放在独立子目录：

- 当前：`building/`、`supplier/`、`town-economy/`；实际开始任务时再创建工作单，不预建空模块。
- 以下旧目录保留历史波次：

- `cook/`
- `economy/`
- `town/`

文件名格式：

`phase-{phase}-wave-{wave}-{短任务名}.md`

示例：

`cook/phase-4-wave-1-san-substitute.md`

从 `../templates/WORK_ITEM_TEMPLATE.md` 复制。角色分支只修改自己的子目录；集成者在合并后保留工作单作为真实交接记录。
