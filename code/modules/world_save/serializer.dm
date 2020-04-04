#define IS_PROC(X) (findtext("\ref[X]", "0x26"))

/datum/persistence/serializer
	var/thing_index = 1
	var/var_index = 1
	var/list_index = 1
	var/element_index = 1

	var/list/thing_map = list()
	var/list/reverse_map = list()
	var/list/list_map = list()
	var/list/reverse_list_map = list()

	var/list/thing_inserts = list()
	var/list/var_inserts = list()
	var/list/element_inserts = list()

	var/datum/persistence/load_cache/resolver/resolver = new()
	var/list/ignore_if_empty = list("pixel_x", "pixel_y", "density", "opacity", "blend_mode", "fingerprints", "climbers", "contents", "suit_fibers", "was_bloodied", "last_bumped", "blood_DNA", "id_tag", "x", "y", "z", "loc")
	var/autocommit = TRUE // whether or not to autocommit after a certain number of inserts.
	var/inserts_since_commit = 0
	var/autocommit_threshold = 5000

#ifdef SAVE_DEBUG
	var/verbose_logging = FALSE
#endif

/datum/persistence/serializer/proc/should_flatten(var/datum/thing)
	if(isnull(thing))
		return FALSE
	return thing.type in GLOB.flatten_types

/datum/persistence/serializer/proc/FlattenThing(var/datum/thing)
	var/list/results = list()
	for(var/V in thing.get_saved_vars())
		if(!issaved(thing.vars[V]))
			continue
		var/VV = thing.vars[V]
		if(VV == initial(thing.vars[V]))
			continue
		if(islist(VV))
			var/list/_list = list()
			for(var/LKEY in _list)
				var/K
				if(istext(LKEY) || isnum(LKEY) || isnull(LKEY))
					K = LKEY
				else if(istype(LKEY, /datum))
					if(should_flatten(LKEY))
						K = "FLAT_OBJ#[FlattenThing(LKEY)]"
					else
						K = "OBJ#[SerializeThing(LKEY)]"
				try
					var/value = _list[LKEY]
					if(istext(value) || isnum(value) || isnull(value))
						_list[K] = value
					else if(istype(value, /datum))
						if(should_flatten(value))
							_list[K] = "FLAT_OBJ#[FlattenThing(value)]"
						else
							_list[K] = "OBJ#[SerializeThing(value)]"
				catch
					_list.Add(K)
			results[V] = _list
		else if(istext(VV) || isnum(VV) || isnull(VV))
			results[V] = VV
		else if(istype(VV, /datum))
			if(should_flatten(VV))
				results[V] = "FLAT_OBJ#[FlattenThing(VV)]"
			else
				results[V] = "OBJ#[SerializeThing(VV)]"
	return "[thing.type]|[json_encode(results)]"

/datum/persistence/serializer/proc/SerializeList(var/_list, var/datum/parent_thing)
	if(isnull(_list) || !islist(_list))
		return

	var/list/existing = list_map["\ref[_list]"]
	if(existing)
#ifdef SAVE_DEBUG
		to_world_log("(SerializeList-Resv) \ref[_list] to [existing]")
		CHECK_TICK
#endif
		return existing

	var/l_i = list_index
	list_index++
	inserts_since_commit++
	list_map["\ref[_list]"] = l_i

	var/I = 1
	for(var/key in _list)
		var/ET = "NULL"
		var/KT = "NULL"
		var/KV = key
		var/EV = null
		if(!isnum(key))
			try
				EV = _list[key]
			catch
				EV = null // NBD... No value.

		if (isnull(key))
			KT = "NULL"
		else if(isnum(key))
			KT = "NUM"
		else if (istext(key))
			KT = "TEXT"
		else if (ispath(key) || IS_PROC(key))
			KT = "PATH"
		else if (isfile(key))
			KT = "FILE"
		else if (islist(key))
			KT = "LIST"
			KV = SerializeList(key)
			if(isnull(KV))
#ifdef SAVE_DEBUG
				to_world_log("(SerializeListElem-Skip) Key thing is null.")
#endif
				continue
		else if(isarea(key))
			KT = "AREA"
			KV = SerializeArea(KV)
			if(isnull(KV))
				continue
		else if(istype(key, /datum))
			var/datum/key_d = key
			if(!key_d.should_save(parent_thing))
				continue
			if(should_flatten(KV))
				KT = "FLAT_OBJ" // If we flatten an object, the var becomes json. This saves on indexes for simple objects.
				KV = FlattenThing(KV)
			else
				KT = "OBJ"
				KV = SerializeThing(KV)
			if(isnull(KV))
#ifdef SAVE_DEBUG
				to_world_log("(SerializeListElem-Skip) Key list is null.")
#endif
				continue
		else
#ifdef SAVE_DEBUG
			to_world_log("(SerializeListElem-Skip) Unknown Key. Value: [key]")
#endif
			continue

		if(!isnull(key) && !isnull(EV))
			if(isnum(EV))
				ET = "NUM"
			else if (istext(EV))
				ET = "TEXT"
			else if (isnull(EV))
				ET = "NULL"
			else if (ispath(EV) || IS_PROC(EV))
				ET = "PATH"
			else if (isfile(EV))
				ET = "FILE"
			else if (islist(EV))
				ET = "LIST"
				EV = SerializeList(EV)
				if(isnull(EV))
#ifdef SAVE_DEBUG
					to_world_log("(SerializeListElem-Skip) Value list is null.")
#endif
					continue
			else if(isarea(key))
				ET = "AREA"
				EV = SerializeArea(EV)
				if(isnull(EV))
					continue
			else if (istype(EV, /datum))
				if(should_flatten(EV))
					ET = "FLAT_OBJ" // If we flatten an object, the var becomes json. This saves on indexes for simple objects.
					EV = FlattenThing(EV)
				else
					ET = "OBJ"
					EV = SerializeThing(EV)
				if(isnull(EV))
#ifdef SAVE_DEBUG
					to_world_log("(SerializeListElem-Skip) Value thing is null.")
#endif
					continue
			else
				// Don't know what this is. Skip it.
#ifdef SAVE_DEBUG
				to_world_log("(SerializeListElem-Skip) Unknown Value")
#endif
				continue
		KV = sanitizeSQL("[KV]")
		EV = sanitizeSQL("[EV]")
#ifdef SAVE_DEBUG
		if(verbose_logging)
			to_world_log("(SerializeListElem-Done) ([element_index],[l_i],[I],\"[KV]\",'[KT]',\"[EV]\",\"[ET]\")")
#endif
		element_inserts.Add("([element_index],[l_i],[I],\"[KV]\",'[KT]',\"[EV]\",\"[ET]\")")
		inserts_since_commit++
		element_index++
		I++
	return l_i

/datum/persistence/serializer/proc/SerializeThing(var/datum/thing)
	// Check for existing references first. If we've already saved
	// there's no reason to save again.
	if(isnull(thing) || !thing.should_save)
		return

	if(isnull(GLOB.saved_vars[thing.type]))
		return // EXPERIMENTAL. Don't save things without a whitelist.

	var/datum/existing = thing_map["\ref[thing]"]
	if (existing)
#ifdef SAVE_DEBUG
		to_world_log("(SerializeThing-Resv) \ref[thing] to [existing]")
		CHECK_TICK
#endif
		return existing

	// Thing didn't exist. Create it.
	var/t_i = thing_index
	thing_index++

	var/x = 0
	var/y = 0
	var/z = 0

	thing.before_save() // Before save hook.
	// var/datum/default_instance
	if(ispath(thing.type, /turf))
		var/turf/T = thing
		x = T.x
		y = T.y
		z = T.z
	// else
	// 	try
	// 		default_instance = new thing.type()
	// 	catch
	// 		default_instance = null // Not needed, we know it's null. Some things won't let me do this, so eh..
	//		// Just accept we're serializing the whole thing.

#ifdef SAVE_DEBUG
	to_world_log("(SerializeThing) ([t_i],'[thing.type]',[x],[y],[z])")
#endif
	thing_inserts.Add("([t_i],'[thing.type]',[x],[y],[z])")
	inserts_since_commit++
	thing_map["\ref[thing]"] = t_i

	for(var/V in thing.get_saved_vars())
		if(!issaved(thing.vars[V]))
			continue
		var/VV = thing.vars[V]
		var/VT = "VAR"
#ifdef SAVE_DEBUG
		to_world_log("(SerializeThingVar) [V]")
#endif
		// EXPERIMENTAL SAVING OPTIMIZATION OH FUCK
		// if(default_instance && default_instance.vars[V] == VV)
			// continue // Don't save things that are 'default value'. doh.
		if(VV == initial(thing.vars[V]))
			continue

		// hacking in some other optimizations
		for(var/ignore in ignore_if_empty)
			if(V == ignore)
				if(!VV)
					continue
				if(islist(VV) && !length(VV))
					continue

		if(islist(VV) && !isnull(VV))
			// Complex code for serializing lists...
			if(length(VV) == 0)
				// Another optimization. Don't need to serialize lists
				// that have 0 elements.
#ifdef SAVE_DEBUG
				to_world_log("(SerializeThingVar-Skip) Zero Length List")
#endif
				continue
			VT = "LIST"
			VV = SerializeList(VV, thing)
			if(isnull(VV))
#ifdef SAVE_DEBUG
				to_world_log("(SerializeThingVar-Skip) Null List")
#endif
				continue
		else if (isnum(VV))
			VT = "NUM"
		else if (istext(VV))
			VT = "TEXT"
		else if (ispath(VV) || IS_PROC(VV)) // After /datum check to avoid high-number obj refs
			VT = "PATH"
		else if (isfile(VV))
			VT = "FILE"
		else if (isnull(VV))
			VT = "NULL"
		else if (isarea(VV))
			VT = "AREA"
			VV = SerializeArea(VV)
			if(isnull(VV))
				continue
		else if (istype(VV, /datum))
			var/datum/VD = VV
			if(!VD.should_save(thing))
				continue
			// Serialize it complex-like, baby.
			if(should_flatten(VV))
				VT = "FLAT_OBJ" // If we flatten an object, the var becomes json. This saves on indexes for simple objects.
				VV = FlattenThing(VV)
			else
				VT = "OBJ"
				VV = SerializeThing(VV)
			if(isnull(VV))
#ifdef SAVE_DEBUG
				to_world_log("(SerializeThingVar-Skip) Null Thing")
#endif
				continue
		else
			// We don't know what this is. Skip it.
#ifdef SAVE_DEBUG
			to_world_log("(SerializeThingVar-Skip) Unknown Var")
#endif
			continue
		VV = sanitizeSQL("[VV]")
#ifdef SAVE_DEBUG
		to_world_log("(SerializeThingVar-Done) ([var_index],[t_i],'[V]','[VT]',\"[VV]\")")
#endif
		var_inserts.Add("([var_index],[t_i],'[V]','[VT]',\"[VV]\")")
		inserts_since_commit++
		var_index++
	// if(default_instance)
	// 	try
	// 		qdel(default_instance) // After we've checked out the default vars, we don't need it anymore. Off to GC you go.
	// 	catch
	// 		to_world_log("Instance of type [thing.type] resisted being deleted. Double check it's allowed to be QDEL'd on save.")
	thing.after_save() // After save hook.
	if(inserts_since_commit > autocommit_threshold)
		Commit()
	return t_i

/datum/persistence/serializer/proc/SerializeArea(var/area/A)
	var/existing = thing_map["\ref[A]"]
	if(existing) return existing
	if(istype(A, /area/space)) return
	var/datum/wrapper/area/wrapper = new(A)

	var/area_id = SerializeThing(wrapper)
	thing_map["\ref[A]"] = area_id
	return area_id

/datum/persistence/serializer/proc/DeserializeThing(var/datum/persistence/load_cache/thing/thing)
#ifdef SAVE_DEBUG
	var/list/deserialized_vars = list()
#endif

	// Checking for existing items.
	var/datum/existing = reverse_map["[thing.id]"]
	if(existing)
		return existing
	// Handlers for specific types would go here.
	if (ispath(thing.thing_type, /turf))
		// turf turf turf
		var/turf/T = locate(thing.x, thing.y, thing.z)
		if (!T)
			to_world_log("Attempting to deserialize onto turf [thing.x],[thing.y],[thing.z] failed. Could not locate turf.")
			return
		T.ChangeTurf(thing.thing_type)
		existing = T
		// Try to QDEL contents list just to be safe.
		try
			QDEL_NULL_LIST(T.contents)
		catch
	else
		// default creation
		existing = new thing.thing_type()
	reverse_map["[thing.id]"] = existing
	// Fetch all the variables for the thing.
	for(var/datum/persistence/load_cache/thing_var/TV in thing.thing_vars)
		// Each row is a variable on this object.
#ifdef SAVE_DEBUG
		deserialized_vars.Add("[TV.key]:[TV.var_type]")
#endif
		try
			switch(TV.var_type)
				if("NUM")
					existing.vars[TV.key] = text2num(TV.value)
				if("TEXT")
					existing.vars[TV.key] = TV.value
				if("PATH")
					existing.vars[TV.key] = text2path(TV.value)
				if("NULL")
					existing.vars[TV.key] = null
				if("LIST")
					existing.vars[TV.key] = DeserializeList(TV.value)
				if("OBJ")
					existing.vars[TV.key] = QueryAndDeserializeThing(TV.value)
				if("FLAT_OBJ")
					existing.vars[TV.key] = QueryAndInflateThing(TV.value)
				if("FILE")
					existing.vars[TV.key] = file(TV.value)
				if("AREA")
					existing.vars[TV.key] = DeserializeArea(TV.value)
		catch(var/exception/e)
			to_world_log("Failed to deserialize '[TV.key]' of type '[TV.var_type]' on line [e.line] / file [e.file] for reason: '[e]'.")
#ifdef SAVE_DEBUG
	to_world_log("Deserialized thing of type [thing.thing_type] ([thing.x],[thing.y],[thing.z]) with vars: " + jointext(deserialized_vars, ", "))
#endif
	return existing

/datum/persistence/serializer/proc/QueryAndDeserializeThing(var/thing_id)
	var/datum/existing = reverse_map["[thing_id]"]
	if(!isnull(existing))
		return existing
	return DeserializeThing(resolver.things["[thing_id]"])

// This method will look a thing by its ID from the cache and deflate if it.
// This should only be called if the thing was a flattened object. It will not work
// on normal objects.
/datum/persistence/serializer/proc/QueryAndInflateThing(var/thing_json)
	var/list/tokens = splittext(thing_json, "|")
	var/thing_type = text2path(tokens[1])
	var/datum/existing = new thing_type
	var/list/vars = json_decode(jointext(tokens.Copy(2), "|"))
	return InflateThing(existing, vars)

/datum/persistence/serializer/proc/InflateThing(var/datum/thing, var/list/thing_vars)
	for(var/V in thing_vars)
		var/encoded_value = thing_vars[V]
		if(istext(encoded_value) && findtext(encoded_value, "OBJ#", 1, 5))
			// This is an object reference.
			thing.vars[V] = QueryAndDeserializeThing(copytext(encoded_value, 5))
			continue
		if(islist(encoded_value))
			thing.vars[V] = InflateList(encoded_value)
			continue
		thing.vars[V] = encoded_value
	return thing

/datum/persistence/serializer/proc/InflateList(var/list/_list)
	var/list/final_list = list()
	for(var/K in _list)
		var/key = K
		if(istext(K) && findtext(K, "OBJ#", 1, 2))
			key = QueryAndDeserializeThing(copytext(K, 5))
		else if(istext(K) && findtext(K, "FLAT_OBJ#", 1, 2))
			key = QueryAndInflateThing(copytext(K, 10))
		else if(islist(K))
			key = InflateList(K)
		try
			var/V = _list[K]
			if(istext(V) && findtext(V, "OBJ#", 1, 2))
				V = QueryAndDeserializeThing(copytext(V, 5))
			else if(istext(K) && findtext(K, "FLAT_OBJ#", 1, 2))
				V = QueryAndInflateThing(copytext(V, 10))
			else if(islist(V))
				V = InflateList(V)
			final_list[key] = V
		catch
			final_list.Add(key)
	return final_list

/datum/persistence/serializer/proc/DeserializeList(var/list_id, var/list/existing)
	// Will deserialize and return a list.
	if(!dbcon.IsConnected())
		return

	if(isnull(existing))
		existing = reverse_list_map["[list_id]"]
		if(isnull(existing))
			existing = list()
	reverse_list_map["[list_id]"] = existing

	// We gotta resolve the list.
	var/list/raw_list = resolver.lists["[list_id]"]
	// to_world_log("deserializing list with [length(raw_list)] elements.")
	for(var/datum/persistence/load_cache/list_element/LE in raw_list)
		var/key_value
		// to_world_log("deserializing list element [LE.key_type].")
		try
			switch(LE.key_type)
				if("NULL")
					key_value = null
				if("TEXT")
					key_value = LE.key
				if("NUM")
					key_value = text2num(LE.key)
				if("PATH")
					key_value = text2path(LE.key)
				if("LIST")
					key_value = DeserializeList(LE.key)
				if("OBJ")
					key_value = QueryAndDeserializeThing(LE.key)
				if("FLAT_OBJ")
					key_value = QueryAndInflateThing(LE.key)
				if("FILE")
					key_value = file(LE.key)
				if("AREA")
					key_value = DeserializeArea(LE.key)

			switch(LE.value_type)
				if("NULL")
					// This is how lists are made. Everything else is a dict.
					existing.Add(key_value)
				if("TEXT")
					existing[key_value] = LE.value
				if("NUM")
					existing[key_value] = text2num(LE.value)
				if("PATH")
					existing[key_value] = text2path(LE.value)
				if("LIST")
					existing[key_value] = DeserializeList(LE.value)
				if("OBJ")
					existing[key_value] = QueryAndDeserializeThing(LE.value)
				if("FLAT_OBJ")
					existing[key_value] = QueryAndInflateThing(LE.value)
				if("FILE")
					existing[key_value] = file(LE.value)
				if("AREA")
					existing[key_value] = DeserializeArea(LE.value)

		catch(var/exception/e)
			to_world_log("Failed to deserialize list [list_id] element [key_value] on line [e.line] / file [e.file] for reason: [e].")

	return existing

/datum/persistence/serializer/proc/DeserializeArea(var/area_id)
	var/existing = reverse_map["[area_id]"]
	if(existing)
		return existing

	var/datum/wrapper/area/area_wrapper = QueryAndDeserializeThing(area_id)
	var/area/A = new area_wrapper.area_type()
	A.name = area_wrapper.name
	A.has_gravity = area_wrapper.has_gravity
	A.apc = area_wrapper.apc
	A.power_light = area_wrapper.power_light
	A.power_equip = area_wrapper.power_equip
	A.power_environ = area_wrapper.power_environ
	var/list/turfs = list()
	for(var/index in 1 to length(area_wrapper.turfs))
		var/list/coords = splittext(area_wrapper.turfs[index], ",")
		var/turf/T = locate(text2num(coords[1]), text2num(coords[2]), text2num(coords[3]))
		turfs |= T
	A.contents.Add(turfs)

	reverse_map["[area_id]"] = A
	return A

/datum/persistence/serializer/proc/Commit()
	establish_db_connection()
	if(!dbcon.IsConnected())
		return

	var/DBQuery/query
	try
		if(length(thing_inserts) > 0)
			query = dbcon.NewQuery("INSERT INTO `thing`(`id`,`type`,`x`,`y`,`z`) VALUES[jointext(thing_inserts, ",")]")
			query.Execute()
			if(query.ErrorMsg())
				to_world_log("THING SERIALIZATION FAILED: [query.ErrorMsg()].")
		if(length(var_inserts) > 0)
			query = dbcon.NewQuery("INSERT INTO `thing_var`(`id`,`thing_id`,`key`,`type`,`value`) VALUES[jointext(var_inserts, ",")]")
			query.Execute()
			if(query.ErrorMsg())
				to_world_log("VAR SERIALIZATION FAILED: [query.ErrorMsg()].")
		if(length(element_inserts) > 0)
			query = dbcon.NewQuery("INSERT INTO `list_element`(`id`,`list_id`,`index`,`key`,`key_type`,`value`,`value_type`) VALUES[jointext(element_inserts, ",")]")
			query.Execute()
			if(query.ErrorMsg())
				to_world_log("ELEMENT SERIALIZATION FAILED: [query.ErrorMsg()].")
	catch (var/exception/e)
		to_world_log("World Serializer Failed")
		to_world_log(e)

	thing_inserts.Cut(1)
	var_inserts.Cut(1)
	element_inserts.Cut(1)
	inserts_since_commit = 0


/datum/persistence/serializer/proc/Clear()
	thing_inserts.Cut(1)
	var_inserts.Cut(1)
	element_inserts.Cut(1)
	thing_map.Cut(1)
	reverse_map.Cut(1)
	list_map.Cut(1)
	reverse_list_map.Cut(1)

// Deletes all saves from the database.
/datum/persistence/serializer/proc/WipeSave()
	var/DBQuery/query = dbcon.NewQuery("TRUNCATE TABLE `thing`;")
	query.Execute()
	if(query.ErrorMsg())
		to_world_log("UNABLE TO WIPE PREVIOUS SAVE: [query.ErrorMsg()].")
	query = dbcon.NewQuery("TRUNCATE TABLE `thing_var`;")
	query.Execute()
	if(query.ErrorMsg())
		to_world_log("UNABLE TO WIPE PREVIOUS SAVE: [query.ErrorMsg()].")
	query = dbcon.NewQuery("TRUNCATE TABLE `list_element`;")
	query.Execute()
	if(query.ErrorMsg())
		to_world_log("UNABLE TO WIPE PREVIOUS SAVE: [query.ErrorMsg()].")
	Clear()

	thing_index = 1
	var_index = 1
	list_index = 1
	element_index = 1
	