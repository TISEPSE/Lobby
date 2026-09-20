use std::fs;
use std::path::PathBuf;
use std::process::Command;

use tauri::Manager;

/// Fiche d'un jeu, telle que l'interface l'attend. Tout vient des points
/// d'entrée publics de Steam : pas de clé, pas de compte.
#[derive(serde::Serialize, serde::Deserialize, Clone, Debug)]
struct GameDetails {
  appid: String,
  title: String,
  /// Jaquette verticale quand elle existe, bannière sinon.
  cover: String,
  hero: String,
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
  let mut cover_candidates = vec![
    format!("{cdn}/{appid}/library_600x900_2x.jpg"),
    format!("{cdn}/{appid}/library_600x900.jpg"),
  ];
  if let Some(header) = data["header_image"].as_str() {
    cover_candidates.push(header.to_string());
  }
  cover_candidates.push(format!("{cdn}/{appid}/header.jpg"));

  let mut hero_candidates = vec![format!("{cdn}/{appid}/library_hero.jpg")];
  if let Some(background) = data["background_raw"].as_str() {
    hero_candidates.push(background.to_string());
  }

  let details = GameDetails {
    appid: appid.clone(),
    title: data["name"].as_str().unwrap_or_default().to_string(),
    cover: first_available(&client, &cover_candidates).await,
    hero: first_available(&client, &hero_candidates).await,
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


/// Lance un jeu et rend la main tout de suite : l'interface reste vivante et
/// suit le processus. Renvoie le PID pour pouvoir surveiller la fin de partie.
#[tauri::command]
fn launch_game(program: String, args: Vec<String>) -> Result<u32, String> {
  Command::new(&program)
    .args(&args)
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
      steam_details
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
