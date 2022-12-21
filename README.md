# Janus

Flexible and composable authorization for `Ecto.Schema`s.

Janus provides an API for defining authorization policies that can be used both as
filters in Ecto queries and to authorize actions on loaded resources with minimal to no
duplication of authorization logic.

[**Documentation**](https://hexdocs.pm/janus)

## Installation

Janus is pre-0.1 and can be installed by adding `janus` as a git dependency in `mix.exs`:

```elixir
def deps do
  [
    {:janus, github: "zachallaun/janus"}
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
