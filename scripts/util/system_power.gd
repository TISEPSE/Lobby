class_name SystemPower
extends RefCounted

## Actions d'alimentation de la console. Chaque action retourne un message vide
## en cas de succès, ou la raison de l'échec à afficher à l'écran.

## Windows est le poste de développement, pas la cible : y couper la machine
## ferait perdre le travail en cours, donc l'action y est volontairement inerte.
## Passer ALLOW_ON_WINDOWS à true pour l'activer quand même.
const ALLOW_ON_WINDOWS: bool = false

static func shutdown() -> String:
	if OS.get_name() == "Linux":
		return _run("systemctl", ["poweroff"])
	if OS.get_name() == "Windows":
		if not ALLOW_ON_WINDOWS:
			return "Extinction désactivée sur le poste de développement."
		return _run("shutdown", ["/s", "/t", "0"])
	return "Extinction non prise en charge sur %s." % OS.get_name()

static func reboot() -> String:
	if OS.get_name() == "Linux":
		return _run("systemctl", ["reboot"])
	if OS.get_name() == "Windows":
		if not ALLOW_ON_WINDOWS:
			return "Redémarrage désactivé sur le poste de développement."
		return _run("shutdown", ["/r", "/t", "0"])
	return "Redémarrage non pris en charge sur %s." % OS.get_name()

## Extinction de la manette : demande une déconnexion Bluetooth, donc l'adresse
## du périphérique. Sera câblé avec l'intégration système (étape 5).
static func disconnect_controller() -> String:
	return "Extinction de la manette : à câbler avec Bluetooth (étape système)."

static func _run(command: String, args: Array) -> String:
	var output: Array = []
	var code: int = OS.execute(command, PackedStringArray(args), output, true)
	if code != 0:
		return "Échec de « %s » (code %d)." % [command, code]
	return ""
