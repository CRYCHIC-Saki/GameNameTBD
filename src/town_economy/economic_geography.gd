class_name TDEconomicGeography
extends RefCounted
## Sparse per-cell overrides + derived defaults, not one Node/Resource per tile.
## Never mutates TDTownMap (owned by building work line).
var _town_id: String
var _plots: Array = []
var _overrides: Dictionary = {}
var _cache: Dictionary = {}
var _layout_version: int = 1
var _regional: bool = false
var _shiomi := false
var _egret_version := 0
var _egret_titles: Array[Rect2i] = []
var _legacy_jiangnan: bool = false
var _anchors: Dictionary = {}

func configure(town_id: String, plots: Array, overrides: Dictionary = {}, layout_version: int = 1) -> void:
	_town_id = town_id
	_layout_version = layout_version
	_plots = plots.duplicate(true)
	_overrides = overrides.duplicate(true)
	_cache.clear()
	_regional=town_id in TDRegionalLayout.IDS and _plots.any(func(p:Dictionary)->bool:return p.get("region_layout_version",1)==2)
	_shiomi=town_id=="tokyo" and _plots.any(func(p:Dictionary)->bool:return p.get("region_layout_version",1)==3)
	_egret_version=0
	_egret_titles.clear()
	if town_id=="paris":
		# Occupancy and player shops can precede the native plots in this list.
		for plot: Dictionary in _plots:
			var version := int(plot.get("region_layout_version",1))
			if version in [4,5,6,7,8,9,10,11,TDEgretLayout.CURRENT_VERSION]:
				_egret_version=version
				break
		if _egret_version != 0 and TDEgretLayout.geography(_egret_version).has("land_use"):
			for title: Dictionary in TDEgretLayout.titles(_egret_version):
				_egret_titles.append(Rect2i(title.x,title.y,title.w,title.h))
	_regional=_regional or _shiomi or _egret_version!=0
	_legacy_jiangnan=not _regional and _plots.any(func(p:Dictionary)->bool:return p.get("jiangnan_layout_revision",2)==1)
	_anchors={"residential":[],"market":[],"station":[]}
	for plot: Dictionary in _plots:
		var kind:=str(plot.kind)
		var origin: String="residential" if kind in ["housing","urban_village","rich_district"] else kind
		if _anchors.has(origin):
			_anchors[origin].append(Vector2i(int(plot.get("approach_x",plot.x)),int(plot.get("approach_y",plot.y))))
	if _egret_version>=5: _anchors.station.append(TDEgretLayout.port(_egret_version))
	elif _regional: _anchors.station.append(TDRegionalLayout.port(town_id))
	elif layout_version == 2 and not _legacy_jiangnan and town_id == "chengdu":
		var surveyed := TDPlannedTown.reference_anchors()
		for kind: String in surveyed:
			_anchors[kind].clear()
			for point: Array in surveyed[kind]:
				_anchors[kind].append(Vector2i(int(point[0]),int(point[1])))

func cell(at: Vector2i) -> Dictionary:
	var key := TDEconomicCell.identity(_town_id, at)
	if _cache.has(key): return _cache[key].duplicate(true)
	var parcel: Dictionary = {}
	for plot: Dictionary in _plots:
		if not Rect2i(int(plot.x),int(plot.y),int(plot.w),int(plot.h)).has_point(at): continue
		parcel=plot
		if plot.kind not in ["diner_lot","factory_lot"] and not plot.get("economic_courtyard",false): break
	var zone: String = str(parcel.get("kind","road"))
	var center_distance := absf(float(at.x)-20.0)+absf(float(at.y)-20.0)
	var visibility := clampf(0.8-center_distance*0.012,0.15,0.9)
	var result: Dictionary = {"schema_version":1,"id":key,"town_id":_town_id,"x":at.x,"y":at.y,"zone_id":zone,"parcel_id":str(parcel.get("id",key)),"land_value_cents":roundi(10000*(0.5+visibility)),"rent_quote_cents_per_day":roundi(8+16*visibility),"visibility":visibility,"attractiveness":0.6 if zone in ["plaza","commercial_street","rich_district"] else 0.4,"reachable":true,"travel_minutes":{"residential":2.0+center_distance*0.3,"station":2.0+absf(float(at.x)-5)*0.3,"market":2.0+absf(float(at.y)-30)*0.3}}
	if _overrides.has(key): result.merge(_overrides[key],true)
	if _layout_version == 2:
		var road := false
		var terrain: Dictionary
		if _egret_version!=0: terrain=TDEgretLayout.terrain(at,_egret_version)
		elif _shiomi: terrain=TDShiomiLayout.terrain(at)
		elif _regional: terrain=TDRegionalLayout.terrain(_town_id,at)
		elif _legacy_jiangnan:
			road=TDLegacyJiangnanLayout.is_road(at)
			terrain=TDLegacyJiangnanLayout.terrain(at,road)
		elif _town_id == "chengdu":
			road=TDPlannedTown.reference_street_in_cell(at)
			terrain=TDPlannedTown.reference_terrain(at)
		else:
			road=TDPlannedTown.is_road(at)
			terrain=TDPlannedTown.terrain(at,road)
		result.merge(terrain, true)
		# A snapshot can carry economic overrides, while the current plan owns
		# parcel identity (e.g. a former residential frontage now houses the inn).
		var grass_access: bool = not _regional and terrain.surface_type=="lawn" and road
		result.zone_id = zone if not parcel.is_empty() else ("road" if grass_access or terrain.surface_type in ["stone","bridge"] else terrain.district_id)
		var surveyed_egret := _egret_version != 0 and terrain.has("zone_id")
		if surveyed_egret:
			if not parcel.has("economic_parcel_id") and not parcel.has("branch_id"):
				result.zone_id = terrain.zone_id
			if result.buildable:
				result.buildable = parcel.is_empty() and not _egret_titles.any(func(title: Rect2i) -> bool: return title.has_point(at))
		result.parcel_id = str(parcel.get("id",key))
		# Saved economic overrides cannot turn a river or hillside into a footpath.
		result.reachable = bool(result.reachable) and bool(terrain.walkable)
		if not _overrides.has(key):
			# Quote the current district by distance from its actual markets, homes
			# and transit stops. Signed leases and historical purchase prices live elsewhere.
			if _shiomi:
				result.travel_minutes=TDShiomiLayout.route_minutes(at)
			elif surveyed_egret:
				result.travel_minutes=TDEgretLayout.route_minutes(at)
			else:
				for origin: String in _anchors:
					var distance: float=100.0
					for stop: Vector2i in _anchors[origin]:
						distance=minf(distance,absi(at.x-stop.x)+absi(at.y-stop.y))
					result.travel_minutes[origin]=2.0+distance*.3
			var access := clampf(1.0-(float(result.travel_minutes.market)*.45+float(result.travel_minutes.residential)*.35+float(result.travel_minutes.station)*.20-2.0)/18.0,0.0,1.0)
			var frontage_zone: String = result.zone_id if surveyed_egret else zone
			var frontage := .12 if grass_access or terrain.surface_type in ["stone","square","quay"] or frontage_zone in ["market","commercial_street","plaza","bank"] else 0.0
			result.visibility = clampf(.15+.60*access+frontage,.15,.90)
			result.attractiveness = clampf(.22+.46*access+frontage,.18,.9)
			if _shiomi:
				if terrain.district_id in ["fish_wharf","shiomi_machiya","civic_centre"]:
					result.visibility=minf(.94,result.visibility+.07)
				if terrain.district_id in ["shrine_ridge","noh_square","onsen_coast"]:
					result.attractiveness=minf(.94,result.attractiveness+.12)
			result.land_value_cents = roundi(10000*(.50+float(result.visibility)))
			result.rent_quote_cents_per_day = roundi(8+16*float(result.visibility))
			if not terrain.walkable and (terrain.surface_type != "lawn" or _town_id != "chengdu" or _legacy_jiangnan):
				result.visibility=0.0
				result.attractiveness=0.0
				result.land_value_cents=0
				result.rent_quote_cents_per_day=0
		if ((_shiomi or surveyed_egret) and not terrain.walkable) or (_town_id == "chengdu" and not _legacy_jiangnan and terrain.surface_type in ["water","sea"]):
			result.visibility=0.0
			result.attractiveness=0.0
			result.land_value_cents=0
			result.rent_quote_cents_per_day=0
	_cache[key]=result
	return result.duplicate(true)

func parcel_quote(parcel_id: String) -> Dictionary:
	var total_land: int = 0
	var total_rent: int = 0
	var cells: int = 0
	for plot: Dictionary in _plots:
		if plot.id != parcel_id: continue
		for x: int in range(int(plot.x),int(plot.x+plot.w)):
			for y: int in range(int(plot.y),int(plot.y+plot.h)):
				var value:=cell(Vector2i(x,y))
				total_land+=int(value.land_value_cents);total_rent+=int(value.rent_quote_cents_per_day);cells+=1
	return {"parcel_id":parcel_id,"cells":cells,"land_value_cents":total_land,"rent_quote_cents_per_day":total_rent}
