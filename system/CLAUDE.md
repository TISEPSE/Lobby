# Intégration système (Linux)

- `interface-console.sh` (installé en `/usr/local/bin/interface-console`) lance Gamescope en plein écran sur le binaire Tauri. Résolution, fréquence et chemin se règlent par variables d'environnement (`INTERFACE_CONSOLE_WIDTH`, `_HEIGHT`, `_REFRESH`, `_BIN`).
- `interface-console.service` prend `tty1` (`Conflicts=getty@tty1`), comme la session du Steam Deck. `Restart=on-failure` seulement : quitter l'interface doit ramener à un terminal, pas la relancer en boucle.
- `install.sh` copie le binaire dans `/opt/interface-console/`, écrit l'unité pour le bon utilisateur et recharge systemd. `autologin.conf` couvre la variante sans unité dédiée.
- Sous Linux, Tauri s'appuie sur WebKitGTK (`webkit2gtk-4.1`).
- Toujours prévoir une porte de sortie pour ne pas se bloquer hors du système pendant les tests (voir `system/README.md`).
