# Changelog

## v0.2.0 (Unreleased)

### Enhancements

  * [Janus] `use Janus` accepts optional defaults for `Janus.Authorization.authorize/4` options
  * [Janus.Policy] **Breaking:** `policy_for` renamed to `build_policy`
  * [Janus.Authorization] **Breaking:** `filter_authorized` renamed to `scope`
  * [Janus.Authorization] **Breaking:** `authorize` now returns `{:error, :not_authorized}` instead of `:error`
  * [Janus.Authorization] `authorize/4` adds `:repo` and `:load_assocations` options
  * [mix janus.gen.policy] Overhaul generated policy helpers to more easily replace `Ecto.Repo` callbacks

## v0.1.0 (2022-12-25)

First release.
