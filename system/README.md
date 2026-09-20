# Session console (Linux)

Faire démarrer le PC directement sur l'interface, sans bureau, comme un Steam Deck.

## 1. Construire l'interface

Depuis le poste de développement (ou directement sur la machine cible) :

```
npm install
npm run tauri build
```

Le binaire sort dans `src-tauri/target/release/interface-console`. Sous Linux,
Tauri s'appuie sur WebKitGTK : `webkit2gtk-4.1` et `libappindicator` doivent être
installés.

## 2. Installer sur la machine cible

```
sudo pacman -S gamescope          # Arch ; déjà présent sur Bazzite
./system/install.sh src-tauri/target/release/interface-console joueur
sudo systemctl enable --now interface-console.service
```

L'unité prend le premier terminal (`tty1`) et lance
`/usr/local/bin/interface-console`, qui démarre Gamescope en plein écran avec
l'interface dedans. Résolution et fréquence se règlent sans toucher au script :
`INTERFACE_CONSOLE_WIDTH`, `_HEIGHT`, `_REFRESH`, et `INTERFACE_CONSOLE_BIN`
pour essayer un autre binaire.

## Variante sans unité dédiée

Autologin sur `tty1` puis lancement depuis le profil du compte :

```
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
sudo cp system/autologin.conf /etc/systemd/system/getty@tty1.service.d/
sudo systemctl daemon-reload
echo '[[ $(tty) == /dev/tty1 ]] && exec interface-console' >> ~/.bash_profile
```

## Portes de sortie

Ne jamais se retrouver enfermé hors du système :

- Dans l'interface : **Options (X) → Alimentation → Quitter l'interface**. Le
  service ne redémarre que sur plantage (`Restart=on-failure`), donc on retombe
  sur un terminal.
- Depuis un autre terminal : `Ctrl+Alt+F2`, puis
  `sudo systemctl stop interface-console.service`.
- En SSH : `sudo systemctl disable --now interface-console.service`.

## Vérifier

```
systemctl status interface-console.service
journalctl -u interface-console.service -b
```
