# Changelog

All notable changes to this project will be documented in this file.

## v0.2.0 (Unreleased)

### Added

- (Janus) `use Janus` accepts optional defaults for `Janus.Authorization.authorize/4` options.
- (Janus.Authorization) `authorize/4` adds `:repo` and `:load_assocations` options.
- (mix janus.gen.policy) Overhaul generated policy helpers to more easily replace `Ecto.Repo` callbacks.

### Changed

- (Breaking / Janus.Authorization) `policy_for` renamed to `build_policy`.
- (Breaking / Janus.Authorization) `filter_authorized` renamed to `scope`.
- (Breaking / Janus.authorization) `authorize` now returns `{:error, :not_authorized}` instead of `:error`.

## v0.1.0 (2022-12-25)

This marks the first release of Janus.
