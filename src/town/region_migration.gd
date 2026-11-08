class_name TDRegionMigration
extends RefCounted
## Pure candidate conversion. Caller validates both snapshots and backs up before activation.
const GEOMETRY := ["x","y","w","h","approach_x","approach_y","parent_id","tradable","capacity","initial_store_index"]

static func convert(raw: Dictionary) -> TDOutcome:
	if int(raw.get("region_layout_version",1))==2: return TDOutcome.new(true,"REGIONS_CURRENT","",raw.duplicate(true))
	var data:=raw.duplicate(true)
	var catalog:=TDTownCatalog.new();var loaded:=catalog.load_file()
	if not loaded.ok: return loaded
	var maps: Dictionary={}
	for id: String in TDRegionalLayout.IDS:
		var map:=TDTownMap.new();map.layout_version=2
		loaded=map.build_economic_layout(catalog,TDTownMap.seed_of(id))
		if not loaded.ok: return loaded
		maps[id]=map
	var archive: Dictionary={"from":1,"to":2,"branches":{},"cells":{}}
	if data.has("economy") and int(data.economy.schema_version)==2:
		for id: String in maps:
			var map: TDTownMap=maps[id]
			var definitions: Dictionary={}
			for parcel: Dictionary in map.commercial_parcels(): definitions[parcel.id]=parcel
			for key: String in data.economy.expansion.parcels.get(id,{}):
				if not definitions.has(key): return TDOutcome.new(false,"REGION_UNKNOWN_PROPERTY",key)
				for field: String in GEOMETRY: data.economy.expansion.parcels[id][key][field]=definitions[key][field]
			var geo:=TDEconomicGeography.new();geo.configure(id,map.plots,{},2)
			for firm: Dictionary in data.economy.competitors.get(id,[]):
				var parcel: Dictionary=definitions.get(str(firm.parcel_id),{})
				if not parcel.is_empty(): firm.travel_minutes=geo.cell(Vector2i(parcel.x,parcel.y)).travel_minutes.residential
		# Sparse old-coordinate overrides are retained in the archive, never silently
		# applied to a different parcel now occupying that coordinate.
		for key: String in data.economy.cells.keys():
			if data.economy.cells[key].town_id not in maps: continue
			archive.cells[key]=data.economy.cells[key].duplicate(true);data.economy.cells.erase(key)
	var stores: Dictionary=data.get("branches",{}).get("stores",{})
	var keys: Array=stores.keys();keys.sort()
	for key: String in keys:
		var store: Dictionary=stores[key]
		if not maps.has(store.town_id): continue
		var map: TDTownMap=maps[store.town_id]
		var old: Array=store.rect.duplicate();var next:=find_site(map,old)
		if next.is_empty(): return TDOutcome.new(false,"REGION_NO_BRANCH_SITE",store.name+"：无法保留原面积，未修改存档。")
		archive.branches[key]={"town_id":store.town_id,"rect":old,"place":store.place.duplicate(true)}
		store.rect=next
		var geo:=TDEconomicGeography.new();geo.configure(store.town_id,map.plots,{},2)
		store.place=geo.cell(Vector2i(int(next[0]+next[2]/2),int(next[1]+next[3]/2)))
		map.plots.append({"id":key,"kind":"player_diner","x":next[0],"y":next[1],"w":next[2],"h":next[3]})
	data.region_layout_version=2;data.region_migration=archive
	return TDOutcome.new(true,"REGIONS_MIGRATED","四镇地形已更新，分店面积、产权与经营进度已保留。",data)

static func find_site(map: TDTownMap, old: Array) -> Array:
	var blocked: Dictionary={}
	for y: int in map.extent:
		for x: int in map.extent:
			var at:=Vector2i(x,y)
			if map.is_road(x,y) or not map.terrain_at(at).buildable: blocked[at]=true
	for p: Dictionary in map.plots:
		for y: int in range(int(p.y),int(p.y+p.h)):
			for x: int in range(int(p.x),int(p.x+p.w)): blocked[Vector2i(x,y)]=true
	var valid:=func(x:int,y:int)->bool:
		if x<0 or y<0 or x+int(old[2])>map.extent or y+int(old[3])>map.extent: return false
		for dy: int in int(old[3]):
			for dx: int in int(old[2]):
				if blocked.has(Vector2i(x+dx,y+dy)): return false
		return map._touches_road(x,y,int(old[2]),int(old[3]))
	if valid.call(int(old[0]),int(old[1])): return old.duplicate()
	var best: Array=[];var distance: int=2147483647
	for y: int in range(1,map.extent-int(old[3])):
		for x: int in range(1,map.extent-int(old[2])):
			var d:=absi(x-int(old[0]))+absi(y-int(old[1]))
			if d<distance and valid.call(x,y): best=[x,y,old[2],old[3]];distance=d
	return best

static func validate_archive(raw: Variant) -> TDOutcome:
	if not raw is Dictionary: return TDOutcome.new(false,"REGION_ARCHIVE")
	if raw.is_empty(): return TDOutcome.new(true)
	if raw.get("from")!=1 or raw.get("to")!=2 or not raw.get("branches") is Dictionary or not raw.get("cells") is Dictionary: return TDOutcome.new(false,"REGION_ARCHIVE")
	for value: Variant in raw.cells.values():
		if not TDEconomicCell.validate(value).ok: return TDOutcome.new(false,"REGION_ARCHIVED_CELL")
	for value: Variant in raw.branches.values():
		if not value is Dictionary or value.get("town_id") not in TDRegionalLayout.IDS or not value.get("rect") is Array or value.rect.size()!=4 or not TDEconomicCell.validate(value.get("place")).ok: return TDOutcome.new(false,"REGION_ARCHIVED_BRANCH")
		for n: Variant in value.rect:
			if not TDServiceCatalog.integer(n,0,73): return TDOutcome.new(false,"REGION_ARCHIVED_RECT")
	return TDOutcome.new(true,"VALID_REGION_ARCHIVE")
