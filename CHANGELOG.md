# Changelog

## [2026-08-25] - v0.2.1

### Fixed

- `normalize_result_to_map/2` in `Orchid.Hook.ApplyInterventions` paired step
  outputs with out keys positionally (`Enum.zip(out_keys, params)`), but
  `out_keys` had already passed through MapSet normalization, destroying
  the declared order. On multi-output steps this mis-paired the inner data
  handed to merge-type interventions (override-type interventions were
  unaffected since they never read the inner data). Params are now paired
  by `Param.name` — which the core hook has already aligned with its out
  key — with the positional zip kept as a fallback for raw (non-Param)
  results.

## [2026-06-28] - v0.2.0

### Breaking

- Removed `short_circuit?/0` callback from `OrchidIntervention.Operate` behaviour.
  It is now derived automatically from `data_enable/0`: returns `true` when
  `use_inner?` is `false` (i.e. the step output is not needed for the merge).
  Custom `Operate` modules only need to implement `data_enable/0` and `merge/2`.

### Added

- `OrchidIntervention.Operate.short_circuit?/1` — public function that derives
  the short-circuit decision from a module's `data_enable/0`.

### Changed

- `Orchid.Hook.ApplyInterventions` now calls `Operate.short_circuit?/1` instead
  of invoking the callback directly.
- `OrchidIntervention.Operate.Override` no longer implements `short_circuit?/0`
  (derived from `data_enable/0 = {false, true}`, unchanged behaviour).

### Removed

- `@callback short_circuit?/0` from `OrchidIntervention.Operate`.

## v0.1.x

Initial release.
