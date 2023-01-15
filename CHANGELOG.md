# Changelog

This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v0.3.0 (Unreleased)

### Enhancements

  * [Janus.Policy / **Breaking**] `build_policy/2` replaced with `build_policy/1`, with the actor added as a field to `%Janus.Policy{}` instead of being passed as a second argument

    ```elixir
    # old
    def build_policy(%Janus.Policy{} = policy, actor) do
      # ...
    end

    # new
    def build_policy(%Janus.Policy{actor: actor} = policy) do
      # ...
    end
    ```

  * [Janus.Policy / **Breaking**] Change schema/action argument order in `allow/4` and `deny/4` to be more consistent with the rest of Janus

    ```elixir
    # old
    allow(policy, :action, Schema, where: [...])

    # new
    allow(policy, Schema, :action, where: [...])
    ```

## v0.2.1 (2023-01-14)

### Enhancements

  * [Janus.Policy] Raise if something other than a schema is passed to `allow/4` or `deny/4`

## v0.2.0 (2023-01-05)

### Enhancements

  * [Janus] `use Janus` accepts optional defaults for `Janus.Authorization.authorize/4` options
  * [Janus.Policy / **Breaking**] `policy_for` renamed to `build_policy`
  * [Janus.Policy / **Breaking**] `before_policy_for` removed
  * [Janus.Policy] Pre-authorization hooks with `Janus.Policy.attach_hook/4` and friends
  * [Janus.Authorization / **Breaking**] `filter_authorized` renamed to `scope`
  * [Janus.Authorization / **Breaking**] `authorize` now returns `{:error, :not_authorized}` instead of `:error`
  * [Janus.Authorization] `authorize/4` adds `:repo` and `:load_assocations` options
  * [mix janus.gen.policy] Overhaul generated policy helpers to more easily replace `Ecto.Repo` callbacks

## v0.1.0 (2022-12-25)

First release.
