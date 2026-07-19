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
const ANDROID_GRAPH_ZOOM_LABEL_SHIFT := 18.0
const ANDROID_GRAPH_TOOL_FONT_SIZE := 22
const ANDROID_GRAPH_NUMBER_FONT_SIZE := 30
const ANDROID_GRAPH_TOOL_ICON_SIZE := 34
const ANDROID_TOP_ACTION_SCALE := 1.5
const ANDROID_HISTORY_BUTTON_WIDTH := 48.0
const ANDROID_HISTORY_BUTTON_GAP := 12
const ANDROID_BOTTOM_ACTION_SIZE := Vector2(64.0, 48.0)
const ANDROID_SCENE_TITLE_STRETCH := 0.65
const ANDROID_QUERY_FONT_SIZE := 22
const ANDROID_PROJECT_TITLE_FONT_SIZE := 22
const ANDROID_SCENE_TITLE_FONT_SIZE := 26
const ANDROID_INSPECTOR_BLOCKER_FONT_SIZE := 22

enum CanvasMode {
	NONE,
	PENDING,
	LONG_READY,
	PAN,
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
var QueryInput: LineEdit

var _setup_complete := false
var _keyboard_shift := 0.0
var _keyboard_avoidance_active := false
var _keyboard_movable_panel: Control
var _keyboard_base_position := Vector2.ZERO

var _touch_points: Dictionary = {}

var _canvas_mode := CanvasMode.NONE
var _canvas_touch_index := -1
var _canvas_origin := Vector2.ZERO
var _canvas_current := Vector2.ZERO
var _canvas_start_scroll := Vector2.ZERO
var _canvas_elapsed := 0.0
var _last_empty_tap_time_ms := -1000
var _last_empty_tap_position := Vector2.ZERO
var _last_node_tap_time_ms := -1000
var _last_node_tap_position := Vector2.ZERO
var _last_node_tap_id := -1

var _node_hold_active := false
var _node_hold_index := -1
var _node_hold_node_id := -1
var _node_hold_origin := Vector2.ZERO
var _node_hold_current := Vector2.ZERO
var _node_hold_elapsed := 0.0
var _node_long_press_triggered := false
var _node_dragging := false
var _node_resizing := false
var _node_start_offset := Vector2.ZERO
var _node_start_size := Vector2.ZERO

var _pinch_start_distance := 1.0
var _pinch_start_zoom := 1.0
var _pinch_anchor_graph_position := Vector2.ZERO
var _pinch_update_pending := false
var _app_menu_touch_index := -1
var _inspector_toggle_touch_index := -1
var _control_touch_states: Dictionary = {}
var _touch_connection: Dictionary = {}
var _touch_connection_preview: Line2D
var _inspector_hidden_for_query := false
var _query_inspector_was_visible := false
var _query_focus_active := false
var _keyboard_was_visible := false
var _popup_touch_states: Dictionary = {}


func _enter_tree() -> void:
	if OS.has_feature("android"):
		# Keep touch and mouse as independent input streams. Android gestures are
		# handled below; a connected mouse remains entirely native GraphEdit input.
		Input.set_emulate_mouse_from_touch(false)


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
		"/root/Main/Overlays/Control/AndroidContext/Center/Menu"
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
	QueryInput = get_node_or_null(
		"/root/Main/Editor/Bottom/Bar/Query/Tools/Input"
	) as LineEdit
	_install_touch_control_handlers(Main)
	_touch_connection_preview = Line2D.new()
	_touch_connection_preview.name = "AndroidConnectionPreview"
	_touch_connection_preview.width = 4.0
	_touch_connection_preview.default_color = Color(0.9, 0.9, 0.9, 0.9)
	_touch_connection_preview.visible = false
	Main.add_child(_touch_connection_preview)
	if QueryInput != null:
		QueryInput.focus_entered.connect(_on_query_focus_entered)
		QueryInput.focus_exited.connect(_on_query_focus_exited)

	DisplayServer.screen_set_orientation(
		DisplayServer.SCREEN_SENSOR_LANDSCAPE
	)

	_setup_complete = true
	_configure_optional_android_controls()
	_apply_android_ui_scale()
	_enlarge_graph_toolbar.call_deferred()
	_enlarge_top_right_actions.call_deferred()
	_enlarge_history_actions.call_deferred()
	_refine_bottom_query_layout.call_deferred()
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


func _install_touch_control_handlers(node: Node) -> void:
	if (
		(ContextMenu != null and (node == ContextMenu or ContextMenu.is_ancestor_of(node)))
		or (
			AndroidContextOverlay != null
			and (
				node == AndroidContextOverlay
				or AndroidContextOverlay.is_ancestor_of(node)
			)
		)
	):
		return
	if not node.has_meta("android_touch_tree_handler"):
		node.set_meta("android_touch_tree_handler", true)
		node.child_entered_tree.connect(_install_touch_control_handlers)
	if (
		node is BaseButton
		or node is LineEdit
		or node is TextEdit
		or node is ItemList
		or node is TabBar
		or node is HSlider
		or node is VSlider
	):
		var control := node as Control
		if not control.has_meta("android_touch_handler"):
			control.set_meta("android_touch_handler", true)
			control.gui_input.connect(
				_on_native_control_touch.bind(control)
			)
	for child in node.get_children():
		_install_touch_control_handlers(child)


func _on_native_control_touch(event: InputEvent, control: Control) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_control_touch_states[control.get_instance_id()] = {
				"index": event.index,
				"origin": event.position,
				"current": event.position,
			}
			control.accept_event()
			if control is LineEdit or control is TextEdit:
				control.grab_focus()
		elif _control_touch_states.has(control.get_instance_id()):
			var state: Dictionary = _control_touch_states[control.get_instance_id()]
			_control_touch_states.erase(control.get_instance_id())
			if state.index != event.index:
				return
			if (
				state.origin.distance_to(event.position) <= TAP_MOVE_DISTANCE
				and Rect2(Vector2.ZERO, control.size).has_point(event.position)
			):
				_activate_native_control(control, event.position)
			control.accept_event()
		return
	if event is InputEventScreenDrag:
		var state_key := control.get_instance_id()
		if not _control_touch_states.has(state_key):
			return
		var state: Dictionary = _control_touch_states[state_key]
		if state.index != event.index:
			return
		state.current = event.position
		_control_touch_states[state_key] = state
		if control is HSlider or control is VSlider:
			_update_touch_slider(control as Range, event.position)
			control.accept_event()


func _activate_native_control(control: Control, local_position: Vector2) -> void:
	if control is OptionButton:
		var option_button := control as OptionButton
		if not option_button.disabled:
			_prepare_touch_popup(option_button.get_popup())
			option_button.show_popup()
	elif control is MenuButton:
		var menu_button := control as MenuButton
		if not menu_button.disabled:
			_prepare_touch_popup(menu_button.get_popup())
			menu_button.show_popup()
	elif control is BaseButton:
		var button := control as BaseButton
		if button.disabled:
			return
		if button.toggle_mode:
			button.set_pressed_no_signal(not button.button_pressed)
			button.toggled.emit(button.button_pressed)
		button.pressed.emit()
	elif control is LineEdit or control is TextEdit:
		control.grab_focus()
	elif control is ItemList:
		var item_list := control as ItemList
		var item_index := item_list.get_item_at_position(local_position, true)
		if item_index >= 0:
			item_list.select(item_index)
			item_list.item_selected.emit(item_index)
	elif control is TabBar:
		var tab_bar := control as TabBar
		var tab_index := tab_bar.get_tab_idx_at_point(local_position)
		if tab_index >= 0 and not tab_bar.is_tab_disabled(tab_index):
			tab_bar.current_tab = tab_index
	elif control is HSlider or control is VSlider:
		_update_touch_slider(control as Range, local_position)


func _update_touch_slider(slider: Range, local_position: Vector2) -> void:
	var ratio := 0.0
	if slider is VSlider:
		ratio = 1.0 - clampf(local_position.y / maxf(slider.size.y, 1.0), 0.0, 1.0)
	else:
		ratio = clampf(local_position.x / maxf(slider.size.x, 1.0), 0.0, 1.0)
	slider.value = lerpf(slider.min_value, slider.max_value, ratio)


func _prepare_touch_popup(popup: PopupMenu) -> void:
	if popup.has_meta("android_touch_popup"):
		return
	popup.set_meta("android_touch_popup", true)
	popup.window_input.connect(_on_popup_touch.bind(popup))


func _on_popup_touch(event: InputEvent, popup: PopupMenu) -> void:
	if not event is InputEventScreenTouch:
		return
	if event.pressed:
		_popup_touch_states[popup.get_instance_id()] = event.index
		return
	if _popup_touch_states.get(popup.get_instance_id(), -1) != event.index:
		return
	_popup_touch_states.erase(popup.get_instance_id())
	var item_count := popup.get_item_count()
	if item_count <= 0 or popup.size.y <= 0:
		popup.hide()
		return
	var item_index := clampi(
		int(floor(event.position.y / (float(popup.size.y) / item_count))),
		0,
		item_count - 1
	)
	if popup.is_item_disabled(item_index) or popup.is_item_separator(item_index):
		return
	popup.index_pressed.emit(item_index)
	popup.id_pressed.emit(popup.get_item_id(item_index))
	popup.hide()


func _on_query_focus_entered() -> void:
	if _query_focus_active:
		return
	_query_focus_active = true
	_query_inspector_was_visible = (
		InspectorPanel != null and InspectorPanel.is_visible_in_tree()
	)
	_inspector_hidden_for_query = _query_inspector_was_visible
	if _inspector_hidden_for_query:
		Main.UI.set_panel_visibility("inspector", false)


func _on_query_focus_exited() -> void:
	if not _query_focus_active:
		return
	_query_focus_active = false
	if InspectorPanel != null:
		Main.UI.set_panel_visibility(
			"inspector",
			_query_inspector_was_visible
		)
	_inspector_hidden_for_query = false

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

	toolbar.add_theme_constant_override("separation", 8)
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


func _enlarge_history_actions() -> void:
	await get_tree().process_frame
	var history_tools := get_node_or_null(
		"/root/Main/Editor/Top/Bar/History/Tools"
	) as HBoxContainer
	if history_tools == null:
		return
	history_tools.add_theme_constant_override(
		"separation",
		ANDROID_HISTORY_BUTTON_GAP
	)
	for child in history_tools.get_children():
		if child is Button:
			var button := child as Button
			button.custom_minimum_size.x = ANDROID_HISTORY_BUTTON_WIDTH
			button.expand_icon = true


func _refine_bottom_query_layout() -> void:
	await get_tree().process_frame
	var scene_title := get_node_or_null(
		"/root/Main/Editor/Bottom/Bar/SceneTitle"
	) as Label
	if scene_title != null:
		scene_title.size_flags_stretch_ratio = ANDROID_SCENE_TITLE_STRETCH
	var query_input := get_node_or_null(
		"/root/Main/Editor/Bottom/Bar/Query/Tools/Input"
	) as LineEdit
	if query_input != null:
		query_input.custom_minimum_size.x = 0.0
		query_input.size_flags_stretch_ratio = 0.75
		query_input.add_theme_font_size_override(
			"font_size",
			ANDROID_QUERY_FONT_SIZE
		)
		query_input.focus_entered.connect(_hide_inspector_for_query)
	for path in [
		"/root/Main/Editor/Bottom/Bar/Query/Tools/Scoped",
		"/root/Main/Editor/Bottom/Bar/Query/Tools/Search",
	]:
		var button := get_node_or_null(path) as Button
		if button != null:
			button.custom_minimum_size = ANDROID_BOTTOM_ACTION_SIZE
			button.expand_icon = true
			button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER


func _hide_inspector_for_query() -> void:
	if InspectorPanel != null and InspectorPanel.is_visible_in_tree():
		Main.UI.set_panel_visibility("inspector", false)


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
	var inspector_blocker := get_node_or_null(
		"/root/Main/FloatingTools/Control/Inspector/Sections/Tabs/Node/Blocker"
	) as Label
	if inspector_blocker != null:
		inspector_blocker.add_theme_font_size_override(
			"font_size",
			ANDROID_INSPECTOR_BLOCKER_FONT_SIZE
		)


func _input(event: InputEvent) -> void:
	# Main forwards raw Android input before child Controls can consume it.
	# Keeping this callback empty prevents a single touch from being handled twice.
	pass


func handle_raw_touch_input(event: InputEvent) -> void:
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
			_cancel_active_canvas_gesture()
			get_viewport().set_input_as_handled()
			return
		if not event.pressed:
			_touch_points.erase(event.index)
			_cancel_active_canvas_gesture()
		return
	if _handle_android_menu_touch(event):
		get_viewport().set_input_as_handled()
		return
	if _is_touch_control_area(event.position):
		return

	if event.pressed:
		_touch_points[event.index] = event.position

		if _touch_points.size() == 2 and _touch_pair_is_on_grid():
			_begin_pinch()
			get_viewport().set_input_as_handled()
			return

		var touched_port := _find_port_at(event.position)
		if not touched_port.is_empty():
			_begin_touch_connection(event, touched_port)
			get_viewport().set_input_as_handled()
			return

		var node_id := _find_node_at(event.position)
		if node_id >= 0:
			if _is_node_resize_point(event.position, node_id):
				_begin_node_resize(event, node_id)
				get_viewport().set_input_as_handled()
				return
			if (
				event.double_tap
				or _is_manual_node_double_tap(event.position, node_id)
			):
				_last_node_tap_time_ms = -1000
				_cancel_active_canvas_gesture()
				_show_context_menu(event.position)
				get_viewport().set_input_as_handled()
				return
			_begin_node_hold(event, node_id)
			get_viewport().set_input_as_handled()
			return

		if _is_direct_canvas_point(event.position):
			handle_grid_touch_press(event, event.position)
			get_viewport().set_input_as_handled()
			return

	else:
		_touch_points.erase(event.index)
		if (
			not _touch_connection.is_empty()
			and _touch_connection.index == event.index
		):
			_finish_touch_connection(event.position)
			get_viewport().set_input_as_handled()
			return

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
			get_viewport().set_input_as_handled()


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


func _is_touch_control_area(global_position: Vector2) -> bool:
	for panel in [InspectorPanel, BottomPanel, NewDocumentPanel]:
		if (
			panel != null
			and panel.is_visible_in_tree()
			and panel.get_global_rect().has_point(global_position)
		):
			return true
	return false


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	if (
		AndroidContextOverlay != null
		and AndroidContextOverlay.is_visible_in_tree()
	):
		return
	_touch_points[event.index] = event.position
	if (
		not _touch_connection.is_empty()
		and _touch_connection.index == event.index
	):
		_touch_connection_preview.set_point_position(1, event.position)
		get_viewport().set_input_as_handled()
		return

	if _canvas_mode == CanvasMode.PINCH:
		_pinch_update_pending = true
		get_viewport().set_input_as_handled()
		return

	if (
		_canvas_mode != CanvasMode.NONE
		and event.index == _canvas_touch_index
	):
		_canvas_current = event.position
		_canvas_mode = CanvasMode.PAN
		Grid.set_scroll_offset(Grid.get_scroll_offset() - event.relative)
		get_viewport().set_input_as_handled()
		return

	if _node_hold_active and event.index == _node_hold_index:
		_node_hold_current = event.position
		var graph_node := Grid._DRAWN_NODES_BY_ID.get(
			_node_hold_node_id
		) as GraphNode
		if graph_node == null:
			_cancel_node_hold()
			return
		var drag_delta := (
			_node_hold_current - _node_hold_origin
		) / Grid.get_zoom()
		if _node_resizing:
			Grid._on_resize_request(
				_node_start_size + drag_delta,
				graph_node
			)
		elif (
			_node_dragging
			or drag_delta.length() > NODE_DRAG_CANCEL_DISTANCE
		):
			_node_dragging = true
			_node_hold_elapsed = 0.0
			graph_node.position_offset = _node_start_offset + drag_delta
		get_viewport().set_input_as_handled()


func _handle_pan_gesture(event: InputEventPanGesture) -> void:
	if not Grid.get_global_rect().has_point(event.position):
		return
	if _touch_points.size() >= 2:
		# Raw ScreenDrag updates both finger positions and owns pinch calculations.
		# Consuming the derived gesture avoids applying the same movement twice.
		get_viewport().set_input_as_handled()
		return
	# Android reports two-finger navigation as PanGesture even when raw touch
	# drag events are not emitted. Move the graph opposite the finger delta so
	# the canvas visually follows the gesture.
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
	_canvas_mode = CanvasMode.NONE
	_canvas_touch_index = -1
	_canvas_origin = Vector2.ZERO
	_canvas_start_scroll = Vector2.ZERO
	_canvas_elapsed = 0.0


func _begin_canvas_touch(event: InputEventScreenTouch) -> void:
	_begin_canvas_at(event.position, event.index)


func _begin_canvas_at(position: Vector2, input_index: int) -> void:
	_canvas_mode = CanvasMode.PENDING
	_canvas_touch_index = input_index
	_canvas_origin = position
	_canvas_current = position
	_canvas_start_scroll = Grid.get_scroll_offset()
	_canvas_elapsed = 0.0


func _finish_canvas_touch(release_position: Vector2) -> void:
	_canvas_current = release_position

	match _canvas_mode:
		CanvasMode.PENDING:
			# A short tap on empty canvas clears the current selection.
			if _canvas_origin.distance_to(release_position) <= TAP_MOVE_DISTANCE:
				_last_empty_tap_time_ms = Time.get_ticks_msec()
				_last_empty_tap_position = release_position
			_dismiss_text_input()
			_clear_selection()
		CanvasMode.LONG_READY:
			# The menu was already shown as soon as the hold threshold elapsed.
			pass
		CanvasMode.PAN:
			# The canvas was moved continuously during the drag.
			pass

	_canvas_mode = CanvasMode.NONE
	_canvas_touch_index = -1
	_canvas_origin = Vector2.ZERO
	_canvas_start_scroll = Vector2.ZERO
	_canvas_elapsed = 0.0


func handle_grid_touch_press(
	event: InputEventScreenTouch,
	global_position: Vector2
) -> bool:
	if not _setup_complete or not event.pressed:
		return false
	if _find_node_at(global_position) >= 0:
		return false
	_dismiss_text_input()
	if event.double_tap or _is_manual_double_tap(global_position):
		_last_empty_tap_time_ms = -1000
		_cancel_active_canvas_gesture()
		_show_context_menu(global_position)
	else:
		_begin_canvas_at(global_position, event.index)
	return true


func _dismiss_text_input() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
	DisplayServer.virtual_keyboard_hide()


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
	_node_dragging = false
	_node_resizing = false
	var graph_node := Grid._DRAWN_NODES_BY_ID.get(node_id) as GraphNode
	if graph_node != null:
		_node_start_offset = graph_node.position_offset
		_node_start_size = graph_node.size


func _begin_node_resize(event: InputEventScreenTouch, node_id: int) -> void:
	_begin_node_hold(event, node_id)
	_node_resizing = true


func _is_node_resize_point(global_position: Vector2, node_id: int) -> bool:
	var graph_node := Grid._DRAWN_NODES_BY_ID.get(node_id) as GraphNode
	if graph_node == null or not graph_node.resizable:
		return false
	var rect := graph_node.get_global_rect()
	var handle_size := 64.0
	return Rect2(
		rect.end - Vector2.ONE * handle_size,
		Vector2.ONE * handle_size
	).has_point(global_position)


func _finish_node_hold(release_position: Vector2) -> void:
	_node_hold_current = release_position
	var was_long_press := _node_long_press_triggered
	var held_node_id := _node_hold_node_id
	var was_dragging := _node_dragging
	var was_resizing := _node_resizing
	var graph_node := Grid._DRAWN_NODES_BY_ID.get(held_node_id) as GraphNode
	if was_resizing and graph_node != null:
		Grid._on_resize_end(graph_node.size, graph_node)
	elif was_dragging:
		Grid._on_node_move_end()
	_cancel_node_hold()
	if was_long_press or was_dragging or was_resizing:
		# The menu was already shown while the finger was held.
		get_viewport().set_input_as_handled()
	else:
		_last_node_tap_time_ms = Time.get_ticks_msec()
		_last_node_tap_position = release_position
		_last_node_tap_id = held_node_id
		_inspect_android_node.call_deferred(held_node_id)


func _is_manual_node_double_tap(position: Vector2, node_id: int) -> bool:
	var elapsed_ms := Time.get_ticks_msec() - _last_node_tap_time_ms
	return (
		node_id == _last_node_tap_id
		and elapsed_ms >= 0
		and elapsed_ms <= int(DOUBLE_TAP_SECONDS * 1000.0)
		and _last_node_tap_position.distance_to(position) <= DOUBLE_TAP_DISTANCE
	)


func _inspect_android_node(node_id: int) -> void:
	if (
		node_id >= 0
		and Main != null
		and Main.get("Mind") != null
		and Grid._DRAWN_NODES_BY_ID.has(node_id)
	):
		Grid.select_node_by_id(node_id, true)
		Main.Mind.inspect_node(node_id, -1, true)


func _cancel_node_hold() -> void:
	_node_hold_active = false
	_node_hold_index = -1
	_node_hold_node_id = -1
	_node_hold_origin = Vector2.ZERO
	_node_hold_elapsed = 0.0
	_node_long_press_triggered = false
	_node_dragging = false
	_node_resizing = false
	_node_start_offset = Vector2.ZERO
	_node_start_size = Vector2.ZERO


func _begin_pinch() -> void:
	var points := _get_touch_pair()
	if points.size() < 2:
		return

	_cancel_node_hold()
	_canvas_mode = CanvasMode.PINCH

	var first: Vector2 = points[0]
	var second: Vector2 = points[1]
	var midpoint := (first + second) * 0.5

	_pinch_start_distance = maxf(first.distance_to(second), 1.0)
	_pinch_start_zoom = Grid.get_zoom()
	_pinch_anchor_graph_position = (
		Grid.get_scroll_offset() + Grid.to_local(midpoint)
	) / _pinch_start_zoom
	_pinch_update_pending = true


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
	_pinch_update_pending = false


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


func _is_direct_canvas_point(global_position: Vector2) -> bool:
	if not Grid.get_global_rect().has_point(global_position):
		return false
	if Grid.to_local(global_position).y < 42.0:
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


func _find_port_at(global_position: Vector2, outgoing = null) -> Dictionary:
	const PORT_TOUCH_RADIUS := 36.0
	for node_id in Grid._DRAWN_NODES_BY_ID:
		var graph_node := Grid._DRAWN_NODES_BY_ID[node_id] as GraphNode
		if graph_node == null:
			continue
		if outgoing == null or outgoing == false:
			for input_index in graph_node.get_input_port_count():
				var input_position := (
					graph_node.get_global_transform_with_canvas()
					* graph_node.get_input_port_position(input_index)
				)
				if global_position.distance_to(input_position) <= PORT_TOUCH_RADIUS:
					return {
						"node": graph_node,
						"slot": input_index,
						"outgoing": false,
						"position": input_position,
					}
		if outgoing == null or outgoing == true:
			for output_index in graph_node.get_output_port_count():
				var output_position := (
					graph_node.get_global_transform_with_canvas()
					* graph_node.get_output_port_position(output_index)
				)
				if global_position.distance_to(output_position) <= PORT_TOUCH_RADIUS:
					return {
						"node": graph_node,
						"slot": output_index,
						"outgoing": true,
						"position": output_position,
					}
	return {}


func _begin_touch_connection(event: InputEventScreenTouch, port: Dictionary) -> void:
	_touch_connection = port.duplicate()
	_touch_connection.index = event.index
	_touch_connection_preview.clear_points()
	_touch_connection_preview.add_point(port.position)
	_touch_connection_preview.add_point(event.position)
	_touch_connection_preview.visible = true


func _finish_touch_connection(global_position: Vector2) -> void:
	var start := _touch_connection
	var target := _find_port_at(global_position, not start.outgoing)
	_touch_connection = {}
	_touch_connection_preview.visible = false
	_touch_connection_preview.clear_points()
	if not target.is_empty():
		if start.outgoing:
			Grid._on_connection_request(
				start.node.name,
				start.slot,
				target.node.name,
				target.slot
			)
		else:
			Grid._on_connection_request(
				target.node.name,
				target.slot,
				start.node.name,
				start.slot
			)
		return
	ContextMenu.call(
		"show_up",
		global_position,
		Grid.offset_from_position(Grid.to_local(global_position)),
		[start.node._node_id, start.slot, start.outgoing]
	)


func _show_context_menu(global_position: Vector2) -> void:
	if ContextMenu == null or Grid == null:
		return

	ContextMenu.call_deferred(
		"show_up",
		global_position,
		Grid.offset_from_position(Grid.to_local(global_position))
	)


func _clear_selection() -> void:
	if Main != null and Main.get("Mind") != null:
		Main.Mind.force_unselect_all()


func _process(delta: float) -> void:
	if not _setup_complete:
		return
	if _pinch_update_pending and _canvas_mode == CanvasMode.PINCH:
		_pinch_update_pending = false
		_update_pinch()

	if _canvas_mode == CanvasMode.PENDING:
		_canvas_elapsed += delta
		if _canvas_elapsed >= LONG_PRESS_SECONDS:
			_canvas_mode = CanvasMode.LONG_READY
			_show_context_menu(_canvas_current)
			# Vibration intentionally disabled while testing Android long press.

	if _node_hold_active:
		_node_hold_elapsed += delta
		if (
			not _node_dragging
			and not _node_resizing
			and not _node_long_press_triggered
			and _node_hold_elapsed >= LONG_PRESS_SECONDS
		):
			_node_long_press_triggered = true
			_show_context_menu(_node_hold_current)
			# Vibration intentionally disabled while testing Android long press.

	_update_keyboard_avoidance(delta)


func _update_keyboard_avoidance(delta: float) -> void:
	var keyboard_visible := DisplayServer.virtual_keyboard_get_height() > 0
	var focused := get_viewport().gui_get_focus_owner() as Control
	if (
		_keyboard_was_visible
		and not keyboard_visible
		and (focused is LineEdit or focused is TextEdit)
	):
		focused.release_focus()
		focused = null
	_keyboard_was_visible = keyboard_visible
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
