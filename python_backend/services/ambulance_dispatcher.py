"""Pick the nearest ambulance for a casualty using the road graph.

If the road graph cannot route to a particular ambulance, fall back to the
straight-line Haversine distance so the dispatch loop is robust.
"""

from __future__ import annotations

import math
from typing import List, Optional, Tuple

from routing.astar import astar
from routing.graph import Graph, NodeId, haversine_m


def find_nearest_ambulance(
    graph: Graph,
    casualty: NodeId,
    ambulances: List[dict],
) -> Optional[dict]:
    """Return the ambulance dict closest to `casualty` along the road graph."""
    if not ambulances:
        return None

    casualty_node = graph.nearest_node(casualty) if graph.adjacency else None

    best: Optional[Tuple[float, dict]] = None
    for amb in ambulances:
        try:
            point = (float(amb["lat"]), float(amb["lng"]))
        except (KeyError, ValueError, TypeError):
            continue
        cost = math.inf
        if casualty_node is not None:
            amb_node = graph.nearest_node(point)
            if amb_node is not None:
                _, c = astar(graph, amb_node, casualty_node)
                cost = c
        if math.isinf(cost):
            # Fallback to Haversine when the road graph cannot reach.
            cost = haversine_m(point, casualty)
        if best is None or cost < best[0]:
            best = (cost, amb)
    return best[1] if best else None
