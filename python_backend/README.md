# Python Backend - Routing Engine

Flask service that powers the routing layer for the Real-Time Tactical
Disaster Simulation. It builds a road graph from the Kavrepalanchok
Overpass snapshot and exposes A* and Dijkstra shortest-path searches
with hazard-aware reweighting.

## Endpoints

| Method | Path                | Purpose |
| ------ | ------------------- | ------- |
| GET    | `/healthz`          | Probe + graph size |
| POST   | `/route`            | Primary (A*) + secondary (Dijkstra) routes between two points, with hazards applied |
| POST   | `/nearest_ambulance`| Find the closest available ambulance to a casualty along the road graph |
| POST   | `/reevaluate`       | Same payload as `/route`; called when a hazard is dropped onto the active path |
| POST   | `/refresh_overpass` | Force-fetch the live Overpass API and rebuild the in-memory graph |

### `/route` payload

```json
{
  "from":    [27.6210, 85.5439],
  "to":      [27.6320, 85.4960],
  "hazards": [
    { "type": "flood",        "lat": 27.622, "lng": 85.500 },
    { "type": "forest_fire",  "lat": 27.640, "lng": 85.530 },
    { "type": "landslide",    "lat": 27.610, "lng": 85.520 },
    { "type": "danger_zone",  "lat": 27.625, "lng": 85.555 }
  ]
}
```

### `/route` response

```json
{
  "primary":            [[27.621, 85.544], [27.632, 85.496], ...],
  "secondary":          [[27.621, 85.544], [27.601, 85.536], ...],
  "primary_cost_km":    4.872,
  "secondary_cost_km":  5.301,
  "algorithm_primary":  "astar",
  "algorithm_secondary":"dijkstra"
}
```

### `/nearest_ambulance` payload

```json
{
  "casualty":  [27.6210, 85.5439],
  "ambulances": [
    {"id": "amb-001", "lat": 27.6210, "lng": 85.5439},
    {"id": "amb-002", "lat": 27.6308, "lng": 85.5193}
  ]
}
```

## Layout

```
python_backend/
|-- app.py                      Flask app entrypoint
|-- requirements.txt
|-- routing/
|   |-- __init__.py
|   |-- graph.py                Graph dataclass + Overpass parser
|   |-- astar.py                A*: f(n) = g(n) + h(n) with Haversine h
|   |-- dijkstra.py             Standard Dijkstra
|   `-- hazard.py               Reweighting: infinity for flood/fire, x3 for landslide, x2 for danger zone
|-- services/
|   |-- __init__.py
|   |-- overpass_loader.py      Live Overpass POST + local cache
|   `-- ambulance_dispatcher.py Closest-ambulance picker
|-- data/
|   `-- kavrepalanchok.json     Bundled offline snapshot
`-- README.md                   (this file)
```

## Run locally

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python app.py
```

Default port: `5000`. Override with `PORT=8080 python app.py`.

## Hazard reweighting policy

Edge weights are recomputed in-memory by `routing/hazard.py` before each
search:

| Type           | Influence radius | Penalty       |
| -------------- | ---------------- | ------------- |
| `flood`        | 250 m            | infinity      |
| `forest_fire`  | 350 m            | infinity      |
| `landslide`    | 400 m            | x3 multiplier |
| `danger_zone`  | 300 m            | x2 multiplier |

Edges marked infinity are skipped by both A* and Dijkstra, so blocked
corridors literally disappear from the graph until the hazard is
cleared. If A* cannot reach the destination at all (every short path is
blocked), `/route` falls back to the Dijkstra result so the UI always
gets a renderable path.

## Offline mode

If the live Overpass API is unreachable, `services/overpass_loader.py`
falls back to `data/kavrepalanchok.json`, which is a hand-curated
snapshot of the major roads, hospitals, ward boundaries and forest
patches inside the Kavrepalanchok district bbox `(27.45, 85.40)` to
`(27.95, 85.95)`.
