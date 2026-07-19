extends Control
# Écran de rapport de bug / suggestion — POST /api/feedback (UPlanet_API.send_feedback)
# Même endpoint que UPlanet/earth (feedback.js) et Zelkova (FeedbackService).
# Accessible depuis AideScreen.gd (bouton "🐛 Signaler un bug").

signal feedback_closed

const CATEGORIES: Array[String] = ["bug", "feature", "question", "praise"]
const CATEGORY_LABELS := {
	"bug": "🐛 Bug", "feature": "✨ Idée",
	"question": "❓ Question", "praise": "👍 Compliment",
}

var _selected_category: String = "bug"
var _category_group := ButtonGroup.new()
var _title_inp: LineEdit
var _desc_inp: TextEdit
var _status_lbl: Label
var _send_btn: Button

func _ready():
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = 95

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.02, 0.1, 0.95)
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll)

	var m := MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(side, UI_Theme.scale_px(22))
	scroll.add_child(m)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UI_Theme.scale_px(16))
	m.add_child(vbox)

	_build_form(vbox)
	UI_Theme.auto_scale(vbox)

	UPlanet_API.connect("feedback_sent", Callable(self, "_on_feedback_sent"))
	UPlanet_API.connect("feedback_error", Callable(self, "_on_feedback_error"))

func _exit_tree():
	if UPlanet_API.is_connected("feedback_sent", Callable(self, "_on_feedback_sent")):
		UPlanet_API.disconnect("feedback_sent", Callable(self, "_on_feedback_sent"))
	if UPlanet_API.is_connected("feedback_error", Callable(self, "_on_feedback_error")):
		UPlanet_API.disconnect("feedback_error", Callable(self, "_on_feedback_error"))

func _build_form(vbox: VBoxContainer):
	var title := Label.new()
	title.text = "🐛 Signaler un bug / suggestion"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD
	title.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(24))
	title.modulate = UI_Theme.accent_color()
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	UI_Theme.add_label(vbox, "Type", 13, UI_Theme.text_secondary())
	var cat_hb := HBoxContainer.new()
	cat_hb.add_theme_constant_override("separation", UI_Theme.scale_px(8))
	vbox.add_child(cat_hb)
	for cat in CATEGORIES:
		var btn := Button.new()
		btn.text = CATEGORY_LABELS[cat]
		btn.toggle_mode = true
		btn.button_pressed = (cat == _selected_category)
		btn.button_group = _category_group
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_category_selected.bind(cat))
		cat_hb.add_child(btn)

	vbox.add_child(HSeparator.new())

	UI_Theme.add_label(vbox, "Titre", 13, UI_Theme.text_secondary())
	_title_inp = UI_Theme.add_input(vbox, "FeedbackTitle", "Résumé en une phrase", 56)

	UI_Theme.add_label(vbox, "Description", 13, UI_Theme.text_secondary())
	_desc_inp = TextEdit.new()
	_desc_inp.custom_minimum_size = Vector2(0, UI_Theme.scale_px(160))
	_desc_inp.placeholder_text = "Décrivez le problème ou l'idée en détail…"
	_desc_inp.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	vbox.add_child(_desc_inp)

	_status_lbl = Label.new()
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_lbl.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(13))
	vbox.add_child(_status_lbl)

	_send_btn = UI_Theme.add_styled_button(vbox, "✈️ Envoyer",
		Callable(self, "_on_send_pressed"), false)
	_send_btn.custom_minimum_size = Vector2(0, UI_Theme.scale_px(64))

	var btn_close := Button.new()
	btn_close.text = "✕ Fermer"
	btn_close.custom_minimum_size = Vector2(0, UI_Theme.scale_px(48))
	btn_close.add_theme_font_size_override("font_size", UI_Theme._get_scaled_size(16))
	btn_close.pressed.connect(_close)
	vbox.add_child(btn_close)

func _on_category_selected(cat: String):
	_selected_category = cat

func _on_send_pressed():
	var title_txt := _title_inp.text.strip_edges()
	var desc_txt := _desc_inp.text.strip_edges()
	if title_txt == "":
		_status_lbl.text = "⚠ Le titre est requis."
		_status_lbl.modulate = Color(1, 0.3, 0.3)
		return
	if desc_txt.length() < 10:
		_status_lbl.text = "⚠ Décrivez le problème un peu plus (10 caractères min)."
		_status_lbl.modulate = Color(1, 0.3, 0.3)
		return

	UI_Theme.vibrate(50)
	_status_lbl.text = "⏳ Envoi en cours…"
	_status_lbl.modulate = Color(0.8, 0.8, 0.8)
	_send_btn.disabled = true

	var pubkey := Player_Origin.user_npub if not Player_Origin.user_npub.is_empty() \
		else Player_Origin.user_g1pub
	UPlanet_API.send_feedback(title_txt, desc_txt, _selected_category, pubkey)

func _on_feedback_sent(result: Dictionary):
	_send_btn.disabled = false
	var stored: String = result.get("stored", "local")
	match stored:
		"git":
			var num = result.get("issue_number", null)
			_status_lbl.text = "✅ Merci ! Issue créée" + (" #%s" % str(num) if num != null else "") + "."
		"email":
			_status_lbl.text = "📧 Merci ! Transmis par email au capitaine."
		_:
			_status_lbl.text = "✅ Merci ! Feedback reçu."
	_status_lbl.modulate = Color(0.4, 1.0, 0.5)
	_title_inp.text = ""
	_desc_inp.text = ""

func _on_feedback_error(message: String):
	_send_btn.disabled = false
	_status_lbl.text = "❌ " + message
	_status_lbl.modulate = Color(1, 0.4, 0.4)

func _close():
	emit_signal("feedback_closed")
	queue_free()
