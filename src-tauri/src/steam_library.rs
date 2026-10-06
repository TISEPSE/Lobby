//! Toute la bibliothèque Steam, par une connexion au compte — sans clé d'API.
//!
//! Steam n'a pas d'OAuth pour les applications tierces, et ne donne plus la
//! liste des jeux d'un profil sans être connecté. On procède donc comme pour
//! Epic : une fenêtre ouvre la **page de connexion officielle** de Steam (QR
//! code de l'application mobile, ou identifiants), puis on lit la liste des
//! jeux avec la session de cette fenêtre.
//!
//! La session Steam donne un accès complet au compte sur le web : elle est
//! traitée comme le secret le plus sensible de l'application.
//! - fenêtre en **navigation privée** : rien n'est écrit sur le disque par le
//!   navigateur, tout disparaît à la fermeture ;
//! - la fenêtre ne peut aller que sur les domaines de Steam, et n'ouvre aucune
//!   pop-up ;
//! - la session (cookie et jeton d'accès) est lue **une seule fois, en
//!   mémoire**, envoyée uniquement aux serveurs de Steam (`api.steampowered.com`,
//!   `store.steampowered.com`, `steamcommunity.com`) en HTTPS, puis **effacée** ;
//!   elle n'est jamais enregistrée, jamais transmise à l'interface, jamais
//!   journalisée ;
//! - seule la liste des jeux est gardée, **chiffrée** (`secure_store`).

use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use tauri::{Emitter, Manager};

use crate::secure_store;

const LOGIN_WINDOW: &str = "steam-login";
/// Après connexion, Steam renvoie vers la page « Jeux » du compte connecté.
/// Page de connexion seule : après connexion, Steam renvoie vers l'accueil de
/// la communauté — navigation qu'on **intercepte** sans la charger.
const LOGIN_URL: &str = "https://steamcommunity.com/login/home/?goto=";
/// Seuls domaines où la fenêtre a le droit d'aller.
const ALLOWED_HOSTS: [&str; 3] = ["steamcommunity.com", "steampowered.com", "steamstatic.com"];

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct OwnedGame {
  pub appid: String,
  pub name: String,
  /// Temps de jeu total, en minutes.
  pub playtime: u64,
  /// Dernière partie, en secondes depuis 1970 ; 0 si jamais joué.
  pub last_played: u64,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct OwnedLibrary {
  pub steamid: String,
  /// Date de la récupération, en secondes depuis 1970.
  pub fetched_at: u64,
  pub games: Vec<OwnedGame>,
}

#[derive(Serialize, Clone, Debug)]
struct Outcome {
  ok: bool,
  message: String,
}

fn library_path(data_dir: &Path) -> PathBuf {
  data_dir.join("steam").join("library.bin")
}

/// Bibliothèque récupérée à la dernière connexion ; `None` sinon.
pub fn read_library(data_dir: &Path) -> Result<Option<OwnedLibrary>, String> {
  match secure_store::read(&library_path(data_dir))? {
    Some(bytes) => serde_json::from_slice(&bytes).map(Some).map_err(|e| e.to_string()),
    None => Ok(None),
  }
}

pub fn forget_library(data_dir: &Path) {
  let _ = std::fs::remove_file(library_path(data_dir));
}

fn allowed(url: &tauri::Url) -> bool {
  url.scheme() == "https"
    && url
      .host_str()
      .is_some_and(|host| ALLOWED_HOSTS.iter().any(|allowed| host == *allowed || host.ends_with(&format!(".{allowed}"))))
}

/// Ouvre la page de connexion officielle de Steam, en navigation privée.
pub fn open_login(app: &tauri::AppHandle) -> Result<(), String> {
  if let Some(existing) = app.get_webview_window(LOGIN_WINDOW) {
    let _ = existing.set_focus();
    return Ok(());
  }
  let data_dir = app.path().app_data_dir().map_err(|e| e.to_string())?;
  let url = LOGIN_URL.parse().map_err(|e| format!("Adresse invalide : {e}"))?;
  let done = Arc::new(AtomicBool::new(false));
  let done_on_load = done.clone();
  let handle = app.clone();
  log::info!("Steam : ouverture de la page de connexion");

  let window = tauri::WebviewWindowBuilder::new(app, LOGIN_WINDOW, tauri::WebviewUrl::External(url))
    .title("Connexion à Steam")
    .inner_size(1000.0, 820.0)
    .center()
    .always_on_top(true)
    .focused(true)
    // Navigation privée : cookies et cache en mémoire seulement, effacés à
    // la fermeture de la fenêtre.
    .incognito(true)
    // Rien hors de Steam, et en HTTPS.
    // Rien hors de Steam, et en HTTPS. Et dès que Steam quitte la page de
    // connexion (connexion réussie), on **bloque** la page suivante au lieu
    // de l'afficher, on cache la fenêtre, et la liste se lit en arrière-plan :
    // rien d'autre ne s'ouvre à l'écran.
    .on_navigation(move |url| {
      if !allowed(url) {
        log::warn!("Steam : navigation bloquée vers {}", url.host_str().unwrap_or("?"));
        return false;
      }
      let leaving_login = url.host_str() == Some("steamcommunity.com") && !url.path().starts_with("/login");
      if !leaving_login {
        return true;
      }
      if done_on_load.swap(true, Ordering::SeqCst) {
        return false;
      }
      log::info!("Steam : connecté, lecture de la bibliothèque");
      let app = handle.clone();
      let dir = data_dir.clone();
      // Les cookies ne se lisent pas depuis un gestionnaire d'événement sous
      // Windows (blocage de WebView2) : tâche à part.
      tauri::async_runtime::spawn(async move {
        let Some(window) = app.get_webview_window(LOGIN_WINDOW) else {
          return;
        };
        let _ = window.hide();
        let outcome = match fetch_with_session(&window, &dir).await {
          Ok(count) => Outcome { ok: true, message: count.to_string() },
          Err(error) => {
            log::warn!("Steam : bibliothèque illisible : {error}");
            Outcome { ok: false, message: error }
          }
        };
        // Fermer la fenêtre privée efface la session : plus aucune trace.
        let _ = window.destroy();
        let _ = app.emit("steam-library", outcome);
      });
      false
    })
    // Aucune pop-up : la connexion Steam n'en a pas besoin.
    .on_new_window(|_, _| tauri::webview::NewWindowResponse::Deny)
    .build()
    .map_err(|e| format!("Fenêtre de connexion impossible : {e}"))?;

  let handle = app.clone();
  window.on_window_event(move |event| {
    if let tauri::WindowEvent::Destroyed = event {
      if !done.load(Ordering::SeqCst) {
        log::info!("Steam : fenêtre fermée sans connexion");
        let _ = handle.emit("steam-library", Outcome { ok: false, message: "connexion annulée".into() });
      }
    }
  });
  Ok(())
}

/// Lit la session de la fenêtre, récupère la liste des jeux, puis efface la
/// session de la mémoire. Rend le nombre de jeux.
async fn fetch_with_session(window: &tauri::WebviewWindow, data_dir: &Path) -> Result<usize, String> {
  let community: tauri::Url = "https://steamcommunity.com/".parse().map_err(|_| "adresse invalide")?;
  let store: tauri::Url = "https://store.steampowered.com/".parse().map_err(|_| "adresse invalide")?;
  let community_cookies = window.cookies_for_url(community).map_err(|e| format!("session illisible : {e}"))?;
  let store_cookies = window.cookies_for_url(store).unwrap_or_default();

  // `steamLoginSecure` = `<steamid>||<jeton d'accès>`, encodé pour l'URL.
  let login = community_cookies
    .iter()
    .chain(store_cookies.iter())
    .find(|c| c.name() == "steamLoginSecure")
    .map(|c| c.value().replace("%7C", "|").replace("%7c", "|"))
    .ok_or("pas de session Steam après la connexion")?;
  let (steamid, token) = login.split_once("||").ok_or("session Steam illisible")?;
  let steamid = steamid.to_string();
  if steamid.len() != 17 || !steamid.bytes().all(|b| b.is_ascii_digit()) {
    return Err("session Steam illisible".into());
  }
  let token = token.to_string();
  secure_store::wipe(login);

  let header = |cookies: &[tauri::webview::Cookie<'static>]| {
    cookies.iter().map(|c| format!("{}={}", c.name(), c.value())).collect::<Vec<_>>().join("; ")
  };
  let community_header = header(&community_cookies);
  let store_header = header(&store_cookies);
  drop(community_cookies);
  drop(store_cookies);

  let result = fetch_games(&steamid, &token, &community_header, &store_header).await;
  // La session ne sert plus : on l'efface de la mémoire avant toute suite.
  secure_store::wipe(token);
  secure_store::wipe(community_header);
  secure_store::wipe(store_header);
  let games = result?;

  let library = OwnedLibrary {
    steamid,
    fetched_at: std::time::SystemTime::now()
      .duration_since(std::time::UNIX_EPOCH)
      .map(|d| d.as_secs())
      .unwrap_or(0),
    games,
  };
  let bytes = serde_json::to_vec(&library).map_err(|e| e.to_string())?;
  secure_store::write(&library_path(data_dir), &bytes)?;
  Ok(library.games.len())
}

fn client() -> Result<reqwest::Client, String> {
  reqwest::Client::builder()
    .user_agent("Mozilla/5.0 InterfaceConsole/0.1")
    .https_only(true)
    .build()
    .map_err(|e| e.to_string())
}

/// Plusieurs voies, de la plus sûre à la plus fragile. Steam change ses pages :
/// la liste n'est plus écrite dans la page « Jeux », elle est chargée ensuite
/// par l'API officielle avec le jeton de la session.
async fn fetch_games(
  steamid: &str,
  session_token: &str,
  community_header: &str,
  store_header: &str,
) -> Result<Vec<OwnedGame>, String> {
  let client = client()?;

  // 1. API officielle, avec le jeton de la session (celui du cookie).
  match owned_games_api(&client, steamid, session_token).await {
    Ok(games) if !games.is_empty() => return Ok(games),
    Ok(_) => log::warn!("Steam : API (jeton de session) : liste vide"),
    Err(e) => log::warn!("Steam : API (jeton de session) : {e}"),
  }

  // 2. Jeton délivré par la boutique à la session connectée.
  if !store_header.is_empty() {
    match store_webapi_token(&client, store_header).await {
      Ok(token) => {
        let result = owned_games_api(&client, steamid, &token).await;
        secure_store::wipe(token);
        match result {
          Ok(games) if !games.is_empty() => return Ok(games),
          Ok(_) => log::warn!("Steam : API (jeton boutique) : liste vide"),
          Err(e) => log::warn!("Steam : API (jeton boutique) : {e}"),
        }
      }
      Err(e) => log::warn!("Steam : jeton boutique indisponible : {e}"),
    }
  }

  // 3. Ancienne page « Jeux », où la liste était écrite dans le HTML.
  match games_page(&client, steamid, community_header).await {
    Ok(games) if !games.is_empty() => return Ok(games),
    Ok(_) => log::warn!("Steam : page Jeux : liste vide"),
    Err(e) => log::warn!("Steam : page Jeux : {e}"),
  }

  // 4. Identifiants des jeux possédés, sans noms (complétés par les fiches).
  if !store_header.is_empty() {
    match owned_app_ids(&client, store_header).await {
      Ok(games) if !games.is_empty() => return Ok(games),
      Ok(_) => log::warn!("Steam : boutique : aucun jeu possédé"),
      Err(e) => log::warn!("Steam : boutique : {e}"),
    }
  }
  Err("Steam n'a pas donné la liste des jeux".into())
}

/// `IPlayerService/GetOwnedGames` avec un jeton d'accès (pas de clé d'API).
async fn owned_games_api(client: &reqwest::Client, steamid: &str, token: &str) -> Result<Vec<OwnedGame>, String> {
  let response = client
    .get("https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/")
    .query(&[
      ("access_token", token),
      ("steamid", steamid),
      ("include_appinfo", "1"),
      ("include_played_free_games", "1"),
      ("format", "json"),
    ])
    .send()
    .await
    .map_err(|_| "Steam injoignable".to_string())?;
  let status = response.status();
  if !status.is_success() {
    return Err(format!("réponse {}", status.as_u16()));
  }
  let body: serde_json::Value = response.json().await.map_err(|e| e.to_string())?;
  Ok(parse_owned_games(&body))
}

fn parse_owned_games(body: &serde_json::Value) -> Vec<OwnedGame> {
  body["response"]["games"]
    .as_array()
    .map(|list| {
      list
        .iter()
        .filter_map(|game| {
          Some(OwnedGame {
            appid: game["appid"].as_u64()?.to_string(),
            name: game["name"].as_str().unwrap_or_default().to_string(),
            playtime: game["playtime_forever"].as_u64().unwrap_or(0),
            last_played: game["rtime_last_played"].as_u64().unwrap_or(0),
          })
        })
        .collect()
    })
    .unwrap_or_default()
}

/// Jeton d'API que la boutique donne à une session connectée.
async fn store_webapi_token(client: &reqwest::Client, store_header: &str) -> Result<String, String> {
  let body: serde_json::Value = client
    .get("https://store.steampowered.com/pointssummary/ajaxgetasyncconfig")
    .header(reqwest::header::COOKIE, store_header)
    .send()
    .await
    .map_err(|_| "Steam injoignable".to_string())?
    .json()
    .await
    .map_err(|e| e.to_string())?;
  body["data"]["webapi_token"]
    .as_str()
    .filter(|t| !t.is_empty())
    .map(str::to_string)
    .ok_or_else(|| "pas de jeton (session non reconnue par la boutique)".into())
}

/// Ancienne page « Jeux » : la liste dans l'attribut `data-profile-gameslist`.
async fn games_page(client: &reqwest::Client, steamid: &str, community_header: &str) -> Result<Vec<OwnedGame>, String> {
  let response = client
    .get(format!("https://steamcommunity.com/profiles/{steamid}/games/?tab=all&l=french"))
    .header(reqwest::header::COOKIE, community_header)
    .send()
    .await
    .map_err(|_| "Steam injoignable".to_string())?;
  // Diagnostic sans secret : où l'on est arrivé, et combien de texte.
  let landed = response.url().path().to_string();
  let html = response.text().await.map_err(|e| e.to_string())?;
  log::info!("Steam : page Jeux reçue ({} octets, chemin {landed})", html.len());
  parse_games_page(&html)
}

/// Boutique : identifiants des jeux possédés (`rgOwnedApps`), sans noms.
async fn owned_app_ids(client: &reqwest::Client, store_header: &str) -> Result<Vec<OwnedGame>, String> {
  let body: serde_json::Value = client
    .get("https://store.steampowered.com/dynamicstore/userdata/")
    .header(reqwest::header::COOKIE, store_header)
    .send()
    .await
    .map_err(|_| "Steam injoignable".to_string())?
    .json()
    .await
    .map_err(|e| e.to_string())?;
  Ok(
    body["rgOwnedApps"]
      .as_array()
      .map(|list| {
        list
          .iter()
          .filter_map(|id| id.as_u64())
          .map(|id| OwnedGame { appid: id.to_string(), name: String::new(), playtime: 0, last_played: 0 })
          .collect()
      })
      .unwrap_or_default(),
  )
}

fn parse_games_page(html: &str) -> Result<Vec<OwnedGame>, String> {
  let marker = "data-profile-gameslist=\"";
  let start = html.find(marker).ok_or("liste des jeux introuvable sur la page Steam")? + marker.len();
  let end = html[start..].find('"').ok_or("liste des jeux tronquée")? + start;
  let json = unescape_html(&html[start..end]);
  let data: serde_json::Value = serde_json::from_str(&json).map_err(|e| format!("liste illisible : {e}"))?;
  let games = data["rgGames"].as_array().ok_or("liste des jeux vide")?;
  Ok(
    games
      .iter()
      .filter_map(|game| {
        Some(OwnedGame {
          appid: game["appid"].as_u64()?.to_string(),
          name: game["name"].as_str().unwrap_or_default().to_string(),
          playtime: game["playtime_forever"].as_u64().unwrap_or(0),
          last_played: game["rtime_last_played"].as_u64().unwrap_or(0),
        })
      })
      .collect(),
  )
}

fn unescape_html(value: &str) -> String {
  value
    .replace("&quot;", "\"")
    .replace("&#39;", "'")
    .replace("&lt;", "<")
    .replace("&gt;", ">")
    .replace("&amp;", "&")
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn reads_the_games_list_from_the_page() {
    let html = r#"<template id="gameslist_config" data-profile-gameslist="{&quot;rgGames&quot;:[{&quot;appid&quot;:311210,&quot;name&quot;:&quot;Call of Duty&#39;s Black Ops III&quot;,&quot;playtime_forever&quot;:1200,&quot;rtime_last_played&quot;:1791214058}]}"></template>"#;
    let games = parse_games_page(html).unwrap();
    assert_eq!(games.len(), 1);
    assert_eq!(games[0].appid, "311210");
    assert_eq!(games[0].name, "Call of Duty's Black Ops III");
    assert_eq!(games[0].playtime, 1200);
  }

  #[test]
  fn only_steam_over_https_is_allowed() {
    assert!(allowed(&"https://steamcommunity.com/login".parse().unwrap()));
    assert!(allowed(&"https://store.steampowered.com/".parse().unwrap()));
    assert!(allowed(&"https://login.steampowered.com/jwt".parse().unwrap()));
    assert!(!allowed(&"http://steamcommunity.com/".parse().unwrap()));
    assert!(!allowed(&"https://steamcommunity.com.evil.example/".parse().unwrap()));
    assert!(!allowed(&"https://evil-steampowered.com/".parse().unwrap()));
  }
}

#[cfg(test)]
mod dump {
  /// `cargo test dump_library -- --ignored --nocapture` : liste enregistrée.
  #[test]
  #[ignore]
  fn dump_library() {
    let dir = std::path::PathBuf::from(std::env::var("APPDATA").unwrap()).join("fr.interface.console");
    let lib = super::read_library(&dir).unwrap().expect("aucune liste");
    let named = lib.games.iter().filter(|g| !g.name.is_empty()).count();
    println!("{} jeux ({} avec un nom)", lib.games.len(), named);
    for g in lib.games.iter().take(5) {
      println!("  {} {}", g.appid, g.name);
    }
  }
}
