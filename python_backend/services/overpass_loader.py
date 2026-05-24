"""Load Overpass data restricted to the Kavrepalanchok district.

If the live Overpass endpoint is unreachable, fall back to the bundled
JSON snapshot under `data/kavrepalanchok.json`.
"""

from __future__ import annotations

import json
import os
import time
from typing import Optional

import requests

OVERPASS_URL = "https://overpass-api.de/api/interpreter"

# District bbox (south, west, north, east)
BBOX = (27.45, 85.40, 27.95, 85.95)

# Overpass query - roads, hospitals, ward boundaries, forests
QUERY = """
[out:json][timeout:25];
(
  way["highway"]({s},{w},{n},{e});
  node["amenity"="hospital"]({s},{w},{n},{e});
  way["amenity"="hospital"]({s},{w},{n},{e});
  relation["boundary"="administrative"]["admin_level"~"8|9"]({s},{w},{n},{e});
  way["landuse"="forest"]({s},{w},{n},{e});
  way["natural"="wood"]({s},{w},{n},{e});
);
out body geom;
""".strip()

DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data")
SNAPSHOT_PATH = os.path.normpath(os.path.join(DATA_DIR, "kavrepalanchok.json"))


def _format_query() -> str:
    s, w, n, e = BBOX
    return QUERY.format(s=s, w=w, n=n, e=e)


def fetch_overpass(timeout: int = 30) -> dict:
    """Query the live Overpass API once.

    Raises requests.RequestException on network/HTTP errors.
    """
    response = requests.post(
        OVERPASS_URL,
        data={"data": _format_query()},
        timeout=timeout,
    )
    response.raise_for_status()
    return response.json()


def load_with_cache(force_refresh: bool = False) -> dict:
    """Return an Overpass JSON document, preferring the bundled snapshot."""
    if not force_refresh and os.path.exists(SNAPSHOT_PATH):
        try:
            with open(SNAPSHOT_PATH, "r", encoding="utf-8") as f:
                return json.load(f)
        except (OSError, json.JSONDecodeError):
            pass

    data = fetch_overpass()
    try:
        os.makedirs(DATA_DIR, exist_ok=True)
        with open(SNAPSHOT_PATH, "w", encoding="utf-8") as f:
            json.dump(data, f)
    except OSError:
        pass
    return data
