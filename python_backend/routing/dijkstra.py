"""Dijkstra's algorithm - blueprint section 5 calls this out as the
secondary / validation / fallback route planner."""

from __future__ import annotations

import heapq
import math
from typing import Dict, List, Optional, Tuple

from .graph import Graph, NodeId


def dijkstra(
    graph: Graph,
    start: NodeId,
    goal: NodeId,
) -> Tuple[List[NodeId], float]:
    if start == goal:
        return [start], 0.0

    open_heap: List[Tuple[float, NodeId]] = []
    heapq.heappush(open_heap, (0.0, start))
    came_from: Dict[NodeId, Optional[NodeId]] = {start: None}
    g_score: Dict[NodeId, float] = {start: 0.0}
    closed: Dict[NodeId, bool] = {}

    while open_heap:
        cur_cost, current = heapq.heappop(open_heap)
        if closed.get(current):
            continue
        closed[current] = True
        if current == goal:
            return _reconstruct(came_from, current), g_score[current]

        for neighbor, weight in graph.adjacency.get(current, {}).items():
            if math.isinf(weight):
                continue
            tentative = g_score[current] + weight
            if tentative < g_score.get(neighbor, math.inf):
                g_score[neighbor] = tentative
                came_from[neighbor] = current
                heapq.heappush(open_heap, (tentative, neighbor))

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
