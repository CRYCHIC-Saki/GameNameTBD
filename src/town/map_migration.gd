class_name TDMapMigration
extends RefCounted
## Called only after the original snapshot has passed its original geometry checks.
static func convert(raw: Dictionary) -> TDOutcome:
	if int(raw.world.get("map_version",1))==2: return TDOutcome.new(true,"MAP_CURRENT","",raw.duplicate(true))
	var data:=raw.duplicate(true)
	var previous:=TDPhase3Session.new();previous.load_default()
	var restored:=TDWorldSnapshot.restore(previous,raw.world)
	if not restored.ok: return restored
	data.world.map_version=2
	var planned:=TDPhase3Session.new();planned.map_version=2;planned.load_default()
	if bool(data.world.branch_open):
		var remote:=TDTownMap.new();remote.layout_version=2
		remote.build(planned.catalog,TDTownMap.seed_of(str(data.world.branch_town)))
		var at:=TDPlannedTown.branch_site(remote,int(data.world.branch_w),int(data.world.branch_h))
		if at.x<0: return TDOutcome.new(false,"MIGRATION_NO_BRANCH_SITE")
		data.world.branch_x=at.x;data.world.branch_y=at.y
	restored=TDWorldSnapshot.restore(planned,data.world)
	if not restored.ok: return restored
	if bool(data.world.branch_open) and str(data.world.town_id)==str(data.world.branch_town) and planned._plot_by_id("branch_diner").is_empty(): return TDOutcome.new(false,"MIGRATION_BRANCH_NOT_PLACED")
	var cottage:=planned.town_map.choose_cottage()
	if cottage.is_empty(): return TDOutcome.new(false,"MIGRATION_NO_COTTAGE")
	if int(data.schema_version)>=4: data.residence={"schema_version":1,"anchor":"cottage_bed","plot":cottage}
	var archived: Dictionary={}
	if data.has("economy") and int(data.economy.schema_version)==2:
		for town: String in data.economy.expansion.parcels:
			var map:=planned.town_map if town==data.economy.home else TDTownMap.new()
			if town!=data.economy.home:
				map.layout_version=2
				var built:=map.build_economic_layout(planned.catalog,TDTownMap.seed_of(town))
				if not built.ok: return built
			var definitions: Dictionary={}
			for parcel: Dictionary in map.commercial_parcels(): definitions[parcel.id]=parcel
			for id: String in data.economy.expansion.parcels[town]:
				if not definitions.has(id): return TDOutcome.new(false,"MIGRATION_UNKNOWN_PROPERTY",id)
				# Ownership, historical purchase quote, version and all financial records stay intact.
				for field: String in ["x","y","w","h","approach_x","approach_y","parent_id","tradable","capacity","initial_store_index"]:
					data.economy.expansion.parcels[town][id][field]=definitions[id][field]
			var geography:=TDEconomicGeography.new();geography.configure(town,map.plots,{},2)
			for firm: Dictionary in data.economy.competitors[town]:
				var parcel: Dictionary=definitions.get(str(firm.parcel_id),{})
				if not parcel.is_empty(): firm.travel_minutes=float(geography.cell(Vector2i(parcel.x,parcel.y)).travel_minutes.residential)
		var cells: Dictionary={}
		for key: String in data.economy.cells:
			var cell: Dictionary=data.economy.cells[key].duplicate(true)
			var old_plot:=previous.town_map._by_id(str(cell.parcel_id))
			var new_plot:=planned.town_map._by_id(str(cell.parcel_id))
			if old_plot.is_empty() or new_plot.is_empty(): archived[key]=cell;continue
			var at:=Vector2i(int(new_plot.x)+clampi(int(cell.x-old_plot.x),0,int(new_plot.w)-1),int(new_plot.y)+clampi(int(cell.y-old_plot.y),0,int(new_plot.h)-1))
			cell.x=at.x;cell.y=at.y;cell.id=TDEconomicCell.identity(cell.town_id,at)
			if cells.has(cell.id): archived[key]=data.economy.cells[key].duplicate(true)
			else: cells[cell.id]=cell
		data.economy.cells=cells
	data.map_migration={"from":1,"to":2,"old_residence":raw.get("residence",{}).duplicate(true),"old_branch":[raw.world.branch_x,raw.world.branch_y],"archived_cell_overrides":archived}
	return TDOutcome.new(true,"MAP_MIGRATED","小镇布局已更新：店铺、小屋与工坊已迁入新位置，经营进度已保留。",data)
