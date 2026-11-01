//! Photos de profil importées. L'image d'origine vient de n'importe où sur le
//! PC, alors que le protocole d'accès aux fichiers n'est ouvert que sur le dossier
//! de données : elle passe donc par `read_image`. Une fois recadrée dans
//! l'interface, elle revient en PNG et s'écrit dans `<app data>/avatars`.

use std::fs;
use std::path::{Path, PathBuf};

const IMAGE_EXTENSIONS: [&str; 6] = ["png", "jpg", "jpeg", "webp", "bmp", "gif"];
/// Au-delà, ce n'est plus une photo de profil, et le webview devrait la décoder.
const MAX_IMAGE_BYTES: u64 = 30 * 1024 * 1024;
/// Largement plus qu'un PNG de 512 × 512.
const MAX_AVATAR_BYTES: usize = 8 * 1024 * 1024;
const PNG_SIGNATURE: [u8; 8] = [0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A];
const AVATAR_PREFIX: &str = "avatar-";

/// Un fichier que l'explorateur propose comme photo.
pub fn is_image(path: &Path) -> bool {
  let extension = path.extension().and_then(|e| e.to_str()).unwrap_or("");
  IMAGE_EXTENSIONS.iter().any(|known| extension.eq_ignore_ascii_case(known))
}

/// Les octets d'une image : jamais un autre type de fichier, jamais d'énormes.
pub fn read(path: &Path) -> Result<Vec<u8>, String> {
  if !is_image(path) {
    return Err("Ce fichier n'est pas une image.".into());
  }
  let size = fs::metadata(path).map_err(|e| format!("Image illisible : {e}"))?.len();
  if size > MAX_IMAGE_BYTES {
    return Err("Cette image est trop lourde (30 Mo au plus).".into());
  }
  fs::read(path).map_err(|e| format!("Image illisible : {e}"))
}

fn is_png(bytes: &[u8]) -> bool {
  bytes.starts_with(&PNG_SIGNATURE)
}

/// Écrit la photo recadrée, puis efface la précédente : si l'écriture échoue, le
/// profil garde sa photo. Nom horodaté : à même nom, le webview resservirait
/// l'ancienne image depuis son cache (comme pour `pick_game_art`).
pub fn write_avatar(dir: &Path, bytes: &[u8], stamp: u64) -> Result<PathBuf, String> {
  if !is_png(bytes) || bytes.len() > MAX_AVATAR_BYTES {
    return Err("Photo recadrée invalide.".into());
  }
  fs::create_dir_all(dir).map_err(|e| format!("Dossier des photos impossible à créer : {e}"))?;
  let path = dir.join(format!("{AVATAR_PREFIX}{stamp}.png"));
  fs::write(&path, bytes).map_err(|e| format!("Photo impossible à enregistrer : {e}"))?;
  for entry in fs::read_dir(dir).into_iter().flatten().flatten() {
    let old = entry.path();
    let ours = entry.file_name().to_string_lossy().starts_with(AVATAR_PREFIX);
    if ours && old != path {
      let _ = fs::remove_file(old);
    }
  }
  Ok(path)
}

#[cfg(test)]
mod tests {
  use super::*;

  /// Dossier propre à chaque test, retiré à la fin.
  fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("lobby-images-{name}-{}", std::process::id()));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).unwrap();
    dir
  }

  fn png() -> Vec<u8> {
    let mut bytes = PNG_SIGNATURE.to_vec();
    bytes.extend_from_slice(b"contenu");
    bytes
  }

  #[test]
  fn only_images_are_listed() {
    assert!(is_image(Path::new("C:/Photos/moi.PNG")));
    assert!(is_image(Path::new("moi.jpeg")));
    assert!(!is_image(Path::new("moi.exe")));
    assert!(!is_image(Path::new("settings.json")));
    assert!(!is_image(Path::new("sans-extension")));
  }

  #[test]
  fn other_files_cannot_be_read() {
    let dir = scratch("read");
    let secret = dir.join("epic.session");
    fs::write(&secret, b"secret").unwrap();
    assert!(read(&secret).is_err());
    let photo = dir.join("moi.png");
    fs::write(&photo, png()).unwrap();
    assert_eq!(read(&photo).unwrap(), png());
    fs::remove_dir_all(dir).unwrap();
  }

  #[test]
  fn huge_images_are_refused() {
    let dir = scratch("huge");
    let photo = dir.join("enorme.png");
    let file = fs::File::create(&photo).unwrap();
    file.set_len(MAX_IMAGE_BYTES + 1).unwrap();
    assert!(read(&photo).is_err());
    fs::remove_dir_all(dir).unwrap();
  }

  #[test]
  fn only_a_png_becomes_an_avatar() {
    let dir = scratch("signature");
    assert!(write_avatar(&dir, b"<script>", 1).is_err());
    assert_eq!(fs::read_dir(&dir).unwrap().count(), 0);
    fs::remove_dir_all(dir).unwrap();
  }

  #[test]
  fn the_previous_avatar_is_replaced_and_nothing_else() {
    let dir = scratch("replace");
    fs::write(dir.join("autre.png"), b"a garder").unwrap();
    let first = write_avatar(&dir, &png(), 1).unwrap();
    let second = write_avatar(&dir, &png(), 2).unwrap();
    assert_ne!(first, second);
    assert!(!first.exists());
    assert!(second.exists());
    assert!(dir.join("autre.png").exists());
    fs::remove_dir_all(dir).unwrap();
  }
}
