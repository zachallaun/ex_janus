# Changelog

All notable changes to this project will be documented in this file.

## v0.2.0-dev

### Added

- Overhaul generated policy helpers (mix janus.gen.policy) to more easily replace `Ecto.Repo` callbacks.
- Required association loading:
  - `Janus.Authorization.authorize/4` adds `:repo` and `:load_associations` option.
  - `use Janus` accepts options to override defaults.

### Changed

- (Breaking) All instances of `filter_authorized` replaced by `scope` (no changes to functionality).
- (Breaking) When failing to authorize, return `{:error, :not_authorized}` instead of `:error`.

## v0.1.0 (2022-12-25)

This marks the first release of Janus.

### Added

- `Janus.Policy` and `Janus.Authorization` (behaviours) drive the definition and usage of authorization policies.
- Mix task for generating basic policy and helpers.
