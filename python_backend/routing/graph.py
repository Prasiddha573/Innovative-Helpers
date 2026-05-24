"""Build a weighted road graph from an OSM/Overpass JSON snapshot.

Nodes are identified by their (lat, lon) tuple - blueprint section 5 says
"Latitude and longitude are the node identifiers". Edge weights are the
Haversine distance in metres, optionally inflated (or set to infinity) by
the hazard re-evaluation pass.
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass, field
from typing import Dict, Iterable, List, Optional, Tuple

NodeId = Tuple[float, float]


def haversine_m(a: NodeId, b: NodeId) -> float:
    """Great-circle distance in metres between two (lat, lon) points."""
    lat1, lon1 = a
    lat2, lon2 = b
    r = 6_371_000.0
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlam = math.radians(lon2 - lon1)
    h = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(
        dlam / 2
    ) ** 2
    return 2 * r * math.asin(math.sqrt(h))


@dataclass
class Graph:
    """Simple adjacency-list graph keyed on (lat, lon) tuples."""

    adjacency: Dict[NodeId, Dict[NodeId, float]] = field(default_factory=dict)

    def add_edge(self, u: NodeId, v: NodeId, weight: float) -> None:
        if u == v:
            return
        self.adjacency.setdefault(u, {})[v] = weight
        self.adjacency.setdefault(v, {})[u] = weight

    @property
    def nodes(self) -> Iterable[NodeId]:
        return self.adjacency.keys()

    def nearest_node(self, point: NodeId) -> Optional[NodeId]:
        """Snap an arbitrary point to the nearest graph node."""
        best: Optional[NodeId] = None
        best_d = float("inf")
        for n in self.adjacency.keys():
            d = haversine_m(point, n)
            if d < best_d:
                best_d = d
                best = n
        return best


def graph_from_overpass(elements: List[dict]) -> Graph:
    """Construct a Graph from Overpass `out geom` road ways."""
    g = Graph()
    for el in elements:
        tags = el.get("tags") or {}
        if "highway" not in tags:
            continue
        geom = el.get("geometry") or []
        nodes = [
            (float(p["lat"]), float(p["lon"]))
            for p in geom
            if "lat" in p and "lon" in p
        ]
        for i in range(len(nodes) - 1):
            d = haversine_m(nodes[i], nodes[i + 1])
            g.add_edge(nodes[i], nodes[i + 1], d)
    return g


def load_graph_from_file(path: str) -> Graph:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    return graph_from_overpass(data.get("elements", []))
