# Changelog

## [0.3.0] - 2026-07-20

- Default `config.enabled` to development only (was development and test). The HTML panel is the only output, so running in test only added overhead and could alter response bodies under test.
- Remove per-rule `severity` (`:error` / `:warning`). It only changed the panel's label color and implied consequences (failing tests) the gem doesn't have; detections are uniformly warnings now.
- Remove `[]` access to rule settings (`config.rules[:deep_offset]`); use the method form (`config.rules.deep_offset`).

## [0.2.0] - 2026-07-18

- Remove `config.table_size_hints` / `config.size_rule_threshold`. Tier 2 rules are already opt-in per rule; use `config.ignore_tables` to exclude small tables.

## [0.1.0] - 2026-07-14

Initial release.
