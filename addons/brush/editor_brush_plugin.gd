@tool
extends EditorPlugin

var PaintButton = preload("res://addons/brush/scenes/paint_button.tscn")
var TempObjectMat = preload("res://addons/brush/resources/temp_object_mat.tres")

var painting := false
var placing := false

var _dock: Control = null
var _resource: PackedScene = null
var _current_item: Node3D = null
var _tree: Tree = null
var _parent_node: Node = null


func _enter_tree():
	_dock = PaintButton.instance() as Control
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _dock)

	var button := _dock.get_node("Button") as Button
	button.connect("pressed", self.toggle_painting)
	button.set_button_icon(get_plugin_icon())

	var vsplit = get_editor_interface().get_file_system_dock().get_child(3)
	for c in vsplit.get_children():
		if c is Tree:
			_tree = c
			_tree.connect("cell_selected", self.file_picked)
			break

	change_parent_node()
	get_editor_interface().get_selection().connect("selection_changed", self.change_parent_node)


func _exit_tree():
	_tree.disconnect("cell_selected", self.file_picked)

	if _current_item != null and is_instance_valid(_current_item):
		_current_item.free()
		_current_item = null

	if _dock != null and is_instance_valid(_dock):
		remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _dock)

		var button := _dock.get_node("Button") as Button
		button.disconnect("pressed", self.toggle_painting)

		_dock.free()
		_dock = null

	get_editor_interface().get_selection().disconnect("selection_changed", self.change_parent_node)


func get_plugin_icon() -> Texture:
	var base_color = get_editor_interface().get_editor_settings().get_setting(
		"interface/theme/base_color"
	)
	var theme = "light" if base_color.v > 0.5 else "dark"
	var base_icon = load("res://addons/brush/assets/icons/icon_%s.svg" % [theme]) as Texture

	var size = (
		get_editor_interface().get_editor_viewport().get_icon("Godot", "EditorIcons").get_size()
	)
	var image: Image = base_icon.get_data()
	image.resize(size.x, size.y, Image.INTERPOLATE_TRILINEAR)
	var texture = ImageTexture.new()
	texture.create_from_image(image)
	return texture


func change_parent_node():
	var parent_nodes = get_editor_interface().get_selection().get_selected_nodes()
	if !parent_nodes.empty():
		_parent_node = parent_nodes[0]
	else:
		_parent_node = get_editor_interface().get_edited_scene_root()


func toggle_painting():
	var button := _dock.get_node("Button") as Button
	painting = !painting
	if !painting:
		if _current_item != null and is_instance_valid(_current_item):
			_current_item.free()
			_current_item = null
		button.set_pressed(false)
	else:
		set_up_temp_object()
		button.set_pressed(true)


func forward_Node3D_gui_input(camera: Camera3D, event: InputEvent):
	if !painting or _current_item == null or not is_instance_valid(_current_item):
		return false

	if event is InputEventMouseMotion:
		if Input.is_physical_key_pressed(KEY_SHIFT):
			_current_item.rotate_object_local(Vector3(0, 1, 0), event.relative.x / 10)
			return true

		if !placing:
			var ray_origin := camera.project_ray_origin(event.position)
			var ray_dir := camera.project_ray_normal(event.position)
			var ray_distance := camera.far
			var space_state := get_viewport().get_world_3d().direct_space_state
			var query := PhysicsRayQueryParameters3D.create(
				ray_origin, ray_origin + ray_dir * ray_distance
			)
			var hit := space_state.intersect_ray(query)
			if !hit.is_empty() and hit.has("position"):
				_current_item.global_transform.origin = hit.get("position") as Vector3
			return false

	elif (
		event is InputEventMouseButton
		and event.pressed == true
		and event.button_index == MOUSE_BUTTON_RIGHT
	):
		placing = true

	elif (
		event is InputEventMouseButton
		and event.pressed == false
		and event.button_index == MOUSE_BUTTON_LEFT
	):
		placing = false
		var undo_redo := get_undo_redo()
		undo_redo.create_action("Add object")

		var new_item := _resource.instance() as Node3D
		undo_redo.add_do_method(
			self, "redo_paint", new_item, _current_item.global_transform, _parent_node
		)
		undo_redo.add_do_reference(new_item)
		undo_redo.add_undo_method(_parent_node, "remove_child", new_item)
		undo_redo.commit_action()
		return true

	elif event is InputEventMouse and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if Input.is_physical_key_pressed(KEY_SHIFT):
			return false

		_current_item.scale = _current_item.scale * 0.9
		return true

	elif event is InputEventMouse and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		if Input.is_physical_key_pressed(KEY_SHIFT):
			return false

		_current_item.scale = _current_item.scale * 1.1
		return true

	return false


func handles(_object):
	return true


func file_picked():
	if _current_item != null and is_instance_valid(_current_item):
		_current_item.free()
		_current_item = null

	if !painting:
		return

	set_up_temp_object()


func set_up_temp_object() -> void:
	if _tree == null:
		var vsplit = get_editor_interface().get_file_system_dock().get_child(3)
		for c in vsplit.get_children():
			if c is Tree:
				_tree = c
				break

	# get_editor_interface().get_current_path() returns the wrong path at this point
	# i.e. the previously selected node
	# So we must get the file tree selected item instead
	var path := _tree.get_selected().get_metadata(0) as String

	if ResourceLoader.exists(path):
		_resource = load(path) as PackedScene
		if _resource != null:
			_current_item = add_temp_item(_resource)
			_current_item.set_name("TEMPORARY OBJECT")


func add_temp_item(resource: PackedScene) -> Node3D:
	var new_item := resource.instance() as Node3D
	get_editor_interface().get_edited_scene_root().add_child(new_item)
	if new_item is MeshInstance3D:
		new_item.material_override = TempObjectMat
	else:
		for c in new_item.get_children():
			if c is MeshInstance3D:
				c.material_override = TempObjectMat
	return new_item


func redo_paint(new_item: Node3D, transform: Transform3D, parent_node: Node):
	if parent_node == null:
		parent_node = get_editor_interface().get_edited_scene_root()
	parent_node.add_child(new_item)
	new_item.owner = get_editor_interface().get_edited_scene_root()
	new_item.global_transform.origin = transform.origin
	new_item.global_transform.basis = transform.basis
