# 餐厅布置

状态：场景可运行。PLAYTEST=PENDING。不替换 Phase 2 的订单、做菜和日结。

来源是用户 2026-10-10 的布置要求，以及 2026-10-11 的斜角镜头和全程来客。Phase 2 营业人气乘子仍是 1。斜角画面里的装修进入 D021 客流评价，不写旧营业档。

| AC | 输入 | 可观察结果 |
|---|---|---|
| AC-RESTAURANT-001 | 读取 `content/restaurant.json` | 默认房间含全部门面、迎宾、等候、屏风、收银、点餐机、点餐台、餐桌、卡座、沙发、凳子、儿童座椅、火锅桌；火锅桌带 induction |
| AC-RESTAURANT-002 | 门口到走廊，再堵上唯一出口 | 路线只踩门口和过道；堵住后路线为空。失败的放置和涂格不改房间 |
| AC-RESTAURANT-003 | 未雇迎宾时试客；雇用后再试两位 | 第一位不能进店。之后两位走到不同的用餐落脚点，路径每步相邻 |
| AC-RESTAURANT-004 | 真实场景里走动、撞墙、E、暂停 | 玩家能沿过道移动，墙挡住身体；迎宾台报 NEED_GREETER，收银台在雇用前后从 NEED_CASHIER 变为 READY；暂停时不再移动 |
| AC-RESTAURANT-005 | 两份布局，一份改成法式高端 | 另一份和目录仍是中式低端。中式低端与法式高端的占位图像素不同 |
| AC-RESTAURANT-006 | 隔离路径保存后再写入版本 99 | 读回一致。未知版本不能被新保存覆盖。进入场景不写 `user://shop-v1.json` 或玩家布置档 |
| AC-RESTAURANT-007 | 主菜单进入并返回 | 场景里有玩家、地面和全部默认家具。涂掉脚下格子会把玩家送回门口，空用餐格可以再放凳子 |

## 实际边界

- 区域：门面、接待、点餐/结账、用餐、过道。门口算可走的入口。
- 迎宾台需要迎宾在岗，收银台需要收银员在岗。自助点餐机和点餐台不需要员工。雇用从 Phase 3 现金账付当天工资，钱不够不能到岗。
- 客人寻路是四方向网格搜索，不穿过家具区。用餐家具各算一个座位。等候座不自动分配。
- 风格是文化 × 档次。全店套用会重画地面和全部家具；「这件换风格」只改选中的一件。
- 贴图由 `TDRestaurantArt` 在运行时画出。斜角画面由 `TDRestaurantIsoView` 画地面、两面墙和菱形家具。没有正式装修素材。
- 全程来客走迎宾、点单、入座、等上菜、吃饭、收银和离开。菜单外的单可以拒绝或接下。评价解锁写入 Phase 3 菜谱本，并在「去厨房」时装进原来的逐拍表。
- 「备料」买的是原材料。可以按一道菜一次备齐，也可以点选一种食材。冷藏、冷冻和密封干藏按品类延长保质期。过期在下一天清掉。这本账不进入原来的冰箱。

## 验证

| 检查 | 结果 |
|---|---|
| 资源加载 | `tools/load_check.gd`：resources=55 failures=0，exit 0 |
| 餐厅测试 | GUT 13/13，148 断言，0 失败，exit 0。引擎 `4.7.2.stable.steam.ed1daf0bf`，GUT 9.7.1。本机二进制是 `D:\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`。junit：`artifacts/check/restaurant-framework/junit.xml` |
| 画面 | `artifacts/restaurant-play.png`、`restaurant-edit.png`、`restaurant-guest.png`。Compatibility，NVIDIA GeForce RTX 4060 Laptop。客人停在餐桌旁，编辑栏能看到移动、转向、拆除和恢复默认 |
| 全量检查 | NOT_RUN。`pwsh` 不在 PATH，因此没有跑 `tools/check.ps1`。主菜单旧烹饪回归也没有在这次跑完 |
| 人工 | PENDING |

试玩不超过五步：主菜单进「布置餐厅」；走到迎宾台按 E，雇用迎宾和收银；点「试来客」看入座；点「布置」移动一件家具或把全店换成日式高端；保存后返回。营业里的订单和账本应与进餐厅之前一样。
