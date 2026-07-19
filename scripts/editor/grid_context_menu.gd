# Arrow
# Game Narrative Design Tool
# Mor. H. Golkar

# Grid Context Menu
# (right-click popup)
extends PopupPanel

signal request_mind()

@onready var Main = get_tree().get_root().get_child(0)
@onready var Grid = $/root/Main/Editor/Center/Grid

# cached click point position
# (where user has right-clicked and probably wants the node to be placed)
var _CLICK_POINT_POSITION:Vector2
var _CLICK_POINT_OFFSET:Vector2
var _QUICK_INSERT_MODE:bool = false
var _QUICK_INSERT_TARGET = null

@onready var MenuBox = $/root/Main/FloatingTools/Control/Context/Menu
@onready var NodeInsertFilterForm = $/root/Main/FloatingTools/Control/Context/Menu/Node/Types/Actions
@onready var NodeInsertFilterInput = $/root/Main/FloatingTools/Control/Context/Menu/Node/Types/Actions/Filter
@onready var NodeInsertList = $/root/Main/FloatingTools/Control/Context/Menu/Node/Types/List
@onready var InsertNodesButton = $/root/Main/FloatingTools/Control/Context/Menu/Node/Types/Actions/Insert
@onready var EditToolBox = $/root/Main/FloatingTools/Control/Context/Menu/Tools
@onready var ClearClipboardButton = $/root/Main/FloatingTools/Control/Context/Menu/Tools/ClearClipboard
@onready var CopyNodesButton = $/root/Main/FloatingTools/Control/Context/Menu/Tools/Copy
@onready var CutNodesButton = $/root/Main/FloatingTools/Control/Context/Menu/Tools/Cut
@onready var PasteClipboardButton = $/root/Main/FloatingTools/Control/Context/Menu/Tools/Paste
@onready var RemoveNodesButton = $/root/Main/FloatingTools/Control/Context/Menu/Tools/Remove

const CLIPBOARD_MODE = Settings.CLIPBOARD_MODE

var _NODE_INSERT_LIST_FULL = []
var _ANDROID_OVERLAY: Control
var _ANDROID_PANEL: PanelContainer
var _ANDROID_CONTENT: VBoxContainer
var _android_list_touch_index := -1
var _android_list_touch_origin := Vector2.ZERO
var _android_list_last_position := Vector2.ZERO
var _android_list_velocity := 0.0
var _android_list_dragging := false
var _android_suppress_mouse_until_ms := -1000

func _ready() -> void:
	register_connections()
	if OS.has_feature("android"):
		_setup_android_context_menu()
	pass

func _setup_android_context_menu() -> void:
	_ANDROID_OVERLAY = get_node_or_null(
		"/root/Main/Overlays/Control/AndroidContext"
	) as Control
	_ANDROID_PANEL = get_node_or_null(
		"/root/Main/Overlays/Control/AndroidContext/Menu"
	) as PanelContainer
	_ANDROID_CONTENT = get_node_or_null(
		"/root/Main/Overlays/Control/AndroidContext/Menu/Margin/Content"
	) as VBoxContainer
	var shield := get_node_or_null(
		"/root/Main/Overlays/Control/AndroidContext/Shield"
	) as Control
	if (
		_ANDROID_OVERLAY == null
		or _ANDROID_PANEL == null
		or _ANDROID_CONTENT == null
	):
		push_error("Android context menu scene controls are missing.")
		return
	# Reuse the actual desktop controls so mouse and keyboard selection semantics
	# (including Ctrl toggle and Shift range selection) stay exactly identical.
	var node_panel := NodeInsertList.get_parent().get_parent() as PanelContainer
	node_panel.reparent(_ANDROID_CONTENT, false)
	EditToolBox.reparent(_ANDROID_CONTENT, false)
	NodeInsertList.custom_minimum_size = Vector2.ZERO
	NodeInsertList.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var popup_style := get_theme_stylebox("panel", "PopupPanel")
	if popup_style != null:
		_ANDROID_PANEL.add_theme_stylebox_override("panel", popup_style)
	NodeInsertList.gui_input.connect(_on_android_list_gui_input)
	set_process_input(true)
	set_process(true)
	_configure_android_list_scrollbar.call_deferred()
	if shield != null:
		shield.gui_input.connect(_on_android_shield_gui_input)


func _configure_android_list_scrollbar() -> void:
	await get_tree().process_frame
	var scroll_bar: VScrollBar = NodeInsertList.get_v_scroll_bar()
	if scroll_bar != null:
		# Scrolling remains available through wheel and kinetic touch gestures;
		# only direct manipulation of the narrow slider is disabled.
		scroll_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		scroll_bar.modulate.a = 0.0


func _input(event: InputEvent) -> void:
	if (
		not OS.has_feature("android")
		or _ANDROID_OVERLAY == null
		or not _ANDROID_OVERLAY.visible
	):
		return
	if (
		event is InputEventMouseButton
		and Time.get_ticks_msec() <= _android_suppress_mouse_until_ms
	):
		get_viewport().set_input_as_handled()


func _on_android_list_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_android_list_touch_index = event.index
			_android_list_touch_origin = event.position
			_android_list_last_position = event.position
			_android_list_velocity = 0.0
			_android_list_dragging = false
		elif event.index == _android_list_touch_index:
			if _android_list_dragging:
				_android_suppress_mouse_until_ms = Time.get_ticks_msec() + 180
				NodeInsertList.accept_event()
			_android_list_touch_index = -1
		return
	if event is InputEventScreenDrag and event.index == _android_list_touch_index:
		var total_drag: Vector2 = event.position - _android_list_touch_origin
		if not _android_list_dragging and absf(total_drag.y) >= 10.0:
			_android_list_dragging = true
		if _android_list_dragging:
			var scroll_bar: VScrollBar = NodeInsertList.get_v_scroll_bar()
			var drag_delta: float = (
				event.position.y - _android_list_last_position.y
			)
			if scroll_bar != null:
				scroll_bar.value -= drag_delta
			_android_list_velocity = -event.velocity.y
			_android_list_last_position = event.position
			NodeInsertList.accept_event()


func _process(delta: float) -> void:
	if not OS.has_feature("android") or _android_list_touch_index >= 0:
		return
	if absf(_android_list_velocity) < 8.0:
		_android_list_velocity = 0.0
		return
	var scroll_bar: VScrollBar = NodeInsertList.get_v_scroll_bar()
	if scroll_bar == null:
		return
	scroll_bar.value += _android_list_velocity * delta
	_android_list_velocity = move_toward(
		_android_list_velocity,
		0.0,
		2200.0 * delta
	)

func register_connections() -> void:
	self.about_to_popup.connect(self._on_about_to_popup)
	self.window_input.connect(self._on_window_input)
	Main.mind_initialized.connect(self.try_cache_node_type_list_from_mind.bind(true), CONNECT_ONE_SHOT)
	NodeInsertFilterInput.text_changed.connect(self.filter_node_insert_list_items_view, CONNECT_DEFERRED)
	NodeInsertList.multi_selected.connect(self._on_node_insert_list_selection_altered, CONNECT_DEFERRED)
	NodeInsertList.item_selected.connect(self._on_node_insert_list_selection_altered.bind(null), CONNECT_DEFERRED)
	NodeInsertList.item_activated.connect(self._on_node_insert_list_item_activated, CONNECT_DEFERRED)
	InsertNodesButton.pressed.connect(self._on_node_insert_selected_type_button_pressed, CONNECT_DEFERRED)
	RemoveNodesButton.pressed.connect(self._request_mind.bind("remove_selected_nodes", null, true), CONNECT_DEFERRED)
	ClearClipboardButton.pressed.connect(self._request_mind.bind("clean_clipboard", null, true), CONNECT_DEFERRED)
	CopyNodesButton.pressed.connect(self._request_mind.bind("clipboard_push_selection", CLIPBOARD_MODE.COPY, true), CONNECT_DEFERRED)
	CutNodesButton.pressed.connect(self._request_mind.bind("clipboard_push_selection", CLIPBOARD_MODE.CUT, true), CONNECT_DEFERRED)
	PasteClipboardButton.pressed.connect(self.request_clipboard_pull, CONNECT_DEFERRED)
	pass

func try_cache_node_type_list_from_mind(refresh_list:bool = true):
	if Main.Mind && Main.Mind.NODE_TYPES_LIST:
		_NODE_INSERT_LIST_FULL = Main.Mind.NODE_TYPES_LIST.duplicate(true)
	if refresh_list:
		filter_node_insert_list_items_view()
	pass

func show_up(on_position:Vector2, offset:Vector2, quick_insertion = null) -> void:
	_CLICK_POINT_POSITION = on_position
	_CLICK_POINT_OFFSET = offset
	set_quick_insert_mode(quick_insertion)
	if OS.has_feature("android"):
		if _ANDROID_OVERLAY == null or _ANDROID_PANEL == null:
			return
		NodeInsertFilterInput.clear()
		NodeInsertList.deselect_all()
		reset_quick_edit_buttons()
		disable_insert_button_if_nothing_is_there()
		_ANDROID_OVERLAY.show()
		_position_android_overlay()
		_refresh_android_overlay.call_deferred()
		return
	disable_insert_button_if_nothing_is_there()
	self.set_position(on_position)
	self.popup()
	pass


func _position_android_overlay() -> void:
	if _ANDROID_OVERLAY == null or _ANDROID_PANEL == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	_ANDROID_OVERLAY.position = Vector2.ZERO
	_ANDROID_OVERLAY.size = viewport_size
	var desired_size := Vector2(320.0, 300.0)
	desired_size = desired_size.min(viewport_size - Vector2.ONE * 32.0)
	_ANDROID_PANEL.custom_minimum_size = desired_size
	_ANDROID_PANEL.size = desired_size
	# Center anchors are stable across Android CanvasLayer scaling and cannot be
	# reset to the top-left by a parent layout pass.
	_ANDROID_PANEL.anchor_left = 0.5
	_ANDROID_PANEL.anchor_top = 0.5
	_ANDROID_PANEL.anchor_right = 0.5
	_ANDROID_PANEL.anchor_bottom = 0.5
	_ANDROID_PANEL.offset_left = -desired_size.x * 0.5
	_ANDROID_PANEL.offset_top = -desired_size.y * 0.5
	_ANDROID_PANEL.offset_right = desired_size.x * 0.5
	_ANDROID_PANEL.offset_bottom = desired_size.y * 0.5


func _refresh_android_overlay() -> void:
	for attempt in range(30):
		try_cache_node_type_list_from_mind(false)
		if _NODE_INSERT_LIST_FULL.size() > 0:
			filter_node_insert_list_items_view()
			await get_tree().process_frame
			_position_android_overlay()
			return
		await get_tree().process_frame

func _on_about_to_popup() -> void:
	# On Android the main mind may finish initialization before this panel's
	# one-shot signal connection runs. Refreshing here keeps insertion choices
	# and their icons/previews available every time the menu opens.
	try_cache_node_type_list_from_mind(true)
	reset_quick_edit_buttons()
	if OS.has_feature("android"):
		NodeInsertList.custom_minimum_size = Vector2(360, 240)
		_refresh_android_node_type_list.call_deferred()
		call_deferred("_fit_android_popup_to_viewport")
	NodeInsertList.grab_focus.call_deferred()
	NodeInsertList.ensure_current_is_visible.call_deferred()
	pass

func _refresh_android_node_type_list() -> void:
	# The Android scene can display this popup before the mind has finished
	# publishing its node registry. Retry for a few rendered frames instead of
	# leaving a permanently empty ItemList.
	for attempt in range(8):
		if Main.Mind && Main.Mind.NODE_TYPES_LIST.size() > 0:
			_NODE_INSERT_LIST_FULL = Main.Mind.NODE_TYPES_LIST.duplicate(true)
			filter_node_insert_list_items_view()
			_fit_android_popup_to_viewport.call_deferred()
			return
		await get_tree().process_frame


func _on_android_shield_gui_input(event: InputEvent) -> void:
	# Raw Android touch outside the panel closes the overlay. Ignoring the
	# synthesized mouse event prevents the gesture that opened the menu from
	# immediately closing it again on the full-screen shield.
	if event is InputEventScreenTouch and event.pressed:
		_ANDROID_OVERLAY.accept_event()
		_ANDROID_OVERLAY.hide()

func _on_window_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		# DEV: PopupPanel in previous versions of Godot (v3.x) would not block a second right-click on the underlying grid;
		# so we could re-open context menu in another position without first closing the popup.
		# In this version (v4.x) we need to have a workaround for that:
		if event.is_pressed() && event.get_button_mask() == MouseButtonMask.MOUSE_BUTTON_MASK_RIGHT:
			var click_pose = event.get_position()
			if ! MenuBox.get_rect().has_point(click_pose):
				Grid._on_popup_request()
	pass


func _fit_android_popup_to_viewport() -> void:
	if not OS.has_feature("android"):
		return

	var viewport_size := get_viewport().get_visible_rect().size
	var fitted_size := Vector2i(
		mini(maxi(size.x, 320), int(viewport_size.x * 0.62)),
		mini(maxi(size.y, 300), int(viewport_size.y * 0.78))
	)
	size = fitted_size

	position = Vector2i(
		clampi(position.x, 0, maxi(0, int(viewport_size.x) - size.x)),
		clampi(position.y, 0, maxi(0, int(viewport_size.y) - size.y))
	)
	pass

func disable_insert_button_if_nothing_is_there(force_disabled:bool = false) -> void:
	var disable
	if force_disabled == true :
		disable = force_disabled
	else:
		disable = (
			NodeInsertList.get_selected_items().size() == 0 ||
			NodeInsertList.get_item_count() == 0
		)
	InsertNodesButton.set_disabled(disable)
	pass

func set_quick_insert_mode(target = null) -> void:
	_QUICK_INSERT_MODE = (target is Array && target.size() == 3)
	_QUICK_INSERT_TARGET = (target if _QUICK_INSERT_MODE else null)
	NodeInsertFilterForm.set_visible(not _QUICK_INSERT_MODE)
	EditToolBox.set_visible( ! _QUICK_INSERT_MODE )
	NodeInsertList.set_select_mode( ItemList.SELECT_SINGLE if _QUICK_INSERT_MODE else ItemList.SELECT_MULTI )
	NodeInsertList.set_default_cursor_shape(
		Control.CursorShape.CURSOR_POINTING_HAND if ( _QUICK_INSERT_MODE && Settings.QUICK_INSERT_NODES_ON_SINGLE_CLICK )
		else Control.CursorShape.CURSOR_ARROW
	)
	pass

func reset_quick_edit_buttons():
	var there_is_selection = (Grid._ALREADY_SELECTED_NODE_IDS.size() > 0)
	var there_is_highlight = (Grid._HIGHLIGHTED_NODES.size() > 0)
	var selected_nodes_are_removable = there_is_selection && Main.Mind.batch_remove_resources(Grid._ALREADY_SELECTED_NODE_IDS, "nodes", true, true) # check-only
	var selected_nodes_are_moveable = there_is_selection && (Main.Mind.immovable_nodes(Grid._ALREADY_SELECTED_NODE_IDS).size() == 0)
	var clipboard_has_copy_or_paste = Main.Mind.clipboard_available()
	PasteClipboardButton.set_disabled( clipboard_has_copy_or_paste == false )
	RemoveNodesButton.set_disabled( selected_nodes_are_removable == false )
	CutNodesButton.set_disabled( selected_nodes_are_moveable == false )
	# copy and clean-clipboard buttons will switch visibility when there_is_selection
	ClearClipboardButton.set("visible", there_is_selection == false && (clipboard_has_copy_or_paste || there_is_highlight))
	ClearClipboardButton.set_disabled( there_is_selection || there_is_highlight == false )
	CopyNodesButton.set("visible", there_is_selection ||  clipboard_has_copy_or_paste == false )
	CopyNodesButton.set_disabled( there_is_selection == false )
	# Note: `InsertNodesButton` & `NodeInsertList` are handled elsewhere.
	pass

func get_restricted_types() -> Array:
	var restriction:Array
	if Main.Mind.is_scene_macro():
		restriction = Settings.NODE_TYPES_RESTRICTED_IN_MACROS
	else:
		restriction = []
	return restriction

# refreshes the list of available node types (modules)
# also updates the index and id caches and attaches meta-data to them
func filter_node_insert_list_items_view(query:String = "", try_read_filter_input:bool = false) -> void:
	clear_node_insert_list()
	if query.length() <= 0 && try_read_filter_input == true:
		query = NodeInsertFilterInput.get_text()
	var show_all = true if (query.length() <= 0 || query == "*" ) else false
	var restricted_items = get_restricted_types()
	var item_order = 0;
	for item in _NODE_INSERT_LIST_FULL:
		if (restricted_items.has(item) == false):
			var item_details = _NODE_INSERT_LIST_FULL[item]
			if show_all || (item_details.text.findn(query, 0) >= 0) :
				NodeInsertList.add_item(item_details.text, item_details.icon)
				NodeInsertList.set_item_metadata(item_order, item_details)
				item_order += 1 
	NodeInsertList.sort_items_by_text()
	disable_insert_button_if_nothing_is_there()
	pass

func clear_node_insert_list() -> void :
	NodeInsertList.clear()
	pass

func _on_node_insert_list_selection_altered(_index, _selected) -> void:
	disable_insert_button_if_nothing_is_there()
	if _QUICK_INSERT_MODE && Settings.QUICK_INSERT_NODES_ON_SINGLE_CLICK != false:
		insert_selected_nodes_from_list()
	pass

func _on_node_insert_list_item_activated(_item_index:int) -> void:
	insert_selected_nodes_from_list()
	pass

func _on_node_insert_selected_type_button_pressed() -> void:
	insert_selected_nodes_from_list()
	pass
	
func insert_selected_nodes_from_list() -> void:
	var items_indices = NodeInsertList.get_selected_items()
	if items_indices.size() > 0 :
		if _QUICK_INSERT_MODE:
			_request_mind("quick_insert_node", {
				"node": NodeInsertList.get_item_metadata(items_indices[0]).type,
				"offset": _CLICK_POINT_OFFSET,
				"connection": _QUICK_INSERT_TARGET
			}, true )
		else:
			var item_types = []
			for item_index in items_indices:
				var item_type = NodeInsertList.get_item_metadata(item_index).type
				item_types.push_back(item_type)
			_request_mind("insert_node", { "nodes": item_types, "offset": _CLICK_POINT_OFFSET }, true )
	pass

func request_clipboard_pull() -> void:
	_request_mind("clipboard_pull", _CLICK_POINT_OFFSET, true)
	pass

func _request_mind(req:String, args, hide_menu:bool = false) -> void:
	self.request_mind.emit(req, args)
	# ... and close the grid context menu (popup)
	if hide_menu:
		if OS.has_feature("android") and _ANDROID_OVERLAY != null:
			_ANDROID_OVERLAY.hide()
		else:
			self.hide()
	pass
