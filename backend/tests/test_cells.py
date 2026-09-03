"""Cell snapping. Everything downstream — cache keys, backfill jobs, normals — is keyed on the
output of this function, so a bug here fragments the cache and multiplies the backfill cost.
"""

import math

import pytest

from vane.cells import GRID, Cell, InvalidCoordinate, cell_for


def test_nearby_coordinates_share_a_cell():
    # The economic claim behind on-demand backfill: everyone in ~25km pays for one backfill.
    ids = {cell_for(lat, lon).id for lat, lon in
           [(37.8044, -122.2712), (37.79, -122.30), (37.70, -122.19), (37.6876, -122.3708)]}
    assert ids == {"37.75,-122.25"}


def test_distant_coordinates_do_not_share_a_cell():
    assert cell_for(37.8044, -122.2712).id != cell_for(40.7128, -74.0060).id


@pytest.mark.parametrize(
    ("lat", "lon", "expected"),
    [
        (0.0, 0.0, "0.00,0.00"),
        (37.8044, -122.2712, "37.75,-122.25"),
        (-33.8688, 151.2093, "-33.75,151.25"),
        (51.5072, -0.1276, "51.50,-0.25"),  # nearer -0.25 than 0.00, by 0.005
    ],
)
def test_known_snaps(lat, lon, expected):
    assert cell_for(lat, lon).id == expected


def test_snapped_values_land_on_the_grid():
    for lat, lon in [(37.8044, -122.2712), (-33.8688, 151.2093), (12.3456, 78.9012)]:
        cell = cell_for(lat, lon)
        assert math.isclose(cell.lat % GRID, 0.0, abs_tol=1e-9)
        assert math.isclose(cell.lon % GRID, 0.0, abs_tol=1e-9)


def test_antimeridian_collapses_to_one_cell():
    # +180 and -180 are the same meridian. Two cells there would mean two identical backfills.
    assert cell_for(0.0, 180.0).id == cell_for(0.0, -180.0).id
    assert cell_for(0.0, 179.99).lon == -180.0


def test_no_negative_zero_in_cell_ids():
    # "-0.00" and "0.00" would be two cache keys and two backfills for one cell. math.floor
    # returns an int, so int * GRID cannot produce -0.0 — this pins that property down.
    for lat, lon in [(-0.05, -0.05), (-0.1, -0.1), (0.0, -0.0), (-0.12, 0.12)]:
        assert "-0.00" not in cell_for(lat, lon).id


def test_poles_do_not_overflow():
    assert cell_for(90.0, 0.0).lat == 90.0
    assert cell_for(-90.0, 0.0).lat == -90.0


def test_midpoint_rounds_consistently():
    # Python's round() is banker's rounding; _snap uses floor(x+0.5) so midpoints always go up.
    assert cell_for(0.125, 0.375).id == cell_for(0.125, 0.375).id
    assert cell_for(0.125, 0.0).lat == 0.25
    assert cell_for(0.375, 0.0).lat == 0.50


@pytest.mark.parametrize(
    ("lat", "lon"),
    [(91.0, 0.0), (-91.0, 0.0), (0.0, 181.0), (0.0, -181.0),
     (float("nan"), 0.0), (0.0, float("inf"))],
)
def test_rejects_impossible_coordinates(lat, lon):
    with pytest.raises(InvalidCoordinate):
        cell_for(lat, lon)


def test_cell_is_hashable_and_frozen():
    # Cells are used as dict keys and in sets; mutability here would be a silent cache bug.
    assert len({Cell(1.0, 2.0), Cell(1.0, 2.0)}) == 1
    with pytest.raises(AttributeError):
        Cell(1.0, 2.0).lat = 3.0  # type: ignore[misc]
