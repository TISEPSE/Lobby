//! Clé SteamGridDB récupérée sur le compte de l'utilisateur, pour lui éviter de
//! recopier 32 caractères à la manette. Même méthode que la connexion Epic : une
//! fenêtre à part, un script qui lit la page, et une adresse factice interceptée
//! qui rapporte le résultat. La fenêtre est privée (rien sur le disque), limitée
//! au HTTPS de SteamGridDB et de la connexion Steam (OpenID), sans pop-up.
//!
//! La clé part vers la fenêtre principale, qui l'enregistre avec les réglages
//! (`steamgriddb_key`) : jamais dans le code, jamais dans le journal.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use serde::Serialize;
use tauri::{Emitter, Manager};

const LOGIN_WINDOW: &str = "steamgriddb-login";
const EVENT: &str = "steamgriddb-key";
const API_PAGE: &str = "https://www.steamgriddb.com/profile/preferences/api";
const API_PATH: &str = "/profile/preferences/api";
/// Adresse fictive qui rapporte la clé : interceptée avant de partir sur le réseau.
const KEY_HOST: &str = "steamgriddb-key.invalid";
const ALLOWED_HOSTS: [&str; 4] = ["steamgriddb.com", "steamcommunity.com", "steampowered.com", "steamstatic.com"];
const KEY_LENGTH: usize = 32;

/// Cherche la clé dans la page, le temps que le site l'affiche : il construit tout
/// en JavaScript, puis montre `Key: <code>…</code>`, ou le seul bouton « Create API
/// Key » pour un compte qui n'en a pas. Ce bouton est pressé une fois : c'est pour
/// obtenir sa clé que l'utilisateur est là, et à la manette il ne pourrait pas
/// cliquer dans cette page. « Revoke API Key » n'est jamais touché.
const READ_KEY: &str = r#"(() => {
  if (window.__lobbyKeySent) return;
  window.__lobbyKeySent = true;
  let tries = 0;
  let created = false;
  const timer = setInterval(() => {
    const fields = [...document.querySelectorAll('code, input, textarea, pre')].map((e) => e.value || e.textContent || '');
    const key = (fields.join(' ').match(/\b[0-9a-f]{32}\b/i) ?? [])[0];
    if (key) {
      clearInterval(timer);
      location.replace(`https://KEY_HOST/?key=${key}`);
      return;
    }
    const create = [...document.querySelectorAll('button')].find((b) => b.textContent.trim() === 'Create API Key');
    if (create && !created) {
      created = true;
      create.click();
    }
    if (++tries > 480) clearInterval(timer);
  }, 250);
})();"#;

#[derive(Serialize, Clone, Debug)]
struct Outcome {
  ok: bool,
  message: String,
  /// La clé trouvée ; vide sinon.
  key: String,
}

fn allowed(url: &tauri::Url) -> bool {
  url.scheme() == "https"
    && url
      .host_str()
      .is_some_and(|host| ALLOWED_HOSTS.iter().any(|allowed| host == *allowed || host.ends_with(&format!(".{allowed}"))))
}

fn is_key(value: &str) -> bool {
  value.len() == KEY_LENGTH && value.bytes().all(|b| b.is_ascii_hexdigit())
}

/// La clé rapportée par l'adresse factice.
fn key_from(url: &tauri::Url) -> Option<String> {
  if url.host_str() != Some(KEY_HOST) {
    return None;
  }
  url.query_pairs().find(|(name, _)| name == "key").map(|(_, value)| value.into_owned()).filter(|key| is_key(key))
}

/// Ouvre la page de la clé d'API, en navigation privée.
pub fn open_login(app: &tauri::AppHandle) -> Result<(), String> {
  if let Some(existing) = app.get_webview_window(LOGIN_WINDOW) {
    let _ = existing.set_focus();
    return Ok(());
  }
  let url = API_PAGE.parse().map_err(|e| format!("Adresse invalide : {e}"))?;
  let done = Arc::new(AtomicBool::new(false));
  let done_on_key = done.clone();
  // Passé par Steam : au retour sur SteamGridDB, on rouvre la page de la clé,
  // son site ramenant ailleurs après la connexion.
  let via_steam = Arc::new(AtomicBool::new(false));
  let handle = app.clone();
  let opener = app.clone();
  log::info!("SteamGridDB : ouverture de la page de la clé");

  let window = tauri::WebviewWindowBuilder::new(app, LOGIN_WINDOW, tauri::WebviewUrl::External(url))
    .title("Connexion à SteamGridDB")
    .inner_size(1100.0, 820.0)
    .center()
    .always_on_top(true)
    .focused(true)
    .incognito(true)
    .on_page_load(move |window, payload| {
      if payload.event() != tauri::webview::PageLoadEvent::Finished {
        return;
      }
      let url = payload.url();
      // Le chemin seulement : la page de retour porte la réponse de Steam dans
      // son adresse.
      log::info!("SteamGridDB : page chargée {}", url.path());
      let on_grid = url.host_str().is_some_and(|host| host.ends_with("steamgriddb.com"));
      if !on_grid {
        via_steam.store(true, Ordering::SeqCst);
      } else if url.path().starts_with(API_PATH) {
        let _ = window.eval(READ_KEY.replace("KEY_HOST", KEY_HOST));
      } else if via_steam.swap(false, Ordering::SeqCst) {
        let _ = window.eval(format!("location.replace('{API_PAGE}')"));
      }
    })
    .on_navigation(move |url| {
      if url.host_str() == Some(KEY_HOST) {
        if let Some(key) = key_from(url) {
          if !done_on_key.swap(true, Ordering::SeqCst) {
            log::info!("SteamGridDB : clé récupérée");
            let app = handle.clone();
            // Détruire la fenêtre depuis son propre gestionnaire la bloquerait.
            tauri::async_runtime::spawn(async move {
              if let Some(window) = app.get_webview_window(LOGIN_WINDOW) {
                let _ = window.destroy();
              }
              let _ = app.emit_to("main", EVENT, Outcome { ok: true, message: String::new(), key });
            });
          }
        }
        return false;
      }
      if !allowed(url) {
        log::warn!("SteamGridDB : navigation bloquée vers {}", url.host_str().unwrap_or("?"));
        return false;
      }
      true
    })
    // « Login with Steam » ouvre une pop-up (`window.open`). Refusée en silence,
    // le clic ne faisait rien. Pas besoin d'une vraie pop-up : la page de retour
    // ouvre la session côté serveur, elle marche aussi bien dans cette fenêtre,
    // et `on_page_load` ramène ensuite à la page de la clé.
    .on_new_window(move |url, _| {
      if allowed(&url) {
        log::info!("SteamGridDB : connexion ouverte dans la fenêtre");
        let app = opener.clone();
        tauri::async_runtime::spawn(async move {
          if let Some(mut window) = app.get_webview_window(LOGIN_WINDOW) {
            let _ = window.navigate(url);
          }
        });
      } else {
        log::warn!("SteamGridDB : pop-up bloquée vers {}", url.host_str().unwrap_or("?"));
      }
      tauri::webview::NewWindowResponse::Deny
    })
    .build()
    .map_err(|e| format!("Fenêtre de connexion impossible : {e}"))?;

  let handle = app.clone();
  window.on_window_event(move |event| {
    if let tauri::WindowEvent::Destroyed = event {
      if !done.load(Ordering::SeqCst) {
        log::info!("SteamGridDB : fenêtre fermée sans clé");
        let _ = handle.emit_to("main", EVENT, Outcome { ok: false, message: "connexion annulée".into(), key: String::new() });
      }
    }
  });
  Ok(())
}

#[cfg(test)]
mod tests {
  use super::*;

  fn url(text: &str) -> tauri::Url {
    text.parse().unwrap()
  }

  #[test]
  fn navigation_stays_on_steamgriddb_and_steam_in_https() {
    assert!(allowed(&url("https://www.steamgriddb.com/profile/preferences/api")));
    assert!(allowed(&url("https://steamcommunity.com/openid/login")));
    assert!(allowed(&url("https://login.steampowered.com/")));
    assert!(!allowed(&url("http://www.steamgriddb.com/")));
    assert!(!allowed(&url("https://steamgriddb.com.evil.example/")));
    assert!(!allowed(&url("https://evilsteamcommunity.com/")));
    assert!(!allowed(&url("https://example.com/")));
  }

  #[test]
  fn only_a_real_key_is_accepted() {
    let key = "0123456789abcdef0123456789abcdef";
    assert_eq!(key_from(&url(&format!("https://{KEY_HOST}/?key={key}"))), Some(key.to_string()));
    assert_eq!(key_from(&url(&format!("https://{KEY_HOST}/?key=trop-court"))), None);
    assert_eq!(key_from(&url(&format!("https://{KEY_HOST}/?autre={key}"))), None);
    assert_eq!(key_from(&url(&format!("https://www.steamgriddb.com/?key={key}"))), None);
  }

  #[test]
  fn the_page_script_points_to_the_intercepted_address() {
    let script = READ_KEY.replace("KEY_HOST", KEY_HOST);
    assert!(script.contains(&format!("https://{KEY_HOST}/?key=")));
    assert!(!script.contains("KEY_HOST"));
  }

  #[test]
  fn the_page_script_can_never_revoke_a_key() {
    assert!(READ_KEY.contains("=== 'Create API Key'"));
    assert!(!READ_KEY.to_lowercase().contains("revoke"));
  }
}
