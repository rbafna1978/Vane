# ADR-0006: VaneKit / VaneUI as local SPM packages, plain .xcodeproj

**Status:** Proposed
**Date:** 2026-09-03

## Context
The app target, the widget extension, and the Live Activity extension are three separate binaries.
They need the same models, the same networking, the same cache, and — because the widget must render
in the same paper/ink/trace palette — the same design tokens.

Three modules for a solo project is normally scaffolding. Here the forcing function is real: without
packages, sharing code across extension targets means checking files into multiple target
memberships, which breaks quietly and is miserable to debug.

## Decision
Two local SPM packages in the repo, consumed by a plain `.xcodeproj`. No `.xcworkspace`.

```
VaneKit   models, networking, GRDB cache, sun-position engine   (no UI imports)
VaneUI    tokens, type scale, motion components, shaders        (depends on VaneKit)
App       WeatherMan.xcodeproj -> app + widget + LiveActivity targets
```

The dependency arrow runs one way. `VaneKit` must not import SwiftUI — that boundary is what keeps
the sun-position engine unit-testable without a host app, and it is worth enforcing in review.

## Options Considered
**One module:** simplest, but extensions then link the entire app, including everything UI. Widget
memory limits are tight (~30MB); dragging in shaders and motion machinery is a real risk.

**Three-plus modules (VaneKit / VaneUI / VaneMotion / ...):** rejected. There is no forcing function
splitting motion from tokens; they change together and are used together.

**Workspace instead of project:** the brief assumed one. Not needed — local packages attach directly
to a plain `.xcodeproj`, and a workspace adds a file to maintain for no benefit at this size.

## Consequences
- Easier: extensions link only what they need. `VaneKit` tests run without a simulator host.
- Harder: adding a file means choosing a package, which is a small tax on every addition.
- Enforced by: `VaneKit` importing SwiftUI is a review failure, not a lint rule. Cheaper to catch by
  eye than to configure.

## Naming — resolved
Renamed to `Vane` before any packages existed. Project, target, scheme, app struct, and bundle
identifier (`com.rishitbafna.vane`) all moved. The parent directory on disk is still
`Documents/WeatherMan`; that is cosmetic and does not appear in any build setting.

## Action Items
1. [ ] `Packages/VaneKit`, `Packages/VaneUI` as local SPM packages
2. [ ] Resolve the naming question before phase 3
