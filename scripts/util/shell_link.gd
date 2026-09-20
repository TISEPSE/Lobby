class_name ShellLink
extends RefCounted

## Lecture d'un raccourci Windows (.lnk). Godot ne sait pas les suivre : on lit
## donc le format « Shell Link » (MS-SHLLINK) nous-mêmes, juste assez pour en
## tirer la cible et ses arguments. Un raccourci illisible est ignoré, jamais
## deviné : mieux vaut un jeu manquant qu'une entrée qui ne lance rien.

const SIGNATURE: int = 0x0000004C

# LinkFlags (section 2.1.1 de la spécification).
const HAS_TARGET_ID_LIST: int = 1 << 0
const HAS_LINK_INFO: int = 1 << 1
const HAS_NAME: int = 1 << 2
const HAS_RELATIVE_PATH: int = 1 << 3
const HAS_WORKING_DIR: int = 1 << 4
const HAS_ARGUMENTS: int = 1 << 5
const HAS_ICON_LOCATION: int = 1 << 6
const IS_UNICODE: int = 1 << 7

var target: String = ""
var arguments: String = ""
var working_dir: String = ""

## Lit un .lnk. Retourne null si le fichier n'est pas un raccourci exploitable.
static func parse(path: String) -> ShellLink:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	if file.get_32() != SIGNATURE:
		return null
	file.seek(20)
	var flags: int = file.get_32()
	# Le header fait 76 octets ; la suite dépend des drapeaux.
	file.seek(76)

	if flags & HAS_TARGET_ID_LIST:
		var id_list_size: int = file.get_16()
		file.seek(file.get_position() + id_list_size)

	var link := ShellLink.new()
	if flags & HAS_LINK_INFO:
		link.target = _read_link_info(file)

	var unicode: bool = (flags & IS_UNICODE) != 0
	# Les chaînes se suivent dans un ordre imposé : on les lit toutes, même
	# celles dont on ne fait rien, sinon on lirait la suivante au mauvais endroit.
	if flags & HAS_NAME:
		_read_string(file, unicode)
	var relative: String = _read_string(file, unicode) if flags & HAS_RELATIVE_PATH else ""
	if flags & HAS_WORKING_DIR:
		link.working_dir = _read_string(file, unicode)
	if flags & HAS_ARGUMENTS:
		link.arguments = _read_string(file, unicode)
	file.close()

	# Sans LinkInfo, la cible se reconstruit depuis le dossier de travail et le
	# chemin relatif (« ..\..\Jeu\jeu.exe »).
	if link.target.is_empty() and not relative.is_empty() and not link.working_dir.is_empty():
		link.target = link.working_dir.path_join(relative.replace("\\", "/")).simplify_path()
	link.target = link.target.replace("\\", "/")
	return link if not link.target.is_empty() else null

## LinkInfo : chemin local du fichier visé, en deux morceaux à recoller.
static func _read_link_info(file: FileAccess) -> String:
	var start: int = file.get_position()
	var size: int = file.get_32()
	if size <= 0:
		return ""
	var header_size: int = file.get_32()
	var info_flags: int = file.get_32()
	file.get_32()  # VolumeIDOffset
	var base_offset: int = file.get_32()
	file.get_32()  # CommonNetworkRelativeLinkOffset
	var suffix_offset: int = file.get_32()
	var base_unicode_offset: int = 0
	var suffix_unicode_offset: int = 0
	if header_size >= 0x24:
		base_unicode_offset = file.get_32()
		suffix_unicode_offset = file.get_32()

	var target: String = ""
	# Bit 0 : le chemin local est renseigné. Sans lui, le raccourci vise un
	# partage réseau, qu'on ne suit pas.
	if info_flags & 1:
		if base_unicode_offset > 0:
			target = _read_utf16_at(file, start + base_unicode_offset)
			target += _read_utf16_at(file, start + suffix_unicode_offset) if suffix_unicode_offset > 0 else ""
		else:
			target = _read_ansi_at(file, start + base_offset)
			target += _read_ansi_at(file, start + suffix_offset) if suffix_offset > 0 else ""

	file.seek(start + size)
	return target

static func _read_ansi_at(file: FileAccess, offset: int) -> String:
	var previous: int = file.get_position()
	file.seek(offset)
	var bytes: PackedByteArray = PackedByteArray()
	var byte: int = file.get_8()
	while byte != 0 and not file.eof_reached():
		bytes.append(byte)
		byte = file.get_8()
	file.seek(previous)
	return bytes.get_string_from_utf8()

static func _read_utf16_at(file: FileAccess, offset: int) -> String:
	var previous: int = file.get_position()
	file.seek(offset)
	var bytes: PackedByteArray = PackedByteArray()
	var unit: int = file.get_16()
	while unit != 0 and not file.eof_reached():
		bytes.append(unit & 0xFF)
		bytes.append((unit >> 8) & 0xFF)
		unit = file.get_16()
	file.seek(previous)
	return bytes.get_string_from_utf16()

## StringData : nombre de caractères puis les caractères eux-mêmes.
static func _read_string(file: FileAccess, unicode: bool) -> String:
	var count: int = file.get_16()
	if count <= 0:
		return ""
	var bytes: PackedByteArray = file.get_buffer(count * (2 if unicode else 1))
	return bytes.get_string_from_utf16() if unicode else bytes.get_string_from_utf8()
