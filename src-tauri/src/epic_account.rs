//! Compte Epic Games : connexion, puis temps de jeu de chaque jeu.
//!
//! Epic ne garde pas le temps de jeu sur le disque : il faut le demander à ses
//! serveurs, avec un jeton du compte. On suit la méthode des launchers libres
//! (Legendary, Heroic) :
//!
//! 1. une fenêtre ouvre la **page de connexion officielle** d'Epic — l'interface
//!    ne voit jamais le mot de passe ;
//! 2. après connexion, Epic affiche un code d'autorisation (page JSON) ; la
//!    fenêtre le relit et le transmet en naviguant vers une adresse fictive
//!    qu'on intercepte ;
//! 3. le code est échangé contre un jeton, et **seul le jeton de
//!    renouvellement** est gardé, dans le dossier de données.
//!
//! Le couple client id / secret est celui du launcher Epic lui-même, publié
//! par ces projets libres : ce n'est pas une clé propre à l'utilisateur.

use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::Arc;
use tauri::{Emitter, Manager};

const CLIENT_ID: &str = "34a02cf8f4414e29b15921876da36f9a";
const CLIENT_SECRET: &str = "daafbccc737745039dffe53d94fc76cf";
const TOKEN_URL: &str = "https://account-public-service-prod03.ol.epicgames.com/account/api/oauth/token";
const PLAYTIME_URL: &str = "https://library-service.live.use1a.on.epicgames.com/library/api/public/playtime/account";
const LIBRARY_URL: &str = "https://library-service.live.use1a.on.epicgames.com/library/api/public/items";
const CATALOG_URL: &str = "https://catalog-public-service-prod06.ol.epicgames.com/catalog/api/shared/namespace";
/// Requêtes de catalogue en parallèle : une par jeu, soit 37 s pour 688 fiches à
/// 8 à la fois.
const CATALOG_PARALLEL: usize = 16;
/// Adresse fictive vers laquelle la fenêtre de connexion renvoie le code : on
/// l'intercepte avant qu'elle ne parte sur le réseau.
const CODE_HOST: &str = "epic-code.invalid";
const LOGIN_WINDOW: &str = "epic-login";
/// Préfixe des pop-ups ouvertes par la page Epic (« Autres méthodes de
/// connexion » : Google, Xbox, PlayStation, Steam…), numérotées.
const POPUP_PREFIX: &str = "epic-popup-";
/// Adresse factice vers laquelle une pop-up de fournisseur navigue quand sa
/// page appelle `window.close()` : on l'intercepte pour détruire la fenêtre.
const POPUP_CLOSE_HOST: &str = "epic-popup-close.invalid";
static POPUP_COUNT: AtomicUsize = AtomicUsize::new(0);

/// Ce qui est gardé sur le disque : de quoi renouveler la session, rien d'autre.
#[derive(Serialize, Deserialize, Clone, Debug)]
struct Session {
  account_id: String,
  display_name: String,
  refresh_token: String,
}

#[derive(Serialize, Clone, Debug)]
pub struct EpicPlay {
  /// Nom interne du jeu (`AppName` des manifestes Epic), en minuscules.
  pub app_name: String,
  pub minutes: u64,
}

/// Un jeu de la bibliothèque Epic, installé ou non.
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct EpicGame {
  /// Nom interne (`AppName`), en minuscules : l'identifiant `epic-<appname>`.
  pub app_name: String,
  pub title: String,
  /// Jaquette verticale du catalogue (`DieselGameBoxTall`), ou vide.
  pub cover: String,
  /// Image large (`DieselGameBox`), pour le fond.
  pub hero: String,
}

#[derive(Serialize, Clone, Debug)]
pub struct EpicAccount {
  pub account_id: String,
  pub display_name: String,
  pub playtime: Vec<EpicPlay>,
  /// La bibliothèque connue du cache (jeux seulement, sans DLC).
  pub library: Vec<EpicGame>,
  /// Fiches pas encore lues : `epic_library` les demande à part, sans bloquer
  /// la connexion.
  pub missing: usize,
}

/// Fiche de catalogue gardée en cache : `None` pour ce qui n'est pas un jeu
/// (DLC, extension), pour ne pas le redemander à chaque lecture.
type CatalogCache = std::collections::BTreeMap<String, Option<EpicGame>>;

fn catalog_path(data_dir: &Path) -> PathBuf {
  data_dir.join("epic.catalog")
}

/// Une entrée de la bibliothèque : de quoi interroger le catalogue.
struct LibraryRecord {
  app_name: String,
  namespace: String,
  catalog_id: String,
}

/// Toutes les pages de la bibliothèque (100 éléments par page).
async fn library_records(token: &str) -> Result<Vec<LibraryRecord>, String> {
  let client = client()?;
  let mut records = Vec::new();
  let mut cursor = String::new();
  for _ in 0..50 {
    let mut request = client.get(LIBRARY_URL).bearer_auth(token).query(&[("includeMetadata", "true")]);
    if !cursor.is_empty() {
      request = request.query(&[("cursor", cursor.as_str())]);
    }
    let body: serde_json::Value = request
      .send()
      .await
      .map_err(|e| format!("Epic injoignable : {e}"))?
      .json()
      .await
      .map_err(|e| format!("Bibliothèque illisible : {e}"))?;
    for record in body["records"].as_array().into_iter().flatten() {
      // Les bacs à sable privés sont des versions de développement.
      if record["recordType"] != "APPLICATION" || record["sandboxType"] == "PRIVATE" {
        continue;
      }
      let (Some(app), Some(ns), Some(id)) = (
        record["appName"].as_str(),
        record["namespace"].as_str(),
        record["catalogItemId"].as_str(),
      ) else {
        continue;
      };
      records.push(LibraryRecord { app_name: app.to_string(), namespace: ns.to_string(), catalog_id: id.to_string() });
    }
    match body["responseMetadata"]["nextCursor"].as_str() {
      Some(next) if !next.is_empty() && next != cursor => cursor = next.to_string(),
      _ => break,
    }
  }
  Ok(records)
}

/// Fiche de catalogue d'un élément : titre, jaquettes, et si c'est un jeu.
/// `None` si Epic n'a pas répondu : rien à retenir, on redemandera. `Some(None)`
/// pour ce qui n'est pas un jeu. Sans cette différence, une requête ratée
/// classait le jeu « pas un jeu » pour toujours dans le cache.
async fn catalog_entry(token: &str, record: &LibraryRecord) -> Option<Option<EpicGame>> {
  let response = client()
    .ok()?
    .get(format!("{CATALOG_URL}/{}/bulk/items", record.namespace))
    .bearer_auth(token)
    .query(&[("id", record.catalog_id.as_str()), ("country", "FR"), ("locale", "fr")])
    .send()
    .await
    .ok()?;
  if !response.status().is_success() {
    return None;
  }
  let body: serde_json::Value = response.json().await.ok()?;
  let item = &body[&record.catalog_id];
  if !item.is_object() {
    return None;
  }
  let is_game = item["categories"]
    .as_array()
    .is_some_and(|list| list.iter().any(|c| c["path"] == "games"));
  if !is_game || item["mainGameItem"].is_object() {
    return Some(None);
  }
  let image = |kind: &str| {
    item["keyImages"]
      .as_array()
      .and_then(|list| list.iter().find(|img| img["type"] == kind))
      .and_then(|img| img["url"].as_str())
      .unwrap_or_default()
      .to_string()
  };
  Some(Some(EpicGame {
    app_name: record.app_name.to_lowercase(),
    title: item["title"].as_str().unwrap_or(&record.app_name).to_string(),
    cover: image("DieselGameBoxTall"),
    hero: image("DieselGameBox"),
  }))
}

/// Bibliothèque : la liste vient d'Epic à chaque lecture, les fiches du
/// catalogue du cache (chiffré). `fetch` demande celles qui manquent, plusieurs
/// à la fois ; sans lui, on rend ce qui est connu et le nombre de fiches à lire.
async fn read_library(data_dir: &Path, token: &str, fetch: bool) -> Result<(Vec<EpicGame>, usize), String> {
  let records = library_records(token).await?;
  let mut cache: CatalogCache = crate::secure_store::read(&catalog_path(data_dir))
    .ok()
    .flatten()
    .and_then(|bytes| serde_json::from_slice(&bytes).ok())
    .unwrap_or_default();

  let missing: Vec<&LibraryRecord> = records.iter().filter(|r| !cache.contains_key(&r.app_name)).collect();
  let to_fetch: &[&LibraryRecord] = if fetch { &missing } else { &[] };
  for chunk in to_fetch.chunks(CATALOG_PARALLEL) {
    let tasks: Vec<_> = chunk
      .iter()
      .map(|record| {
        let token = token.to_string();
        let record = LibraryRecord {
          app_name: record.app_name.clone(),
          namespace: record.namespace.clone(),
          catalog_id: record.catalog_id.clone(),
        };
        tauri::async_runtime::spawn(async move { (record.app_name.clone(), catalog_entry(&token, &record).await) })
      })
      .collect();
    for task in tasks {
      if let Ok((app, Some(entry))) = task.await {
        cache.insert(app, entry);
      }
    }
  }
  if !to_fetch.is_empty() {
    if let Ok(bytes) = serde_json::to_vec(&cache) {
      let _ = crate::secure_store::write(&catalog_path(data_dir), &bytes);
    }
  }

  let unread = records.iter().filter(|r| !cache.contains_key(&r.app_name)).count();
  let mut seen = std::collections::BTreeSet::new();
  let games = records
    .iter()
    .filter_map(|r| cache.get(&r.app_name).cloned().flatten())
    .filter(|game| seen.insert(game.app_name.clone()))
    .collect();
  Ok((games, unread))
}

/// Résultat de la connexion, envoyé à l'interface (événement `epic-login`).
#[derive(Serialize, Clone, Debug)]
struct LoginOutcome {
  ok: bool,
  message: String,
}

#[derive(Deserialize)]
struct TokenResponse {
  access_token: String,
  refresh_token: String,
  account_id: String,
  #[serde(rename = "displayName", default)]
  display_name: String,
}

/// Session chiffrée (DPAPI sous Windows, voir `secure_store`).
fn session_path(data_dir: &Path) -> PathBuf {
  data_dir.join("epic.session")
}

/// Ancien emplacement, en clair : converti puis supprimé à la première lecture.
fn legacy_path(data_dir: &Path) -> PathBuf {
  data_dir.join("epic.json")
}

fn load_session(data_dir: &Path) -> Result<Option<Session>, String> {
  if let Ok(text) = fs::read_to_string(legacy_path(data_dir)) {
    let session: Session = serde_json::from_str(&text).map_err(|e| e.to_string())?;
    store_session(data_dir, &session)?;
    let _ = fs::remove_file(legacy_path(data_dir));
    log::info!("Epic : session convertie au format chiffré");
    return Ok(Some(session));
  }
  match crate::secure_store::read(&session_path(data_dir))? {
    Some(bytes) => serde_json::from_slice(&bytes).map(Some).map_err(|e| e.to_string()),
    None => Ok(None),
  }
}

fn store_session(data_dir: &Path, session: &Session) -> Result<(), String> {
  let text = serde_json::to_vec(session).map_err(|e| e.to_string())?;
  crate::secure_store::write(&session_path(data_dir), &text)
}

fn client() -> Result<reqwest::Client, String> {
  reqwest::Client::builder()
    .user_agent("InterfaceConsole/0.1")
    .build()
    .map_err(|e| e.to_string())
}

async fn request_token(form: &[(&str, &str)]) -> Result<TokenResponse, String> {
  let response = client()?
    .post(TOKEN_URL)
    .basic_auth(CLIENT_ID, Some(CLIENT_SECRET))
    .form(form)
    .send()
    .await
    .map_err(|e| format!("Epic injoignable : {e}"))?;
  if !response.status().is_success() {
    return Err(format!("Epic a refusé la connexion ({})", response.status()));
  }
  response.json().await.map_err(|e| format!("Réponse d'Epic illisible : {e}"))
}

fn save(data_dir: &Path, token: &TokenResponse, previous_name: &str) -> Result<Session, String> {
  let session = Session {
    account_id: token.account_id.clone(),
    display_name: if token.display_name.is_empty() {
      previous_name.to_string()
    } else {
      token.display_name.clone()
    },
    refresh_token: token.refresh_token.clone(),
  };
  store_session(data_dir, &session)?;
  Ok(session)
}

/// Échange le code d'autorisation contre un jeton, et garde la session.
async fn finish_login(data_dir: PathBuf, code: String) -> Result<String, String> {
  let token = request_token(&[
    ("grant_type", "authorization_code"),
    ("code", &code),
    ("token_type", "eg1"),
  ])
  .await?;
  let session = save(&data_dir, &token, "")?;
  Ok(session.display_name)
}

/// Ouvre la page de connexion d'Epic dans une fenêtre à part.
pub fn open_login(app: &tauri::AppHandle) -> Result<(), String> {
  if let Some(existing) = app.get_webview_window(LOGIN_WINDOW) {
    let _ = existing.set_focus();
    return Ok(());
  }
  let data_dir = app.path().app_data_dir().map_err(|e| e.to_string())?;
  let redirect = format!("https://www.epicgames.com/id/api/redirect?clientId={CLIENT_ID}&responseType=code");
  let login = format!(
    "https://www.epicgames.com/id/login?redirectUrl={}",
    urlencode(&redirect)
  );
  let url = login.parse().map_err(|e| format!("Adresse invalide : {e}"))?;
  let handle = app.clone();
  // Vrai dès que le code est reçu : fermer la fenêtre avant ne doit pas laisser
  // l'interface sur « Connexion… ».
  let done = Arc::new(AtomicBool::new(false));
  let done_on_code = done.clone();
  log::info!("Epic : ouverture de la page de connexion");

  let window = tauri::WebviewWindowBuilder::new(app, LOGIN_WINDOW, tauri::WebviewUrl::External(url))
    .title("Connexion à Epic Games")
    .inner_size(1100.0, 820.0)
    .center()
    .always_on_top(true)
    .focused(true)
    // La page finale affiche le code en JSON. Le visualiseur JSON de WebView2
    // ajoute son propre texte autour : on ne parse pas la page, on y cherche
    // le code, et on réessaie quelques secondes le temps qu'elle s'affiche.
    .on_page_load(|window, payload| {
      if payload.event() != tauri::webview::PageLoadEvent::Finished {
        return;
      }
      log::info!("Epic : page chargée {}", payload.url().path());
      if payload.url().path().starts_with("/id/api/redirect") {
        let _ = window.eval(&format!(
          r#"(() => {{
            // La page peut se charger plusieurs fois : un seul envoi du code.
            if (window.__epicCodeSent) return;
            let tries = 0;
            const look = () => {{
              const text = (document.body && document.body.innerText) || document.documentElement.textContent || '';
              const found = text.match(/"authorizationCode"\s*:\s*"([^"]+)"/);
              if (found) {{
                window.__epicCodeSent = true;
                location.replace('https://{CODE_HOST}/?code=' + encodeURIComponent(found[1]));
              }} else if (++tries < 40) {{
                setTimeout(look, 250);
              }} else {{
                location.replace('https://{CODE_HOST}/?error=' + encodeURIComponent(text.slice(0, 200)));
              }}
            }};
            look();
          }})();"#
        ));
      }
    })
    // « Autres méthodes de connexion » ouvre le fournisseur dans une pop-up
    // (`window.open`), que Tauri refuse par défaut : rien ne se passait. On
    // la crée nous-mêmes, avec les caractéristiques demandées par la page —
    // même environnement WebView2, donc `window.opener` fonctionne et la
    // pop-up peut rendre la main à Epic une fois la connexion faite.
    .on_new_window({
      let app = app.clone();
      move |url, features| {
        let label = format!("{POPUP_PREFIX}{}", POPUP_COUNT.fetch_add(1, Ordering::SeqCst));
        let label_for_close = label.clone();
        log::info!("Epic : pop-up ouverte {}", url.host_str().unwrap_or("?"));
        let built = tauri::WebviewWindowBuilder::new(
          &app,
          label,
          tauri::WebviewUrl::External("about:blank".parse().expect("adresse fixe")),
        )
        .window_features(features)
        .title("Connexion")
        .center()
        .always_on_top(true)
        .focused(true)
        // Toujours fermable à la main, avec sa barre de titre.
        .decorations(true)
        .closable(true)
        // Le fournisseur (Steam, Google…) ferme sa pop-up par `window.close()`
        // une fois la connexion faite ; Tauri ne détruisait pas la fenêtre, qui
        // restait blanche au-dessus de tout jusqu'à la fin de la connexion
        // Epic. On remplace `close()` par une navigation vers une adresse
        // factice, interceptée ci-dessous.
        .initialization_script(&format!(
          "window.close = () => location.replace('https://{POPUP_CLOSE_HOST}/');"
        ))
        .on_navigation({
          let app = app.clone();
          let label = label_for_close.clone();
          move |url| {
            if url.host_str() != Some(POPUP_CLOSE_HOST) {
              return true;
            }
            log::info!("Epic : pop-up fermée par le fournisseur");
            let app = app.clone();
            let label = label.clone();
            // Pas de destruction depuis le gestionnaire de navigation lui-même.
            tauri::async_runtime::spawn(async move {
              if let Some(window) = app.get_webview_window(&label) {
                let _ = window.destroy();
              }
            });
            false
          }
        })
        .on_document_title_changed(|window, title| {
          let _ = window.set_title(&title);
        })
        .build();
        match built {
          Ok(window) => tauri::webview::NewWindowResponse::Create { window },
          Err(error) => {
            log::warn!("Epic : pop-up impossible : {error}");
            tauri::webview::NewWindowResponse::Deny
          }
        }
      }
    })
    .on_navigation(move |url| {
      if url.host_str() != Some(CODE_HOST) {
        return true;
      }
      let value = |name: &str| {
        url
          .query_pairs()
          .find(|(key, _)| key == name)
          .map(|(_, value)| value.to_string())
          .unwrap_or_default()
      };
      let code = value("code");
      let page = value("error");
      // La page finale d'Epic peut se charger plusieurs fois et renvoyer le
      // même code : un code ne s'échange qu'une fois, les suivants étaient
      // refusés (400) et affichaient des erreurs alors que la connexion avait
      // réussi. Seul le premier compte.
      if done_on_code.swap(true, Ordering::SeqCst) {
        log::info!("Epic : code en double ignoré");
        return false;
      }
      log::info!("Epic : code reçu ({} caractères)", code.len());
      let app = handle.clone();
      let dir = data_dir.clone();
      tauri::async_runtime::spawn(async move {
        let outcome = if code.is_empty() {
          log::warn!("Epic : pas de code sur la page finale : {page}");
          LoginOutcome { ok: false, message: "Epic n'a pas donné de code de connexion".into() }
        } else {
          match finish_login(dir, code).await {
            Ok(name) => LoginOutcome { ok: true, message: name },
            Err(error) => {
              log::warn!("Epic : échange du code refusé : {error}");
              LoginOutcome { ok: false, message: error }
            }
          }
        };
        // Connexion terminée : on ferme tout, fenêtre de connexion et pop-ups
        // des fournisseurs (Steam, Google…) restées ouvertes.
        close_login_windows(&app);
        let _ = app.emit("epic-login", outcome);
      });
      false
    })
    .build()
    .map_err(|e| format!("Fenêtre de connexion impossible : {e}"))?;

  // Fenêtre fermée à la main, sans code : on le dit, l'interface se débloque.
  let handle = app.clone();
  window.on_window_event(move |event| {
    if let tauri::WindowEvent::Destroyed = event {
      // Les pop-ups des fournisseurs n'ont plus de raison d'être (la fenêtre
      // de connexion, elle, est déjà en train de se fermer).
      close_popups(&handle);
      if !done.load(Ordering::SeqCst) {
        log::info!("Epic : fenêtre fermée sans connexion");
        let _ = handle.emit(
          "epic-login",
          LoginOutcome { ok: false, message: "connexion annulée".into() },
        );
      }
    }
  });
  Ok(())
}

/// Ferme la fenêtre de connexion et toutes les pop-ups de fournisseurs.
/// `destroy` plutôt que `close` : une page peut retenir sa fermeture.
fn close_login_windows(app: &tauri::AppHandle) {
  close_popups(app);
  if let Some(window) = app.get_webview_window(LOGIN_WINDOW) {
    let _ = window.destroy();
  }
}

fn close_popups(app: &tauri::AppHandle) {
  for (label, window) in app.webview_windows() {
    if label.starts_with(POPUP_PREFIX) {
      let _ = window.destroy();
    }
  }
}

/// Compte connecté et temps de jeu ; `Ok(None)` si personne n'est connecté.
pub async fn read_account(data_dir: &Path) -> Result<Option<EpicAccount>, String> {
  let Some(session) = load_session(data_dir)? else {
    return Ok(None);
  };

  // Chaque lecture renouvelle la session : le jeton d'accès ne vit que
  // quelques heures, celui de renouvellement plusieurs semaines.
  let token = request_token(&[
    ("grant_type", "refresh_token"),
    ("refresh_token", &session.refresh_token),
    ("token_type", "eg1"),
  ])
  .await?;
  let session = save(data_dir, &token, &session.display_name)?;

  let entries: Vec<serde_json::Value> = client()?
    .get(format!("{PLAYTIME_URL}/{}/all", session.account_id))
    .bearer_auth(&token.access_token)
    .send()
    .await
    .map_err(|e| format!("Epic injoignable : {e}"))?
    .json()
    .await
    .map_err(|e| format!("Temps de jeu illisible : {e}"))?;

  // Un même jeu peut revenir plusieurs fois (une entrée par plateforme :
  // Fortnite 86 960 min puis 1 min) : on additionne, sinon la dernière
  // écrasait les autres.
  let mut totals: std::collections::BTreeMap<String, u64> = std::collections::BTreeMap::new();
  for entry in &entries {
    if let Some(name) = entry["artifactId"].as_str() {
      *totals.entry(name.to_lowercase()).or_default() += entry["totalTime"].as_u64().unwrap_or(0);
    }
  }
  let playtime = totals
    .into_iter()
    .map(|(app_name, seconds)| EpicPlay { app_name, minutes: seconds / 60 })
    .filter(|play| play.minutes > 0)
    .collect();

  // La bibliothèque complète n'est pas indispensable : sans elle, le temps
  // de jeu des jeux installés reste juste. On ne lit ici que le cache : la
  // connexion aboutit tout de suite, `read_full_library` fait le reste.
  let (library, missing) = match read_library(data_dir, &token.access_token, false).await {
    Ok(found) => found,
    Err(error) => {
      log::warn!("Epic : bibliothèque illisible : {error}");
      (Vec::new(), 0)
    }
  };

  Ok(Some(EpicAccount {
    account_id: session.account_id,
    display_name: session.display_name,
    playtime,
    library,
    missing,
  }))
}

/// Lit les fiches qui manquent au cache et rend toute la bibliothèque : une
/// requête par jeu, longue la première fois, d'où sa commande à part.
pub async fn read_full_library(data_dir: &Path) -> Result<Vec<EpicGame>, String> {
  let Some(session) = load_session(data_dir)? else {
    return Ok(Vec::new());
  };
  let token = request_token(&[
    ("grant_type", "refresh_token"),
    ("refresh_token", &session.refresh_token),
    ("token_type", "eg1"),
  ])
  .await?;
  save(data_dir, &token, &session.display_name)?;
  let (library, unread) = read_library(data_dir, &token.access_token, true).await?;
  log::info!("Epic : bibliothèque lue ({} jeux, {unread} fiches sans réponse)", library.len());
  Ok(library)
}

pub fn logout(data_dir: &Path) {
  let _ = fs::remove_file(session_path(data_dir));
  let _ = fs::remove_file(legacy_path(data_dir));
  let _ = fs::remove_file(catalog_path(data_dir));
}

fn urlencode(value: &str) -> String {
  value
    .bytes()
    .map(|b| match b {
      b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => (b as char).to_string(),
      other => format!("%{other:02X}"),
    })
    .collect()
}

#[cfg(test)]
mod tests {
  use super::*;

  /// `cargo test dump_epic -- --ignored --nocapture` : compte Epic de cette
  /// machine et temps de jeu, avec la session enregistrée par l'application.
  #[tokio::test]
  #[ignore]
  async fn dump_epic() {
    let dir = PathBuf::from(std::env::var("APPDATA").unwrap()).join("fr.interface.console");
    let account = read_account(&dir).await.expect("lecture impossible").expect("pas de session");
    println!("{} ({} jeux avec du temps, {} dans la bibliothèque)", account.display_name, account.playtime.len(), account.library.len());
    for game in account.library.iter().take(8) {
      println!("  [{}] {} (jaquette : {})", game.app_name, game.title, !game.cover.is_empty());
    }
    for play in account.playtime.iter().filter(|p| p.app_name == "fortnite" || p.app_name == "sugar") {
      println!("  {} : {} min", play.app_name, play.minutes);
    }
  }
}
