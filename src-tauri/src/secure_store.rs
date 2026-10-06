//! Secrets gardés sur le disque, chiffrés.
//!
//! Sous Windows : **DPAPI** (`CryptProtectData`), le coffre du système. Le
//! fichier n'est lisible que par le même compte Windows sur le même PC — copié
//! ailleurs, ou lu par un autre utilisateur, il ne vaut rien.
//!
//! Ailleurs (Linux, la cible finale) : pas de coffre garanti dans une session
//! Gamescope sans bureau. Le fichier est alors réservé à l'utilisateur
//! (droits `600`) ; c'est la protection que donnent aussi Steam et Heroic.

use std::fs;
use std::path::Path;

#[cfg(windows)]
mod dpapi {
  use windows_sys::Win32::Foundation::{LocalFree, HLOCAL};
  use windows_sys::Win32::Security::Cryptography::{
    CryptProtectData, CryptUnprotectData, CRYPTPROTECT_UI_FORBIDDEN, CRYPT_INTEGER_BLOB,
  };

  fn run(input: &[u8], protect: bool) -> Result<Vec<u8>, String> {
    let blob_in = CRYPT_INTEGER_BLOB { cbData: input.len() as u32, pbData: input.as_ptr() as *mut u8 };
    let mut blob_out = CRYPT_INTEGER_BLOB { cbData: 0, pbData: std::ptr::null_mut() };
    // SAFETY : appels FFI documentés ; le tampon de sortie est alloué par
    // Windows et rendu par `LocalFree` une fois copié.
    let ok = unsafe {
      if protect {
        CryptProtectData(
          &blob_in,
          std::ptr::null(),
          std::ptr::null(),
          std::ptr::null(),
          std::ptr::null(),
          CRYPTPROTECT_UI_FORBIDDEN,
          &mut blob_out,
        )
      } else {
        CryptUnprotectData(
          &blob_in,
          std::ptr::null_mut(),
          std::ptr::null(),
          std::ptr::null(),
          std::ptr::null(),
          CRYPTPROTECT_UI_FORBIDDEN,
          &mut blob_out,
        )
      }
    };
    if ok == 0 {
      return Err(if protect { "chiffrement impossible".into() } else { "déchiffrement impossible".into() });
    }
    // SAFETY : `pbData` pointe sur `cbData` octets alloués par Windows.
    let out = unsafe { std::slice::from_raw_parts(blob_out.pbData, blob_out.cbData as usize).to_vec() };
    unsafe {
      LocalFree(blob_out.pbData as HLOCAL);
    }
    Ok(out)
  }

  pub fn protect(data: &[u8]) -> Result<Vec<u8>, String> {
    run(data, true)
  }

  pub fn unprotect(data: &[u8]) -> Result<Vec<u8>, String> {
    run(data, false)
  }
}

/// Écrit `data` chiffré dans `path`.
pub fn write(path: &Path, data: &[u8]) -> Result<(), String> {
  if let Some(dir) = path.parent() {
    fs::create_dir_all(dir).map_err(|e| e.to_string())?;
  }
  #[cfg(windows)]
  {
    let sealed = dpapi::protect(data)?;
    fs::write(path, sealed).map_err(|e| e.to_string())
  }
  #[cfg(not(windows))]
  {
    use std::io::Write;
    use std::os::unix::fs::OpenOptionsExt;
    let mut file = fs::OpenOptions::new()
      .write(true)
      .create(true)
      .truncate(true)
      .mode(0o600)
      .open(path)
      .map_err(|e| e.to_string())?;
    file.write_all(data).map_err(|e| e.to_string())
  }
}

/// Relit un fichier écrit par [`write`] ; `None` s'il n'existe pas.
pub fn read(path: &Path) -> Result<Option<Vec<u8>>, String> {
  let Ok(bytes) = fs::read(path) else {
    return Ok(None);
  };
  #[cfg(windows)]
  {
    dpapi::unprotect(&bytes).map(Some)
  }
  #[cfg(not(windows))]
  {
    Ok(Some(bytes))
  }
}

/// Efface un secret de la mémoire avant de le rendre : une chaîne libérée
/// garde son contenu jusqu'à ce que la place soit réutilisée.
pub fn wipe(secret: String) {
  let mut bytes = secret.into_bytes();
  for byte in bytes.iter_mut() {
    // SAFETY : écriture dans un tampon qui nous appartient ; `write_volatile`
    // empêche le compilateur de supprimer l'effacement.
    unsafe { std::ptr::write_volatile(byte, 0) };
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn round_trip_and_unreadable_on_disk() {
    let path = std::env::temp_dir().join("interface-console-secure-test.bin");
    write(&path, b"jeton secret").unwrap();
    let raw = fs::read(&path).unwrap();
    #[cfg(windows)]
    assert!(!raw.windows(5).any(|w| w == b"jeton"), "le fichier ne doit pas contenir le secret en clair");
    assert_eq!(read(&path).unwrap().unwrap(), b"jeton secret");
    let _ = fs::remove_file(&path);
  }
}
