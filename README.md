# Janus

Flexible and composable authorization for resources defined by an `Ecto.Schema`.

Janus provides an API for defining authorization policies that can be used both as
filters in Ecto queries and to authorize actions on loaded resources with minimal to no
duplication of authorization logic.

[**Documentation**](https://hexdocs.pm/ex_janus/Janus.html)

## Installation

Janus is pre-0.1 and can be installed by adding `ex_janus` as a git dependency in `mix.exs`:

```elixir
def deps do
  [
    {:ex_janus, github: "zachallaun/ex_janus"}
  ]
end
```

## Development

Steps to set up `Janus` locally:

```bash
$ git clone https://github.com/zachallaun/janus && cd janus
$ mix deps.get
$ mix ecto.setup
$ mix test
```
