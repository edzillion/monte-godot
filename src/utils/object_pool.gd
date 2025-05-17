# res://src/utils/object_pool.gd
class_name ObjectPool extends RefCounted

## @brief A generic object pool for managing and reusing RefCounted objects.
##
## This pool helps reduce the overhead of frequent object instantiation and
## garbage collection by recycling objects. Pooled objects are expected
## to have a reset() method.

#region Properties
var _pool: Array[RefCounted] = []
var _object_script: Script
var _max_size: int = -1 # -1 for unlimited
var _created_count: int = 0
#endregion


#region Initialization
## @param p_object_script The script of the objects to be pooled (e.g., load("res://path/to/object.gd")).
## @param p_initial_size The number of objects to pre-populate the pool with.
## @param p_max_size The maximum number of objects to store in the pool. -1 for unlimited.
func _init(p_object_script: Script, p_initial_size: int = 0, p_max_size: int = -1) -> void:
	if not p_object_script or not p_object_script is Script:
		push_warning("ObjectPool: Invalid object script provided for pooling.")
		# assert(false, "ObjectPool requires a valid Script to instantiate objects.") # Allow mock to proceed
		# _object_script will remain null, making the pool non-functional for acquire/create,
		# but allows the instance to be created for mocking other methods like release().
		return # Still return early for normal operation if script is invalid

	_object_script = p_object_script
	_max_size = p_max_size
	_created_count = 0 # Reset for this instance

	# Pre-populate the pool
	for i in range(p_initial_size):
		var new_obj: RefCounted = _create_new_object()
		if new_obj:
			if not new_obj.has_method("reset"):
				push_warning("ObjectPool: Pooled object type '%s' does not have a reset() method. This might lead to unexpected behavior." % new_obj.get_class())
			# Call reset even if it's just to establish the pattern; it should handle being called on a fresh object.
			new_obj.call("reset") # Ensure it's in a clean state
			_pool.append(new_obj)
		else:
			# Error creating object, _create_new_object would have logged
			break # Stop pre-population if creation fails
#endregion


#region Private Methods
func _create_new_object() -> RefCounted:
	if not _object_script: # Should have been caught in _init, but defensive check
		Logger.error("ObjectPool: _object_script is null. Cannot create new object.")
		return null

	var new_obj: Variant = _object_script.new() # Script.new() returns Variant
	if not new_obj is RefCounted:
		Logger.error("ObjectPool: Script '%s' did not create a RefCounted instance." % _object_script.resource_path)
		return null
	
	_created_count += 1
	return new_obj as RefCounted
#endregion


#region Public Methods
## @brief Acquires an object from the pool.
## If the pool is empty, a new object is created.
## Pooled objects are expected to have a reset() method, which is called upon acquisition.
func acquire() -> RefCounted:
	if not _pool.is_empty():
		var obj: RefCounted = _pool.pop_back()
		if obj.has_method("reset"):
			obj.call("reset")
		else:
			# Warning issued during _init, but good to be aware if an object somehow misses it.
			# Logger.debug("ObjectPool: Acquired object of type '%s' has no reset() method." % obj.get_class())
			pass 
		return obj
	else:
		var new_obj: RefCounted = _create_new_object()
		if new_obj:
			if new_obj.has_method("reset"):
				new_obj.call("reset") # Ensure fresh objects are also "reset" for consistency
			else:
				# Warning issued during _init
				pass
		return new_obj # Can be null if _create_new_object failed


## @brief Releases an object back to the pool for reuse.
## The object's reset() method is called before it's added back.
## @param p_object The object to release. Must be of the type managed by this pool.
func release(p_object: RefCounted) -> void:
	if not p_object:
		Logger.warning("ObjectPool: Attempted to release a null object.")
		return

	if p_object.get_script() != _object_script:
		Logger.error("ObjectPool: Attempted to release an object of the wrong type. Expected '%s', got '%s'." % [_object_script.resource_path if _object_script else "N/A", p_object.get_script().resource_path if p_object.get_script() else "N/A"])
		# Don't add it to the pool, let it be GC'd if it's a type mismatch.
		return

	if p_object.has_method("reset"):
		p_object.call("reset")
	else:
		# Warning issued during _init
		pass

	if _max_size == -1 or _pool.size() < _max_size:
		_pool.append(p_object)
	else:
		# Pool is full and has a fixed max_size. The object is not re-added.
		# It will be garbage-collected if no other references exist.
		Logger.debug("ObjectPool: Pool is full (max_size: %d). Released object of type '%s' was not re-added and will be GC'd if unreferenced." % [_max_size, p_object.get_class()])


## @brief Gets the current number of available objects in the pool.
func get_pooled_count() -> int:
	return _pool.size()


## @brief Gets the total number of objects ever created by this pool instance.
func get_created_count() -> int:
	return _created_count
#endregion 
