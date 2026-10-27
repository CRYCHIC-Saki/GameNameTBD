class_name TDLevelRewardsView
extends VBoxContainer
## Read-only rewards page. The formal profile performs all progression transactions.

func _card() -> VBoxContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color=Color("172b27");style.border_color=Color("68745b")
	style.set_border_width_all(2);style.content_margin_left=18;style.content_margin_right=18;style.content_margin_top=14;style.content_margin_bottom=14
	panel.add_theme_stylebox_override("panel",style);add_child(panel)
	var box := VBoxContainer.new();box.add_theme_constant_override("separation",9);panel.add_child(box)
	return box

func _text(box: Node, value: String, size: int=19, color: Color=Color("ddd8ba")) -> Label:
	var label := TDUI.label(value,size,color)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	box.add_child(label)
	return label

func setup(levels: TDLevelProgression, points: int) -> void:
	name="LevelRewardsView";size_flags_horizontal=Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",16)
	var state := levels.snapshot()
	var progress := levels.progress()
	var top := _card()
	_text(top,"食堂成长录",17,Color("a9b89b"))
	var heading := _text(top,"经营等级  Lv.%02d"%int(progress.level),34,Color("f3d28b"));heading.name="LevelHeading"
	_text(top,"灵感 %d  ·  升级奖励自动到账"%points,20,Color("a9d3a7"))
	var bar := ProgressBar.new();bar.name="LevelExperienceBar";bar.custom_minimum_size=Vector2(0,22);bar.show_percentage=false
	bar.min_value=0;bar.max_value=int(progress.required_xp);bar.value=bar.max_value if progress.at_cap else int(progress.current_xp)
	var back := StyleBoxFlat.new();back.bg_color=Color("101c19");back.border_color=Color("7e8469");back.set_border_width_all(2)
	var fill := StyleBoxFlat.new();fill.bg_color=Color("b1c57e")
	bar.add_theme_stylebox_override("background",back);bar.add_theme_stylebox_override("fill",fill);top.add_child(bar)
	var caption := "当前等级已满" if progress.at_cap else "%d / %d 经验  ·  下一级获得 %d 点灵感"%[progress.current_xp,progress.required_xp,levels.reward_for(int(progress.level)+1).inspiration]
	_text(top,caption,18).name="LevelExperienceText"
	var daily := _card()
	if state.recent.is_empty():
		_text(daily,"完成一天营业，积累经营经验",23,Color("f3d28b"))
		_text(daily,"经验来自店铺净利润、人气增长和知名度增长；亏损或指标下降不会扣经验。")
	else:
		var record: Dictionary=state.recent.back()
		_text(daily,"第 %d 天  ·  经营经验 +%d"%[record.day,record.xp],23,Color("f3d28b")).name="LevelDailyGain"
		_text(daily,"经营净利润 ¥%+.2f    →  +%d XP\n店铺人气 %+.2f    →  +%d XP\n店铺知名度 %+.2f    →  +%d XP"%[float(record.profit_cents)/100,record.profit_xp,record.popularity_delta,record.popularity_xp,record.awareness_delta,record.awareness_xp],19)
		_text(daily,"%d 家经营店 · 规模 %.1f 标准店 · 折算正利润 ¥%.2f/标准店"%[record.store_count,float(record.scale_milli)/1000,float(record.normalized_profit_cents)/100],16,Color("a9b89b"))
		if progress.at_cap: _text(daily,"满级后不再增加经验，上方分项保留当日映射明细。",16,Color("a9b89b"))
	_text(self,"每日至多 %d XP；收益越高，经验增幅越小。菜品名气、借款和补助不计入。"%int(levels.config.daily.max_xp),16,Color("a9b89b"))
	if progress.migrated: _text(self,"旧档成长从第 %d 天开始记录，历史进度和已解锁功能保留。"%int(progress.origin_day),16,Color("a9b89b"))
	_text(self,"等级奖励",25,Color("f3d28b"))
	for level: int in range(2,int(progress.max_level)+1):
		var reward := levels.reward_for(level)
		var achieved := level<=int(progress.level)
		var row := HBoxContainer.new();row.name="LevelReward%d"%level;row.add_theme_constant_override("separation",18);add_child(row)
		var badge := TDUI.label("Lv.%02d"%level,21,Color("f3d28b") if achieved else Color("879482"));badge.custom_minimum_size.x=90;badge.autowrap_mode=TextServer.AUTOWRAP_OFF;row.add_child(badge)
		var details := VBoxContainer.new();details.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(details)
		_text(details,"灵感 +%d%s"%[reward.inspiration,"  ·  里程碑奖励" if level%int(levels.config.rewards.milestone_every)==0 else ""],20)
		for hook: Dictionary in levels.config.hooks:
			if int(hook.level)!=level: continue
			var kind := str({"feature":"功能资格","furniture":"家具资格","story":"剧情触发","event":"事件触发"}[hook.kind])
			_text(details,kind+" · "+str(hook.get("name",hook.target_id)),16,Color("a9b89b"))
		var status := "已到账" if achieved else ("下一级" if level==int(progress.level)+1 else "未达成")
		var status_label := TDUI.label(status,17,Color("b2cb8e") if achieved else Color("879482"))
		status_label.autowrap_mode=TextServer.AUTOWRAP_OFF;row.add_child(status_label)
	_text(self,"功能、家具和故事奖励将在后续公布；当前已开放功能保持可用。",17,Color("a9b89b"))
