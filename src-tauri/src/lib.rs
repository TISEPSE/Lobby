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
  if !refresh {
    if let Ok(text) = fs::read_to_string(&path) {
      if let Ok(cached) = serde_json::from_str::<GameDetails>(&text) {
        return Ok(cached);
      }
    }
  }

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
  };

  if let Ok(text) = serde_json::to_string_pretty(&details) {
    let _ = fs::write(&path, text);
  }
  Ok(details)
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

use scanner::ScannedGame;

#[derive(serde::Serialize, serde::Deserialize, Clone, Debug)]
pub struct UserSettings {
  pub profile_name: String,
  pub avatar_path: String,
  pub button_layout: String,
  pub game_folders: Vec<String>,
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
  })
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OnlineArtwork {
  pub cover: String,
  pub hero: String,
  pub logo: String,
  pub banner: String,
}

/// Récupère en ligne les jaquettes et illustrations officielles (Steam CDN ou Lutris/IGDB gratuit, 0 clé).
#[tauri::command]
async fn fetch_game_art(title: String, appid: Option<String>) -> Result<OnlineArtwork, String> {
  let client = reqwest::Client::builder()
    .user_agent("InterfaceConsole/0.1")
    .build()
    .map_err(|e| e.to_string())?;

  let cdn = "https://cdn.cloudflare.steamstatic.com/steam/apps";
  let mut target_appid = appid;

  if target_appid.is_none() {
    target_appid = scanner::match_steam_app(&client, &title).await;
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

  // Si pas de jaquette Steam trouvée, interroge Lutris / IGDB (100% gratuit, 0 clé)
  if cover.is_empty() {
    if let Some((lutris_cover, lutris_banner)) = scanner::fetch_lutris_art(&client, &title).await {
      cover = lutris_cover;
      if hero.is_empty() && !lutris_banner.is_empty() {
        hero = lutris_banner.clone();
      }
      if banner.is_empty() && !lutris_banner.is_empty() {
        banner = lutris_banner;
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

/// Ouvre une adresse avec l'application du système : c'est ainsi qu'on demande
/// à Steam d'installer, de vérifier ou de désinstaller un jeu (`steam://…`).
#[tauri::command]
fn open_url(url: String) -> Result<(), String> {
  // On n'ouvre que des liens Steam ou Epic : cette commande ne doit pas devenir un
  // moyen d'exécuter n'importe quoi depuis la page.
  if !url.starts_with("steam://") && !url.starts_with("com.epicgames.launcher://") {
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
      power_action,
      steam_details,
      open_url,
      scan_installed_games,
      save_library,
      load_library,
      save_user_settings,
      load_user_settings,
      fetch_game_art
    ])
    .setup(|app| {
      if cfg!(debug_assertions) {
        app.handle().plugin(
          tauri_plugin_log::Builder::default()
            .level(log::LevelFilter::Info)
            .build(),
        )?;
      }
      Ok(())
    })
    .run(tauri::generate_context!())
    .expect("error while running tauri application");
}
