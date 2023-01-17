# Changelog

This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Enhancements

  * [Janus.Policy] Add rulesets: `Janus.Policy.attach/2`, `Janus.Policy.allow/3`, `Janus.Policy.deny/3`.
  * [mix janus.gen.policy] Simplify generated module and function docs.

### Fixes

  * [Janus.Policy] Fix validation that was incorrectly raising when rules were defined for a schema module whose code hadn't yet been loaded.

## v0.3.0 (2023-01-16)

### Enhancements

  * [**Breaking** / Janus.Policy] Remove `:module` field from `%Janus.Policy{}` struct.
  * [**Breaking** / Janus.Policy] Change schema/action argument order in `allow/4` and `deny/4` to be more consistent with the rest of Janus. See example below.
  * [Janus.Policy] Add `c:Janus.Policy.build_policy/1` callback primarily to document its usage; an implementation was already injected into policy modules.
  * [Janus.Policy] Add `:actor` field to `%Janus.Policy{}` struct.

#### Example `allow/4` and `deny/4`

```elixir
# Old argument order
policy
|> allow(:read, Thread, where: [...])
|> allow(:create, Thread, where: [...])
|> deny(:create, Thread, where: [...])

# New argument order
policy
|> allow(Thread, :read, where: [...])
|> allow(Thread, :create, where: [...])
|> deny(Thread, :create, where: [...])
```

## v0.2.1 (2023-01-14)

### Enhancements

  * [Janus.Policy] Raise if something other than a schema is passed to `allow/4` or `deny/4`.

## v0.2.0 (2023-01-05)

### Enhancements

  * [**Breaking** / Janus.Policy] `policy_for` renamed to `build_policy`.
  * [**Breaking** / Janus.Policy] `before_policy_for` removed.
  * [**Breaking** / Janus.Authorization] `filter_authorized` renamed to `scope`.
  * [**Breaking** / Janus.Authorization] `authorize` now returns `{:error, :not_authorized}` instead of `:error`.
  * [Janus] `use Janus` accepts optional defaults for `Janus.Authorization.authorize/4` options.
  * [Janus.Policy] Pre-authorization hooks with `Janus.Policy.attach_hook/4` and friends.
  * [Janus.Authorization] `authorize/4` adds `:repo` and `:load_assocations` options.
  * [mix janus.gen.policy] Overhaul generated policy helpers to more easily replace `Ecto.Repo` callbacks.

## v0.1.0 (2022-12-25)

First release.
