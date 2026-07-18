# Arrow
# Game Narrative Design Tool
# Mor. H. Golkar

# App Menu
extends MenuButton

const ANDROID_MENU_BUTTON_SIZE := Vector2(64.0, 56.0)

@onready var TheTree = get_tree()
@onready var TheWindow = TheTree.get_root()
@onready var Main = TheWindow.get_child(0)

@onready var popup = self.get_popup()

var _MENU_ITEMS = [
	"PREFERENCES",
	null,
	"FULLSCREEN",
	"ALWAYS_ON_TOP",
	"REFRESH",
	null,
	"ABOUT",
	null,
	"CLEAR",
	null,
	"QUIT",
]

var _MENU_ITEMS_DATA = [
	{ "text": "Preferences" },
	null,
	{ "text": "Fullscreen (F11)", "text_toggled": "Exit Fullscreen (F11)", "android": false },
	{ "text": "Stay Above", "text_toggled": "Leave Above", "html5": false, "android": false },
	{ "text": "Refresh", "html5": true },
	null,
	{ "text": "About" },
	null,
	{ "text": "Clear", "html5": true },
	null,
	{ "text": "Quit" },
]

# items listed by key to ...
var _IDX = {} # indices
var _ID = {} # ids
var _android_preferences_queued := false

func _ready() -> void:
	_configure_android_button()
	self.create_menu_items()
	self.update_menu_items_view()
	if OS.has_feature("android"):
		popup.index_pressed.connect(self._on_android_popup_index_pressed)
		popup.window_input.connect(self._on_android_popup_window_input)
	else:
		popup.id_pressed.connect(self._on_self_popup_item_id_pressed, CONNECT_DEFERRED)
	pass


func _configure_android_button() -> void:
	if not OS.has_feature("android"):
		return

	var app_icon := load("res://icon.svg") as Texture2D
	if app_icon == null:
		return

	text = ""
	icon = app_icon
	expand_icon = true
	custom_minimum_size = ANDROID_MENU_BUTTON_SIZE
	tooltip_text = "Preferences"


func _open_android_preferences() -> void:
	if _android_preferences_queued:
		return
	_android_preferences_queued = true
	popup.hide.call_deferred()
	Main.UI.call_deferred("set_panel_visibility", "preferences", true)
	_reset_android_preferences_guard.call_deferred()


func _reset_android_preferences_guard() -> void:
	_android_preferences_queued = false


func _gui_input(event: InputEvent) -> void:
	if not OS.has_feature("android"):
		return
	var released := false
	if event is InputEventScreenTouch:
		released = not event.pressed
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		released = not event.pressed
	if released:
		accept_event()
		_open_android_preferences()


func _on_android_popup_index_pressed(index: int) -> void:
	var item_id := popup.get_item_id(index)
	_on_self_popup_item_id_pressed(item_id)


func _on_android_popup_window_input(event: InputEvent) -> void:
	var released := false
	var event_position := Vector2.ZERO
	if event is InputEventScreenTouch:
		released = not event.pressed
		event_position = event.position
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		released = not event.pressed
		event_position = event.position
	if not released:
		return
	_activate_android_popup_selection.call_deferred(event_position)


func _activate_android_popup_selection(release_position: Vector2) -> void:
	var index := popup.get_focused_item()
	if index < 0 and release_position.y <= 72.0:
		index = popup.get_item_index(_ID.PREFERENCES)
	if index >= 0 and popup.get_item_id(index) == _ID.PREFERENCES:
		_on_android_popup_index_pressed(index)

func create_menu_items() -> void:
	popup.clear()
	var being_in_browser = Html5Helpers.Utils.is_browser()
	var being_on_android := OS.has_feature("android")
	var item_id = 0; # here, id is the same as order of the item
	for item in _MENU_ITEMS:
		if item != null:
			_ID[item] = item_id
			var the_item = _MENU_ITEMS_DATA[item_id];
			if (
				the_item.has("html5") == false || # (is always available)
				(the_item.html5 == being_in_browser) # (depending on the environment)
			) && (
				the_item.has("android") == false ||
				the_item.android == being_on_android
			):
				popup.add_item(the_item.text, item_id)
				_IDX[item] = popup.get_item_index(item_id)
		else:
			popup.add_separator();
		item_id += 1
	pass

func update_menu_items_view() -> void:
	var is_fullscreen = (DisplayServer.window_get_mode() >= DisplayServer.WindowMode.WINDOW_MODE_FULLSCREEN)
	if _IDX.has("FULLSCREEN"):
		popup.set_item_text(
			_IDX.FULLSCREEN,
			_MENU_ITEMS_DATA[_ID.FULLSCREEN].text_toggled if is_fullscreen else _MENU_ITEMS_DATA[_ID.FULLSCREEN].text
		)
	if _IDX.has("ALWAYS_ON_TOP"):
		popup.set_item_text(
			_IDX.ALWAYS_ON_TOP,
			_MENU_ITEMS_DATA[_ID.ALWAYS_ON_TOP].text_toggled if TheWindow.always_on_top else _MENU_ITEMS_DATA[_ID.ALWAYS_ON_TOP].text
		)
	pass

func force_clear_browser_storage() -> void:
	Html5Helpers.Utils.clear_browser_storage()
	pass

func prompt_to_clear_browser_storage() -> void:
	if Html5Helpers.Utils.is_browser():
		Main.Mind.Notifier.call_deferred(
			"show_notification",
			"Are you sure ?",
			"BROWSER_STORAGE_CLEAR_PROMPT",
			[
				{ 
					"label": "Ok; Terminate!",
					"callee": self,
					"method": "force_clear_browser_storage",
					"arguments": []
				},
			],
			Settings.WARNING_COLOR
		)
	else:
		printerr("Trying to clear browser storage out of context!")
	pass

func _on_self_popup_item_id_pressed(id:int) -> void:
	print_debug("app menu popup item pressed: ", id, " - ", _MENU_ITEMS[id])
	match id:
		_ID.PREFERENCES:
			if OS.has_feature("android"):
				popup.hide()
				Main.UI.set_panel_visibility("preferences", true)
			else:
				Main.UI.call_deferred("set_panel_visibility", "preferences", true)
		_ID.FULLSCREEN:
			Main.UI.call_deferred("toggle_fullscreen")
		_ID.ALWAYS_ON_TOP:
			Main.UI.call_deferred("toggle_always_on_top")
		_ID.REFRESH:
			Html5Helpers.Utils.refresh_window()
		_ID.ABOUT:
			Main.call_deferred("toggle_about")
		_ID.QUIT:
			Main.call_deferred("safe_quit_app")
		_ID.CLEAR:
			prompt_to_clear_browser_storage()
	pass
