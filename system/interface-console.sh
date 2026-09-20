#!/usr/bin/env bash
# Session de la console : Gamescope en plein écran, l'interface dedans.
# Rien d'autre ne tourne — pas de bureau, pas de souris.
set -euo pipefail

# Emplacement de l'export Godot. INTERFACE_CONSOLE_BIN permet de pointer
# ailleurs sans toucher à ce script (utile pour tester une nouvelle version).
BIN="${INTERFACE_CONSOLE_BIN:-/opt/interface-console/interface-console.x86_64}"

WIDTH="${INTERFACE_CONSOLE_WIDTH:-1920}"
HEIGHT="${INTERFACE_CONSOLE_HEIGHT:-1080}"
REFRESH="${INTERFACE_CONSOLE_REFRESH:-60}"

if [[ ! -x "$BIN" ]]; then
	echo "Interface introuvable : $BIN" >&2
	echo "Exporter d'abord : godot --headless --export-release \"Linux\" build/interface-console.x86_64" >&2
	exit 1
fi

# -f plein écran, -e intégration Steam désactivée ici, -r fréquence de l'écran.
# --adaptive-sync suit l'écran quand il le permet ; sans VRR, il est ignoré.
exec gamescope \
	-W "$WIDTH" -H "$HEIGHT" -r "$REFRESH" \
	-f --adaptive-sync \
	-- "$BIN"
