use std::process::Command;

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
    .invoke_handler(tauri::generate_handler![launch_game, is_running, power_action])
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
