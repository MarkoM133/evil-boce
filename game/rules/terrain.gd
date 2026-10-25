class_name Terrain
extends RefCounted
## Ground types a stage can turn its 7 hexes into (GDD 6). Ice and Mud change the slow-down;
## Ramp is a hill (balls slow going up, speed up going down, rest only near the top); Wind
## pushes rolling balls one way. The ids are also the terrain ids in the ground shader.

enum Type { NONE, ICE, MUD, RAMP, WIND }


static func name_of(t: Type) -> String:
	match t:
		Type.ICE:
			return "Ice"
		Type.MUD:
			return "Mud"
		Type.RAMP:
			return "Ramp"
		Type.WIND:
			return "Wind"
	return "None"


## Inverse of name_of(); unknown names are NONE. Matches the `Terrain: X` line on stage cards.
static func parse(name: String) -> Type:
	match name.strip_edges().to_lower():
		"ice":
			return Type.ICE
		"mud":
			return Type.MUD
		"ramp", "hill":
			return Type.RAMP
		"wind":
			return Type.WIND
	return Type.NONE
