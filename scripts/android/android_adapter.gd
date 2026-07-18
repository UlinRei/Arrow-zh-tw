extends Node

# Android-only runtime adaptation.
# Desktop and Web exports are unaffected because this autoload removes itself.

const ANDROID_UI_SCALE := 0.88
const KEYBOARD_MARGIN := 28.0
const KEYBOARD_MOVE_SPEED := 1800.0

var Main: Control
var _main_base_position := Vector2.ZERO
var _keyboard_shift := 0.0
var _setup_complete := false


func _ready() -> void:
	if not OS.has_feature("android"):
		queue_free()
		return

	set_process(true)
	call_deferred("_setup_android")


func _setup_android() -> void:
	# Autoloads start before the main scene. Wait until the root UI exists.
	while Main == null:
		Main = get_node_or_null("/root/Main") as Control
		if Main == null:
			await get_tree().process_frame

	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)

	# A smaller factor shows more UI on phone/tablet screens.
	# This is runtime-only and therefore does not affect desktop builds.
	var root_window := get_window()
	root_window.content_scale_factor = ANDROID_UI_SCALE

	# Let the new content scale settle before recording the unshifted position.
	await get_tree().process_frame
	_main_base_position = Main.position

	_configure_optional_android_controls()
	_setup_complete = true


func _configure_optional_android_controls() -> void:
	# Use the Android system document picker when this dialog is present.
	var path_dialog := get_node_or_null("/root/Main/Overlays/Control/PathDialog")
	if path_dialog is FileDialog:
		path_dialog.use_native_dialog = true

	# Android keeps projects in user://, so external work-directory selection
	# is not useful. These lookups are optional and never abort adaptation.
	var work_dir_row := get_node_or_null(
		"/root/Main/Overlays/Control/Preferences/Margin/Sections/Configs/Scroll/Params/WorkDir"
	)
	if work_dir_row is CanvasItem:
		work_dir_row.hide()

	# Do not expose the fork's external-font browser on Android.
	var external_font_button := get_node_or_null(
		"/root/Main/Overlays/Control/Preferences/Margin/Sections/Configs/Scroll/Params/Font/Selector/Tools/Browse"
	)
	if external_font_button is BaseButton:
		external_font_button.hide()
		external_font_button.disabled = true


func _process(delta: float) -> void:
	if not _setup_complete or Main == null:
		return

	var target_shift := _calculate_keyboard_shift()
	_keyboard_shift = move_toward(
		_keyboard_shift,
		target_shift,
		KEYBOARD_MOVE_SPEED * delta
	)

	Main.position = _main_base_position + Vector2(0.0, round(_keyboard_shift))


func _calculate_keyboard_shift() -> float:
	var keyboard_height_pixels := DisplayServer.virtual_keyboard_get_height()
	if keyboard_height_pixels <= 0:
		return 0.0

	var focused := get_viewport().gui_get_focus_owner() as Control
	if focused == null or not focused.is_visible_in_tree():
		return 0.0

	# The keyboard height is reported in physical pixels. Convert it to the
	# viewport's logical coordinates after content scaling.
	var stretch_scale_y := get_viewport().get_stretch_transform().get_scale().y
	if is_zero_approx(stretch_scale_y):
		stretch_scale_y = 1.0

	var keyboard_height := float(keyboard_height_pixels) / absf(stretch_scale_y)
	var viewport_height := get_viewport().get_visible_rect().size.y
	var visible_bottom := viewport_height - keyboard_height - KEYBOARD_MARGIN

	# The focused rect already includes the current upward shift. Reconstruct
	# its unshifted bottom to avoid feedback/oscillation.
	var focused_bottom_unshifted := focused.get_global_rect().end.y - _keyboard_shift
	var required_shift := visible_bottom - focused_bottom_unshifted

	return minf(required_shift, 0.0)
