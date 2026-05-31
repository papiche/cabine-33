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
	var t = current()
	var s = StyleBoxFlat.new()
	s.bg_color = t["accent2"] if use_accent2 else t["accent"]
	s.set_corner_radius_all(10)
	return s

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
	return text_color().lerp(accent_color(), 0.4)

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
