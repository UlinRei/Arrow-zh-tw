extends Node

# Android-only compatibility layer. This autoload removes itself immediately on
# desktop and Web exports, so the original layouts and input behavior stay intact.

const LONG_PRESS_SECONDS := 0.55
const LONG_PRESS_MOVE_TOLERANCE := 18.0
const PANEL_SHRINK_FACTOR := 0.94

const ACTION_SELECT_BRANCH := 0
const ACTION_SELECT_WATERFALL := 1
const ACTION_COPY_TO_SYSTEM_CLIPBOARD := 2
const ACTION_PASTE_FROM_SYSTEM_CLIPBOARD := 3
const ACTION_CLEAR_SELECTION := 4

var Main
var Grid
var ContextMenu
var ContextTools
var PathDialog

var _touch_active := false
var _touch_index := -1
var _touch_origin := Vector2.ZERO
var _touch_position := Vector2.ZERO
var _touch_grid_offset := Vector2.ZERO
var _touch_elapsed := 0.0
var _touch_target_node_id := -1
var _selection_before_touch: Array = []

var _touch_points: Dictionary = {}
var _pinch_active := false
var _pinch_start_distance := 1.0
var _pinch_start_zoom := 1.0
var _pinch_anchor_graph_position := Vector2.ZERO

var _android_tools_button: MenuButton
var _android_tools_popup: PopupMenu


func _ready() -> void:
	if OS.get_name() != "Android":
		queue_free()
		return

	set_process(true)
	set_process_input(true)
	call_deferred("_setup_android")


func _setup_android() -> void:
	Main = get_node_or_null("/root/Main")
	if Main == null:
		await get_tree().process_frame
		call_deferred("_setup_android")
		return

	Grid = get_node_or_null("/root/Main/Editor/Center/Grid")
	ContextMenu = get_node_or_null("/root/Main/FloatingTools/Control/Context")
	ContextTools = get_node_or_null("/root/Main/FloatingTools/Control/Context/Menu/Tools")
	PathDialog = get_node_or_null("/root/Main/Overlays/Control/PathDialog")

	if Grid == null || ContextMenu == null || ContextTools == null || PathDialog == null:
		push_error("Android adapter could not find the expected Arrow UI nodes.")
		return

	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
	PathDialog.use_native_dialog = true

	_configure_android_storage_and_fonts()
	_shrink_android_panels()
	_install_android_context_tools()


func _configure_android_storage_and_fonts() -> void:
	var work_dir_row := get_node_or_null(
		"/root/Main/Overlays/Control/Preferences/Margin/Sections/Configs/Scroll/Params/WorkDir"
	)
	if work_dir_row != null:
		work_dir_row.hide()

	var external_font_button := get_node_or_null(
		"/root/Main/Overlays/Control/Preferences/Margin/Sections/Configs/Scroll/Params/Font/Selector/Tools/Browse"
	)
	if external_font_button != null:
		external_font_button.hide()
		external_font_button.disabled = true

	var configuration_changed := false
	if Main.Configs.CONFIRMED.get("app_local_dir_path", "user://") != "user://":
		Main.Configs.CONFIRMED["app_local_dir_path"] = "user://"
		configuration_changed = true

	var configured_font = Main.Configs.CONFIRMED.get("appearance_font", "auto")
	if (
		configured_font is String
		and configured_font not in ["auto", "default"]
		and not configured_font.begins_with("res://")
	):
		Main.Configs.CONFIRMED["appearance_font"] = "auto"
		Main.UI.update_view_from_configuration({"appearance_font": "auto"})
		configuration_changed = true

	if configuration_changed:
		Main.Configs.save_configurations_and_confirm(Main.Configs.CONFIRMED, null, true)
		Main.call_deferred("dynamically_update_local_app_dir", "user://")


func _shrink_android_panels() -> void:
	# Shrink only floating/overlay panels. The desktop scene file is untouched.
	var panel_paths := [
		"/root/Main/FloatingTools/Control/Inspector",
		"/root/Main/FloatingTools/Control/Console",
		"/root/Main/Overlays/Control/About",
		"/root/Main/Overlays/Control/Preferences",
		"/root/Main/Overlays/Control/Authors",
		"/root/Main/Overlays/Control/NewDocument",
	]

	for path in panel_paths:
		var panel := get_node_or_null(path) as Control
		if panel != null:
			_shrink_control_anchors(panel, PANEL_SHRINK_FACTOR)


func _shrink_control_anchors(control: Control, factor: float) -> void:
	var center_x := (control.anchor_left + control.anchor_right) * 0.5
	var center_y := (control.anchor_top + control.anchor_bottom) * 0.5

	control.anchor_left = center_x + (control.anchor_left - center_x) * factor
	control.anchor_right = center_x + (control.anchor_right - center_x) * factor
	control.anchor_top = center_y + (control.anchor_top - center_y) * factor
	control.anchor_bottom = center_y + (control.anchor_bottom - center_y) * factor


func _install_android_context_tools() -> void:
	if _android_tools_button != null:
		return

	_android_tools_button = MenuButton.new()
	_android_tools_button.name = "AndroidTools"
	_android_tools_button.text = tr("ANDROID_TOOLS")
	_android_tools_button.tooltip_text = tr("ANDROID_TOOLS_TOOLTIP")
	_android_tools_button.custom_minimum_size = Vector2(96, 32)
	_android_tools_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ContextTools.add_child(_android_tools_button)

	_android_tools_popup = _android_tools_button.get_popup()
	_android_tools_popup.add_item(tr("ANDROID_SELECT_BRANCH"), ACTION_SELECT_BRANCH)
	_android_tools_popup.add_item(tr("ANDROID_SELECT_WATERFALL"), ACTION_SELECT_WATERFALL)
	_android_tools_popup.add_separator()
	_android_tools_popup.add_item(
		tr("ANDROID_COPY_SYSTEM_CLIPBOARD"),
		ACTION_COPY_TO_SYSTEM_CLIPBOARD
	)
	_android_tools_popup.add_item(
		tr("ANDROID_PASTE_SYSTEM_CLIPBOARD"),
		ACTION_PASTE_FROM_SYSTEM_CLIPBOARD
	)
	_android_tools_popup.add_separator()
	_android_tools_popup.add_item(tr("ANDROID_CLEAR_SELECTION"), ACTION_CLEAR_SELECTION)

	_android_tools_popup.about_to_popup.connect(_refresh_android_context_tools)
	_android_tools_popup.id_pressed.connect(_on_android_context_tool_pressed)


func _refresh_android_context_tools() -> void:
	var branch_sources := _selection_before_touch.duplicate()
	branch_sources.erase(_touch_target_node_id)
	var branch_available := _touch_target_node_id >= 0 and not branch_sources.is_empty()

	_set_popup_item_disabled(ACTION_SELECT_BRANCH, not branch_available)
	_set_popup_item_disabled(ACTION_SELECT_WATERFALL, not branch_available)
	_set_popup_item_disabled(
		ACTION_COPY_TO_SYSTEM_CLIPBOARD,
		Grid._ALREADY_SELECTED_NODE_IDS.is_empty()
	)
	_set_popup_item_disabled(
		ACTION_PASTE_FROM_SYSTEM_CLIPBOARD,
		DisplayServer.clipboard_get().find("\"arrow\"") < 0
	)
	_set_popup_item_disabled(
		ACTION_CLEAR_SELECTION,
		Grid._ALREADY_SELECTED_NODE_IDS.is_empty()
	)


func _set_popup_item_disabled(item_id: int, disabled: bool) -> void:
	var item_index := _android_tools_popup.get_item_index(item_id)
	if item_index >= 0:
		_android_tools_popup.set_item_disabled(item_index, disabled)


func _on_android_context_tool_pressed(item_id: int) -> void:
	match item_id:
		ACTION_SELECT_BRANCH, ACTION_SELECT_WATERFALL:
			var branch_sources := _selection_before_touch.duplicate()
			branch_sources.erase(_touch_target_node_id)
			if _touch_target_node_id >= 0 and not branch_sources.is_empty():
				Main.Mind.select_branch(
					branch_sources,
					_touch_target_node_id,
					item_id == ACTION_SELECT_WATERFALL
				)
		ACTION_COPY_TO_SYSTEM_CLIPBOARD:
			Main.Mind.os_clipboard_push()
		ACTION_PASTE_FROM_SYSTEM_CLIPBOARD:
			Main.Mind.os_clipboard_pull(null, _touch_grid_offset)
		ACTION_CLEAR_SELECTION:
			Main.Mind.force_unselect_all()

	ContextMenu.hide()


func _input(event: InputEvent) -> void:
	if Grid == null:
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_points[event.index] = event.position
			if _touch_points.size() == 1:
				_begin_long_press(event)
			elif _touch_points.size() == 2:
				_cancel_long_press()
				_begin_pinch()
				get_viewport().set_input_as_handled()
			else:
				_cancel_long_press()
		else:
			_touch_points.erase(event.index)
			if _pinch_active and _touch_points.size() < 2:
				_end_pinch()
				get_viewport().set_input_as_handled()
			if _touch_active and event.index == _touch_index:
				_cancel_long_press()

	elif event is InputEventScreenDrag:
		_touch_points[event.index] = event.position

		if _pinch_active:
			_update_pinch()
			get_viewport().set_input_as_handled()
		elif _touch_active and event.index == _touch_index:
			_touch_position = event.position
			if _touch_origin.distance_to(event.position) > LONG_PRESS_MOVE_TOLERANCE:
				_cancel_long_press()


func _begin_long_press(event: InputEventScreenTouch) -> void:
	if not Grid.get_global_rect().has_point(event.position):
		return

	_touch_active = true
	_touch_index = event.index
	_touch_origin = event.position
	_touch_position = event.position
	_touch_elapsed = 0.0
	_touch_target_node_id = _find_grid_node_at(event.position)
	_selection_before_touch = Grid._ALREADY_SELECTED_NODE_IDS.duplicate()
	_touch_grid_offset = Grid.offset_from_position(Grid.to_local(event.position))


func _cancel_long_press() -> void:
	_touch_active = false
	_touch_index = -1
	_touch_elapsed = 0.0


func _begin_pinch() -> void:
	var points := _get_first_two_touch_points()
	if points.size() < 2:
		return

	var first: Vector2 = points[0]
	var second: Vector2 = points[1]
	var midpoint := (first + second) * 0.5

	if not Grid.get_global_rect().has_point(midpoint):
		return

	_pinch_active = true
	_pinch_start_distance = maxf(first.distance_to(second), 1.0)
	_pinch_start_zoom = Grid.get_zoom()

	var local_midpoint := Grid.to_local(midpoint)
	_pinch_anchor_graph_position = (
		Grid.get_scroll_offset() + local_midpoint
	) / _pinch_start_zoom


func _update_pinch() -> void:
	var points := _get_first_two_touch_points()
	if points.size() < 2:
		_end_pinch()
		return

	var first: Vector2 = points[0]
	var second: Vector2 = points[1]
	var current_distance := maxf(first.distance_to(second), 1.0)
	var zoom_ratio := current_distance / _pinch_start_distance
	var new_zoom := clampf(
		_pinch_start_zoom * zoom_ratio,
		Grid.get_zoom_min(),
		Grid.get_zoom_max()
	)

	var midpoint := (first + second) * 0.5
	var local_midpoint := Grid.to_local(midpoint)

	Grid.set_zoom(new_zoom)
	Grid.set_scroll_offset(
		_pinch_anchor_graph_position * new_zoom - local_midpoint
	)


func _end_pinch() -> void:
	_pinch_active = false
	_pinch_start_distance = 1.0


func _get_first_two_touch_points() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for touch_index in _touch_points:
		result.append(_touch_points[touch_index])
		if result.size() == 2:
			break
	return result


func _process(delta: float) -> void:
	if not _touch_active or _pinch_active:
		return

	_touch_elapsed += delta
	if _touch_elapsed < LONG_PRESS_SECONDS:
		return

	_touch_active = false
	_touch_index = -1
	ContextMenu.show_up(
		Vector2i(_touch_position),
		_touch_grid_offset
	)


func _find_grid_node_at(global_position: Vector2) -> int:
	for node_id in Grid._DRAWN_NODES_BY_ID:
		var node = Grid._DRAWN_NODES_BY_ID[node_id]
		if is_instance_valid(node) and node.get_global_rect().has_point(global_position):
			return node_id
	return -1
