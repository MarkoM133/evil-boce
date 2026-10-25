# Hex grid

One convention everywhere (rules, sim, scenes, shader).

- **Pointy-top hexes** (a corner points along ±z, flat sides face ±x).
- **Axial coordinates** `(q, r)`, stored as `Vector2i(q, r)`. `r` grows towards +z.
- **World**: the table is the `x, z` plane, `y` is up. A hex of circumradius `s`
  (`PhysicsTuning.hex_size`, 1 m) has its centre at
  `x = s·√3·(q + r/2)`, `z = s·1.5·r` (minus the map origin, see below).
  Neighbour centres are `s·√3` apart.
- **Directions**: `Hex.DIRECTIONS[i]` points at `60·i` degrees in the `x, z` plane:
  `0 (+1,0)`, `1 (0,+1)`, `2 (-1,+1)`, `3 (-1,0)`, `4 (0,-1)`, `5 (+1,-1)`.
  Corner `i` sits at `30 + 60·i` degrees; the edge between corners `i-1` and `i`
  faces direction `i`.
- **Distance**: `(|dq| + |dr| + |dq + dr|) / 2`.
- **Map**: `HexMap` is an N×N rectangle in **odd-r offset** layout
  (`col = q + (r - (r & 1)) / 2`, `row = r`; odd rows sit half a hex to +x).
  Row 0 is the far edge (-z), row N-1 the near edge (+z). The map is centred on
  the world origin: `world = axial world - HexMap.origin`.
- **Start strips** lie outside rows 0 and N-1: team 0 on the near (+z) side,
  team 1 on the far (-z) side.
- **Ball footprint**: WT 1–3 cover their centre hex; WT 4+ cover 7 (centre and ring).
  Range counts from the outer footprint hexes: `HexMap.range_cells()`.
- **In JSON** a hex is `[q, r]` (`JsonUtil.as_hex`); as a dictionary key it is `"q,r"`
  (`TerrainMap`). A `RollResult.end_hex` of a ball that left the table is the last map hex
  it rolled over.
- **Shader**: `scenes/arena/hex_ground.gdshader` repeats the same maths; the per-hex
  data texture is indexed by offset `(col, row)`.
