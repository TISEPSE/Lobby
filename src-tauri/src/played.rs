//! Dernières parties jouées hors de Lobby : launcher Epic, raccourci, ou Lobby
//! simplement fermé. Steam garde ses propres dates (`steam_account`), Epic non :
//! ni son API ni ses manifestes n'en donnent, et un jeu Epic n'avait donc aucune
//! date tant que Lobby ne l'avait pas vu tourner.
//!
//! Deux sources, lues sans droit d'administrateur et jamais écrites :
//! - `HKCU\System\GameConfigStore\Children\*` : Windows y note chaque jeu, avec
//!   son chemin et, sur les versions récentes, `LastAccessed` (l'instant du
//!   lancement). Tous les jeux, quelle que soit la boutique, mais pas toutes les
//!   versions de Windows ;
//! - `GameUserSettings.ini` du launcher Epic : `LastPlayedGame`, le dernier jeu
//!   Epic seulement, sur toutes les versions de Windows.

use serde::Serialize;

/// Une partie vue ailleurs. Le front la rattache à un jeu : par son dossier
/// (`path`), ou par son nom interne Epic (`app_name`).
#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct PlayedElsewhere {
  /// Exécutable lancé, quand c'est Windows qui l'a vu ; vide sinon.
  pub path: String,
  /// Nom interne Epic (`Sugar` pour Rocket League) ; vide sinon.
  pub app_name: String,
  /// Instant de la partie en millisecondes ; 0 s'il est dans `local_time`.
  pub at: u64,
  /// Heure locale sans fuseau (`2026-10-31T23:43:01.183`) ; vide sinon.
  pub local_time: String,
}

/// Millisecondes entre l'origine d'un FILETIME (1601) et celle d'Unix (1970).
const FILETIME_TO_UNIX_MS: u64 = 11_644_473_600_000;

/// FILETIME (dixièmes de microseconde depuis 1601) en millisecondes Unix.
fn filetime_to_ms(filetime: u64) -> Option<u64> {
  (filetime / 10_000)
    .checked_sub(FILETIME_TO_UNIX_MS)
    .filter(|ms| *ms > 0)
}

/// Lit `LastPlayedGame=<namespace>:<item>:<AppName>,<date>`.
///
/// Malgré son « Z », la date d'Epic est en **heure locale** : le même lancement
/// est à 22:43 UTC dans le journal d'Epic et à 23:43 ici, sur un PC à UTC+1. Elle
/// part donc sans son « Z », et le front la lit comme une heure locale.
fn epic_last_played(ini: &str) -> Option<PlayedElsewhere> {
  let value = ini
    .lines()
    .find_map(|line| line.trim().strip_prefix("LastPlayedGame="))?;
  let (id, when) = value.split_once(',')?;
  let app_name = id.rsplit(':').next()?.trim();
  let local_time = when.trim().trim_end_matches('Z');
  // Au moins `AAAA-MM-JJTHH:MM:SS`.
  if app_name.is_empty() || local_time.len() < 19 {
    return None;
  }
  Some(PlayedElsewhere {
    path: String::new(),
    app_name: app_name.to_string(),
    at: 0,
    local_time: local_time.to_string(),
  })
}

/// Jeux notés par Windows, avec leur date quand il la donne.
#[cfg(windows)]
fn windows_games() -> Vec<PlayedElsewhere> {
  use winreg::{enums::HKEY_CURRENT_USER, RegKey};

  let Ok(children) =
    RegKey::predef(HKEY_CURRENT_USER).open_subkey(r"System\GameConfigStore\Children")
  else {
    return Vec::new();
  };
  children
    .enum_keys()
    .flatten()
    .filter_map(|name| {
      let child = children.open_subkey(&name).ok()?;
      let filetime: u64 = child.get_value("LastAccessed").ok()?;
      let path: String = child.get_value("MatchedExeFullPath").ok()?;
      Some(PlayedElsewhere {
        path,
        app_name: String::new(),
        at: filetime_to_ms(filetime)?,
        local_time: String::new(),
      })
    })
    .collect()
}

/// Dernier jeu lancé par le launcher Epic.
#[cfg(windows)]
fn epic_launcher_game() -> Option<PlayedElsewhere> {
  let local = std::env::var_os("LOCALAPPDATA")?;
  let config = std::path::Path::new(&local).join(r"EpicGamesLauncher\Saved\Config");
  ["WindowsEditor", "Windows"].iter().find_map(|folder| {
    let bytes = std::fs::read(config.join(folder).join("GameUserSettings.ini")).ok()?;
    epic_last_played(&String::from_utf8_lossy(&bytes))
  })
}

/// Tout ce qui est connu sur ce PC. Hors Windows, rien : sous Gamescope, Lobby
/// est le lanceur, il voit toutes les parties.
pub fn read() -> Vec<PlayedElsewhere> {
  #[cfg(windows)]
  {
    let mut found = windows_games();
    found.extend(epic_launcher_game());
    found
  }
  #[cfg(not(windows))]
  {
    Vec::new()
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn filetime_becomes_unix_milliseconds() {
    // 31/10/2026 22:43:18 UTC : Rocket League, relevé dans le registre.
    assert_eq!(filetime_to_ms(134_379_601_986_620_000), Some(1_793_486_598_662));
  }

  #[test]
  fn absurd_filetimes_are_ignored() {
    assert_eq!(filetime_to_ms(0), None);
    assert_eq!(filetime_to_ms(116_444_736_000_000_000), None);
  }

  #[test]
  fn epic_date_loses_its_false_utc_marker() {
    let ini = "[Launcher]\nOther=1\nLastPlayedGame=9773aa:530145:Sugar,2026-10-31T23:43:01.183Z\nThen=2\n";
    let found = epic_last_played(ini).unwrap();
    assert_eq!(found.app_name, "Sugar");
    assert_eq!(found.local_time, "2026-10-31T23:43:01.183");
    assert_eq!(found.at, 0);
  }

  #[test]
  fn epic_settings_without_a_game_give_nothing() {
    assert_eq!(epic_last_played("[Launcher]\nOther=1\n"), None);
    assert_eq!(epic_last_played("LastPlayedGame=\n"), None);
    assert_eq!(epic_last_played("LastPlayedGame=a:b:Sugar\n"), None);
    assert_eq!(epic_last_played("LastPlayedGame=a:b:,2026-10-31T23:43:01Z\n"), None);
    assert_eq!(epic_last_played("LastPlayedGame=a:b:Sugar,hier\n"), None);
  }

  /// `cargo test --lib dump_played -- --ignored --nocapture` montre ce que voit ce PC.
  #[test]
  #[ignore]
  fn dump_played() {
    for entry in read() {
      println!("{entry:?}");
    }
  }
}
