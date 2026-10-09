# Architecture

## Capture and local browsing

`native/App.swift` owns the AppKit application lifecycle and coordinates a Python
capture subprocess. `native/PythonRuntime.swift` discovers a compatible interpreter.
`src/touchline_live.py` identifies and gates the running FM24 executable, asks
macOS to authorize `src/probe.cpp`, then captures the established player vector.

The helper exposes bounded read operations through a private temporary transport
directory. It obtains `task_read_for_pid`, drops administrator identity and
releases its task port on completion. No write/suspend/injection operation is used.

Capture reads occupied blocks in bulk, resolves deduplicated strings and known
object relationships, and rechecks the collection header/pointer array. Unknown
subtypes, malformed core records, invalid vectors or changed collections reject
the snapshot. A bounded decoded-name sample validates the string relationship
without requiring any specific player or database content. Confirmed detach
precedes serialization/publication; the previous cache survives rejected captures.

The vector count is authoritative. Capacity is not the player count. Scalar
values can change during capture, so collection consistency is not an atomic
snapshot guarantee.

## Modules

| Responsibility | Files |
| --- | --- |
| Read-only capture and collection checks | `src/probe.cpp`, `src/touchline_live.py` |
| Structured players and string/page cache | `src/live_player.py` |
| Contracts/parent clubs and monetary fields | `src/live_transfers.py` |
| Trusted game date, currencies and primary nationality | `src/live_date.py`, `src/live_currency.py`, `src/live_nationality.py` |
| Local decoding/presentation values | `native/Model.swift` |
| Shared filter drafts, local matching and stable sorting | `native/Query.swift` |
| Native profile/table presentation | `native/App.swift`, `native/Views.swift`, `native/ShortlistUI.swift` |
| Advanced scouting editor and preferences | `native/AdvancedFilters.swift`, `native/SettingsWindowController.swift` |
| Shortlist identifiers/persistence | `native/Shortlist.swift` |
| Pure projected-attribute, personality and role logic | `native/Projection.swift`, `native/Personality.swift`, `native/RoleFocus.swift` |
| Role selector presentation | `native/RoleFocusControl.swift` |
| Facepack parsing, persistent index and lazy image loading | `native/FacepackIndex.swift`, `native/FacepackCache.swift`, `native/PlayerFaces.swift` |

## Data invariants

- Field statuses distinguish verified, derived, unresolved, unavailable and inconsistent
  values. Optional invalid fields do not silently become zero or a guessed value.
- Player UID is an external person identifier. The separate entity index is not
  interchangeable with UID; face mappings use UID and shortlist identity retains
  its existing identifiers.
- Club means the owning parent club from the main employment contract.
- Money remains in raw/base units. Display conversion multiplies by the selected
  captured currency's float-derived multiplier; filtering retains base-unit semantics.
- Age derives from DOB and the verified capture-scoped game date, never the host date.
- Queries compose with AND. Unknown values do not match an active numeric constraint.
  Quick controls and the advanced editor share one filter state.
- Cached objects/keys support browsing without a process attachment. Interface
  preferences persist through `UserDefaults`; no settings action recaptures FM.

## Projection and Role Focus

Projection is Foundation-only and deterministic over cached inputs. Fixed position
priority and age/coefficient tables are immutable. Signed-byte/word behavior,
rounding, clamps, unchanged slots and the Natural Fitness special path are preserved
by golden tests; unusual numeric behavior is not smoothed into a new heuristic.
Missing trusted date/raw-attribute inputs disable projection for that player.
Projected mode replaces visible values only and does not alter CA/PA, hidden data,
traits or relationships. Source attribution is documented separately.

Role Focus marks key/preferable attribute tiers. It is a presentation overlay,
not a suitability score, and does not affect filters, current values or projections.

## Faces and persistence

The face resolver discovers configs once, builds a UID-to-relative-path index and
stores a versioned binary cache outside the facepack. Config paths/sizes/mtime and
directory timestamps determine invalidation. Images are loaded lazily for the
selected profile with a bounded recent-image cache. Existing files stay untouched.

Player snapshots retain model versions 2/3. Readers accept older optional diagnostic
metadata; new captures omit unused product/stage/reference-sample fields. The native
loader retains the legacy adjacent-cache fallback; removing that path would require
a separate storage migration. Unresolved data remains representable when older
caches lack newer optional fields. The CLI writes only `players.json` and
`summary.json` to `app-data/latest` by default; `--output` overrides that location.
