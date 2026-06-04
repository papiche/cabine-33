extends Node
# Gestionnaire de thèmes visuels ATOM4LOVE — styles interchangeables
# Les développeurs peuvent enregistrer leurs propres thèmes via register_theme()

signal theme_changed(theme_id)

const DEFAULT_THEME: String = "cosmic_dark"
const SAVE_KEY: String = "atom4love_ui_theme"

# Structure d'un thème :
# { id, label, bg, border, accent, accent2, text, bar_day, bar_night, panel_alpha }
var _themes: Dictionary = {}
var current_theme_id: String = DEFAULT_THEME

func _ready():
	_register_builtin_themes()
	var saved = ProjectSettings.get_setting("atom4love/ui_theme", DEFAULT_THEME)
	if _themes.has(saved):
		current_theme_id = saved
	else:
		current_theme_id = DEFAULT_THEME
	_setup_emoji_font()
	# Purger le cache de scale si la fenêtre est redimensionnée (split-screen Android, web)
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		tree.root.size_changed.connect(func(): _cached_vp_scale = -1.0)

func _setup_emoji_font():
	var emoji_path := "res://fonts/NotoColorEmoji.ttf"
	if not ResourceLoader.exists(emoji_path): return
	var emoji := load(emoji_path) as FontFile
	if emoji == null: return
	var fb : Font = ThemeDB.fallback_font
	if fb != null:
		fb.fallbacks = [emoji]

# ── API publique ──────────────────────────────────────────────────────────────

func register_theme(id: String, definition: Dictionary):
	_themes[id] = definition

func get_theme_ids() -> Array:
	return _themes.keys()

func get_theme_label(id: String) -> String:
	return _themes.get(id, {}).get("label", id)

func apply_theme(id: String):
	if not _themes.has(id): return
	current_theme_id = id
	ProjectSettings.set_setting("atom4love/ui_theme", id)
	emit_signal("theme_changed", id)

func current() -> Dictionary:
	return _themes.get(current_theme_id, _themes[DEFAULT_THEME])

# Helpers pour créer rapidement des StyleBoxFlat cohérents avec le thème actif

func make_panel_style(alpha_override: float = -1.0) -> StyleBoxFlat:
	var t = current()
	var s = StyleBoxFlat.new()
	var a = alpha_override if alpha_override >= 0.0 else t.get("panel_alpha", 0.85)
	s.bg_color = Color(t["bg"].r, t["bg"].g, t["bg"].b, a)
	s.border_width_left = 2; s.border_width_right = 2
	s.border_width_top = 1; s.border_width_bottom = 1
	s.border_color = t["border"]
	s.set_corner_radius_all(16)
	return s

func make_button_style(use_accent2: bool = false) -> StyleBoxFlat:
	# Normal : fond sombre + bordure accent → texte accent lisible
	var t = current()
	var ac: Color = t["accent2"] if use_accent2 else t["accent"]
	var bg: Color = t["bg"] as Color
	var s = StyleBoxFlat.new()
	s.bg_color = Color(bg.r + 0.05, bg.g + 0.05, bg.b + 0.08, 0.92)
	s.border_width_left  = 2; s.border_width_right  = 2
	s.border_width_top   = 2; s.border_width_bottom = 2
	s.border_color = Color(ac.r, ac.g, ac.b, 0.85)
	s.set_corner_radius_all(12)
	s.set_content_margin_all(14)
	return s

func _make_button_hover_style(use_accent2: bool = false) -> StyleBoxFlat:
	# Hover / Pressed : fond teinté accent + bordure pleine → texte blanc
	var t = current()
	var ac: Color = t["accent2"] if use_accent2 else t["accent"]
	var s = StyleBoxFlat.new()
	s.bg_color = Color(ac.r * 0.28, ac.g * 0.28, ac.b * 0.28, 0.97)
	s.border_width_left  = 2; s.border_width_right  = 2
	s.border_width_top   = 2; s.border_width_bottom = 2
	s.border_color = Color(ac.r, ac.g, ac.b, 1.0)
	s.set_corner_radius_all(12)
	s.set_content_margin_all(14)
	return s

func create_label(text: String, size: int, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", _get_scaled_size(size))
	l.modulate = color
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	return l

# ── Mise à l'échelle adaptative ─────────────────────────────────────────────
# Référence de design : 720 × 1280 (portrait mobile).
# Formule : min(largeur/720, hauteur/1280) → scale uniforme qui préserve les
# proportions quels que soient l'écran (petit téléphone, grand téléphone, tablette).
# À 720×1280 : scale = 1.0 — tailles de design exactes.
# À 540×960  : scale = 0.75 — réduit légèrement sur petits écrans.
# À 1080×1920: scale = 1.5  — agrandit sur grands écrans / tablettes.

const _DESIGN_W: float = 720.0
const _DESIGN_H: float = 1280.0
var _cached_vp_scale: float = -1.0

func _get_vp_scale() -> float:
	if _cached_vp_scale < 0.0:
		var vps := get_viewport().get_visible_rect().size if get_viewport() else Vector2(_DESIGN_W, _DESIGN_H)
		_cached_vp_scale = clampf(minf(vps.x / _DESIGN_W, vps.y / _DESIGN_H), 0.75, 1.6)
	return _cached_vp_scale

# ── Type scale mobile ATOM4LOVE ──────────────────────────────────────────────
# Facteur d'amplification typographique : les tailles "design" sont des
# indices sémantiques que l'on projette sur une échelle mobile lisible.
# Règle : jamais moins de 15px pour un texte visible, 19px pour le corps.
# Reference Material Design : 16sp corps, 12sp minimum légende.
#
# Index → taille mobile réelle (à scale=1.0, 720×1280) :
#   ≤ 12 (hint/caption)   →  15px
#   13   (secondary)      →  17px
#   14   (body small)     →  19px
#   15   (body)           →  20px
#   16   (body+)          →  22px
#   17-19 (label)         →  23px
#   20-22 (section)       →  27px
#   23-26 (heading)       →  30px
#   27+  (title)          →  size × 1.12

func _get_scaled_size(base: int) -> int:
	var s := _get_vp_scale()
	var mobile: int
	if   base <= 12: mobile = 15
	elif base <= 13: mobile = 17
	elif base <= 14: mobile = 19
	elif base <= 15: mobile = 20
	elif base <= 16: mobile = 22
	elif base <= 19: mobile = 23
	elif base <= 22: mobile = 27
	elif base <= 26: mobile = 30
	else:            mobile = int(base * 1.12)
	return maxi(15, int(float(mobile) * s))

func scale_px(px: int) -> int:
	# Scala une hauteur ou marge en px selon le facteur d'écran
	return maxi(1, int(px * _get_vp_scale()))

func add_panel_vbox(parent: Node) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", make_panel_style())
	parent.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", scale_px(12))  # +6 vs ancien pour aérer
	pc.add_child(v)
	return v

func setup_auto_advance(current: LineEdit, next_field: LineEdit, max_len: int):
	current.max_length = max_len
	current.text_changed.connect(func(text: String):
		if text.length() >= max_len and is_instance_valid(next_field):
			next_field.grab_focus())

func add_styled_button(parent: Node, text: String, callback: Callable,
		accent2: bool = false, min_h: int = 62) -> Button:
	var t := current()
	var ac: Color = t["accent2"] if accent2 else t["accent"]
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, scale_px(min_h))
	# Styles : normal (fond sombre + bordure) / hover (fond teinté) / pressed (même que hover)
	btn.add_theme_stylebox_override("normal",  make_button_style(accent2))
	btn.add_theme_stylebox_override("hover",   _make_button_hover_style(accent2))
	btn.add_theme_stylebox_override("pressed", _make_button_hover_style(accent2))
	btn.add_theme_stylebox_override("focus",   make_button_style(accent2))
	# Couleurs de texte : accent sur fond sombre, blanc sur hover
	btn.add_theme_color_override("font_color",         Color(ac.r * 1.1, ac.g * 1.1, ac.b * 1.1).clamp())
	btn.add_theme_color_override("font_hover_color",   Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	btn.add_theme_color_override("font_focus_color",   Color(ac.r * 1.1, ac.g * 1.1, ac.b * 1.1).clamp())
	btn.add_theme_font_size_override("font_size", _get_scaled_size(16))
	if callback.is_valid(): btn.pressed.connect(callback)
	btn.button_down.connect(func(): vibrate(15))
	parent.add_child(btn)
	return btn

func add_section_title(parent: Node, text: String) -> Label:
	var l := create_label(text, 16, accent_color())
	parent.add_child(l)
	return l

func add_label(parent: Node, text: String, size: int = 14,
		color: Color = Color.TRANSPARENT, wrap: bool = true) -> Label:
	var l := create_label(text, size, color if color != Color.TRANSPARENT else text_color())
	if wrap: l.autowrap_mode = TextServer.AUTOWRAP_WORD
	parent.add_child(l)
	return l

func add_labeled_input(parent: Node, p_name: String, label_text: String,
		placeholder: String, min_h: int = 50,
		kbd: int = LineEdit.KEYBOARD_TYPE_DEFAULT) -> LineEdit:
	add_label(parent, label_text, 13, text_secondary())
	return add_input(parent, p_name, placeholder, min_h, kbd)

func add_input(parent: Node, p_name: String, placeholder: String,
		min_h: int = 68, kbd: int = LineEdit.KEYBOARD_TYPE_DEFAULT) -> LineEdit:
	var t := current()
	var bg := t["bg"] as Color
	var ac := t["accent"] as Color
	var le := LineEdit.new()
	le.name = p_name
	le.placeholder_text = placeholder
	le.custom_minimum_size = Vector2(0, scale_px(min_h))
	le.virtual_keyboard_type = kbd
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.add_theme_font_size_override("font_size", _get_scaled_size(16))
	# Style : fond légèrement plus clair + bordure basse accent (underline)
	var inp_sb := StyleBoxFlat.new()
	inp_sb.bg_color = Color(bg.r + 0.07, bg.g + 0.07, bg.b + 0.12, 0.95)
	inp_sb.border_width_bottom = 2
	inp_sb.border_color = Color(ac.r, ac.g, ac.b, 0.6)
	inp_sb.set_corner_radius_all(8)
	inp_sb.set_content_margin_all(scale_px(12))
	inp_sb.content_margin_left  = scale_px(14)
	inp_sb.content_margin_right = scale_px(14)
	le.add_theme_stylebox_override("normal", inp_sb)
	# Style focus : bordure basse plus marquée
	var foc_sb := inp_sb.duplicate() as StyleBoxFlat
	foc_sb.border_width_bottom = 3
	foc_sb.border_color = Color(ac.r, ac.g, ac.b, 1.0)
	foc_sb.bg_color = Color(bg.r + 0.10, bg.g + 0.10, bg.b + 0.16, 1.0)
	le.add_theme_stylebox_override("focus", foc_sb)
	# Couleurs texte
	le.add_theme_color_override("font_color",             t["text"] as Color)
	le.add_theme_color_override("font_placeholder_color", text_hint())
	le.add_theme_color_override("caret_color",            ac)
	le.add_theme_color_override("selection_color",        Color(ac.r, ac.g, ac.b, 0.35))
	parent.add_child(le)
	return le

func auto_scale(node: Node):
	# Réservé aux scènes .tscn chargées sans passer par les builders UI_Theme.
	# NE PAS appeler sur des arbres déjà construits via add_label/add_input/etc.
	# (les builders scalent déjà via _get_scaled_size et scale_px).
	var s := _get_vp_scale()
	if absf(s - 1.0) < 0.03: return  # pas de scaling si dans 3% de la cible
	if node is Control:
		var ctrl := node as Control
		if ctrl.has_theme_font_size_override("font_size"):
			var fs := ctrl.get_theme_font_size("font_size")
			ctrl.add_theme_font_size_override("font_size", maxi(8, int(fs * s)))
		if ctrl.custom_minimum_size.y > 0.0:
			ctrl.custom_minimum_size.y = ctrl.custom_minimum_size.y * s
	for child in node.get_children():
		auto_scale(child)

func vibrate(duration_ms: int):
	if OS.has_feature("web"):
		JavaScriptBridge.eval("if(navigator.vibrate) navigator.vibrate(%d);" % duration_ms)
	else:
		Input.vibrate_handheld(duration_ms)

func accent_color() -> Color:
	return current()["accent"]

func text_color() -> Color:
	return current()["text"]

func bar_color(is_night: bool = false) -> Color:
	var t = current()
	return t["bar_night"] if is_night else t["bar_day"]

func _is_dark() -> bool:
	return (current()["bg"] as Color).get_luminance() < 0.4

# Texte secondaire — mélange texte+accent, lisible sur tout thème
func text_secondary() -> Color:
	return text_color().lerp(accent_color(), 0.7)

# Texte atténué (hints, descriptions)
func text_hint() -> Color:
	var t := text_color()
	return Color(t.r, t.g, t.b, 0.60)

# Texte positif/succès — bar_day du thème (vert foncé ou vif selon contexte)
func text_positive() -> Color:
	return bar_color(false)

# Texte chaud/doré (Kin Maya, polarité solaire) — accent2 du thème
func text_warm() -> Color:
	return current()["accent2"] as Color

# Couleur selon taux de résonance k — source unique pour tous les onglets
func k_color(k: float) -> Color:
	if k >= 0.95: return Color(1.0, 0.85, 0.0)   # or — singularité optique
	if k >= 0.80: return Color(0.0, 1.0, 0.5)    # vert vif
	if k >= 0.60: return Color(0.0, 0.78, 1.0)   # cyan
	return Color(0.5, 0.5, 0.5)                   # gris — faible résonance

# ── Thèmes intégrés ───────────────────────────────────────────────────────────

func _register_builtin_themes():
	# ── 1. Cosmique Sombre — fond espace profond, accents cyan/ambre
	register_theme("cosmic_dark", {
		"label":       "🌑 Sombre",
		"bg":          Color(0.020, 0.047, 0.118),  # #050C1E
		"border":      Color(0.0,   0.784, 1.0,  0.65),
		"accent":      Color(0.0,   0.784, 1.0),   # #00C8FF cyan
		"accent2":     Color(0.980, 0.659, 0.063), # #FAA810 ambre chaud
		"text":        Color(0.871, 0.941, 1.0),   # #DEF0FF
		"bar_day":     Color(0.118, 0.878, 0.502), # #1EE080 vert vif
		"bar_night":   Color(0.502, 0.251, 1.0),   # #8040FF violet
		"panel_alpha": 0.88,
	})

	# ── 2. Lumière Claire — propre, haut contraste, WCAG AA
	register_theme("lumiere_claire", {
		"label":       "☀ Clair",
		"bg":          Color(0.953, 0.961, 0.980),  # #F3F5FA
		"border":      Color(0.180, 0.357, 0.722, 0.5),
		"accent":      Color(0.118, 0.318, 0.718),  # #1E51B7
		"accent2":     Color(0.761, 0.318, 0.027),  # #C25107 orange brun
		"text":        Color(0.078, 0.094, 0.188),  # #141830
		"bar_day":     Color(0.094, 0.494, 0.188),  # #187E30 vert foncé
		"bar_night":   Color(0.333, 0.157, 0.588),  # #552896 violet foncé
		"panel_alpha": 0.96,
	})

	# ── 3. Solarized Dark — palette Ethan Schoonover
	register_theme("solarized_dark", {
		"label":       "🌓 Solarisé Sombre",
		"bg":          Color(0.0,   0.169, 0.212),  # #002B36 base03
		"border":      Color(0.345, 0.431, 0.459, 0.7),  # #586E75 base01
		"accent":      Color(0.149, 0.545, 0.824),  # #268BD2 blue
		"accent2":     Color(0.796, 0.294, 0.086),  # #CB4B16 orange
		"text":        Color(0.514, 0.580, 0.588),  # #839496 base0
		"bar_day":     Color(0.522, 0.600, 0.0),    # #859900 green
		"bar_night":   Color(0.424, 0.443, 0.769),  # #6C71C4 violet
		"panel_alpha": 0.93,
	})

	# ── 4. Solarized Light — même palette, fond crème
	register_theme("solarized_light", {
		"label":       "🌤 Solarisé Clair",
		"bg":          Color(0.992, 0.965, 0.890),  # #FDF6E3 base3
		"border":      Color(0.576, 0.631, 0.631, 0.6),  # #93A1A1 base1
		"accent":      Color(0.149, 0.545, 0.824),  # #268BD2 blue (même)
		"accent2":     Color(0.710, 0.537, 0.0),    # #B58900 yellow
		"text":        Color(0.396, 0.482, 0.514),  # #657B83 base00
		"bar_day":     Color(0.522, 0.600, 0.0),    # #859900 green
		"bar_night":   Color(0.424, 0.443, 0.769),  # #6C71C4 violet
		"panel_alpha": 0.97,
	})
