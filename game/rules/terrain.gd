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


## Inverse of name_of(); unknown names are NONE. Matches the `Terrain: X` line on stage cards.
static func parse(name: String) -> Type:
	match name.strip_edges().to_lower():
		"ice":
			return Type.ICE
		"mud":
			return Type.MUD
	return Type.NONE
