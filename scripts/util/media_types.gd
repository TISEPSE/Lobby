class_name MediaTypes
extends RefCounted

## Extensions de fichiers reconnues par l'interface, partagées entre le
## navigateur de fichiers et les écrans qui l'ouvrent.

const IMAGE: PackedStringArray = ["png", "jpg", "jpeg", "webp", "bmp"]

## Avatars : les tiens dans `user://avatars/`, plus les SVG fournis avec
## l'interface, que Godot importe comme des textures.
const IMAGE_AVATAR: PackedStringArray = ["png", "jpg", "jpeg", "webp", "bmp", "svg"]

## Godot 4 ne décode nativement que l'Ogg Theora. Proposer d'autres conteneurs
## ne ferait qu'offrir des fichiers qui resteraient muets à la lecture.
const VIDEO: PackedStringArray = ["ogv"]
