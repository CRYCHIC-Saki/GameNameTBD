class_name TDJiangnanMigration
extends RefCounted
## Transform a validated old slot into a candidate for the new map. The caller
## validates this candidate before activation or saving, and retains the old slot.

static func convert(raw: Dictionary) -> TDOutcome:
	var data := raw.duplicate(true)
	var world := TDPhase3Session.new()
	var loaded := world.catalog.load_file()
	if not loaded.ok: return loaded
	var home := str(data.get("economy",{}).get("home",data.world.home_town_id))
	var archive := {"residence":{},"branches":{},"cells":{},"old_branch":[]}
	var old_single := bool(data.world.branch_open) and str(data.world.branch_town)==home
	var world_data: Dictionary = data.world.duplicate(true)
	if old_single: world_data.branch_open=false
	world.import_phase4(world_data)
	var map := world.town_map
	if data.has("residence"):
		var old: Dictionary = data.residence.plot
		if not map.validate_cottage(old).ok:
			var cottage := map.choose_cottage()
			if cottage.is_empty(): return TDOutcome.new(false,"JIANGNAN_NO_COTTAGE","新版小镇缺少可用的小屋位置。")
			archive.residence=old.duplicate(true)
			data.residence.plot=cottage
		var installed := map.install_cottage(data.residence.plot)
		if not installed.ok: return installed

	_update_cells(data,home,archive)
	var geography := TDEconomicGeography.new()
	geography.configure(home,map.plots,data.get("economy",{}).get("cells",{}),2)
	var properties := _update_properties(data,home,map,geography)
	if not properties.ok: return properties

	var stores: Dictionary = data.get("branches",{}).get("stores",{})
	var ids := stores.keys()
	ids.sort()
	for id: String in ids:
		var store: Dictionary = stores[id]
		if store.town_id != home or store.get("construction",{}).get("kind","")=="unverified": continue
		var next := TDRegionMigration.find_site(map,store.rect)
		if next.is_empty():
			return TDOutcome.new(false,"JIANGNAN_NO_BRANCH_SITE",store.name+"无法安置到同面积的临街地块。")
		archive.branches[id]={"rect":store.rect.duplicate(),"place":store.place.duplicate(true)}
		store.rect=next
		store.site_survey=1
		var center := Vector2i(int(next[0])+int(next[2])/2,int(next[1])+int(next[3])/2)
		store.place=geography.cell(center)
		map.plots.append({"id":id,"kind":"player_diner","x":next[0],"y":next[1],"w":next[2],"h":next[3]})

	if old_single:
		var old := [data.world.branch_x,data.world.branch_y,data.world.branch_w,data.world.branch_h]
		var next := TDRegionMigration.find_site(map,old)
		if next.is_empty(): return TDOutcome.new(false,"JIANGNAN_NO_LEGACY_BRANCH_SITE","旧式分店无法找到同面积的临街地块。")
		archive.old_branch=old
		data.world.branch_x=next[0]
		data.world.branch_y=next[1]

	data.jiangnan_layout_revision=2
	data.jiangnan_migration=archive
	return TDOutcome.new(true,"JIANGNAN_MIGRATED","江南已更新地图，小屋和原有分店均已安置。",data)

static func _update_cells(data: Dictionary, home: String, archive: Dictionary) -> void:
	# Old coordinate overrides describe the former geography, even if a new plot
	# happens to use the same numbers. Preserve them as historical records.
	if not data.has("economy"): return
	var cells: Dictionary = data.economy.get("cells",{})
	for id: String in cells.keys():
		if cells[id].town_id!=home: continue
		archive.cells[id]=cells[id]
		cells.erase(id)

static func _update_properties(data: Dictionary, home: String, map: TDTownMap, geography: TDEconomicGeography) -> TDOutcome:
	if not data.has("economy") or int(data.economy.schema_version)!=2: return TDOutcome.new(true)
	var definitions := {}
	for parcel: Dictionary in map.commercial_parcels(): definitions[parcel.id]=parcel
	var parcels: Dictionary = data.economy.expansion.parcels.get(home,{})
	for id: String in parcels:
		if not definitions.has(id): return TDOutcome.new(false,"JIANGNAN_UNKNOWN_PROPERTY",id)
		for field: String in TDRegionMigration.GEOMETRY:
			parcels[id][field]=definitions[id][field]
	for firm: Dictionary in data.economy.competitors.get(home,[]):
		var parcel: Dictionary = definitions.get(str(firm.parcel_id),{})
		if not parcel.is_empty():
			firm.travel_minutes=float(geography.cell(Vector2i(parcel.x,parcel.y)).travel_minutes.residential)
	return TDOutcome.new(true)

## Validate old titles against the exact previously issued rectangle and entrance.
static func issued_definition(current: Dictionary, saved: Dictionary) -> Dictionary:
	for old: Dictionary in TDPlannedTown.definition().commercial_parcels:
		if old.id!=current.id or old.rect[0]!=saved.get("x") or old.rect[1]!=saved.get("y"): continue
		var issued := current.duplicate()
		issued.merge({"x":old.rect[0],"y":old.rect[1],"w":old.rect[2],"h":old.rect[3],
			"approach_x":old.approach[0],"approach_y":old.approach[1]},true)
		return issued
	return current

static func validate_archive(raw: Variant) -> TDOutcome:
	if not raw is Dictionary: return TDOutcome.new(false,"INVALID_JIANGNAN_ARCHIVE")
	if raw.is_empty(): return TDOutcome.new(true)
	if not raw.get("residence") is Dictionary or not raw.get("branches") is Dictionary or not raw.get("cells") is Dictionary or not raw.get("old_branch") is Array:
		return TDOutcome.new(false,"INVALID_JIANGNAN_ARCHIVE")
	if not raw.old_branch.is_empty() and not _valid_rect(raw.old_branch):
		return TDOutcome.new(false,"INVALID_JIANGNAN_LEGACY_ARCHIVE")
	for cell: Variant in raw.cells.values():
		if not TDEconomicCell.validate(cell).ok: return TDOutcome.new(false,"INVALID_JIANGNAN_CELL_ARCHIVE")
	for store: Variant in raw.branches.values():
		if not store is Dictionary or not _valid_rect(store.get("rect")) or not TDEconomicCell.validate(store.get("place")).ok:
			return TDOutcome.new(false,"INVALID_JIANGNAN_BRANCH_ARCHIVE")
	return TDOutcome.new(true)

static func _valid_rect(rect: Variant) -> bool:
	if not rect is Array or rect.size()!=4: return false
	for field: Variant in rect:
		if not TDServiceCatalog.integer(field,0,73): return false
	return rect[2]>0 and rect[3]>0 and rect[0]+rect[2]<=73 and rect[1]+rect[3]<=73
