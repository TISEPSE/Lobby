# Session console (Linux)

Faire démarrer le PC directement sur l'interface, sans bureau, comme un Steam Deck.

## 1. Exporter l'interface

Depuis le poste de développement, avec les modèles d'exportation Linux installés
(éditeur Godot : *Éditeur → Gérer les modèles d'exportation*) :

```
godot --headless --export-release "Linux" build/interface-console.x86_64
```

Le preset `Linux` est déjà dans `export_presets.cfg` (x86_64, PCK embarqué, les
dossiers `Références-XBOX/` et `tools/` sont exclus).

## 2. Installer sur la machine cible

```
sudo pacman -S gamescope          # Arch ; déjà présent sur Bazzite
./system/install.sh build/interface-console.x86_64 joueur
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
