[![Hex.pm](https://img.shields.io/hexpm/v/ex_janus.svg)](https://hex.pm/packages/ex_janus) [![Docs](https://img.shields.io/badge/hexdocs.pm-docs-8e7ce6.svg)](https://hexdocs.pm/ex_janus)

Authorization superpowers for your `Ecto` schemas.

Janus prioritizes:

* Single source of truth: authorization rules should be defined once and used for authorizing individual actions as well as composing Ecto queries.

* Minimal library footprint: expose a small set of useful functions that application authors can use to set up their own optimal authorization API.

* Minimal application footprint: "hide" Janus behind application- controlled policy modules that define the interface for the rest of the application.

* Escape hatches: easily "drop down" to your own code when the declarative API doesn't cut it.

## Documentation

If you're reading this on GitHub, head over to the [HexDocs](https://hexdocs.pm/ex_janus/Janus.html).

If you're already on HexDocs, here's where you might head next:

- `Janus` module docs
- [The Basics](basics.html) cheatsheet
- [Generated Policy Modules](generated_policy_modules.html) - ideas behind `mix janus.gen.policy`

## Installation

Janus can be installed by adding `ex_janus` to your deps in `mix.exs`:

```elixir
defp deps do
  [
    {:ex_janus, "~> 0.2.0-alpha.3"}
  ]
end
```

## Development

To set up and test `Janus` locally:

```bash
$ git clone https://github.com/zachallaun/ex_janus && cd ex_janus

$ mix deps.get

# Set up test database and run tests with code coverage report
$ mix setup
$ mix t
```
