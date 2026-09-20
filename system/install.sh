#!/usr/bin/env bash
# Installe la session « console » sur une machine Linux.
# À lancer depuis la machine cible, après avoir exporté l'interface.
#
#   ./install.sh /chemin/vers/interface-console.x86_64 [utilisateur]
set -euo pipefail

BIN_SOURCE="${1:-build/interface-console.x86_64}"
USER_NAME="${2:-$USER}"
TARGET_DIR=/opt/interface-console
LAUNCHER=/usr/local/bin/interface-console
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "$BIN_SOURCE" ]]; then
	echo "Export introuvable : $BIN_SOURCE" >&2
	exit 1
fi
if ! command -v gamescope >/dev/null; then
	echo "gamescope n'est pas installé (paquet « gamescope »)." >&2
	exit 1
fi

sudo install -d "$TARGET_DIR"
sudo install -m 755 "$BIN_SOURCE" "$TARGET_DIR/interface-console.x86_64"
sudo install -m 755 "$HERE/interface-console.sh" "$LAUNCHER"

# L'unité est écrite pour l'utilisateur demandé, avec son UID réel.
UID_NUM="$(id -u "$USER_NAME")"
sed -e "s/^User=.*/User=$USER_NAME/" \
	-e "s/^Group=.*/Group=$USER_NAME/" \
	-e "s#^Environment=XDG_RUNTIME_DIR=.*#Environment=XDG_RUNTIME_DIR=/run/user/$UID_NUM#" \
	"$HERE/interface-console.service" | sudo tee /etc/systemd/system/interface-console.service >/dev/null

sudo systemctl daemon-reload
echo "Installé. Démarrer maintenant :  sudo systemctl enable --now interface-console.service"
echo "Revenir à un terminal :          sudo systemctl disable --now interface-console.service"
