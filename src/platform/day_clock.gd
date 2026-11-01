class_name TDWorldDayClock
extends RefCounted
## Calendar day changes only with sleep. Minutes after midnight remain on that day.
const START_MINUTE := 480.0
const END_MINUTE := 1560.0
const MINUTES_PER_SECOND := 1.0
var day: int = 1
var minute: float = START_MINUTE
var closed_day: int = 0

func advance(seconds: float, frozen: bool = false) -> bool:
	if frozen or not is_finite(seconds) or seconds <= 0 or closed_day == day: return false
	minute = minf(END_MINUTE, minute + seconds * MINUTES_PER_SECOND)
	return minute >= END_MINUTE

func next_day(value: int) -> void:
	day = value
	minute = START_MINUTE

func label() -> String:
	var whole := floori(minute)
	return "%02d:%02d" % [(whole / 60) % 24, whole % 60]

func snapshot() -> Dictionary:
	return {"schema_version":1,"day":day,"minute":minute,"closed_day":closed_day}

func restore(raw: Dictionary) -> TDOutcome:
	var valid := validate(raw)
	if not valid.ok: return valid
	day = int(raw.day); minute = float(raw.minute); closed_day = int(raw.closed_day)
	return TDOutcome.new(true,"CLOCK_RESTORED")

static func validate(raw: Variant) -> TDOutcome:
	if not raw is Dictionary or raw.get("schema_version") != 1: return TDOutcome.new(false,"INVALID_CLOCK_VERSION")
	if not TDServiceCatalog.integer(raw.get("day"),1,1000000) or not TDServiceCatalog.integer(raw.get("closed_day"),0,int(raw.day)): return TDOutcome.new(false,"INVALID_CLOCK_DAY")
	if not TDEconomicCustomer.finite_range(raw.get("minute"),START_MINUTE,END_MINUTE): return TDOutcome.new(false,"INVALID_CLOCK_MINUTE")
	if int(raw.closed_day)==int(raw.day) and float(raw.minute)<END_MINUTE: return TDOutcome.new(false,"INVALID_CLOCK_CLOSURE")
	return TDOutcome.new(true,"VALID_CLOCK")
