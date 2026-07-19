extends Node

# Android-only input and keyboard adaptation.
# Desktop, Linux and Web builds are unaffected.

const LONG_PRESS_SECONDS := 0.55
const NODE_DRAG_CANCEL_DISTANCE := 18.0
const DOUBLE_TAP_SECONDS := 0.34
const DOUBLE_TAP_DISTANCE := 56.0
const TAP_MOVE_DISTANCE := 24.0
const KEYBOARD_MARGIN := 56.0
const KEYBOARD_MOVE_SPEED := 1800.0
const ANDROID_BASE_DPI := 160.0
const ANDROID_UI_SCALE_MIN := 1.0
const ANDROID_UI_SCALE_MAX := 1.6
const ANDROID_GRAPH_TOOL_SIZE := 64.0
const ANDROID_GRAPH_BUTTON_SIZE := ANDROID_GRAPH_TOOL_SIZE * 0.85
const ANDROID_GRAPH_NUMBER_HEIGHT := ANDROID_GRAPH_TOOL_SIZE * 0.90
const ANDROID_GRAPH_NUMBER_WIDTH_SCALE := 0.75
const ANDROID_GRAPH_ZOOM_LABEL_SHIFT := 12.0
const ANDROID_GRAPH_TOOL_FONT_SIZE := 22
const ANDROID_GRAPH_NUMBER_FONT_SIZE := 30
const ANDROID_GRAPH_TOOL_ICON_SIZE := 34
const ANDROID_TOP_ACTION_SCALE := 1.5
const ANDROID_PROJECT_TITLE_FONT_SIZE := 22
const ANDROID_SCENE_TITLE_FONT_SIZE := 20

enum CanvasMode {
	NONE,
	PENDING,
	LONG_READY,
	DISABLED_DRAG,
	PINCH,
}

var Main: Control
var Grid: GraphEdit
var ContextMenu: PopupPanel
var AndroidContextOverlay: Control
var AndroidContextPanel: Control
var MiniMapBox: Control
var InspectorPanel: Control
var NewDocumentPanel: Control
var AppMenuButton: MenuButton
var SaveButton: Button
var EditorPanel: Control
var InspectorToggleButton: Button
var BottomQuery: Control
var BottomPanel: Control

var _setup_complete := false
var _keyboard_shift := 0.0
var _keyboard_avoidance_active := false
var _keyboard_movable_panel: Control
var _keyboard_base_position := Vector2.ZERO

var _touch_points: Dictionary = {}
var _suppress_emulated_canvas_mouse := false
var _mouse_canvas_fallback_active := false

var _canvas_mode := CanvasMode.NONE
var _canvas_touch_index := -1
var _canvas_origin := Vector2.ZERO
var _canvas_current := Vector2.ZERO
var _canvas_elapsed := 0.0
var _last_empty_tap_time_ms := -1000
var _last_empty_tap_position := Vector2.ZERO

var _node_hold_active := false
var _node_hold_index := -1
var _node_hold_node_id := -1
var _node_hold_origin := Vector2.ZERO
var _node_hold_current := Vector2.ZERO
var _node_hold_elapsed := 0.0
var _node_long_press_triggered := false

var _pinch_start_distance := 1.0
var _pinch_start_zoom := 1.0
var _pinch_anchor_graph_position := Vector2.ZERO
var _app_menu_touch_index := -1
var _inspector_toggle_touch_index := -1


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
	AndroidContextOverlay = get_node_or_null(
		"/root/Main/Overlays/Control/AndroidContext"
	) as Control
	AndroidContextPanel = get_node_or_null(
		"/root/Main/Overlays/Control/AndroidContext/Menu"
	) as Control
	MiniMapBox = get_node_or_null(
		"/root/Main/Editor/Center/MiniMap"
	) as Control
	InspectorPanel = get_node_or_null(
		"/root/Main/FloatingTools/Control/Inspector"
	) as Control
	NewDocumentPanel = get_node_or_null(
		"/root/Main/Overlays/Control/NewDocument"
	) as Control
	AppMenuButton = get_node_or_null(
		"/root/Main/Editor/Top/Bar/AppMenu"
	) as MenuButton
	SaveButton = get_node_or_null(
		"/root/Main/Editor/Top/Bar/Save"
	) as Button
	EditorPanel = get_node_or_null("/root/Main/Editor") as Control
	InspectorToggleButton = get_node_or_null(
		"/root/Main/Editor/Bottom/Bar/Quick/Access/InspectorVisibility"
	) as Button
	BottomQuery = get_node_or_null(
		"/root/Main/Editor/Bottom/Bar/Query"
	) as Control
	BottomPanel = get_node_or_null(
		"/root/Main/Editor/Bottom"
	) as Control

	DisplayServer.screen_set_orientation(
		DisplayServer.SCREEN_SENSOR_LANDSCAPE
	)

	_setup_complete = true
	_configure_optional_android_controls()
	_apply_android_ui_scale()
	_enlarge_graph_toolbar.call_deferred()
	_enlarge_top_right_actions.call_deferred()
	_enlarge_android_titles.call_deferred()
	Main.UI.call_deferred("_apply_android_inspector_layout")
	if InspectorToggleButton != null:
		InspectorToggleButton.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _configure_optional_android_controls() -> void:
	var preferences_panel := get_node_or_null(
		"/root/Main/Overlays/Control/Preferences"
	) as Control
	if preferences_panel != null:
		preferences_panel.anchor_top = 0.08
		preferences_panel.anchor_bottom = 0.92
		preferences_panel.offset_top = 0.0
		preferences_panel.offset_bottom = 0.0

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
	get_window().content_scale_factor = android_scale


func _enlarge_graph_toolbar() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_resize_graph_toolbar_controls(Grid)
	await get_tree().process_frame
	_refine_graph_toolbar_layout()


func _resize_graph_toolbar_controls(parent: Node) -> void:
	for child in parent.get_children(true):
		if child is GraphNode:
			continue
		if child is Control:
			var control := child as Control
			var toolbar_bottom := Grid.global_position.y + 72.0
			if control.global_position.y <= toolbar_bottom:
				control.add_theme_font_size_override(
					"font_size",
					ANDROID_GRAPH_TOOL_FONT_SIZE
				)
				control.custom_minimum_size.y = maxf(
					control.custom_minimum_size.y,
					ANDROID_GRAPH_TOOL_SIZE
				)
				if control is BaseButton:
					control.custom_minimum_size = Vector2.ONE * (
						ANDROID_GRAPH_BUTTON_SIZE
					)
					control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				if control is Button:
					var button := control as Button
					button.expand_icon = true
					button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
					button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
					button.add_theme_constant_override(
						"icon_max_width",
						ANDROID_GRAPH_TOOL_ICON_SIZE
					)
					button.add_theme_constant_override("h_separation", 8)
				if control is LineEdit:
					var line_edit := control as LineEdit
					line_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
					line_edit.add_theme_font_size_override(
						"font_size",
						ANDROID_GRAPH_NUMBER_FONT_SIZE
					)
				if control is Label:
					var label := control as Label
					label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
					label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				if control is BoxContainer:
					control.add_theme_constant_override("separation", 0)
		_resize_graph_toolbar_controls(child)


func _refine_graph_toolbar_layout() -> void:
	var toolbar := Grid.get_menu_hbox()
	if toolbar == null:
		return

	toolbar.add_theme_constant_override("separation", -6)
	var spacer := toolbar.get_node_or_null("AndroidZoomLabelSpacer") as Control
	if spacer == null:
		spacer = Control.new()
		spacer.name = "AndroidZoomLabelSpacer"
		spacer.custom_minimum_size.x = ANDROID_GRAPH_ZOOM_LABEL_SHIFT
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		toolbar.add_child(spacer)
		toolbar.move_child(spacer, 0)
	for child in toolbar.get_children():
		if child is Label:
			var zoom_label := child as Label
			zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		elif child is Button:
			var toolbar_button := child as Button
			toolbar_button.custom_minimum_size = Vector2.ONE * (
				ANDROID_GRAPH_BUTTON_SIZE
			)
			toolbar_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		elif child is SpinBox:
			var number_box := child as SpinBox
			number_box.custom_minimum_size = Vector2(
				number_box.size.x * ANDROID_GRAPH_NUMBER_WIDTH_SCALE,
				ANDROID_GRAPH_NUMBER_HEIGHT
			)
			number_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var number_input := number_box.get_line_edit()
			number_input.expand_to_text_length = false
			number_input.add_theme_constant_override(
				"minimum_character_width",
				1
			)
			number_input.custom_minimum_size.y = ANDROID_GRAPH_NUMBER_HEIGHT
			_hide_android_spinbox_arrows(number_box)
	# The first three toolbar buttons are GraphEdit's zoom out, reset-to-100%,
	# and zoom in controls. Pinch zoom replaces the outer two on Android while
	# keeping the center reset button available.
	var zoom_buttons: Array[Button] = []
	var found_zoom_label := false
	for child in toolbar.get_children():
		if child is Label:
			found_zoom_label = true
			continue
		if child is SpinBox:
			break
		if found_zoom_label and child is Button:
			zoom_buttons.append(child)
	if zoom_buttons.size() >= 3:
		zoom_buttons[0].hide()
		zoom_buttons[2].hide()
	toolbar.queue_sort()


func _hide_android_spinbox_arrows(number_box: SpinBox) -> void:
	var empty_image := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	var empty_icon := ImageTexture.create_from_image(empty_image)
	for icon_name in [
		"updown",
		"up",
		"up_disabled",
		"up_hover",
		"up_pressed",
		"down",
		"down_disabled",
		"down_hover",
		"down_pressed",
	]:
		number_box.add_theme_icon_override(icon_name, empty_icon)
	var empty_style := StyleBoxEmpty.new()
	for style_name in [
		"up_background",
		"up_background_disabled",
		"up_background_hovered",
		"up_background_pressed",
		"down_background",
		"down_background_disabled",
		"down_background_hovered",
		"down_background_pressed",
		"field_and_buttons_separator",
		"up_down_buttons_separator",
	]:
		number_box.add_theme_stylebox_override(style_name, empty_style)


func _enlarge_top_right_actions() -> void:
	await get_tree().process_frame
	var play_buttons := get_node_or_null(
		"/root/Main/Editor/Top/Bar/Play/From"
	) as Container
	if play_buttons != null:
		for child in play_buttons.get_children():
			if child is Button:
				var button := child as Button
				button.custom_minimum_size = Vector2.ONE * (
					24.0 * ANDROID_TOP_ACTION_SCALE
				)
				button.expand_icon = true
				button.add_theme_constant_override("icon_max_width", 30)

	var save_button := get_node_or_null(
		"/root/Main/Editor/Top/Bar/Save"
	) as Button
	if save_button != null:
		save_button.text = ""
		save_button.custom_minimum_size = Vector2.ONE * 54.0
		save_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		save_button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		save_button.add_theme_constant_override("icon_max_width", 44)
		save_button.mouse_filter = Control.MOUSE_FILTER_STOP
		var indicator := save_button.get_node_or_null("Indicator") as Control
		if indicator != null:
			indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _enlarge_android_titles() -> void:
	await get_tree().process_frame
	var project_title := get_node_or_null(
		"/root/Main/Editor/Top/Bar/ProjectTitle"
	) as Label
	if project_title != null:
		project_title.add_theme_font_size_override(
			"font_size",
			ANDROID_PROJECT_TITLE_FONT_SIZE
		)
	var scene_title := get_node_or_null(
		"/root/Main/Editor/Bottom/Bar/SceneTitle"
	) as Label
	if scene_title != null:
		scene_title.add_theme_font_size_override(
			"font_size",
			ANDROID_SCENE_TITLE_FONT_SIZE
		)


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
	var global_position = null
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		global_position = Grid.to_global(event.position)
	return _handle_emulated_canvas_mouse(event, true, global_position)


func _handle_emulated_canvas_mouse(
	event: InputEvent,
	from_grid_gui: bool,
	explicit_global_position = null
) -> bool:
	var mouse_position := Vector2.ZERO
	if explicit_global_position is Vector2:
		mouse_position = explicit_global_position
	elif event is InputEventMouseButton:
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
			if event.double_click:
				_cancel_active_canvas_gesture()
				_show_context_menu(mouse_position)
				get_viewport().set_input_as_handled()
				return true
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
	if (
		AndroidContextOverlay != null
		and AndroidContextOverlay.is_visible_in_tree()
	):
		if (
			event.pressed
			and AndroidContextPanel != null
			and not AndroidContextPanel.get_global_rect().has_point(event.position)
		):
			AndroidContextOverlay.hide()
			_touch_points.erase(event.index)
			_suppress_emulated_canvas_mouse = true
			_cancel_active_canvas_gesture()
			get_viewport().set_input_as_handled()
			return
		if not event.pressed:
			_touch_points.erase(event.index)
			_suppress_emulated_canvas_mouse = false
			_cancel_active_canvas_gesture()
		return
	if _handle_android_menu_touch(event):
		get_viewport().set_input_as_handled()
		return

	if event.pressed:
		_touch_points[event.index] = event.position

		if _touch_points.size() == 2 and _touch_pair_is_on_grid():
			_begin_pinch()
			get_viewport().set_input_as_handled()
			return

		var node_id := _find_node_at(event.position)
		if node_id >= 0:
			_begin_node_hold(event, node_id)
			return

		if _is_empty_canvas_point(event.position):
			if event.double_tap or _is_manual_double_tap(event.position):
				_last_empty_tap_time_ms = -1000
				_cancel_active_canvas_gesture()
				_suppress_emulated_canvas_mouse = true
				_show_context_menu(event.position)
				get_viewport().set_input_as_handled()
				return
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


func _handle_android_menu_touch(event: InputEventScreenTouch) -> bool:
	if event.pressed:
		if (
			SaveButton != null
			and EditorPanel != null
			and SaveButton.get_global_rect().grow(18.0).has_point(event.position)
		):
			EditorPanel.call("_request_android_save")
			return true
		if (
			InspectorToggleButton != null
			and InspectorToggleButton.get_global_rect().has_point(event.position)
		):
			_inspector_toggle_touch_index = event.index
			return true
		if (
			AppMenuButton != null
			and AppMenuButton.get_global_rect().has_point(event.position)
		):
			_app_menu_touch_index = event.index
			AppMenuButton.get_popup().hide()
			Main.UI.call_deferred("set_panel_visibility", "preferences", true)
			return true
		return false

	if event.index == _app_menu_touch_index:
		_app_menu_touch_index = -1
		return true
	if event.index == _inspector_toggle_touch_index:
		_inspector_toggle_touch_index = -1
		if InspectorToggleButton.get_global_rect().has_point(event.position):
			Main.UI.set_panel_visibility(
				"inspector",
				not InspectorPanel.is_visible_in_tree()
			)
		return true
	return false


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	if (
		AndroidContextOverlay != null
		and AndroidContextOverlay.is_visible_in_tree()
	):
		return
	_touch_points[event.index] = event.position

	if _canvas_mode == CanvasMode.PINCH:
		_update_pinch()
		get_viewport().set_input_as_handled()
		return

	if (
		_canvas_mode != CanvasMode.NONE
		and event.index == _canvas_touch_index
	):
		_canvas_current = event.position
		get_viewport().set_input_as_handled()
		return

	if _node_hold_active and event.index == _node_hold_index:
		_node_hold_current = event.position
		if _node_hold_origin.distance_to(_node_hold_current) > NODE_DRAG_CANCEL_DISTANCE:
			_cancel_node_hold()


func _handle_pan_gesture(event: InputEventPanGesture) -> void:
	if not Grid.get_global_rect().has_point(event.position):
		return
	# Android reports two-finger navigation as PanGesture even when raw touch
	# drag events are not emitted. Move the graph opposite the finger delta so
	# the canvas visually follows the gesture.
	_cancel_active_canvas_gesture()
	_suppress_emulated_canvas_mouse = true
	Grid.set_scroll_offset(Grid.get_scroll_offset() - event.delta)
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


func _update_canvas_drag(position: Vector2) -> void:
	_canvas_current = position
	if (
		_canvas_mode == CanvasMode.PENDING
		and _canvas_origin.distance_to(position) > TAP_MOVE_DISTANCE
	):
		# Android deliberately has no selection rectangle. Keep consuming the
		# complete empty-canvas drag so GraphEdit cannot start native box select.
		_canvas_mode = CanvasMode.DISABLED_DRAG


func _finish_canvas_touch(release_position: Vector2) -> void:
	_canvas_current = release_position

	match _canvas_mode:
		CanvasMode.PENDING:
			# A short tap on empty canvas clears the current selection.
			if _canvas_origin.distance_to(release_position) <= TAP_MOVE_DISTANCE:
				_last_empty_tap_time_ms = Time.get_ticks_msec()
				_last_empty_tap_position = release_position
			_clear_selection()
		CanvasMode.LONG_READY:
			# The menu was already shown as soon as the hold threshold elapsed.
			pass
		CanvasMode.DISABLED_DRAG:
			# Empty-canvas drag is intentionally a no-op on Android.
			pass

	_canvas_mode = CanvasMode.NONE
	_canvas_touch_index = -1
	_canvas_origin = Vector2.ZERO
	_canvas_elapsed = 0.0


func _is_manual_double_tap(position: Vector2) -> bool:
	var elapsed_ms := Time.get_ticks_msec() - _last_empty_tap_time_ms
	return (
		elapsed_ms >= 0
		and elapsed_ms <= int(DOUBLE_TAP_SECONDS * 1000.0)
		and _last_empty_tap_position.distance_to(position) <= DOUBLE_TAP_DISTANCE
	)


func _begin_node_hold(event: InputEventScreenTouch, node_id: int) -> void:
	_node_hold_active = true
	_node_hold_index = event.index
	_node_hold_node_id = node_id
	_node_hold_origin = event.position
	_node_hold_current = event.position
	_node_hold_elapsed = 0.0
	_node_long_press_triggered = false


func _finish_node_hold(release_position: Vector2) -> void:
	_node_hold_current = release_position
	var was_long_press := _node_long_press_triggered
	var held_node_id := _node_hold_node_id
	_cancel_node_hold()
	if was_long_press:
		# The menu was already shown while the finger was held.
		get_viewport().set_input_as_handled()
	else:
		_inspect_android_node.call_deferred(held_node_id)


func _inspect_android_node(node_id: int) -> void:
	if (
		node_id >= 0
		and Main != null
		and Main.get("Mind") != null
		and Grid._DRAWN_NODES_BY_ID.has(node_id)
	):
		Main.Mind.inspect_node(node_id, -1, true)


func _cancel_node_hold() -> void:
	_node_hold_active = false
	_node_hold_index = -1
	_node_hold_node_id = -1
	_node_hold_origin = Vector2.ZERO
	_node_hold_elapsed = 0.0
	_node_long_press_triggered = false


func _begin_pinch() -> void:
	var points := _get_touch_pair()
	if points.size() < 2:
		return

	_cancel_node_hold()
	_suppress_emulated_canvas_mouse = true
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
			_show_context_menu(_canvas_current)
			# Vibration intentionally disabled while testing Android long press.

	if _node_hold_active:
		_node_hold_elapsed += delta
		if (
			not _node_long_press_triggered
			and _node_hold_elapsed >= LONG_PRESS_SECONDS
		):
			_node_long_press_triggered = true
			_show_context_menu(_node_hold_current)
			# Vibration intentionally disabled while testing Android long press.

	_update_keyboard_avoidance(delta)


func _update_keyboard_avoidance(delta: float) -> void:
	var keyboard_visible := DisplayServer.virtual_keyboard_get_height() > 0
	var focused := get_viewport().gui_get_focus_owner() as Control
	var focused_panel := _keyboard_panel_for(focused)

	if (
		keyboard_visible
		and focused_panel != null
		and (
			not _keyboard_avoidance_active
			or focused_panel != _keyboard_movable_panel
		)
	):
		_restore_keyboard_panel()
		_keyboard_movable_panel = focused_panel
		_keyboard_base_position = focused_panel.position
		_keyboard_shift = 0.0
		_keyboard_avoidance_active = true

	if not _keyboard_avoidance_active:
		return

	var target_shift := 0.0
	if keyboard_visible and focused_panel == _keyboard_movable_panel:
		target_shift = _calculate_keyboard_shift(
			focused,
			_keyboard_movable_panel
		)
	_keyboard_shift = move_toward(
		_keyboard_shift,
		target_shift,
		KEYBOARD_MOVE_SPEED * delta
	)

	if is_instance_valid(_keyboard_movable_panel):
		_keyboard_movable_panel.position = _keyboard_base_position + Vector2(
			0.0,
			round(_keyboard_shift)
		)
	if not keyboard_visible and is_zero_approx(_keyboard_shift):
		_restore_keyboard_panel()
		_keyboard_avoidance_active = false


func _keyboard_panel_for(focused: Control) -> Control:
	if focused == null or not focused.is_visible_in_tree():
		return null
	if NewDocumentPanel != null and NewDocumentPanel.is_ancestor_of(focused):
		return NewDocumentPanel
	if InspectorPanel != null and InspectorPanel.is_ancestor_of(focused):
		return InspectorPanel
	if (
		BottomQuery != null
		and (focused == BottomQuery or BottomQuery.is_ancestor_of(focused))
	):
		return BottomPanel
	return null


func _restore_keyboard_panel() -> void:
	if is_instance_valid(_keyboard_movable_panel):
		_keyboard_movable_panel.position = _keyboard_base_position
	_keyboard_movable_panel = null


func _calculate_keyboard_shift(
	focused: Control,
	movable_panel: Control
) -> float:
	var keyboard_height_pixels := DisplayServer.virtual_keyboard_get_height()
	if keyboard_height_pixels <= 0:
		return 0.0

	if (
		focused == null
		or not focused.is_visible_in_tree()
		or movable_panel == null
	):
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

	var focused_bottom_without_shift := focused.get_global_rect().end.y - _keyboard_shift
	var requested_shift := minf(
		visible_bottom - focused_bottom_without_shift,
		0.0
	)
	return requested_shift
