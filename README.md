[![Hex.pm](https://img.shields.io/hexpm/v/ex_janus.svg)](https://hex.pm/packages/ex_janus) [![Docs](https://img.shields.io/badge/hexdocs.pm-docs-8e7ce6.svg)](https://hexdocs.pm/ex_janus)

Authorization superpowers for applications using `Ecto`.

Priorities:

  * Single source of truth - The same rules that authorize loaded data should be able to load authorized data.

  * Authentication-agnostic - Janus should not care about how users are modeled or authenticated.

  * Minimal library footprint - Expose a small but flexible API that can be used to create an optimal authorization interface for each application.

  * Escape hatches where necessary - Complex authorization rules and use-cases should be representable when Janus neglects to provide a short cut.

## Installation

Janus can be installed by adding `ex_janus` to your deps in `mix.exs`:

```elixir
defp deps do
  [
    {:ex_janus, "~> 0.2.0-alpha.3"}
  ]
end
```

## Why (not) Janus?

Janus was created to scratch an itch: the same rules that authorize loaded data should be able to load authorized data.
In concrete terms, a rule that defines whether a user can edit a resource should also be able to load all the resources that user can edit.

Loading data this way should be:

  1. efficient - loading everything and then filtering it in-memory doesn't cut it;

  2. composable - it should be possible to add additional conditions when loading data;

  3. ergonomic - authorization should slot-in naturally without major rewrites.

Thankfully, integration with `Ecto.Query` solves for all of the above.
One only needs authorization rules that can be translated into a query.

And thus, Janus was born.

### Janus may be a good fit if...

  * you're authorizing data backed by `Ecto.Schema`. Janus relies on the reflection capabilities of schemas to produce correct queries, cast values, navigate associations, etc.

  * you share interfaces between users with different permissions. Janus allows you to scope queries in a uniform way using the current user (or lack of one), making shared interfaces a natural default.

  * you prefer to have the final say. Janus takes an approach similar to Phoenix, generating code that supports certain conventions while allowing you to override or redefine behavior to fit your preferences.

  * you prefer a functional API for defining rules. Authorization policies are data; adding an authorization rule just transforms that data. Policies can be built using the full extent and natural composability of the Elixir language.

### Janus may not be a good fit if...

  * you're only authorizing actions that don't have an obvious association to data backed by `Ecto.Schema`. For instance, a `:send_welcome_email` action without some kind of `Email` schema. Janus does, however, give you a natural place to define that sort of API yourself (your policy module).

  * you want an easy-to-read DSL for authorization rules. Janus policies are "just code", so readability will depend on your own style and structure. If you value readability/scannability very highly, definitely check out [`LetMe`](https://hexdocs.pm/let_me), which provides a great DSL and makes some different trade-offs than Janus does.

  * you want runtime introspection for your authorization rules, like a list of all actions a user can perform. Janus does not currently provide structured access to this information, but you might again turn to [`LetMe`](https://hexdocs.pm/let_me), which provides introspection capabilities.

## Documentation

If you're reading this on GitHub, head over to the [HexDocs](https://hexdocs.pm/ex_janus/Janus.html).

If you're already on HexDocs, here's where you might head next:

- `Janus` module docs
- [The Basics](basics.html) cheatsheet
- [Generated Policy Modules](generated_policy_modules.html) - ideas behind `mix janus.gen.policy`

## Development

To set up and test `Janus` locally:

```bash
$ git clone https://github.com/zachallaun/ex_janus && cd ex_janus

$ mix deps.get

# Set up test database and run tests with code coverage report
$ mix setup
$ mix t
```
