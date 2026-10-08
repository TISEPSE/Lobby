use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use serde::{Deserialize, Serialize};
use tauri::Manager;

/// Fiche d'un jeu, telle que l'interface l'attend. Tout vient des points
/// d'entrée publics de Steam : pas de clé, pas de compte.
#[derive(serde::Serialize, serde::Deserialize, Clone, Debug)]
struct GameDetails {
  appid: String,
  title: String,
  /// Jaquette verticale quand elle existe, vide sinon : l'interface compose
  /// alors une tuile avec l'artwork et le logo.
  cover: String,
  hero: String,
  /// Logo détouré du jeu, sur fond transparent, quand Steam en fournit un.
  logo: String,
  /// Bannière horizontale, utilisée pour composer une jaquette à défaut.
  banner: String,
  genres: Vec<String>,
  release_date: String,
  summary: String,
  /// Note ramenée sur 5 ; 0 quand Metacritic ne connaît pas le jeu.
  rating: f32,
  /// Captures d'écran du magasin : vignette et pleine taille.
  #[serde(default)]
  screenshots: Vec<Screenshot>,
  /// Bandes-annonces. Steam ne fournit plus de fichier webm/mp4 pour les
  /// récentes, seulement des flux HLS — lus côté interface par hls.js.
  #[serde(default)]
  movies: Vec<Movie>,
  #[serde(default)]
  developers: Vec<String>,
  #[serde(default)]
  publishers: Vec<String>,
  /// Résumé long (section « À propos » du magasin), en texte.
  #[serde(default)]
  about: String,
  /// Version du contenu de la fiche : une fiche en cache plus ancienne que
  /// `DETAILS_VERSION` est redemandée, sinon elle n'aurait jamais de médias.
  #[serde(default)]
  version: u32,
}

/// À augmenter quand la fiche gagne des champs à récupérer chez Steam.
const DETAILS_VERSION: u32 = 1;

#[derive(serde::Serialize, serde::Deserialize, Clone, Debug)]
struct Screenshot {
  thumb: String,
  full: String,
}

#[derive(serde::Serialize, serde::Deserialize, Clone, Debug)]
struct Movie {
  name: String,
  thumb: String,
  /// Flux HLS (`.m3u8`), CORS ouvert chez Steam.
  hls: String,
}

/// Emplacement du cache : une fiche par jeu, relue avant toute requête.
fn cache_path(app: &tauri::AppHandle, appid: &str) -> Result<PathBuf, String> {
  let dir = app
    .path()
    .app_data_dir()
    .map_err(|error| format!("Dossier de données introuvable : {error}"))?
    .join("steam");
  fs::create_dir_all(&dir).map_err(|error| format!("Cache impossible à créer : {error}"))?;
  Ok(dir.join(format!("{appid}.json")))
}

/// Première adresse qui répond vraiment. Les jeux récents n'ont plus leurs
/// images à l'ancien emplacement du CDN : inutile de deviner, on vérifie.
async fn first_available(client: &reqwest::Client, urls: &[String]) -> String {
  for url in urls {
    if let Ok(response) = client.head(url).send().await {
      if response.status().is_success() {
        return url.clone();
      }
    }
  }
  String::new()
}

/// Fiche complète d'un jeu Steam. Le résultat est mis en cache sur le disque :
/// une fois récupérée, la fiche s'affiche même sans connexion.
#[tauri::command]
async fn steam_details(app: tauri::AppHandle, appid: String, refresh: bool) -> Result<GameDetails, String> {
  let path = cache_path(&app, &appid)?;
  let cached = fs::read_to_string(&path)
    .ok()
    .and_then(|text| serde_json::from_str::<GameDetails>(&text).ok());
  if !refresh {
    if let Some(cached) = &cached {
      if cached.version >= DETAILS_VERSION {
        return Ok(cached.clone());
      }
    }
  }
  // Fiche ancienne ou forcée : on la redemande, et on garde l'ancienne si
  // Steam ne répond pas — mieux vaut une fiche sans médias que pas de fiche.
  match fetch_steam_details(&appid).await {
    Ok(details) => {
      if let Ok(text) = serde_json::to_string_pretty(&details) {
        let _ = fs::write(&path, text);
      }
      Ok(details)
    }
    Err(error) => cached.ok_or(error),
  }
}

async fn fetch_steam_details(appid: &str) -> Result<GameDetails, String> {
  let appid = appid.to_string();

  let client = reqwest::Client::builder()
    .user_agent("InterfaceConsole/0.1")
    .build()
    .map_err(|error| error.to_string())?;

  let url = format!("https://store.steampowered.com/api/appdetails?appids={appid}&l=french");
  let body: serde_json::Value = client
    .get(&url)
    .send()
    .await
    .map_err(|error| format!("Steam injoignable : {error}"))?
    .json()
    .await
    .map_err(|error| format!("Réponse illisible : {error}"))?;

  let entry = body.get(&appid).ok_or("Jeu inconnu chez Steam")?;
  if !entry["success"].as_bool().unwrap_or(false) {
    return Err("Jeu inconnu chez Steam".into());
  }
  let data = &entry["data"];

  // La jaquette verticale n'existe pas pour tous les jeux : on garde la
  // première adresse qui répond, et l'image de la fiche Steam en dernier recours.
  let cdn = "https://cdn.cloudflare.steamstatic.com/steam/apps";
  // Jaquette verticale seulement : une bannière 16/9 étirée dans une tuile 2/3
  // est laide. Sans jaquette, l'interface compose la sienne.
  let cover_candidates = vec![
    format!("{cdn}/{appid}/library_600x900_2x.jpg"),
    format!("{cdn}/{appid}/library_600x900.jpg"),
  ];

  let mut banner_candidates = vec![];
  if let Some(header) = data["header_image"].as_str() {
    banner_candidates.push(header.to_string());
  }
  banner_candidates.push(format!("{cdn}/{appid}/header.jpg"));

  let mut hero_candidates = vec![format!("{cdn}/{appid}/library_hero.jpg")];
  if let Some(background) = data["background_raw"].as_str() {
    hero_candidates.push(background.to_string());
  }

  let logo_candidates = vec![
    format!("{cdn}/{appid}/logo.png"),
    format!("{cdn}/{appid}/logo_2x.png"),
  ];

  let mut resolved_cover = first_available(&client, &cover_candidates).await;
  let mut resolved_banner = first_available(&client, &banner_candidates).await;
  if resolved_cover.is_empty() {
    let game_name = data["name"].as_str().unwrap_or_default();
    if let Some((lutris_cover, lutris_banner)) = scanner::fetch_lutris_art(&client, game_name).await {
      resolved_cover = lutris_cover;
      if resolved_banner.is_empty() && !lutris_banner.is_empty() {
        resolved_banner = lutris_banner;
      }
    }
  }

  let details = GameDetails {
    appid: appid.clone(),
    title: data["name"].as_str().unwrap_or_default().to_string(),
    cover: resolved_cover,
    hero: first_available(&client, &hero_candidates).await,
    logo: first_available(&client, &logo_candidates).await,
    banner: resolved_banner,
    genres: data["genres"]
      .as_array()
      .map(|list| {
        list
          .iter()
          .filter_map(|genre| genre["description"].as_str().map(str::to_string))
          .collect()
      })
      .unwrap_or_default(),
    release_date: data["release_date"]["date"].as_str().unwrap_or_default().to_string(),
    summary: strip_html(data["short_description"].as_str().unwrap_or_default()),
    // Metacritic note sur 100, l'interface affiche sur 5.
    rating: data["metacritic"]["score"].as_f64().map(|score| (score as f32) / 20.0).unwrap_or(0.0),
    screenshots: data["screenshots"]
      .as_array()
      .map(|list| {
        list
          .iter()
          .filter_map(|shot| {
            Some(Screenshot {
              thumb: shot["path_thumbnail"].as_str()?.to_string(),
              full: shot["path_full"].as_str()?.to_string(),
            })
          })
          .collect()
      })
      .unwrap_or_default(),
    movies: data["movies"]
      .as_array()
      .map(|list| {
        list
          .iter()
          .filter_map(|movie| {
            Some(Movie {
              name: movie["name"].as_str().unwrap_or_default().to_string(),
              thumb: movie["thumbnail"].as_str().unwrap_or_default().to_string(),
              hls: movie["hls_h264"].as_str()?.to_string(),
            })
          })
          .collect()
      })
      .unwrap_or_default(),
    developers: string_list(&data["developers"]),
    publishers: string_list(&data["publishers"]),
    about: strip_html(data["about_the_game"].as_str().unwrap_or_default()),
    version: DETAILS_VERSION,
  };

  Ok(details)
}

fn string_list(value: &serde_json::Value) -> Vec<String> {
  value
    .as_array()
    .map(|list| list.iter().filter_map(|v| v.as_str().map(str::to_string)).collect())
    .unwrap_or_default()
}

/// Les résumés de Steam contiennent des balises ; l'interface affiche du texte.
fn strip_html(value: &str) -> String {
  let mut out = String::with_capacity(value.len());
  let mut inside = false;
  for character in value.replace("<br>", "
").chars() {
    match character {
      '<' => inside = true,
      '>' => inside = false,
      other if !inside => out.push(other),
      _ => {}
    }
  }
  out.replace("&quot;", "\"").replace("&amp;", "&").replace("&nbsp;", " ").trim().to_string()
}


mod scanner;
mod steam_account;
mod epic_account;
mod secure_store;
mod steam_library;

use scanner::ScannedGame;

#[derive(serde::Serialize, serde::Deserialize, Clone, Debug)]
pub struct UserSettings {
  pub profile_name: String,
  pub avatar_path: String,
  pub button_layout: String,
  pub game_folders: Vec<String>,
  /// Retours sonores de l'interface.
  #[serde(default = "default_true")]
  pub sound_enabled: bool,
  /// Clé SteamGridDB, saisie par l'utilisateur. Elle n'est **jamais** écrite
  /// dans le dépôt : elle ne vit que dans le fichier de réglages local.
  #[serde(default)]
  pub steamgriddb_key: String,
  /// Minutes d'inactivité avant l'écran de veille ; 0 pour ne jamais l'afficher.
  #[serde(default = "default_screensaver")]
  pub screensaver_minutes: u32,
  /// Ordre de la rangée d'accueil : `recent` (dernière partie) ou `title`.
  #[serde(default = "default_home_order")]
  pub home_order: String,
  /// Filtre et tri de la bibliothèque, retrouvés d'une session à l'autre.
  #[serde(default = "default_library_filter")]
  pub library_filter: String,
  #[serde(default = "default_library_sort")]
  pub library_sort: String,
  /// Volumes en pour cent : général, puis par famille de sons (déplacements
  /// et validations, notifications, lancement d'un jeu, vidéos).
  #[serde(default = "default_volume")]
  pub volume_master: u32,
  #[serde(default = "default_volume")]
  pub volume_menu: u32,
  #[serde(default = "default_volume")]
  pub volume_alerts: u32,
  #[serde(default = "default_volume")]
  pub volume_launch: u32,
  #[serde(default = "default_volume")]
  pub volume_video: u32,
}

fn default_volume() -> u32 {
  100
}

fn default_library_filter() -> String {
  "all".to_string()
}

fn default_library_sort() -> String {
  "title".to_string()
}

fn default_home_order() -> String {
  "recent".to_string()
}

fn default_screensaver() -> u32 {
  5
}

fn default_true() -> bool {
  true
}

fn library_path(app: &tauri::AppHandle) -> Result<PathBuf, String> {
  let dir = app
    .path()
    .app_data_dir()
    .map_err(|error| format!("Dossier de données introuvable : {error}"))?;
  fs::create_dir_all(&dir).map_err(|error| format!("Dossier de données impossible à créer : {error}"))?;
  Ok(dir.join("library.json"))
}

fn settings_path(app: &tauri::AppHandle) -> Result<PathBuf, String> {
  let dir = app
    .path()
    .app_data_dir()
    .map_err(|error| format!("Dossier de données introuvable : {error}"))?;
  fs::create_dir_all(&dir).map_err(|error| format!("Dossier de données impossible à créer : {error}"))?;
  Ok(dir.join("settings.json"))
}

/// Lance le scan des jeux installés sur toutes les sources disponibles.
#[tauri::command]
async fn scan_installed_games(custom_folders: Vec<String>) -> Vec<ScannedGame> {
  scanner::scan_all_games(&custom_folders).await
}

/// Sauvegarde la liste complète des jeux de la bibliothèque sur le disque.
#[tauri::command]
fn save_library(app: tauri::AppHandle, games: Vec<ScannedGame>) -> Result<(), String> {
  let path = library_path(&app)?;
  let text = serde_json::to_string_pretty(&games).map_err(|e| e.to_string())?;
  fs::write(path, text).map_err(|e| format!("Impossible d'écrire la bibliothèque : {e}"))
}

/// Nom de magasin admis : quelques lettres et tirets, jamais un chemin.
fn store_name_is_safe(name: &str) -> bool {
  !name.is_empty() && name.len() <= 32 && name.bytes().all(|b| b.is_ascii_lowercase() || b == b'-')
}

fn store_path(app: &tauri::AppHandle, name: &str) -> Result<PathBuf, String> {
  if !store_name_is_safe(name) {
    return Err(format!("Nom de magasin refusé : {name}"));
  }
  let dir = app
    .path()
    .app_data_dir()
    .map_err(|error| format!("Dossier de données introuvable : {error}"))?
    .join("store");
  fs::create_dir_all(&dir).map_err(|error| format!("Dossier de données impossible à créer : {error}"))?;
  Ok(dir.join(format!("{name}.json")))
}

/// Données de l'interface (statistiques, journal des parties, choix d'affiches)
/// gardées sur le disque : le stockage du webview dépend de l'origine de la
/// page, et l'exécutable compilé n'a pas la même que `tauri dev` — tout y
/// semblait perdu.
#[tauri::command]
fn save_store(app: tauri::AppHandle, name: String, data: String) -> Result<(), String> {
  let path = store_path(&app, &name)?;
  // Écriture dans un fichier voisin puis renommage : jamais de fichier à moitié écrit.
  let tmp = path.with_extension("json.tmp");
  fs::write(&tmp, data).map_err(|e| format!("Écriture impossible ({name}) : {e}"))?;
  fs::rename(&tmp, &path).map_err(|e| format!("Écriture impossible ({name}) : {e}"))
}

#[tauri::command]
fn load_store(app: tauri::AppHandle, name: String) -> Result<Option<String>, String> {
  let path = store_path(&app, &name)?;
  if !path.exists() {
    return Ok(None);
  }
  fs::read_to_string(path).map(Some).map_err(|e| format!("Lecture impossible ({name}) : {e}"))
}

#[cfg(test)]
mod store_tests {
  use super::store_name_is_safe;

  #[test]
  fn store_names_cannot_escape_the_folder() {
    assert!(store_name_is_safe("stats"));
    assert!(store_name_is_safe("art-styles"));
    assert!(!store_name_is_safe("../settings"));
    assert!(!store_name_is_safe("a/b"));
    assert!(!store_name_is_safe(""));
    assert!(!store_name_is_safe("Stats"));
  }
}

/// Charge la bibliothèque persistée sur le disque.
#[tauri::command]
fn load_library(app: tauri::AppHandle) -> Result<Vec<ScannedGame>, String> {
  let path = library_path(&app)?;
  if !path.exists() {
    return Ok(Vec::new());
  }
  let text = fs::read_to_string(path).map_err(|e| format!("Lecture impossible : {e}"))?;
  serde_json::from_str(&text).map_err(|e| format!("Bibliothèque corrompue : {e}"))
}

/// Sauvegarde les préférences utilisateur (pseudo, avatar, dossiers).
#[tauri::command]
fn save_user_settings(app: tauri::AppHandle, settings: UserSettings) -> Result<(), String> {
  let path = settings_path(&app)?;
  let text = serde_json::to_string_pretty(&settings).map_err(|e| e.to_string())?;
  fs::write(path, text).map_err(|e| format!("Impossible d'écrire les réglages : {e}"))
}

/// Charge les préférences utilisateur ou renvoie les valeurs par défaut.
#[tauri::command]
fn load_user_settings(app: tauri::AppHandle) -> Result<UserSettings, String> {
  let path = settings_path(&app)?;
  if path.exists() {
    if let Ok(text) = fs::read_to_string(&path) {
      if let Ok(loaded) = serde_json::from_str::<UserSettings>(&text) {
        return Ok(loaded);
      }
    }
  }

  let mut default_folders = Vec::new();
  #[cfg(windows)]
  {
    if std::path::Path::new("D:\\Jeux").exists() {
      default_folders.push("D:/Jeux".to_string());
    }
    if std::path::Path::new("C:\\Games").exists() {
      default_folders.push("C:/Games".to_string());
    }
  }

  Ok(UserSettings {
    profile_name: "Joueur".to_string(),
    avatar_path: "/assets/avatars/a11_face.svg".to_string(),
    button_layout: "ps5".to_string(),
    game_folders: default_folders,
    sound_enabled: true,
    steamgriddb_key: String::new(),
    screensaver_minutes: 5,
    home_order: default_home_order(),
    library_filter: default_library_filter(),
    library_sort: default_library_sort(),
    volume_master: default_volume(),
    volume_menu: default_volume(),
    volume_alerts: default_volume(),
    volume_launch: default_volume(),
    volume_video: default_volume(),
  })
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OnlineArtwork {
  pub cover: String,
  pub hero: String,
  pub logo: String,
  pub banner: String,
}

/// Une affiche proposée à l'utilisateur dans « Changer l'affiche ».
///
/// On garde l'adresse de la vignette à part : les jaquettes SteamGridDB font
/// 600x900 en plein format, et en afficher vingt d'un coup tirerait plusieurs
/// mégaoctets pour rien.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ArtCandidate {
  pub url: String,
  pub thumb: String,
  /// « Steam », « Lutris » ou « SteamGridDB » : l'utilisateur voit d'où ça vient.
  pub source: String,
  /// « cover » (2/3), « hero » (artwork large) ou « banner » (16/9).
  pub kind: String,
}

/// État d'un téléchargement ou d'une mise à jour en cours chez Steam.
#[derive(serde::Serialize, Clone, Debug)]
pub struct DownloadStatus {
  pub appid: String,
  pub title: String,
  /// « download », « stage » (installation des fichiers) ou « queued ».
  pub phase: String,
  pub bytes_done: u64,
  pub bytes_total: u64,
  /// Avancement de 0 à 100, déjà calculé pour l'interface.
  pub percent: f32,
}

/// Téléchargements en cours, lus dans les manifestes de Steam.
///
/// Steam n'expose pas d'API locale pour ça, mais il tient ses `appmanifest`
/// à jour en permanence : `StateFlags` dit ce qu'il fait, et les compteurs
/// d'octets donnent l'avancement réel. C'est la même source que celle qui sert
/// à lister les jeux installés.
/// Ouvre la page de connexion officielle d'Epic Games ; le résultat arrive
/// plus tard par l'événement `epic-login`.
/// **Asynchrone** : sous Windows, créer une fenêtre depuis une commande
/// synchrone (exécutée sur le fil principal) peut bloquer l'application.
#[tauri::command]
async fn epic_login(app: tauri::AppHandle) -> Result<(), String> {
  epic_account::open_login(&app)
}

/// Compte Epic connecté et temps de jeu par jeu ; `None` sans connexion.
#[tauri::command]
async fn epic_account(app: tauri::AppHandle) -> Result<Option<epic_account::EpicAccount>, String> {
  let data_dir = app.path().app_data_dir().map_err(|e| e.to_string())?;
  epic_account::read_account(&data_dir).await
}

#[tauri::command]
fn epic_logout(app: tauri::AppHandle) {
  if let Ok(data_dir) = app.path().app_data_dir() {
    epic_account::logout(&data_dir);
  }
}

/// Pour chaque chemin, dit s'il existe encore : la synchronisation retire les
/// jeux dont l'exécutable a disparu (dossier déplacé ou supprimé).
#[tauri::command]
fn paths_exist(paths: Vec<String>) -> Vec<bool> {
  paths.iter().map(|path| Path::new(path).exists()).collect()
}

/// Bascule entre le plein écran sans bordure (mode console) et une fenêtre
/// classique avec sa barre de titre — la porte de sortie pendant les tests.
/// Rend le nouvel état : `true` en plein écran.
#[tauri::command]
fn toggle_fullscreen(window: tauri::WebviewWindow) -> Result<bool, String> {
  let fullscreen = !window.is_fullscreen().map_err(|e| e.to_string())?;
  // Bordures d'abord : passer en plein écran avec elles laissait une bande de
  // barre de titre en haut de l'écran.
  window.set_decorations(!fullscreen).map_err(|e| e.to_string())?;
  window.set_fullscreen(fullscreen).map_err(|e| e.to_string())?;
  if !fullscreen {
    let _ = window.center();
  }
  Ok(fullscreen)
}

/// Écran de lancement : pendant qu'un jeu démarre, Lobby reste **au-dessus de
/// tout** (`on`) pour cacher le bureau, les fenêtres de lancement et les
/// écrans noirs ; il redescend (`off`) une fois le jeu au premier plan.
/// À l'allumage, on note les fenêtres déjà ouvertes : un navigateur agrandi
/// n'est pas le jeu qu'on attend.
#[tauri::command]
fn set_launch_cover(window: tauri::WebviewWindow, on: bool) -> Result<(), String> {
  #[cfg(windows)]
  if on {
    *LAUNCH_BASELINE.lock().unwrap() = big_windows().into_iter().map(|(hwnd, _, _)| hwnd).collect();
  }
  window.set_always_on_top(on).map_err(|e| e.to_string())
}

/// Donne le premier plan à une fenêtre de Lobby alors qu'un autre programme
/// (le jeu) l'a. Windows le refuse à une fenêtre en arrière-plan : on se
/// rattache un instant à la file d'entrée de la fenêtre au premier plan
/// (`AttachThreadInput`), ce qui l'autorise, et on passe un instant
/// « au-dessus de tout ».
fn force_foreground(window: &tauri::WebviewWindow, keep_on_top: bool) {
  let _ = window.unminimize();
  let _ = window.show();
  let _ = window.set_always_on_top(true);
  #[cfg(windows)]
  if let Ok(hwnd) = window.hwnd() {
    use windows_sys::Win32::System::Threading::{AttachThreadInput, GetCurrentThreadId};
    use windows_sys::Win32::UI::Input::KeyboardAndMouse::SetFocus;
    use windows_sys::Win32::UI::WindowsAndMessaging::{
      BringWindowToTop, GetForegroundWindow, GetWindowThreadProcessId, SetForegroundWindow,
    };
    use windows_sys::Win32::UI::Input::KeyboardAndMouse::{keybd_event, KEYEVENTF_KEYUP, VK_MENU};
    unsafe {
      let ours: windows_sys::Win32::Foundation::HWND = hwnd.0 as _;
      // Plusieurs tentatives : un jeu en plein écran garde parfois la main
      // au premier essai.
      for _ in 0..5 {
        let front = GetWindowThreadProcessId(GetForegroundWindow(), std::ptr::null_mut());
        let me = GetCurrentThreadId();
        let attached = front != 0 && front != me && AttachThreadInput(me, front, 1) != 0;
        // Un appui d'Alt simulé lève le verrou de premier plan de Windows :
        // c'est ce qui permet de prendre le focus à un jeu.
        keybd_event(VK_MENU as u8, 0, 0, 0);
        BringWindowToTop(ours);
        SetForegroundWindow(ours);
        SetFocus(ours);
        keybd_event(VK_MENU as u8, 0, KEYEVENTF_KEYUP, 0);
        if attached {
          AttachThreadInput(me, front, 0);
        }
        if GetForegroundWindow() == ours {
          break;
        }
        std::thread::sleep(std::time::Duration::from_millis(60));
      }
    }
  }
  let _ = window.set_focus();
  if !keep_on_top {
    let _ = window.set_always_on_top(false);
  }
}

/// Fin de partie, ou « Accueil » depuis le menu du jeu : Lobby revient au
/// premier plan.
#[tauri::command]
fn bring_to_front(window: tauri::WebviewWindow) {
  force_foreground(&window, false);
}

/// Fenêtre du menu du jeu : transparente, sans bordure, au-dessus de tout,
/// posée **sur la partie** — comme le guide Xbox, on ne quitte pas le jeu
/// pour l'ouvrir. Elle est créée une fois puis montrée / cachée.
const OVERLAY: &str = "overlay";

/// View + Menu maintenus en pleine partie : le menu du jeu `game_id` s'ouvre
/// par-dessus. Asynchrone : sous Windows, créer une fenêtre depuis une
/// commande synchrone (fil principal) peut bloquer l'application.
#[tauri::command]
async fn open_game_overlay(app: tauri::AppHandle, game_id: String) -> Result<(), String> {
  let overlay = match app.get_webview_window(OVERLAY) {
    Some(window) => {
      let _ = tauri::Emitter::emit_to(&app, OVERLAY, "overlay-open", &game_id);
      window
    }
    None => {
      let script = format!(
        "window.__LOBBY_OVERLAY__ = {};",
        serde_json::to_string(&game_id).map_err(|e| e.to_string())?
      );
      tauri::WebviewWindowBuilder::new(&app, OVERLAY, tauri::WebviewUrl::App("index.html".into()))
        .title("Lobby")
        .initialization_script(&script)
        .transparent(true)
        .decorations(false)
        .shadow(false)
        .resizable(false)
        .skip_taskbar(true)
        .always_on_top(true)
        .visible(false)
        .build()
        .map_err(|e| e.to_string())?
    }
  };
  // L'écran du jeu : celui de la fenêtre principale de Lobby.
  if let Some(monitor) = app
    .get_webview_window("main")
    .and_then(|main| main.current_monitor().ok().flatten())
  {
    let _ = overlay.set_position(*monitor.position());
    let _ = overlay.set_size(*monitor.size());
  }
  fit_to_screen(&overlay);
  let _ = overlay.set_cursor_visible(false);
  force_foreground(&overlay, true);
  Ok(())
}

/// Le menu du jeu se referme (il reste prêt pour la prochaine fois).
#[tauri::command]
fn close_game_overlay(app: tauri::AppHandle) {
  if let Some(window) = app.get_webview_window(OVERLAY) {
    let _ = window.hide();
  }
}

/// Processus dont une grande fenêtre n'est **pas** le jeu : le bureau, les
/// launchers eux-mêmes (la bibliothèque Steam peut s'ouvrir en grand).
#[cfg(windows)]
const NOT_A_GAME: [&str; 6] = [
  "explorer.exe",
  "steam.exe",
  "steamwebhelper.exe",
  "epicgameslauncher.exe",
  "epicwebhelper.exe",
  "msedgewebview2.exe",
];

/// Nom de l'exécutable d'un processus (`rocketleague.exe`), en minuscules.
#[cfg(windows)]
fn process_name(pid: u32) -> String {
  use windows_sys::Win32::Foundation::CloseHandle;
  use windows_sys::Win32::System::Threading::{
    OpenProcess, QueryFullProcessImageNameW, PROCESS_QUERY_LIMITED_INFORMATION,
  };
  unsafe {
    let handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid);
    if handle.is_null() {
      return String::new();
    }
    let mut buffer = [0u16; 1024];
    let mut len = buffer.len() as u32;
    let ok = QueryFullProcessImageNameW(handle, 0, buffer.as_mut_ptr(), &mut len);
    CloseHandle(handle);
    if ok == 0 {
      return String::new();
    }
    let path = String::from_utf16_lossy(&buffer[..len as usize]);
    path.rsplit(['\\', '/']).next().unwrap_or_default().to_lowercase()
  }
}

/// Fenêtres déjà ouvertes quand le lancement a commencé (`set_launch_cover`).
#[cfg(windows)]
static LAUNCH_BASELINE: std::sync::Mutex<Vec<isize>> = std::sync::Mutex::new(Vec::new());

/// Grandes fenêtres visibles d'autres programmes que Lobby et les launchers :
/// au moins 60 % de leur écran (les fenêtres de lancement — logo de
/// l'éditeur — sont bien plus petites), ni réduites ni masquées. Rend la
/// fenêtre, sa surface et son processus.
#[cfg(windows)]
fn big_windows() -> Vec<(isize, i64, u32)> {
  use windows_sys::Win32::Foundation::{BOOL, HWND, LPARAM, RECT};
  use windows_sys::Win32::Graphics::Dwm::{DwmGetWindowAttribute, DWMWA_CLOAKED};
  use windows_sys::Win32::Graphics::Gdi::{
    GetMonitorInfoW, MonitorFromWindow, MONITORINFO, MONITOR_DEFAULTTONEAREST,
  };
  use windows_sys::Win32::UI::WindowsAndMessaging::{
    EnumWindows, GetWindowRect, GetWindowThreadProcessId, IsIconic, IsWindowVisible,
  };

  unsafe extern "system" fn visit(hwnd: HWND, data: LPARAM) -> BOOL {
    let found = &mut *(data as *mut Vec<(isize, i64, u32)>);
    if IsWindowVisible(hwnd) == 0 || IsIconic(hwnd) != 0 {
      return 1;
    }
    // Fenêtre « masquée » par Windows (applications du Store en sommeil).
    let mut cloaked = 0u32;
    DwmGetWindowAttribute(
      hwnd,
      DWMWA_CLOAKED as u32,
      &mut cloaked as *mut u32 as *mut _,
      std::mem::size_of::<u32>() as u32,
    );
    if cloaked != 0 {
      return 1;
    }
    let mut pid = 0u32;
    GetWindowThreadProcessId(hwnd, &mut pid);
    if pid == std::process::id() || NOT_A_GAME.contains(&process_name(pid).as_str()) {
      return 1;
    }
    let mut rect: RECT = std::mem::zeroed();
    GetWindowRect(hwnd, &mut rect);
    let mut info: MONITORINFO = std::mem::zeroed();
    info.cbSize = std::mem::size_of::<MONITORINFO>() as u32;
    GetMonitorInfoW(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST), &mut info);
    let area = |r: &RECT| i64::from(r.right - r.left).max(0) * i64::from(r.bottom - r.top).max(0);
    let size = area(&rect);
    if size * 10 >= area(&info.rcMonitor) * 6 {
      found.push((hwnd as isize, size, pid));
    }
    1
  }

  let mut found: Vec<(isize, i64, u32)> = Vec::new();
  unsafe {
    EnumWindows(Some(visit), &mut found as *mut _ as LPARAM);
  }
  found
}

/// La fenêtre du jeu, sans y toucher : la plus grande fenêtre apparue depuis
/// le début du lancement, et son processus (0 : pas encore là). L'écran de
/// lancement attend qu'elle soit **stable** avant de lui donner le focus.
#[tauri::command]
fn find_game_window() -> u32 {
  #[cfg(windows)]
  {
    let baseline = LAUNCH_BASELINE.lock().unwrap().clone();
    big_windows()
      .into_iter()
      .filter(|(hwnd, _, _)| !baseline.contains(hwnd))
      .max_by_key(|(_, size, _)| *size)
      .map(|(_, _, pid)| pid)
      .unwrap_or(0)
  }
  #[cfg(not(windows))]
  {
    1
  }
}

/// Écran de lancement : la fenêtre du jeu est-elle là ? Une grande fenêtre
/// apparue depuis le début du lancement. Si oui, Lobby redescend et **donne
/// lui-même le focus au jeu** — Windows ne laisse pas une nouvelle fenêtre
/// prendre le premier plan à une fenêtre « au-dessus de tout » ; Lobby, qui a
/// le focus, a le droit de le céder. Rend le processus de cette fenêtre (c'est
/// lui que « Quitter le jeu » arrête), 0 tant qu'elle n'est pas là. Hors
/// Windows (Gamescope), on ne sait pas la désigner : 1, « prête » d'office.
#[tauri::command]
fn focus_game_window(window: tauri::WebviewWindow) -> u32 {
  #[cfg(windows)]
  {
    use windows_sys::Win32::UI::WindowsAndMessaging::{BringWindowToTop, SetForegroundWindow};
    let baseline = LAUNCH_BASELINE.lock().unwrap().clone();
    let game = big_windows()
      .into_iter()
      .filter(|(hwnd, _, _)| !baseline.contains(hwnd))
      .max_by_key(|(_, size, _)| *size);
    let Some((hwnd, _, pid)) = game else {
      return 0;
    };
    let _ = window.set_always_on_top(false);
    unsafe {
      BringWindowToTop(hwnd as _);
      SetForegroundWindow(hwnd as _);
    }
    pid
  }
  #[cfg(not(windows))]
  {
    let _ = window.set_always_on_top(false);
    1
  }
}

/// « Revenir au jeu » : Lobby rend le premier plan à la plus grande fenêtre
/// du jeu en cours (processus `pid`). Faux si elle n'existe plus.
#[tauri::command]
fn focus_process(pid: u32) -> bool {
  #[cfg(windows)]
  {
    use windows_sys::Win32::UI::WindowsAndMessaging::{BringWindowToTop, SetForegroundWindow};
    let Some((hwnd, _, _)) = big_windows()
      .into_iter()
      .filter(|(_, _, owner)| *owner == pid)
      .max_by_key(|(_, size, _)| *size)
    else {
      return false;
    };
    unsafe {
      BringWindowToTop(hwnd as _);
      SetForegroundWindow(hwnd as _);
    }
    true
  }
  #[cfg(not(windows))]
  {
    let _ = pid;
    false
  }
}

/// « Quitter le jeu », comme sur Xbox : le processus du jeu (et ses enfants)
/// est arrêté. Jamais Lobby lui-même.
#[tauri::command]
fn kill_process(pid: u32) -> Result<(), String> {
  if pid == 0 || pid == std::process::id() {
    return Err("aucun jeu à quitter".into());
  }
  #[cfg(windows)]
  let status = {
    use std::os::windows::process::CommandExt;
    // CREATE_NO_WINDOW : pas de console qui clignote par-dessus l'interface.
    Command::new("taskkill")
      .args(["/PID", &pid.to_string(), "/T", "/F"])
      .creation_flags(0x0800_0000)
      .status()
  };
  #[cfg(not(windows))]
  let status = Command::new("kill").args(["-TERM", &pid.to_string()]).status();
  match status {
    Ok(code) if code.success() => Ok(()),
    Ok(_) => Err("le jeu ne s'est pas arrêté".into()),
    Err(e) => Err(e.to_string()),
  }
}

/// Lobby est-il la fenêtre au premier plan ? La manette ne pilote l'interface
/// que dans ce cas : `document.hasFocus()` restait vrai pendant une partie.
/// Hors Windows (session Gamescope), on s'en remet au webview.
#[tauri::command]
fn lobby_in_front(window: tauri::WebviewWindow) -> bool {
  // Chaque fenêtre se demande si c'est **elle** qui est devant : quand le
  // menu du jeu a le focus, la fenêtre principale ne doit pas réagir.
  #[cfg(windows)]
  {
    use windows_sys::Win32::UI::WindowsAndMessaging::GetForegroundWindow;
    let Ok(hwnd) = window.hwnd() else {
      return true;
    };
    unsafe { GetForegroundWindow() as isize == hwnd.0 as isize }
  }
  #[cfg(not(windows))]
  {
    let _ = window;
    true
  }
}

/// Compte Steam connecté sur cette machine, ses jeux joués et sa photo.
/// `None` quand Steam n'est pas installé ou qu'aucun compte n'y est connecté.
#[tauri::command]
fn steam_account(app: tauri::AppHandle) -> Option<steam_account::SteamAccount> {
  let data_dir = app.path().app_data_dir().ok()?;
  steam_account::read_account(&data_dir)
}

#[tauri::command]
fn steam_downloads() -> Vec<DownloadStatus> {
  let mut running = Vec::new();
  let root = match scanner::steam_root() {
    Some(r) => r,
    None => return running,
  };

  for library in scanner::steam_libraries(&root) {
    let steamapps = library.join("steamapps");
    let entries = match fs::read_dir(&steamapps) {
      Ok(e) => e,
      Err(_) => continue,
    };

    for entry in entries.flatten() {
      let name = entry.file_name().to_string_lossy().to_string();
      if !name.starts_with("appmanifest_") || !name.ends_with(".acf") {
        continue;
      }
      let content = match fs::read_to_string(entry.path()) {
        Ok(c) => c,
        Err(_) => continue,
      };

      let value = |key: &str| -> String {
        content
          .lines()
          .find_map(|line| scanner::parse_vdf_value(line, key))
          .unwrap_or_default()
      };
      let number = |key: &str| -> u64 { value(key).parse().unwrap_or(0) };

      let flags: u64 = value("StateFlags").parse().unwrap_or(0);
      // 4 = installé et à jour : rien à signaler.
      if flags == 4 {
        continue;
      }

      let downloaded = number("BytesDownloaded");
      let to_download = number("BytesToDownload");
      let staged = number("BytesStaged");
      let to_stage = number("BytesToStage");

      // Tant que le téléchargement n'est pas fini, c'est lui qui compte ;
      // ensuite Steam installe les fichiers, et c'est cette étape qu'on montre.
      let (phase, done, total) = if to_download > 0 && downloaded < to_download {
        ("download", downloaded, to_download)
      } else if to_stage > 0 && staged < to_stage {
        ("stage", staged, to_stage)
      } else {
        ("queued", 0, 0)
      };

      let percent = if total > 0 {
        (done as f64 / total as f64 * 100.0) as f32
      } else {
        0.0
      };

      running.push(DownloadStatus {
        appid: value("appid"),
        title: value("name"),
        phase: phase.to_string(),
        bytes_done: done,
        bytes_total: total,
        percent,
      });
    }
  }

  running
}

/// Visuels trouvés chez SteamGridDB, la base communautaire de jaquettes.
///
/// C'est le dernier recours de la chaîne : les jeux qui n'existent ni chez
/// Steam ni chez Lutris (Valorant, Call of Duty, jeux hors catalogue) n'ont
/// que là de vraies jaquettes verticales. La clé appartient à l'utilisateur et
/// ne quitte pas sa machine.
async fn fetch_steamgriddb_art(
  client: &reqwest::Client,
  key: &str,
  title: &str,
) -> Option<(String, String, String)> {
  if key.is_empty() || title.is_empty() {
    return None;
  }

  let search = format!(
    "https://www.steamgriddb.com/api/v2/search/autocomplete/{}",
    scanner::urlencoding_simple(title)
  );
  let found: serde_json::Value = client
    .get(&search)
    .bearer_auth(key)
    .send()
    .await
    .ok()?
    .json()
    .await
    .ok()?;

  let game_id = found["data"].as_array()?.first()?["id"].as_i64()?;

  // Une image par usage : la jaquette verticale, l'artwork large, le logo.
  let grab = |kind: &str, query: &str| {
    let url = format!(
      "https://www.steamgriddb.com/api/v2/{kind}/game/{game_id}{query}"
    );
    let client = client.clone();
    let key = key.to_string();
    async move {
      let body: serde_json::Value = client
        .get(&url)
        .bearer_auth(&key)
        .send()
        .await
        .ok()?
        .json()
        .await
        .ok()?;
      body["data"].as_array()?.first()?["url"].as_str().map(str::to_string)
    }
  };

  let cover = grab("grids", "?dimensions=600x900").await.unwrap_or_default();
  let hero = grab("heroes", "").await.unwrap_or_default();
  let logo = grab("logos", "").await.unwrap_or_default();

  if cover.is_empty() && hero.is_empty() {
    return None;
  }
  Some((cover, hero, logo))
}

/// Dossier des visuels téléchargés, un fichier par jeu.
fn artwork_dir(app: &tauri::AppHandle) -> Result<PathBuf, String> {
  let dir = app
    .path()
    .app_data_dir()
    .map_err(|error| format!("Dossier de données introuvable : {error}"))?
    .join("artwork");
  fs::create_dir_all(&dir).map_err(|error| format!("Dossier des visuels impossible : {error}"))?;
  Ok(dir)
}

/// Télécharge une image **une seule fois** et rend son chemin local.
///
/// C'est ce qui fige l'association jeu ↔ jaquette : une fois le bon visuel
/// trouvé, il est posé sur le disque sous le nom du jeu. Plus de requête au
/// démarrage, plus de risque qu'une recherche renvoie autre chose demain, et
/// l'interface s'affiche hors ligne.
async fn download_once(
  client: &reqwest::Client,
  dir: &Path,
  game_id: &str,
  kind: &str,
  url: &str,
) -> String {
  if url.is_empty() {
    return String::new();
  }

  let safe_id = safe_game_id(game_id);
  // Un fichier déjà là — quel que soit son suffixe de version — est le bon :
  // c'est celui que l'utilisateur voit, et peut-être celui qu'il a choisi.
  if let Some(existing) = existing_art(dir, &safe_id, kind) {
    return existing;
  }

  let path = dir.join(format!("{safe_id}-{kind}.{}", extension_of(url)));
  download_to(client, url, &path).await
}

/// Nom de fichier sûr pour un identifiant de jeu.
fn safe_game_id(game_id: &str) -> String {
  game_id
    .chars()
    .map(|c| if c.is_ascii_alphanumeric() || c == '-' || c == '_' { c } else { '_' })
    .collect()
}

/// L'extension suit l'adresse : une jaquette Steam est en .jpg, un logo en .png.
fn extension_of(url: &str) -> String {
  url
    .split('?')
    .next()
    .and_then(|clean| clean.rsplit('.').next())
    .filter(|ext| ext.len() <= 4 && ext.chars().all(|c| c.is_ascii_alphanumeric()))
    .unwrap_or("jpg")
    .to_lowercase()
}

/// Les fichiers d'un jeu pour un type donné : `<id>-cover.jpg`, mais aussi
/// `<id>-cover-<horodatage>.png` quand l'utilisateur a choisi lui-même.
fn art_files(dir: &Path, safe_id: &str, kind: &str) -> Vec<PathBuf> {
  let exact = format!("{safe_id}-{kind}.");
  let versioned = format!("{safe_id}-{kind}-");
  let mut found = Vec::new();
  if let Ok(entries) = fs::read_dir(dir) {
    for entry in entries.flatten() {
      let name = entry.file_name().to_string_lossy().to_string();
      if name.starts_with(&exact) || name.starts_with(&versioned) {
        found.push(entry.path());
      }
    }
  }
  found
}

fn existing_art(dir: &Path, safe_id: &str, kind: &str) -> Option<String> {
  art_files(dir, safe_id, kind)
    .first()
    .map(|path| path.to_string_lossy().replace('\\', "/"))
}

/// Télécharge une image vers un chemin précis et rend ce chemin.
async fn download_to(client: &reqwest::Client, url: &str, path: &Path) -> String {
  let bytes = match client.get(url).send().await {
    Ok(response) if response.status().is_success() => match response.bytes().await {
      Ok(b) => b,
      Err(_) => return String::new(),
    },
    _ => return String::new(),
  };

  // Une réponse minuscule n'est pas une image : inutile de la garder.
  if bytes.len() < 1024 {
    return String::new();
  }
  if fs::write(path, &bytes).is_err() {
    return String::new();
  }
  path.to_string_lossy().replace('\\', "/")
}

/// Trouve les visuels d'un jeu **et les enregistre sur le disque**.
///
/// L'interface n'a plus qu'à afficher les fichiers locaux : l'association est
/// faite une fois pour toutes.
#[tauri::command]
async fn cache_game_art(
  app: tauri::AppHandle,
  game_id: String,
  title: String,
  appid: Option<String>,
  executable: Option<String>,
) -> Result<OnlineArtwork, String> {
  let dir = artwork_dir(&app)?;
  let found = fetch_game_art(app.clone(), title, appid, executable).await?;

  let client = reqwest::Client::builder()
    .user_agent("InterfaceConsole/0.1")
    .build()
    .map_err(|error| error.to_string())?;

  Ok(OnlineArtwork {
    cover: download_once(&client, &dir, &game_id, "cover", &found.cover).await,
    hero: download_once(&client, &dir, &game_id, "hero", &found.hero).await,
    logo: download_once(&client, &dir, &game_id, "logo", &found.logo).await,
    banner: download_once(&client, &dir, &game_id, "banner", &found.banner).await,
  })
}

/// Toutes les affiches possibles pour un jeu, pour que l'utilisateur choisisse
/// lui-même — l'automatique se trompe parfois de jeu, et lui seul sait laquelle
/// il veut voir dans sa bibliothèque.
#[tauri::command]
async fn art_candidates(
  app: tauri::AppHandle,
  title: String,
  appid: Option<String>,
  executable: Option<String>,
) -> Result<Vec<ArtCandidate>, String> {
  let exe = executable.unwrap_or_default();
  let steamgriddb_key = load_user_settings(app)
    .map(|settings| settings.steamgriddb_key)
    .unwrap_or_default();
  let client = reqwest::Client::builder()
    .user_agent("InterfaceConsole/0.1")
    .build()
    .map_err(|e| e.to_string())?;

  let mut out: Vec<ArtCandidate> = Vec::new();
  let cdn = "https://cdn.cloudflare.steamstatic.com/steam/apps";

  let mut target_appid = appid;
  if target_appid.is_none() {
    target_appid = scanner::match_steam_app_variants(&client, &title, &exe).await;
  }

  if let Some(ref id) = target_appid {
    for (url, kind) in [
      (format!("{cdn}/{id}/library_600x900_2x.jpg"), "cover"),
      (format!("{cdn}/{id}/library_600x900.jpg"), "cover"),
      (format!("{cdn}/{id}/library_hero.jpg"), "hero"),
      (format!("{cdn}/{id}/header.jpg"), "banner"),
      (format!("{cdn}/{id}/capsule_616x353.jpg"), "banner"),
    ] {
      if !first_available(&client, &[url.clone()]).await.is_empty() {
        out.push(ArtCandidate {
          thumb: url.clone(),
          url,
          source: "Steam".into(),
          kind: kind.into(),
        });
      }
    }

    // Les jeux récents n'ont plus rien à l'ancien emplacement du CDN : chaque
    // image vit sous `store_item_assets` avec **son propre identifiant**,
    // impossible à deviner. Seule la fiche du magasin les donne.
    out.extend(store_asset_candidates(&client, id).await);
  }

  if let Some((cover, banner)) = scanner::fetch_lutris_art_variants(&client, &title, &exe).await {
    if !cover.is_empty() {
      out.push(ArtCandidate {
        thumb: cover.clone(),
        url: cover,
        source: "Lutris".into(),
        kind: "cover".into(),
      });
    }
    if !banner.is_empty() {
      out.push(ArtCandidate {
        thumb: banner.clone(),
        url: banner,
        source: "Lutris".into(),
        kind: "banner".into(),
      });
    }
  }

  out.extend(steamgriddb_candidates(&client, &steamgriddb_key, &title).await);
  Ok(out)
}

/// Images données par la fiche du magasin : c'est la seule source pour les
/// jeux dont les visuels ne sont plus à l'ancien emplacement du CDN.
async fn store_asset_candidates(client: &reqwest::Client, appid: &str) -> Vec<ArtCandidate> {
  let url = format!("https://store.steampowered.com/api/appdetails?appids={appid}&l=french");
  let body: serde_json::Value = match client.get(&url).send().await {
    Ok(response) => match response.json().await {
      Ok(body) => body,
      Err(_) => return Vec::new(),
    },
    Err(_) => return Vec::new(),
  };

  let Some(data) = body.get(appid).map(|entry| &entry["data"]) else {
    return Vec::new();
  };

  let mut out = Vec::new();
  for (field, kind) in [
    ("header_image", "banner"),
    ("capsule_imagev5", "banner"),
    ("capsule_image", "banner"),
    ("background_raw", "hero"),
  ] {
    if let Some(image) = data[field].as_str() {
      if image.is_empty() {
        continue;
      }
      out.push(ArtCandidate {
        thumb: image.to_string(),
        url: image.to_string(),
        source: "Steam".into(),
        kind: kind.into(),
      });
    }
  }
  out
}

/// Les jaquettes communautaires : celles-ci sont nombreuses, d'où un choix à
/// faire par l'utilisateur plutôt qu'une première réponse prise au hasard.
///
/// SteamGridDB peut avoir **plusieurs fiches pour un même jeu** (deux entrées
/// « Rhythia », une jaquette chacune). On interroge donc toutes les fiches qui
/// portent exactement ce titre, pas seulement la première, sinon la moitié des
/// affiches reste invisible.
async fn steamgriddb_candidates(
  client: &reqwest::Client,
  key: &str,
  title: &str,
) -> Vec<ArtCandidate> {
  if key.is_empty() || title.is_empty() {
    return Vec::new();
  }

  let search = format!(
    "https://www.steamgriddb.com/api/v2/search/autocomplete/{}",
    scanner::urlencoding_simple(title)
  );
  let found: serde_json::Value = match client.get(&search).bearer_auth(key).send().await {
    Ok(response) => match response.json().await {
      Ok(body) => body,
      Err(_) => return Vec::new(),
    },
    Err(_) => return Vec::new(),
  };

  let Some(results) = found["data"].as_array() else {
    return Vec::new();
  };

  // Seules les fiches qui portent vraiment ce titre. Prendre le premier
  // résultat à défaut proposait les jaquettes d'un autre jeu — « Ballgame
  // Demo » se voyait offrir celles de « Bunnies & Ballgames! ». Mieux vaut
  // aucune affiche qu'une affiche qui n'a rien à voir.
  let game_ids: Vec<i64> = results
    .iter()
    .filter(|entry| {
      entry["name"]
        .as_str()
        .map(|name| scanner::titles_match(name, title))
        .unwrap_or(false)
    })
    .filter_map(|entry| entry["id"].as_i64())
    .take(3)
    .collect();

  let mut out: Vec<ArtCandidate> = Vec::new();
  let mut seen: Vec<String> = Vec::new();

  for game_id in game_ids {
    for (kind, endpoint, query) in [
      ("cover", "grids", "?dimensions=600x900"),
      ("hero", "heroes", ""),
    ] {
      let url = format!("https://www.steamgriddb.com/api/v2/{endpoint}/game/{game_id}{query}");
      let body: serde_json::Value = match client.get(&url).bearer_auth(key).send().await {
        Ok(response) => match response.json().await {
          Ok(body) => body,
          Err(_) => continue,
        },
        Err(_) => continue,
      };
      let Some(items) = body["data"].as_array() else {
        continue;
      };
      for item in items {
        let Some(full) = item["url"].as_str() else {
          continue;
        };
        // Une même image peut revenir d'une fiche à l'autre.
        if seen.iter().any(|known| known == full) {
          continue;
        }
        seen.push(full.to_string());
        out.push(ArtCandidate {
          // `thumb` est la miniature fournie par l'API : c'est elle qu'on affiche
          // dans la grille, l'image pleine taille n'est tirée qu'au choix.
          thumb: item["thumb"].as_str().unwrap_or(full).to_string(),
          url: full.to_string(),
          source: "SteamGridDB".into(),
          kind: kind.into(),
        });
      }
    }
  }

  // L'API ignore toute limite demandée : certains jeux ont cinquante grids, et
  // la fenêtre de choix n'a pas vocation à tous les montrer.
  out.truncate(24);
  out
}

/// Vérifie qu'une clé SteamGridDB fonctionne vraiment, au moment où
/// l'utilisateur la saisit : une clé mal copiée resterait sinon silencieuse
/// jusqu'au prochain jeu sans jaquette.
///
/// Rend « ok », « unauthorized » ou « offline » — la clé n'est ni écrite ni
/// renvoyée, seulement essayée.
#[tauri::command]
async fn test_steamgriddb_key(key: String) -> Result<String, String> {
  if key.trim().is_empty() {
    return Ok("empty".into());
  }

  let client = reqwest::Client::builder()
    .user_agent("InterfaceConsole/0.1")
    .build()
    .map_err(|error| error.to_string())?;

  let response = client
    .get("https://www.steamgriddb.com/api/v2/search/autocomplete/hades")
    .bearer_auth(key.trim())
    .send()
    .await;

  match response {
    Ok(response) if response.status().is_success() => Ok("ok".into()),
    Ok(response) if response.status().as_u16() == 401 || response.status().as_u16() == 403 => {
      Ok("unauthorized".into())
    }
    Ok(response) => Ok(format!("http {}", response.status().as_u16())),
    Err(_) => Ok("offline".into()),
  }
}

/// Ouvre la connexion à Steam (page officielle, navigation privée) ; la
/// bibliothèque arrive ensuite par l'événement `steam-library`.
/// **Asynchrone** : sous Windows, créer une fenêtre depuis une commande
/// synchrone peut bloquer l'application.
#[tauri::command]
async fn steam_library_login(app: tauri::AppHandle) -> Result<(), String> {
  steam_library::open_login(&app)
}

/// Bibliothèque Steam récupérée à la dernière connexion (déchiffrée).
#[tauri::command]
fn steam_library(app: tauri::AppHandle) -> Result<Option<steam_library::OwnedLibrary>, String> {
  let data_dir = app.path().app_data_dir().map_err(|e| e.to_string())?;
  steam_library::read_library(&data_dir)
}

#[tauri::command]
fn steam_library_forget(app: tauri::AppHandle) {
  if let Ok(data_dir) = app.path().app_data_dir() {
    steam_library::forget_library(&data_dir);
  }
}

/// Enregistre l'affiche choisie par l'utilisateur, en remplaçant celle qui
/// était déjà sur le disque pour ce jeu.
#[tauri::command]
async fn pick_game_art(
  app: tauri::AppHandle,
  game_id: String,
  url: String,
  kind: String,
) -> Result<String, String> {
  let dir = artwork_dir(&app)?;
  let client = reqwest::Client::builder()
    .user_agent("InterfaceConsole/0.1")
    .build()
    .map_err(|error| error.to_string())?;

  let safe_id = safe_game_id(&game_id);

  // Le fichier retenu porte un horodatage : son **adresse change**, donc le
  // webview affiche la nouvelle image au lieu de resservir l'ancienne depuis
  // son cache. Un paramètre d'URL ne suffisait pas — le protocole d'accès aux
  // fichiers le prend pour une partie du chemin.
  let stamp = std::time::SystemTime::now()
    .duration_since(std::time::UNIX_EPOCH)
    .map(|d| d.as_secs())
    .unwrap_or(0);
  let path = dir.join(format!("{safe_id}-{kind}-{stamp}.{}", extension_of(&url)));

  let local = download_to(&client, &url, &path).await;
  if local.is_empty() {
    return Err("Cette image n'a pas pu être téléchargée.".into());
  }

  // Les anciens fichiers de ce type partent seulement une fois la nouvelle
  // image écrite : en cas d'échec, le jeu garde son affiche.
  for old in art_files(&dir, &safe_id, &kind) {
    if old != path {
      let _ = fs::remove_file(old);
    }
  }

  Ok(local)
}

/// Récupère en ligne les jaquettes et illustrations officielles (Steam CDN ou Lutris/IGDB gratuit, 0 clé).
#[tauri::command]
async fn fetch_game_art(
  app: tauri::AppHandle,
  title: String,
  appid: Option<String>,
  executable: Option<String>,
) -> Result<OnlineArtwork, String> {
  let exe = executable.unwrap_or_default();
  // La clé vient des réglages de l'utilisateur, jamais du code.
  let steamgriddb_key = load_user_settings(app)
    .map(|settings| settings.steamgriddb_key)
    .unwrap_or_default();
  let client = reqwest::Client::builder()
    .user_agent("InterfaceConsole/0.1")
    .build()
    .map_err(|e| e.to_string())?;

  let cdn = "https://cdn.cloudflare.steamstatic.com/steam/apps";
  let mut target_appid = appid;

  if target_appid.is_none() {
    target_appid = scanner::match_steam_app_variants(&client, &title, &exe).await;
  }

  let mut cover = String::new();
  let mut hero = String::new();
  let mut logo = String::new();
  let mut banner = String::new();

  if let Some(ref id) = target_appid {
    let cover_candidates = vec![
      format!("{cdn}/{id}/library_600x900_2x.jpg"),
      format!("{cdn}/{id}/library_600x900.jpg"),
    ];
    let banner_candidates = vec![
      format!("{cdn}/{id}/header.jpg"),
    ];
    let hero_candidates = vec![
      format!("{cdn}/{id}/library_hero.jpg"),
    ];
    let logo_candidates = vec![
      format!("{cdn}/{id}/logo.png"),
    ];

    cover = first_available(&client, &cover_candidates).await;
    banner = first_available(&client, &banner_candidates).await;
    hero = first_available(&client, &hero_candidates).await;
    logo = first_available(&client, &logo_candidates).await;
  }

  // Si pas de jaquette Steam trouvée, interroge Lutris (gratuit, sans clé)
  if cover.is_empty() {
    if let Some((lutris_cover, lutris_banner)) = scanner::fetch_lutris_art_variants(&client, &title, &exe).await {
      cover = lutris_cover;
      if hero.is_empty() && !lutris_banner.is_empty() {
        hero = lutris_banner.clone();
      }
      if banner.is_empty() && !lutris_banner.is_empty() {
        banner = lutris_banner;
      }
    }
  }

  // Dernier recours : SteamGridDB, si l'utilisateur a renseigné sa clé. C'est
  // la seule source à avoir de vraies jaquettes verticales pour les jeux hors
  // catalogue Steam.
  if cover.is_empty() {
    if let Some((grid_cover, grid_hero, grid_logo)) =
      fetch_steamgriddb_art(&client, &steamgriddb_key, &title).await
    {
      cover = grid_cover;
      if hero.is_empty() {
        hero = grid_hero;
      }
      if logo.is_empty() {
        logo = grid_logo;
      }
    }
  }

  Ok(OnlineArtwork {
    cover,
    hero,
    logo,
    banner,
  })
}

/// Lance un jeu et rend la main tout de suite : l'interface reste vivante et
/// suit le processus. Renvoie le PID pour pouvoir surveiller la fin de partie.
#[tauri::command]
fn launch_game(program: String, args: Vec<String>) -> Result<u32, String> {
  if program.starts_with("com.epicgames.launcher://") || program.starts_with("steam://") {
    #[cfg(windows)]
    let res = Command::new("cmd").args(["/C", "start", "", &program]).spawn();
    #[cfg(not(windows))]
    let res = Command::new("xdg-open").arg(&program).spawn();

    return res.map(|child| child.id()).map_err(|e| format!("Lancement impossible ({program}) : {e}"));
  }

  let mut cmd = Command::new(&program);
  cmd.args(&args);

  // Positionne le dossier de travail dans le répertoire de l'exécutable pour que
  // le jeu trouve ses dépendances et fichiers de configuration.
  let p = Path::new(&program);
  if let Some(parent) = p.parent() {
    if parent.is_dir() {
      cmd.current_dir(parent);
    }
  }

  cmd
    .spawn()
    .map(|child| child.id())
    .map_err(|error| format!("Lancement impossible ({program}) : {error}"))
}

/// Vrai tant que le jeu tourne : c'est ce qui permet de remettre l'interface au
/// premier plan quand la partie se termine.
#[tauri::command]
fn is_running(pid: u32) -> bool {
  #[cfg(windows)]
  {
    Command::new("tasklist")
      .args(["/FI", &format!("PID eq {pid}"), "/NH"])
      .output()
      .map(|out| String::from_utf8_lossy(&out.stdout).contains(&pid.to_string()))
      .unwrap_or(false)
  }
  #[cfg(not(windows))]
  {
    std::path::Path::new(&format!("/proc/{pid}")).exists()
  }
}

/// Une entrée de l'explorateur de fichiers (choix de l'exécutable d'un jeu).
#[derive(Serialize)]
struct FileEntry {
  name: String,
  path: String,
  /// Dossier, disque, ou exécutable.
  kind: &'static str,
  /// Taille en octets (exécutables seulement).
  size: u64,
}

/// Le contenu d'un dossier, tel que l'explorateur le montre.
#[derive(Serialize)]
struct FolderListing {
  path: String,
  /// Dossier parent ; vide à la racine d'un disque (on remonte alors aux disques).
  parent: String,
  entries: Vec<FileEntry>,
}

/// Un fichier qu'on peut lancer comme un jeu.
fn is_launchable(path: &Path) -> bool {
  let ext = path.extension().and_then(|e| e.to_str()).unwrap_or("").to_ascii_lowercase();
  #[cfg(windows)]
  {
    matches!(ext.as_str(), "exe" | "bat" | "cmd")
  }
  #[cfg(not(windows))]
  {
    use std::os::unix::fs::PermissionsExt;
    matches!(ext.as_str(), "sh" | "appimage" | "x86_64" | "exe")
      || path.metadata().map(|m| m.is_file() && m.permissions().mode() & 0o111 != 0).unwrap_or(false)
  }
}

/// Les points de départ de l'explorateur : les disques (Windows), ou la racine
/// et le dossier personnel (Linux).
#[tauri::command]
fn list_roots() -> Vec<FileEntry> {
  #[cfg(windows)]
  {
    (b'A'..=b'Z')
      .map(|letter| format!("{}:\\", letter as char))
      .filter(|root| Path::new(root).exists())
      .map(|root| FileEntry { name: root.trim_end_matches('\\').to_string(), path: root, kind: "drive", size: 0 })
      .collect()
  }
  #[cfg(not(windows))]
  {
    let mut roots = vec![FileEntry { name: "/".into(), path: "/".into(), kind: "drive", size: 0 }];
    if let Some(home) = std::env::var_os("HOME") {
      let home = home.to_string_lossy().to_string();
      roots.push(FileEntry { name: "Dossier personnel".into(), path: home, kind: "drive", size: 0 });
    }
    roots
  }
}

/// Le contenu d'un dossier : ses sous-dossiers puis ses exécutables, chacun par
/// ordre alphabétique. Les fichiers cachés ou système et le reste sont omis :
/// on cherche un exécutable, pas à tout parcourir.
#[tauri::command]
fn list_dir(path: String) -> Result<FolderListing, String> {
  let dir = Path::new(&path);
  let read = fs::read_dir(dir).map_err(|e| format!("Dossier illisible : {e}"))?;
  let mut folders = Vec::new();
  let mut files = Vec::new();
  for entry in read.flatten() {
    let name = entry.file_name().to_string_lossy().to_string();
    if name.starts_with('.') || name.starts_with('$') {
      continue;
    }
    let full = entry.path();
    let Ok(meta) = entry.metadata() else { continue };
    #[cfg(windows)]
    {
      use std::os::windows::fs::MetadataExt;
      // Fichiers cachés ou système (2 | 4) : jamais ceux d'un jeu.
      if meta.file_attributes() & 0x6 != 0 {
        continue;
      }
    }
    if meta.is_dir() {
      folders.push(FileEntry { name, path: full.to_string_lossy().to_string(), kind: "folder", size: 0 });
    } else if is_launchable(&full) {
      files.push(FileEntry { name, path: full.to_string_lossy().to_string(), kind: "exe", size: meta.len() });
    }
  }
  let by_name = |a: &FileEntry, b: &FileEntry| a.name.to_lowercase().cmp(&b.name.to_lowercase());
  folders.sort_by(by_name);
  files.sort_by(by_name);
  folders.extend(files);
  folders.truncate(2000);
  let parent = dir.parent().map(|p| p.to_string_lossy().to_string()).unwrap_or_default();
  Ok(FolderListing { path, parent, entries: folders })
}

/// Taille pour laquelle l'interface est dessinée (une TV 1080p).
const DESIGN_WIDTH: f64 = 1920.0;
const DESIGN_HEIGHT: f64 = 1080.0;

/// Met toute l'interface à l'échelle de la fenêtre, d'un bloc : zoom du
/// webview = min(largeur / 1920, hauteur / 1080), en pixels logiques. Sur un
/// portable, « Rechercher parmi N jeux » passait à la ligne ; sur une TV 4K,
/// tout était minuscule. C'est le zoom du navigateur, pas `zoom` en CSS : la
/// page voit alors 1920 × 1080 pixels CSS, et `vw` / `vh` restent justes.
fn fit_to_screen(window: &tauri::WebviewWindow) {
  let (Ok(size), Ok(scale)) = (window.inner_size(), window.scale_factor()) else {
    return;
  };
  if size.width == 0 || size.height == 0 {
    return;
  }
  let width = size.width as f64 / scale;
  let height = size.height as f64 / scale;
  let zoom = (width / DESIGN_WIDTH).min(height / DESIGN_HEIGHT);
  if let Err(error) = window.set_zoom(zoom) {
    log::warn!("Mise à l'échelle impossible : {error}");
  }
}

/// Jeu Steam en cours (appid), 0 sinon. `steam -applaunch` rend la main
/// aussitôt : c'est Steam lui-même qui dit quand la partie commence et finit,
/// dans le registre sous Windows (`RunningAppID`), dans `~/.steam/registry.vdf`
/// ailleurs.
#[tauri::command]
fn steam_running_app() -> u32 {
  #[cfg(windows)]
  {
    use winreg::enums::HKEY_CURRENT_USER;
    winreg::RegKey::predef(HKEY_CURRENT_USER)
      .open_subkey(r"Software\Valve\Steam")
      .and_then(|key| key.get_value::<u32, _>("RunningAppID"))
      .unwrap_or(0)
  }
  #[cfg(not(windows))]
  {
    let Some(home) = std::env::var_os("HOME") else { return 0 };
    let path = Path::new(&home).join(".steam/registry.vdf");
    std::fs::read_to_string(path)
      .ok()
      .and_then(|text| running_app_in_vdf(&text))
      .unwrap_or(0)
  }
}

/// `"RunningAppID"		"1145360"` dans `registry.vdf` (Linux).
#[cfg_attr(windows, allow(dead_code))]
fn running_app_in_vdf(text: &str) -> Option<u32> {
  let at = text.find("\"RunningAppID\"")? + "\"RunningAppID\"".len();
  let rest = &text[at..];
  let start = rest.find('"')? + 1;
  let end = start + rest[start..].find('"')?;
  rest[start..end].trim().parse().ok()
}

#[cfg(test)]
mod running_app_tests {
  use super::running_app_in_vdf;

  #[test]
  fn reads_running_app_from_registry_vdf() {
    let text = "\"Steam\"\n{\n\t\t\"RunningAppID\"\t\t\"1145360\"\n}";
    assert_eq!(running_app_in_vdf(text), Some(1145360));
    assert_eq!(running_app_in_vdf("\"RunningAppID\"\t\"0\""), Some(0));
    assert_eq!(running_app_in_vdf("rien"), None);
  }
}

/// Ouvre une adresse avec l'application du système : c'est ainsi qu'on demande
/// à Steam d'installer, de vérifier ou de désinstaller un jeu (`steam://…`).
/// Caractères admis dans une adresse `steam://` ou `com.epicgames.launcher://`.
fn url_is_safe(url: &str) -> bool {
  url.bytes().all(|b| b.is_ascii_alphanumeric() || b":/?=._-".contains(&b))
}

#[cfg(test)]
mod open_url_tests {
  use super::url_is_safe;

  #[test]
  fn rejects_shell_metacharacters() {
    assert!(url_is_safe("steam://install/311210"));
    assert!(url_is_safe("com.epicgames.launcher://apps/Fortnite?action=install"));
    assert!(!url_is_safe("steam://install/1&calc"));
    assert!(!url_is_safe("steam://x|whoami"));
    assert!(!url_is_safe("steam://x^&y"));
    assert!(!url_is_safe("steam://%COMSPEC%"));
    assert!(!url_is_safe("steam://a b"));
  }
}

#[tauri::command]
fn open_url(url: String) -> Result<(), String> {
  // On n'ouvre que des liens Steam ou Epic : cette commande ne doit pas devenir un
  // moyen d'exécuter n'importe quoi depuis la page.
  if !url.starts_with("steam://") && !url.starts_with("com.epicgames.launcher://") {
    return Err("Adresse refusée".into());
  }
  // Sous Windows, l'adresse passe par `cmd /C start`, qui interprète `&`, `|`,
  // `^`, `%`… : `steam://x&calc` lançait une autre commande. Seuls les
  // caractères d'une adresse de launcher sont admis.
  if !url_is_safe(&url) {
    return Err("Adresse refusée".into());
  }

  #[cfg(windows)]
  let result = Command::new("cmd").args(["/C", "start", "", &url]).spawn();
  #[cfg(not(windows))]
  let result = Command::new("xdg-open").arg(&url).spawn();

  result
    .map(|_| ())
    .map_err(|error| format!("Ouverture impossible : {error}"))
}

/// Éteint, redémarre ou quitte. Rien n'est fait sans que l'interface ait
/// demandé confirmation : cette commande ne pose pas de question, elle exécute.
#[tauri::command]
fn power_action(app: tauri::AppHandle, action: String) -> Result<(), String> {
  match action.as_str() {
    "quit" => {
      app.exit(0);
      Ok(())
    }
    "shutdown" | "reboot" => {
      #[cfg(windows)]
      let mut command = {
        let mut c = Command::new("shutdown");
        c.args([if action == "reboot" { "/r" } else { "/s" }, "/t", "0"]);
        c
      };
      #[cfg(not(windows))]
      let mut command = {
        let mut c = Command::new("systemctl");
        c.arg(if action == "reboot" { "reboot" } else { "poweroff" });
        c
      };
      command
        .spawn()
        .map(|_| ())
        .map_err(|error| format!("Commande refusée : {error}"))
    }
    other => Err(format!("Action inconnue : {other}")),
  }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
  tauri::Builder::default()
    .invoke_handler(tauri::generate_handler![
      launch_game,
      is_running,
      steam_running_app,
      set_launch_cover,
      bring_to_front,
      focus_game_window,
      find_game_window,
      focus_process,
      kill_process,
      lobby_in_front,
      open_game_overlay,
      close_game_overlay,
      list_roots,
      list_dir,
      power_action,
      steam_details,
      cache_game_art,
      art_candidates,
      test_steamgriddb_key,
      pick_game_art,
      steam_downloads,
      steam_account,
      toggle_fullscreen,
      paths_exist,
      steam_library_login,
      steam_library,
      steam_library_forget,
      epic_login,
      epic_account,
      epic_logout,
      open_url,
      scan_installed_games,
      save_library,
      save_store,
      load_store,
      load_library,
      save_user_settings,
      load_user_settings,
      fetch_game_art
    ])
    .setup(|app| {
      // Une console ne montre pas de pointeur : le curseur système disparaît
      // dès qu'il passe sur la fenêtre, quel que soit l'élément survolé.
      if let Some(window) = app.get_webview_window("main") {
        let _ = window.set_cursor_visible(false);
        // L'interface est dessinée pour du 1920 × 1080 : on la met à l'échelle
        // de l'écran, au démarrage puis à chaque changement de taille.
        fit_to_screen(&window);
        let fitted = window.clone();
        window.on_window_event(move |event| {
          if matches!(event, tauri::WindowEvent::Resized(_) | tauri::WindowEvent::ScaleFactorChanged { .. }) {
            fit_to_screen(&fitted);
          }
        });
      }
      // Journal aussi dans l'application installée : c'est là qu'on en a
      // besoin pour comprendre un souci de connexion sur un autre PC.
      app.handle().plugin(
        tauri_plugin_log::Builder::default()
          .level(log::LevelFilter::Info)
          .build(),
      )?;
      Ok(())
    })
    .run(tauri::generate_context!())
    .expect("error while running tauri application");
}
