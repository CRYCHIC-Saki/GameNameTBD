class_name TDEconomicGeography
extends RefCounted
## Sparse per-cell overrides + derived defaults, not one Node/Resource per tile.
## Never mutates TDTownMap (owned by building work line).
var _town_id: String
var _plots: Array = []
var _overrides: Dictionary = {}
var _cache: Dictionary = {}

func configure(town_id: String, plots: Array, overrides: Dictionary = {}) -> void:
	_town_id = town_id
	_plots = plots.duplicate(true)
	_overrides = overrides.duplicate(true)
	_cache.clear()

func cell(at: Vector2i) -> Dictionary:
	var key := TDEconomicCell.identity(_town_id, at)
	if _cache.has(key): return _cache[key].duplicate(true)
	var parcel: Dictionary = {}
	for plot: Dictionary in _plots:
		if Rect2i(int(plot.x),int(plot.y),int(plot.w),int(plot.h)).has_point(at): parcel=plot;break
	var zone: String = str(parcel.get("kind","road"))
	var center_distance := absf(float(at.x)-20.0)+absf(float(at.y)-20.0)
	var visibility := clampf(0.8-center_distance*0.012,0.15,0.9)
	var result: Dictionary = {"schema_version":1,"id":key,"town_id":_town_id,"x":at.x,"y":at.y,"zone_id":zone,"parcel_id":str(parcel.get("id",key)),"land_value_cents":roundi(10000*(0.5+visibility)),"rent_quote_cents_per_day":roundi(8+16*visibility),"visibility":visibility,"attractiveness":0.6 if zone in ["plaza","commercial_street","rich_district"] else 0.4,"reachable":true,"travel_minutes":{"residential":2.0+center_distance*0.3,"station":2.0+absf(float(at.x)-5)*0.3,"market":2.0+absf(float(at.y)-30)*0.3}}
	if _overrides.has(key): result.merge(_overrides[key],true)
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
