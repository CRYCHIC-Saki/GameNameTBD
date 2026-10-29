class_name TDGuestVisit
extends RefCounted
## Visual visit clock for a shop order. Money, stock and reviews stay on the order.

const EAT_SEC := 6.0
const PAY_SEC := 2.2

static func phase_of(status: String, arrived: bool, since_terminal: float) -> String:
	if status in ["WAITING", "COOKING"]:
		return "wait_serve" if arrived else "approach"
	if status == "SERVED" and since_terminal < EAT_SEC:
		return "eat"
	if status == "SERVED" and since_terminal < EAT_SEC + PAY_SEC:
		return "pay"
	return "leave"

static func shirt(phase: String) -> Color:
	match phase:
		"wait_serve":
			return Color("#c47a3a")
		"eat":
			return Color("#3f8f6a")
		"pay":
			return Color("#c4b14a")
		"leave":
			return Color("#6a6a78")
		_:
			return Color("#3f6f8f")

static func caption(dish: String, status: String, phase: String, seconds_left: int, satisfaction: float, net_cents: int, refunded_cents: int) -> String:
	var name := dish if dish != "" else "菜"
	match phase:
		"approach":
			return "%s · 进门" % name
		"wait_serve":
			var doing := "制作中" if status == "COOKING" else "等上菜"
			return "%s · %s · %d秒" % [name, doing, maxi(0, seconds_left)]
		"eat":
			if satisfaction >= 0.0:
				return "%s · 用餐 %.0f分" % [name, satisfaction]
			return "%s · 用餐" % name
		"pay":
			if refunded_cents > 0:
				return "%s · 退款 ¥%.2f" % [name, float(refunded_cents) / 100.0]
			return "%s · 结账 ¥%.2f" % [name, float(net_cents) / 100.0]
		_:
			return "%s · %s" % [name, leave_name(status, refunded_cents)]

static func leave_name(status: String, refunded_cents: int) -> String:
	if status == "SERVED" and refunded_cents > 0:
		return "退款离开"
	if status == "SERVED":
		return "吃完离开"
	return status_name(status)

static func status_name(status: String) -> String:
	return {
		"WAITING": "等上菜",
		"COOKING": "后厨制作",
		"SERVED": "已上菜",
		"CANCELLED": "订单取消",
		"TIMED_OUT": "等太久离开",
		"REJECTED_STOCK": "缺料谢客",
	}.get(status, status)

static func inspect_text(dish: String, customer: String, status: String, phase: String, seconds_left: int, price_cents: int, satisfaction: float, net_cents: int, refunded_cents: int, reasons: PackedStringArray, decor_effect: float, crew_line: String) -> String:
	var who := customer if customer != "" else "客人"
	var meal := dish if dish != "" else "菜"
	var lines := PackedStringArray()
	lines.append("%s点了%s。" % [who, meal])
	lines.append(_sentence(status, phase, seconds_left, satisfaction, net_cents, refunded_cents))
	if price_cents > 0:
		lines.append("点单时的菜单价 ¥%.2f。到店后的改价不改这一单。" % [float(price_cents) / 100.0])
	if not reasons.is_empty():
		lines.append("选店：" + "；".join(reasons))
	lines.append("当前装修效果 %.0f。之后进门的客人会把它和竞品、在家吃饭一起比较。" % decor_effect)
	if crew_line != "":
		lines.append(crew_line + "。厨师延长新单等待并修正口味，服务员招呼客人并提高小费。")
	else:
		lines.append("还没有雇员。厨师在后厨做菜，服务员在座位旁招呼。")
	return "\n".join(lines)

static func _sentence(status: String, phase: String, seconds_left: int, satisfaction: float, net_cents: int, refunded_cents: int) -> String:
	if status in ["WAITING", "COOKING"] and phase == "approach":
		return "正在进门，入座后还能等 %d 秒。" % maxi(0, seconds_left)
	if status == "WAITING":
		return "已经坐下等上菜，还能等 %d 秒。后厨做好并送达后才记账。" % maxi(0, seconds_left)
	if status == "COOKING":
		return "后厨正在做这道菜，还能等 %d 秒。" % maxi(0, seconds_left)
	if status == "SERVED" and phase == "eat":
		if satisfaction >= 0.0:
			return "正在吃，满意度 %.0f。这一单的菜款已经记入账本。" % satisfaction
		return "正在吃。这一单的菜款已经记入账本。"
	if status == "SERVED" and phase == "pay":
		if refunded_cents > 0:
			return "不满意，退款 ¥%.2f 已从账本扣回。" % [float(refunded_cents) / 100.0]
		return "结账收尾，本单净收 ¥%.2f，含小费。" % [float(net_cents) / 100.0]
	if status == "SERVED":
		return "这单已经结束，客人离开。账本不再重复收款。"
	if status == "TIMED_OUT":
		return "等太久，没吃到就离开。这单不收款，并计入放弃。"
	if status == "REJECTED_STOCK":
		return "缺料没做成，客人离开。这单不收款。"
	if status == "CANCELLED":
		return "这单已取消，客人不留下吃饭。"
	return "客人正在离开。"

static func conversation(who: String, dish: String, phase: String, portrait: String) -> TDDialogue:
	var talk := TDDialogue.new()
	var meal := dish if dish != "" else "这道菜"
	var person := who if who != "" else "客人"
	var opening := "%s：我点了%s。" % [person, meal]
	if phase == "eat":
		opening = "%s：%s我正在吃。" % [person, meal]
	elif phase in ["pay", "leave"]:
		opening = "%s：这桌我用完了。" % person
	elif phase == "wait_serve":
		opening = "%s：%s还没上来，我坐着等。" % [person, meal]
	talk.add_line(person, portrait if portrait != "" else "guest", opening)
	var calm_id := "soon"
	var blunt_id := "hurry"
	var calm_label := "马上就好，请再坐一会儿。"
	var blunt_label := "你再催也快不了。"
	var calm := "%s：好，我等这道%s。来了我就吃。" % [person, meal]
	var blunt := "%s：那我再等等。催也不另算一笔。" % person
	if phase == "eat":
		calm_id = "enjoy"
		blunt_id = "rush"
		calm_label = "慢慢吃，不着急。"
		blunt_label = "吃完请马上走。"
		calm = "%s：我按自己的速度吃。账在出餐时已经记过了。" % person
		blunt = "%s：吃完我会自己起身，不用赶。" % person
	elif phase in ["pay", "leave"]:
		calm_id = "thanks"
		blunt_id = "stay"
		calm_label = "谢谢光临。"
		blunt_label = "再坐一会儿吧。"
		calm = "%s：谢谢。这一桌的账已经算过，我这就走。" % person
		blunt = "%s：不坐了。账不会再算一次。" % person
	talk.add_choice([
		{"id": calm_id, "label": calm_label, "text": calm, "speaker": person, "portrait": portrait},
		{"id": blunt_id, "label": blunt_label, "text": blunt, "speaker": person, "portrait": portrait},
	])
	return talk
