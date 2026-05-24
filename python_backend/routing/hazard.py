"""Hazard re-evaluation per blueprint section 5.

Rules:
  * If a road segment is fully blocked (flood / forest_fire close enough),
    its weight becomes +infinity so A* / Dijkstra cannot pick it.
  * If a road segment merely passes through a risky zone (landslide,
    danger_zone), the weight is multiplied by a penalty factor.
"""

from __future__ import annotations

import math
from copy import deepcopy
from typing import Dict, Iterable, List

from .graph import Graph, NodeId, haversine_m

# Distances at which a hazard influences an edge (metres).
_INFLUENCE_M = {
    "flood": 250.0,
    "forest_fire": 350.0,
    "landslide": 400.0,
    "danger_zone": 300.0,
}

# Multipliers applied to edges that pass close to a hazard. `inf` means
# the edge is removed from the search.
_PENALTY = {
    "flood": math.inf,
    "forest_fire": math.inf,
    "landslide": 3.0,
    "danger_zone": 2.0,
}


def _edge_min_distance_to_point(u: NodeId, v: NodeId, p: NodeId) -> float:
    """Approximate the minimum distance from segment uv to point p.

    Treated as planar in lat/lon for short distances - good enough for the
    influence radii we use here.
    """
    ux, uy = u[1], u[0]
    vx, vy = v[1], v[0]
    px, py = p[1], p[0]
    dx, dy = vx - ux, vy - uy
    if dx == 0 and dy == 0:
        return haversine_m(u, p)
    t = ((px - ux) * dx + (py - uy) * dy) / (dx * dx + dy * dy)
    t = max(0.0, min(1.0, t))
    closest = (uy + t * dy, ux + t * dx)
    return haversine_m(closest, p)


def apply_hazards(graph: Graph, hazards: List[Dict]) -> Graph:
    """Return a deep-copied graph with hazard-adjusted weights."""
    if not hazards:
        return graph

    out = deepcopy(graph)

    for hz in hazards:
        try:
            kind = str(hz.get("type", "")).strip()
            p = (float(hz["lat"]), float(hz["lng"]))
        except (KeyError, ValueError, TypeError):
            continue
        influence = _INFLUENCE_M.get(kind)
        penalty = _PENALTY.get(kind)
        if influence is None or penalty is None:
            continue

        for u, neighbors in out.adjacency.items():
            for v in list(neighbors.keys()):
                if _edge_min_distance_to_point(u, v, p) <= influence:
                    current = neighbors[v]
                    if math.isinf(penalty):
                        neighbors[v] = math.inf
                    else:
                        neighbors[v] = current * penalty
    return out
