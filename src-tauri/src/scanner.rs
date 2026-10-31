use std::fs;
use std::path::{Path, PathBuf};

/// Raccourcis et exécutables rejetés d'office (outils, désinstallateurs, dépendances).
const REJECTED_NAMES: &[&str] = &[
  "unins", "désinstall", "desinstall", "uninstall", "readme", "lisez", "manual",
  "manuel", "support", "site web", "website", "configurat", "settings", "éditeur",
  "editor", "server", "serveur", "documentation", "aide", "help",
  "crash", "report", "benchmark", "redist", "directx", "vcredist", "touchup",
  "helper", "launcher_update", "update", "patcher", "eac_", "easyanticheat",
  "unitycrashhandler", "crashpad", "dotnet", "sample", "verifier", "cert kit",
  "windows kits", "sdk", "tools for",
];

/// Applications courantes qui traînent sur le Bureau ou le menu Démarrer :
/// aucune n'est un jeu, on les écarte pour une bibliothèque propre.
const APP_BLOCKLIST: &[&str] = &[
  "chrome", "firefox", "msedge", "iexplore", "opera", "brave", "vivaldi",
  "discord", "teams", "zoom", "slack", "skype", "whatsapp", "telegram",
  "thunderbird", "outlook", "mailflow", "proton", "spotify", "nuclear",
  "notion", "obsidian", "claude", "chatgpt", "antigravity",
  "code", "vscode", "sublime", "notepad", "cursor", "docker", "git",
  "libreoffice", "soffice", "winword", "excel", "powerpnt", "acrord",
  "obs64", "obs32", "audacity", "gimp", "krita", "inkscape", "davinci",
  "fl64", "fl studio", "ableton", "reaper",
  "winrar", "7zfm", "vlc", "easeus", "unigetui", "lghub", "nvidia app",
  "geforce", "armoury", "msiafterburner", "rivatuner", "synology",
  "radvideo", "autoclicker", "auto clicker", "luatools", "debload",
  "explorer", "cmd", "powershell", "terminal", "regedit", "taskmgr",
  "python", "idle", "node", "npm", "java", "visual studio", "installer",
  "updater", "recovery", "tailscale", "parsec", "localsend", "plex",
  "teamviewer", "anydesk", "onedrive", "dropbox", "google drive",
  "fl cloud", "bakkesmod", "wireshark", "putty", "filezilla", "tlauncher",
  "steam", "ea", "ea desktop", "ealauncher", "epic games", "epicgameslauncher",
  "gog galaxy", "ubisoft connect", "battle.net", "riot client",
  "epiconlineservices", "epic online services", "easyanticheat", "battleye",
  "crashreport", "crashhandler", "unitycrashhandler", "dotnet", "redist",
  "7-zip", "7zip", "ffmpeg", "hidhide", "vigem", "melodyne", "vanguard",
  "winget", "temurin", "adoptium", "copilot", "webview", "edge",
];

const COVER_FILENAMES: &[&str] = &[
  "library_600x900.jpg", "library_600x900_2x.jpg", "cover.jpg", "cover.png",
  "folder.jpg", "folder.png", "boxart.jpg", "boxart.png", "poster.jpg",
  "poster.png", "header.jpg"
];

#[derive(serde::Serialize, serde::Deserialize, Clone, Debug)]
pub struct ScannedGame {
  pub id: String,
  pub title: String,
  pub appid: Option<String>,
  // Champs facultatifs côté interface : sans `default`, un seul jeu qui ne
  // les porte pas faisait refuser toute la sauvegarde de la bibliothèque, en
  // silence — elle ne vivait alors que dans le stockage du navigateur.
  #[serde(default)]
  pub cover: String,
  #[serde(default)]
  pub hero: String,
  #[serde(default)]
  pub logo: String,
  #[serde(default)]
  pub source: String, // "steam", "epic", "folder", "shortcut"
  #[serde(default)]
  pub executable: String,
  #[serde(default)]
  pub args: Vec<String>,
  /// Exécutable choisi à la main (options du jeu → « Changer l'exécutable ») :
  /// la recherche automatique ne doit plus jamais le remplacer.
  #[serde(default, skip_serializing_if = "std::ops::Not::not")]
  pub custom_executable: bool,
}

/// Normalise un nom pour comparaison insensible à la ponctuation et casse.
pub fn normalize(s: &str) -> String {
  s.chars()
    .filter(|c| c.is_alphanumeric())
    .flat_map(|c| c.to_lowercase())
    .collect()
}

pub fn is_plausible_title(name: &str) -> bool {
  let low = name.to_lowercase();
  for rej in REJECTED_NAMES {
    if low.contains(rej) {
      return false;
    }
  }
  true
}

pub fn is_application(title: &str, exe_name: &str) -> bool {
  let t_low = title.to_lowercase();
  let e_low = exe_name.to_lowercase();
  for app in APP_BLOCKLIST {
    if t_low == *app || t_low.starts_with(&format!("{app} ")) || t_low.starts_with(&format!("{app}-")) {
      return true;
    }
    if e_low == *app || e_low.starts_with(&format!("{app}.")) || e_low.starts_with(&format!("{app}_")) {
      return true;
    }
    if app.len() >= 6 && (t_low.contains(app) || e_low.contains(app)) {
      return true;
    }
  }
  false
}

/// Cherche une jaquette locale dans un dossier.
pub fn find_local_cover(folder: &Path) -> Option<String> {
  if !folder.exists() || !folder.is_dir() {
    return None;
  }
  for name in COVER_FILENAMES {
    let p = folder.join(name);
    if p.is_file() {
      return Some(p.to_string_lossy().replace('\\', "/"));
    }
  }
  None
}

// ============================================================================
// STEAM
// ============================================================================

/// Dossier de Steam déclaré dans le registre : le seul moyen de le trouver
/// quel que soit le disque choisi à l'installation.
#[cfg(windows)]
fn registered_steam_root() -> Option<PathBuf> {
  use winreg::enums::*;
  use winreg::RegKey;

  let keys = [
    (HKEY_CURRENT_USER, "Software\\Valve\\Steam", "SteamPath"),
    (HKEY_LOCAL_MACHINE, "SOFTWARE\\WOW6432Node\\Valve\\Steam", "InstallPath"),
    (HKEY_LOCAL_MACHINE, "SOFTWARE\\Valve\\Steam", "InstallPath"),
  ];
  keys.into_iter().find_map(|(hive, key, value)| {
    let path: String = RegKey::predef(hive).open_subkey(key).ok()?.get_value(value).ok()?;
    let path = PathBuf::from(path);
    path.join("steamapps").exists().then_some(path)
  })
}

/// Trouve le dossier principal de Steam.
pub fn steam_root() -> Option<PathBuf> {
  #[cfg(windows)]
  {
    if let Some(root) = registered_steam_root() {
      return Some(root);
    }
    // Rien dans le registre (Steam recopié à la main) : les emplacements
    // habituels, sur chaque disque.
    for drive in drive_roots() {
      for folder in ["Program Files (x86)\\Steam", "Program Files\\Steam", "Steam"] {
        let candidate = drive.join(folder);
        if candidate.join("steamapps").exists() {
          return Some(candidate);
        }
      }
    }
  }
  #[cfg(not(windows))]
  {
    if let Ok(home) = std::env::var("HOME") {
      let home_p = PathBuf::from(home);
      let candidates = [
        home_p.join(".steam/steam"),
        home_p.join(".local/share/Steam"),
        home_p.join(".var/app/com.valvesoftware.Steam/.local/share/Steam"),
      ];
      for c in candidates {
        if c.join("steamapps").exists() {
          return Some(c);
        }
      }
    }
  }
  None
}

/// Extrait la valeur d'une clé dans un fichier Valve .vdf ou .acf : `"clé"   "valeur"`
pub fn parse_vdf_value(line: &str, key: &str) -> Option<String> {
  let parts: Vec<&str> = line.split('"').collect();
  for i in 0..parts.len() {
    if parts[i].trim().eq_ignore_ascii_case(key) {
      for j in (i + 1)..parts.len() {
        let val = parts[j].trim();
        if !val.is_empty() {
          return Some(val.to_string());
        }
      }
    }
  }
  None
}

/// Lit les bibliothèques déclarées dans `libraryfolders.vdf`.
pub fn steam_libraries(root: &Path) -> Vec<PathBuf> {
  let mut libs = vec![root.to_path_buf()];
  let vdf = root.join("steamapps").join("libraryfolders.vdf");
  if let Ok(content) = fs::read_to_string(vdf) {
    for line in content.lines() {
      if let Some(path_str) = parse_vdf_value(line, "path") {
        let clean = path_str.replace("\\\\", "/").replace('\\', "/");
        let p = PathBuf::from(&clean);
        if p.exists() && !libs.contains(&p) {
          libs.push(p);
        }
      }
    }
  }
  libs
}

pub fn scan_steam() -> Vec<ScannedGame> {
  let mut games = Vec::new();
  let root = match steam_root() {
    Some(r) => r,
    None => return games,
  };

  let client = if cfg!(windows) {
    root.join("steam.exe").to_string_lossy().replace('\\', "/")
  } else {
    "steam".to_string()
  };

  for lib in steam_libraries(&root) {
    let steamapps = lib.join("steamapps");
    let entries = match fs::read_dir(&steamapps) {
      Ok(e) => e,
      Err(_) => continue,
    };

    for entry in entries.flatten() {
      let file_name = entry.file_name().to_string_lossy().to_string();
      if file_name.starts_with("appmanifest_") && file_name.ends_with(".acf") {
        if let Ok(content) = fs::read_to_string(entry.path()) {
          let mut appid = String::new();
          let mut title = String::new();
          let mut install_dir = String::new();

          for line in content.lines() {
            if appid.is_empty() {
              if let Some(val) = parse_vdf_value(line, "appid") {
                appid = val;
              }
            }
            if title.is_empty() {
              if let Some(val) = parse_vdf_value(line, "name") {
                title = val;
              }
            }
            if install_dir.is_empty() {
              if let Some(val) = parse_vdf_value(line, "installdir") {
                install_dir = val;
              }
            }
          }

          if appid.is_empty() || title.is_empty() {
            continue;
          }
          if !is_plausible_title(&title) || appid == "228980" {
            // 228980 = Steamworks Common Redistributables
            continue;
          }

          // Vérifie la présence physique des fichiers
          let full_install = steamapps.join("common").join(&install_dir);
          if !install_dir.is_empty() && !full_install.exists() {
            continue;
          }

          let cdn = "https://cdn.cloudflare.steamstatic.com/steam/apps";
          // Vérification si des images locales existent dans appcache
          let cache_dir = root.join("appcache").join("librarycache").join(&appid);
          let local_cover = if cache_dir.join("library_600x900.jpg").exists() {
            cache_dir.join("library_600x900.jpg").to_string_lossy().replace('\\', "/")
          } else {
            format!("{cdn}/{appid}/library_600x900_2x.jpg")
          };

          let local_hero = if cache_dir.join("library_hero.jpg").exists() {
            cache_dir.join("library_hero.jpg").to_string_lossy().replace('\\', "/")
          } else {
            format!("{cdn}/{appid}/library_hero.jpg")
          };

          let local_logo = if cache_dir.join("logo.png").exists() {
            cache_dir.join("logo.png").to_string_lossy().replace('\\', "/")
          } else {
            format!("{cdn}/{appid}/logo.png")
          };

          games.push(ScannedGame {
            id: format!("steam-{appid}"),
            title,
            appid: Some(appid.clone()),
            cover: local_cover,
            hero: local_hero,
            logo: local_logo,
            source: "steam".to_string(),
            executable: client.clone(),
            args: vec!["-applaunch".to_string(), appid],
            custom_executable: false,
          });
        }
      }
    }
  }

  games
}

/// Dossiers de `steamapps/common` **sans manifeste**. Steam n'est pas la seule
/// façon dont un jeu arrive là : on en trouve beaucoup dont l'`appmanifest`
/// n'existe pas (installation copiée, manifeste supprimé). Sans ce passage, la
/// moitié de la bibliothèque restait invisible.
pub fn scan_steam_common() -> Vec<ScannedGame> {
  let mut games = Vec::new();
  let root = match steam_root() {
    Some(r) => r,
    None => return games,
  };

  // Dossiers techniques de Steam : ce ne sont pas des jeux.
  const IGNORED: [&str; 5] = [
    "steamworks shared",
    "steamworks common redistributables",
    "steam controller configs",
    "screenshots",
    "soundtracks",
  ];

  for lib in steam_libraries(&root) {
    let steamapps = lib.join("steamapps");
    let common = steamapps.join("common");

    // Dossiers déjà décrits par un manifeste : ils sont traités par scan_steam.
    let mut known = Vec::new();
    if let Ok(entries) = fs::read_dir(&steamapps) {
      for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        if name.starts_with("appmanifest_") && name.ends_with(".acf") {
          if let Ok(content) = fs::read_to_string(entry.path()) {
            for line in content.lines() {
              if let Some(dir) = parse_vdf_value(line, "installdir") {
                known.push(dir.to_lowercase());
                break;
              }
            }
          }
        }
      }
    }

    let entries = match fs::read_dir(&common) {
      Ok(e) => e,
      Err(_) => continue,
    };

    for entry in entries.flatten() {
      let path = entry.path();
      if !path.is_dir() {
        continue;
      }
      let folder_name = entry.file_name().to_string_lossy().to_string();
      let lowered = folder_name.to_lowercase();
      if known.contains(&lowered) || IGNORED.contains(&lowered.as_str()) {
        continue;
      }
      if !is_plausible_title(&folder_name) {
        continue;
      }

      let clean = clean_game_title(&folder_name);
      let exe = match find_best_executable(&path, &clean, 0, 3) {
        Some(e) => e,
        None => continue,
      };

      games.push(ScannedGame {
        id: format!("steamdir-{}", hash_string(&path.to_string_lossy())),
        title: clean,
        appid: None,
        cover: find_local_cover(&path).unwrap_or_default(),
        hero: String::new(),
        logo: String::new(),
        source: "folder".to_string(),
        executable: exe.to_string_lossy().replace('\\', "/"),
        args: vec![],
        custom_executable: false,
      });
    }
  }

  games
}

/// Noms de dossiers où l'on range ses jeux, quelle que soit la langue.
const GAME_FOLDER_NAMES: [&str; 12] = [
  "jeux", "jeu", "games", "game", "epic games", "gog games", "ubisoft games", "my games",
  "juegos", "spiele", "giochi", "jogos",
];

/// Dossiers système à ne jamais explorer : rien d'intéressant, et c'est long.
const SKIPPED_ROOT_DIRS: [&str; 10] = [
  "windows",
  "$recycle.bin",
  "system volume information",
  "programdata",
  "perflogs",
  "recovery",
  "appdata",
  "node_modules",
  "onedrive",
  "temp",
];

/// Trouve tout seul les dossiers où l'utilisateur range ses jeux.
///
/// Beaucoup de jeux n'apparaissent nulle part ailleurs : installation Epic
/// déplacée (le manifeste a disparu mais le dossier `.egstore` est là), copie
/// manuelle, jeu sans installeur. Plutôt que d'attendre que l'utilisateur
/// déclare `D:\Jeux`, on va regarder — à faible profondeur, pour rester rapide.
pub fn discover_game_folders() -> Vec<PathBuf> {
  let mut found = Vec::new();

  for root in drive_roots() {
    let entries = match fs::read_dir(&root) {
      Ok(e) => e,
      Err(_) => continue,
    };

    for entry in entries.flatten() {
      let path = entry.path();
      if !path.is_dir() {
        continue;
      }
      let name = entry.file_name().to_string_lossy().to_lowercase();
      if SKIPPED_ROOT_DIRS.contains(&name.as_str()) {
        continue;
      }

      if GAME_FOLDER_NAMES.contains(&name.as_str()) {
        found.push(path.clone());
        continue;
      }

      // Un cran plus bas : « C:\Ordi\Jeux » est aussi fréquent qu'un dossier
      // de jeux à la racine.
      if let Ok(children) = fs::read_dir(&path) {
        for child in children.flatten() {
          let child_path = child.path();
          if !child_path.is_dir() {
            continue;
          }
          let child_name = child.file_name().to_string_lossy().to_lowercase();
          if GAME_FOLDER_NAMES.contains(&child_name.as_str()) {
            found.push(child_path);
          }
        }
      }
    }
  }

  found
}

/// Racines des lecteurs montés. Windows n'expose pas la liste : on teste.
fn drive_roots() -> Vec<PathBuf> {
  let mut roots = Vec::new();
  #[cfg(windows)]
  {
    for letter in b'C'..=b'Z' {
      let path = PathBuf::from(format!("{}:\\", letter as char));
      if path.is_dir() {
        roots.push(path);
      }
    }
  }
  #[cfg(not(windows))]
  {
    if let Some(home) = std::env::var_os("HOME") {
      roots.push(PathBuf::from(home));
    }
    roots.push(PathBuf::from("/games"));
  }
  roots
}

// ============================================================================
// REGISTRE WINDOWS
// ============================================================================

/// Éditeurs dont rien n'est jamais un jeu : pilotes, outils système, runtimes.
#[cfg(windows)]
const NON_GAME_PUBLISHERS: [&str; 14] = [
  "nvidia",
  "microsoft",
  "realtek",
  "intel",
  "advanced micro devices",
  "amd",
  "google",
  "mozilla",
  "oracle",
  "eclipse",
  "docker",
  "python",
  "nefarius",
  "the git development community",
];

/// Jeux déclarés dans le registre Windows. C'est la seule source qui connaisse
/// les jeux installés hors launcher connu : Riot (Valorant), Battle.net
/// (Overwatch), ou n'importe quel installeur classique.
pub fn scan_registry() -> Vec<ScannedGame> {
  let mut games = Vec::new();

  #[cfg(windows)]
  {
    use winreg::enums::*;
    use winreg::RegKey;

    let roots: [(RegKey, &str); 3] = [
      (RegKey::predef(HKEY_LOCAL_MACHINE), "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall"),
      (RegKey::predef(HKEY_LOCAL_MACHINE), "SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall"),
      (RegKey::predef(HKEY_CURRENT_USER), "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall"),
    ];

    for (hive, path) in roots {
      let uninstall = match hive.open_subkey(path) {
        Ok(key) => key,
        Err(_) => continue,
      };

      for name in uninstall.enum_keys().flatten() {
        let entry = match uninstall.open_subkey(&name) {
          Ok(key) => key,
          Err(_) => continue,
        };

        let title: String = entry.get_value("DisplayName").unwrap_or_default();
        let location: String = entry.get_value("InstallLocation").unwrap_or_default();
        let publisher: String = entry.get_value("Publisher").unwrap_or_default();
        // Une mise à jour système n'a pas à figurer dans une bibliothèque.
        let system_component: u32 = entry.get_value("SystemComponent").unwrap_or(0);

        if title.is_empty() || location.is_empty() || system_component == 1 {
          continue;
        }

        let lowered_publisher = publisher.to_lowercase();
        if NON_GAME_PUBLISHERS.iter().any(|p| lowered_publisher.contains(p)) {
          continue;
        }
        if !is_plausible_title(&title) || is_application(&title, &title) {
          continue;
        }

        // Le chemin est parfois entre guillemets dans le registre.
        let cleaned = location.trim().trim_matches('"').replace('/', "\\");
        let folder = PathBuf::from(&cleaned);
        if !folder.is_dir() {
          continue;
        }

        let clean = clean_game_title(&title);
        let exe = match find_best_executable(&folder, &clean, 0, 3) {
          Some(e) => e,
          None => continue,
        };
        if is_application(&clean, &exe.file_stem().unwrap_or_default().to_string_lossy()) {
          continue;
        }

        games.push(ScannedGame {
          id: format!("registry-{}", hash_string(&exe.to_string_lossy())),
          title: clean,
          appid: None,
          cover: find_local_cover(&folder).unwrap_or_default(),
          hero: String::new(),
          logo: String::new(),
          source: "registry".to_string(),
          executable: exe.to_string_lossy().replace('\\', "/"),
          args: vec![],
          custom_executable: false,
        });
      }
    }
  }

  games
}

// ============================================================================
// EPIC GAMES
// ============================================================================

pub fn scan_epic() -> Vec<ScannedGame> {
  let mut games = Vec::new();
  #[cfg(windows)]
  {
    // `ProgramData` peut avoir été déplacé : on demande à Windows où il est.
    let program_data = std::env::var("ProgramData").unwrap_or_else(|_| "C:\\ProgramData".to_string());
    let manifests = PathBuf::from(program_data).join("Epic\\EpicGamesLauncher\\Data\\Manifests");
    if let Ok(entries) = fs::read_dir(manifests) {
      for entry in entries.flatten() {
        let path = entry.path();
        if path.extension().map_or(false, |ext| ext == "item") {
          if let Ok(content) = fs::read_to_string(&path) {
            if let Ok(json) = serde_json::from_str::<serde_json::Value>(&content) {
              let title = json["DisplayName"].as_str().unwrap_or("").trim();
              let app_name = json["AppName"].as_str().unwrap_or("").trim();
              let location = json["InstallLocation"].as_str().unwrap_or("").trim();
              let launch_exe = json["LaunchExecutable"].as_str().unwrap_or("").trim();

              if title.is_empty() || location.is_empty() || launch_exe.is_empty() {
                continue;
              }

              let loc_path = PathBuf::from(location);
              let full_exe = loc_path.join(launch_exe);
              if !full_exe.exists() || !is_plausible_title(title) {
                continue;
              }

              let clean_title = title.replace("®", "").replace("™", "").trim().to_string();
              let cover = find_local_cover(&loc_path)
                .or_else(|| full_exe.parent().and_then(find_local_cover))
                .unwrap_or_default();

              games.push(ScannedGame {
                id: format!("epic-{}", if !app_name.is_empty() { app_name.to_lowercase() } else { normalize(&clean_title) }),
                title: clean_title,
                appid: None,
                cover,
                hero: String::new(),
                logo: String::new(),
                source: "epic".to_string(),
                executable: full_exe.to_string_lossy().replace('\\', "/"),
                args: vec![],
                custom_executable: false,
              });
            }
          }
        }
      }
    }
  }
  games
}

// ============================================================================
// DOSSIERS DE JEUX (ex: D:\Jeux)
// ============================================================================

/// Scanne les sous-dossiers d'un répertoire pour trouver les jeux.
pub fn scan_custom_folder(folder: &Path) -> Vec<ScannedGame> {
  let mut games = Vec::new();
  let entries = match fs::read_dir(folder) {
    Ok(e) => e,
    Err(_) => return games,
  };

  for entry in entries.flatten() {
    let path = entry.path();
    if !path.is_dir() {
      continue;
    }

    let dir_name = entry.file_name().to_string_lossy().to_string();
    if dir_name.starts_with('.') || !is_plausible_title(&dir_name) {
      continue;
    }

    // Détection si c'est un jeu Epic Games via .egstore
    let is_epic = path.join(".egstore").exists();

    // Cherche l'exécutable principal
    if let Some(exe) = find_best_executable(&path, &dir_name, 0, 3) {
      // Un dossier de jeux abrite aussi des launchers et des services : ce
      // n'est pas parce qu'il y a un exécutable que c'est un jeu.
      let exe_stem = exe.file_stem().unwrap_or_default().to_string_lossy().to_string();
      if is_application(&dir_name, &exe_stem) {
        continue;
      }

      let cover = find_local_cover(&path)
        .or_else(|| exe.parent().and_then(find_local_cover))
        .unwrap_or_default();

      // « bo3 » ne dit rien ; « BlackOps3.exe » si. Quand le nom du dossier est
      // trop court pour être un titre, celui de l'exécutable fait mieux.
      let mut clean_title = clean_game_title(&dir_name);
      if clean_title.chars().count() <= 4 {
        let from_exe = clean_game_title(&exe_stem);
        if from_exe.chars().count() > clean_title.chars().count() {
          clean_title = from_exe;
        }
      }
      let exe_str = exe.to_string_lossy().replace('\\', "/");
      let id = if is_epic {
        format!("epic-{}", normalize(&clean_title))
      } else {
        format!("scan-{:x}", hash_string(&exe_str))
      };

      games.push(ScannedGame {
        id,
        title: clean_title,
        appid: None,
        cover,
        hero: String::new(),
        logo: String::new(),
        source: if is_epic { "epic".to_string() } else { "folder".to_string() },
        executable: exe_str,
        args: vec![],
        custom_executable: false,
      });
    }
  }

  games
}

/// Nettoie un titre de jeu en retirant les tags de release ("ALL DLC", "By STG GEGE", versions entre parenthèses, etc.).
pub fn clean_game_title(title: &str) -> String {
  let mut t = title.to_string();

  if t.to_lowercase().ends_with(".exe") {
    t = t[..t.len() - 4].to_string();
  }

  let junk_patterns = [
    "by stg gege", "stg gege", "all dlc", "deluxe edition", "definitive edition",
    "special edition", "repack", "fitgirl", "dodi", "xatab", "gold edition",
    "enhanced edition", "goty", "game of the year", "complete edition",
    "clean steam", "steam rip", "remastered", "remake", " launcher", " client",
  ];

  let mut lower = t.to_lowercase();
  for junk in junk_patterns {
    if let Some(pos) = lower.find(junk) {
      t = t[..pos].trim_matches(|c: char| !c.is_alphanumeric()).to_string();
      lower = t.to_lowercase();
    }
  }

  if let Some(pos) = t.find('(') {
    if let Some(end_pos) = t[pos..].find(')') {
      let sub = &t[pos + 1..pos + end_pos];
      if sub.starts_with('v') || sub.chars().all(|c| c.is_numeric() || c == '.' || c == ' ') || sub.eq_ignore_ascii_case("lazer") {
        t = format!("{}{}", &t[..pos], &t[pos + end_pos + 1..]);
      }
    }
  }

  let mut cleaned = t.replace('_', " ").replace('.', " ").trim().to_string();

  // « bo3 game files » : le nom du dossier, pas celui du jeu.
  for suffix in [" game files", " gamefiles", " files"] {
    if cleaned.to_lowercase().ends_with(suffix) {
      cleaned = cleaned[..cleaned.len() - suffix.len()].trim().to_string();
    }
  }

  // « HandOfFate2 » se lit mal : on rend les espaces que le dossier a perdus.
  if !cleaned.contains(' ') && cleaned.len() > 6 {
    cleaned = split_camel_case(&cleaned);
  }

  cleaned.trim().to_string()
}

/// Sépare un nom collé en CamelCase, et détache le numéro final éventuel.
fn split_camel_case(value: &str) -> String {
  let chars: Vec<char> = value.chars().collect();
  let mut out = String::new();

  for (i, &c) in chars.iter().enumerate() {
    let previous = if i > 0 { chars[i - 1] } else { c };
    let starts_word = i > 0
      && ((c.is_uppercase() && previous.is_lowercase())
        || (c.is_ascii_digit() && !previous.is_ascii_digit()));
    if starts_word {
      out.push(' ');
    }
    out.push(c);
  }

  // Sans majuscule interne, il n'y a rien à découper : on garde l'original.
  if out.trim() == value {
    value.to_string()
  } else {
    out
  }
}

fn find_best_executable(dir: &Path, game_name: &str, depth: usize, max_depth: usize) -> Option<PathBuf> {
  if depth > max_depth {
    return None;
  }
  let entries = fs::read_dir(dir).ok()?;
  let mut candidate_fallback: Option<PathBuf> = None;
  let mut subdirs = Vec::new();

  let norm_game = normalize(game_name);

  for entry in entries.flatten() {
    let p = entry.path();
    if p.is_dir() {
      let name = entry.file_name().to_string_lossy().to_string();
      if !name.starts_with('.') && !name.eq_ignore_ascii_case("crashpad") && !name.eq_ignore_ascii_case("easyanticheat") {
        subdirs.push(p);
      }
    } else if p.is_file() {
      let ext = p.extension().and_then(|e| e.to_str()).unwrap_or("");
      #[cfg(windows)]
      let is_exe = ext.eq_ignore_ascii_case("exe");
      #[cfg(not(windows))]
      let is_exe = ext.is_empty() || ext == "x86_64" || ext == "AppImage";

      if is_exe {
        let stem = p.file_stem().and_then(|s| s.to_str()).unwrap_or("");
        if is_plausible_title(stem) {
          let norm_stem = normalize(stem);
          if !norm_game.is_empty() && (norm_stem.contains(&norm_game) || norm_game.contains(&norm_stem)) {
            return Some(p);
          }
          if candidate_fallback.is_none() {
            candidate_fallback = Some(p);
          }
        }
      }
    }
  }

  // Si pas de correspondance exacte dans le dossier courant, explore les sous-dossiers
  for sub in subdirs {
    if let Some(found) = find_best_executable(&sub, game_name, depth + 1, max_depth) {
      let stem = found.file_stem().and_then(|s| s.to_str()).unwrap_or("");
      let norm_stem = normalize(stem);
      if !norm_game.is_empty() && (norm_stem.contains(&norm_game) || norm_game.contains(&norm_stem)) {
        return Some(found);
      }
      if candidate_fallback.is_none() {
        candidate_fallback = Some(found);
      }
    }
  }

  candidate_fallback
}

// ============================================================================
// RACCOURCIS (.lnk sous Windows)
// ============================================================================

pub fn scan_shortcuts() -> Vec<ScannedGame> {
  let mut games = Vec::new();
  #[cfg(windows)]
  {
    let mut dirs_to_scan = Vec::new();
    if let Ok(userprofile) = std::env::var("USERPROFILE") {
      dirs_to_scan.push(PathBuf::from(&userprofile).join("Desktop"));
      dirs_to_scan.push(PathBuf::from(&userprofile).join("AppData\\Roaming\\Microsoft\\Windows\\Start Menu\\Programs"));
    }
    if let Ok(public) = std::env::var("PUBLIC") {
      dirs_to_scan.push(PathBuf::from(&public).join("Desktop"));
    }
    if let Ok(program_data) = std::env::var("ProgramData") {
      dirs_to_scan.push(PathBuf::from(&program_data).join("Microsoft\\Windows\\Start Menu\\Programs"));
    }

    for dir in dirs_to_scan {
      if dir.exists() {
        collect_lnk_shortcuts(&dir, 0, 3, &mut games);
      }
    }
  }
  games
}

#[cfg(windows)]
fn collect_lnk_shortcuts(dir: &Path, depth: usize, max_depth: usize, games: &mut Vec<ScannedGame>) {
  if depth > max_depth {
    return;
  }
  let entries = match fs::read_dir(dir) {
    Ok(e) => e,
    Err(_) => return,
  };

  for entry in entries.flatten() {
    let p = entry.path();
    if p.is_dir() {
      let name = entry.file_name().to_string_lossy().to_string();
      if !name.starts_with('.') {
        collect_lnk_shortcuts(&p, depth + 1, max_depth, games);
      }
    } else if p.extension().map_or(false, |ext| ext.eq_ignore_ascii_case("lnk")) {
      let stem = p.file_stem().and_then(|s| s.to_str()).unwrap_or("");
      if !is_plausible_title(stem) {
        continue;
      }
      if let Some(target) = parse_lnk_target(&p) {
        let target_clean = target.replace('\\', "/");
        let low_target = target_clean.to_lowercase();
        if !low_target.ends_with(".exe") || low_target.starts_with("c:/windows") {
          continue;
        }

        let exe_name = Path::new(&target_clean).file_name().and_then(|n| n.to_str()).unwrap_or("");
        if is_application(stem, exe_name) {
          continue;
        }

        let cover = Path::new(&target_clean).parent().and_then(find_local_cover).unwrap_or_default();

        games.push(ScannedGame {
          id: format!("lnk-{:x}", hash_string(&target_clean)),
          title: stem.trim().to_string(),
          appid: None,
          cover,
          hero: String::new(),
          logo: String::new(),
          source: "shortcut".to_string(),
          executable: target_clean,
          args: vec![],
          custom_executable: false,
        });
      }
    }
  }
}

/// Parser sommaire mais fiable du format Windows Shell Link (.lnk).
#[cfg(windows)]
fn parse_lnk_target(path: &Path) -> Option<String> {
  let bytes = fs::read(path).ok()?;
  if bytes.len() < 76 || &bytes[0..4] != [0x4C, 0x00, 0x00, 0x00] {
    return None;
  }

  let flags = u32::from_le_bytes(bytes[20..24].try_into().ok()?);
  let has_target_id_list = (flags & 0x01) != 0;
  let has_link_info = (flags & 0x02) != 0;

  let mut offset = 76;
  if has_target_id_list {
    if offset + 2 > bytes.len() {
      return None;
    }
    let id_list_size = u16::from_le_bytes(bytes[offset..offset + 2].try_into().ok()?) as usize;
    offset += 2 + id_list_size;
  }

  if has_link_info {
    if offset + 28 > bytes.len() {
      return None;
    }
    let link_info_size = u32::from_le_bytes(bytes[offset..offset + 4].try_into().ok()?) as usize;
    let header_size = u32::from_le_bytes(bytes[offset + 4..offset + 8].try_into().ok()?) as usize;
    let info_flags = u32::from_le_bytes(bytes[offset + 8..offset + 12].try_into().ok()?);
    let base_offset = u32::from_le_bytes(bytes[offset + 16..offset + 20].try_into().ok()?) as usize;
    let suffix_offset = u32::from_le_bytes(bytes[offset + 24..offset + 28].try_into().ok()?) as usize;

    // Bit 0 = LocalBasePath est renseigné
    if (info_flags & 0x01) != 0 {
      let base = read_null_terminated_ascii(&bytes, offset + base_offset);
      let suffix = read_null_terminated_ascii(&bytes, offset + suffix_offset);
      let mut full = format!("{base}{suffix}");
      if header_size >= 0x24 && offset + 36 <= bytes.len() {
        let unicode_base = u32::from_le_bytes(bytes[offset + 28..offset + 32].try_into().ok()?) as usize;
        let unicode_suffix = u32::from_le_bytes(bytes[offset + 32..offset + 36].try_into().ok()?) as usize;
        if unicode_base > 0 {
          let u_base = read_null_terminated_utf16(&bytes, offset + unicode_base);
          let u_suffix = read_null_terminated_utf16(&bytes, offset + unicode_suffix);
          full = format!("{u_base}{u_suffix}");
        }
      }
      if Path::new(&full).is_file() {
        return Some(full);
      }
    }
    let _ = link_info_size;
  }

  None
}

#[cfg(windows)]
fn read_null_terminated_ascii(bytes: &[u8], start: usize) -> String {
  let mut s = Vec::new();
  let mut i = start;
  while i < bytes.len() && bytes[i] != 0 {
    s.push(bytes[i]);
    i += 1;
  }
  String::from_utf8_lossy(&s).to_string()
}

#[cfg(windows)]
fn read_null_terminated_utf16(bytes: &[u8], start: usize) -> String {
  let mut u16_units = Vec::new();
  let mut i = start;
  while i + 1 < bytes.len() {
    let unit = u16::from_le_bytes([bytes[i], bytes[i + 1]]);
    if unit == 0 {
      break;
    }
    u16_units.push(unit);
    i += 2;
  }
  String::from_utf16_lossy(&u16_units)
}

fn hash_string(val: &str) -> u64 {
  use std::hash::{Hash, Hasher};
  let mut hasher = std::collections::hash_map::DefaultHasher::new();
  val.hash(&mut hasher);
  hasher.finish()
}

// ============================================================================
// SCAN GLOBAL & METADONNEES STEAM PUBLIC
// ============================================================================

/// Scanne toutes les sources et dédoublonne les résultats.
pub async fn scan_all_games(custom_folders: &[String]) -> Vec<ScannedGame> {
  let mut candidates = Vec::new();

  // 1. Steam
  candidates.extend(scan_steam());

  // 2. Jeux posés dans steamapps/common sans manifeste
  candidates.extend(scan_steam_common());

  // 3. Epic Games
  candidates.extend(scan_epic());

  // 4. Registre Windows : Riot, Battle.net, installeurs classiques
  candidates.extend(scan_registry());

  // 5. Dossiers de jeux : ceux déclarés par l'utilisateur, plus ceux qu'on
  //    reconnaît tout seul (D:\Jeux, C:\Ordi\Jeux…).
  let mut folders: Vec<PathBuf> = custom_folders.iter().map(PathBuf::from).collect();
  for discovered in discover_game_folders() {
    if !folders.iter().any(|f| f == &discovered) {
      folders.push(discovered);
    }
  }
  for folder in folders {
    if folder.exists() && folder.is_dir() {
      candidates.extend(scan_custom_folder(&folder));
    }
  }

  // 4. Raccourcis
  candidates.extend(scan_shortcuts());

  // Dédoublonnage robuste par titre normalisé ET par exécutable : fusionne les doublons (ex: Epic vs Dossier Rocket League, shortcut vs dossier)
  let mut title_map: std::collections::HashMap<String, ScannedGame> = std::collections::HashMap::new();
  let mut exe_to_key: std::collections::HashMap<String, String> = std::collections::HashMap::new();

  for game in candidates {
    let norm_title = normalize(&clean_game_title(&game.title));
    if norm_title.is_empty() {
      continue;
    }

    let norm_exe = game.executable.to_lowercase().replace('\\', "/");
    let is_generic = norm_exe.ends_with("/steam.exe")
      || norm_exe.ends_with("/ealauncher.exe")
      || norm_exe.ends_with("/epicgameslauncher.exe")
      || norm_exe.is_empty();

    let matched_key = if title_map.contains_key(&norm_title) {
      Some(norm_title.clone())
    } else if !is_generic && exe_to_key.contains_key(&norm_exe) {
      exe_to_key.get(&norm_exe).cloned()
    } else {
      None
    };

    if let Some(key) = matched_key {
      if let Some(existing) = title_map.get_mut(&key) {
        // Complète avec la jaquette si l'autre en a une
        if existing.cover.is_empty() && !game.cover.is_empty() {
          existing.cover = game.cover;
        }
        if existing.hero.is_empty() && !game.hero.is_empty() {
          existing.hero = game.hero;
        }
        if existing.logo.is_empty() && !game.logo.is_empty() {
          existing.logo = game.logo;
        }
        if existing.appid.is_none() && game.appid.is_some() {
          existing.appid = game.appid;
        }
        // Préfère un titre plus complet et soigné avec espaces (ex: "Spiderman Miles Morales" plutôt que "MilesMorales")
        if game.title.len() > existing.title.len() && game.title.contains(' ') {
          existing.title = game.title.clone();
        } else if game.title.chars().any(|c| c.is_uppercase()) && !existing.title.chars().any(|c| c.is_uppercase()) {
          existing.title = game.title.clone();
        }
        // Préfère une source officielle ("steam" ou "epic")
        if (game.source == "steam" || game.source == "epic") && existing.source != "steam" && existing.source != "epic" {
          existing.source = game.source;
          existing.executable = game.executable;
          existing.args = game.args;
          existing.id = game.id;
        }
      }
    } else {
      if !is_generic {
        exe_to_key.insert(norm_exe, norm_title.clone());
      }
      title_map.insert(norm_title, game);
    }
  }

  let mut unique_games: Vec<ScannedGame> = title_map.into_values().collect();

  // Tente d'associer un AppID Steam pour les jeux non-Steam afin de récupérer les jaquettes HD
  let client = reqwest::Client::builder()
    .user_agent("InterfaceConsole/0.1")
    .build()
    .ok();

  if let Some(client) = client {
    for game in &mut unique_games {
      // 1. Recherche Steam pour associer un AppID et récupérer les images HD 600x900
      if game.appid.is_none() {
        if let Some(appid) = match_steam_app(&client, &game.title).await {
          let cdn = "https://cdn.cloudflare.steamstatic.com/steam/apps";
          game.appid = Some(appid.clone());
          if game.cover.is_empty() {
            game.cover = format!("{cdn}/{appid}/library_600x900_2x.jpg");
          }
          if game.hero.is_empty() {
            game.hero = format!("{cdn}/{appid}/library_hero.jpg");
          }
          if game.logo.is_empty() {
            game.logo = format!("{cdn}/{appid}/logo.png");
          }
        }
      }

      // 2. Si la jaquette est toujours manquante (jeux hors-Steam, Hytale, Epic, etc.),
      // interroge l'API publique Lutris qui fournit directement les jaquettes officielles IGDB (100% gratuit, 0 clé)
      if game.cover.is_empty() {
        if let Some((cover_url, banner_url)) = fetch_lutris_art(&client, &game.title).await {
          game.cover = cover_url;
          if game.hero.is_empty() && !banner_url.is_empty() {
            game.hero = banner_url;
          }
        }
      }
    }
  }

  unique_games.sort_by(|a, b| a.title.to_lowercase().cmp(&b.title.to_lowercase()));
  unique_games
}


/// Recherche un jeu dans l'annuaire public Steam pour trouver son AppID.
/// Variantes d'un titre à essayer auprès des catalogues en ligne.
///
/// Le nom d'un dossier est souvent collé (« Fallguys », « rocketleague ») et
/// aucun moteur de recherche ne le retrouve. Celui de l'exécutable, lui, est
/// presque toujours en CamelCase (« FallGuys_client.exe », « Spider-Man2.exe »)
/// : une fois découpé, il donne le vrai titre. On essaie donc les deux, du plus
/// probable au moins probable.
pub fn title_variants(title: &str, executable: &str) -> Vec<String> {
  let mut variants = Vec::new();
  let mut push = |value: String| {
    let trimmed = value.trim().to_string();
    if !trimmed.is_empty() && !variants.contains(&trimmed) {
      variants.push(trimmed);
    }
  };

  let cleaned = clean_game_title(title);
  push(cleaned.clone());

  // Le titre collé, séparé : « Fallguys » reste tel quel, mais « HandOfFate2 »
  // devient « Hand Of Fate 2 ».
  if !cleaned.contains(' ') {
    push(split_camel_case(&cleaned));
  }

  if !executable.is_empty() {
    let stem = Path::new(executable)
      .file_stem()
      .map(|s| s.to_string_lossy().to_string())
      .unwrap_or_default();
    let from_exe = clean_game_title(&stem);
    // Un exécutable générique (« game.exe », « launcher.exe ») ne donne aucune
    // indication : le chercher revenait à tirer une jaquette au hasard.
    let generic = GENERIC_EXECUTABLES.contains(&normalize(&from_exe).as_str());
    if !generic {
      push(from_exe.clone());
      if !from_exe.contains(' ') {
        push(split_camel_case(&from_exe));
      }
      push(split_camel_case(&stem));
    }
  }

  variants
}

/// Premier identifiant Steam trouvé en essayant chaque variante du titre.
pub async fn match_steam_app_variants(
  client: &reqwest::Client,
  title: &str,
  executable: &str,
) -> Option<String> {
  for variant in title_variants(title, executable) {
    if let Some(appid) = match_steam_app(client, &variant).await {
      return Some(appid);
    }
  }
  None
}

/// Deux titres désignent-ils le même jeu ?
///
/// L'inclusion seule ne suffit pas : « osu » est contenu dans des dizaines de
/// noms, et un jeu au nom très court (« Ball ») est contenu dans « Golf
/// Ballgame ». C'est ainsi qu'une jaquette se retrouvait sur le mauvais jeu.
/// On exige donc des titres assez longs **et** une forte proportion commune.
pub fn titles_match(a: &str, b: &str) -> bool {
  let (a, b) = (normalize(a), normalize(b));
  if a.is_empty() || b.is_empty() {
    return false;
  }
  if a == b {
    return true;
  }

  let (short, long) = if a.len() <= b.len() { (&a, &b) } else { (&b, &a) };
  // En dessous de cinq caractères, une inclusion ne veut plus rien dire.
  if short.len() < 5 || !long.contains(short.as_str()) {
    return false;
  }
  // Le titre le plus court doit représenter l'essentiel de l'autre : « Hades »
  // ne doit pas attraper « Hades II », mais « Dome Keeper » accepte
  // « Dome Keeper Demo ».
  short.len() * 10 >= long.len() * 7
}

/// Noms d'exécutables qui ne disent rien du jeu : les prendre pour un titre
/// lançait une recherche au hasard, et donc une jaquette au hasard.
const GENERIC_EXECUTABLES: &[&str] = &[
  "game", "games", "launcher", "start", "startup", "play", "run", "main", "client", "app",
  "application", "bin", "win64", "win32", "x64", "shipping", "setup", "install", "launch",
];

pub async fn match_steam_app(client: &reqwest::Client, title: &str) -> Option<String> {
  let cleaned = clean_game_title(title);
  let norm_title = normalize(&cleaned);

  // 1. Table de correspondance statique pour les jeux connus ou délistés du Store Steam
  let static_known = match norm_title.as_str() {
    "rocketleague" => Some("252950"),
    "fallguys" | "fallguysclient" => Some("1097150"),
    "spidermanmilesmorales" | "marvelsspidermanmilesmorales" => Some("1817070"),
    "spiderman2" | "marvelsspiderman2" => Some("2651280"),
    "spidermanremastered" | "marvelsspidermanremastered" => Some("1817080"),
    "deadcells" => Some("588650"),
    "ghostrunner2" => Some("2144740"),
    "handoffate2" => Some("456670"),
    "combatmaster" => Some("2281730"),
    "balatro" => Some("2379780"),
    "hades" => Some("1145360"),
    "outerwilds" => Some("753640"),
    "northgard" => Some("466560"),
    "dredge" => Some("1562430"),
    "domekeeper" => Some("1637320"),
    _ => None,
  };
  if let Some(id) = static_known {
    return Some(id.to_string());
  }

  // 2. Recherche via l'API StoreSearch Steam (très tolérante, sans clé API)
  let store_url = format!("https://store.steampowered.com/api/storesearch/?term={}&l=french&cc=FR", urlencoding_simple(&cleaned));
  if let Ok(res) = client.get(&store_url).send().await {
    if let Ok(json) = res.json::<serde_json::Value>().await {
      if let Some(items) = json["items"].as_array() {
        for item in items {
          if let (Some(id_num), Some(name)) = (item["id"].as_u64(), item["name"].as_str()) {
            if titles_match(name, &cleaned) {
              return Some(id_num.to_string());
            }
          }
        }
      }
    }
  }

  // 3. Fallback sur SearchApps de SteamCommunity
  let encoded = urlencoding_simple(&cleaned);
  let url = format!("https://steamcommunity.com/actions/SearchApps/{encoded}");
  let res = client.get(&url).send().await.ok()?;
  let json: serde_json::Value = res.json().await.ok()?;
  let list = json.as_array()?;

  // Passe 1 : correspondance exacte du nom
  for item in list {
    if let (Some(appid), Some(name)) = (item["appid"].as_str(), item["name"].as_str()) {
      if normalize(name) == norm_title {
        return Some(appid.to_string());
      }
    }
  }

  // Passe 2 : correspondance approchée, mais jamais sur une simple inclusion
  // de quelques lettres (voir `titles_match`).
  for item in list {
    if let (Some(appid), Some(name)) = (item["appid"].as_str(), item["name"].as_str()) {
      if titles_match(name, &cleaned) {
        return Some(appid.to_string());
      }
    }
  }

  None
}

pub fn urlencoding_simple(s: &str) -> String {
  let mut out = String::new();
  for b in s.bytes() {
    match b {
      b'a'..=b'z' | b'A'..=b'Z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
        out.push(b as char);
      }
      b' ' => out.push_str("%20"),
      other => {
        out.push_str(&format!("%{:02X}", other));
      }
    }
  }
  out
}

/// Génère un slug normalisé pour interroger les API en ligne (ex: "Rocket League" -> "rocket-league").
pub fn slugify(title: &str) -> String {
  let cleaned = clean_game_title(title);
  let mut slug = String::new();
  let mut last_was_dash = false;
  for ch in cleaned.chars() {
    if ch.is_alphanumeric() {
      slug.push(ch.to_ascii_lowercase());
      last_was_dash = false;
    } else if !last_was_dash && !slug.is_empty() {
      slug.push('-');
      last_was_dash = true;
    }
  }
  slug.trim_end_matches('-').to_string()
}

/// Récupère la jaquette officielle IGDB et la bannière depuis l'API publique ouverte Lutris (100% gratuite, sans clé API).
/// Visuels Lutris en essayant chaque variante du titre : c'est la source des
/// jeux absents de Steam (Valorant, Overwatch, Fall Guys, Rocket League).
pub async fn fetch_lutris_art_variants(
  client: &reqwest::Client,
  title: &str,
  executable: &str,
) -> Option<(String, String)> {
  for variant in title_variants(title, executable) {
    if let Some(found) = fetch_lutris_art(client, &variant).await {
      return Some(found);
    }
  }
  None
}

pub async fn fetch_lutris_art(client: &reqwest::Client, title: &str) -> Option<(String, String)> {
  let cleaned = clean_game_title(title);
  let slug = slugify(&cleaned);
  let norm_target = normalize(&cleaned);

  // 1. Essai direct par slug (ex: "hytale", "rocket-league", "fall-guys", "minecraft")
  if !slug.is_empty() {
    let direct_url = format!("https://lutris.net/api/games/{}", slug);
    if let Ok(res) = client.get(&direct_url).send().await {
      if res.status().is_success() {
        if let Ok(json) = res.json::<serde_json::Value>().await {
          // Le slug peut tomber sur un homonyme : on vérifie le nom rendu.
          let same = json["name"]
            .as_str()
            .map(|name| titles_match(name, &cleaned))
            .unwrap_or(false);
          let cover = json["coverart"].as_str().unwrap_or("").to_string();
          let banner = json["banner_url"].as_str().unwrap_or("").to_string();
          if same && !cover.is_empty() {
            return Some((cover, banner));
          }
        }
      }
    }
  }

  // 2. Recherche par mot-clé dans l'annuaire Lutris/IGDB
  let search_url = format!("https://lutris.net/api/games?search={}", urlencoding_simple(&cleaned));
  if let Ok(res) = client.get(&search_url).send().await {
    if res.status().is_success() {
      if let Ok(json) = res.json::<serde_json::Value>().await {
        if let Some(results) = json["results"].as_array() {
          // Passe 1 : correspondance exacte du nom
          for item in results {
            if let Some(name) = item["name"].as_str() {
              if normalize(name) == norm_target {
                let cover = item["coverart"].as_str().unwrap_or("").to_string();
                let banner = item["banner_url"].as_str().unwrap_or("").to_string();
                if !cover.is_empty() {
                  return Some((cover, banner));
                }
              }
            }
          }
          // Passe 2 : ressemblance du nom, jamais « le premier qui a une
          // jaquette ». Une recherche « osu » renvoie chez Lutris une liste de
          // jeux sans rapport, et on accrochait la jaquette du premier venu.
          for item in results {
            let Some(name) = item["name"].as_str() else {
              continue;
            };
            if !titles_match(name, &cleaned) {
              continue;
            }
            let cover = item["coverart"].as_str().unwrap_or("").to_string();
            let banner = item["banner_url"].as_str().unwrap_or("").to_string();
            if !cover.is_empty() {
              return Some((cover, banner));
            }
          }
        }
      }
    }
  }

  None
}

#[cfg(test)]
mod tests {
  use super::*;

  #[tokio::test]
  async fn test_lutris_hytale() {
    let client = reqwest::Client::builder()
      .user_agent("InterfaceConsole/0.1")
      .build()
      .unwrap();
    let res = fetch_lutris_art(&client, "Hytale Launcher").await;
    println!("\nTest Lutris Hytale Launcher => {:?}\n", res);
    assert!(res.is_some());
    let (cover, _banner) = res.unwrap();
    assert!(cover.contains("lutris.net"));
  }

  #[tokio::test]
  async fn test_scan_machine() {
    let custom = vec!["D:/Jeux".to_string()];
    let games = scan_all_games(&custom).await;
    println!("\n==========================================");
    println!("SCAN RESULTS : {} JEUX TROUVES", games.len());
    println!("==========================================");
    for g in &games {
      println!("- [{}] \"{}\" (AppID: {:?}) => Cover: {}", g.source, g.title, g.appid, g.cover);
    }
    println!("==========================================\n");
    assert!(!games.is_empty());
  }

  /// Outil de développement : montre ce que chaque source trouve sur cette
  /// machine. `cargo test -- --nocapture dump_sources`
  #[test]
  fn dump_sources() {
    for (name, list) in [
      ("Steam (manifestes)", scan_steam()),
      ("Steam (dossiers sans manifeste)", scan_steam_common()),
      ("Epic", scan_epic()),
      ("Registre", scan_registry()),
      ("Raccourcis", scan_shortcuts()),
    ] {
      println!("
--- {name} : {} ---", list.len());
      for game in list {
        println!("  {:<42} {}", game.title, game.executable);
      }
    }
  }

  /// Montre les dossiers de jeux reconnus tout seuls sur cette machine.
  #[test]
  fn dump_discovered_folders() {
    for folder in discover_game_folders() {
      println!("  {}", folder.display());
      for game in scan_custom_folder(&folder) {
        println!("      {:<40} {}", game.title, game.executable);
      }
    }
  }

  /// Le scan complet, dédoublonné : ce que l'utilisateur verra proposé.
  #[tokio::test]
  async fn dump_full_scan() {
    let games = scan_all_games(&[]).await;
    println!("
=== {} jeux ===", games.len());
    for game in games {
      println!("  {:<40} {:<9} {}", game.title, game.source, game.executable);
    }
  }
}
