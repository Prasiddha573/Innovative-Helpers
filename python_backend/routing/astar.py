"""A* shortest-path search per blueprint section 5.

f(n) = g(n) + h(n)
  g(n) = actual path cost from the start to n (sum of edge weights, metres)
  h(n) = heuristic - straight-line Haversine distance from n to the goal
"""

from __future__ import annotations

import heapq
import math
from typing import Dict, List, Optional, Tuple

from .graph import Graph, NodeId, haversine_m


def astar(
    graph: Graph,
    start: NodeId,
    goal: NodeId,
) -> Tuple[List[NodeId], float]:
    """Return (path, total_cost_m). Empty path if no route is found."""
    if start == goal:
        return [start], 0.0

    open_heap: List[Tuple[float, NodeId]] = []
    heapq.heappush(open_heap, (0.0, start))
    came_from: Dict[NodeId, Optional[NodeId]] = {start: None}
    g_score: Dict[NodeId, float] = {start: 0.0}

    while open_heap:
        _, current = heapq.heappop(open_heap)
        if current == goal:
            return _reconstruct(came_from, current), g_score[current]

        for neighbor, weight in graph.adjacency.get(current, {}).items():
            if math.isinf(weight):
                continue
            tentative_g = g_score[current] + weight
            if tentative_g < g_score.get(neighbor, math.inf):
                came_from[neighbor] = current
                g_score[neighbor] = tentative_g
                f = tentative_g + haversine_m(neighbor, goal)
                heapq.heappush(open_heap, (f, neighbor))

    return [], math.inf


def _reconstruct(
    came_from: Dict[NodeId, Optional[NodeId]], end: NodeId
) -> List[NodeId]:
    path: List[NodeId] = []
    cur: Optional[NodeId] = end
    while cur is not None:
        path.append(cur)
        cur = came_from[cur]
    return list(reversed(path))
