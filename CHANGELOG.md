# Changelog

All notable changes to this project will be documented in this file.

## v0.2.0-dev

### Changed

- All instances of `filter_authorized` replaced by `scope` (no changes to functionality).

## v0.1.0 (2022-12-25)

This marks the first release of Janus.

### Added

- `Janus.Policy` and `Janus.Authorization` (behaviours) drive the definition and usage of authorization policies.
- [mix janus.gen.policy] Mix task for generating basic policy and helpers.
