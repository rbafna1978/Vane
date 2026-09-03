# ADR-0003: Two narrow provider protocols, not one wide one

**Status:** Proposed
**Date:** 2026-09-03

## Context
Open-Meteo is primary: no API key, ERA5 historical archive, generous limits, and it covers current,
forecast, and history. NWS covers US alerts and nothing else we need. The brief asks for an
abstraction so sources are swappable.

An interface with one implementation is usually a smell. Here there are genuinely two sources from
day one — but they are not the same shape, and forcing them into one interface would mean an
`alerts()` method that Open-Meteo answers with an empty list and a `forecast()` method that NWS
raises on.

## Decision
Two protocols, each with only the methods actually called.

```python
class WeatherSource(Protocol):
    async def current(self, cell: Cell) -> Observation: ...
    async def forecast(self, cell: Cell, days: int) -> Forecast: ...
    async def archive(self, cell: Cell, start: date, end: date) -> list[Observation]: ...

class AlertSource(Protocol):
    async def alerts(self, cell: Cell) -> list[Alert]: ...
```

`OpenMeteoSource` implements the first. `NWSAlertSource` implements the second. Pydantic v2 models
at the boundary are the contract; provider-specific response shapes never escape the adapter.

## Options Considered
**One `WeatherProvider` with every method:** simpler to name, but produces two classes that each
raise or no-op on half their surface. That is not an abstraction, it is a union type wearing a
protocol.

**No abstraction, call Open-Meteo directly:** shortest diff today. Rejected because tests would then
require either network access or HTTP-level mocking on every context-engine test, and the context
engine is the part we most need to test in isolation. The protocol buys a fake, and the fake buys
the test suite.

## Consequences
- Easier: context-engine tests inject a fake source with known values. No network in unit tests.
- Harder: two names to hold instead of one.
- Revisit if a third source arrives that spans both shapes.

## Action Items
1. [ ] Protocols in `vane/sources/base.py`, adapters in siblings
2. [ ] `FakeSource` in the test package, built from fixtures, not from recorded HTTP
