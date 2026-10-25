class_name Terrain
extends RefCounted
## Ground types a stage can turn its 7 hexes into. Ramp and Wind come in step 1b.

enum Type { NONE, ICE, MUD }


static func name_of(t: Type) -> String:
	match t:
		Type.ICE:
			return "Ice"
		Type.MUD:
			return "Mud"
	return "None"
