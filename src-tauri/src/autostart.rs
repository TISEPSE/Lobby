//! Lobby lancé à l'ouverture de session Windows : une valeur dans la clé `Run`
//! de l'utilisateur, sans droit d'administrateur. Le désinstalleur retire cette
//! même valeur (elle porte le nom du produit). Sous Linux, c'est la session
//! dédiée qui s'en charge (`system/`).

#[cfg(windows)]
mod windows {
  use winreg::{
    enums::{HKEY_CURRENT_USER, KEY_READ, KEY_SET_VALUE},
    RegKey,
  };

  pub const RUN_KEY: &str = r"Software\Microsoft\Windows\CurrentVersion\Run";
  /// Le nom du produit : c'est celui que le désinstalleur efface.
  pub const RUN_VALUE: &str = "Lobby";

  /// Commande écrite dans la clé : entre guillemets, le chemin peut avoir des espaces.
  pub fn command_for(exe: &std::path::Path) -> String {
    format!("\"{}\"", exe.display())
  }

  pub fn is_set(key: &str, value: &str) -> bool {
    RegKey::predef(HKEY_CURRENT_USER)
      .open_subkey_with_flags(key, KEY_READ)
      .and_then(|run| run.get_value::<String, _>(value))
      .is_ok()
  }

  pub fn set(key: &str, value: &str, command: Option<&str>) -> std::io::Result<()> {
    let hkcu = RegKey::predef(HKEY_CURRENT_USER);
    match command {
      Some(command) => hkcu.create_subkey(key)?.0.set_value(value, &command),
      None => match hkcu
        .open_subkey_with_flags(key, KEY_SET_VALUE)
        .and_then(|run| run.delete_value(value))
      {
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        other => other,
      },
    }
  }
}

/// `None` : ce système ne passe pas par là, le réglage n'est pas proposé.
pub fn enabled() -> Option<bool> {
  #[cfg(windows)]
  {
    Some(windows::is_set(windows::RUN_KEY, windows::RUN_VALUE))
  }
  #[cfg(not(windows))]
  {
    None
  }
}

pub fn set(on: bool) -> Result<(), String> {
  #[cfg(windows)]
  {
    let command = if on {
      let exe = std::env::current_exe().map_err(|e| format!("Exécutable introuvable : {e}"))?;
      Some(windows::command_for(&exe))
    } else {
      None
    };
    windows::set(windows::RUN_KEY, windows::RUN_VALUE, command.as_deref())
      .map_err(|e| format!("Réglage de démarrage impossible : {e}"))
  }
  #[cfg(not(windows))]
  {
    let _ = on;
    Err("Démarrage automatique géré par la session Linux.".to_string())
  }
}

#[cfg(all(test, windows))]
mod tests {
  use super::windows::{command_for, is_set, set};
  use winreg::{enums::HKEY_CURRENT_USER, RegKey};

  /// Une clé de test, jamais la vraie clé `Run` : un test ne doit pas toucher au
  /// démarrage du PC.
  const KEY: &str = r"Software\Lobby-autostart-test";

  #[test]
  fn the_setting_is_written_then_removed() {
    assert!(!is_set(KEY, "Lobby"));
    set(KEY, "Lobby", Some("\"C:\\Lobby\\app.exe\"")).unwrap();
    assert!(is_set(KEY, "Lobby"));
    set(KEY, "Lobby", None).unwrap();
    assert!(!is_set(KEY, "Lobby"));
    // Le retirer deux fois n'est pas une erreur.
    set(KEY, "Lobby", None).unwrap();
    RegKey::predef(HKEY_CURRENT_USER).delete_subkey(KEY).unwrap();
  }

  #[test]
  fn the_path_is_quoted() {
    let command = command_for(std::path::Path::new(r"C:\Program Files\Lobby\app.exe"));
    assert_eq!(command, r#""C:\Program Files\Lobby\app.exe""#);
  }
}
