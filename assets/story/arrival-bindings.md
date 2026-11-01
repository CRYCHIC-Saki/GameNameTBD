# 第一场海港开篇资源绑定（D054）

来源：doc/source/无敌厨神_第一场演出动画提示词_v01.txt；原文件只读，SHA256保存在content/story/opening.json。其旧电脑路径和黑发旧厨师不适用于当前定妆；最新用户明确授权正式新档先播放、之后出现在港口。

| 实际资源 | 读取区域/方向/姿势 | 图层及用途 |
| --- | --- | --- |
| res://assets/story/arrival-hero-v1.png | 1536×1024，4列2行；每格384×512，透明边测量后裁切；右向3/4 | 新增8个完整姿势，闭图/抬图/半开/展开/两步/按胃/逞强；锅随全身图始终在背，不拉伸角色或剪身体冒充骨骼。 |
| res://assets/story/arrival-aling-v2.png | 1536×1024，3列2行；每格512×512，左向3/4 | 新增6姿势；腰侧闭书→手捧唯一账本→打开→读书→抬眼，持书姿势不叠腰书。v1朝向不符，未被正式场景引用。 |
| res://assets/story/arrival-coast-v1.png | 整幅1586×992，按1280×800舞台取景 | 新生成海港/公交停靠处/镇入口背景，木箱在右侧原图中，海风左向右；未添加彩色群众。 |
| res://assets/story/opening-props-v1.png | 旧道具图集Rect2(0,0,548,420)，仅客车 | 旧客车左右翻向后驶离左侧。车轮未独立，因此不旋转整车冒充轮子。 |
| res://assets/characters/protagonist/protagonist-dialogue-halfbody-pose-pixel-v7.png、protagonist-idle-four-directions-v1.png | 原图只读 | 仅定妆参考；静态四视图未当行走帧。 |
| res://assets/characters/aling/archive/2026-10-29/aling-dialogue-halfbody.png | 原图只读 | 新姿态身份参考，不用整体镜像替换阿铃方向。 |
| res://assets/audio/casual.wav | TDGameMusic原连续音轨 | 镜头之间不重启；演出暂停/失焦同时暂停。 |
| TDCutsceneView.sound | engine/step/paper/stomach合成拟音 | 旧有原创合成占位，不是配音或录制实物音效；纸声只在打开时，跳过不集中触发音效。 |

地图与账本细节使用新生成arrival-props-v1.png，按实测四区域裁切（地图0,0,1030,500；闭书1030,0,506,500；半开0,500,750,524；打开750,500,786,524）；MapRoot下同组两个中文Label及三条Line2D红圈，整体缩放。账本细节为闭合/半开/展开三个生成姿态，与全身持书姿态连续。中文未交给图像模型生成。原始角色宽高比保留，nearest采样；不强制整个游戏降帧率。

可编辑文件：res://src/story/arrival_cutscene.tscn的AnimationPlayer，A_arrival 14s、B_hungry 6s、C_aling 10s。镜号/焦点/缩放/位置/姿势/道具/细节状态均在轨道，脚本只取样与绘制，时间轴不写存档。镜头相机是本地绘制变换，不接管TownCamera，也无需恢复被覆盖的世界相机状态。

独立预览：Godot打开res://src/story/arrival_preview.tscn并F6；可选整场/三独立段，暂停/跳过本段；不创建或读取经营存档。正式新档复用同一场景和TDDialogue完成信号。

边界：这版是实时二维有限姿势动画，非完整逐帧长片。未提供正式配音、独立口型/披风/乌鸦图层或高帧率身体补间；不可将整体位移、三帧账本称为连续全帧动作成片。最终观感和真实设备试听待玩家验收。生成工具与完整提示词见arrival-generation.json。
