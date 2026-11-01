class_name TDQuestPath
extends RefCounted
## Bounded 4-neighbour search. Chooses the nearest reachable point to an object;
## target cells may be solid, but no returned segment traverses one.
static func find(start: Vector2i, target: Vector2i, bounds: Rect2i, walkable: Callable) -> Array[Vector2i]:
	var result: Array[Vector2i]=[]
	if not bounds.has_point(start) or not walkable.call(start): return result
	var queue: Array[Vector2i]=[start]
	var parent: Dictionary={start:start}
	var best:=start;var best_distance:=start.distance_squared_to(target);var head:=0
	while head<queue.size() and head<12000:
		var here:=queue[head];head+=1
		var gap:=here.distance_squared_to(target)
		if gap<best_distance: best=here;best_distance=gap
		if gap==0: break
		for step: Vector2i in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]:
			var next:=here+step
			if parent.has(next) or not bounds.has_point(next) or not walkable.call(next): continue
			parent[next]=here;queue.append(next)
	var cell:=best
	while cell!=start:
		result.push_front(cell);cell=parent[cell]
	result.push_front(start)
	return result
