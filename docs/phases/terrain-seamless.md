# 地表循环与道路平滑（2026-11-11）

用户要求道路等地表上下左右能循环衔接，去掉突出的断头路，让地图自然平滑。沿用本轮建筑放大成果。

验收：五镇草/路/土/水20种运行纹理左右、上下逐像素一致；清理无用途短尾，门口路线保留；凸角圆滑，填平无建筑的三面路草地凹口；不改地籍、产权、玩家档或导航权威；受影响回归和图形检查通过。

技能：imagegen内置工具重做20格新图集，提示和来源见assets/town/map-surfaces-v2-generation.json；使用godot-gdscript-patterns静态类型、只读资源规范。grilling不可用，以等价需求审核代替，无阻塞问题。

实现：map-surfaces-v2.png新版本保留旧图；TownScenery加载后在运行副本上匹配两组对边的6像素带，以保证裁切/缩放后仍完全循环；石/草/土/水保持世界坐标UV。smooth_surfaces创建独立显示副本，只裁剪无保护端点的短尾，所有建筑/小屋approach不裁剪，桥不裁剪；填平三面道路、无建筑的草地小缺口。主镇短入口铺面按建筑正面宽度收窄，保留与其他道路重叠的主干，不再产生店旁多余突出的铺路块。paint_cell根据上下左右相邻材质绘制12像素半径的道路凸角，不改变主干宽度。主镇及四镇旅行共用。建筑显示尺寸、港口水面调用、地籍与存档保持。

初轮图形检查发现边缘颜色插值有1/255量化差，严格对边比较失败（保留gpu.log）；修为两边使用同一个中间颜色。gpu-final.log与入口进一步收窄后的gpu-release.log均125项通过。不能将初轮失败记作通过。

root唯一写入，基线artifacts/terrain-seamless/baseline，不提交推送。最终验证：terrain-seamless-town-final主镇48/48、导出前travel-core 11/11、gpu-release 125项/14图PASS；638资源导出、启动3次各4项、实际EXE输入94项PASS。对应证据artifacts/check、artifacts/terrain-seamless、artifacts/export。outputs/道路平滑版.zip、截图/说明和完整生成提示已交付。人工视觉确认PENDING，全量/远程CI未跑，本轮锁释放。
