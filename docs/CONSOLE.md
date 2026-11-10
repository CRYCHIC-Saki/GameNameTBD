# 调试控制台

按键盘左上角反引号键（Esc下方、数字1左侧）打开，输入 `debug` 开启调试。再按反引号或Esc关闭。打开时游戏暂停；输入框保持焦点，连续回车可执行多条命令。

- `help`：分类帮助；`help employee`等查看详细用法。未开启调试也能看help。
- ↑ / ↓：上/下一条命令，回到末尾恢复原来未提交的草稿。
- Tab：补全命令、食材ID、菜谱ID、店铺ID、当前可签约员工ID；多个匹配会显示候选，可继续输入缩小范围。
- 鼠标滚轮：查阅输出；可选中文本复制。保留50条命令/240行输出。
- `clear`：清空输出；`debug off`或`debug_off`：关闭修改权限。关闭不会撤销已发生的内存修改。

## 常用例子

```text
debug
money add 10000
give tomato 10
give egg 10
inspiration add 50
recipe unlock C03
time set 18:00
check
```

命令只改当前槽的内存，普通退出不会保存。需要保留时明确输入 `save`，它仍要求筹备/日结、厨房整理完毕；不支持QTE现场保存。切换存档或回到标题会清空调试权限和历史。测试时建议使用单独的游戏存档位。

## 命令表

| 命令 | 作用与边界 |
|---|---|
| `status` | 当前槽/地点/时间/阶段、现金、人气、店名气、SAN、灵感、员工及订单数量。 |
| `check` | 只读校验整槽数据，并显示世界资金与银行账差额（正常均为0）；不写盘。 |
| `money add 10000` | 增加10000金币；负数可减少。最多两位小数，单次绝对值≤1000000。资金走真实账本；正注入可能先偿还旧欠费，输出显示实际现金。不是经营收入。 |
| `items 番茄` | 按ID/名称片段查询可识别原料、单位和库存。省略关键词时显示前40项。 |
| `give tomato 10 [店铺ID]` | 调试添加原料，默认主店；0.001–1000标准份，最多三位小数。正常批次/保质期、免费0成本，库存上限仍生效。调料也是标准份，不是采购界面的整瓶/整袋数量。 |
| `stock [店铺ID] [关键词]` | 查看正库存，如 `stock main tomato`。 |
| `inspiration add 50` | 增加1–10000灵感，带独立debug事件；不改变等级。 |
| `recipes 面` | 查询菜谱ID/状态/运行时对应。 |
| `recipe unlock C03` | 调试掌握该菜及其前置节点、开放其菜系。目标必须有运行时内容；前置节点可仅有树定义。记录debug_unlock，不伪造研习分数/Perfect/历史迁移；不表示尚未制作的玩法已实现。 |
| `cuisine open jp` | 开放一个菜系页，菜谱仍逐个掌握。可用cn/eu/jp/sea/lat。 |
| `san 50` | 设置0–100，后续工序生效；进行中的QTE不能改。 |
| `time` / `time set 18:00` | 查看/调整当天钟表，只允许筹备或日结。范围08:00–次日01:59；00:30等同24:30。仅预览时间及NPC日程，不快进顾客、生产或跨日，不触发02:00安全保存。 |
| `employee market chengdu manager` | 查当前小镇/岗位的候选人、ID、星级、签约费和日薪。 |
| `employee hire 员工ID` | 签约当前候选并真实付款，进入仓库。不能给任意身份造合同；先用money补足调试资金。 |
| `employee owned [关键词]` | 查看已拥有员工、岗位、当前店及日薪。 |
| `employee assign 员工ID main` | 派驻主店；目标可换成分店ID，`idle`为撤任回库。仍检查岗位容量、同人单店与日薪。 |
| `shop list [关键词]` | 查看主店和分店的稳定ID。 |
| `shop info main` | 查看该店经理、人员、菜单及托管信息。 |
| `shop auto main on` | 开启经营托管，off关闭。主店须先有经理；供货托管独立。 |
| `orders [关键词]` | 订单、菜品、状态、等待剩余秒数；不生成假顾客或假成品。 |
| `supply [关键词]` | 查询供货目标、数量、剩余真实活动秒和收货状态。 |
| `quest` / `quest track on` | 查当前任务节点和引导目标；on/off切追踪，不强制完成剧情或发奖励。 |
| `open shops` | 打开正式管理界面；也可用employees/suppliers/recipes/quests/map/relationships。 |
| `goto harbor` | 回主镇港口；可用town/restaurant/kitchen/cottage。仍需整理工位，小屋须已解锁；不改变跨镇旅行规则。 |
| `save` | 明确主动保存当前槽，完整校验和原子保存规则不变。 |
| `tools` | 旧独立试验入口，使用独立调试文件；不把试验结果回写当前槽。 |

小镇ID：`chengdu`、`tokyo`、`paris`、`bangkok`、`mexico_city`。岗位：`manager`店长、`cook`厨师、`waiter`服务员。主店可用`main`或`player_diner`，分店使用`shop list`列出的ID。

中文完整名称可代替食材/菜谱/员工ID；名称含空格时用单或双引号，如 `give "番茄" 2`。同名歧义时请使用稳定ID。列表先显示40项，追加关键词筛选；不会按数组序号识别人或菜。

资源、签约、托管、解锁和传送默认只在筹备/日结使用；剧情/对话、研习及任一正在运行的QTE中拒绝修改。查询仍可用。无活动槽、非法参数、未知ID或余额/库存上限失败会明确返回原因，不留下部分变更。

工程检查：`pwsh -NoProfile -File tools/check.ps1 -Suite console`。旧入口回归单独运行`-Suite game -TimeoutSeconds 900`。实际证据及未验证项见`docs/phases/game-shell.md` D066。

店铺施工状态：`shop list` 同时显示施工中、待任命店长和待核对旧选址。`status` 的店铺数量只计主店与已付款分店。`time set` 只预览钟表，不改变日期或跳过分店工期。
