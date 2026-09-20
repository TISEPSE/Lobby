class_name UITheme
extends RefCounted

## Constantes visuelles partagées : aucune valeur magique ailleurs dans le code.
## Direction artistique : tableau de bord de console, tuiles carrées, fond = artwork
## du jeu sélectionné assombri, une seule couleur d'accent.

# --- Couleurs ---
const COLOR_BACKGROUND: Color = Color("08090b")
const COLOR_SURFACE: Color = Color("14171e")
const COLOR_ACCENT: Color = Color("22d366")
const COLOR_TEXT: Color = Color("ffffff")
const COLOR_TEXT_DIM: Color = Color("9aa3af")
## Étoile non obtenue : présente mais discrète, jamais noire sur fond sombre.
const COLOR_STAR_EMPTY: Color = Color(0.35, 0.38, 0.43, 1.0)
## Taille des étoiles de note sur la fiche d'un jeu.
const STAR_SIZE: float = 30.0
const COLOR_SHADOW: Color = Color(0.0, 0.0, 0.0, 0.0)
const COLOR_SIDEBAR: Color = Color("0d1117")
## Fond opaque des écrans de réglages : on n'est plus sur l'accueil, l'artwork
## n'a plus à transparaître derrière le texte.
const COLOR_PAGE: Color = Color("12161d")
const COLOR_PAGE_PANEL: Color = Color("171c25")
## Voile posé sur l'écran quand le panneau latéral est ouvert.
const SIDEBAR_SCRIM_ALPHA: float = 0.65
## Opacité du fond sur les écrans où c'est la grille qui porte le regard.
const BACKDROP_DIMMED_ALPHA: float = 0.16
## Force du voile posé sur un artwork : minimale sur une image sombre, maximale
## au-delà de cette clarté moyenne mesurée dans la moitié basse de l'image.
const SCRIM_MIN: float = 0.62
const SCRIM_MAX: float = 1.0
const SCRIM_LUMINANCE_RANGE: float = 0.55

# Pastilles de la barre d'aide, dans l'ordre A / B / X / Y.
const COLOR_BUTTON_A: Color = Color("6bb700")
const COLOR_BUTTON_B: Color = Color("e34b4b")
const COLOR_BUTTON_X: Color = Color("3a8cff")
const COLOR_BUTTON_Y: Color = Color("f2c14e")

# --- Mise en page ---
const REFERENCE_SIZE: Vector2i = Vector2i(1920, 1080)
const SAFE_AREA_RATIO: float = 0.05
const GRID_COLUMNS: int = 5
const TILE_SIZE: Vector2 = Vector2(300, 300)
const TILE_SEPARATION: Vector2 = Vector2(26, 26)
const TILE_FOCUS_SCALE: float = 1.10
const TILE_BORDER_WIDTH: int = 3
const TILE_CORNER_RADIUS: int = 14
const ROW_SEPARATION: int = 28
const FOCUS_GLOW_SIZE: int = 13
const SPACING_SMALL: int = 8
const SPACING_MEDIUM: int = 22
const SPACING_MEDIUM_LARGE: int = 32
const SPACING_LARGE: int = 44
const BADGE_SIZE: float = 40.0
## Pastille ronde contenant une icône de la barre du haut.
const ICON_BADGE_SIZE: float = 48.0
const ICON_GLYPH_SIZE: float = 26.0
const COLOR_ICON_BADGE: Color = Color(0.08, 0.10, 0.14, 0.78)
const Z_TILE_FOCUSED: int = 1

# --- Écran d'accueil (hub) ---
const CAROUSEL_TILE_SIZE: Vector2 = Vector2(189, 189)
const CAROUSEL_FOCUS_SCALE: float = 1.45
const CAROUSEL_SEPARATION: int = 24
## Air réservé au-dessus et au-dessous de la rangée pour le halo de la tuile sélectionnée.
const CAROUSEL_TOP_ROOM: float = 48.0
const CAROUSEL_BOTTOM_ROOM: float = 48.0
## Place minimale réservée de chaque côté pour la flèche de défilement. La
## gouttière réelle est plus large : le reste de la largeur y est réparti à
## parts égales, pour que les deux bords soient identiques.
const CAROUSEL_MIN_GUTTER: float = 52.0
## Opacité d'une tuile qui n'est pas entièrement visible : on ne montre jamais
## une jaquette coupée, une flèche signale qu'il reste des jeux de ce côté.
const CAROUSEL_CLIPPED_ALPHA: float = 0.0
const CAROUSEL_ARROW_SIZE: float = 34.0
const CAROUSEL_ARROW_ALPHA: float = 0.55
const SHORTCUT_SIZE: Vector2 = Vector2(404, 170)
const SHORTCUT_SEPARATION: int = 24

# --- Écran de réglages ---
## Colonne des catégories, à gauche.
const SETTINGS_CATEGORY_WIDTH: float = 420.0
const SETTINGS_CATEGORY_HEIGHT: float = 96.0
## Lignes d'options, à droite : hautes et larges, lisibles de loin.
const SETTINGS_ROW_HEIGHT: float = 96.0
## Carte de profil : grande photo ronde, pseudo lisible depuis le canapé.
const SETTINGS_AVATAR_SIZE: float = 200.0
const SETTINGS_PROFILE_CARD_WIDTH: float = 460.0
const SETTINGS_PROFILE_CARD_HEIGHT: float = 400.0
const SETTINGS_PROFILE_GAP: int = 40
## Grille de choix de la photo de profil (modale).
const AVATAR_CELL_SIZE: float = 168.0
const AVATAR_PICK_SIZE: float = 124.0
## Aperçu de la vidéo de démarrage : 16:9, comme ce qui sera affiché au boot.
const BOOT_PREVIEW_SIZE: Vector2 = Vector2(420, 236)
## Aperçu dans la fenêtre de choix de la vidéo : plus grand, c'est le sujet.
const BOOT_PICKER_PREVIEW_SIZE: Vector2 = Vector2(640, 360)
## Fenêtres modales (alimentation, choix d'avatar).
const MODAL_SHADOW_SIZE: int = 24
const MODAL_SHADOW_ALPHA: float = 0.6

# --- Typographie (minimum 28 px pour un affichage TV) ---
const FONT_SIZE_HERO: int = 64
## Titre d'une page de réglages : présent sans manger la place des options.
const FONT_SIZE_PAGE_TITLE: int = 52
const FONT_SIZE_TITLE: int = 40
const FONT_SIZE_BODY: int = 30
const FONT_SIZE_SMALL: int = 28
## Titre du carrousel : 20 px agrandis de 1,45 font 29 px à l'écran.
const FONT_SIZE_CAROUSEL_TITLE: int = 20

# --- Animations (courtes, 150 à 300 ms) ---
const ANIM_FAST: float = 0.15
const ANIM_NORMAL: float = 0.20
const ANIM_SLOW: float = 0.30
## Changement de sélection : une seule durée et une seule courbe pour tout ce qui
## bouge en même temps (taille de la tuile, halo, titre, défilement de la rangée).
const ANIM_SELECT: float = 0.30
## Le carrousel déplace beaucoup plus de matière que les raccourcis : il lui faut
## plus de temps et une courbe qui démarre en douceur au lieu de partir sec.
const ANIM_CAROUSEL: float = 0.32
const ANIM_BACKDROP: float = 0.45
## Passage d'un écran à l'autre : la jaquette sélectionnée rejoint sa place sur
## la fiche, puis les informations apparaissent.
const ANIM_TRANSITION: float = 0.34
const ANIM_SCREEN_FADE: float = 0.22
## Distance dont le titre monte en apparaissant.
const TITLE_RISE: float = 14.0

## Fond d'un élément interactif au repos.
static func surface_box(radius: int = TILE_CORNER_RADIUS) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = COLOR_SURFACE
	box.set_corner_radius_all(radius)
	return box

## Sélection : contour d'accent qui rayonne, jamais un aplat vert. Même langage
## pour les jaquettes, les icônes de la barre du haut et les boutons.
static func focus_box(radius: int = TILE_CORNER_RADIUS, filled: bool = true) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = COLOR_SURFACE if filled else Color.TRANSPARENT
	box.set_corner_radius_all(radius)
	box.set_border_width_all(TILE_BORDER_WIDTH)
	box.border_color = COLOR_ACCENT
	box.shadow_color = Color(COLOR_ACCENT.r, COLOR_ACCENT.g, COLOR_ACCENT.b, 0.26)
	box.shadow_size = FOCUS_GLOW_SIZE
	return box

## Marge de sécurité en pixels pour la résolution de référence.
static func safe_margin() -> Vector2:
	return Vector2(REFERENCE_SIZE) * SAFE_AREA_RATIO

## Couleur d'identité stable dérivée de l'identifiant d'un jeu.
## Teinte sombre et contrastée pour un rendu cinématique moderne.
static func color_for_id(id: String) -> Color:
	var hue: float = float(abs(id.hash()) % 360) / 360.0
	return Color.from_hsv(hue, 0.40, 0.28)

## Dégradé diagonal servant de jaquette provisoire.
static func cover_texture(id: String, size: Vector2) -> GradientTexture2D:
	var base: Color = color_for_id(id)
	var gradient := Gradient.new()
	gradient.set_color(0, base.lightened(0.18))
	gradient.set_color(1, Color("0a0c10"))
	gradient.add_point(0.40, base)
	return _gradient_texture(gradient, size, GradientTexture2D.FILL_LINEAR, Vector2(0.1, 0.0), Vector2(0.9, 1.0))

## Fond plein écran : dégradé vertical tenant lieu d'artwork du jeu sélectionné.
static func backdrop_texture(id: String, size: Vector2) -> GradientTexture2D:
	var base: Color = color_for_id(id)
	var gradient := Gradient.new()
	gradient.set_color(0, Color.from_hsv(base.h, base.s * 0.8, 0.30))
	gradient.set_color(1, COLOR_BACKGROUND)
	gradient.add_point(0.45, Color.from_hsv(base.h, base.s * 0.9, 0.16))
	gradient.add_point(0.75, Color.from_hsv(base.h, base.s * 0.6, 0.05))
	return _gradient_texture(gradient, size, GradientTexture2D.FILL_LINEAR, Vector2(0.5, 0.0), Vector2(0.5, 1.0))

## Lueur colorée derrière le sujet de l'artwork.
static func glow_texture(id: String, size: Vector2) -> GradientTexture2D:
	var base: Color = color_for_id(id)
	base = Color.from_hsv(base.h, base.s * 0.75, 0.85)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(base, 0.9))
	gradient.set_color(1, Color(base, 0.0))
	gradient.add_point(0.28, Color(base, 0.34))
	return _gradient_texture(gradient, size, GradientTexture2D.FILL_RADIAL, Vector2(0.4, 0.3), Vector2(1.0, 0.8))

## Seconde lueur, teinte voisine et décalée : donne de la profondeur au fond.
static func accent_glow_texture(id: String, size: Vector2) -> GradientTexture2D:
	var base: Color = color_for_id(id)
	base = Color.from_hsv(fmod(base.h + 0.14, 1.0), base.s * 0.85, 0.75)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(base, 0.55))
	gradient.set_color(1, Color(base, 0.0))
	gradient.add_point(0.32, Color(base, 0.18))
	return _gradient_texture(gradient, size, GradientTexture2D.FILL_RADIAL, Vector2(0.76, 0.52), Vector2(1.15, 0.95))

## Assombrissement des bords : concentre le regard au centre de l'artwork.
static func vignette_texture(size: Vector2) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0.0))
	gradient.set_color(1, Color(0, 0, 0, 0.88))
	gradient.add_point(0.45, Color(0, 0, 0, 0.04))
	return _gradient_texture(gradient, size, GradientTexture2D.FILL_RADIAL, Vector2(0.5, 0.4), Vector2(1.05, 0.95))

## Voile vertical posé sur le fond pour garantir la lisibilité du texte.
static func scrim_texture(size: Vector2) -> GradientTexture2D:
	var gradient := Gradient.new()
	# Le voile s'installe dès la moitié de l'écran : c'est là que commencent les
	# jaquettes et les libellés, qui doivent rester lisibles sur toute image.
	gradient.set_color(0, Color(0, 0, 0, 0.0))
	gradient.set_color(1, Color(0, 0, 0, 0.96))
	gradient.add_point(0.34, Color(0, 0, 0, 0.14))
	gradient.add_point(0.52, Color(0, 0, 0, 0.6))
	gradient.add_point(0.72, Color(0, 0, 0, 0.88))
	return _gradient_texture(gradient, size, GradientTexture2D.FILL_LINEAR, Vector2(0.0, 0.0), Vector2(0.0, 1.0))

## Voile posé au bas d'une jaquette pour que le titre reste lisible.
static func tile_shade_texture(size: Vector2) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0.0))
	gradient.set_color(1, Color(0, 0, 0, 0.88))
	return _gradient_texture(gradient, size, GradientTexture2D.FILL_LINEAR, Vector2(0.0, 0.0), Vector2(0.0, 1.0))

static func _gradient_texture(gradient: Gradient, size: Vector2, fill: int, from: Vector2, to: Vector2) -> GradientTexture2D:
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = maxi(int(size.x), 1)
	texture.height = maxi(int(size.y), 1)
	texture.fill = fill
	texture.fill_from = from
	texture.fill_to = to
	return texture
