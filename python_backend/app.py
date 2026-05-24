"""Flask backend for the Real-Time Tactical Disaster Simulation app.

Endpoints (per blueprint section 4):
  POST /route              - shortest A* primary + Dijkstra secondary
  POST /nearest_ambulance  - pick the closest available ambulance
  POST /reevaluate         - rerun A* against an updated hazard list
  GET  /healthz            - simple health probe
  POST /refresh_overpass   - rebuild the cached road graph from Overpass
"""

from __future__ import annotations

import math
import os
from typing import List, Tuple

from flask import Flask, jsonify, request
from flask_cors import CORS

from routing.astar import astar
from routing.dijkstra import dijkstra
from routing.graph import Graph, graph_from_overpass, haversine_m
from routing.hazard import apply_hazards
from services.ambulance_dispatcher import find_nearest_ambulance
from services.overpass_loader import load_with_cache

NodeId = Tuple[float, float]

app = Flask(__name__)
CORS(app)


# ---------------------------------------------------------------------------
# Graph bootstrap
# ---------------------------------------------------------------------------
_graph: Graph | None = None


def get_graph() -> Graph:
    """Lazy-load the road graph. Tries the live Overpass first, then the
    bundled snapshot under data/kavrepalanchok.json."""
    global _graph
    if _graph is None:
        try:
            data = load_with_cache(force_refresh=False)
        except Exception as exc:  # pylint: disable=broad-except
            app.logger.warning("Overpass load failed: %s", exc)
            data = {"elements": []}
        _graph = graph_from_overpass(data.get("elements", []))
        app.logger.info(
            "Graph built with %s nodes / %s edges.",
            len(_graph.adjacency),
            sum(len(v) for v in _graph.adjacency.values()) // 2,
        )
    return _graph


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def _parse_point(raw, key: str) -> NodeId:
    try:
        lat, lng = raw
        return float(lat), float(lng)
    except (TypeError, ValueError):
        raise ValueError(f"`{key}` must be [lat, lng]") from None


def _path_to_payload(path: List[NodeId]) -> List[List[float]]:
    return [[p[0], p[1]] for p in path]


def _cost_km(cost_m: float) -> float:
    return round(cost_m / 1000.0, 3)


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------
@app.get("/healthz")
def healthz():
    g = get_graph()
    return jsonify(
        {
            "status": "ok",
            "nodes": len(g.adjacency),
            "edges": sum(len(v) for v in g.adjacency.values()) // 2,
        }
    )


@app.post("/refresh_overpass")
def refresh_overpass():
    global _graph
    try:
        data = load_with_cache(force_refresh=True)
        _graph = graph_from_overpass(data.get("elements", []))
        return jsonify({"status": "ok", "nodes": len(_graph.adjacency)})
    except Exception as exc:  # pylint: disable=broad-except
        return jsonify({"status": "error", "message": str(exc)}), 500


@app.post("/route")
def route():
    body = request.get_json(force=True, silent=True) or {}
    try:
        src = _parse_point(body.get("from"), "from")
        dst = _parse_point(body.get("to"), "to")
    except ValueError as exc:
        return jsonify({"error": str(exc)}), 400

    hazards = body.get("hazards") or []
    graph = get_graph()
    if not graph.adjacency:
        # No road graph available - return a degenerate straight line so the
        # client can still render something.
        d = haversine_m(src, dst)
        return jsonify(
            {
                "primary": [list(src), list(dst)],
                "secondary": [list(src), list(dst)],
                "primary_cost_km": _cost_km(d),
                "secondary_cost_km": _cost_km(d),
                "algorithm_primary": "haversine_fallback",
                "algorithm_secondary": "haversine_fallback",
            }
        )

    adjusted = apply_hazards(graph, hazards)
    s_node = adjusted.nearest_node(src)
    d_node = adjusted.nearest_node(dst)
    if s_node is None or d_node is None:
        return jsonify({"error": "graph empty"}), 500

    primary_path, primary_cost = astar(adjusted, s_node, d_node)
    secondary_path, secondary_cost = dijkstra(adjusted, s_node, d_node)

    # Fallback to Dijkstra if A* could not find anything (e.g. all edges
    # along the heuristic-preferred direction are flooded).
    if not primary_path:
        primary_path = secondary_path
        primary_cost = secondary_cost

    return jsonify(
        {
            "primary": _path_to_payload(primary_path),
            "secondary": _path_to_payload(secondary_path),
            "primary_cost_km": _cost_km(primary_cost),
            "secondary_cost_km": _cost_km(secondary_cost),
            "algorithm_primary": "astar",
            "algorithm_secondary": "dijkstra",
        }
    )


@app.post("/nearest_ambulance")
def nearest_ambulance():
    body = request.get_json(force=True, silent=True) or {}
    try:
        casualty = _parse_point(body.get("casualty"), "casualty")
    except ValueError as exc:
        return jsonify({"error": str(exc)}), 400
    ambulances = body.get("ambulances") or []
    graph = get_graph()
    best = find_nearest_ambulance(graph, casualty, ambulances)
    if not best:
        return jsonify({"ambulance_id": None}), 404
    return jsonify(
        {
            "ambulance_id": best.get("id"),
            "lat": best.get("lat"),
            "lng": best.get("lng"),
        }
    )


@app.post("/reevaluate")
def reevaluate():
    """Rerun the search when a hazard appears on the active path."""
    return route()


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "5000"))
    app.run(host="0.0.0.0", port=port, debug=True)
