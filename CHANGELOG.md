# Changelog

All notable changes to this project will be documented in this file.

## v0.2.0-dev

### Added

- `Janus.Authorization.validate_authorized/4` to expose authorization failure as validation errors on an Ecto changeset.

### Changed

- (Breaking) All instances of `filter_authorized` replaced by `scope` (no changes to functionality).
- (Breaking) When failing to authorize, return `{:error, :not_authorized}` instead of `:error`.

## v0.1.0 (2022-12-25)

This marks the first release of Janus.

### Added

- `Janus.Policy` and `Janus.Authorization` (behaviours) drive the definition and usage of authorization policies.
- [mix janus.gen.policy] Mix task for generating basic policy and helpers.
