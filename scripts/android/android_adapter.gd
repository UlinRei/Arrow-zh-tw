extends Node

# Android-only input and keyboard adaptation.
# Desktop, Linux and Web builds are unaffected.

const LONG_PRESS_SECONDS := 0.55
const PAN_START_DISTANCE := 10.0
const BOX_SELECT_START_DISTANCE := 12.0
const NODE_LONG_PRESS_MOVE_TOLERANCE := 18.0
const KEYBOARD_MARGIN := 28.0
const KEYBOARD_MOVE_SPEED := 1800.0
const ANDROID_BASE_DPI := 160.0
const ANDROID_UI_SCALE_MIN := 1.0
const ANDROID_UI_SCALE_MAX := 1.6

enum CanvasMode {
	NONE,
	PENDING,
	PAN,
	LONG_READY,
	BOX_SELECT,
	PINCH,
}

var Main: Control
var Grid: GraphEdit
var ContextMenu: PopupPanel
var MiniMapBox: Control

var _setup_complete := false
var _main_base_position := Vector2.ZERO
var _keyboard_shift := 0.0

var _touch_points: Dictionary = {}
var _suppress_emulated_canvas_mouse := false
var _mouse_canvas_fallback_active := false

var _canvas_mode := CanvasMode.NONE
var _canvas_touch_index := -1
var _canvas_origin := Vector2.ZERO
var _canvas_current := Vector2.ZERO
var _canvas_elapsed := 0.0
var _canvas_start_scroll := Vector2.ZERO

var _node_hold_active := false
var _node_hold_index := -1
var _node_hold_origin := Vector2.ZERO
var _node_hold_current := Vector2.ZERO
var _node_hold_elapsed := 0.0
var _node_long_press_triggered := false

var _pinch_start_distance := 1.0
var _pinch_start_zoom := 1.0
var _pinch_anchor_graph_position := Vector2.ZERO

var _selection_overlay: Panel


func _ready() -> void:
	if not OS.has_feature("android"):
		queue_free()
		return

	set_process(true)
	set_process_input(true)
	call_deferred("_setup_android")


func _setup_android() -> void:
	# Autoloads start before the main scene, so wait for the scene tree.
	while Main == null or Grid == null:
		Main = get_node_or_null("/root/Main") as Control
		Grid = get_node_or_null("/root/Main/Editor/Center/Grid") as GraphEdit
		if Main == null or Grid == null:
			await get_tree().process_frame

	ContextMenu = get_node_or_null(
		"/root/Main/FloatingTools/Control/Context"
	) as PopupPanel
	MiniMapBox = get_node_or_null(
		"/root/Main/Editor/Center/MiniMap"
	) as Control

	DisplayServer.screen_set_orientation(
		DisplayServer.SCREEN_SENSOR_LANDSCAPE
	)

	_main_base_position = Main.position
	_apply_android_ui_scale()
	Grid.child_entered_tree.connect(_refresh_android_graph_node)
	for child in Grid.get_children():
		_refresh_android_graph_node(child)
	_create_selection_overlay()
	_configure_optional_android_controls()
	_setup_complete = true


func _configure_optional_android_controls() -> void:
	var path_dialog := get_node_or_null(
		"/root/Main/Overlays/Control/PathDialog"
	)
	if path_dialog is FileDialog:
		path_dialog.use_native_dialog = true

	var work_dir_row := get_node_or_null(
		"/root/Main/Overlays/Control/Preferences/Margin/Sections/Configs/Scroll/Params/WorkDir"
	)
	if work_dir_row is CanvasItem:
		work_dir_row.hide()

	var interface_font_row := get_node_or_null(
		"/root/Main/Overlays/Control/Preferences/Margin/Sections/Configs/Scroll/Params/Font"
	)
	if interface_font_row is CanvasItem:
		interface_font_row.hide()


func _apply_android_ui_scale() -> void:
	var dpi := float(DisplayServer.screen_get_dpi())
	if dpi <= 0.0:
		return

	var android_scale := clampf(
		dpi / ANDROID_BASE_DPI,
		ANDROID_UI_SCALE_MIN,
		ANDROID_UI_SCALE_MAX
	)
	var base_theme := Main.theme
	var android_theme := base_theme.duplicate() as Theme
	if android_theme == null:
		return
	var canvas_theme := base_theme.duplicate() as Theme
	if canvas_theme != null:
		canvas_theme.default_base_scale = 1.0
		Grid.theme = canvas_theme
	android_theme.default_base_scale = android_scale
	for layer_path in [
		"/root/Main",
		"/root/Main/Overlays/Control",
		"/root/Main/FloatingTools/Control",
	]:
		var layer := get_node_or_null(layer_path) as Control
		if layer != null:
			layer.theme = android_theme.duplicate()


func _create_selection_overlay() -> void:
	var overlay_parent := get_node_or_null(
		"/root/Main/Overlays/Control"
	) as Control
	if overlay_parent == null:
		return

	_selection_overlay = Panel.new()
	_selection_overlay.name = "AndroidBoxSelection"
	_selection_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selection_overlay.z_index = 1000
	_selection_overlay.hide()

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.25, 0.55, 1.0, 0.16)
	style.border_color = Color(0.45, 0.72, 1.0, 0.9)
	style.set_border_width_all(2)
	_selection_overlay.add_theme_stylebox_override("panel", style)

	overlay_parent.add_child(_selection_overlay)


func _input(event: InputEvent) -> void:
	if not _setup_complete:
		return

	if event is InputEventScreenTouch:
		_handle_screen_touch(event)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event)
	elif event is InputEventPanGesture:
		_handle_pan_gesture(event)
	elif event is InputEventMagnifyGesture:
		_handle_magnify_gesture(event)
	elif event is InputEventMouseButton or event is InputEventMouseMotion:
		_handle_emulated_canvas_mouse(event, false)


func handle_grid_mouse_input(event: InputEvent) -> bool:
	return _handle_emulated_canvas_mouse(event, true)


func _handle_emulated_canvas_mouse(
	event: InputEvent,
	from_grid_gui: bool
) -> bool:
	var mouse_position := Vector2.ZERO
	if event is InputEventMouseButton:
		mouse_position = event.position
	elif event is InputEventMouseMotion:
		mouse_position = event.position

	if _suppress_emulated_canvas_mouse:
		if Grid.get_global_rect().has_point(mouse_position):
			get_viewport().set_input_as_handled()
		if event is InputEventMouseButton and not event.pressed:
			_suppress_emulated_canvas_mouse = false
		return true

	if not from_grid_gui:
		return false

	if event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT:
			return false
		if event.pressed:
			if not _is_empty_canvas_point(mouse_position):
				return false
			_mouse_canvas_fallback_active = true
			_begin_canvas_at(mouse_position, -2)
		else:
			if not _mouse_canvas_fallback_active:
				return false
			_finish_canvas_touch(mouse_position)
			_mouse_canvas_fallback_active = false
		get_viewport().set_input_as_handled()
		return true

	if event is InputEventMouseMotion and _mouse_canvas_fallback_active:
		_update_canvas_drag(mouse_position)
		get_viewport().set_input_as_handled()
		return true
	return false


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touch_points[event.index] = event.position

		if _touch_points.size() == 2 and _touch_pair_is_on_grid():
			_begin_pinch()
			get_viewport().set_input_as_handled()
			return

		var node_id := _find_node_at(event.position)
		if node_id >= 0:
			_begin_node_hold(event)
			return

		if _is_empty_canvas_point(event.position):
			_begin_canvas_touch(event)
			get_viewport().set_input_as_handled()
			return

	else:
		_touch_points.erase(event.index)
		if _touch_points.is_empty():
			_suppress_emulated_canvas_mouse = false

		if _canvas_mode == CanvasMode.PINCH:
			if _touch_points.size() < 2:
				_finish_pinch()
			get_viewport().set_input_as_handled()
			return

		if (
			_canvas_mode != CanvasMode.NONE
			and event.index == _canvas_touch_index
		):
			_finish_canvas_touch(event.position)
			get_viewport().set_input_as_handled()
			return

		if _node_hold_active and event.index == _node_hold_index:
			_finish_node_hold(event.position)


func _refresh_android_graph_node(node: Node) -> void:
	if not node is GraphNode:
		return
	await get_tree().process_frame
	if not is_instance_valid(node):
		return

	var node_resource = node.get("_node_resource")
	if not node_resource is Dictionary or not node_resource.has("data"):
		return
	var data_clone: Dictionary = node_resource.data.duplicate(true)
	if node.has_method("_update_node"):
		node.call("_update_node", data_clone)
	Grid.resize_to_best_fit(node, data_clone)


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	_touch_points[event.index] = event.position

	if _canvas_mode == CanvasMode.PINCH:
		_update_pinch()
		get_viewport().set_input_as_handled()
		return

	if (
		_canvas_mode != CanvasMode.NONE
		and event.index == _canvas_touch_index
	):
		_update_canvas_drag(event.position)
		get_viewport().set_input_as_handled()
		return

	if _node_hold_active and event.index == _node_hold_index:
		_node_hold_current = event.position
		if (
			_node_hold_origin.distance_to(_node_hold_current)
			> NODE_LONG_PRESS_MOVE_TOLERANCE
		):
			_cancel_node_hold()


func _handle_pan_gesture(event: InputEventPanGesture) -> void:
	if not Grid.get_global_rect().has_point(event.position):
		return
	_cancel_active_canvas_gesture()
	Grid.set_scroll_offset(Grid.get_scroll_offset() + event.delta)
	get_viewport().set_input_as_handled()


func _handle_magnify_gesture(event: InputEventMagnifyGesture) -> void:
	if not Grid.get_global_rect().has_point(event.position):
		return

	_cancel_active_canvas_gesture()
	var local_anchor: Vector2 = Grid.to_local(event.position)
	var old_zoom := Grid.get_zoom()
	var graph_anchor: Vector2 = (
		Grid.get_scroll_offset() + local_anchor
	) / old_zoom
	var new_zoom := clampf(
		old_zoom * event.factor,
		Grid.get_zoom_min(),
		Grid.get_zoom_max()
	)
	Grid.set_zoom(new_zoom)
	Grid.set_scroll_offset(graph_anchor * new_zoom - local_anchor)
	get_viewport().set_input_as_handled()


func _cancel_active_canvas_gesture() -> void:
	_cancel_node_hold()
	_hide_selection_overlay()
	_canvas_mode = CanvasMode.NONE
	_canvas_touch_index = -1
	_canvas_elapsed = 0.0


func _begin_canvas_touch(event: InputEventScreenTouch) -> void:
	_suppress_emulated_canvas_mouse = true
	_begin_canvas_at(event.position, event.index)


func _begin_canvas_at(position: Vector2, input_index: int) -> void:
	_canvas_mode = CanvasMode.PENDING
	_canvas_touch_index = input_index
	_canvas_origin = position
	_canvas_current = position
	_canvas_elapsed = 0.0
	_canvas_start_scroll = Grid.get_scroll_offset()


func _update_canvas_drag(position: Vector2) -> void:
	_canvas_current = position
	var travel := _canvas_origin.distance_to(_canvas_current)

	match _canvas_mode:
		CanvasMode.PENDING:
			if travel >= PAN_START_DISTANCE:
				_canvas_mode = CanvasMode.PAN
				_update_canvas_pan()
		CanvasMode.PAN:
			_update_canvas_pan()
		CanvasMode.LONG_READY:
			if travel >= BOX_SELECT_START_DISTANCE:
				_begin_box_selection()
				_update_box_selection()
		CanvasMode.BOX_SELECT:
			_update_box_selection()


func _finish_canvas_touch(release_position: Vector2) -> void:
	_canvas_current = release_position

	match _canvas_mode:
		CanvasMode.PENDING:
			# A short tap on empty canvas clears the current selection.
			_clear_selection()
		CanvasMode.LONG_READY:
			_show_context_menu(release_position)
		CanvasMode.BOX_SELECT:
			_apply_box_selection()

	_hide_selection_overlay()
	_canvas_mode = CanvasMode.NONE
	_canvas_touch_index = -1
	_canvas_elapsed = 0.0


func _update_canvas_pan() -> void:
	# GraphEdit scroll_offset is in visible canvas pixels.
	var drag_delta := _canvas_current - _canvas_origin
	Grid.set_scroll_offset(_canvas_start_scroll - drag_delta)


func _begin_box_selection() -> void:
	_canvas_mode = CanvasMode.BOX_SELECT
	_clear_selection()
	if _selection_overlay != null:
		_selection_overlay.show()


func _update_box_selection() -> void:
	if _selection_overlay == null:
		return

	var top_left := Vector2(
		minf(_canvas_origin.x, _canvas_current.x),
		minf(_canvas_origin.y, _canvas_current.y)
	)
	var bottom_right := Vector2(
		maxf(_canvas_origin.x, _canvas_current.x),
		maxf(_canvas_origin.y, _canvas_current.y)
	)

	_selection_overlay.global_position = top_left
	_selection_overlay.size = bottom_right - top_left


func _apply_box_selection() -> void:
	var top_left := Vector2(
		minf(_canvas_origin.x, _canvas_current.x),
		minf(_canvas_origin.y, _canvas_current.y)
	)
	var size := Vector2(
		absf(_canvas_current.x - _canvas_origin.x),
		absf(_canvas_current.y - _canvas_origin.y)
	)

	if size.x >= BOX_SELECT_START_DISTANCE and size.y >= BOX_SELECT_START_DISTANCE:
		Grid.select_all_in(Rect2(top_left, size))


func _hide_selection_overlay() -> void:
	if _selection_overlay != null:
		_selection_overlay.hide()


func _begin_node_hold(event: InputEventScreenTouch) -> void:
	_node_hold_active = true
	_node_hold_index = event.index
	_node_hold_origin = event.position
	_node_hold_current = event.position
	_node_hold_elapsed = 0.0
	_node_long_press_triggered = false


func _finish_node_hold(release_position: Vector2) -> void:
	_node_hold_current = release_position
	var was_long_press := _node_long_press_triggered
	_cancel_node_hold()
	if was_long_press:
		get_viewport().set_input_as_handled()


func _cancel_node_hold() -> void:
	_node_hold_active = false
	_node_hold_index = -1
	_node_hold_elapsed = 0.0
	_node_long_press_triggered = false


func _begin_pinch() -> void:
	var points := _get_touch_pair()
	if points.size() < 2:
		return

	_cancel_node_hold()
	_suppress_emulated_canvas_mouse = true
	_hide_selection_overlay()
	_canvas_mode = CanvasMode.PINCH

	var first: Vector2 = points[0]
	var second: Vector2 = points[1]
	var midpoint := (first + second) * 0.5

	_pinch_start_distance = maxf(first.distance_to(second), 1.0)
	_pinch_start_zoom = Grid.get_zoom()
	_pinch_anchor_graph_position = (
		Grid.get_scroll_offset() + Grid.to_local(midpoint)
	) / _pinch_start_zoom


func _update_pinch() -> void:
	var points := _get_touch_pair()
	if points.size() < 2:
		return

	var first: Vector2 = points[0]
	var second: Vector2 = points[1]
	var midpoint := (first + second) * 0.5
	var current_distance := maxf(first.distance_to(second), 1.0)

	var new_zoom := clampf(
		_pinch_start_zoom * current_distance / _pinch_start_distance,
		Grid.get_zoom_min(),
		Grid.get_zoom_max()
	)

	Grid.set_zoom(new_zoom)
	Grid.set_scroll_offset(
		_pinch_anchor_graph_position * new_zoom
		- Grid.to_local(midpoint)
	)


func _finish_pinch() -> void:
	_canvas_mode = CanvasMode.NONE
	_canvas_touch_index = -1
	_pinch_start_distance = 1.0


func _get_touch_pair() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for touch_index in _touch_points:
		result.append(_touch_points[touch_index])
		if result.size() == 2:
			break
	return result


func _touch_pair_is_on_grid() -> bool:
	var points := _get_touch_pair()
	if points.size() < 2:
		return false
	return (
		Grid.get_global_rect().has_point(points[0])
		and Grid.get_global_rect().has_point(points[1])
	)


func _is_empty_canvas_point(global_position: Vector2) -> bool:
	if not Grid.get_global_rect().has_point(global_position):
		return false

	if _find_node_at(global_position) >= 0:
		return false

	# Do not intercept GraphEdit's built-in top toolbar.
	var local_position: Vector2 = Grid.to_local(global_position)
	if local_position.y < 42.0:
		return false

	if (
		MiniMapBox != null
		and MiniMapBox.is_visible_in_tree()
		and MiniMapBox.get_global_rect().has_point(global_position)
	):
		return false

	return true


func _find_node_at(global_position: Vector2) -> int:
	for node_id in Grid._DRAWN_NODES_BY_ID:
		var node = Grid._DRAWN_NODES_BY_ID[node_id]
		if (
			is_instance_valid(node)
			and node is Control
			and node.get_global_rect().has_point(global_position)
		):
			return int(node_id)

	return -1


func _show_context_menu(global_position: Vector2) -> void:
	if ContextMenu == null or Grid == null:
		return

	ContextMenu.show_up(
		global_position,
		Grid.offset_from_position(Grid.to_local(global_position))
	)


func _clear_selection() -> void:
	if Main != null and Main.get("Mind") != null:
		Main.Mind.force_unselect_all()


func _process(delta: float) -> void:
	if not _setup_complete:
		return

	if _canvas_mode == CanvasMode.PENDING:
		_canvas_elapsed += delta
		if _canvas_elapsed >= LONG_PRESS_SECONDS:
			_canvas_mode = CanvasMode.LONG_READY
			_show_long_press_indicator()

	if _node_hold_active:
		_node_hold_elapsed += delta
		if (
			not _node_long_press_triggered
			and _node_hold_elapsed >= LONG_PRESS_SECONDS
			and _node_hold_origin.distance_to(_node_hold_current)
				<= NODE_LONG_PRESS_MOVE_TOLERANCE
		):
			_node_long_press_triggered = true
			Input.vibrate_handheld(35)
			_show_context_menu(_node_hold_current)

	_update_keyboard_avoidance(delta)


func _show_long_press_indicator() -> void:
	Input.vibrate_handheld(35)
	if _selection_overlay == null:
		return
	_selection_overlay.global_position = (
		_canvas_origin - Vector2.ONE * BOX_SELECT_START_DISTANCE * 0.5
	)
	_selection_overlay.size = Vector2.ONE * BOX_SELECT_START_DISTANCE
	_selection_overlay.show()


func _update_keyboard_avoidance(delta: float) -> void:
	var target_shift := _calculate_keyboard_shift()
	_keyboard_shift = move_toward(
		_keyboard_shift,
		target_shift,
		KEYBOARD_MOVE_SPEED * delta
	)

	Main.position = _main_base_position + Vector2(
		0.0,
		round(_keyboard_shift)
	)


func _calculate_keyboard_shift() -> float:
	var keyboard_height_pixels := DisplayServer.virtual_keyboard_get_height()
	if keyboard_height_pixels <= 0:
		return 0.0

	var focused := get_viewport().gui_get_focus_owner() as Control
	if focused == null or not focused.is_visible_in_tree():
		return 0.0

	var stretch_scale_y := (
		get_viewport().get_stretch_transform().get_scale().y
	)
	if is_zero_approx(stretch_scale_y):
		stretch_scale_y = 1.0

	var keyboard_height := (
		float(keyboard_height_pixels) / absf(stretch_scale_y)
	)
	var viewport_height := get_viewport().get_visible_rect().size.y
	var visible_bottom := (
		viewport_height - keyboard_height - KEYBOARD_MARGIN
	)

	var focused_bottom_without_shift := (
		focused.get_global_rect().end.y - _keyboard_shift
	)
	return minf(
		visible_bottom - focused_bottom_without_shift,
		0.0
	)
