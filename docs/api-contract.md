# Vane API v1 — contract

Refined from the brief's sketch. Three changes are argued below rather than assumed.

## Identity: devices, not users

**Dropped the `users` table.** Nothing in the product needs an account. There is no sign-in, no
password, no email, nothing to recover. A device registers once, receives an opaque token, and that
token scopes its locations, archive, and push registration.

Why this matters beyond simplicity: no accounts means no password reset flow, no email deliverability
problem, no account-deletion endpoint to build for App Store compliance beyond deleting one device
row, and a materially smaller privacy nutrition label. If cross-device archive sync becomes a
requirement, the migration is to add an optional Sign in with Apple identity that *adopts* existing
device rows — additive, not a rewrite.

```
POST /v1/devices
  body   { apns_token?, tz, locale }
  200    { device_id, token }          # token is bearer for everything below
```

All authenticated routes take `Authorization: Bearer <token>`.

## Requests are collapsed into one per app open

The sketch has the main screen calling `/conditions`, `/forecast`, and `/context` — three round trips
on a cold cellular launch, for one screen. Merged:

```
GET /v1/snapshot?lat={f}&lon={f}
  200  {
    cell_id,                        # 0.25° cell, snapped server-side
    observed_at,
    utc_offset_seconds,             # the location's own offset — sunrise must render in the
                                    # time of the place, not the phone. Sent rather than
                                    # inferred, because inference breaks on DST days.
    current:  { temp_c, feels_c, wind_kt, wind_deg, humidity, pressure_hpa, code },
    arc:      [ { t, temp_c, precip_mm, code } ],     # today, hourly, local midnight to midnight
    normal:   { tmax_c, tmin_c, years } | null,       # the dashed band behind the trace
    context:  Context | null,
    context_state: "warm" | "warming",
    alerts:   [ Alert ],
    sun:      { sunrise, sunset, civil_dawn, civil_dusk, solar_noon, elevation_deg, azimuth_deg }
  }
```

`normal` and `sun` exist because the design needs them, not because the data is interesting.

`normal` is a **band**, not a series: the average high and low for this calendar date. We hold
daily history, so an hourly normal would have to be invented from a diurnal shape, and a
fabricated curve behind a real trace is the quiet dishonesty this app is built against. `sun` drives the `wash` token — the
client computes color state from it locally so the palette keeps advancing while offline.

`context_state` is `cold` | `warming` | `warm`. `cold` means no history and nothing queued;
`warming` means backfill is running; `warm` means history is present, though `context` may still
be null when nothing true about today is interesting. All three render identically — everything
except the context line — so the absence of a sentence is never read as an error.

## Remaining routes

```
GET  /v1/forecast?lat&lon&days={1..16}      extended view, hourly + daily
GET  /v1/context?lat&lon                    separately addressable for the push worker
GET  /v1/almanac?lat&lon&date=YYYY-MM-DD    this date across every recorded year (the plate detail)

GET  /v1/locations                          saved places
POST /v1/locations                          { lat, lon, label }
DELETE /v1/locations/{id}

GET  /v1/archive?before={cursor}&limit=     the personal timeline, reverse chronological, cursor-paged
POST /v1/archive/open                       records a day-open; returns updated streak

PATCH /v1/devices/me                        { apns_token?, morning_push_at?, tz? }
DELETE /v1/devices/me                       deletes the device and everything scoped to it

GET  /healthz                               liveness, no auth
GET  /metrics                               Prometheus text, no auth, not publicly routed
```

## Context payload

The differentiator. Server returns structured facts *and* the rendered sentence, so copy can be
revised without shipping an app update, while the client keeps enough structure to lay it out.

```
Context {
  headline: str,              # "Warmest September 3rd in eleven years."
  kind: "percentile" | "streak" | "since" | "threshold" | "seasonal_edge",
  facts: {...},               # kind-specific, typed per variant
  confidence: "high" | "low"  # low when the cell has < 10 years of usable record
}
```

`confidence: "low"` exists because ERA5 coverage is not uniform and a superlative drawn from four
years of record is a lie with a number in it. The client renders low-confidence context differently
or not at all — `design:ux-copy` decides which.

## Caching and offline reconciliation

Every GET returns `ETag` and honors `If-None-Match`, returning `304` with no body. This is what makes
"opens instantly with cached state and reconciles" cheap: the client renders from GRDB immediately,
fires the request with its stored ETag, and usually gets a 304 costing one small round trip.

Redis TTLs matched to source cadence, not guessed:

| Key | TTL | Why |
|---|---|---|
| `snapshot:{cell}` | 10 min | Open-Meteo current refreshes ~15 min; 10 keeps us just ahead |
| `forecast:{cell}:{days}` | 1 hour | Model runs are hourly at best |
| `context:{cell}:{date}` | until local midnight | Recomputing mid-day would change the headline under the user |
| `alerts:{cell}` | 2 min | Alerts are the one thing where stale is dangerous |
| `almanac:{cell}:{date}` | 24 h | Historical data does not change |

`normals:{cell}` is not cached — it lives in Postgres and is immutable once warm.

## Errors

```
{ "error": { "code": "cell_unavailable", "message": "...", "retry_after": 30 } }
```

`message` is not shown to users. The client maps `code` to copy that went through `design:ux-copy`;
server strings leaking into the interface is how apps end up saying "upstream timeout" to someone
who wants to know if it will rain.

## Tables

`devices`, `locations`, `cells`, `observations`, `daily_normals`, `forecast_cache`, `day_opens`,
`archive_entries`.

Changed from the brief: `users` dropped (see above). `cells` added — it holds warm/cold status per
grid cell, which ADR-0004 needs and which nothing else owns.

**Built so far:** `cells`, `observations`, `daily_normals`. Tables arrive with the code that uses
them. `devices`, `locations`, `day_opens` and `archive_entries` land with the push loop and the
archive.

`forecast_cache` was specified as a durable second tier behind Redis and has **not** been built —
the stampede it guards against has not been observed. Listed in `TECH-DEBT.md` rather than left
in this document as a table that exists only on paper.
