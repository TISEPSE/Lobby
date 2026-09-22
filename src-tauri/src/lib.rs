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
  /// Vidéo jouée au lancement, parmi celles livrées dans `assets/boot`.
  /// Vide : on va droit à l'accueil.
  #[serde(default)]
  pub boot_video: String,
  /// Permet de garder la vidéo choisie tout en la désactivant.
  #[serde(default = "default_true")]
  pub boot_video_enabled: bool,
  /// Retours sonores de l'interface.
  #[serde(default = "default_true")]
  pub sound_enabled: bool,
  /// Clé SteamGridDB, saisie par l'utilisateur. Elle n'est **jamais** écrite
  /// dans le dépôt : elle ne vit que dans le fichier de réglages local.
  #[serde(default)]
  pub steamgriddb_key: String,
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
    boot_video: "/assets/boot/steamos_startup.webm".to_string(),
    boot_video_enabled: true,
    sound_enabled: true,
    steamgriddb_key: String::new(),
  })
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OnlineArtwork {
  pub cover: String,
  pub hero: String,
  pub logo: String,
  pub banner: String,
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

  // L'extension suit l'adresse : une jaquette Steam est en .jpg, un logo en .png.
  let extension = url
    .split('?')
    .next()
    .and_then(|clean| clean.rsplit('.').next())
    .filter(|ext| ext.len() <= 4 && ext.chars().all(|c| c.is_ascii_alphanumeric()))
    .unwrap_or("jpg")
    .to_lowercase();

  let safe_id: String = game_id
    .chars()
    .map(|c| if c.is_ascii_alphanumeric() || c == '-' || c == '_' { c } else { '_' })
    .collect();
  let path = dir.join(format!("{safe_id}-{kind}.{extension}"));

  if path.exists() {
    return path.to_string_lossy().replace('\\', "/");
  }

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
  if fs::write(&path, &bytes).is_err() {
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
      cache_game_art,
      steam_downloads,
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
