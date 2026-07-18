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
var _ANDROID_NODE_BUTTONS_SCROLL: ScrollContainer
var _ANDROID_NODE_BUTTONS: VBoxContainer

func _ready() -> void:
	register_connections()
	if OS.has_feature("android"):
		_setup_android_node_buttons()
	pass

func _setup_android_node_buttons() -> void:
	_ANDROID_NODE_BUTTONS_SCROLL = ScrollContainer.new()
	_ANDROID_NODE_BUTTONS_SCROLL.name = "AndroidNodeButtonsScroll"
	_ANDROID_NODE_BUTTONS_SCROLL.custom_minimum_size = Vector2(360, 240)
	_ANDROID_NODE_BUTTONS_SCROLL.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ANDROID_NODE_BUTTONS_SCROLL.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ANDROID_NODE_BUTTONS = VBoxContainer.new()
	_ANDROID_NODE_BUTTONS.name = "AndroidNodeButtons"
	_ANDROID_NODE_BUTTONS.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ANDROID_NODE_BUTTONS.add_theme_constant_override("separation", 6)
	_ANDROID_NODE_BUTTONS_SCROLL.add_child(_ANDROID_NODE_BUTTONS)
	var types_box := NodeInsertList.get_parent()
	types_box.add_child(_ANDROID_NODE_BUTTONS_SCROLL)
	types_box.move_child(_ANDROID_NODE_BUTTONS_SCROLL, 0)
	NodeInsertList.hide()

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
	disable_insert_button_if_nothing_is_there()
	set_quick_insert_mode(quick_insertion)
	self.set_position(on_position)
	self.popup()
	pass

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
			_populate_android_node_buttons()
			_fit_android_popup_to_viewport.call_deferred()
			return
		await get_tree().process_frame

func _populate_android_node_buttons() -> void:
	if _ANDROID_NODE_BUTTONS == null:
		return
	for child in _ANDROID_NODE_BUTTONS.get_children():
		child.queue_free()
	var restricted_items := get_restricted_types()
	for item_type in _NODE_INSERT_LIST_FULL:
		if restricted_items.has(item_type):
			continue
		var item_details = _NODE_INSERT_LIST_FULL[item_type]
		var button := Button.new()
		button.text = item_details.text
		button.icon = item_details.icon
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 54)
		button.add_theme_constant_override("icon_max_width", 40)
		button.pressed.connect(_on_android_node_type_pressed.bind(item_details))
		_ANDROID_NODE_BUTTONS.add_child(button)

func _on_android_node_type_pressed(item_details: Dictionary) -> void:
	if _QUICK_INSERT_MODE:
		_request_mind("quick_insert_node", {
			"node": item_details.type,
			"offset": _CLICK_POINT_OFFSET,
			"connection": _QUICK_INSERT_TARGET,
		}, true)
	else:
		_request_mind("insert_node", {
			"nodes": [item_details.type],
			"offset": _CLICK_POINT_OFFSET,
		}, true)

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
	NodeInsertFilterForm.set_visible(
		not _QUICK_INSERT_MODE and not OS.has_feature("android")
	)
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
		self.hide()
	pass
