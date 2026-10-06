//! Compte Steam de cette machine, lu dans les fichiers du client Steam.
//!
//! Aucune clé, aucun mot de passe : Steam garde localement le compte connecté
//! (`config/loginusers.vdf`), sa photo (`config/avatarcache/`) et, pour chaque
//! jeu joué, la date de dernière partie et le temps de jeu
//! (`userdata/<id>/config/localconfig.vdf`). C'est ce qui fait la « connexion ».

use serde::Serialize;
use std::fs;
use std::path::{Path, PathBuf};

use crate::scanner;

/// Écart entre un SteamID 64 bits et l'identifiant court des dossiers `userdata`.
const STEAMID64_BASE: u64 = 76_561_197_960_265_728;

#[derive(Serialize, Clone, Debug)]
pub struct SteamApp {
  pub appid: String,
  /// Dernière partie, en secondes depuis 1970 ; 0 si Steam ne la connaît pas.
  pub last_played: u64,
  /// Temps de jeu total, en minutes.
  pub playtime: u64,
}

#[derive(Serialize, Clone, Debug)]
pub struct SteamAccount {
  pub steamid: String,
  pub persona: String,
  /// Photo de profil copiée dans le dossier de données (lisible par le webview), ou vide.
  pub avatar: String,
  pub apps: Vec<SteamApp>,
}

/// Une ligne de fichier Valve découpée : `"clé"`, `"clé" "valeur"`, `{` ou `}`.
enum Token {
  Key(String),
  Value(String, String),
  Open,
  Close,
}

fn tokenize(line: &str) -> Option<Token> {
  let trimmed = line.trim();
  if trimmed == "{" {
    return Some(Token::Open);
  }
  if trimmed == "}" {
    return Some(Token::Close);
  }
  let parts: Vec<&str> = trimmed.split('"').collect();
  // `"clé"` → ["", "clé", ""] ; `"clé"  "valeur"` → ["", "clé", "  ", "valeur", ""]
  match parts.len() {
    3 => Some(Token::Key(parts[1].to_string())),
    n if n >= 5 => Some(Token::Value(parts[1].to_string(), parts[3].to_string())),
    _ => None,
  }
}

/// Compte retenu : celui marqué « le plus récent », sinon celui qui se connecte
/// tout seul, sinon le dernier connecté.
fn pick_user(content: &str) -> Option<(String, String)> {
  struct User {
    id: String,
    persona: String,
    most_recent: bool,
    auto_login: bool,
    timestamp: u64,
  }

  let mut users: Vec<User> = Vec::new();
  let mut depth = 0;
  let mut pending = String::new();

  for line in content.lines() {
    match tokenize(line) {
      Some(Token::Key(key)) => pending = key,
      Some(Token::Open) => {
        depth += 1;
        if depth == 2 {
          users.push(User {
            id: pending.clone(),
            persona: String::new(),
            most_recent: false,
            auto_login: false,
            timestamp: 0,
          });
        }
      }
      Some(Token::Close) => depth -= 1,
      Some(Token::Value(key, value)) if depth == 2 => {
        if let Some(user) = users.last_mut() {
          match key.to_ascii_lowercase().as_str() {
            "personaname" => user.persona = value,
            "mostrecent" => user.most_recent = value == "1",
            "autologin" => user.auto_login = value == "1",
            "timestamp" => user.timestamp = value.parse().unwrap_or(0),
            _ => {}
          }
        }
      }
      _ => {}
    }
  }

  users.sort_by_key(|u| (u.most_recent, u.auto_login, u.timestamp));
  users
    .pop()
    .filter(|u| u.id.parse::<u64>().is_ok())
    .map(|u| (u.id, u.persona))
}

/// Jeux joués d'après `localconfig.vdf` : seul le bloc
/// `Software / Valve / Steam / apps` compte, d'autres blocs `apps` existent
/// ailleurs dans le fichier avec un tout autre sens.
fn played_apps(content: &str) -> Vec<SteamApp> {
  let mut path: Vec<String> = Vec::new();
  let mut pending = String::new();
  let mut apps: Vec<SteamApp> = Vec::new();

  let in_apps = |path: &[String]| -> bool {
    let n = path.len();
    n >= 5
      && path[n - 5].eq_ignore_ascii_case("software")
      && path[n - 4].eq_ignore_ascii_case("valve")
      && path[n - 3].eq_ignore_ascii_case("steam")
      && path[n - 2].eq_ignore_ascii_case("apps")
  };

  for line in content.lines() {
    match tokenize(line) {
      Some(Token::Key(key)) => pending = key,
      Some(Token::Open) => {
        path.push(std::mem::take(&mut pending));
        if in_apps(&path) {
          apps.push(SteamApp { appid: path[path.len() - 1].clone(), last_played: 0, playtime: 0 });
        }
      }
      Some(Token::Close) => {
        path.pop();
      }
      Some(Token::Value(key, value)) if in_apps(&path) => {
        if let Some(app) = apps.last_mut() {
          if key.eq_ignore_ascii_case("LastPlayed") {
            app.last_played = value.parse().unwrap_or(0);
          } else if key.eq_ignore_ascii_case("Playtime") {
            app.playtime = value.parse().unwrap_or(0);
          }
        }
      }
      _ => {}
    }
  }

  // Un bloc sans date ni temps (réglages de cloud, par exemple) n'est pas un jeu joué.
  apps.retain(|a| a.appid.parse::<u64>().is_ok() && (a.last_played > 0 || a.playtime > 0));
  apps
}

/// Copie la photo de profil là où le webview a le droit de lire.
fn copy_avatar(root: &Path, steamid: &str, data_dir: &Path) -> String {
  let source = root.join("config").join("avatarcache").join(format!("{steamid}.png"));
  if !source.exists() {
    return String::new();
  }
  let dir = data_dir.join("steam");
  if fs::create_dir_all(&dir).is_err() {
    return String::new();
  }
  let target = dir.join(format!("avatar-{steamid}.png"));
  match fs::copy(&source, &target) {
    Ok(_) => target.to_string_lossy().to_string(),
    Err(_) => String::new(),
  }
}

pub fn read_account(data_dir: &Path) -> Option<SteamAccount> {
  let root: PathBuf = scanner::steam_root()?;
  let login = fs::read_to_string(root.join("config").join("loginusers.vdf")).ok()?;
  let (steamid, persona) = pick_user(&login)?;

  let short = steamid.parse::<u64>().ok()?.checked_sub(STEAMID64_BASE)?;
  let local = root.join("userdata").join(short.to_string()).join("config").join("localconfig.vdf");
  let apps = fs::read_to_string(local).map(|c| played_apps(&c)).unwrap_or_default();

  Some(SteamAccount {
    avatar: copy_avatar(&root, &steamid, data_dir),
    steamid,
    persona,
    apps,
  })
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn picks_the_auto_login_account() {
    let vdf = r#""users"
{
	"111"
	{
		"PersonaName"		"autre"
		"AutoLogin"		"0"
		"Timestamp"		"9"
	}
	"76561198881240490"
	{
		"PersonaName"		"TISEPSE"
		"AutoLogin"		"1"
		"Timestamp"		"5"
	}
}"#;
    assert_eq!(pick_user(vdf), Some(("76561198881240490".into(), "TISEPSE".into())));
  }

  #[test]
  fn reads_only_the_steam_apps_block() {
    let vdf = r#""UserLocalConfigStore"
{
	"apps"
	{
		"999"
		{
			"LastPlayed"		"42"
		}
	}
	"Software"
	{
		"Valve"
		{
			"Steam"
			{
				"apps"
				{
					"7"
					{
						"cloud"
						{
							"last_sync_state"		"synchronized"
						}
					}
					"730"
					{
						"LastPlayed"		"1751831707"
						"Playtime"		"3871"
					}
				}
			}
		}
	}
}"#;
    let apps = played_apps(vdf);
    assert_eq!(apps.len(), 1);
    assert_eq!(apps[0].appid, "730");
    assert_eq!(apps[0].last_played, 1751831707);
    assert_eq!(apps[0].playtime, 3871);
  }

  /// `cargo test dump_account -- --ignored --nocapture` : le compte de cette machine.
  #[test]
  #[ignore]
  fn dump_account() {
    let dir = std::env::temp_dir().join("interface-console-test");
    let account = read_account(&dir).expect("aucun compte Steam");
    let mut apps = account.apps.clone();
    apps.sort_by_key(|a| std::cmp::Reverse(a.last_played));
    println!("{} ({}) avatar={} jeux={}", account.persona, account.steamid, !account.avatar.is_empty(), apps.len());
    for a in apps.iter().take(5) {
      println!("  {} last={} playtime={} min", a.appid, a.last_played, a.playtime);
    }
  }
}
