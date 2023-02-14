[![Hex.pm](https://img.shields.io/hexpm/v/ex_janus.svg)](https://hex.pm/packages/ex_janus) [![Docs](https://img.shields.io/badge/hexdocs.pm-docs-8e7ce6.svg)](https://hexdocs.pm/ex_janus)

Authorization superpowers for applications using `Ecto`.

## Installation

Janus can be installed by adding `ex_janus` to your deps in `mix.exs`:

```elixir
defp deps do
  [
    {:ex_janus, "~> 0.3.2"}
  ]
end
```

## Documentation

Here are a few places to get started:

- [`Janus` module docs](https://hexdocs.pm/ex_janus/Janus.html)
- [The Basics](https://hexdocs.pm/ex_janus/basics.html) cheatsheet
- [Generated Policy Modules](https://hexdocs.pm/ex_janus/generated_policy_modules.html) - ideas behind `mix janus.gen.policy`

## Development

To set up and test `Janus` locally:

```bash
$ git clone https://github.com/zachallaun/ex_janus && cd ex_janus

$ mix deps.get

# Set up test database and run tests with code coverage report
$ mix setup
$ mix t
```
